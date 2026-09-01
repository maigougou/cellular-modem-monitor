import Foundation

/// Narrow injectable surface used by the verified VOS control session.
/// Keeping transport mechanics behind this protocol makes cancellation,
/// rollback and identity binding testable without an SSH-connected modem.
protocol VOSControlTransport: Sendable {
    func fetchDeviceFingerprint(configuration: DeviceConfiguration) async throws -> String
    func fetchOperatorSelection(configuration: DeviceConfiguration) async throws -> OperatorSelection
    func scanNetworks(configuration: DeviceConfiguration) async throws -> [CellularNetwork]
    func selectNetwork(
        plmn: String,
        configuration: DeviceConfiguration
    ) async throws -> OperatorSelection
    func selectAutomaticNetwork(configuration: DeviceConfiguration) async throws -> OperatorSelection
    func fetchNRSystemSelectionPreferences(
        configuration: DeviceConfiguration
    ) async throws -> NRSystemSelectionPreferences
    func setNRSystemSelectionPreferences(
        modePreference: UInt16,
        saBands: NRBandMask,
        nsaBands: NRBandMask,
        lteBands: LTEBandMask?,
        configuration: DeviceConfiguration
    ) async throws -> NRSystemSelectionPreferences
}

extension VOSClient: VOSControlTransport {}

/// Verified control session for VOS's SSH/AT/QMI implementation.
///
/// All VOS-specific ordering and exact QMI tuple rollback live here rather
/// than in StatusModel, so the UI can drive every modem through one contract.
actor VOSControlSession: ModemControlSession {
    nonisolated let kind = ModemKind.vos5G
    nonisolated let capabilities = ModemCapability.deviceControls
    nonisolated let stableIdentifier: String

    private let client: any VOSControlTransport
    private let configuration: DeviceConfiguration
    private let expectedFingerprint: String
    private var invalidated = false
    private var operationInProgress = false
    private var operationMutationAttempted = false
    private var originalPreferences: NRSystemSelectionPreferences?
    private var activeNRBandLock: Set<Int>?
    private var lastKnownSelection: OperatorSelection?

    private init(
        client: any VOSControlTransport,
        configuration: DeviceConfiguration,
        expectedFingerprint: String
    ) {
        self.client = client
        self.configuration = configuration
        self.expectedFingerprint = expectedFingerprint
        self.stableIdentifier = expectedFingerprint
    }

    static func open(
        client: any VOSControlTransport,
        configuration: DeviceConfiguration
    ) async throws -> VOSControlSession {
        let fingerprint = try await client.fetchDeviceFingerprint(configuration: configuration)
        return VOSControlSession(
            client: client,
            configuration: configuration,
            expectedFingerprint: fingerprint
        )
    }

    func invalidate() async {
        invalidated = true
    }

    func refresh() async throws -> ModemControlState {
        try await validateDevice()
        let selection = try await client.fetchOperatorSelection(configuration: configuration)
        try await validateDevice()
        let preferences = try await client.fetchNRSystemSelectionPreferences(configuration: configuration)
        try await validateDevice()
        lastKnownSelection = selection
        rememberBaselineIfAutomatic(preferences)
        // VOS radio preferences are volatile. A power cycle can preserve the
        // endpoint/fingerprint while restoring the captured tuple; do not keep
        // a stale in-memory band-lock marker and reapply it later.
        if let originalPreferences, preferences == originalPreferences {
            activeNRBandLock = nil
        }
        return state(selection: selection, preferences: preferences)
    }

    func perform(_ command: ModemControlCommand) async throws -> ModemControlResult {
        guard !operationInProgress else {
            throw ModemControlError.invalidState(
                "Another VOS control operation is already in progress."
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
            let preserved = try await preservingCurrentPreferences {
                try await self.validateDevice()
                try self.markMutationAttempt()
                return try await self.client.scanNetworks(configuration: self.configuration)
            }
            let selection = try await client.fetchOperatorSelection(configuration: configuration)
            try await validateDevice()
            lastKnownSelection = selection
            return ModemControlResult(
                state: state(selection: selection, preferences: preserved.preferences),
                scannedNetworks: preserved.value
            )

        case let .selectNetwork(network):
            let applied = try await selectNetwork(network)
            lastKnownSelection = applied.selection
            return ModemControlResult(state: state(
                selection: applied.selection,
                preferences: applied.preferences
            ))

        case .selectAutomaticNetwork:
            let applied = try await selectAutomaticNetwork()
            lastKnownSelection = applied.selection
            return ModemControlResult(state: state(
                selection: applied.selection,
                preferences: applied.preferences
            ))

        case let .setArchitecture(mode):
            let preferences = try await setArchitecture(mode)
            return ModemControlResult(state: state(
                selection: lastKnownSelection,
                preferences: preferences
            ))

        case let .lockNRBands(bands):
            let preferences = try await lockNRBands(bands)
            return ModemControlResult(state: state(
                selection: lastKnownSelection,
                preferences: preferences
            ))

        case let .lockLTEBands(bands):
            let preferences = try await lockLTEBands(bands)
            return ModemControlResult(state: state(
                selection: lastKnownSelection,
                preferences: preferences
            ))

        case .restoreDefaults:
            let restored = try await restoreDefaults()
            lastKnownSelection = restored.selection
            return ModemControlResult(state: state(
                selection: restored.selection,
                preferences: restored.preferences
            ))
        }
    }

    private func selectNetwork(
        _ network: CellularNetwork
    ) async throws -> (selection: OperatorSelection, preferences: NRSystemSelectionPreferences) {
        do {
            let preserved = try await preservingCurrentPreferences {
                try await self.validateDevice()
                try self.markMutationAttempt()
                return try await self.client.selectNetwork(
                    plmn: network.plmn,
                    configuration: self.configuration
                )
            }
            let final = try await client.fetchOperatorSelection(configuration: configuration)
            guard final.mode == .manual, final.plmn == network.plmn else {
                throw VOSClientError.verificationFailed(
                    "Manual selection did not remain active after restoring the radio preference."
                )
            }
            try await validateDevice()
            return (final, preserved.preferences)
        } catch {
            let manualFailure = error
            guard operationMutationAttempted else { throw manualFailure }
            do {
                try await recoverAutomaticOperatorUncancelled()
            } catch {
                if error as? ModemControlError == .deviceChanged { throw error }
                throw VOSClientError.verificationFailed(
                    "\(manualFailure.localizedDescription) Automatic operator recovery could not be verified: \(error.localizedDescription) The state is unknown."
                )
            }
            // The manual write may already have reached the modem. Complete
            // and verify automatic recovery first, then preserve cancellation
            // as a non-user-facing interruption for StatusModel.
            if manualFailure is CancellationError {
                throw CancellationError()
            }
            throw VOSClientError.verificationFailed(
                "\(manualFailure.localizedDescription) Automatic operator selection was restored and verified."
            )
        }
    }

    private func selectAutomaticNetwork(
    ) async throws -> (selection: OperatorSelection, preferences: NRSystemSelectionPreferences) {
        let preserved = try await preservingCurrentPreferences {
            try await self.validateDevice()
            try self.markMutationAttempt()
            return try await self.client.selectAutomaticNetwork(configuration: self.configuration)
        }
        let final = try await client.fetchOperatorSelection(configuration: configuration)
        guard final.mode == .automatic else {
            throw VOSClientError.verificationFailed(
                "Automatic operator selection did not remain active after restoring the radio preference; state is unknown."
            )
        }
        try await validateDevice()
        return (final, preserved.preferences)
    }

    private func setArchitecture(
        _ mode: NRArchitectureMode
    ) async throws -> NRSystemSelectionPreferences {
        guard mode != .unavailable else {
            throw VOSClientError.verificationFailed("Radio access preference control is unavailable.")
        }
        let previous = try await client.fetchNRSystemSelectionPreferences(configuration: configuration)
        let plan = try targetPreferences(for: mode, current: previous)
        guard let modePreference = plan.target.modePreference else {
            throw VOSClientError.verificationFailed("Qualcomm NAS did not report a mode preference to preserve.")
        }
        do {
            try await validateDevice()
            try markMutationAttempt()
            let verified = try await client.setNRSystemSelectionPreferences(
                modePreference: modePreference,
                saBands: plan.target.saBands,
                nsaBands: plan.target.nsaBands,
                lteBands: plan.lteBandsToWrite,
                configuration: configuration
            )
            try await validateDevice()
            return verified
        } catch {
            guard operationMutationAttempted else { throw error }
            if let rollback = try await runRollbackUncancelled(previous) {
                throw VOSClientError.verificationFailed(
                    "\(error.localizedDescription) Automatic rollback also failed: \(rollback). Power-cycle VOS to restore its temporary radio preferences."
                )
            }
            throw error
        }
    }

    private func lockNRBands(_ bands: Set<Int>) async throws -> NRSystemSelectionPreferences {
        guard !bands.isEmpty, let requested = NRBandMask(bands: bands) else {
            throw VOSClientError.verificationFailed("Enter one or more valid NR bands, for example 77,78.")
        }
        let previous = try await client.fetchNRSystemSelectionPreferences(configuration: configuration)
        rememberBaselineIfAutomatic(previous)
        guard let baseline = originalPreferences,
              let modePreference = previous.modePreference else {
            throw VOSClientError.verificationFailed(
                "The original band masks were not captured. Power-cycle VOS, then reopen Network & radio controls."
            )
        }
        let plan = try NRBandLockPlan.make(
            requested: requested,
            baseline: baseline,
            architecture: previous.architectureMode
        )
        do {
            try await validateDevice()
            try markMutationAttempt()
            let verified = try await client.setNRSystemSelectionPreferences(
                modePreference: modePreference,
                saBands: plan.saBands,
                nsaBands: plan.nsaBands,
                lteBands: nil,
                configuration: configuration
            )
            try await validateDevice()
            activeNRBandLock = bands
            return verified
        } catch {
            guard operationMutationAttempted else { throw error }
            if let rollback = try await runRollbackUncancelled(previous) {
                throw VOSClientError.verificationFailed(
                    "\(error.localizedDescription) Rollback also failed: \(rollback). Power-cycle VOS."
                )
            }
            throw error
        }
    }

    private func lockLTEBands(_ bands: Set<Int>) async throws -> NRSystemSelectionPreferences {
        guard !bands.isEmpty, let requested = LTEBandMask(bands: bands) else {
            throw VOSClientError.verificationFailed("Enter one or more valid LTE bands, for example 2,4,25,66.")
        }
        let previous = try await client.fetchNRSystemSelectionPreferences(configuration: configuration)
        rememberBaselineIfAutomatic(previous)
        guard let baseline = originalPreferences?.lteBands,
              let previousLTE = previous.lteBands,
              let modePreference = previous.modePreference else {
            throw VOSClientError.verificationFailed("Qualcomm NAS did not report an extended LTE band mask to preserve.")
        }
        let target = baseline.intersecting(requested)
        let unavailable = bands.subtracting(Set(target.enabledBands)).sorted()
        guard unavailable.isEmpty else {
            throw VOSClientError.verificationFailed(
                "These LTE bands are not enabled by the captured modem defaults: \(unavailable.map(String.init).joined(separator: ", "))."
            )
        }
        do {
            try await validateDevice()
            try markMutationAttempt()
            let verified = try await client.setNRSystemSelectionPreferences(
                modePreference: modePreference,
                saBands: previous.saBands,
                nsaBands: previous.nsaBands,
                lteBands: target,
                configuration: configuration
            )
            try await validateDevice()
            return verified
        } catch {
            guard operationMutationAttempted else { throw error }
            var rollbackState = previous
            rollbackState.lteBands = previousLTE
            if let rollback = try await runRollbackUncancelled(rollbackState) {
                throw VOSClientError.verificationFailed(
                    "\(error.localizedDescription) Rollback also failed: \(rollback). Power-cycle VOS."
                )
            }
            throw error
        }
    }

    private func restoreDefaults(
    ) async throws -> (selection: OperatorSelection, preferences: NRSystemSelectionPreferences) {
        guard let original = originalPreferences,
              let modePreference = original.modePreference else {
            throw VOSClientError.verificationFailed(
                "No automatic radio baseline is available for this physical VOS. Power-cycle it, then reopen this panel to capture its defaults."
            )
        }

        do {
            return try await restoreDefaultsSequence(
                original: original,
                modePreference: modePreference
            )
        } catch is CancellationError {
            guard operationMutationAttempted else { throw CancellationError() }
            // A cancellation after either write cannot leave a half-restored
            // tuple. Finish both idempotent restore steps in a fresh task and
            // verify the final state before reporting cancellation upstream.
            let cleanup = Task {
                try await self.restoreDefaultsSequence(
                    original: original,
                    modePreference: modePreference
                )
            }
            do {
                let restored = try await cleanup.value
                lastKnownSelection = restored.selection
            } catch {
                if error as? ModemControlError == .deviceChanged { throw error }
                throw VOSClientError.verificationFailed(
                    "The restore operation was cancelled after a write was attempted, and completing the restore could not be verified: \(error.localizedDescription) The modem control state is unknown."
                )
            }
            throw CancellationError()
        }
    }

    private func restoreDefaultsSequence(
        original: NRSystemSelectionPreferences,
        modePreference: UInt16
    ) async throws -> (selection: OperatorSelection, preferences: NRSystemSelectionPreferences) {
        var failures: [String] = []
        var restoredSelection: OperatorSelection?
        var restoredPreferences: NRSystemSelectionPreferences?
        do {
            try await validateDevice()
            try markMutationAttempt()
            restoredSelection = try await client.selectAutomaticNetwork(configuration: configuration)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            guard !invalidated else { throw error }
            failures.append("operator selection: \(error.localizedDescription)")
        }
        do {
            try await validateDevice()
            try markMutationAttempt()
            restoredPreferences = try await client.setNRSystemSelectionPreferences(
                modePreference: modePreference,
                saBands: original.saBands,
                nsaBands: original.nsaBands,
                lteBands: original.lteBands,
                configuration: configuration
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            guard !invalidated else { throw error }
            failures.append("radio preference: \(error.localizedDescription)")
        }
        guard failures.isEmpty else {
            throw VOSClientError.verificationFailed(failures.joined(separator: "; "))
        }
        guard restoredSelection != nil, let restoredPreferences else {
            throw VOSClientError.verificationFailed("The restored VOS state is incomplete.")
        }
        let finalSelection = try await client.fetchOperatorSelection(configuration: configuration)
        guard finalSelection.mode == .automatic else {
            throw VOSClientError.verificationFailed(
                "The original radio tuple was restored, but final automatic operator selection could not be verified."
            )
        }
        try await validateDevice()
        activeNRBandLock = nil
        return (finalSelection, restoredPreferences)
    }

    private func targetPreferences(
        for mode: NRArchitectureMode,
        current: NRSystemSelectionPreferences
    ) throws -> RadioAccessPreferencePlan {
        rememberBaselineIfAutomatic(current)
        guard let original = originalPreferences,
              original.modePreference != nil else {
            throw VOSClientError.verificationFailed(
                "The original automatic radio masks were not captured. Power-cycle VOS, then open Network & radio controls before changing the mode."
            )
        }
        return try RadioAccessPreferencePlan.make(
            mode: mode,
            baseline: original,
            current: current,
            activeNRBandLock: activeNRBandLock
        )
    }

    private func preservingCurrentPreferences<T: Sendable>(
        operation: () async throws -> T
    ) async throws -> (value: T, preferences: NRSystemSelectionPreferences) {
        let previous = try await client.fetchNRSystemSelectionPreferences(configuration: configuration)
        let result: T
        do {
            result = try await operation()
        } catch {
            guard operationMutationAttempted else { throw error }
            if let rollback = try await runRollbackUncancelled(previous) {
                throw VOSClientError.verificationFailed(
                    "\(error.localizedDescription) Restoring the pre-operation radio preference also failed: \(rollback). Power-cycle VOS before another control operation."
                )
            }
            throw error
        }
        if let rollback = try await runRollbackUncancelled(previous) {
            throw VOSClientError.verificationFailed(
                "The operator operation was verified, but restoring its pre-operation radio preference failed: \(rollback). Power-cycle VOS before another control operation."
            )
        }
        return (result, previous)
    }

    private func rollback(_ previous: NRSystemSelectionPreferences) async throws -> String? {
        guard let modePreference = previous.modePreference else {
            return "the pre-operation preference tuple is incomplete"
        }
        do {
            try await validatePhysicalDevice()
            _ = try await client.setNRSystemSelectionPreferences(
                modePreference: modePreference,
                saBands: previous.saBands,
                nsaBands: previous.nsaBands,
                lteBands: previous.lteBands,
                configuration: configuration
            )
            try await validatePhysicalDevice()
            return nil
        } catch {
            if error as? ModemControlError == .deviceChanged { throw error }
            return error.localizedDescription
        }
    }

    private func runRollbackUncancelled(
        _ previous: NRSystemSelectionPreferences
    ) async throws -> String? {
        let cleanup = Task { try await self.rollback(previous) }
        return try await cleanup.value
    }

    private func recoverAutomaticOperatorUncancelled() async throws {
        let cleanup = Task { try await self.recoverAutomaticOperator() }
        try await cleanup.value
    }

    private func recoverAutomaticOperator() async throws {
        let previous = try await client.fetchNRSystemSelectionPreferences(
            configuration: configuration
        )
        try await validatePhysicalDevice()
        _ = try await client.selectAutomaticNetwork(configuration: configuration)
        if let rollback = try await self.rollback(previous) {
            throw VOSClientError.verificationFailed(
                "Automatic operator recovery changed the radio tuple and restoring it failed: \(rollback)."
            )
        }
        let final = try await client.fetchOperatorSelection(configuration: configuration)
        guard final.mode == .automatic else {
            throw VOSClientError.verificationFailed(
                "Automatic operator recovery was not confirmed."
            )
        }
        try await validatePhysicalDevice()
        lastKnownSelection = final
    }

    private func markMutationAttempt() throws {
        guard !invalidated else { throw ModemControlError.deviceChanged }
        try Task.checkCancellation()
        operationMutationAttempted = true
    }

    private func validateDevice() async throws {
        guard !invalidated else { throw ModemControlError.deviceChanged }
        try await validatePhysicalDevice()
    }

    private func validatePhysicalDevice() async throws {
        let current = try await client.fetchDeviceFingerprint(configuration: configuration)
        guard current == expectedFingerprint else {
            invalidated = true
            throw ModemControlError.deviceChanged
        }
    }

    private func rememberBaselineIfAutomatic(_ preferences: NRSystemSelectionPreferences) {
        guard originalPreferences == nil,
              preferences.architectureMode == .automatic,
              preferences.modePreference != nil else { return }
        originalPreferences = preferences
    }

    private func state(
        selection: OperatorSelection?,
        preferences: NRSystemSelectionPreferences
    ) -> ModemControlState {
        ModemControlState(
            operatorSelection: selection,
            architecture: preferences.architectureMode,
            saBands: Set(preferences.saBands.enabledBands),
            nsaBands: Set(preferences.nsaBands.enabledBands),
            lteBands: Set(preferences.lteBands?.enabledBands ?? []),
            canRestoreDefaults: originalPreferences != nil,
            preferenceLifetime: .untilPowerLoss
        )
    }
}
