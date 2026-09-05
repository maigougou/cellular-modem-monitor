import Foundation
import Network
import Darwin

/// Route metadata passed to an injectable HTTP transport.
///
/// `URLSessionZTEHTTPTransport` deliberately leaves route selection to macOS.
/// A discovery implementation that needs strict path isolation can inject a
/// transport backed by Network.framework or `IP_BOUND_IF` and use this context.
struct ZTEHTTPRoute: Hashable, Sendable {
    var interfaceName: String?
    var interfaceIndex: UInt32?
    var sourceAddress: String?

    static let systemDefault = ZTEHTTPRoute(
        interfaceName: nil,
        interfaceIndex: nil,
        sourceAddress: nil
    )
}

struct ZTEHTTPResponse: Equatable, Sendable {
    var statusCode: Int
    var headers: [String: String]
    var body: Data
}

protocol ZTEHTTPTransport: Sendable {
    func send(_ request: URLRequest, route: ZTEHTTPRoute) async throws -> ZTEHTTPResponse
}

struct ZTEAvailableInterface<Value: Sendable>: Sendable {
    let name: String
    let index: UInt32
    let value: Value

    func matches(_ route: ZTEHTTPRoute) -> Bool {
        (route.interfaceName.map { $0 == name } ?? true) &&
            (route.interfaceIndex.map { $0 == index } ?? true)
    }
}

/// A single live interface snapshot, not a time-based route cache. A new path
/// event replaces the whole list, including removals. All mutable state is
/// protected by the lock; continuations are always resumed outside it.
final class ZTEInterfaceDirectory<Value: Sendable>: @unchecked Sendable {
    private struct Waiter {
        let route: ZTEHTTPRoute
        let continuation: CheckedContinuation<Value, Error>
        let deadline: DispatchWorkItem
    }
    private let lock = NSLock()
    private var interfaces: [ZTEAvailableInterface<Value>]?
    private var waiters: [UUID: Waiter] = [:]

    func update(_ next: [ZTEAvailableInterface<Value>]) {
        lock.lock()
        interfaces = next
        let pending = Array(waiters.values)
        waiters.removeAll()
        lock.unlock()
        for waiter in pending {
            waiter.deadline.cancel()
            waiter.continuation.resume(with: Self.match(waiter.route, in: next))
        }
    }

    func resolve(_ route: ZTEHTTPRoute, timeout: TimeInterval) async throws -> Value {
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if Task.isCancelled {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                } else if let interfaces {
                    let result = Self.match(route, in: interfaces)
                    lock.unlock()
                    continuation.resume(with: result)
                } else {
                    let deadline = DispatchWorkItem { [weak self] in
                        self?.finish(id, error: ZTEUBusError.interfaceUnavailable)
                    }
                    waiters[id] = Waiter(route: route, continuation: continuation, deadline: deadline)
                    lock.unlock()
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + max(0, timeout), execute: deadline)
                }
            }
        } onCancel: {
            self.finish(id, error: CancellationError())
        }
    }

    private func finish(_ id: UUID, error: Error) {
        lock.lock()
        let waiter = waiters.removeValue(forKey: id)
        lock.unlock()
        waiter?.deadline.cancel()
        waiter?.continuation.resume(throwing: error)
    }

    private static func match(_ route: ZTEHTTPRoute, in interfaces: [ZTEAvailableInterface<Value>]) -> Result<Value, Error> {
        guard route.interfaceName != nil || route.interfaceIndex != nil,
              let match = interfaces.first(where: { $0.matches(route) })
        else { return .failure(ZTEUBusError.interfaceUnavailable) }
        return .success(match.value)
    }
}

private final class ZTELiveInterfaceResolver: @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let directory = ZTEInterfaceDirectory<NWInterface>()
    private let queue = DispatchQueue(label: "CellularModemMonitor.ZTEInterfaces", qos: .utility)
    private let lock = NSLock()
    private var started = false

    init() {
        let directory = directory
        monitor.pathUpdateHandler = { path in
            directory.update(path.availableInterfaces.map {
                ZTEAvailableInterface(name: $0.name, index: UInt32($0.index), value: $0)
            })
        }
    }

    deinit { monitor.cancel() }

    private func startIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        guard !started else { return }
        started = true
        monitor.start(queue: queue)
    }

    func resolve(_ route: ZTEHTTPRoute, timeout: TimeInterval) async throws -> NWInterface? {
        guard route.interfaceName != nil || route.interfaceIndex != nil else { return nil }
        startIfNeeded()
        let interface = try await directory.resolve(route, timeout: timeout)
        // Reject a removed/replaced interface even before its path event arrives.
        guard if_nametoindex(interface.name) == UInt32(interface.index) else {
            throw ZTEUBusError.interfaceUnavailable
        }
        return interface
    }
}

final class URLSessionZTEHTTPTransport: ZTEHTTPTransport, @unchecked Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func send(_ request: URLRequest, route: ZTEHTTPRoute) async throws -> ZTEHTTPResponse {
        // URLSession has no supported public API for binding one request to a
        // BSD interface. The route is still part of the injectable contract so
        // the discovery layer can substitute a scoped implementation.
        _ = route
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ZTEUBusError.nonHTTPResponse
        }

        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            headers[String(describing: key)] = String(describing: value)
        }
        return ZTEHTTPResponse(statusCode: http.statusCode, headers: headers, body: data)
    }
}

/// HTTP/1.1 transport that can pin a request to the exact interface discovered
/// for the modem. This prevents simultaneous direct and routed paths from racing
/// through macOS service-order routing.
final class NetworkBoundZTEHTTPTransport: ZTEHTTPTransport, @unchecked Sendable {
    fileprivate static let maximumResponseBytes = 4 * 1024 * 1024
    private let queue = DispatchQueue(label: "CellularModemMonitor.ZTEHTTP")
    private let timeout: TimeInterval
    private let interfaceResolver = ZTELiveInterfaceResolver()

    init(timeout: TimeInterval = 15) {
        self.timeout = timeout
    }

    func send(_ request: URLRequest, route: ZTEHTTPRoute) async throws -> ZTEHTTPResponse {
        guard let url = request.url,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let hostname = url.host
        else { throw ZTEUBusError.invalidEndpoint }
        let portNumber = url.port ?? (scheme == "https" ? 443 : 80)
        guard
              let rawPort = UInt16(exactly: portNumber),
              let port = NWEndpoint.Port(rawValue: rawPort)
        else { throw ZTEUBusError.invalidEndpoint }

        let requiredInterface = try await resolveInterface(for: route)
        let parameters: NWParameters
        if scheme == "https" {
            parameters = NWParameters(
                tls: NWProtocolTLS.Options(),
                tcp: NWProtocolTCP.Options()
            )
        } else {
            parameters = .tcp
        }
        parameters.requiredInterface = requiredInterface
        if let sourceAddress = route.sourceAddress, !sourceAddress.isEmpty {
            parameters.requiredLocalEndpoint = .hostPort(
                host: NWEndpoint.Host(sourceAddress),
                port: .any
            )
        }

        let wireRequest = try Self.serialize(request, hostname: hostname, port: portNumber, scheme: scheme)
        let connection = NWConnection(
            host: NWEndpoint.Host(hostname),
            port: port,
            using: parameters
        )
        return try await exchange(wireRequest, over: connection)
    }

    private func resolveInterface(for route: ZTEHTTPRoute) async throws -> NWInterface? {
        try await interfaceResolver.resolve(route, timeout: min(timeout, 3))
    }

    private func exchange(_ request: Data, over connection: NWConnection) async throws -> ZTEHTTPResponse {
        try await withCheckedThrowingContinuation { continuation in
            let exchange = ZTEHTTPExchange(
                connection: connection,
                continuation: continuation,
                queue: queue,
                timeout: timeout
            )
            exchange.start(request)
        }
    }

    private static func serialize(
        _ request: URLRequest,
        hostname: String,
        port: Int,
        scheme: String
    ) throws -> Data {
        guard let url = request.url else { throw ZTEUBusError.invalidEndpoint }
        let method = request.httpMethod ?? "GET"
        var target = url.path.isEmpty ? "/" : url.path
        if let query = url.query, !query.isEmpty { target += "?\(query)" }

        let defaultPort = scheme == "https" ? 443 : 80
        let hostHeader = port == defaultPort ? hostname : "\(hostname):\(port)"
        var headers = request.allHTTPHeaderFields ?? [:]
        headers["Host"] = hostHeader
        headers["Connection"] = "close"
        let body = request.httpBody ?? Data()
        headers["Content-Length"] = String(body.count)

        var message = "\(method) \(target) HTTP/1.1\r\n"
        for (name, value) in headers.sorted(by: { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }) {
            message += "\(name): \(value)\r\n"
        }
        message += "\r\n"
        guard var data = message.data(using: .utf8) else { throw ZTEUBusError.invalidResponse }
        data.append(body)
        return data
    }

    fileprivate static func parseResponse(_ data: Data) throws -> ZTEHTTPResponse {
        guard data.count <= maximumResponseBytes else { throw ZTEUBusError.responseTooLarge }
        let separator = Data([13, 10, 13, 10])
        guard let headerRange = data.range(of: separator),
              let headerText = String(data: data[..<headerRange.lowerBound], encoding: .isoLatin1)
        else { throw ZTEUBusError.invalidResponse }

        let lines = headerText.components(separatedBy: "\r\n")
        guard let statusLine = lines.first else { throw ZTEUBusError.invalidResponse }
        let statusParts = statusLine.split(separator: " ", maxSplits: 2)
        guard statusParts.count >= 2, let status = Int(statusParts[1]) else {
            throw ZTEUBusError.invalidResponse
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        let bodyStart = headerRange.upperBound
        var body = Data(data[bodyStart...])
        if let transferEncoding = headerValue("Transfer-Encoding", in: headers),
           transferEncoding.lowercased().contains("chunked") {
            body = try decodeChunked(body)
        } else if let rawLength = headerValue("Content-Length", in: headers),
                  let length = Int(rawLength), length >= 0 {
            guard body.count >= length else { throw ZTEUBusError.invalidResponse }
            body = body.prefix(length)
        }
        return ZTEHTTPResponse(statusCode: status, headers: headers, body: body)
    }

    private static func headerValue(_ name: String, in headers: [String: String]) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    private static func decodeChunked(_ data: Data) throws -> Data {
        var output = Data()
        var cursor = data.startIndex
        let lineEnd = Data([13, 10])

        while cursor < data.endIndex {
            guard let range = data[cursor...].range(of: lineEnd),
                  let line = String(data: data[cursor..<range.lowerBound], encoding: .ascii)
            else { throw ZTEUBusError.invalidResponse }
            let sizeText = line.split(separator: ";", maxSplits: 1).first.map(String.init) ?? line
            guard let size = Int(sizeText.trimmingCharacters(in: .whitespaces), radix: 16) else {
                throw ZTEUBusError.invalidResponse
            }
            cursor = range.upperBound
            if size == 0 { return output }
            guard size <= maximumResponseBytes - output.count else {
                throw ZTEUBusError.responseTooLarge
            }
            guard data.distance(from: cursor, to: data.endIndex) >= size + 2 else {
                throw ZTEUBusError.invalidResponse
            }
            let end = data.index(cursor, offsetBy: size)
            output.append(contentsOf: data[cursor..<end])
            guard data[end] == 13, data[data.index(after: end)] == 10 else {
                throw ZTEUBusError.invalidResponse
            }
            cursor = data.index(end, offsetBy: 2)
        }
        throw ZTEUBusError.invalidResponse
    }
}

/// Owns all mutable state used by Network.framework's `@Sendable` callbacks.
/// The connection runs on one serial queue, while the lock also covers the
/// timeout path and makes the single-resume guarantee explicit to Swift 6.
private final class ZTEHTTPExchange: @unchecked Sendable {
    private let connection: NWConnection
    private let continuation: CheckedContinuation<ZTEHTTPResponse, Error>
    private let queue: DispatchQueue
    private let timeout: TimeInterval
    private let lock = NSLock()
    private var completed = false
    private var received = Data()

    init(
        connection: NWConnection,
        continuation: CheckedContinuation<ZTEHTTPResponse, Error>,
        queue: DispatchQueue,
        timeout: TimeInterval
    ) {
        self.connection = connection
        self.continuation = continuation
        self.queue = queue
        self.timeout = timeout
    }

    func start(_ request: Data) {
        connection.stateUpdateHandler = { [self] state in
            switch state {
            case .ready:
                connection.send(content: request, completion: .contentProcessed { [self] error in
                    if let error { finish(.failure(error)) }
                    else { receiveNext() }
                })
            case let .failed(error):
                finish(.failure(error))
            case .cancelled:
                break
            default:
                break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + timeout) { [self] in
            finish(.failure(ZTEUBusError.timedOut))
        }
    }

    private func receiveNext() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [self]
            content, _, isComplete, error in
            if let content, !append(content) {
                finish(.failure(ZTEUBusError.responseTooLarge))
                return
            }
            if let error {
                finish(.failure(error))
            } else if isComplete {
                do { finish(.success(try NetworkBoundZTEHTTPTransport.parseResponse(snapshot()))) }
                catch { finish(.failure(error)) }
            } else {
                receiveNext()
            }
        }
    }

    private func append(_ content: Data) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !completed,
              content.count <= NetworkBoundZTEHTTPTransport.maximumResponseBytes - received.count
        else { return false }
        received.append(content)
        return true
    }

    private func snapshot() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return received
    }

    private func finish(_ result: sending Result<ZTEHTTPResponse, Error>) {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return
        }
        completed = true
        lock.unlock()

        connection.stateUpdateHandler = nil
        connection.cancel()
        continuation.resume(with: result)
    }
}

private final class ZTEContinuationGate<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false

    func resume(
        _ result: sending Result<Value, Error>,
        continuation: CheckedContinuation<Value, Error>
    ) {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return
        }
        completed = true
        lock.unlock()
        continuation.resume(with: result)
    }
}

enum ZTEJSONValue: Equatable, Sendable, Codable {
    case null
    case bool(Bool)
    case integer(Int64)
    case double(Double)
    case string(String)
    case array([ZTEJSONValue])
    case object([String: ZTEJSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([ZTEJSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: ZTEJSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case let .bool(value):
            try container.encode(value)
        case let .integer(value):
            try container.encode(value)
        case let .double(value):
            try container.encode(value)
        case let .string(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        }
    }

    var objectValue: [String: ZTEJSONValue]? {
        guard case let .object(value) = self else { return nil }
        return value
    }

    var arrayValue: [ZTEJSONValue]? {
        guard case let .array(value) = self else { return nil }
        return value
    }

    var stringValue: String? {
        switch self {
        case let .string(value): return value
        case let .integer(value): return String(value)
        case let .double(value): return String(value)
        default: return nil
        }
    }

    var int64Value: Int64? {
        switch self {
        case let .integer(value): return value
        case let .double(value):
            guard value.isFinite, value.rounded(.towardZero) == value else { return nil }
            return Int64(exactly: value)
        case let .string(value): return Int64(value.trimmingCharacters(in: .whitespacesAndNewlines))
        default: return nil
        }
    }

    var doubleValue: Double? {
        switch self {
        case let .integer(value): return Double(value)
        case let .double(value): return value.isFinite ? value : nil
        case let .string(value):
            guard let parsed = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)),
                  parsed.isFinite
            else { return nil }
            return parsed
        default: return nil
        }
    }

    subscript(key: String) -> ZTEJSONValue? {
        objectValue?[key]
    }
}

struct ZTEUBusCallResult: Equatable, Sendable {
    let status: Int
    let payload: ZTEJSONValue?

    var object: [String: ZTEJSONValue]? { payload?.objectValue }
}

/// Wire values for ZTE's per-request `Z-Mode` header. The historical case
/// names describe the common retail-Web usage, not authorization or mutation
/// semantics: the verified MC7530CA SID-authenticated control path deliberately
/// uses wire value `0` for both reads and actions.
enum ZTEUBusCallMode: String, Equatable, Sendable {
    case read = "0"
    case write = "1"
}

enum ZTEUBusError: LocalizedError, Equatable, Sendable, ModemFailureCategorizing {
    case invalidEndpoint
    case nonHTTPResponse
    case interfaceUnavailable
    case timedOut
    case responseTooLarge
    case httpStatus(Int)
    case invalidResponse
    case rpc(code: Int, message: String?)
    case ubusStatus(Int)
    case authenticationFailed
    case missingSalt
    case missingSession

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "The ZTE management endpoint is invalid."
        case .nonHTTPResponse:
            return "The ZTE management endpoint returned a non-HTTP response."
        case .interfaceUnavailable:
            return "The selected network interface is not available."
        case .timedOut:
            return "The ZTE management request timed out."
        case .responseTooLarge:
            return "The ZTE management response exceeded the safe size limit."
        case let .httpStatus(status):
            return "The ZTE management endpoint returned HTTP \(status)."
        case .invalidResponse:
            return "The ZTE UBus response is malformed."
        case let .rpc(code, message):
            return message.map { "ZTE UBus error \(code): \($0)" } ?? "ZTE UBus error \(code)."
        case let .ubusStatus(status):
            return "ZTE UBus returned status \(status)."
        case .authenticationFailed:
            return "The ZTE administrator password was rejected."
        case .missingSalt:
            return "The ZTE login challenge did not contain a salt."
        case .missingSession:
            return "The ZTE login response did not contain a session."
        }
    }

    var isAccessDenied: Bool {
        if case let .rpc(code, _) = self { return code == -32_002 }
        return false
    }

    var modemFailureCategory: ModemFailureCategory {
        self == .authenticationFailed ? .authentication : .other
    }
}

struct ZTEUBusTransport: Sendable {
    static let zeroSessionID = "00000000000000000000000000000000"

    private let baseURL: URL
    private let ubusURL: URL
    private let origin: String
    private let route: ZTEHTTPRoute
    private let http: any ZTEHTTPTransport

    init(
        baseURL: URL,
        route: ZTEHTTPRoute = .systemDefault,
        http: any ZTEHTTPTransport = NetworkBoundZTEHTTPTransport()
    ) throws {
        guard let scheme = baseURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              baseURL.host != nil
        else { throw ZTEUBusError.invalidEndpoint }

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = ""
        components?.query = nil
        components?.fragment = nil
        guard let rootURL = components?.url else { throw ZTEUBusError.invalidEndpoint }

        self.baseURL = rootURL
        self.ubusURL = rootURL.appendingPathComponent("ubus", isDirectory: true)
        self.origin = rootURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.route = route
        self.http = http
    }

    /// Uses the anonymous method-list endpoint as a strong, read-only device
    /// fingerprint. It does not create a session or read subscriber identity.
    func hasMC7530Schema() async throws -> Bool {
        let request = RPCRequest(
            id: 1,
            method: "list",
            params: [.string(Self.zeroSessionID), .string("zte_nwinfo_api")]
        )
        let reply = try await perform(request)
        guard let objects = reply.result?.objectValue,
              let nwinfo = objects["zte_nwinfo_api"]?.objectValue
        else { return false }
        return nwinfo["nwinfo_get_netinfo"]?.objectValue != nil
    }

    func call(
        sessionID: String,
        object: String,
        method: String,
        parameters: [String: ZTEJSONValue] = [:],
        mode: ZTEUBusCallMode = .read,
        zTag: String = ""
    ) async throws -> ZTEUBusCallResult {
        let request = RPCRequest(
            id: 3,
            method: "call",
            params: [
                .string(sessionID),
                .string(object),
                .string(method),
                .object(parameters)
            ]
        )
        let reply = try await perform(request, mode: mode, zTag: zTag)
        guard let values = reply.result?.arrayValue,
              let rawStatus = values.first?.int64Value,
              let status = Int(exactly: rawStatus)
        else { throw ZTEUBusError.invalidResponse }
        return ZTEUBusCallResult(status: status, payload: values.count > 1 ? values[1] : nil)
    }

    private func perform(
        _ rpc: RPCRequest,
        mode: ZTEUBusCallMode = .read,
        zTag: String = ""
    ) async throws -> RPCReply {
        let body = try JSONEncoder().encode([rpc])
        var request = URLRequest(url: ubusURL)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(origin, forHTTPHeaderField: "Origin")
        request.setValue("\(origin)/", forHTTPHeaderField: "Referer")
        request.setValue(mode.rawValue, forHTTPHeaderField: "Z-Mode")
        request.setValue(zTag, forHTTPHeaderField: "Z-Tag")

        let response = try await http.send(request, route: route)
        guard (200..<300).contains(response.statusCode) else {
            throw ZTEUBusError.httpStatus(response.statusCode)
        }
        guard let reply = try JSONDecoder().decode([RPCReply].self, from: response.body).first else {
            throw ZTEUBusError.invalidResponse
        }
        if let error = reply.error {
            throw ZTEUBusError.rpc(code: error.code, message: error.message)
        }
        guard reply.result != nil else { throw ZTEUBusError.invalidResponse }
        return reply
    }
}

private struct RPCRequest: Encodable, Sendable {
    let jsonrpc = "2.0"
    let id: Int
    let method: String
    let params: [ZTEJSONValue]
}

private struct RPCReply: Decodable, Sendable {
    let id: Int?
    let result: ZTEJSONValue?
    let error: RPCError?
}

private struct RPCError: Decodable, Sendable {
    let code: Int
    let message: String?
}
