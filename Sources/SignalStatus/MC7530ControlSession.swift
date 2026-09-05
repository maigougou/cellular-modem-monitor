import CryptoKit
import Foundation

private func mc7530IsASCIIDigits(_ value: String) -> Bool {
    !value.isEmpty && value.utf8.allSatisfy { byte in
        byte >= 48 && byte <= 57
    }
}

/// Polling limits are explicit because the retail Web UI has no reliable scan
/// timeout (and accidentally resets its manual-registration counter on every
/// poll). Tests inject zero-delay limits; production remains finite.
struct MC7530ControlTiming: Sendable {
    var pollIntervalNanoseconds: UInt64
    var scanAttempts: Int
    var registrationAttempts: Int
    var verificationAttempts: Int
    var resetAttempts: Int

    static let production = MC7530ControlTiming(
        pollIntervalNanoseconds: 1_000_000_000,
        scanAttempts: 180,
        registrationAttempts: 120,
        verificationAttempts: 45,
        resetAttempts: 40
    )
}

private struct MC7530RawControlState: Equatable, Sendable {
    private static let acceptedNetSelectTokens: Set<String> = [
        "WL_AND_NSA", "WCDMA_AND_LTE", "Only_LTE", "Only_WCDMA",
        "LTE_AND_5G", "Only_5G"
    ]

    var netSelect: String
    var netSelectMode: String
    var operatorName: String?
    var plmn: String?
    var networkType: String?
    var lteBands: Set<Int>
    var saBands: Set<Int>
    var nsaBands: Set<Int>
    var nrdcBands: Set<Int>
    var gwBandLock: String
    var lteCellLock: String
    var nrCellLock: String

    var architecture: NRArchitectureMode {
        switch netSelect {
        case "WL_AND_NSA": return .automatic
        case "LTE_AND_5G": return .nsaOnly
        case "Only_5G": return .saOnly
        case "Only_LTE": return .lteOnly
        default: return .unavailable
        }
    }

    var operatorSelection: OperatorSelection {
        OperatorSelection(
            mode: netSelectMode == "manual_select" ? .manual : .automatic,
            operatorName: operatorName,
            plmn: plmn,
            accessTechnology: Self.accessTechnology(for: networkType)
        )
    }

    var controlState: ModemControlState {
        ModemControlState(
            operatorSelection: operatorSelection,
            architecture: architecture,
            saBands: saBands,
            nsaBands: nsaBands,
            lteBands: lteBands,
            availableNRBands: MC7530ControlSession.defaultNRBands,
            availableLTEBands: MC7530ControlSession.defaultLTEBands,
            canRestoreDefaults: true,
            preferenceLifetime: .persistent
        )
    }

    static func parse(_ payload: ZTEJSONValue) throws -> MC7530RawControlState {
        guard let object = payload.objectValue,
              let netSelect = normalized(object["net_select"]?.stringValue),
              let netSelectMode = normalized(object["net_select_mode"]?.stringValue),
              let lte = parseBands(object["lte_band"]?.stringValue),
              let sa = parseBands(object["nr5g_sa_band_lock"]?.stringValue),
              let nsa = parseBands(object["nr5g_nsa_band_lock"]?.stringValue),
              let nrdc = parseBands(object["nr5g_nrdc_band_lock"]?.stringValue),
              let gwBandLock = normalized(object["gw_band_lock"]?.stringValue),
              acceptedNetSelectTokens.contains(netSelect),
              ["auto_select", "manual_select"].contains(netSelectMode),
              !lte.isEmpty, !sa.isEmpty, !nsa.isEmpty, !nrdc.isEmpty
        else { throw ZTEUBusError.invalidResponse }

        let mcc = formattedMCC(object["rmcc"])
        let mnc = formattedMNC(object["rmnc"])
        let plmn: String?
        if componentIsAbsent(object["rmcc"]), componentIsAbsent(object["rmnc"]) {
            plmn = nil
        } else if let mcc, let mnc {
            plmn = mcc + mnc
        } else {
            throw ZTEUBusError.invalidResponse
        }

        return MC7530RawControlState(
            netSelect: netSelect,
            netSelectMode: netSelectMode,
            operatorName: normalized(object["network_provider_fullname"]?.stringValue)
                ?? normalized(object["network_provider"]?.stringValue),
            plmn: plmn,
            networkType: normalized(object["network_type"]?.stringValue),
            lteBands: lte,
            saBands: sa,
            nsaBands: nsa,
            nrdcBands: nrdc,
            gwBandLock: gwBandLock,
            lteCellLock: normalizedCellLock(
                object["lock_lte_cell"]?.stringValue,
                unlockedSentinel: "0,0"
            ),
            nrCellLock: normalizedCellLock(
                object["lock_nr_cell"]?.stringValue,
                unlockedSentinel: "0,0,0"
            )
        )
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let result = value
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    private static func formattedMCC(_ value: ZTEJSONValue?) -> String? {
        switch value {
        case let .string(raw):
            let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return token.count == 3 && mc7530IsASCIIDigits(token) ? token : nil
        case let .integer(number):
            guard (0...999).contains(number) else { return nil }
            return String(format: "%03lld", number)
        default:
            return nil
        }
    }

    private static func formattedMNC(_ value: ZTEJSONValue?) -> String? {
        switch value {
        case let .string(raw):
            let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return (token.count == 2 || token.count == 3) && mc7530IsASCIIDigits(token)
                ? token : nil
        case let .integer(number):
            guard (0...999).contains(number) else { return nil }
            return String(format: number < 100 ? "%02lld" : "%03lld", number)
        default:
            return nil
        }
    }

    private static func componentIsAbsent(_ value: ZTEJSONValue?) -> Bool {
        switch value {
        case nil, .null:
            return true
        case let .string(raw):
            return raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default:
            return false
        }
    }

    private static func parseBands(_ value: String?) -> Set<Int>? {
        guard let value else { return nil }
        let fields = value.split(separator: ",", omittingEmptySubsequences: false)
        guard !fields.isEmpty else { return nil }
        var values: Set<Int> = []
        for field in fields {
            let token = field.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty,
                  mc7530IsASCIIDigits(token),
                  let band = Int(token),
                  band > 0
            else { return nil }
            values.insert(band)
        }
        return values
    }

    private static func normalizedCellLock(
        _ value: String?,
        unlockedSentinel: String
    ) -> String {
        guard let normalized = normalized(value), normalized != unlockedSentinel else {
            return ""
        }
        return normalized
    }

    private static func accessTechnology(for value: String?) -> CellularAccessTechnology? {
        guard let value = value?.uppercased() else { return nil }
        if value.contains("ENDC") || value.contains("NSA") { return .lteNRDualConnectivity }
        if value.contains("LTE") && value.contains("5GC") { return .lte5GC }
        if value.contains("NR") || value.contains("5G") { return .nr5GC }
        if value.contains("LTE") || value.contains("4G") { return .lte }
        if value.contains("WCDMA") || value.contains("UMTS") || value.contains("3G") { return .umts }
        if value.contains("GSM") || value.contains("2G") { return .gsm }
        return nil
    }
}

private struct MC7530ManualRegistration: Equatable, Sendable {
    let plmn: String
    let rat: String
}

private struct MC7530CellLockRollbackPlan: Equatable, Sendable {
    let gwBandMask: String
    let lteParameters: [String: ZTEJSONValue]?
    let nrParameters: [String: ZTEJSONValue]?
}

/// Authenticated radio controls for the MC7530CA / G5 MAX retail Web UBus API.
///
/// Every mutation is preceded by a physical-device identity check, followed by
/// authoritative `nwinfo_get_netinfo` readback. On a failed write or readback,
/// the exact pre-operation ZTE tokens/band lists are restored where the retail
/// API exposes a corresponding setter.
actor MC7530ControlSession: ModemRestartSession {
    typealias Sleeper = @Sendable (UInt64) async throws -> Void

    nonisolated let kind = ModemKind.zteMC7530CA
    nonisolated let capabilities: ModemCapability = [
        .deviceRestart,
        .operatorSelection,
        .networkScan,
        .radioAccessPreference,
        .nrBandLock,
        .lteBandLock
    ]
    nonisolated let stableIdentifier: String

    static let defaultLTEBands: Set<Int> = [
        2, 4, 5, 7, 12, 13, 17, 25, 26, 29, 30, 38, 41, 42, 43, 48, 66, 71
    ]
    static let defaultNRBands: Set<Int> = [
        2, 5, 7, 12, 25, 29, 30, 38, 41, 66, 71, 77
    ]
    /// `nr5g_nrdc_band_lock` is a read-only capability/default list on this
    /// retail build: the exposed UBus schema has no corresponding setter.
    /// Restore is therefore allowed only while it already equals this exact
    /// verified target value, so the global reset has no non-default NRDC
    /// value to destroy.
    static let defaultNRDCBands: Set<Int> = [
        1, 2, 3, 5, 7, 8, 12, 13, 14, 18, 20, 25, 26, 28, 29, 30, 34, 38,
        39, 40, 41, 46, 47, 48, 50, 51, 53, 65, 66, 67, 68, 70, 71, 74, 75,
        76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 89, 91, 92, 93, 94, 95,
        96, 97, 98, 99, 102, 104, 105, 106, 257, 258, 259, 260, 261
    ]
    static let automaticNetSelect = "WL_AND_NSA"
    private static let acceptedRegistrationRATs: Set<String> = [
        "0", "2", "7", "9", "11", "12", "13", "14"
    ]
    /// Exact registration technologies that can coexist with each verified
    /// `net_select` token. This is checked before every manual-register write;
    /// a scan row from another radio mode must never be replayed blindly.
    private static let registrationRATsByNetSelect: [String: Set<String>] = [
        "WL_AND_NSA": ["0", "2", "7", "9", "11", "12", "13", "14"],
        "WCDMA_AND_LTE": ["2", "7"],
        "Only_WCDMA": ["2"],
        "Only_LTE": ["7", "14"],
        "LTE_AND_5G": ["7", "13"],
        "Only_5G": ["9", "11", "12"]
    ]

    private let session: ZTEAuthSession
    private let expectedFingerprint: String
    private let timing: MC7530ControlTiming
    private let sleep: Sleeper
    private var invalidated = false
    private var operationInProgress = false
    private var operationMutationAttempted = false
    /// `nwinfo_get_netinfo` reports only a broad network type, not the exact
    /// `m_rat` token required to replay manual registration. Retain a token only
    /// when this session wrote it or a fresh scan identifies one unambiguous
    /// current row. Never infer 9/11/12 from a generic 5G label.
    private var knownManualRegistration: MC7530ManualRegistration?

    private init(
        session: ZTEAuthSession,
        expectedFingerprint: String,
        timing: MC7530ControlTiming,
        sleep: @escaping Sleeper
    ) {
        self.session = session
        self.expectedFingerprint = expectedFingerprint
        self.stableIdentifier = expectedFingerprint
        self.timing = timing
        self.sleep = sleep
    }

    static func open(
        session: ZTEAuthSession,
        timing: MC7530ControlTiming = .production,
        sleep: @escaping Sleeper = { try await Task.sleep(nanoseconds: $0) }
    ) async throws -> MC7530ControlSession {
        let fingerprint = try await fetchFingerprint(session: session)
        return MC7530ControlSession(
            session: session,
            expectedFingerprint: fingerprint,
            timing: timing,
            sleep: sleep
        )
    }

    func invalidate() async {
        invalidated = true
    }

    func requestRestart() async throws {
        guard !operationInProgress else {
            throw ModemControlError.invalidState("Another MC7530CA control operation is already in progress.")
        }
        operationInProgress = true
        defer { operationInProgress = false }
        try await validateDevice()
        try Task.checkCancellation()
        guard !invalidated else { throw ModemControlError.deviceChanged }
        // The exact vendor Web UI action is device_reboot(moduleName: web).
        // Retire this session even if its reply is lost; never recover/replay it.
        invalidated = true
        try await session.restartDevice()
    }

    func refresh() async throws -> ModemControlState {
        try await validateDevice()
        let raw = try await readRawState()
        try await validateDevice()
        reconcileKnownManualRegistration(with: raw)
        return raw.controlState
    }

    func perform(_ command: ModemControlCommand) async throws -> ModemControlResult {
        guard !operationInProgress else {
            throw ModemControlError.invalidState(
                "Another MC7530CA control operation is already in progress."
            )
        }
        operationInProgress = true
        operationMutationAttempted = false
        defer {
            operationMutationAttempted = false
            operationInProgress = false
        }
        guard capabilities.contains(command.requiredCapability) else {
            throw ModemBackendError.unsupportedCapability(command.requiredCapability)
        }
        try await validateDevice()

        switch command {
        case .scanNetworks:
            let networks = try await scanNetworks()
            return ModemControlResult(state: try await refresh(), scannedNetworks: networks)
        case let .selectNetwork(network):
            return ModemControlResult(state: try await selectNetwork(network).controlState)
        case .selectAutomaticNetwork:
            return ModemControlResult(state: try await selectAutomaticNetwork().controlState)
        case let .setArchitecture(mode):
            return ModemControlResult(state: try await setArchitecture(mode).controlState)
        case let .lockNRBands(bands):
            return ModemControlResult(state: try await lockNRBands(bands).controlState)
        case let .lockLTEBands(bands):
            return ModemControlResult(state: try await lockLTEBands(bands).controlState)
        case .restoreDefaults:
            return ModemControlResult(state: try await restoreDefaults().controlState)
        }
    }

    private func readRawState(
        allowInvalidatedSession: Bool = false
    ) async throws -> MC7530RawControlState {
        let payload = try await read(
            "nwinfo_get_netinfo",
            allowInvalidatedSession: allowInvalidatedSession
        )
        return try MC7530RawControlState.parse(payload)
    }

    private func scanNetworks() async throws -> [CellularNetwork] {
        try await write("nwinfo_manual_scan")
        let completed: Bool? = try await poll(attempts: timing.scanAttempts) {
            let payload = try await self.read("nwinfo_m_netselect_status")
            guard let status = payload["m_netselect_status"]?.stringValue?
                .trimmingCharacters(in: .whitespacesAndNewlines), !status.isEmpty
            else { throw ZTEUBusError.invalidResponse }
            if status == "manual_selecting" { return nil }
            if status == "manual_search_fail" {
                throw ModemControlError.commandRejected("The MC7530CA network scan failed.")
            }
            // The retail UI treats every other status as completion.
            return true
        }
        guard completed == true else { throw ModemControlError.timedOut("Network scan") }

        let payload = try await read("nwinfo_m_netselect_contents")
        guard let contents = payload["m_netselect_contents"]?.stringValue else {
            throw ZTEUBusError.invalidResponse
        }
        let networks = try Self.parseNetworks(contents)
        let current = try await readRawState()
        reconcileKnownManualRegistration(with: current, scannedNetworks: networks)
        return networks
    }

    private func selectNetwork(_ network: CellularNetwork) async throws -> MC7530RawControlState {
        let previous = try await readRawState()
        let previousManual = try replayableManualRegistration(
            for: previous,
            operation: "changing the current manual operator"
        )
        guard let token = network.selectionToken,
              Self.acceptedRegistrationRATs.contains(token),
              let targetPLMN = Self.normalizedPLMN(network.plmn),
              Self.registrationRATsByNetSelect[previous.netSelect]?.contains(token) == true
        else {
            throw ModemControlError.invalidState(
                "The selected MC7530CA scan row is not valid for the current radio access mode. Scan again after choosing the required mode."
            )
        }
        let targetRegistration = MC7530ManualRegistration(plmn: targetPLMN, rat: token)
        var expectedState = previous
        expectedState.netSelectMode = "manual_select"
        expectedState.plmn = targetPLMN
        let expected = expectedState
        let rollbackPlan = try Self.rollbackPlan(for: previous)

        do {
            try await manualRegister(
                plmn: targetPLMN,
                rat: token,
                netSelect: previous.netSelect
            )
            let final = try await pollRaw(attempts: timing.verificationAttempts) { raw in
                Self.persistentConfigurationMatches(raw, expected) &&
                    Self.manualRegistrationMatches(raw, targetRegistration)
            }
            guard let final else {
                throw ModemControlError.verificationFailed(
                    "The MC7530CA accepted manual registration, but the requested operator was not active on readback."
                )
            }
            try await validateDevice()
            return final
        } catch {
            let operationError = error
            guard operationMutationAttempted else { throw operationError }
            let cleanup = Task {
                try await self.restoreRaw(
                    previous,
                    manualRegistration: previousManual,
                    rollbackPlan: rollbackPlan
                )
            }
            let recovery: String?
            do {
                recovery = try await cleanup.value
            } catch {
                if error as? ModemControlError == .deviceChanged { throw operationError }
                throw ModemControlError.rollbackFailed(
                    operation: operationError.localizedDescription,
                    rollback: error.localizedDescription
                )
            }
            if let recovery {
                throw ModemControlError.rollbackFailed(
                    operation: operationError.localizedDescription,
                    rollback: recovery
                )
            }
            throw operationError
        }
    }

    private func selectAutomaticNetwork() async throws -> MC7530RawControlState {
        let previous = try await readRawState()
        let previousManual = try replayableManualRegistration(
            for: previous,
            operation: "leaving the current manual operator"
        )
        var expectedState = previous
        expectedState.netSelectMode = "auto_select"
        let expected = expectedState
        let rollbackPlan = try Self.rollbackPlan(for: previous)
        do {
            try await setNetSelect(previous.netSelect)
            let final = try await pollRaw(attempts: timing.verificationAttempts) {
                Self.persistentConfigurationMatches($0, expected)
            }
            guard let final else {
                throw ModemControlError.verificationFailed(
                    "Automatic operator selection was not confirmed by MC7530CA readback."
                )
            }
            try await validateDevice()
            return final
        } catch {
            let operationError = error
            guard operationMutationAttempted else { throw operationError }
            let cleanup = Task {
                try await self.restoreRaw(
                    previous,
                    manualRegistration: previousManual,
                    rollbackPlan: rollbackPlan
                )
            }
            let rollback: String?
            do {
                rollback = try await cleanup.value
            } catch {
                if error as? ModemControlError == .deviceChanged { throw operationError }
                throw ModemControlError.rollbackFailed(
                    operation: operationError.localizedDescription,
                    rollback: error.localizedDescription
                )
            }
            if let rollback {
                throw ModemControlError.rollbackFailed(
                    operation: operationError.localizedDescription,
                    rollback: rollback
                )
            }
            throw operationError
        }
    }

    private func setArchitecture(_ mode: NRArchitectureMode) async throws -> MC7530RawControlState {
        let token: String
        switch mode {
        case .automatic: token = Self.automaticNetSelect
        case .nsaOnly: token = "LTE_AND_5G"
        case .saOnly: token = "Only_5G"
        case .lteOnly: token = "Only_LTE"
        case .unavailable:
            throw ModemControlError.invalidState("Select a supported radio access mode.")
        }

        let previous = try await readRawState()
        let previousManual = try replayableManualRegistration(
            for: previous,
            operation: "changing radio access mode while manual selection is active"
        )
        if let previousManual,
           Self.registrationRATsByNetSelect[token]?.contains(previousManual.rat) != true {
            throw ModemControlError.invalidState(
                "The current manual operator RAT is incompatible with the requested MC7530CA radio mode. Select automatic operator mode or scan/select a compatible operator first."
            )
        }
        var expectedState = previous
        expectedState.netSelect = token
        let expected = expectedState
        let rollbackPlan = try Self.rollbackPlan(for: previous)
        do {
            try await setNetSelect(token)
            if previous.netSelectMode == "manual_select" {
                try await restoreManualOperator(previousManual, netSelect: token)
            }
            let final = try await pollRaw(attempts: timing.verificationAttempts) { raw in
                Self.persistentConfigurationMatches(raw, expected) &&
                    (previous.netSelectMode != "manual_select" ||
                        Self.manualRegistrationMatches(raw, previousManual))
            }
            guard let final else {
                throw ModemControlError.verificationFailed(
                    "The requested radio access mode was not confirmed by MC7530CA readback."
                )
            }
            try await validateDevice()
            return final
        } catch {
            let operationError = error
            guard operationMutationAttempted else { throw operationError }
            let cleanup = Task {
                try await self.restoreRaw(
                    previous,
                    manualRegistration: previousManual,
                    rollbackPlan: rollbackPlan
                )
            }
            let rollback: String?
            do {
                rollback = try await cleanup.value
            } catch {
                if error as? ModemControlError == .deviceChanged { throw operationError }
                throw ModemControlError.rollbackFailed(
                    operation: operationError.localizedDescription,
                    rollback: error.localizedDescription
                )
            }
            if let rollback {
                throw ModemControlError.rollbackFailed(
                    operation: operationError.localizedDescription,
                    rollback: rollback
                )
            }
            throw operationError
        }
    }

    private func lockNRBands(_ bands: Set<Int>) async throws -> MC7530RawControlState {
        try validateBands(bands, allowed: Self.defaultNRBands, radio: "NR")
        let previous = try await readRawState()
        let previousManual = try replayableManualRegistration(
            for: previous,
            operation: "changing NR bands while manual selection is active"
        )
        var expectedState = previous
        switch previous.architecture {
        case .automatic:
            expectedState.saBands = bands
            expectedState.nsaBands = bands
        case .saOnly:
            expectedState.saBands = bands
        case .nsaOnly:
            expectedState.nsaBands = bands
        case .lteOnly:
            throw ModemControlError.invalidState(
                "NR band lock is unavailable while MC7530CA is in LTE-only mode."
            )
        case .unavailable:
            throw ModemControlError.invalidState(
                "The current MC7530CA radio access mode cannot be mapped safely."
            )
        }
        let expected = expectedState
        let rollbackPlan = try Self.rollbackPlan(for: previous)

        do {
            switch previous.architecture {
            case .automatic:
                try await setNRBands(bands, type: "0")
                try await setNRBands(bands, type: "1")
            case .saOnly:
                try await setNRBands(bands, type: "0")
            case .nsaOnly:
                try await setNRBands(bands, type: "1")
            case .lteOnly, .unavailable:
                preconditionFailure("NR architecture was validated before the first write")
            }

            let final = try await pollRaw(attempts: timing.verificationAttempts) { raw in
                Self.persistentConfigurationMatches(raw, expected) &&
                    (previous.netSelectMode != "manual_select" ||
                        Self.manualRegistrationMatches(raw, previousManual))
            }
            guard let final else {
                throw ModemControlError.verificationFailed(
                    "The requested NR band lock was not confirmed by MC7530CA readback."
                )
            }
            try await validateDevice()
            return final
        } catch {
            let operationError = error
            guard operationMutationAttempted else { throw operationError }
            let cleanup = Task {
                try await self.restoreRaw(
                    previous,
                    manualRegistration: previousManual,
                    rollbackPlan: rollbackPlan
                )
            }
            let rollback: String?
            do {
                rollback = try await cleanup.value
            } catch {
                if error as? ModemControlError == .deviceChanged { throw operationError }
                throw ModemControlError.rollbackFailed(
                    operation: operationError.localizedDescription,
                    rollback: error.localizedDescription
                )
            }
            if let rollback {
                throw ModemControlError.rollbackFailed(
                    operation: operationError.localizedDescription,
                    rollback: rollback
                )
            }
            throw operationError
        }
    }

    private func lockLTEBands(_ bands: Set<Int>) async throws -> MC7530RawControlState {
        try validateBands(bands, allowed: Self.defaultLTEBands, radio: "LTE")
        let previous = try await readRawState()
        let previousManual = try replayableManualRegistration(
            for: previous,
            operation: "changing LTE bands while manual selection is active"
        )
        var expectedState = previous
        expectedState.lteBands = bands
        let expected = expectedState
        let rollbackPlan = try Self.rollbackPlan(for: previous)
        do {
            try await setLTEBands(bands)
            let final = try await pollRaw(attempts: timing.verificationAttempts) {
                Self.persistentConfigurationMatches($0, expected) &&
                    (previous.netSelectMode != "manual_select" ||
                        Self.manualRegistrationMatches($0, previousManual))
            }
            guard let final else {
                throw ModemControlError.verificationFailed(
                    "The requested LTE band lock was not confirmed by MC7530CA readback."
                )
            }
            try await validateDevice()
            return final
        } catch {
            let operationError = error
            guard operationMutationAttempted else { throw operationError }
            let cleanup = Task {
                try await self.restoreRaw(
                    previous,
                    manualRegistration: previousManual,
                    rollbackPlan: rollbackPlan
                )
            }
            let rollback: String?
            do {
                rollback = try await cleanup.value
            } catch {
                if error as? ModemControlError == .deviceChanged { throw operationError }
                throw ModemControlError.rollbackFailed(
                    operation: operationError.localizedDescription,
                    rollback: error.localizedDescription
                )
            }
            if let rollback {
                throw ModemControlError.rollbackFailed(
                    operation: operationError.localizedDescription,
                    rollback: rollback
                )
            }
            throw operationError
        }
    }

    private func restoreDefaults() async throws -> MC7530RawControlState {
        let previous = try await readRawState()
        let previousManual = try replayableManualRegistration(
            for: previous,
            operation: "restoring vendor defaults while manual selection is active"
        )
        // The global reset also owns legacy GW band and cell-lock state. Build
        // and strictly validate the complete rollback request before the first
        // write; malformed readback must never be discovered after reset.
        let rollbackPlan = try Self.rollbackPlan(for: previous)
        do {
            try await write("nwinfo_reset_band_cell_setting")
            let locksReset = try await pollRaw(attempts: timing.resetAttempts) { raw in
                raw.nrdcBands == Self.defaultNRDCBands &&
                    raw.lteCellLock.isEmpty && raw.nrCellLock.isEmpty
            }
            guard let locksReset else {
                throw ModemControlError.timedOut("Restoring MC7530CA band and cell defaults")
            }
            let resetGWBandMask = try Self.rollbackPlan(for: locksReset).gwBandMask

            // Retail MC7530CAV2.6 does not rebuild the SA/NSA allowlists when
            // nwinfo_reset_band_cell_setting is called. It clears the cell
            // locks, restores LTE, and changes the legacy GW mask to its own
            // unlocked value, while leaving an NR lock such as `77` intact.
            // Treat the reset's GW value as authoritative, but explicitly
            // restore every writable LTE/NR vendor list before switching back
            // to automatic SA/NSA mode.
            try await setLTEBands(Self.defaultLTEBands)
            try await setNRBands(Self.defaultNRBands, type: "0")
            try await setNRBands(Self.defaultNRBands, type: "1")
            try await setNetSelect(Self.automaticNetSelect)
            let final = try await pollRaw(attempts: timing.verificationAttempts) { raw in
                raw.netSelect == Self.automaticNetSelect && raw.netSelectMode == "auto_select" &&
                    raw.lteBands == Self.defaultLTEBands &&
                    raw.saBands == Self.defaultNRBands &&
                    raw.nsaBands == Self.defaultNRBands &&
                    raw.nrdcBands == Self.defaultNRDCBands &&
                    raw.gwBandLock.lowercased() == resetGWBandMask.lowercased() &&
                    raw.lteCellLock.isEmpty && raw.nrCellLock.isEmpty
            }
            guard let final else {
                throw ModemControlError.verificationFailed(
                    "MC7530CA automatic mode and unlocked band/cell defaults were not all confirmed on readback."
                )
            }
            try await validateDevice()
            return final
        } catch {
            let operationError = error
            guard operationMutationAttempted else { throw operationError }
            let cleanup = Task {
                try await self.restoreRaw(
                    previous,
                    manualRegistration: previousManual,
                    rollbackPlan: rollbackPlan
                )
            }
            let rollback: String?
            do {
                rollback = try await cleanup.value
            } catch {
                if error as? ModemControlError == .deviceChanged { throw operationError }
                throw ModemControlError.rollbackFailed(
                    operation: operationError.localizedDescription,
                    rollback: error.localizedDescription
                )
            }
            if let rollback {
                throw ModemControlError.rollbackFailed(
                    operation: operationError.localizedDescription,
                    rollback: rollback
                )
            }
            throw operationError
        }
    }

    private func setNetSelect(
        _ value: String,
        allowInvalidatedSession: Bool = false
    ) async throws {
        try await write(
            "nwinfo_set_netselect",
            parameters: ["net_select": .string(value)],
            allowInvalidatedSession: allowInvalidatedSession
        )
    }

    private func setLTEBands(
        _ bands: Set<Int>,
        allowInvalidatedSession: Bool = false
    ) async throws {
        try await write(
            "nwinfo_set_lte_ext_band",
            parameters: ["lte_band": .string(Self.bandCSV(bands))],
            allowInvalidatedSession: allowInvalidatedSession
        )
    }

    private func setNRBands(
        _ bands: Set<Int>,
        type: String,
        allowInvalidatedSession: Bool = false
    ) async throws {
        try await write(
            "nwinfo_set_nrbandlock",
            parameters: [
                "nr5g_type": .string(type),
                "nr5g_band": .string(Self.bandCSV(bands))
            ],
            allowInvalidatedSession: allowInvalidatedSession
        )
    }

    private func setGWBandMask(
        _ mask: String,
        allowInvalidatedSession: Bool = false
    ) async throws {
        try await write(
            "nwinfo_set_gwl_bandlock",
            parameters: [
                "is_gw_band": .string("1"),
                "gw_band_mask": .string(mask),
                "is_lte_band": .string("0"),
                "lte_band_mask": .string("0")
            ],
            allowInvalidatedSession: allowInvalidatedSession
        )
    }

    private func manualRegister(
        plmn: String,
        rat: String,
        netSelect: String,
        allowInvalidatedSession: Bool = false
    ) async throws {
        guard let plmn = Self.normalizedPLMN(plmn),
              Self.acceptedRegistrationRATs.contains(rat),
              Self.registrationRATsByNetSelect[netSelect]?.contains(rat) == true
        else {
            throw ModemControlError.invalidState(
                "The operator registration request is invalid for the current MC7530CA radio mode."
            )
        }

        try await write(
            "nwinfo_manual_register",
            parameters: [
                "m_mcc_mnc": .string(plmn),
                "m_rat": .string(rat)
            ],
            allowInvalidatedSession: allowInvalidatedSession
        )
        let completed: Bool? = try await poll(attempts: timing.registrationAttempts) {
            let payload = try await self.read(
                "nwinfo_m_netselect_result",
                allowInvalidatedSession: allowInvalidatedSession
            )
            guard let result = payload["m_netselect_result"]?.stringValue?
                .trimmingCharacters(in: .whitespacesAndNewlines), !result.isEmpty
            else { throw ZTEUBusError.invalidResponse }
            switch result {
            case "manual_success": return true
            case "manual_fail":
                throw ModemControlError.commandRejected(
                    "The MC7530CA or mobile network rejected manual registration."
                )
            default: return nil
            }
        }
        guard completed == true else {
            throw ModemControlError.timedOut("Manual operator registration")
        }
        knownManualRegistration = MC7530ManualRegistration(plmn: plmn, rat: rat)
    }

    private func restoreManualOperator(
        _ registration: MC7530ManualRegistration?,
        netSelect: String,
        allowInvalidatedSession: Bool = false
    ) async throws {
        guard let registration else {
            throw ModemControlError.invalidState(
                "The previous manual operator does not have an exact MC7530CA RAT token. Run Scan Networks while it is current before changing settings that must replay it."
            )
        }
        try await manualRegister(
            plmn: registration.plmn,
            rat: registration.rat,
            netSelect: netSelect,
            allowInvalidatedSession: allowInvalidatedSession
        )
    }

    private func restoreRaw(
        _ state: MC7530RawControlState,
        manualRegistration: MC7530ManualRegistration?,
        rollbackPlan: MC7530CellLockRollbackPlan
    ) async throws -> String? {
        var failures: [String] = []

        // Reset first so an unexpected collateral cell lock can also be
        // removed. The preflight requires the read-only NRDC list to be the
        // exact reset default, after which every writable field is rebuilt.
        let steps: [(String, () async throws -> Void)] = [
            ("global band/cell reset", {
                try await self.write(
                    "nwinfo_reset_band_cell_setting",
                    allowInvalidatedSession: true
                )
            }),
            ("legacy GW bands", {
                try await self.setGWBandMask(
                    rollbackPlan.gwBandMask,
                    allowInvalidatedSession: true
                )
            }),
            ("LTE bands", {
                try await self.setLTEBands(
                    state.lteBands,
                    allowInvalidatedSession: true
                )
            }),
            ("SA bands", {
                try await self.setNRBands(
                    state.saBands,
                    type: "0",
                    allowInvalidatedSession: true
                )
            }),
            ("NSA bands", {
                try await self.setNRBands(
                    state.nsaBands,
                    type: "1",
                    allowInvalidatedSession: true
                )
            })
        ]
        for (label, operation) in steps {
            if let failure = try await recoveryStep(label, operation: operation) {
                failures.append(failure)
            }
        }
        if let parameters = rollbackPlan.lteParameters,
           let failure = try await recoveryStep("LTE cell lock", operation: {
               try await self.write(
                   "nwinfo_lock_lte_cell",
                   parameters: parameters,
                   allowInvalidatedSession: true
               )
           }) {
            failures.append(failure)
        }
        if let parameters = rollbackPlan.nrParameters,
           let failure = try await recoveryStep("NR cell lock", operation: {
               try await self.write(
                   "nwinfo_lock_nr_cell",
                   parameters: parameters,
                   allowInvalidatedSession: true
               )
           }) {
            failures.append(failure)
        }
        if let failure = try await recoveryStep("radio access mode", operation: {
            try await self.setNetSelect(
                state.netSelect,
                allowInvalidatedSession: true
            )
        }) {
            failures.append(failure)
        }
        if state.netSelectMode == "manual_select",
           let failure = try await recoveryStep("manual operator", operation: {
               try await self.restoreManualOperator(
                   manualRegistration,
                   netSelect: state.netSelect,
                   allowInvalidatedSession: true
               )
           }) {
            failures.append(failure)
        }

        let recovered: MC7530RawControlState?
        do {
            recovered = try await pollRaw(
                attempts: timing.verificationAttempts,
                allowInvalidatedSession: true
            ) { current in
                Self.persistentConfigurationMatches(current, state) &&
                    (state.netSelectMode != "manual_select" ||
                        Self.manualRegistrationMatches(current, manualRegistration))
            }
        } catch {
            if error as? ModemControlError == .deviceChanged { throw error }
            failures.append("final readback: \(error.localizedDescription)")
            recovered = nil
        }
        if recovered != nil {
            try await validatePhysicalDevice()
            return nil
        }
        failures.append("the exact pre-operation state was not confirmed")
        return failures.joined(separator: "; ")
    }

    private func recoveryStep(
        _ label: String,
        operation: () async throws -> Void
    ) async throws -> String? {
        do {
            try await operation()
            return nil
        } catch {
            if error as? ModemControlError == .deviceChanged { throw error }
            return "\(label): \(error.localizedDescription)"
        }
    }

    private static func rollbackPlan(
        for state: MC7530RawControlState
    ) throws -> MC7530CellLockRollbackPlan {
        guard state.nrdcBands == defaultNRDCBands else {
            throw ModemControlError.invalidState(
                "The MC7530CA NRDC list is not the verified retail default and has no exposed rollback setter; the control operation was blocked before any write."
            )
        }
        let mask = state.gwBandLock.trimmingCharacters(in: .whitespacesAndNewlines)
        guard mask.range(
            of: #"^0[xX][0-9a-fA-F]+$"#,
            options: .regularExpression
        ) != nil else {
            throw ModemControlError.invalidState(
                "The MC7530CA returned a malformed legacy GW band mask; the control operation was blocked before any write."
            )
        }

        let lte = try cellLockParameters(
            state.lteCellLock,
            labels: ["lock_lte_pci", "lock_lte_earfcn"],
            ranges: [0...503, 1...262_143],
            radio: "LTE"
        )
        let nr = try cellLockParameters(
            state.nrCellLock,
            labels: ["lock_nr_pci", "lock_nr_earfcn", "lock_nr_cell_band"],
            ranges: [0...1_007, 1...3_279_165, 1...1_024],
            radio: "NR"
        )
        return MC7530CellLockRollbackPlan(
            gwBandMask: mask,
            lteParameters: lte,
            nrParameters: nr
        )
    }

    private static func cellLockParameters(
        _ raw: String,
        labels: [String],
        ranges: [ClosedRange<Int>],
        radio: String
    ) throws -> [String: ZTEJSONValue]? {
        guard !raw.isEmpty else { return nil }
        let fields = raw.split(separator: ",", omittingEmptySubsequences: false)
        guard fields.count == labels.count, ranges.count == labels.count else {
            throw ModemControlError.invalidState(
                "The MC7530CA returned a malformed \(radio) cell lock; the control operation was blocked before any write."
            )
        }
        var parameters: [String: ZTEJSONValue] = [:]
        for index in labels.indices {
            let token = fields[index].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty,
                  mc7530IsASCIIDigits(token),
                  let value = Int(token),
                  ranges[index].contains(value)
            else {
                throw ModemControlError.invalidState(
                    "The MC7530CA returned a malformed \(radio) cell lock; the control operation was blocked before any write."
                )
            }
            parameters[labels[index]] = .string(token)
        }
        return parameters
    }

    private func write(
        _ method: String,
        parameters: [String: ZTEJSONValue] = [:],
        allowInvalidatedSession: Bool = false
    ) async throws {
        if allowInvalidatedSession {
            try await validatePhysicalDevice()
        } else {
            try await validateDevice()
            // No await is allowed between these checks and marking the first
            // ambiguous request boundary. A failure before this point cannot
            // have changed persistent modem state and must not trigger writes.
            guard !invalidated else { throw ModemControlError.deviceChanged }
            try Task.checkCancellation()
            operationMutationAttempted = true
        }
        try await action(
            method,
            parameters: parameters,
            allowInvalidatedSession: allowInvalidatedSession
        )
    }

    private func action(
        _ method: String,
        parameters: [String: ZTEJSONValue] = [:],
        allowInvalidatedSession: Bool = false
    ) async throws {
        guard allowInvalidatedSession || !invalidated else {
            throw ModemControlError.deviceChanged
        }
        try Task.checkCancellation()
        try await session.action(
            object: "zte_nwinfo_api",
            method: method,
            parameters: parameters,
            // The verified MC7530CA SID-authenticated API accepts control RPCs
            // with this form. The browser-style Z-Mode 1/method-tag form returns
            // JSON-RPC -32002 for the same valid SID on the tested firmware.
            mode: .read,
            zTag: ""
        )
    }

    private func read(
        _ method: String,
        parameters: [String: ZTEJSONValue] = [:],
        allowInvalidatedSession: Bool = false
    ) async throws -> ZTEJSONValue {
        guard allowInvalidatedSession || !invalidated else {
            throw ModemControlError.deviceChanged
        }
        try Task.checkCancellation()
        return try await session.call(
            object: "zte_nwinfo_api",
            method: method,
            parameters: parameters,
            mode: .read,
            zTag: ""
        )
    }

    private func pollRaw(
        attempts: Int,
        allowInvalidatedSession: Bool = false,
        predicate: @escaping @Sendable (MC7530RawControlState) -> Bool
    ) async throws -> MC7530RawControlState? {
        try await poll(attempts: attempts) {
            let raw = try await self.readRawState(
                allowInvalidatedSession: allowInvalidatedSession
            )
            return predicate(raw) ? raw : nil
        }
    }

    private func poll<T: Sendable>(
        attempts: Int,
        operation: @escaping @Sendable () async throws -> T?
    ) async throws -> T? {
        guard attempts > 0 else { return nil }
        for attempt in 0..<attempts {
            try Task.checkCancellation()
            do {
                if let value = try await operation() { return value }
            } catch {
                guard Self.isTransientPollError(error) else { throw error }
            }
            if attempt + 1 < attempts {
                try await sleep(timing.pollIntervalNanoseconds)
            }
        }
        return nil
    }

    private static func isTransientPollError(_ error: Error) -> Bool {
        if error is CancellationError { return false }
        if let control = error as? ModemControlError {
            switch control {
            case .commandRejected, .invalidState, .invalidBands, .verificationFailed,
                 .rollbackFailed, .timedOut, .deviceChanged:
                return false
            }
        }
        if let zte = error as? ZTEUBusError {
            switch zte {
            case .timedOut, .nonHTTPResponse, .interfaceUnavailable, .httpStatus,
                 .invalidResponse:
                return true
            case let .rpc(code, _):
                return code != -32_002
            case .invalidEndpoint, .responseTooLarge, .ubusStatus,
                 .authenticationFailed, .missingSalt, .missingSession:
                return false
            }
        }
        return true
    }

    private func replayableManualRegistration(
        for state: MC7530RawControlState,
        operation: String
    ) throws -> MC7530ManualRegistration? {
        guard state.netSelectMode == "manual_select" else { return nil }
        guard let plmn = Self.normalizedPLMN(state.plmn),
              let knownManualRegistration,
              knownManualRegistration.plmn == plmn,
              Self.registrationRATsByNetSelect[state.netSelect]?
                  .contains(knownManualRegistration.rat) == true
        else {
            throw ModemControlError.invalidState(
                "The MC7530CA does not report the exact RAT token for its current manual operator. Run Scan Networks while that operator is current before \(operation)."
            )
        }
        return knownManualRegistration
    }

    private func reconcileKnownManualRegistration(
        with state: MC7530RawControlState,
        scannedNetworks: [CellularNetwork]? = nil
    ) {
        guard state.netSelectMode == "manual_select",
              let currentPLMN = Self.normalizedPLMN(state.plmn)
        else {
            knownManualRegistration = nil
            return
        }

        if let scannedNetworks {
            // A fresh scan is authoritative even when the PLMN is unchanged:
            // the user may have selected the same operator with a different
            // RAT outside this app. Exactly one current PLMN/RAT row replaces
            // the cache; zero or multiple rows make replay unsafe and clear it.
            let currentRows = scannedNetworks.compactMap {
                network -> MC7530ManualRegistration? in
                guard network.availability == .current,
                      Self.normalizedPLMN(network.plmn) == currentPLMN,
                      let rat = network.selectionToken,
                      Self.acceptedRegistrationRATs.contains(rat),
                      Self.registrationRATsByNetSelect[state.netSelect]?.contains(rat) == true
                else { return nil }
                return MC7530ManualRegistration(plmn: currentPLMN, rat: rat)
            }
            let uniqueRows = Set(currentRows.map { "\($0.plmn)|\($0.rat)" })
            knownManualRegistration = uniqueRows.count == 1 ? currentRows.first : nil
            return
        }

        if knownManualRegistration?.plmn != currentPLMN ||
            knownManualRegistration.map({ registration in
                Self.registrationRATsByNetSelect[state.netSelect]?
                    .contains(registration.rat) != true
            }) == true {
            knownManualRegistration = nil
        }
    }

    private func validateBands(_ bands: Set<Int>, allowed: Set<Int>, radio: String) throws {
        guard !bands.isEmpty else {
            throw ModemControlError.invalidState("Select at least one \(radio) band.")
        }
        let unavailable = bands.subtracting(allowed).sorted()
        guard unavailable.isEmpty else {
            throw ModemControlError.invalidBands(radio: radio, bands: unavailable)
        }
    }

    private func validateDevice() async throws {
        guard !invalidated else { throw ModemControlError.deviceChanged }
        try await validatePhysicalDevice()
    }

    private func validatePhysicalDevice() async throws {
        let current = try await Self.fetchFingerprint(session: session)
        guard current == expectedFingerprint else {
            invalidated = true
            throw ModemControlError.deviceChanged
        }
    }

    static func fetchFingerprint(session: ZTEAuthSession) async throws -> String {
        let payload = try await session.call(
            object: "zwrt_zte_mdm.api",
            method: "get_modem_msn",
            mode: .read,
            zTag: "get_modem_msn"
        )
        let identity = try fingerprintMaterial(from: payload)
        return try fingerprint(modemMSN: identity)
    }

    static func fingerprint(modemMSN: String) throws -> String {
        let identity = modemMSN
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identity.isEmpty else { throw ModemBackendError.identityUnavailable }
        return SHA256.hash(data: Data(identity.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func fingerprintMaterial(from value: ZTEJSONValue) throws -> String {
        guard let candidate = value.objectValue?["modem_msn"]?.stringValue?
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !candidate.isEmpty
        else {
            // The target firmware's get_modem_msn method is verified to expose
            // this exact unique field. Hashing a generic success payload would
            // let two devices share a fingerprint and defeat the write guard.
            throw ModemBackendError.identityUnavailable
        }
        return candidate
    }

    static func parseNetworks(_ contents: String) throws -> [CellularNetwork] {
        var result: [CellularNetwork] = []
        var seen: Set<String> = []
        for rawEntry in contents.split(separator: ";", omittingEmptySubsequences: true) {
            let fields = rawEntry.split(
                separator: ",",
                maxSplits: 3,
                omittingEmptySubsequences: false
            )
            let stateToken = fields[0].trimmingCharacters(in: .whitespacesAndNewlines)
            guard fields.count == 4,
                  mc7530IsASCIIDigits(stateToken),
                  let state = Int(stateToken),
                  let availability = NetworkAvailability(rawValue: state)
            else { continue }
            let name = fields[1]
                .replacingOccurrences(of: "\"", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let plmn = fields[2].trimmingCharacters(in: .whitespacesAndNewlines)
            let rat = fields[3].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let plmn = normalizedPLMN(plmn),
                  mc7530IsASCIIDigits(rat),
                  acceptedRegistrationRATs.contains(rat)
            else { continue }
            let key = plmn + "|" + rat
            guard seen.insert(key).inserted else { continue }
            result.append(CellularNetwork(
                longName: name,
                shortName: name,
                plmn: plmn,
                availability: availability,
                accessTechnologies: [accessTechnology(forRAT: rat)].compactMap { $0 },
                selectionToken: rat
            ))
        }
        guard !result.isEmpty else {
            throw ModemControlError.verificationFailed(
                "MC7530CA returned no usable operator rows after the scan completed."
            )
        }
        return result.sorted {
            if $0.availability.sortOrder != $1.availability.sortOrder {
                return $0.availability.sortOrder < $1.availability.sortOrder
            }
            if $0.plmn != $1.plmn { return $0.plmn < $1.plmn }
            return ($0.selectionToken ?? "") < ($1.selectionToken ?? "")
        }
    }

    private static func accessTechnology(forRAT value: String) -> CellularAccessTechnology? {
        switch value {
        case "0": return .gsm
        case "2": return .umts
        case "7": return .lte
        case "9", "11", "12": return .nr5GC
        case "13": return .lteNRDualConnectivity
        case "14": return .lte5GC
        default: return nil
        }
    }

    private static func normalizedPLMN(_ value: String?) -> String? {
        guard let value else { return nil }
        let token = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (token.count == 5 || token.count == 6), mc7530IsASCIIDigits(token) else {
            return nil
        }
        return token
    }

    private static func persistentConfigurationMatches(
        _ current: MC7530RawControlState,
        _ expected: MC7530RawControlState
    ) -> Bool {
        current.netSelect == expected.netSelect &&
            current.netSelectMode == expected.netSelectMode &&
            current.lteBands == expected.lteBands &&
            current.saBands == expected.saBands &&
            current.nsaBands == expected.nsaBands &&
            current.nrdcBands == expected.nrdcBands &&
            current.gwBandLock.lowercased() == expected.gwBandLock.lowercased() &&
            current.lteCellLock == expected.lteCellLock &&
            current.nrCellLock == expected.nrCellLock
    }

    private static func manualRegistrationMatches(
        _ current: MC7530RawControlState,
        _ registration: MC7530ManualRegistration?
    ) -> Bool {
        guard let registration else { return false }
        return current.netSelectMode == "manual_select" &&
            normalizedPLMN(current.plmn) == registration.plmn &&
            current.operatorSelection.accessTechnology == accessTechnology(forRAT: registration.rat)
    }

    private static func bandCSV(_ bands: Set<Int>) -> String {
        bands.sorted().map(String.init).joined(separator: ",")
    }
}
