import Foundation

enum ConnectionState: Equatable, Sendable {
    case connecting
    case online
    case stale
    case disconnected
    case authenticationFailed
    case qmiUnavailable

    var label: String {
        switch self {
        case .connecting: return "Connecting"
        case .online: return "Online"
        case .stale: return "Stale"
        case .disconnected: return "Disconnected"
        case .authenticationFailed: return "Authentication failed"
        case .qmiUnavailable: return "QMI unavailable"
        }
    }
}

enum StatusPollingPolicy {
    static let reconnectInterval: TimeInterval = 5

    static func interval(
        userInterval: TimeInterval,
        connectionState: ConnectionState
    ) -> TimeInterval {
        let configured = max(1, userInterval)
        return connectionState == .online
            ? configured
            : min(configured, reconnectInterval)
    }
}

struct RefreshCoalescer: Equatable, Sendable {
    private(set) var isPending = false

    mutating func request(isRefreshing: Bool, isControlBusy: Bool) -> Bool {
        guard !isRefreshing, !isControlBusy else {
            isPending = true
            return false
        }
        return true
    }

    mutating func beginRefresh() {
        isPending = false
    }

    func shouldDrain(isRefreshing: Bool, isControlBusy: Bool) -> Bool {
        isPending && !isRefreshing && !isControlBusy
    }
}

enum NRSystemMode: String, Equatable, Sendable {
    case sa = "SA"
    case nsa = "NSA"
}

enum MenuBarStyle: String, CaseIterable, Identifiable, Sendable {
    case detailed
    case compact
    case iconOnly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .detailed: return "Detailed"
        case .compact: return "Compact"
        case .iconOnly: return "Icon only"
        }
    }
}

enum OperatorSelectionMode: Int, Equatable, Sendable {
    case automatic = 0
    case manual = 1
    case deregistered = 2
    case formatOnly = 3
    case manualThenAutomatic = 4

    var label: String {
        switch self {
        case .automatic: return "Automatic"
        case .manual: return "Manual"
        case .deregistered: return "Deregistered"
        case .formatOnly: return "Format only"
        case .manualThenAutomatic: return "Manual, then automatic"
        }
    }
}

enum NetworkAvailability: Int, Equatable, Sendable {
    case unknown = 0
    case available = 1
    case current = 2
    case forbidden = 3

    var label: String {
        switch self {
        case .unknown: return "Unknown"
        case .available: return "Available"
        case .current: return "Current"
        case .forbidden: return "Forbidden"
        }
    }

    var sortOrder: Int {
        switch self {
        case .current: return 0
        case .available: return 1
        case .unknown: return 2
        case .forbidden: return 3
        }
    }

    var mergePriority: Int {
        switch self {
        case .current: return 3
        case .available: return 2
        case .forbidden: return 1
        case .unknown: return 0
        }
    }
}

enum CellularAccessTechnology: Int, Hashable, Sendable {
    case gsm = 0
    case gsmCompact = 1
    case umts = 2
    case edge = 3
    case hsdpa = 4
    case hsupa = 5
    case hspa = 6
    case lte = 7
    case ecGsmIoT = 8
    case nbIoT = 9
    case lte5GC = 10
    case nr5GC = 11
    case ngRAN = 12
    case lteNRDualConnectivity = 13

    var label: String {
        switch self {
        case .gsm: return "GSM"
        case .gsmCompact: return "GSM Compact"
        case .umts: return "UMTS"
        case .edge: return "EDGE"
        case .hsdpa: return "HSDPA"
        case .hsupa: return "HSUPA"
        case .hspa: return "HSPA"
        case .lte: return "LTE"
        case .ecGsmIoT: return "EC-GSM-IoT"
        case .nbIoT: return "NB-IoT"
        case .lte5GC: return "LTE / 5GC"
        case .nr5GC: return "5G SA"
        case .ngRAN: return "5G SA"
        case .lteNRDualConnectivity: return "5G NSA"
        }
    }
}

struct OperatorSelection: Equatable, Sendable {
    var mode: OperatorSelectionMode
    var operatorName: String?
    var plmn: String?
    var accessTechnology: CellularAccessTechnology?

    var formattedPLMN: String? { plmn.map(PLMNFormatter.format) }
}

struct CellularNetwork: Identifiable, Equatable, Sendable {
    var longName: String
    var shortName: String
    var plmn: String
    var availability: NetworkAvailability
    var accessTechnologies: [CellularAccessTechnology]
    /// Opaque token returned by a backend scan and replayed only to that same
    /// backend when the user selects the row. ZTE uses it for the exact m_rat
    /// value; VOS does not need one.
    var selectionToken: String? = nil

    var id: String {
        selectionToken.map { "\(plmn)|\($0)" } ?? plmn
    }

    var displayName: String {
        if !longName.isEmpty { return longName }
        if !shortName.isEmpty { return shortName }
        return plmn
    }

    var accessTechnologyLabel: String {
        accessTechnologies.map(\.label).joined(separator: ", ")
    }

    var formattedPLMN: String {
        PLMNFormatter.format(plmn)
    }

    var supportsLTE: Bool {
        accessTechnologies.contains { [.lte, .lte5GC, .lteNRDualConnectivity].contains($0) }
    }

    var supportsNR: Bool {
        accessTechnologies.contains { [.nr5GC, .ngRAN, .lteNRDualConnectivity].contains($0) }
    }
}

struct OperatorDisplayIdentity: Equatable, Sendable {
    var name: String?
    var plmn: String?

    var formatted: String? {
        switch (name, plmn) {
        case let (.some(name), .some(plmn)): return "\(name) · \(plmn)"
        case let (.some(name), .none): return name
        case let (.none, .some(plmn)): return plmn
        case (.none, .none): return nil
        }
    }

    /// Builds the compact app-header subtitle without exposing numeric PLMN
    /// identifiers. PLMN remains available in detailed network information.
    func headerSubtitle(modemName: String?, fallback: String) -> String {
        switch (name, modemName) {
        case let (.some(carrier), .some(modem)):
            return "\(carrier) · \(modem)"
        case let (.some(carrier), nil):
            return carrier
        case let (nil, .some(modem)):
            return modem
        case (nil, nil):
            return fallback
        }
    }

    static func resolve(
        snapshotName: String?,
        snapshotPLMN: String?,
        selection: OperatorSelection?,
        scannedNetworks: [CellularNetwork]
    ) -> OperatorDisplayIdentity {
        let selectionDigits = normalizedPLMN(selection?.plmn)
        let snapshotDigits = normalizedPLMN(snapshotPLMN)
        let digits = selectionDigits ?? snapshotDigits
        let formattedPLMN = digits.map(PLMNFormatter.format)
        let scannedName = digits.flatMap { current in
            scannedNetworks.first { normalizedPLMN($0.plmn) == current }?.displayName
        }
        // Do not pair a newly selected PLMN with a stale name from the last
        // radio snapshot. A snapshot name is authoritative only for the same
        // PLMN (or when one side did not report a numeric identity).
        let snapshotNameForCurrentPLMN = selectionDigits == nil || snapshotDigits == nil || selectionDigits == snapshotDigits
            ? snapshotName
            : nil
        let candidates = [selection?.operatorName, snapshotNameForCurrentPLMN, scannedName]
        let name = candidates.lazy.compactMap { normalizedName($0, excluding: digits) }.first
        return OperatorDisplayIdentity(name: name, plmn: formattedPLMN)
    }

    private static func normalizedName(_ value: String?, excluding plmn: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, normalizedPLMN(cleaned) != plmn else { return nil }
        return cleaned
    }

    private static func normalizedPLMN(_ value: String?) -> String? {
        guard let value else { return nil }
        let digits = value.filter(\.isNumber)
        guard (digits.count == 5 || digits.count == 6),
              digits.count == value.filter({ $0 != "-" }).count
        else { return nil }
        return digits
    }
}

enum PLMNFormatter {
    static func format(_ value: String) -> String {
        guard !value.contains("-"), value.count > 3 else { return value }
        return "\(value.prefix(3))-\(value.dropFirst(3))"
    }
}

enum NRArchitectureMode: String, CaseIterable, Identifiable, Equatable, Sendable {
    case automatic
    case saOnly
    case nsaOnly
    case lteOnly
    case unavailable

    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatic: return "Auto SA/NSA"
        case .saOnly: return "SA only"
        case .nsaOnly: return "NSA only"
        case .lteOnly: return "LTE only"
        case .unavailable: return "Unavailable"
        }
    }
}

enum NetworkControlOperation: Equatable, Sendable {
    case loading
    case scanning
    case selecting(String)
    case automaticSelection
    case changingArchitecture(NRArchitectureMode)
    case lockingNRBands
    case lockingLTEBands
    case restoring

    var label: String {
        switch self {
        case .loading: return "Reading network settings…"
        case .scanning: return "Scanning networks…"
        case let .selecting(plmn): return "Selecting \(plmn)…"
        case .automaticSelection: return "Restoring automatic network selection…"
        case let .changingArchitecture(mode): return "Applying \(mode.label)…"
        case .lockingNRBands: return "Applying NR band lock…"
        case .lockingLTEBands: return "Applying LTE band lock…"
        case .restoring: return "Restoring automatic defaults…"
        }
    }
}

struct NRBandMask: Equatable, Sendable {
    static let byteCount = 64
    static let zero = NRBandMask(uncheckedBytes: Data(repeating: 0, count: byteCount))

    let bytes: Data

    init?(_ bytes: Data) {
        guard bytes.count == Self.byteCount else { return nil }
        self.bytes = bytes
    }

    private init(uncheckedBytes: Data) {
        bytes = uncheckedBytes
    }

    var isEmpty: Bool { bytes.allSatisfy { $0 == 0 } }
    var base64: String { bytes.base64EncodedString() }

    var enabledBands: [Int] {
        Self.enabledBands(in: bytes)
    }

    init?(bands: Set<Int>) {
        guard let value = Self.bytes(for: bands, byteCount: Self.byteCount) else { return nil }
        bytes = value
    }

    func intersecting(_ other: NRBandMask) -> NRBandMask {
        var value = Data(repeating: 0, count: Self.byteCount)
        for index in 0..<Self.byteCount { value[index] = bytes[index] & other.bytes[index] }
        return NRBandMask(uncheckedBytes: value)
    }

    fileprivate static func bytes(for bands: Set<Int>, byteCount: Int) -> Data? {
        guard bands.allSatisfy({ (1...(byteCount * 8)).contains($0) }) else { return nil }
        var value = Data(repeating: 0, count: byteCount)
        for band in bands {
            let bit = band - 1
            value[bit / 8] |= UInt8(1 << (bit % 8))
        }
        return value
    }

    fileprivate static func enabledBands(in bytes: Data) -> [Int] {
        bytes.enumerated().flatMap { offset, byte in
            (0..<8).compactMap { bit in byte & UInt8(1 << bit) != 0 ? offset * 8 + bit + 1 : nil }
        }
    }
}

struct LTEBandMask: Equatable, Sendable {
    static let byteCount = 32
    static let zero = LTEBandMask(uncheckedBytes: Data(repeating: 0, count: byteCount))

    let bytes: Data

    init?(_ bytes: Data) {
        guard bytes.count == Self.byteCount else { return nil }
        self.bytes = bytes
    }

    init?(bands: Set<Int>) {
        guard let value = NRBandMask.bytes(for: bands, byteCount: Self.byteCount) else { return nil }
        bytes = value
    }

    private init(uncheckedBytes: Data) { bytes = uncheckedBytes }

    var isEmpty: Bool { bytes.allSatisfy { $0 == 0 } }
    var enabledBands: [Int] { NRBandMask.enabledBands(in: bytes) }

    func intersecting(_ other: LTEBandMask) -> LTEBandMask {
        var value = Data(repeating: 0, count: Self.byteCount)
        for index in 0..<Self.byteCount { value[index] = bytes[index] & other.bytes[index] }
        return LTEBandMask(uncheckedBytes: value)
    }
}

struct NRSystemSelectionPreferences: Equatable, Sendable {
    var modePreference: UInt16?
    var saBands: NRBandMask
    var nsaBands: NRBandMask
    var lteBands: LTEBandMask? = nil

    var architectureMode: NRArchitectureMode {
        guard let modePreference else { return .unavailable }
        let hasLTE = modePreference & 0x0010 != 0
        let hasNR = modePreference & 0x0040 != 0

        // LTE-only is the exact LTE RAT mask written by this app. Other
        // no-NR combinations may still include legacy RATs and must not be
        // presented as LTE only.
        if modePreference == 0x0010 { return .lteOnly }
        if hasNR, !hasLTE, !saBands.isEmpty { return .saOnly }
        if hasNR, hasLTE, saBands.isEmpty, !nsaBands.isEmpty { return .nsaOnly }
        if hasNR, hasLTE, !saBands.isEmpty, !nsaBands.isEmpty { return .automatic }
        return .unavailable
    }
}

struct RadioAccessPreferencePlan: Equatable, Sendable {
    let target: NRSystemSelectionPreferences
    /// Architecture changes normally leave the current LTE mask untouched.
    /// LTE-only writes it explicitly when the extended mask is available so
    /// the read-back verifies that disabling NR did not alter an LTE lock.
    let lteBandsToWrite: LTEBandMask?

    static func make(
        mode: NRArchitectureMode,
        baseline: NRSystemSelectionPreferences,
        current: NRSystemSelectionPreferences,
        activeNRBandLock: Set<Int>? = nil
    ) throws -> RadioAccessPreferencePlan {
        guard let automaticMode = baseline.modePreference,
              baseline.architectureMode == .automatic
        else { throw RadioAccessPreferencePlanError.baselineUnavailable }
        guard mode != .unavailable else {
            throw RadioAccessPreferencePlanError.architectureUnavailable
        }

        let nrPlan: NRBandLockPlan?
        if mode != .lteOnly, let activeNRBandLock {
            guard let requested = NRBandMask(bands: activeNRBandLock) else {
                throw NRBandLockPlanError.emptyRequest
            }
            nrPlan = try NRBandLockPlan.make(
                requested: requested,
                baseline: baseline,
                architecture: mode
            )
        } else {
            nrPlan = nil
        }

        switch mode {
        case .automatic:
            return RadioAccessPreferencePlan(
                target: NRSystemSelectionPreferences(
                    modePreference: automaticMode,
                    saBands: nrPlan?.saBands ?? baseline.saBands,
                    nsaBands: nrPlan?.nsaBands ?? baseline.nsaBands,
                    lteBands: current.lteBands
                ),
                lteBandsToWrite: nil
            )
        case .saOnly:
            return RadioAccessPreferencePlan(
                target: NRSystemSelectionPreferences(
                    modePreference: 0x0040,
                    saBands: nrPlan?.saBands ?? baseline.saBands,
                    nsaBands: .zero,
                    lteBands: current.lteBands
                ),
                lteBandsToWrite: nil
            )
        case .nsaOnly:
            return RadioAccessPreferencePlan(
                target: NRSystemSelectionPreferences(
                    modePreference: 0x0050,
                    saBands: .zero,
                    nsaBands: nrPlan?.nsaBands ?? baseline.nsaBands,
                    lteBands: current.lteBands
                ),
                lteBandsToWrite: nil
            )
        case .lteOnly:
            let lteBands: LTEBandMask?
            if let currentLTE = current.lteBands, !currentLTE.isEmpty {
                lteBands = currentLTE
            } else if let baselineLTE = baseline.lteBands, !baselineLTE.isEmpty {
                lteBands = baselineLTE
            } else if current.lteBands?.isEmpty == true || baseline.lteBands?.isEmpty == true {
                throw RadioAccessPreferencePlanError.emptyLTEBandMask
            } else {
                // Some firmware omits the extended LTE mask. Leaving the TLV
                // out preserves the modem's existing LTE band preference.
                lteBands = nil
            }
            return RadioAccessPreferencePlan(
                target: NRSystemSelectionPreferences(
                    modePreference: 0x0010,
                    saBands: .zero,
                    nsaBands: .zero,
                    lteBands: lteBands
                ),
                lteBandsToWrite: lteBands
            )
        case .unavailable:
            throw RadioAccessPreferencePlanError.architectureUnavailable
        }
    }
}

enum RadioAccessPreferencePlanError: LocalizedError, Equatable, Sendable {
    case baselineUnavailable
    case architectureUnavailable
    case emptyLTEBandMask

    var errorDescription: String? {
        switch self {
        case .baselineUnavailable:
            return "The original automatic radio preference was not captured."
        case .architectureUnavailable:
            return "Radio access preference control is unavailable."
        case .emptyLTEBandMask:
            return "The modem reported an empty LTE band mask; LTE-only mode was not applied."
        }
    }
}

struct NRBandLockPlan: Equatable, Sendable {
    let saBands: NRBandMask
    let nsaBands: NRBandMask

    static func make(
        requested: NRBandMask,
        baseline: NRSystemSelectionPreferences,
        architecture: NRArchitectureMode
    ) throws -> NRBandLockPlan {
        let usesSA: Bool
        let usesNSA: Bool
        switch architecture {
        case .automatic:
            usesSA = true
            usesNSA = true
        case .saOnly:
            usesSA = true
            usesNSA = false
        case .nsaOnly:
            usesSA = false
            usesNSA = true
        case .lteOnly:
            throw NRBandLockPlanError.architectureUnavailable
        case .unavailable:
            throw NRBandLockPlanError.architectureUnavailable
        }

        let requestedBands = Set(requested.enabledBands)
        guard !requestedBands.isEmpty else {
            throw NRBandLockPlanError.emptyRequest
        }

        let unavailableSA = usesSA
            ? requestedBands.subtracting(Set(baseline.saBands.enabledBands)).sorted()
            : []
        let unavailableNSA = usesNSA
            ? requestedBands.subtracting(Set(baseline.nsaBands.enabledBands)).sorted()
            : []
        guard unavailableSA.isEmpty, unavailableNSA.isEmpty else {
            throw NRBandLockPlanError.unsupportedBands(sa: unavailableSA, nsa: unavailableNSA)
        }

        let saBands = usesSA ? baseline.saBands.intersecting(requested) : .zero
        let nsaBands = usesNSA ? baseline.nsaBands.intersecting(requested) : .zero
        if usesSA, saBands.isEmpty { throw NRBandLockPlanError.emptySA }
        if usesNSA, nsaBands.isEmpty { throw NRBandLockPlanError.emptyNSA }
        return NRBandLockPlan(saBands: saBands, nsaBands: nsaBands)
    }
}

enum NRBandLockPlanError: LocalizedError, Equatable, Sendable {
    case architectureUnavailable
    case emptyRequest
    case unsupportedBands(sa: [Int], nsa: [Int])
    case emptySA
    case emptyNSA

    var errorDescription: String? {
        switch self {
        case .architectureUnavailable:
            return "The current SA/NSA preference is unavailable; no NR band lock was applied."
        case .emptyRequest:
            return "Enter one or more valid NR bands, for example 77,78."
        case let .unsupportedBands(sa, nsa):
            var details: [String] = []
            if !sa.isEmpty { details.append("SA: \(sa.map(String.init).joined(separator: ", "))") }
            if !nsa.isEmpty { details.append("NSA: \(nsa.map(String.init).joined(separator: ", "))") }
            return "These NR bands are not enabled for the active architecture by the captured modem defaults (\(details.joined(separator: "; ")))."
        case .emptySA:
            return "The requested NR lock would leave the active SA band mask empty."
        case .emptyNSA:
            return "The requested NR lock would leave the active NSA band mask empty."
        }
    }
}

enum ControlOperationDeviceGuardError: LocalizedError, Equatable, Sendable {
    case deviceChanged

    var errorDescription: String? {
        "The attached modem changed during the operation. No saved radio settings were written to the replacement device."
    }
}

/// Binds one control operation to the physical modem that started it.
///
/// The expected fingerprint never changes. Once any mismatch is observed, the
/// guard remains invalid even if the original device later reappears, so no
/// later write or rollback from the same operation can resume.
final class ControlOperationDeviceGuard {
    let expectedFingerprint: String
    private(set) var isValid = true

    init(expectedFingerprint: String) {
        self.expectedFingerprint = expectedFingerprint
    }

    func validate(currentFingerprint: String) throws {
        guard isValid, currentFingerprint == expectedFingerprint else {
            isValid = false
            throw ControlOperationDeviceGuardError.deviceChanged
        }
    }
}

struct DeviceConfiguration: Equatable, Sendable {
    var host: String
    var username: String
    var password: String
    var refreshInterval: TimeInterval
    var sourceAddress: String? = nil
    var interfaceName: String? = nil

    var sshHost: String? { baseURL?.host }

    var baseURL: URL? {
        let value = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        let candidate = value.contains("://") ? value : "http://\(value)"
        guard let components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let hostname = components.host,
              Self.isLocalHost(hostname)
        else {
            return nil
        }

        var normalized = components
        normalized.path = ""
        normalized.query = nil
        normalized.fragment = nil
        return normalized.url
    }

    static func isLocalHost(_ host: String) -> Bool {
        let lower = host.lowercased()
        if lower == "localhost" || lower.hasSuffix(".local") { return true }

        let parts = lower.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, parts.allSatisfy({ 0...255 ~= $0 }) else { return false }
        if parts[0] == 10 || parts[0] == 127 || parts[0] == 169 && parts[1] == 254 { return true }
        if parts[0] == 192 && parts[1] == 168 { return true }
        if parts[0] == 172 && (16...31).contains(parts[1]) { return true }
        if parts[0] == 100 && (64...127).contains(parts[1]) { return true }
        return false
    }
}

struct RadioSignal: Equatable, Sendable {
    var rsrpDBm: Int?
    var rsrqDB: Double?
    var rssiDBm: Int?
    var snrDB: Double?

    static let empty = RadioSignal(
        rsrpDBm: nil,
        rsrqDB: nil,
        rssiDBm: nil,
        snrDB: nil
    )
}

enum RadioCarrierRole: Equatable, Sendable {
    case primary
    case secondary(index: Int?)

    var label: String {
        switch self {
        case .primary:
            return "PCell"
        case let .secondary(index):
            return index.map { "SCell \($0)" } ?? "SCell"
        }
    }
}

enum RadioCarrierState: Equatable, Sendable {
    case active
    case configured
    case deconfigured
    case unknown

    var label: String {
        switch self {
        case .active: return "Active"
        case .configured: return "Configured"
        case .deconfigured: return "Deconfigured"
        case .unknown: return "Unknown"
        }
    }
}

struct LTECarrier: Equatable, Sendable {
    var role: RadioCarrierRole
    var band: String?
    var earfcn: UInt32
    var bandwidthMHz: Double?
    var physicalCellID: UInt16
    var state: RadioCarrierState?
    var globalCellID: UInt64? = nil
    var signal: RadioSignal = .empty

    var downlinkFrequencyMHz: Double? {
        guard let band else { return nil }
        return ChannelFrequency.lteMHz(band: band, earfcn: earfcn)
    }
}

struct NRCarrier: Equatable, Sendable {
    var role: RadioCarrierRole
    var band: String?
    var nrarfcn: UInt32
    var bandwidthMHz: Double?
    var physicalCellID: UInt16?
    var state: RadioCarrierState?
    var globalCellID: UInt64? = nil
    var signal: RadioSignal = .empty

    var downlinkFrequencyMHz: Double? {
        ChannelFrequency.nrMHz(nrarfcn)
    }
}

struct LTECellNeighbor: Equatable, Sendable, Identifiable {
    var band: String?
    var earfcn: UInt32
    var physicalCellID: UInt16
    var signal: RadioSignal

    var id: String { "\(earfcn)-\(physicalCellID)" }

    var downlinkFrequencyMHz: Double? {
        guard let band else { return nil }
        return ChannelFrequency.lteMHz(band: band, earfcn: earfcn)
    }
}

struct DeviceSnapshot: Equatable, Sendable {
    var host: String
    var interfaceName: String?
    var operatorName: String?
    var mcc: String?
    var mnc: String?
    var nrSystemMode: NRSystemMode?

    var nrBand: String?
    var nrChannel: String?
    var nrBandwidthMHz: Double?
    var nrRaw: String?
    var nrSignal: RadioSignal
    var nrGlobalCellID: UInt64? = nil
    var nrPhysicalCellID: UInt16? = nil
    var nrPrimaryCell: NRCarrier? = nil
    var nrSecondaryCells: [NRCarrier] = []

    var lteBand: String?
    var lteChannel: String?
    var lteBandwidthMHz: Double?
    var lteRaw: String?
    var lteSignal: RadioSignal
    var lteGlobalCellID: UInt64? = nil
    var ltePhysicalCellID: UInt16? = nil
    var ltePrimaryCell: LTECarrier?
    var lteSecondaryCells: [LTECarrier]
    var lteNeighborCells: [LTECellNeighbor] = []

    var moduleVersion: String?
    var deviceFirmware: String?
    var updatedAt: Date

    static let empty = DeviceSnapshot(
        host: "192.168.225.1",
        interfaceName: nil,
        operatorName: nil,
        mcc: nil,
        mnc: nil,
        nrSystemMode: nil,
        nrBand: nil,
        nrChannel: nil,
        nrBandwidthMHz: nil,
        nrRaw: nil,
        nrSignal: .empty,
        lteBand: nil,
        lteChannel: nil,
        lteBandwidthMHz: nil,
        lteRaw: nil,
        lteSignal: .empty,
        ltePrimaryCell: nil,
        lteSecondaryCells: [],
        moduleVersion: nil,
        deviceFirmware: nil,
        updatedAt: .distantPast
    )

    var hasRadioData: Bool { nrBand != nil || lteBand != nil }

    var modeLabel: String {
        if let nrSystemMode, nrBand != nil { return nrSystemMode.rawValue }
        switch (nrBand, lteBand) {
        case (.some, .some): return "NR + LTE"
        case (.some, .none): return "NR"
        case (.none, .some): return "LTE"
        case (.none, .none): return "Searching"
        }
    }

    var bandCombination: String {
        var parts: [String] = []
        if let nrBand { parts.append(nrBand) }
        if let lteBand { parts.append(lteBand) }
        return parts.isEmpty ? "—" : parts.joined(separator: "+")
    }

    var displayCombination: String {
        var parts: [String] = []
        if let nrBand { parts.append(nrBand) }
        if let lteBand { parts.append(lteBand) }
        return parts.isEmpty ? "No active band" : parts.joined(separator: "  +  ")
    }

    var detailedMenuTitle: String {
        switch (nrBand, lteBand) {
        case let (.some(nr), .some(lte)):
            if nrSystemMode == .sa { return "SA \(nr)" }
            if nrSystemMode == .nsa { return "NSA \(nr)+\(lte)" }
            return "NR \(nr)+\(lte)"
        case let (.some(nr), .none):
            return "\(nrSystemMode?.rawValue ?? "NR") \(nr)"
        case let (.none, .some(lte)): return "LTE \(lte)"
        case (.none, .none): return "Cellular —"
        }
    }

    var compactMenuTitle: String {
        hasRadioData ? bandCombination : "Cellular —"
    }

    var plmn: String? {
        guard let mcc, let mnc, !mcc.isEmpty, !mnc.isEmpty else { return nil }
        return "\(mcc)-\(mnc)"
    }

    var nrFrequencyMHz: Double? {
        nrChannel.flatMap(UInt32.init).flatMap(ChannelFrequency.nrMHz)
    }

    var lteFrequencyMHz: Double? {
        guard let lteBand, let channel = lteChannel.flatMap(UInt32.init) else { return nil }
        return ChannelFrequency.lteMHz(band: lteBand, earfcn: channel)
    }

    var diagnostics: String {
        var lines = [
            "Cellular Modem Monitor",
            "Updated: \(updatedAt.formatted(date: .numeric, time: .standard))",
            "Host: \(host)",
            "Interface: \(interfaceName ?? "—")",
            "Operator: \(operatorName ?? "—")",
            "PLMN: \(plmn ?? "—")",
            "Mode: \(nrSystemMode?.rawValue ?? modeLabel)",
            "NR: \(nrRaw ?? nrBand ?? "—")",
            "LTE: \(lteRaw ?? lteBand ?? "—")",
            "NR Cell ID: \(nrGlobalCellID.map(Self.cellIDText) ?? "—")",
            "LTE Cell ID: \(lteGlobalCellID.map(Self.cellIDText) ?? "—")",
            "NR signal: \(Self.signalText(nrSignal))",
            "LTE signal: \(Self.signalText(lteSignal))"
        ]
        if let nrBandwidthMHz { lines.append("NR bandwidth: \(Self.bandwidthText(nrBandwidthMHz))") }
        if let nrPrimaryCell { lines.append("NR PCell: \(Self.carrierText(nrPrimaryCell))") }
        for cell in nrSecondaryCells {
            lines.append("NR \(cell.role.label): \(Self.carrierText(cell))")
        }
        if let lteBandwidthMHz { lines.append("LTE bandwidth: \(Self.bandwidthText(lteBandwidthMHz))") }
        if let ltePrimaryCell { lines.append("LTE PCell: \(Self.carrierText(ltePrimaryCell))") }
        for cell in lteSecondaryCells {
            lines.append("LTE \(cell.role.label): \(Self.carrierText(cell))")
        }
        for cell in lteNeighborCells {
            lines.append("LTE neighbor: \(cell.band ?? "Unknown band"), EARFCN \(cell.earfcn), \(Self.signalText(cell.signal))")
        }
        if let moduleVersion { lines.append("Module: \(moduleVersion)") }
        if let deviceFirmware { lines.append("Device firmware: \(deviceFirmware)") }
        return lines.joined(separator: "\n")
    }

    static func bandwidthText(_ value: Double) -> String {
        value.rounded() == value ? "\(Int(value)) MHz" : "\(value) MHz"
    }

    static func frequencyText(_ value: Double) -> String {
        let rounded = value.rounded()
        if abs(value - rounded) < 0.05 { return "\(Int(rounded)) MHz" }
        return String(format: "%.1f MHz", value)
    }

    private static func signalText(_ signal: RadioSignal) -> String {
        var values: [String] = []
        if let value = signal.rsrpDBm { values.append("RSRP \(value) dBm") }
        if let value = signal.rsrqDB { values.append("RSRQ \(metricText(value)) dB") }
        if let value = signal.rssiDBm { values.append("RSSI \(value) dBm") }
        if let value = signal.snrDB { values.append("SNR \(metricText(value)) dB") }
        return values.isEmpty ? "—" : values.joined(separator: ", ")
    }

    private static func carrierText(_ carrier: LTECarrier) -> String {
        var values = [carrier.band ?? "Unknown band", "EARFCN \(carrier.earfcn)"]
        if let cellID = carrier.globalCellID { values.append("Cell ID \(cellIDText(cellID))") }
        if let bandwidthMHz = carrier.bandwidthMHz {
            values.append(bandwidthText(bandwidthMHz))
        }
        if let frequency = carrier.downlinkFrequencyMHz {
            values.append(frequencyText(frequency))
        }
        if let state = carrier.state { values.append(state.label) }
        values.append(signalText(carrier.signal))
        return values.joined(separator: ", ")
    }

    private static func carrierText(_ carrier: NRCarrier) -> String {
        var values = [carrier.band ?? "Unknown band", "NR-ARFCN \(carrier.nrarfcn)"]
        if let cellID = carrier.globalCellID { values.append("Cell ID \(cellIDText(cellID))") }
        if let bandwidthMHz = carrier.bandwidthMHz {
            values.append(bandwidthText(bandwidthMHz))
        }
        if let frequency = carrier.downlinkFrequencyMHz {
            values.append(frequencyText(frequency))
        }
        if let state = carrier.state { values.append(state.label) }
        values.append(signalText(carrier.signal))
        return values.joined(separator: ", ")
    }

    private static func metricText(_ value: Double) -> String {
        value.rounded() == value ? "\(Int(value))" : String(format: "%.1f", value)
    }

    private static func cellIDText(_ value: UInt64) -> String {
        String(value)
    }
}

enum BandParser {
    static func band(from raw: String?, radio: RadioKind) -> String? {
        guard let value = clean(raw) else { return nil }
        let patterns: [String]
        switch radio {
        case .nr:
            patterns = [#"(?i)NR5G\s*BAND\s*(\d+)"#, #"(?i)\bn\s*(\d+)\b"#, #"(?i)\bBAND\s*(\d+)\b"#]
        case .lte:
            patterns = [#"(?i)LTE\s*BAND\s*(\d+)"#, #"(?i)\bB\s*(\d+)\b"#, #"(?i)\bBAND\s*(\d+)\b"#]
        }
        guard let number = firstCapture(in: value, patterns: patterns) else { return nil }
        return radio == .nr ? "n\(number)" : "B\(number)"
    }

    static func channel(from raw: String?, radio: RadioKind) -> String? {
        guard let value = clean(raw) else { return nil }
        let patterns: [String]
        switch radio {
        case .nr:
            patterns = [#"(?i)(?:NR[-_ ]?ARFCN|NRARFCN)\s*[:=]?\s*(\d+)"#]
        case .lte:
            patterns = [#"(?i)(?:EARFCN|LTE[-_ ]?ARFCN)\s*[:=]?\s*(\d+)"#]
        }
        return firstCapture(in: value, patterns: patterns)
    }

    static func clean(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              !["NA", "N/A", "NONE", "NULL", "0", "-"].contains(value.uppercased())
        else { return nil }
        return value
    }

    private static func firstCapture(in value: String, patterns: [String]) -> String? {
        let range = NSRange(value.startIndex..., in: value)
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: value, range: range),
                  match.numberOfRanges > 1,
                  let capture = Range(match.range(at: 1), in: value)
            else { continue }
            return String(value[capture])
        }
        return nil
    }
}

enum RadioKind: Hashable, Sendable {
    case nr
    case lte
}

enum CellMapperLink {
    static func destination(
        for cellID: UInt64,
        radio: RadioKind,
        mcc: String?,
        mnc: String?
    ) -> URL? {
        switch radio {
        case .lte:
            var components = URLComponents()
            components.scheme = "https"
            components.host = "www.cellmapper.net"
            components.path = "/enbid"
            components.queryItems = [
                URLQueryItem(name: "net", value: "LTE"),
                URLQueryItem(name: "cellid", value: String(cellID))
            ]
            return components.url

        case .nr:
            var components = URLComponents()
            components.scheme = "https"
            components.host = "www.cellmapper.net"
            components.path = "/map"
            var queryItems = [
                URLQueryItem(name: "type", value: "NR"),
                URLQueryItem(name: "showTowers", value: "true"),
                URLQueryItem(name: "showTowerLabels", value: "true")
            ]
            if let mcc = normalized(mcc, allowedLengths: [3]),
               let mnc = normalized(mnc, allowedLengths: [2, 3]) {
                queryItems.insert(URLQueryItem(name: "MNC", value: mnc), at: 0)
                queryItems.insert(URLQueryItem(name: "MCC", value: mcc), at: 0)
            }
            components.queryItems = queryItems
            return components.url
        }
    }

    static func copiesCellIDBeforeOpening(radio: RadioKind) -> Bool {
        radio == .nr
    }

    private static func normalized(_ value: String?, allowedLengths: Set<Int>) -> String? {
        guard let value else { return nil }
        let digits = value.filter(\.isNumber)
        guard allowedLengths.contains(digits.count), digits.count == value.count else { return nil }
        return digits
    }
}

enum ChannelFrequency {
    static func nrMHz(_ channel: UInt32) -> Double? {
        switch channel {
        case 0...599_999:
            return Double(channel) * 0.005
        case 600_000...2_016_666:
            return 3_000 + Double(channel - 600_000) * 0.015
        case 2_016_667...3_279_165:
            return 24_250.08 + Double(channel - 2_016_667) * 0.06
        default:
            return nil
        }
    }

    static func lteMHz(band label: String, earfcn: UInt32) -> Double? {
        guard label.first?.uppercased() == "B",
              let number = Int(label.dropFirst()),
              let band = lteBands[number],
              band.range.contains(earfcn)
        else { return nil }
        return band.lowMHz + 0.1 * Double(earfcn - band.offset)
    }

    private struct LTEBand {
        let lowMHz: Double
        let offset: UInt32
        let range: ClosedRange<UInt32>
    }

    // 3GPP downlink EARFCN parameters for bands a VOS-class modem commonly
    // reports. Unknown bands simply keep their raw channel in diagnostics.
    private static let lteBands: [Int: LTEBand] = [
        1: .init(lowMHz: 2_110, offset: 0, range: 0...599),
        2: .init(lowMHz: 1_930, offset: 600, range: 600...1_199),
        3: .init(lowMHz: 1_805, offset: 1_200, range: 1_200...1_949),
        4: .init(lowMHz: 2_110, offset: 1_950, range: 1_950...2_399),
        5: .init(lowMHz: 869, offset: 2_400, range: 2_400...2_649),
        7: .init(lowMHz: 2_620, offset: 2_750, range: 2_750...3_449),
        8: .init(lowMHz: 925, offset: 3_450, range: 3_450...3_799),
        12: .init(lowMHz: 729, offset: 5_010, range: 5_010...5_179),
        13: .init(lowMHz: 746, offset: 5_180, range: 5_180...5_279),
        14: .init(lowMHz: 758, offset: 5_280, range: 5_280...5_379),
        17: .init(lowMHz: 734, offset: 5_730, range: 5_730...5_849),
        18: .init(lowMHz: 860, offset: 5_850, range: 5_850...5_999),
        19: .init(lowMHz: 875, offset: 6_000, range: 6_000...6_149),
        20: .init(lowMHz: 791, offset: 6_150, range: 6_150...6_449),
        21: .init(lowMHz: 1_495.9, offset: 6_450, range: 6_450...6_599),
        23: .init(lowMHz: 2_180, offset: 7_500, range: 7_500...7_699),
        24: .init(lowMHz: 1_525, offset: 7_700, range: 7_700...8_039),
        25: .init(lowMHz: 1_930, offset: 8_040, range: 8_040...8_689),
        26: .init(lowMHz: 859, offset: 8_690, range: 8_690...9_039),
        27: .init(lowMHz: 852, offset: 9_040, range: 9_040...9_209),
        28: .init(lowMHz: 758, offset: 9_210, range: 9_210...9_659),
        29: .init(lowMHz: 717, offset: 9_660, range: 9_660...9_769),
        30: .init(lowMHz: 2_350, offset: 9_770, range: 9_770...9_869),
        31: .init(lowMHz: 462.5, offset: 9_870, range: 9_870...9_919),
        32: .init(lowMHz: 1_452, offset: 9_920, range: 9_920...10_359),
        33: .init(lowMHz: 1_900, offset: 36_000, range: 36_000...36_199),
        34: .init(lowMHz: 2_010, offset: 36_200, range: 36_200...36_349),
        35: .init(lowMHz: 1_850, offset: 36_350, range: 36_350...36_949),
        36: .init(lowMHz: 1_930, offset: 36_950, range: 36_950...37_549),
        37: .init(lowMHz: 1_910, offset: 37_550, range: 37_550...37_749),
        38: .init(lowMHz: 2_570, offset: 37_750, range: 37_750...38_249),
        39: .init(lowMHz: 1_880, offset: 38_250, range: 38_250...38_649),
        40: .init(lowMHz: 2_300, offset: 38_650, range: 38_650...39_649),
        41: .init(lowMHz: 2_496, offset: 39_650, range: 39_650...41_589),
        42: .init(lowMHz: 3_400, offset: 41_590, range: 41_590...43_589),
        43: .init(lowMHz: 3_600, offset: 43_590, range: 43_590...45_589),
        44: .init(lowMHz: 703, offset: 45_590, range: 45_590...46_589),
        45: .init(lowMHz: 1_447, offset: 46_590, range: 46_590...46_789),
        46: .init(lowMHz: 5_150, offset: 46_790, range: 46_790...54_539),
        47: .init(lowMHz: 5_855, offset: 54_540, range: 54_540...55_239),
        48: .init(lowMHz: 3_550, offset: 55_240, range: 55_240...56_739),
        65: .init(lowMHz: 2_110, offset: 65_536, range: 65_536...66_435),
        66: .init(lowMHz: 2_110, offset: 66_436, range: 66_436...67_335),
        71: .init(lowMHz: 617, offset: 68_586, range: 68_586...68_935)
    ]
}
