import Foundation

/// Identifies a modem implementation without tying callers to its transport.
enum ModemKind: String, CaseIterable, Codable, Hashable, Sendable {
    case vos5G
    case zteMC7530CA

    var displayName: String {
        switch self {
        case .vos5G:
            return "VOS 5G"
        case .zteMC7530CA:
            return "ZTE MC7530CA / G5 MAX"
        }
    }
}

/// Features that a backend can expose safely to the rest of the application.
///
/// Status collection and mutating radio controls are deliberately separate so
/// a read-only backend never has to provide placeholder write operations.
struct ModemCapability: OptionSet, Hashable, Sendable {
    let rawValue: UInt16

    static let statusRead = ModemCapability(rawValue: 1 << 0)
    static let identityRead = ModemCapability(rawValue: 1 << 1)
    static let webUI = ModemCapability(rawValue: 1 << 2)
    static let operatorSelection = ModemCapability(rawValue: 1 << 3)
    static let networkScan = ModemCapability(rawValue: 1 << 4)
    static let radioAccessPreference = ModemCapability(rawValue: 1 << 5)
    static let nrBandLock = ModemCapability(rawValue: 1 << 6)
    static let lteBandLock = ModemCapability(rawValue: 1 << 7)
    static let neighborMeasurements = ModemCapability(rawValue: 1 << 8)

    // Descriptive aliases retained for call sites that discuss radio/device
    // data rather than the read operation itself.
    static let radioStatus = statusRead
    static let deviceInformation = identityRead

    static let vosControls: ModemCapability = [
        .operatorSelection,
        .networkScan,
        .radioAccessPreference,
        .nrBandLock,
        .lteBandLock,
        .neighborMeasurements
    ]
}

/// Describes how macOS reaches the management endpoint. It is intentionally
/// independent of the modem kind: USB ECM and Ethernet both appear as normal
/// IP interfaces, while a modem behind another router is a routed endpoint.
enum ConnectionPath: String, CaseIterable, Hashable, Sendable {
    case directUSB
    case directEthernet
    case routed
    case unknown
}

/// A management URL together with the route scope that selected it.
///
/// The interface index is part of `scopeKey`, which prevents two otherwise
/// identical private addresses on separate interfaces from being collapsed by
/// discovery. `sourceAddress` is advisory: transports that support binding can
/// use it, while URLSession-based transports may initially follow system
/// routing and still retain the route metadata for diagnostics.
struct ScopedEndpoint: Hashable, Sendable {
    let baseURL: URL
    let interfaceName: String?
    let interfaceIndex: UInt32?
    let sourceAddress: String?
    let connectionPath: ConnectionPath
    let gateway: String?

    init(
        baseURL: URL,
        interfaceName: String? = nil,
        interfaceIndex: UInt32? = nil,
        sourceAddress: String? = nil,
        connectionPath: ConnectionPath = .unknown,
        gateway: String? = nil
    ) {
        self.baseURL = baseURL
        self.interfaceName = interfaceName
        self.interfaceIndex = interfaceIndex
        self.sourceAddress = sourceAddress
        self.connectionPath = connectionPath
        self.gateway = gateway
    }

    var host: String? { baseURL.host }

    /// Stable only for the lifetime of the current network topology. Device
    /// identity must still be verified by a backend before the endpoint is used.
    var scopeKey: String {
        let normalizedHost = (baseURL.host ?? baseURL.absoluteString).lowercased()
        let port = baseURL.port.map { ":\($0)" } ?? ""
        let interface = interfaceIndex.map(String.init) ?? "unscoped"
        return "\(normalizedHost)\(port)%\(interface)"
    }
}

/// Non-secret identity returned only after a backend has positively recognized
/// its device. `stableIdentifier` should be a digest rather than a raw serial.
struct ModemIdentity: Hashable, Sendable {
    let kind: ModemKind
    let manufacturer: String
    let model: String
    let displayName: String
    let firmwareVersion: String?
    let hardwareRevision: String?
    let stableIdentifier: String?

    init(
        kind: ModemKind,
        manufacturer: String,
        model: String,
        displayName: String? = nil,
        firmwareVersion: String? = nil,
        hardwareRevision: String? = nil,
        stableIdentifier: String? = nil
    ) {
        self.kind = kind
        self.manufacturer = manufacturer
        self.model = model
        self.displayName = displayName ?? model
        self.firmwareVersion = firmwareVersion
        self.hardwareRevision = hardwareRevision
        self.stableIdentifier = stableIdentifier
    }
}

enum ModemCredentialKind: String, Hashable, Sendable {
    case none
    case ssh
    case web
}

/// Transport-neutral failure categories that must survive discovery and
/// coordinator wrapping. UI state decisions use these structured values rather
/// than parsing localized error text.
enum ModemFailureCategory: String, Equatable, Hashable, Sendable {
    case authentication
    case qmiUnavailable
    case other
}

protocol ModemFailureCategorizing {
    var modemFailureCategory: ModemFailureCategory { get }
}

enum ModemFailureClassifier {
    static func category(of error: Error) -> ModemFailureCategory {
        (error as? any ModemFailureCategorizing)?.modemFailureCategory ?? .other
    }
}

struct SSHCredentials: Equatable, Sendable {
    let username: String
    let password: String
}

struct WebCredentials: Equatable, Sendable {
    let username: String?
    let password: String

    init(username: String? = nil, password: String) {
        self.username = username
        self.password = password
    }
}

enum ModemCredentials: Equatable, Sendable {
    case none
    case ssh(SSHCredentials)
    case web(WebCredentials)

    var kind: ModemCredentialKind {
        switch self {
        case .none: return .none
        case .ssh: return .ssh
        case .web: return .web
        }
    }
}

enum ModemBackendError: LocalizedError, Equatable, Sendable, ModemFailureCategorizing {
    case invalidEndpoint
    case credentialsRequired(ModemCredentialKind)
    case incompatibleCredentials(expected: ModemCredentialKind, actual: ModemCredentialKind)
    case identityUnavailable
    case unsupportedCapability(ModemCapability)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "The modem management endpoint is invalid."
        case let .credentialsRequired(kind):
            return "The modem requires \(kind.rawValue) credentials."
        case let .incompatibleCredentials(expected, actual):
            return "The modem requires \(expected.rawValue) credentials, not \(actual.rawValue) credentials."
        case .identityUnavailable:
            return "The endpoint did not provide a verifiable modem identity."
        case .unsupportedCapability:
            return "This modem backend does not support the requested operation."
        }
    }

    var modemFailureCategory: ModemFailureCategory {
        switch self {
        case .credentialsRequired, .incompatibleCredentials:
            return .authentication
        case .invalidEndpoint, .identityUnavailable, .unsupportedCapability:
            return .other
        }
    }
}

/// Common read-only surface shared by all modem implementations.
///
/// Implementations are expected to be actors (or otherwise safely Sendable).
/// Actor implementations should expose immutable `kind` and `capabilities` as
/// `nonisolated let` values so callers can inspect them without an actor hop.
protocol ModemStatusBackend: Sendable {
    var kind: ModemKind { get }
    var capabilities: ModemCapability { get }

    func identify(
        endpoint: ScopedEndpoint,
        credentials: ModemCredentials
    ) async throws -> ModemIdentity?

    func fetchSnapshot(
        endpoint: ScopedEndpoint,
        credentials: ModemCredentials
    ) async throws -> DeviceSnapshot
}
