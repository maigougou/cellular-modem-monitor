import Foundation

/// Backend-neutral radio state presented by the control panel.
///
/// Vendor representations (QMI masks and ZTE string tokens) stay private to
/// their control sessions. The UI deals only in radio modes and band numbers.
struct ModemControlState: Equatable, Sendable {
    var operatorSelection: OperatorSelection?
    var architecture: NRArchitectureMode
    var saBands: Set<Int>
    var nsaBands: Set<Int>
    var lteBands: Set<Int>
    var canRestoreDefaults: Bool
    var preferenceLifetime: ModemPreferenceLifetime

    /// A serving-PLMN transition can be a normal operator change, not a modem
    /// or SIM replacement. Drop only the operator-specific value while keeping
    /// the verified radio tuple and restore capability for the same modem.
    func clearingOperatorSelection() -> ModemControlState {
        var updated = self
        updated.operatorSelection = nil
        return updated
    }
}

enum ModemPreferenceLifetime: Equatable, Sendable {
    /// The modem itself forgets the setting when it loses power.
    case untilPowerLoss
    /// The modem persists the setting until another write or an explicit reset.
    case persistent
    /// The backend cannot make a reliable persistence claim.
    case unknown
}

enum ModemControlCommand: Equatable, Sendable {
    case scanNetworks
    case selectNetwork(CellularNetwork)
    case selectAutomaticNetwork
    case setArchitecture(NRArchitectureMode)
    case lockNRBands(Set<Int>)
    case lockLTEBands(Set<Int>)
    case restoreDefaults

    var requiredCapability: ModemCapability {
        switch self {
        case .scanNetworks:
            return .networkScan
        case .selectNetwork, .selectAutomaticNetwork:
            return .operatorSelection
        case .setArchitecture:
            return .radioAccessPreference
        case .lockNRBands:
            return .nrBandLock
        case .lockLTEBands:
            return .lteBandLock
        case .restoreDefaults:
            return [.operatorSelection, .radioAccessPreference, .nrBandLock, .lteBandLock]
        }
    }
}

struct ModemControlResult: Equatable, Sendable {
    var state: ModemControlState
    var scannedNetworks: [CellularNetwork]?

    init(state: ModemControlState, scannedNetworks: [CellularNetwork]? = nil) {
        self.state = state
        self.scannedNetworks = scannedNetworks
    }
}

enum ModemControlError: LocalizedError, Equatable, Sendable {
    case invalidState(String)
    case invalidBands(radio: String, bands: [Int])
    case commandRejected(String)
    case verificationFailed(String)
    case rollbackFailed(operation: String, rollback: String)
    case timedOut(String)
    case deviceChanged

    var errorDescription: String? {
        switch self {
        case let .invalidState(message),
             let .commandRejected(message),
             let .verificationFailed(message):
            return message
        case let .invalidBands(radio, bands):
            let values = bands.map(String.init).joined(separator: ", ")
            return "These \(radio) bands are not enabled by the modem defaults: \(values)."
        case let .rollbackFailed(operation, rollback):
            let detail = rollback.trimmingCharacters(in: .whitespacesAndNewlines)
            let terminatedDetail: String
            if detail.isEmpty {
                terminatedDetail = "No rollback detail was reported."
            } else if let last = detail.last, ".!?".contains(last) {
                terminatedDetail = detail
            } else {
                terminatedDetail = detail + "."
            }
            return "\(operation) Automatic rollback also failed: \(terminatedDetail) The modem control state is unknown."
        case let .timedOut(operation):
            return "\(operation) did not complete before the verification timeout."
        case .deviceChanged:
            return "The attached modem changed during the operation. No saved radio settings were written to the replacement device."
        }
    }
}

/// Optional mutating surface implemented only by backends that can provide
/// authenticated, verified controls.
protocol ModemControlBackend: ModemStatusBackend {
    func openControlSession(
        endpoint: ScopedEndpoint,
        credentials: ModemCredentials
    ) async throws -> any ModemControlSession
}

/// One session is bound to one physical modem and one scoped management path.
/// Implementations must verify device identity before writes, read back every
/// successful mutation, and roll back the pre-operation vendor state on error.
protocol ModemControlSession: Sendable {
    var kind: ModemKind { get }
    var capabilities: ModemCapability { get }
    /// Digest returned by the same physical-identity source used during
    /// discovery. The coordinator compares it before exposing any write.
    var stableIdentifier: String { get }

    /// Permanently retires this endpoint/credential-bound session. An in-flight
    /// transaction may still use its private recovery path to restore the
    /// verified pre-operation state, but no new control calls may start.
    func invalidate() async
    func refresh() async throws -> ModemControlState
    func perform(_ command: ModemControlCommand) async throws -> ModemControlResult
}
