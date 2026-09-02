import Darwin
import Combine
import Foundation

struct SpeedTestBinding: Equatable, Sendable {
    let modemID: String
    let modemName: String
    let endpoint: ScopedEndpoint
    let settingsGeneration: UInt64

    var interfaceName: String { endpoint.interfaceName ?? "" }
    var interfaceIndex: UInt32 { endpoint.interfaceIndex ?? 0 }

    init(activeModem: ActiveModem, settingsGeneration: UInt64) throws {
        guard let interfaceName = activeModem.endpoint.interfaceName?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !interfaceName.isEmpty,
              let interfaceIndex = activeModem.endpoint.interfaceIndex,
              interfaceIndex > 0
        else {
            throw SpeedTestError.interfaceBindingUnavailable
        }
        guard interfaceName.utf8.allSatisfy({ byte in
            (byte >= 48 && byte <= 57) ||
                (byte >= 65 && byte <= 90) ||
                (byte >= 97 && byte <= 122) ||
                byte == 45 || byte == 46 || byte == 95
        }) else {
            throw SpeedTestError.invalidInterfaceName
        }

        modemID = activeModem.id
        modemName = activeModem.identity.displayName
        endpoint = ScopedEndpoint(
            baseURL: activeModem.endpoint.baseURL,
            interfaceName: interfaceName,
            interfaceIndex: interfaceIndex,
            sourceAddress: activeModem.endpoint.sourceAddress,
            connectionPath: activeModem.endpoint.connectionPath,
            gateway: activeModem.endpoint.gateway
        )
        self.settingsGeneration = settingsGeneration
    }
}

struct SpeedTestProgress: Equatable, Sendable {
    let downloadBitsPerSecond: Double
    let uploadBitsPerSecond: Double
    let elapsed: TimeInterval

    static let zero = SpeedTestProgress(
        downloadBitsPerSecond: 0,
        uploadBitsPerSecond: 0,
        elapsed: 0
    )
}

struct SpeedTestResult: Equatable, Sendable {
    let binding: SpeedTestBinding
    let downloadBitsPerSecond: Double
    let uploadBitsPerSecond: Double
    let idleLatencyMilliseconds: Double?
    let jitterMilliseconds: Double?
    let packetLossPercent: Double?
    let serverName: String?
    let resultURL: URL?
    let completedAt: Date

    init(
        binding: SpeedTestBinding,
        downloadBitsPerSecond: Double,
        uploadBitsPerSecond: Double,
        idleLatencyMilliseconds: Double? = nil,
        jitterMilliseconds: Double? = nil,
        packetLossPercent: Double? = nil,
        serverName: String? = nil,
        resultURL: URL? = nil,
        completedAt: Date
    ) {
        self.binding = binding
        self.downloadBitsPerSecond = downloadBitsPerSecond
        self.uploadBitsPerSecond = uploadBitsPerSecond
        self.idleLatencyMilliseconds = idleLatencyMilliseconds
        self.jitterMilliseconds = jitterMilliseconds
        self.packetLossPercent = packetLossPercent
        self.serverName = serverName
        self.resultURL = resultURL
        self.completedAt = completedAt
    }
}

enum SpeedTestState: Equatable, Sendable {
    case unavailable(SpeedTestError)
    case ready
    case running(SpeedTestProgress)
    case completed(SpeedTestResult)
    case failed(SpeedTestError)
}

enum SpeedTestError: LocalizedError, Equatable, Sendable {
    case noActiveModem
    case interfaceBindingUnavailable
    case invalidInterfaceName
    case interfaceUnavailable(String)
    case interfaceInactive(String)
    case interfaceIndexChanged(expected: UInt32, actual: UInt32)
    case sourceAddressChanged(String)
    case gatewayChanged(expected: String, actual: String?)
    case defaultRouteUnavailable
    case defaultRouteMismatch(expected: String, actual: [String])
    case ooklaCLIUnavailable
    case ooklaCLIIncompatible
    case launchFailed(String)
    case commandTimedOut
    case commandFailed(status: Int32, detail: String)
    case invalidResult
    case reportedInterfaceMissing
    case reportedInterfaceMismatch(expected: String, actual: String)
    case reportedSourceAddressMismatch(expected: String, actual: String?)

    var errorDescription: String? {
        localizedMessage(language: .english)
    }

    func localizedMessage(language: AppLanguage) -> String {
        switch self {
        case .noActiveModem:
            return L10n.text("No active modem is available for a speed test.", language: language)
        case .interfaceBindingUnavailable:
            return L10n.text("The selected modem is not bound to a verified local network interface.", language: language)
        case .invalidInterfaceName:
            return L10n.text("The selected modem reported an invalid local interface name.", language: language)
        case let .interfaceUnavailable(name):
            return L10n.format("The bound interface %@ is no longer available.", language: language, name)
        case let .interfaceInactive(name):
            return L10n.format("The bound interface %@ is not active.", language: language, name)
        case let .interfaceIndexChanged(expected, actual):
            return L10n.format(
                "The bound interface changed identity (expected index %d, found %d).",
                language: language,
                Int(expected),
                Int(actual)
            )
        case let .sourceAddressChanged(address):
            return L10n.format(
                "The bound source address %@ is no longer assigned to the modem interface.",
                language: language,
                address
            )
        case let .gatewayChanged(expected, actual):
            return L10n.format(
                "The bound gateway changed (expected %@, found %@).",
                language: language,
                expected,
                actual ?? "—"
            )
        case .defaultRouteUnavailable:
            return L10n.text(
                "No default Internet route is available for the Ookla test.",
                language: language
            )
        case let .defaultRouteMismatch(expected, actual):
            return L10n.format(
                "Ookla would use the default route through %@, not the modem interface %@.",
                language: language,
                actual.isEmpty ? "—" : actual.joined(separator: ", "),
                expected
            )
        case .ooklaCLIUnavailable:
            return L10n.text("The official Ookla Speedtest CLI is not installed.", language: language)
        case .ooklaCLIIncompatible:
            return L10n.text("The installed speedtest command is not the official Ookla CLI.", language: language)
        case let .launchFailed(detail):
            return L10n.format("The speed test could not be started: %@", language: language, detail)
        case .commandTimedOut:
            return L10n.text("The speed test timed out.", language: language)
        case let .commandFailed(status, detail):
            let message = L10n.format(
                "The speed test failed (exit %d).",
                language: language,
                Int(status)
            )
            return detail.isEmpty ? message : "\(message) \(detail)"
        case .invalidResult:
            return L10n.text("The speed test returned an unreadable result.", language: language)
        case .reportedInterfaceMissing:
            return L10n.text("The speed test did not report which interface carried its traffic.", language: language)
        case let .reportedInterfaceMismatch(expected, actual):
            return L10n.format(
                "The speed test used %@, not the modem-bound interface %@.",
                language: language,
                actual,
                expected
            )
        case let .reportedSourceAddressMismatch(expected, actual):
            return L10n.format(
                "The speed test reported source address %@, not the modem-bound address %@.",
                language: language,
                actual ?? "—",
                expected
            )
        }
    }
}

protocol SpeedTestRunning: Sendable {
    var availabilityError: SpeedTestError? { get }

    func run(
        binding: SpeedTestBinding,
        progress: @escaping @Sendable (SpeedTestProgress) async -> Void
    ) async throws -> SpeedTestResult

}

extension SpeedTestRunning {
    var availabilityError: SpeedTestError? { nil }
}

struct NetworkInterfaceTraffic: Equatable, Sendable {
    let receivedBytes: UInt64
    let sentBytes: UInt64
    let sampledAt: ContinuousClock.Instant
}

struct NetworkInterfaceByteCounters: Equatable, Sendable {
    let receivedBytes: UInt64
    let sentBytes: UInt64
}

/// Parses the mixed routing-message stream returned by NET_RT_IFLIST2.
/// RTM_NEWADDR records are shorter than `if_msghdr`; only the common
/// msglen/version/type prefix may be read before dispatching on message type.
enum NetworkInterfaceTrafficMessageParser {
    private static let commonHeaderSize = 4

    static func counters(
        in data: Data,
        interfaceIndex: UInt32
    ) -> NetworkInterfaceByteCounters? {
        data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return nil }
            return counters(
                in: baseAddress,
                byteCount: rawBuffer.count,
                interfaceIndex: interfaceIndex
            )
        }
    }

    static func counters(
        in buffer: UnsafeRawPointer,
        byteCount: Int,
        interfaceIndex: UInt32
    ) -> NetworkInterfaceByteCounters? {
        var offset = 0
        while offset + commonHeaderSize <= byteCount {
            let record = buffer.advanced(by: offset)
            var messageLength: UInt16 = 0
            memcpy(&messageLength, record, MemoryLayout<UInt16>.size)
            let length = Int(messageLength)
            let type = record.load(fromByteOffset: 3, as: UInt8.self)
            guard length >= commonHeaderSize, offset + length <= byteCount else {
                return nil
            }

            if type == UInt8(RTM_IFINFO2),
               length >= MemoryLayout<if_msghdr2>.size {
                // Routing records are not guaranteed to start at an
                // if_msghdr2-aligned address, so copy before binding.
                let aligned = UnsafeMutablePointer<if_msghdr2>.allocate(capacity: 1)
                defer { aligned.deallocate() }
                memcpy(aligned, record, MemoryLayout<if_msghdr2>.size)
                let message = aligned.pointee
                if UInt32(message.ifm_index) == interfaceIndex {
                    return NetworkInterfaceByteCounters(
                        receivedBytes: message.ifm_data.ifi_ibytes,
                        sentBytes: message.ifm_data.ifi_obytes
                    )
                }
            }
            offset += length
        }
        return nil
    }
}

protocol NetworkInterfaceTrafficReading: Sendable {
    func read(binding: SpeedTestBinding) throws -> NetworkInterfaceTraffic
}

struct SystemNetworkInterfaceTrafficReader: NetworkInterfaceTrafficReading {
    private let topologyProvider: any NetworkTopologyProviding

    init(
        topologyProvider: any NetworkTopologyProviding = SystemNetworkTopologyProvider()
    ) {
        self.topologyProvider = topologyProvider
    }

    func read(binding: SpeedTestBinding) throws -> NetworkInterfaceTraffic {
        try validateTopology(binding: binding)

        let expectedIndex = binding.interfaceIndex
        var mib: [Int32] = [
            CTL_NET,
            PF_ROUTE,
            0,
            AF_UNSPEC,
            NET_RT_IFLIST2,
            0
        ]
        var size = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0, size > 0 else {
            throw SpeedTestError.interfaceUnavailable(binding.interfaceName)
        }

        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: size,
            alignment: MemoryLayout<if_msghdr2>.alignment
        )
        defer { buffer.deallocate() }
        guard sysctl(&mib, u_int(mib.count), buffer, &size, nil, 0) == 0 else {
            throw SpeedTestError.interfaceUnavailable(binding.interfaceName)
        }

        if let counters = NetworkInterfaceTrafficMessageParser.counters(
            in: UnsafeRawPointer(buffer),
            byteCount: size,
            interfaceIndex: expectedIndex
        ) {
            return NetworkInterfaceTraffic(
                receivedBytes: counters.receivedBytes,
                sentBytes: counters.sentBytes,
                sampledAt: ContinuousClock.now
            )
        }
        throw SpeedTestError.interfaceUnavailable(binding.interfaceName)
    }

    private func validateTopology(binding: SpeedTestBinding) throws {
        let topology = topologyProvider.snapshot()
        guard let interface = topology.interfaces.first(where: { $0.name == binding.interfaceName }) else {
            throw SpeedTestError.interfaceUnavailable(binding.interfaceName)
        }
        guard interface.index == binding.interfaceIndex else {
            throw SpeedTestError.interfaceIndexChanged(
                expected: binding.interfaceIndex,
                actual: interface.index
            )
        }
        guard interface.kind == .physical, interface.isUp, interface.isRunning else {
            throw SpeedTestError.interfaceInactive(binding.interfaceName)
        }
        if let source = binding.endpoint.sourceAddress,
           !source.isEmpty {
            guard let expectedAddress = IPv4HostAddress(string: source),
                  interface.addresses.contains(where: { $0.address == expectedAddress })
            else { throw SpeedTestError.sourceAddressChanged(source) }
        }
        if let expectedGateway = binding.endpoint.gateway,
           !expectedGateway.isEmpty {
            let actualGateway = interface.router?.description
            guard actualGateway == expectedGateway else {
                throw SpeedTestError.gatewayChanged(
                    expected: expectedGateway,
                    actual: actualGateway
                )
            }
        }
    }
}

@MainActor
final class SpeedTestModel: ObservableObject {
    @Published private(set) var state: SpeedTestState = .unavailable(.noActiveModem)
    @Published private(set) var boundInterfaceName: String?
    @Published private(set) var boundConnectionPath: ConnectionPath?

    private let runner: any SpeedTestRunning
    private let availabilityError: SpeedTestError?
    private var binding: SpeedTestBinding?
    private var runTask: Task<Void, Never>?
    private var runToken = UUID()

    init(runner: any SpeedTestRunning) {
        self.runner = runner
        availabilityError = runner.availabilityError
    }

    deinit {
        runTask?.cancel()
    }

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    var canStart: Bool { binding != nil && availabilityError == nil && !isRunning }

    func updateActiveModem(_ activeModem: ActiveModem?, settingsGeneration: UInt64) {
        let next: Result<SpeedTestBinding, SpeedTestError>
        do {
            guard let activeModem else { throw SpeedTestError.noActiveModem }
            next = .success(try SpeedTestBinding(
                activeModem: activeModem,
                settingsGeneration: settingsGeneration
            ))
        } catch let error as SpeedTestError {
            next = .failure(error)
        } catch {
            next = .failure(.interfaceBindingUnavailable)
        }
        let nextBinding = try? next.get()
        guard nextBinding != binding else { return }

        cancelAndInvalidate()
        binding = nextBinding
        boundInterfaceName = nextBinding?.interfaceName
        boundConnectionPath = nextBinding?.endpoint.connectionPath
        switch next {
        case .success:
            state = availabilityError.map(SpeedTestState.unavailable) ?? .ready
        case let .failure(error):
            state = .unavailable(error)
        }
    }

    func start() {
        guard !isRunning else { return }
        if let availabilityError {
            state = .unavailable(availabilityError)
            return
        }
        guard let binding else {
            state = .unavailable(.interfaceBindingUnavailable)
            return
        }

        let token = UUID()
        runToken = token
        state = .running(.zero)
        let runner = self.runner
        let owner = WeakSpeedTestModelReference(self)
        runTask = Task {
            do {
                let result = try await runner.run(binding: binding) { progress in
                    await owner.model()?.accept(
                        progress: progress,
                        token: token,
                        binding: binding
                    )
                }
                try Task.checkCancellation()
                guard let model = owner.model(),
                      model.runToken == token,
                      model.binding == binding
                else { return }
                model.state = .completed(result)
                model.runTask = nil
            } catch {
                guard let model = owner.model(),
                      model.runToken == token,
                      model.binding == binding
                else { return }
                model.runTask = nil
                if error is CancellationError {
                    model.state = .ready
                } else if let speedTestError = error as? SpeedTestError {
                    model.state = .failed(speedTestError)
                } else {
                    model.state = .failed(.launchFailed(error.localizedDescription))
                }
            }
        }
    }

    func cancel() {
        guard isRunning else { return }
        cancelAndInvalidate()
        if binding == nil {
            state = .unavailable(.noActiveModem)
        } else if let availabilityError {
            state = .unavailable(availabilityError)
        } else {
            state = .ready
        }
    }

    private func accept(
        progress: SpeedTestProgress,
        token: UUID,
        binding: SpeedTestBinding
    ) {
        guard runToken == token, self.binding == binding else { return }
        state = .running(progress)
    }

    private func cancelAndInvalidate() {
        runToken = UUID()
        runTask?.cancel()
        runTask = nil
    }
}

private final class WeakSpeedTestModelReference: @unchecked Sendable {
    private weak var value: SpeedTestModel?

    init(_ value: SpeedTestModel) {
        self.value = value
    }

    @MainActor
    func model() -> SpeedTestModel? { value }
}
