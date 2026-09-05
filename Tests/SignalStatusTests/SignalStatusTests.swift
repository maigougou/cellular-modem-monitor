import XCTest
@testable import SignalStatus

final class SignalStatusTests: XCTestCase {
    func testEfficiencyWithoutLosingFreshnessOrInterfaceBinding() async {
        let failures = await EfficiencyRegression.run()
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }

    private let lteBand = "02010031002400020400000000000106000108790084031108000108790084030000120600010805000000"
    private let nrAndLTE = "0201003100270002040000000000110f00020c0d0180ac090008790084030000120b00020c0d0000000805000000"
    private let nrCAAndLTE = "0201003100330002040000000000111600030c0c0160c609000c0c0180ac090008790084030000121000030c0d0000000c0b0000000805000000"
    private let noActiveBand = "0201003100070002040000000000"
    private let dsdNSA = "02010024001b000204000000000010110001000000000600000000000000000a0000"
    private let dsdSA = "02010024001b00020400000000001011000100000000060000000000000000120000"
    private let dsdLTE = "02010024001b00020400000000001011000100000000030000000010000000000000"
    private let signal = "0202004f001c0002040000000000140600b7f394ff2e00170400acff7b00180200f5ff"
    private let signalSentinels = "0202004f001c0002040000000000140600b7f394ff2e00170400008000801802000080"
    private let ca = "020100ac00360002040000000000130a00df008403050000007900151f000229000208050000007b0002000000012a00c0210300000094000100000002"
    private let legacyCA = "020100ac00290002040000000000130a00df008403050000007900120e0011000208050000007b000200000014010003"
    private let legacyNoCA = "020100ac00180002040000000000120e0000000000ff000000780000000000"
    private let telusPLMNName = "020700440029000204000000000010140000000000000554454c55530000000554454c55531504000400000016010000"
    private let nrCellLocation = "02050043002700020400000000002e0400dea206002f1600030222010203785634120000000029006affa0fbf1ff"
    private let nrCACellLocation = "02050043002700020400000000002e040080ac09002f1600030222010203785634120000000029006affa0fbf1ff"

    func testAppLanguageDefaultsToChineseForChineseSystemLanguages() {
        XCTAssertEqual(AppLanguage.systemDefault(preferredLanguages: ["zh-Hans-CN", "en-CA"]), .simplifiedChinese)
        XCTAssertEqual(AppLanguage.systemDefault(preferredLanguages: ["zh-Hant-TW"]), .simplifiedChinese)
        XCTAssertEqual(AppLanguage.systemDefault(preferredLanguages: ["ZH-cn"]), .simplifiedChinese)
    }

    func testCarrierStateUsesInactiveForConfiguredDeactivatedCells() {
        XCTAssertEqual(RadioCarrierState.configured.label, "Inactive")
        XCTAssertEqual(
            RadioCarrierState.configured.localizedLabel(language: .simplifiedChinese),
            "未激活"
        )
    }

    func testQuickArchitectureMenuOrderAndCompactLabels() {
        XCTAssertEqual(
            NRArchitectureMode.quickAccessModes,
            [.automatic, .saOnly, .nsaOnly, .lteOnly]
        )
        XCTAssertEqual(
            NRArchitectureMode.quickAccessModes.map(\.compactLabel),
            ["Auto", "SA", "NSA", "LTE"]
        )
        XCTAssertEqual(
            NRArchitectureMode.quickAccessModes.map(\.label),
            ["Auto SA/NSA", "SA only", "NSA only", "LTE only"]
        )
    }

    func testQuickArchitectureTitleRemainsVisibleThroughoutModeChange() {
        let phases: [(NRArchitectureMode?, NetworkControlOperation?, String, Bool)] = [
            (nil, .loading, "—", true),
            (.automatic, nil, "Auto SA/NSA", false),
            (.automatic, .changingArchitecture(.saOnly), "SA only…", true),
            (.saOnly, .changingArchitecture(.saOnly), "SA only…", true),
            (.saOnly, nil, "SA only", false),
            (.saOnly, .loading, "SA only", true),
            (.saOnly, .changingArchitecture(.automatic), "Auto SA/NSA…", true),
            (.saOnly, nil, "SA only", false), // rollback must not keep the requested Auto label
            (.automatic, nil, "Auto SA/NSA", false),
            (.nsaOnly, nil, "NSA only", false),
            (.lteOnly, nil, "LTE only", false),
            (nil, nil, "—", false)
        ]
        for (mode, operation, title, busy) in phases {
            let state = QuickArchitectureMenuState(confirmedMode: mode, operation: operation)
            XCTAssertEqual(state.title, title)
            XCTAssertEqual(state.isBusy, busy)
        }
    }

    @MainActor
    func testPanelWidthPersistsImmediatelyAndInvalidValueUsesStandard() {
        let suiteName = "SignalStatusTests.panel-width.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        @MainActor func model() -> StatusModel {
            StatusModel(defaults: defaults, credentialStore: EmptyTestCredentialStore(), demoSnapshot: .empty)
        }
        let first = model()
        XCTAssertEqual(first.panelWidth, .standard)
        first.panelWidth = .wide
        XCTAssertEqual(model().panelWidth, .wide)
        defaults.set("unknown-width", forKey: "panelWidth")
        XCTAssertEqual(model().panelWidth, .standard)
        XCTAssertEqual(PanelWidth.allCases.map(\.points), [360, 420, 480])
    }

    func testCarrierAggregationPresentationFormatting() {
        XCTAssertEqual(
            CarrierAggregationFormatting.summary(for: [
                CarrierAggregationSummaryItem(band: "n77", bandwidthMHz: 50)
            ]),
            "n77 · 50 MHz"
        )
        XCTAssertEqual(
            CarrierAggregationFormatting.summary(for: [
                CarrierAggregationSummaryItem(band: "B7", bandwidthMHz: 20)
            ]),
            "B7 · 20 MHz"
        )
        XCTAssertEqual(
            CarrierAggregationFormatting.summary(for: [
                CarrierAggregationSummaryItem(band: "n77", bandwidthMHz: 50),
                CarrierAggregationSummaryItem(band: "n66", bandwidthMHz: 30),
                CarrierAggregationSummaryItem(band: "n71", bandwidthMHz: 10),
                CarrierAggregationSummaryItem(band: "n77", bandwidthMHz: 30)
            ]),
            "4CC · 120 MHz"
        )
        XCTAssertEqual(
            CarrierCellReference.resolve(globalCellID: 12_345, physicalCellID: 203),
            .global(12_345)
        )
        XCTAssertEqual(
            CarrierCellReference.resolve(globalCellID: nil, physicalCellID: 203),
            .physical(203)
        )
        XCTAssertEqual(
            CarrierCellReference.resolve(globalCellID: nil, physicalCellID: nil),
            .unavailable
        )
    }

    func testAppLanguageDefaultsToEnglishForOtherOrMissingSystemLanguages() {
        XCTAssertEqual(AppLanguage.systemDefault(preferredLanguages: ["en-CA", "zh-Hans-CN"]), .english)
        XCTAssertEqual(AppLanguage.systemDefault(preferredLanguages: ["fr-CA"]), .english)
        XCTAssertEqual(AppLanguage.systemDefault(preferredLanguages: []), .english)
    }

    func testSavedLanguageOverridesTheSystemDefault() {
        XCTAssertEqual(
            AppLanguage.resolved(storedValue: AppLanguage.english.rawValue, preferredLanguages: ["zh-Hans"]),
            .english
        )
        XCTAssertEqual(
            AppLanguage.resolved(storedValue: AppLanguage.simplifiedChinese.rawValue, preferredLanguages: ["en-CA"]),
            .simplifiedChinese
        )
        XCTAssertEqual(
            AppLanguage.resolved(storedValue: "invalid", preferredLanguages: ["zh-Hant"]),
            .simplifiedChinese
        )
    }

    func testLocalizedTextFormattingAndFallback() {
        XCTAssertEqual(L10n.text("Online", language: .simplifiedChinese), "在线")
        XCTAssertEqual(L10n.text("Online", language: .english), "Online")
        XCTAssertEqual(L10n.text("Expanded", language: .simplifiedChinese), "已展开")
        XCTAssertEqual(L10n.text("Collapse section", language: .simplifiedChinese), "折叠此部分")
        XCTAssertEqual(
            SpeedTestError.noActiveModem.localizedMessage(language: .simplifiedChinese),
            "没有可用于测速的活动调制解调器。"
        )
        XCTAssertEqual(L10n.text("Unmapped technical value", language: .simplifiedChinese), "Unmapped technical value")
        XCTAssertEqual(
            L10n.format("Selecting %@…", language: .simplifiedChinese, "302-220"),
            "正在选择 302-220…"
        )
        XCTAssertEqual(
            NetworkControlOperation.changingArchitecture(.saOnly)
                .localizedLabel(language: .simplifiedChinese),
            "正在应用 仅 SA…"
        )
        XCTAssertEqual(NRArchitectureMode.lteOnly.localizedLabel(language: .simplifiedChinese), "仅 LTE")
    }

    func testNeighborMeasurementsExposeDeviceControlSurface() {
        XCTAssertTrue(ModemCapability.neighborMeasurements.supportsDeviceControlSurface)
        XCTAssertFalse(ModemCapability.neighborMeasurements.supportsControlSession)
        XCTAssertTrue(ModemCapability.networkScan.supportsControlSession)
        XCTAssertFalse(ModemCapability.statusRead.supportsDeviceControlSurface)
    }

    func testControlPresentationInvalidationDistinguishesPLMNFromModemChanges() {
        let endpointA = ScopedEndpoint(
            baseURL: URL(string: "http://192.168.254.1")!,
            interfaceName: "en8",
            interfaceIndex: 8,
            sourceAddress: "192.168.254.2"
        )
        let endpointB = ScopedEndpoint(
            baseURL: URL(string: "http://192.168.254.1")!,
            interfaceName: "en9",
            interfaceIndex: 9,
            sourceAddress: "192.168.254.3",
            connectionPath: .routed,
            gateway: "192.168.8.1"
        )
        XCTAssertEqual(
            ControlPresentationInvalidation.transition(
                previousModemID: "modem-a",
                nextModemID: "modem-a",
                previousEndpoint: endpointA,
                nextEndpoint: endpointA,
                previousPLMN: "00101",
                nextPLMN: "00102"
            ),
            .operatorContext
        )
        XCTAssertEqual(
            ControlPresentationInvalidation.transition(
                previousModemID: "modem-a",
                nextModemID: "modem-b",
                previousEndpoint: endpointA,
                nextEndpoint: endpointA,
                previousPLMN: "00101",
                nextPLMN: "00101"
            ),
            .all
        )
        XCTAssertEqual(
            ControlPresentationInvalidation.transition(
                previousModemID: "modem-a",
                nextModemID: "modem-a",
                previousEndpoint: endpointA,
                nextEndpoint: endpointA,
                previousPLMN: "00101",
                nextPLMN: "00101"
            ),
            .none
        )
        XCTAssertEqual(
            ControlPresentationInvalidation.transition(
                previousModemID: "modem-a",
                nextModemID: "modem-a",
                previousEndpoint: endpointA,
                nextEndpoint: endpointB,
                previousPLMN: "00101",
                nextPLMN: "00101"
            ),
            .all
        )
    }

    func testOnlyTrueTaskCancellationIsSilentlyIgnored() {
        XCTAssertTrue(ModemOperationInterruption.isCancellation(CancellationError()))
        XCTAssertFalse(ModemOperationInterruption.isCancellation(
            ModemControlError.commandRejected("fixture")
        ))
        XCTAssertTrue(ModemOperationInterruption.shouldIgnoreRefreshFailure(
            ModemCoordinatorError.noMatchingModem,
            taskIsCancelled: true
        ))
        XCTAssertFalse(ModemOperationInterruption.shouldIgnoreRefreshFailure(
            ModemControlError.rollbackFailed(operation: "fixture", rollback: "fixture"),
            taskIsCancelled: false
        ))
    }

    func testPLMNChangeClearsOnlyOperatorFromVerifiedControlState() {
        let selection = OperatorSelection(
            mode: .manual,
            operatorName: "Fixture",
            plmn: "00101",
            accessTechnology: .lte5GC
        )
        let state = ModemControlState(
            operatorSelection: selection,
            architecture: .nsaOnly,
            saBands: [77],
            nsaBands: [66, 77],
            lteBands: [2, 4, 66],
            availableNRBands: [5, 66, 77],
            availableLTEBands: [2, 4, 5, 66],
            canRestoreDefaults: true,
            preferenceLifetime: .persistent
        )

        let updated = state.clearingOperatorSelection()

        XCTAssertNil(updated.operatorSelection)
        XCTAssertEqual(updated.architecture, state.architecture)
        XCTAssertEqual(updated.saBands, state.saBands)
        XCTAssertEqual(updated.nsaBands, state.nsaBands)
        XCTAssertEqual(updated.lteBands, state.lteBands)
        XCTAssertEqual(updated.availableNRBands, state.availableNRBands)
        XCTAssertEqual(updated.availableLTEBands, state.availableLTEBands)
        XCTAssertEqual(updated.canRestoreDefaults, state.canRestoreDefaults)
        XCTAssertEqual(updated.preferenceLifetime, state.preferenceLifetime)
    }

    func testBandSelectionDraftSurvivesPollingAndCommitsOnMatchingReadback() {
        var state = ModemControlState(
            operatorSelection: nil,
            architecture: .nsaOnly,
            saBands: [77],
            nsaBands: [66, 77],
            lteBands: [2, 4, 66],
            availableNRBands: [5, 66, 77],
            availableLTEBands: [2, 4, 5, 66],
            canRestoreDefaults: true,
            preferenceLifetime: .persistent
        )
        var draft = ModemBandSelectionDraft()
        draft.synchronize(with: state)
        draft.toggleNR(66)
        draft.toggleLTE(4)

        draft.synchronize(with: state)
        XCTAssertEqual(draft.nrBands, [77])
        XCTAssertEqual(draft.lteBands, [2, 66])
        XCTAssertTrue(draft.isNRDirty)
        XCTAssertTrue(draft.isLTEDirty)

        state.nsaBands = [77]
        state.lteBands = [2, 66]
        draft.synchronize(with: state)
        XCTAssertFalse(draft.isNRDirty)
        XCTAssertFalse(draft.isLTEDirty)
    }

    @MainActor
    func testApplyingAuthoritativeControlStateClearsStaleOperatorSelection() {
        let suiteName = "SignalStatusTests.control-result.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let previousDemo = ProcessInfo.processInfo.environment["SIGNAL_STATUS_DEMO"]
        setenv("SIGNAL_STATUS_DEMO", "1", 1)
        defer {
            if let previousDemo {
                setenv("SIGNAL_STATUS_DEMO", previousDemo, 1)
            } else {
                unsetenv("SIGNAL_STATUS_DEMO")
            }
        }

        let model = StatusModel(
            defaults: defaults,
            credentialStore: EmptyTestCredentialStore()
        )
        let selected = OperatorSelection(
            mode: .manual,
            operatorName: "Fixture",
            plmn: "00101",
            accessTechnology: .lte5GC
        )
        let radioState = ModemControlState(
            operatorSelection: selected,
            architecture: .nsaOnly,
            saBands: [77],
            nsaBands: [66, 77],
            lteBands: [2, 4, 66],
            canRestoreDefaults: true,
            preferenceLifetime: .persistent
        )

        model.applyControlResult(ModemControlResult(state: radioState))
        XCTAssertEqual(model.operatorSelection, selected)

        model.applyControlResult(ModemControlResult(
            state: radioState.clearingOperatorSelection()
        ))
        XCTAssertNil(model.operatorSelection)
        XCTAssertNil(model.controlState?.operatorSelection)
        XCTAssertEqual(model.controlState?.architecture, .nsaOnly)
        XCTAssertTrue(model.controlState?.canRestoreDefaults == true)
    }

    func testRollbackFailureMessageSeparatesRecoveryDetail() {
        XCTAssertEqual(
            ModemControlError.rollbackFailed(
                operation: "Band update failed.",
                rollback: "Reset was rejected"
            ).errorDescription,
            "Band update failed. Automatic rollback also failed: Reset was rejected. The modem control state is unknown."
        )
        XCTAssertEqual(
            ModemControlError.rollbackFailed(
                operation: "Band update failed.",
                rollback: "Reset timed out!"
            ).errorDescription,
            "Band update failed. Automatic rollback also failed: Reset timed out! The modem control state is unknown."
        )
        XCTAssertEqual(
            ModemControlError.rollbackFailed(
                operation: "Band update failed.",
                rollback: ""
            ).errorDescription,
            "Band update failed. Automatic rollback also failed: No rollback detail was reported. The modem control state is unknown."
        )
    }

    func testLanguageDisplayNamesAndLocales() {
        XCTAssertEqual(AppLanguage.english.displayName, "English")
        XCTAssertEqual(AppLanguage.simplifiedChinese.displayName, "简体中文")
        XCTAssertEqual(AppLanguage.english.locale.identifier, "en")
        XCTAssertEqual(AppLanguage.simplifiedChinese.locale.identifier, "zh-Hans")
    }

    func testControlOperationDeviceGuardCannotRebindOrResumeAfterHotSwap() throws {
        let operationGuard = ControlOperationDeviceGuard(expectedFingerprint: "device-a")

        XCTAssertNoThrow(try operationGuard.validate(currentFingerprint: "device-a"))
        XCTAssertTrue(operationGuard.isValid)

        XCTAssertThrowsError(try operationGuard.validate(currentFingerprint: "device-b")) { error in
            XCTAssertEqual(error as? ControlOperationDeviceGuardError, .deviceChanged)
        }
        XCTAssertFalse(operationGuard.isValid)
        XCTAssertEqual(operationGuard.expectedFingerprint, "device-a")

        XCTAssertThrowsError(try operationGuard.validate(currentFingerprint: "device-a")) { error in
            XCTAssertEqual(error as? ControlOperationDeviceGuardError, .deviceChanged)
        }
        XCTAssertFalse(operationGuard.isValid)
    }

    func testPollingUsesConfiguredIntervalOnlineAndFastRetryOtherwise() {
        XCTAssertEqual(
            StatusPollingPolicy.interval(userInterval: 30, connectionState: .online),
            30
        )
        for state in [
            ConnectionState.connecting,
            .stale,
            .disconnected,
            .authenticationFailed,
            .qmiUnavailable
        ] {
            XCTAssertEqual(
                StatusPollingPolicy.interval(userInterval: 60, connectionState: state),
                5
            )
            XCTAssertEqual(
                StatusPollingPolicy.interval(userInterval: 1, connectionState: state),
                1,
                "Reconnect polling must not be slower than the selected interval"
            )
        }
    }

    func testRefreshCoalescerRetainsInFlightAndControlBusyRequests() {
        var coalescer = RefreshCoalescer()
        XCTAssertTrue(coalescer.request(isRefreshing: false, isControlBusy: false))

        coalescer.beginRefresh()
        XCTAssertFalse(coalescer.request(isRefreshing: true, isControlBusy: false))
        XCTAssertTrue(coalescer.isPending)
        XCTAssertTrue(coalescer.shouldDrain(isRefreshing: false, isControlBusy: false))

        coalescer.beginRefresh()
        XCTAssertFalse(coalescer.request(isRefreshing: false, isControlBusy: true))
        XCTAssertTrue(coalescer.isPending)
        XCTAssertFalse(coalescer.shouldDrain(isRefreshing: false, isControlBusy: true))
        XCTAssertTrue(coalescer.shouldDrain(isRefreshing: false, isControlBusy: false))
    }

    func testVOSInterfaceSelectionPrefersActiveRouteAndRejectsStaleInterface() {
        let candidates = [
            LocalInterfaceCandidate(name: "en12", address: "192.168.225.10", isActive: false),
            LocalInterfaceCandidate(name: "en13", address: "10.0.0.2", isActive: true),
            LocalInterfaceCandidate(name: "en14", address: "192.168.225.20", isActive: true),
            LocalInterfaceCandidate(name: "en15", address: "192.168.225.30", isActive: true)
        ]

        XCTAssertEqual(
            LocalInterface.selectVOSInterface(
                candidates: candidates,
                routedSourceAddress: "192.168.225.30"
            ),
            candidates[3]
        )
        XCTAssertEqual(
            LocalInterface.selectVOSInterface(
                candidates: candidates,
                routedSourceAddress: "192.168.225.10"
            ),
            candidates[3]
        )
        XCTAssertEqual(
            LocalInterface.selectVOSInterface(
                candidates: candidates,
                routedSourceAddress: nil
            ),
            candidates[3]
        )
    }

    func testDiscoveryBuildsScopedCandidateForDirectUSBECM() throws {
        let topology = NetworkTopologySnapshot(interfaces: [discoveryInterface(
            name: "en8",
            index: 18,
            address: "192.168.254.20",
            prefixLength: 24,
            router: "192.168.254.1"
        )])

        let candidate = try XCTUnwrap(ModemCandidateGenerator().candidates(
            topology: topology,
            allowedKinds: [.zteMC7530CA]
        ).first)

        XCTAssertEqual(candidate.key.host, "192.168.254.1")
        XCTAssertEqual(candidate.key.interfaceIndex, 18)
        XCTAssertEqual(candidate.endpoint.interfaceName, "en8")
        XCTAssertEqual(candidate.endpoint.sourceAddress, "192.168.254.20")
        XCTAssertEqual(candidate.endpoint.gateway, "192.168.254.1")
        XCTAssertEqual(candidate.endpoint.connectionPath, .unknown)
        XCTAssertTrue(candidate.sources.contains(.matchingSubnet))
        XCTAssertTrue(candidate.sources.contains(.matchingGateway))
    }

    func testDiscoveryBuildsScopedCandidateForDirectRJ45() throws {
        let topology = NetworkTopologySnapshot(interfaces: [discoveryInterface(
            name: "en5",
            index: 12,
            address: "192.168.254.30",
            prefixLength: 24,
            router: "192.168.254.1"
        )])

        let candidate = try XCTUnwrap(ModemCandidateGenerator().candidates(
            topology: topology,
            allowedKinds: [.zteMC7530CA]
        ).first)

        XCTAssertEqual(candidate.key.interfaceIndex, 12)
        XCTAssertEqual(candidate.endpoint.interfaceName, "en5")
        XCTAssertEqual(candidate.endpoint.sourceAddress, "192.168.254.30")
        XCTAssertEqual(candidate.endpoint.connectionPath, .unknown)
        XCTAssertTrue(candidate.sources.contains(.matchingSubnet))
    }

    func testDiscoveryMarksZTEBehindRouterAsRouted() throws {
        let topology = NetworkTopologySnapshot(interfaces: [discoveryInterface(
            name: "en1",
            index: 6,
            address: "192.168.8.23",
            prefixLength: 24,
            router: "192.168.8.1",
            isPrimary: true
        )])

        let candidate = try XCTUnwrap(ModemCandidateGenerator().candidates(
            topology: topology,
            allowedKinds: [.zteMC7530CA]
        ).first)

        XCTAssertEqual(candidate.endpoint.connectionPath, .routed)
        XCTAssertEqual(candidate.endpoint.sourceAddress, "192.168.8.23")
        XCTAssertEqual(candidate.endpoint.gateway, "192.168.8.1")
        XCTAssertTrue(candidate.sources.contains(.primaryInterface))
        XCTAssertFalse(candidate.sources.contains(.matchingSubnet))
    }

    func testDiscoveryKeepsSamePrivateAddressDistinctAcrossInterfaces() {
        let topology = NetworkTopologySnapshot(interfaces: [
            discoveryInterface(
                name: "en5",
                index: 12,
                address: "192.168.254.20",
                prefixLength: 24,
                router: "192.168.254.1"
            ),
            discoveryInterface(
                name: "en8",
                index: 18,
                address: "192.168.254.30",
                prefixLength: 24,
                router: "192.168.254.1"
            )
        ])

        let candidates = ModemCandidateGenerator().candidates(
            topology: topology,
            allowedKinds: [.zteMC7530CA]
        )

        XCTAssertEqual(candidates.count, 2)
        XCTAssertEqual(Set(candidates.map(\.key.host)), ["192.168.254.1"])
        XCTAssertEqual(Set(candidates.map(\.key.interfaceIndex)), [12, 18])
        XCTAssertEqual(Set(candidates.map(\.id)).count, 2)
    }

    func testDiscoveryExcludesTunnelAndPeerInterfaces() {
        let topology = NetworkTopologySnapshot(interfaces: [
            discoveryInterface(
                name: "en1",
                index: 6,
                address: "192.168.8.23",
                prefixLength: 24,
                router: "192.168.8.1"
            ),
            discoveryInterface(
                name: "utun4",
                index: 20,
                address: "10.0.0.2",
                prefixLength: 24,
                router: nil,
                kind: .tunnel
            ),
            discoveryInterface(
                name: "awdl0",
                index: 21,
                address: "169.254.5.2",
                prefixLength: 16,
                router: nil,
                kind: .peerToPeer
            )
        ])

        let candidates = ModemCandidateGenerator().candidates(topology: topology)

        XCTAssertEqual(candidates.count, 2)
        XCTAssertTrue(candidates.allSatisfy { $0.key.interfaceIndex == 6 })
    }

    func testDiscoveryRanksManualAheadOfLastSuccessfulAndMergesEvidence() throws {
        let topology = NetworkTopologySnapshot(interfaces: [discoveryInterface(
            name: "en8",
            index: 18,
            address: "192.168.254.20",
            prefixLength: 24,
            router: "192.168.254.1"
        )])
        let hints = ModemDiscoveryHints(
            lastSuccessful: [ModemEndpointHint(
                kind: .zteMC7530CA,
                baseURL: URL(string: "http://192.168.254.1")!,
                interfaceIndex: 18
            )],
            manual: [ModemEndpointHint(
                kind: .zteMC7530CA,
                baseURL: URL(string: "http://192.168.254.99:8080")!
            )]
        )

        let candidates = ModemCandidateGenerator().candidates(
            topology: topology,
            hints: hints,
            allowedKinds: [.zteMC7530CA]
        )
        let last = try XCTUnwrap(candidates.first { $0.key.effectivePort == 80 })
        let manual = try XCTUnwrap(candidates.first { $0.key.effectivePort == 8080 })

        XCTAssertEqual(candidates.first?.id, manual.id)
        XCTAssertEqual(last.key.host, "192.168.254.1")
        XCTAssertEqual(last.priority, ModemDiscoveryCandidateSource.lastSuccessful.rawValue)
        XCTAssertTrue(last.sources.contains(.lastSuccessful))
        XCTAssertTrue(last.sources.contains(.knownDefault))
        XCTAssertTrue(last.sources.contains(.matchingSubnet))
        XCTAssertEqual(manual.priority, ModemDiscoveryCandidateSource.manual.rawValue)
        XCTAssertTrue(manual.sources.contains(.manual))
        XCTAssertGreaterThan(manual.priority, last.priority)
    }

    func testDiscoveryDoesNotMergeDifferentSchemesOrPorts() {
        let topology = NetworkTopologySnapshot(interfaces: [discoveryInterface(
            name: "en1",
            index: 6,
            address: "192.168.50.20",
            prefixLength: 24,
            router: "192.168.50.1"
        )])
        let profile = ModemDiscoveryProfile(
            kind: .zteMC7530CA,
            defaultBaseURLs: [
                URL(string: "http://192.168.50.1")!,
                URL(string: "http://192.168.50.1:80")!,
                URL(string: "https://192.168.50.1")!,
                URL(string: "http://192.168.50.1:8080")!
            ]
        )

        let candidates = ModemCandidateGenerator(profiles: [profile]).candidates(
            topology: topology
        )

        XCTAssertEqual(candidates.count, 3)
        XCTAssertEqual(Set(candidates.map(\.key.description)), [
            "http://192.168.50.1:80%6",
            "https://192.168.50.1:443%6",
            "http://192.168.50.1:8080%6"
        ])
    }

    func testDiscoveryAllowedKindsFiltersBeforeProbing() async {
        let topology = NetworkTopologySnapshot(interfaces: [discoveryInterface(
            name: "en1",
            index: 6,
            address: "192.168.8.23",
            prefixLength: 24,
            router: "192.168.8.1"
        )])
        let engine = ModemDiscoveryEngine(
            topologyProvider: FixedNetworkTopologyProvider(snapshot: topology),
            probe: ClosureModemDiscoveryProbe { candidate in
                modemIdentity(for: candidate.kind)
            }
        )

        let report = await engine.discover(allowedKinds: [.zteMC7530CA])

        XCTAssertEqual(report.attempts.count, 1)
        XCTAssertEqual(report.matches.count, 1)
        XCTAssertEqual(report.attempts.first?.candidate.kind, .zteMC7530CA)
    }

    func testDiscoveryProbeTimeoutDoesNotWaitForNonCooperativeProbe() async {
        let topology = NetworkTopologySnapshot(interfaces: [discoveryInterface(
            name: "en1",
            index: 6,
            address: "192.168.8.23",
            prefixLength: 24,
            router: "192.168.8.1"
        )])
        let engine = ModemDiscoveryEngine(
            topologyProvider: FixedNetworkTopologyProvider(snapshot: topology),
            probe: ClosureModemDiscoveryProbe { candidate in
                await withCheckedContinuation { continuation in
                    DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(500)) {
                        continuation.resume()
                    }
                }
                return modemIdentity(for: candidate.kind)
            },
            maximumConcurrentProbes: 2,
            probeTimeoutNanoseconds: 1_000_000
        )

        let start = Date()
        let report = await engine.discover()
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(report.attempts.count, 2)
        XCTAssertTrue(report.attempts.allSatisfy { $0.result == .timedOut })
        XCTAssertLessThan(elapsed, 0.25, "Deadline must not await a non-cooperative probe")
    }

    func testDiscoveryResultsRemainInCandidateOrderWhenResponsesFinishOutOfOrder() async {
        let topology = NetworkTopologySnapshot(interfaces: [discoveryInterface(
            name: "en1",
            index: 6,
            address: "192.168.8.23",
            prefixLength: 24,
            router: "192.168.8.1"
        )])
        let provider = FixedNetworkTopologyProvider(snapshot: topology)
        let engine = ModemDiscoveryEngine(
            topologyProvider: provider,
            probe: ClosureModemDiscoveryProbe { candidate in
                let delay: UInt64 = candidate.kind == .vos5G ? 40_000_000 : 1_000_000
                try await Task.sleep(nanoseconds: delay)
                return modemIdentity(for: candidate.kind)
            },
            maximumConcurrentProbes: 2,
            probeTimeoutNanoseconds: 500_000_000
        )
        let expectedOrder = engine.candidates().map(\.id)

        let report = await engine.discover()

        XCTAssertEqual(report.attempts.map { $0.candidate.id }, expectedOrder)
        XCTAssertEqual(report.matches.count, expectedOrder.count)
    }

    func testMC7530ParserFixturesCoverENDCSAAndSentinels() throws {
        let endc = try MC7530Parser.parse(data: mc7530Fixture("endc-mixed-types.json"))
        XCTAssertEqual(endc.networkType, "ENDC")
        XCTAssertEqual(endc.operatorName, "Example Carrier")
        XCTAssertEqual(endc.mcc, "302")
        XCTAssertEqual(endc.mnc, "220")
        XCTAssertEqual(endc.nrSystemMode, .nsa)
        XCTAssertEqual(endc.nrBand, "n66")
        XCTAssertEqual(endc.nrChannel, "434910")
        XCTAssertEqual(endc.nrBandwidthMHz, 20)
        XCTAssertEqual(endc.nrSignal, RadioSignal(rsrpDBm: -104, rsrqDB: -12, rssiDBm: -99, snrDB: 10.5))
        XCTAssertEqual(endc.lteBand, "B2")
        XCTAssertEqual(endc.lteChannel, "900")
        XCTAssertEqual(endc.lteSignal, RadioSignal(rsrpDBm: -99, rsrqDB: -15.5, rssiDBm: -65, snrDB: 2))
        XCTAssertEqual(endc.lteGlobalCellID, 19_088_743)
        XCTAssertEqual(endc.ltePrimaryCell?.band, "B2")
        XCTAssertEqual(endc.ltePrimaryCell?.state, .active)
        XCTAssertEqual(endc.lteSecondaryCells.map(\.band), ["B66", "B7"])
        XCTAssertEqual(endc.lteSecondaryCells.map(\.earfcn), [66_811, 3_350])
        XCTAssertEqual(
            endc.lteSecondaryCells.map(\.role),
            [.secondary(index: 1), .secondary(index: 2)]
        )
        XCTAssertEqual(endc.lteSecondaryCells.map(\.state), [.active, .configured])
        XCTAssertEqual(endc.lteSecondaryCells.filter(\.isActive).count, 1)
        XCTAssertEqual(
            endc.lteSecondaryCells.first?.signal,
            RadioSignal(rsrpDBm: -108, rsrqDB: -14.1, rssiDBm: -86, snrDB: 10)
        )
        XCTAssertEqual(
            endc.lteSecondaryCells.last?.signal,
            .empty
        )
        XCTAssertEqual(endc.unparsedNRCA, "opaque-vendor-value")

        let snapshot = endc.snapshot(
            host: "192.168.254.1",
            interfaceName: "en8",
            now: Date(timeIntervalSince1970: 1)
        )
        XCTAssertEqual(snapshot.detailedMenuTitle, "NSA n66+B2")
        XCTAssertEqual(snapshot.interfaceName, "en8")

        let sa = try MC7530Parser.parse(data: mc7530Fixture("sa.json"))
        XCTAssertEqual(sa.nrSystemMode, .sa)
        XCTAssertEqual(sa.nrBand, "n77")
        XCTAssertEqual(sa.nrChannel, "650000")
        XCTAssertEqual(sa.nrBandwidthMHz, 100)
        XCTAssertEqual(sa.nrGlobalCellID, 305_419_896)
        XCTAssertNil(sa.lteBand)

        let nrCA = try MC7530Parser.parse(data: mc7530Fixture("sa-nr-ca.json"))
        XCTAssertEqual(nrCA.nrPrimaryCell?.band, "n77")
        XCTAssertEqual(nrCA.nrPrimaryCell?.nrarfcn, 640_608)
        XCTAssertEqual(nrCA.nrPrimaryCell?.bandwidthMHz, 50)
        XCTAssertEqual(nrCA.nrSecondaryCells.count, 2)
        XCTAssertEqual(nrCA.nrSecondaryCells.first?.role, .secondary(index: 1))
        XCTAssertEqual(nrCA.nrSecondaryCells.first?.band, "n66")
        XCTAssertEqual(nrCA.nrSecondaryCells.first?.nrarfcn, 438_000)
        XCTAssertEqual(nrCA.nrSecondaryCells.first?.bandwidthMHz, 30)
        XCTAssertEqual(nrCA.nrSecondaryCells.first?.physicalCellID, 203)
        XCTAssertEqual(nrCA.nrSecondaryCells.first?.state, .active)
        XCTAssertEqual(
            nrCA.nrSecondaryCells.first?.signal,
            RadioSignal(rsrpDBm: -91, rsrqDB: -12, rssiDBm: -78, snrDB: 14.3)
        )
        XCTAssertEqual(nrCA.nrSecondaryCells.last?.role, .secondary(index: 2))
        XCTAssertEqual(nrCA.nrSecondaryCells.last?.band, "n77")
        XCTAssertEqual(nrCA.nrSecondaryCells.last?.state, .configured)
        XCTAssertEqual(nrCA.nrSecondaryCells.last?.signal, .empty)
        XCTAssertEqual(nrCA.nrSecondaryCells.filter(\.isActive).count, 1)
        XCTAssertEqual(nrCA.snapshot(host: "192.168.254.1", interfaceName: "en9").nrSecondaryCells.count, 2)

        let lte = try MC7530Parser.parse(data: mc7530Fixture("lte-sentinels.json"))
        XCTAssertEqual(lte.lteBand, "B12")
        XCTAssertEqual(lte.lteChannel, "5010")
        XCTAssertEqual(lte.lteSignal, .empty)
        XCTAssertNil(lte.nrBand)
        XCTAssertTrue(lte.nrSecondaryCells.isEmpty)
        XCTAssertEqual(lte.mcc, "001")
        XCTAssertEqual(lte.mnc, "01")

        let ranges = try MC7530Parser.parse(data: mc7530Fixture("range-sentinels.json"))
        XCTAssertEqual(ranges.lteBand, "B12")
        XCTAssertNil(ranges.lteChannel)
        XCTAssertNil(ranges.lteGlobalCellID)
        XCTAssertNil(ranges.ltePhysicalCellID)
        XCTAssertNil(ranges.ltePrimaryCell)
        XCTAssertTrue(ranges.lteSecondaryCells.isEmpty)
        XCTAssertEqual(ranges.nrBand, "n77")
        XCTAssertNil(ranges.nrChannel)
        XCTAssertNil(ranges.nrBandwidthMHz)
        XCTAssertNil(ranges.nrGlobalCellID)
        XCTAssertNil(ranges.nrPhysicalCellID)
        XCTAssertTrue(ranges.nrSecondaryCells.isEmpty)
        XCTAssertThrowsError(try MC7530Parser.parse(data: Data("[]".utf8)))
    }

    func testZTEAnonymousSchemaAndCSRFCompatibilityHeaders() async throws {
        let http = TestScriptedZTEHTTPTransport(responses: [
            testZTEResponse(#"[{"jsonrpc":"2.0","id":1,"result":{"zte_nwinfo_api":{"nwinfo_get_netinfo":{}}}}]"#)
        ])
        let transport = try ZTEUBusTransport(
            baseURL: URL(string: "http://192.168.254.1")!,
            route: ZTEHTTPRoute(interfaceName: "en8", interfaceIndex: 18, sourceAddress: "192.168.254.20"),
            http: http
        )

        XCTAssertTrue(try await transport.hasMC7530Schema())
        let request = try XCTUnwrap(await http.records().first)
        XCTAssertEqual(request.rpcMethod, "list")
        XCTAssertEqual(request.sessionID, ZTEUBusTransport.zeroSessionID)
        XCTAssertEqual(request.header("Origin"), "http://192.168.254.1")
        XCTAssertEqual(request.header("Referer"), "http://192.168.254.1/")
        XCTAssertEqual(request.header("Z-Mode"), "0")
        XCTAssertEqual(request.header("Z-Tag"), "")
        XCTAssertEqual(request.route.interfaceName, "en8")
        XCTAssertEqual(request.route.interfaceIndex, 18)
    }

    func testMC7530IdentityPrefiltersAnonymouslyBeforeAuthenticatedMSN() async throws {
        let http = TestScriptedZTEHTTPTransport(responses: [
            testZTEResponse(#"[{"jsonrpc":"2.0","id":1,"result":{"zte_nwinfo_api":{"nwinfo_get_netinfo":{}}}}]"#),
            testZTECallResponse(#"{"values":{"wa_inner_version":"MC7530CAV2.6"}}"#),
            testZTECallResponse(#"{"zte_web_sault":"fixture-salt"}"#),
            testZTECallResponse(#"{"result":"0","ubus_rpc_session":"fixture-sid"}"#),
            testZTECallResponse(#"{"values":{"wa_inner_version":"MC7530CAV2.6"}}"#),
            testZTECallResponse(#"{"modem_msn":"fixture-device-alpha"}"#)
        ])
        let backend = MC7530Backend(httpTransport: http)
        let endpoint = ScopedEndpoint(baseURL: URL(string: "http://192.168.254.1")!)
        let credentials = ModemCredentials.web(WebCredentials(password: "fixture-password"))

        let identified = try await backend.identify(
            endpoint: endpoint,
            credentials: credentials
        )
        let identity = try XCTUnwrap(identified)

        XCTAssertEqual(identity.kind, .zteMC7530CA)
        XCTAssertEqual(
            identity.stableIdentifier,
            try MC7530ControlSession.fingerprint(modemMSN: "fixture-device-alpha")
        )
        let records = await http.records()
        XCTAssertEqual(
            records.map(\.ubusMethod),
            [nil, "get", "web_login_info", "web_login", "get", "get_modem_msn"]
        )
        XCTAssertEqual(
            records.map(\.sessionID),
            [
                ZTEUBusTransport.zeroSessionID,
                ZTEUBusTransport.zeroSessionID,
                ZTEUBusTransport.zeroSessionID,
                ZTEUBusTransport.zeroSessionID,
                "fixture-sid",
                "fixture-sid"
            ]
        )
        XCTAssertEqual(records[1].header("Z-Tag"), "zwrt_common_info")
        XCTAssertEqual(records[4].header("Z-Tag"), "zwrt_common_info")
        XCTAssertEqual(records[5].header("Z-Tag"), "get_modem_msn")
    }

    func testMC7530IdentityWrongPasswordFailsBeforeAuthenticatedIdentityRead() async throws {
        let http = TestScriptedZTEHTTPTransport(responses: [
            testZTEResponse(#"[{"jsonrpc":"2.0","id":1,"result":{"zte_nwinfo_api":{"nwinfo_get_netinfo":{}}}}]"#),
            testZTECallResponse(#"{"values":{"wa_inner_version":"MC7530CAV2.6"}}"#),
            testZTECallResponse(#"{"zte_web_sault":"fixture-salt"}"#),
            testZTECallResponse(#"{"result":"1"}"#)
        ])
        let backend = MC7530Backend(httpTransport: http)
        let endpoint = ScopedEndpoint(baseURL: URL(string: "http://192.168.254.1")!)

        do {
            _ = try await backend.identify(
                endpoint: endpoint,
                credentials: .web(WebCredentials(password: "wrong-fixture-password"))
            )
            XCTFail("A rejected Web credential must not identify the modem")
        } catch let error as ZTEUBusError {
            XCTAssertEqual(error, .authenticationFailed)
        }

        let records = await http.records()
        XCTAssertEqual(
            records.map(\.ubusMethod),
            [nil, "get", "web_login_info", "web_login"]
        )
        XCTAssertFalse(records.contains { $0.ubusMethod == "get_modem_msn" })
    }

    func testZTEAuthHashesPasswordAndUsesReturnedSession() async throws {
        let expectedHash = "8D1C7328B6F8EFB7E5D58D42216F27B67BE22C038BF4468A546DBA881440F62C"
        XCTAssertEqual(ZTEAuthSession.loginHash(password: "secret", salt: "pepper"), expectedHash)
        let http = TestScriptedZTEHTTPTransport(responses: [
            testZTECallResponse(#"{"zte_web_sault":"pepper"}"#),
            testZTECallResponse(#"{"result":"0","ubus_rpc_session":"sid-one"}"#),
            testZTECallResponse(#"{"network_type":"LTE"}"#)
        ])
        let session = ZTEAuthSession(
            transport: try ZTEUBusTransport(baseURL: URL(string: "http://192.168.254.1")!, http: http),
            username: "admin",
            password: "secret"
        )

        let payload = try await session.read(object: "zte_nwinfo_api", method: "nwinfo_get_netinfo")
        XCTAssertEqual(payload["network_type"]?.stringValue, "LTE")
        let records = await http.records()
        XCTAssertEqual(records.map(\.ubusMethod), ["web_login_info", "web_login", "nwinfo_get_netinfo"])
        XCTAssertEqual(records[1].loginUsername, "admin")
        XCTAssertEqual(records[1].loginPassword, expectedHash)
        XCTAssertEqual(records[2].sessionID, "sid-one")
        XCTAssertTrue(records.allSatisfy { !$0.bodyText.contains("secret") })
    }

    func testZTEExpiredSessionRelogsExactlyOnce() async throws {
        let http = TestScriptedZTEHTTPTransport(responses: [
            testZTECallResponse(#"{"zte_web_sault":"salt-one"}"#),
            testZTECallResponse(#"{"result":"0","ubus_rpc_session":"sid-one"}"#),
            testZTEStatusResponse(6),
            testZTECallResponse(#"{"zte_web_sault":"salt-two"}"#),
            testZTECallResponse(#"{"result":"0","ubus_rpc_session":"sid-two"}"#),
            testZTECallResponse(#"{"network_type":"NR5G SA"}"#)
        ])
        let session = ZTEAuthSession(
            transport: try ZTEUBusTransport(baseURL: URL(string: "http://192.168.254.1")!, http: http),
            password: "fixture-password"
        )

        let payload = try await session.read(object: "zte_nwinfo_api", method: "nwinfo_get_netinfo")
        XCTAssertEqual(payload["network_type"]?.stringValue, "NR5G SA")
        let records = await http.records()
        XCTAssertEqual(records.count, 6)
        XCTAssertEqual(records.filter { $0.ubusMethod == "web_login" }.count, 2)
        XCTAssertEqual(
            records.filter { $0.ubusMethod == "nwinfo_get_netinfo" }.map(\.sessionID),
            ["sid-one", "sid-two"]
        )
    }

    func testZTEAuthenticatedGenericWriteUsesRetailHeadersAndParameters() async throws {
        let http = TestScriptedZTEHTTPTransport(responses: [
            testZTECallResponse(#"{"zte_web_sault":"write-salt"}"#),
            testZTECallResponse(#"{"result":"0","ubus_rpc_session":"write-sid"}"#),
            testZTECallResponse(#"{"result":"success"}"#)
        ])
        let session = ZTEAuthSession(
            transport: try ZTEUBusTransport(baseURL: URL(string: "http://192.168.254.1")!, http: http),
            password: "fixture-password"
        )

        let payload = try await session.call(
            object: "zte_nwinfo_api",
            method: "nwinfo_set_netselect",
            parameters: ["net_select": .string("Only_LTE")],
            mode: .write,
            zTag: "fixture-tag"
        )

        XCTAssertEqual(payload["result"]?.stringValue, "success")
        let records = await http.records()
        let write = try XCTUnwrap(records.last)
        XCTAssertEqual(write.sessionID, "write-sid")
        XCTAssertEqual(write.ubusMethod, "nwinfo_set_netselect")
        XCTAssertEqual(write.header("Z-Mode"), "1")
        XCTAssertEqual(write.header("Z-Tag"), "fixture-tag")
        XCTAssertTrue(write.bodyText.contains(#""net_select":"Only_LTE""#))
        XCTAssertEqual(records[0].header("Z-Mode"), "0")
        XCTAssertEqual(records[1].header("Z-Mode"), "0")
    }

    func testZTEGenericWriteRelogsOnceAndPreservesHeaders() async throws {
        let http = TestScriptedZTEHTTPTransport(responses: [
            testZTECallResponse(#"{"zte_web_sault":"salt-one"}"#),
            testZTECallResponse(#"{"result":"0","ubus_rpc_session":"sid-one"}"#),
            testZTEStatusResponse(6),
            testZTECallResponse(#"{"zte_web_sault":"salt-two"}"#),
            testZTECallResponse(#"{"result":"0","ubus_rpc_session":"sid-two"}"#),
            testZTECallResponse(#"{"result":"success"}"#)
        ])
        let session = ZTEAuthSession(
            transport: try ZTEUBusTransport(baseURL: URL(string: "http://192.168.254.1")!, http: http),
            password: "fixture-password"
        )

        _ = try await session.call(
            object: "zte_nwinfo_api",
            method: "nwinfo_set_lte_ext_band",
            parameters: ["lte_band": .string("2,4,66")],
            mode: .write,
            zTag: "band-lock"
        )

        let records = await http.records()
        let writes = records.filter { $0.ubusMethod == "nwinfo_set_lte_ext_band" }
        XCTAssertEqual(writes.map(\.sessionID), ["sid-one", "sid-two"])
        XCTAssertEqual(writes.map { $0.header("Z-Mode") }, ["1", "1"])
        XCTAssertEqual(writes.map { $0.header("Z-Tag") }, ["band-lock", "band-lock"])
        XCTAssertEqual(records.filter { $0.ubusMethod == "web_login" }.count, 2)
    }

    func testZTEMC7530HeaderFormRelogsOnceAfterAccessDenied() async throws {
        let http = TestScriptedZTEHTTPTransport(responses: [
            testZTECallResponse(#"{"zte_web_sault":"salt-one"}"#),
            testZTECallResponse(#"{"result":"0","ubus_rpc_session":"sid-one"}"#),
            testZTEResponse(#"[{"jsonrpc":"2.0","id":3,"error":{"code":-32002,"message":"Access denied"}}]"#),
            testZTECallResponse(#"{"zte_web_sault":"salt-two"}"#),
            testZTECallResponse(#"{"result":"0","ubus_rpc_session":"sid-two"}"#),
            testZTEStatusResponse(0)
        ])
        let session = ZTEAuthSession(
            transport: try ZTEUBusTransport(
                baseURL: URL(string: "http://192.168.254.1")!,
                http: http
            ),
            password: "fixture-password"
        )

        try await session.action(
            object: "zte_nwinfo_api",
            method: "nwinfo_set_netselect",
            parameters: ["net_select": .string("Only_5G")],
            mode: .read,
            zTag: ""
        )

        let records = await http.records()
        XCTAssertEqual(records.count, 6)
        let setters = records.filter { $0.ubusMethod == "nwinfo_set_netselect" }
        XCTAssertEqual(setters.map(\.sessionID), ["sid-one", "sid-two"])
        XCTAssertEqual(setters.map { $0.header("Z-Mode") }, ["0", "0"])
        XCTAssertEqual(setters.map { $0.header("Z-Tag") }, ["", ""])
        XCTAssertEqual(records.filter { $0.ubusMethod == "web_login" }.count, 2)
    }

    func testZTEReadRejectsPayloadFreeSuccess() async throws {
        let http = TestScriptedZTEHTTPTransport(responses: [
            testZTECallResponse(#"{"zte_web_sault":"fixture-salt"}"#),
            testZTECallResponse(#"{"result":"0","ubus_rpc_session":"fixture-sid"}"#),
            testZTEStatusResponse(0)
        ])
        let session = ZTEAuthSession(
            transport: try ZTEUBusTransport(
                baseURL: URL(string: "http://192.168.254.1")!,
                http: http
            ),
            password: "fixture-password"
        )

        do {
            _ = try await session.call(
                object: "zte_nwinfo_api",
                method: "nwinfo_get_netinfo",
                mode: .read,
                zTag: ""
            )
            XCTFail("An authenticated read must require a response payload")
        } catch let error as ZTEUBusError {
            XCTAssertEqual(error, .invalidResponse)
        }
    }

    func testZTEReplacementSIDDenialDoesNotTriggerASecondRetry() async throws {
        let http = TestScriptedZTEHTTPTransport(responses: [
            testZTECallResponse(#"{"zte_web_sault":"salt-one"}"#),
            testZTECallResponse(#"{"result":"0","ubus_rpc_session":"sid-one"}"#),
            testZTEStatusResponse(6),
            testZTECallResponse(#"{"zte_web_sault":"salt-two"}"#),
            testZTECallResponse(#"{"result":"0","ubus_rpc_session":"sid-two"}"#),
            testZTEResponse(#"[{"jsonrpc":"2.0","id":3,"error":{"code":-32002,"message":"Access denied"}}]"#)
        ])
        let session = ZTEAuthSession(
            transport: try ZTEUBusTransport(
                baseURL: URL(string: "http://192.168.254.1")!,
                http: http
            ),
            password: "fixture-password"
        )

        do {
            _ = try await session.call(
                object: "zte_nwinfo_api",
                method: "nwinfo_set_netselect",
                parameters: ["net_select": .string("Only_LTE")],
                mode: .write,
                zTag: "nwinfo_set_netselect"
            )
            XCTFail("A replacement SID rejected by rpcd must fail")
        } catch let error as ZTEUBusError {
            XCTAssertEqual(error, .rpc(code: -32_002, message: "Access denied"))
        }

        let records = await http.records()
        XCTAssertEqual(records.count, 6)
        XCTAssertEqual(records.filter { $0.ubusMethod == "web_login" }.count, 2)
        XCTAssertEqual(
            records.filter { $0.ubusMethod == "nwinfo_set_netselect" }.map(\.sessionID),
            ["sid-one", "sid-two"]
        )
    }

    func testZTEGenericCallReportsUBusAndJSONRPCErrors() async throws {
        let ubusHTTP = TestScriptedZTEHTTPTransport(responses: [
            testZTECallResponse(#"{"zte_web_sault":"status-salt"}"#),
            testZTECallResponse(#"{"result":"0","ubus_rpc_session":"status-sid"}"#),
            testZTEStatusResponse(5)
        ])
        let ubusSession = ZTEAuthSession(
            transport: try ZTEUBusTransport(baseURL: URL(string: "http://192.168.254.1")!, http: ubusHTTP),
            password: "fixture-password"
        )
        do {
            _ = try await ubusSession.call(
                object: "zte_nwinfo_api",
                method: "nwinfo_set_netselect",
                mode: .write
            )
            XCTFail("A non-zero UBus result status must fail")
        } catch let error as ZTEUBusError {
            XCTAssertEqual(error, .ubusStatus(5))
        }

        let rpcHTTP = TestScriptedZTEHTTPTransport(responses: [
            testZTECallResponse(#"{"zte_web_sault":"rpc-salt"}"#),
            testZTECallResponse(#"{"result":"0","ubus_rpc_session":"rpc-sid"}"#),
            testZTEResponse(#"[{"jsonrpc":"2.0","id":3,"error":{"code":-32601,"message":"fixture missing method"}}]"#)
        ])
        let rpcSession = ZTEAuthSession(
            transport: try ZTEUBusTransport(baseURL: URL(string: "http://192.168.254.1")!, http: rpcHTTP),
            password: "fixture-password"
        )
        do {
            _ = try await rpcSession.call(
                object: "zte_nwinfo_api",
                method: "fixture_missing_method",
                mode: .write
            )
            XCTFail("A JSON-RPC error must fail")
        } catch let error as ZTEUBusError {
            XCTAssertEqual(error, .rpc(code: -32_601, message: "fixture missing method"))
        }
    }

    func testMC7530ScanContentsPreserveExactRegistrationTokens() throws {
        let networks = try MC7530ControlSession.parseNetworks(
            "1,Fixture LTE,00101,7;2,Fixture NSA,00102,13;3,Fixture SA,00103,11;"
        )

        XCTAssertEqual(networks.map(\.plmn), ["00102", "00101", "00103"])
        XCTAssertEqual(networks.map(\.selectionToken), ["13", "7", "11"])
        XCTAssertEqual(networks.map(\.accessTechnologies), [
            [.lteNRDualConnectivity], [.lte], [.nr5GC]
        ])
    }

    func testMC7530ControlRefreshMapsNetinfoToNeutralState() async throws {
        let netinfo = #"{"net_select":"LTE_AND_5G","net_select_mode":"auto_select","network_provider_fullname":"Fixture Carrier","rmcc":"001","rmnc":"01","network_type":"ENDC","lte_band":"2,4,66","nr5g_sa_band_lock":"5,77","nr5g_nsa_band_lock":"2,66,77","nr5g_nrdc_band_lock":"2,66,77,78","gw_band_lock":"0x006800000","lock_lte_cell":"","lock_nr_cell":""}"#
        let http = TestScriptedZTEHTTPTransport(responses: [
            testZTECallResponse(#"{"zte_web_sault":"fixture-salt"}"#),
            testZTECallResponse(#"{"result":"0","ubus_rpc_session":"fixture-sid"}"#),
            testZTECallResponse(#"{"modem_msn":"fixture-device-alpha"}"#),
            testZTECallResponse(#"{"modem_msn":"fixture-device-alpha"}"#),
            testZTECallResponse(netinfo),
            testZTECallResponse(#"{"modem_msn":"fixture-device-alpha"}"#)
        ])
        let auth = ZTEAuthSession(
            transport: try ZTEUBusTransport(baseURL: URL(string: "http://192.0.2.1")!, http: http),
            password: "fixture-password"
        )
        let session = try await MC7530ControlSession.open(
            session: auth,
            timing: MC7530ControlTiming(
                pollIntervalNanoseconds: 0,
                scanAttempts: 1,
                registrationAttempts: 1,
                verificationAttempts: 1,
                resetAttempts: 1
            ),
            sleep: { _ in }
        )

        let state = try await session.refresh()
        XCTAssertEqual(state.architecture, .nsaOnly)
        XCTAssertEqual(state.operatorSelection, OperatorSelection(
            mode: .automatic,
            operatorName: "Fixture Carrier",
            plmn: "00101",
            accessTechnology: .lteNRDualConnectivity
        ))
        XCTAssertEqual(state.lteBands, Set([2, 4, 66]))
        XCTAssertEqual(state.saBands, Set([5, 77]))
        XCTAssertEqual(state.nsaBands, Set([2, 66, 77]))
        XCTAssertEqual(state.preferenceLifetime, .persistent)

        let records = await http.records()
        let controlReads = records.filter { $0.ubusMethod == "nwinfo_get_netinfo" }
        XCTAssertTrue(controlReads.allSatisfy {
            $0.header("Z-Mode") == "0" && $0.header("Z-Tag") == ""
        })
        let identityReads = records.filter { $0.ubusMethod == "get_modem_msn" }
        XCTAssertTrue(identityReads.allSatisfy {
            $0.header("Z-Mode") == "0" && $0.header("Z-Tag") == "get_modem_msn"
        })
    }

    func testMC7530FingerprintMismatchPermanentlyBlocksWrites() async throws {
        let http = TestScriptedZTEHTTPTransport(responses: [
            testZTECallResponse(#"{"zte_web_sault":"fixture-salt"}"#),
            testZTECallResponse(#"{"result":"0","ubus_rpc_session":"fixture-sid"}"#),
            testZTECallResponse(#"{"modem_msn":"fixture-device-alpha"}"#),
            testZTECallResponse(#"{"modem_msn":"fixture-device-beta"}"#)
        ])
        let auth = ZTEAuthSession(
            transport: try ZTEUBusTransport(baseURL: URL(string: "http://192.0.2.1")!, http: http),
            password: "fixture-password"
        )
        let session = try await MC7530ControlSession.open(
            session: auth,
            timing: MC7530ControlTiming(
                pollIntervalNanoseconds: 0,
                scanAttempts: 1,
                registrationAttempts: 1,
                verificationAttempts: 1,
                resetAttempts: 1
            ),
            sleep: { _ in }
        )

        for _ in 0..<2 {
            do {
                _ = try await session.perform(.setArchitecture(.lteOnly))
                XCTFail("A changed modem must reject every write")
            } catch let error as ModemControlError {
                XCTAssertEqual(error, .deviceChanged)
            }
        }
        let records = await http.records()
        XCTAssertEqual(records.filter { $0.ubusMethod == "get_modem_msn" }.count, 2)
        XCTAssertFalse(records.contains { $0.ubusMethod == "nwinfo_set_netselect" })
    }

    func testMC7530UnknownMSNFieldFailsClosed() async throws {
        let http = TestScriptedZTEHTTPTransport(responses: [
            testZTECallResponse(#"{"zte_web_sault":"fixture-salt"}"#),
            testZTECallResponse(#"{"result":"0","ubus_rpc_session":"fixture-sid"}"#),
            testZTECallResponse(#"{"serial":"fixture-but-unverified-field"}"#)
        ])
        let auth = ZTEAuthSession(
            transport: try ZTEUBusTransport(baseURL: URL(string: "http://192.0.2.1")!, http: http),
            password: "fixture-password"
        )

        do {
            _ = try await MC7530ControlSession.open(session: auth)
            XCTFail("Only the verified modem_msn field may bind a control session")
        } catch let error as ModemBackendError {
            XCTAssertEqual(error, .identityUnavailable)
        }
        let records = await http.records()
        XCTAssertEqual(records.count, 3)
        XCTAssertFalse(records.contains { ($0.ubusMethod ?? "").hasPrefix("nwinfo_set_") })
    }

    func testMC7530UnknownManualRATFailsBeforeDestructiveWrite() async throws {
        let manualNetinfo = #"{"net_select":"Only_5G","net_select_mode":"manual_select","network_provider_fullname":"Fixture Carrier","rmcc":"001","rmnc":"01","network_type":"NR5G SA","lte_band":"2,4,66","nr5g_sa_band_lock":"5,77","nr5g_nsa_band_lock":"2,66,77","nr5g_nrdc_band_lock":"2,66,77,78","gw_band_lock":"0x006800000","lock_lte_cell":"","lock_nr_cell":""}"#
        let http = TestScriptedZTEHTTPTransport(responses: [
            testZTECallResponse(#"{"zte_web_sault":"fixture-salt"}"#),
            testZTECallResponse(#"{"result":"0","ubus_rpc_session":"fixture-sid"}"#),
            testZTECallResponse(#"{"modem_msn":"fixture-device-alpha"}"#),
            testZTECallResponse(#"{"modem_msn":"fixture-device-alpha"}"#),
            testZTECallResponse(manualNetinfo)
        ])
        let auth = ZTEAuthSession(
            transport: try ZTEUBusTransport(baseURL: URL(string: "http://192.0.2.1")!, http: http),
            password: "fixture-password"
        )
        let session = try await MC7530ControlSession.open(session: auth)

        do {
            _ = try await session.perform(.selectAutomaticNetwork)
            XCTFail("A broad network_type must never be guessed into a manual m_rat token")
        } catch let error as ModemControlError {
            guard case .invalidState = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        let records = await http.records()
        XCTAssertFalse(records.contains { $0.ubusMethod == "nwinfo_set_netselect" })
        XCTAssertFalse(records.contains { $0.ubusMethod == "nwinfo_manual_register" })
    }

    func testZTEWrongPasswordStopsFurtherLoginAttempts() async throws {
        let http = TestScriptedZTEHTTPTransport(responses: [
            testZTECallResponse(#"{"zte_web_sault":"pepper"}"#),
            testZTECallResponse(#"{"result":"1"}"#)
        ])
        let session = ZTEAuthSession(
            transport: try ZTEUBusTransport(baseURL: URL(string: "http://192.168.254.1")!, http: http),
            password: "wrong-fixture-password"
        )

        for _ in 0..<2 {
            do {
                _ = try await session.read(object: "zte_nwinfo_api", method: "nwinfo_get_netinfo")
                XCTFail("Wrong password must fail")
            } catch let error as ZTEUBusError {
                XCTAssertEqual(error, .authenticationFailed)
            }
        }
        XCTAssertEqual(await http.requestCount(), 2)
    }

    func testZTEBackendScopesCredentialRejectionPerEndpointUntilItChanges() async throws {
        let http = TestScriptedZTEHTTPTransport(responses: [
            testZTECallResponse(#"{"zte_web_sault":"bad-salt-routed"}"#),
            testZTECallResponse(#"{"result":"1"}"#),
            testZTECallResponse(#"{"zte_web_sault":"bad-salt-direct"}"#),
            testZTECallResponse(#"{"result":"1"}"#),
            testZTECallResponse(#"{"zte_web_sault":"good-salt"}"#),
            testZTECallResponse(#"{"result":"0","ubus_rpc_session":"good-sid"}"#),
            testZTECallResponse(#"{"values":{"wa_inner_version":"MC7530CAV2.6"}}"#),
            testZTECallResponse(#"{"network_type":"LTE","wan_active_band":"B12","wan_active_channel":5010,"lte_pci":7}"#)
        ])
        let backend = MC7530Backend(httpTransport: http)
        let routed = ScopedEndpoint(
            baseURL: URL(string: "http://192.168.254.1")!,
            interfaceName: "en1",
            interfaceIndex: 11,
            sourceAddress: "192.168.8.25",
            connectionPath: .routed,
            gateway: "192.168.8.1"
        )
        let direct = ScopedEndpoint(
            baseURL: URL(string: "http://192.168.254.1")!,
            interfaceName: "en8",
            interfaceIndex: 18,
            sourceAddress: "192.168.254.20",
            connectionPath: .directUSB,
            gateway: "192.168.254.1"
        )
        let rejected = ModemCredentials.web(WebCredentials(password: "wrong-fixture-password"))

        for endpoint in [routed, direct] {
            do {
                _ = try await backend.fetchSnapshot(endpoint: endpoint, credentials: rejected)
                XCTFail("Wrong password must fail on every path")
            } catch let error as ZTEUBusError {
                XCTAssertEqual(error, .authenticationFailed)
            }
        }
        XCTAssertEqual(
            await http.requestCount(),
            4,
            "A rejected candidate must not poison authentication on another scoped endpoint"
        )

        let snapshot = try await backend.fetchSnapshot(
            endpoint: routed,
            credentials: .web(WebCredentials(password: "changed-fixture-password"))
        )
        XCTAssertEqual(snapshot.lteBand, "B12")
        let records = await http.records()
        XCTAssertEqual(records.count, 8)
        XCTAssertEqual(records.prefix(2).map(\.route.interfaceName), ["en1", "en1"])
        XCTAssertEqual(records.dropFirst(2).prefix(2).map(\.route.interfaceName), ["en8", "en8"])
        XCTAssertEqual(records.suffix(4).map(\.route.interfaceName), ["en1", "en1", "en1", "en1"])
        XCTAssertTrue(records.allSatisfy { $0.route.sourceAddress == nil })
        XCTAssertEqual(records.last?.route.interfaceIndex, 11)
    }

    func testZTEBackendRejectsAnotherModelBeforeStatusOrControls() async throws {
        let http = TestScriptedZTEHTTPTransport(responses: [
            testZTECallResponse(#"{"zte_web_sault":"fixture-salt"}"#),
            testZTECallResponse(#"{"result":"0","ubus_rpc_session":"fixture-sid"}"#),
            testZTECallResponse(#"{"values":{"wa_inner_version":"MC889V1.0"}}"#)
        ])
        let backend = MC7530Backend(httpTransport: http)
        let endpoint = ScopedEndpoint(baseURL: URL(string: "http://192.168.254.1")!)
        let credentials = ModemCredentials.web(WebCredentials(password: "fixture-password"))

        do {
            _ = try await backend.fetchSnapshot(endpoint: endpoint, credentials: credentials)
            XCTFail("A generic ZTE nwinfo schema must not identify another model as MC7530CA")
        } catch let error as ModemBackendError {
            XCTAssertEqual(
                error,
                .deviceModelMismatch(expected: "MC7530CA", actual: "MC889V1.0")
            )
        }

        let records = await http.records()
        XCTAssertEqual(records.map(\.ubusMethod), ["web_login_info", "web_login", "get"])
        XCTAssertEqual(records.last?.object, "uci")
        XCTAssertEqual(records.last?.header("Z-Mode"), "0")
        XCTAssertEqual(records.last?.header("Z-Tag"), "zwrt_common_info")
        XCTAssertFalse(records.contains { $0.ubusMethod == "nwinfo_get_netinfo" })
    }

    func testZTEConcurrentExpiredReadsReuseSingleReplacementSID() async throws {
        let http = TestRacingExpiryZTEHTTPTransport()
        let session = ZTEAuthSession(
            transport: try ZTEUBusTransport(
                baseURL: URL(string: "http://192.168.254.1")!,
                http: http
            ),
            password: "fixture-password"
        )

        async let first = session.read(object: "zte_nwinfo_api", method: "nwinfo_get_netinfo")
        async let second = session.read(object: "zte_nwinfo_api", method: "nwinfo_get_netinfo")
        let payloads = try await [first, second]

        XCTAssertEqual(payloads.map { $0["network_type"]?.stringValue }, ["ENDC", "ENDC"])
        let history = await http.history()
        XCTAssertEqual(history.loginCount, 2, "Only the initial and one replacement login are allowed")
        XCTAssertEqual(history.netinfoSessions.filter { $0 == "sid-two" }.count, 2)
        XCTAssertFalse(history.netinfoSessions.contains("sid-three"))
    }

    func testCoordinatorCredentialPolicySelectionAndActiveReuse() async throws {
        let zte = TestMockModemBackend(kind: .zteMC7530CA)
        let vos = TestMockModemBackend(kind: .vos5G)
        let coordinator = ModemCoordinator(
            registry: try testRegistry(zte: zte, vos: vos),
            topologyProvider: FixedNetworkTopologyProvider(snapshot: NetworkTopologySnapshot(interfaces: [
                discoveryInterface(
                    name: "en8", index: 18, address: "192.168.254.20",
                    prefixLength: 24, router: "192.168.254.1"
                )
            ])),
            probeTimeoutNanoseconds: 100_000_000
        )
        let web = ModemCredentials.web(WebCredentials(username: "admin", password: "fixture-web-password"))
        let credentials = ModemConnectionCredentials([.zteMC7530CA: web])

        let first = try await coordinator.read(
            preferences: ModemConnectionPreferences(selection: .zteMC7530CA),
            credentials: credentials
        )
        let second = try await coordinator.read(
            preferences: ModemConnectionPreferences(selection: .zteMC7530CA),
            credentials: credentials
        )

        XCTAssertFalse(first.reusedActiveEndpoint)
        XCTAssertTrue(second.reusedActiveEndpoint)
        let zteHistory = await zte.history()
        XCTAssertEqual(zteHistory.identifyCredentials, [web])
        XCTAssertEqual(zteHistory.fetchCredentials, [web, web])
        let vosHistory = await vos.history()
        XCTAssertTrue(vosHistory.identifyCredentials.isEmpty)
        XCTAssertTrue(vosHistory.fetchCredentials.isEmpty)

        let preferences = ModemConnectionPreferences(
            selection: .zteMC7530CA,
            lastSuccessfulScopeKey: first.lastSuccessfulScopeKey,
            lastSuccessfulEndpoint: first.lastSuccessfulEndpoint
        )
        let encoded = try JSONEncoder().encode(preferences)
        XCTAssertEqual(try JSONDecoder().decode(ModemConnectionPreferences.self, from: encoded), preferences)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("fixture-web-password"))
    }

    func testStandardRegistryUsesTwoStageMC7530IdentityAndRequiresWebForStatus() throws {
        let registry = try ModemBackendRegistry.standard(
            zteHTTPTransport: TestScriptedZTEHTTPTransport(responses: [])
        )
        let registration = try XCTUnwrap(registry.registration(for: .zteMC7530CA))

        XCTAssertEqual(
            registration.identificationCredentials,
            .configuredOrAnonymous(.web)
        )
        XCTAssertEqual(registration.statusCredentials, .configured(.web))
    }

    func testCoordinatorSelectedZTEFailsClosedForMissingOrWrongCredentials() async throws {
        let zte = TestMockModemBackend(kind: .zteMC7530CA)
        let coordinator = ModemCoordinator(
            registry: try testRegistry(zte: zte),
            topologyProvider: FixedNetworkTopologyProvider(snapshot: NetworkTopologySnapshot(interfaces: [
                discoveryInterface(
                    name: "en8", index: 18, address: "192.168.254.20",
                    prefixLength: 24, router: "192.168.254.1"
                )
            ])),
            probeTimeoutNanoseconds: 100_000_000
        )
        let preferences = ModemConnectionPreferences(selection: .zteMC7530CA)

        do {
            _ = try await coordinator.read(
                preferences: preferences,
                credentials: ModemConnectionCredentials()
            )
            XCTFail("Missing Web credentials must fail before discovery")
        } catch let error as ModemBackendError {
            XCTAssertEqual(error, .credentialsRequired(.web))
        }

        do {
            _ = try await coordinator.read(
                preferences: preferences,
                credentials: ModemConnectionCredentials([
                    .zteMC7530CA: .ssh(SSHCredentials(
                        username: "fixture",
                        password: "wrong-transport-password"
                    ))
                ])
            )
            XCTFail("An SSH credential must not be passed to the ZTE Web backend")
        } catch let error as ModemBackendError {
            XCTAssertEqual(
                error,
                .incompatibleCredentials(expected: .web, actual: .ssh)
            )
        }

        let history = await zte.history()
        XCTAssertTrue(history.identifyCredentials.isEmpty)
        XCTAssertTrue(history.fetchCredentials.isEmpty)
    }

    func testCoordinatorAutomaticZTEDefersPasswordUntilAfterAnonymousMatch() async throws {
        let topology = NetworkTopologySnapshot(interfaces: [discoveryInterface(
            name: "en8", index: 18, address: "192.168.254.20",
            prefixLength: 24, router: "192.168.254.1"
        )])
        let matchingZTE = TestMockModemBackend(kind: .zteMC7530CA)
        let matchingCoordinator = ModemCoordinator(
            registry: try testRegistry(zte: matchingZTE),
            topologyProvider: FixedNetworkTopologyProvider(snapshot: topology),
            probeTimeoutNanoseconds: 100_000_000
        )

        do {
            _ = try await matchingCoordinator.read(
                preferences: ModemConnectionPreferences(selection: .automatic),
                credentials: ModemConnectionCredentials()
            )
            XCTFail("A matching ZTE must require its Web password")
        } catch let error as ModemCoordinatorError {
            guard case let .authenticationFailed(kind, _) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(kind, .zteMC7530CA)
        }
        let matchingHistory = await matchingZTE.history()
        XCTAssertEqual(matchingHistory.identifyCredentials, [.none])
        XCTAssertTrue(matchingHistory.fetchCredentials.isEmpty)

        let unrelated = TestMockModemBackend(kind: .zteMC7530CA, identifies: false)
        let unrelatedCoordinator = ModemCoordinator(
            registry: try testRegistry(zte: unrelated),
            topologyProvider: FixedNetworkTopologyProvider(snapshot: topology),
            probeTimeoutNanoseconds: 100_000_000
        )
        do {
            _ = try await unrelatedCoordinator.read(
                preferences: ModemConnectionPreferences(selection: .automatic),
                credentials: ModemConnectionCredentials()
            )
            XCTFail("An unrelated candidate must not match ZTE")
        } catch let error as ModemCoordinatorError {
            XCTAssertEqual(error, .noMatchingModem)
        }
        let unrelatedHistory = await unrelated.history()
        XCTAssertEqual(unrelatedHistory.identifyCredentials, [.none])
        XCTAssertTrue(unrelatedHistory.fetchCredentials.isEmpty)
    }

    func testCoordinatorFailedActiveReadRediscoverAndVOSUsesSSH() async throws {
        let zte = TestMockModemBackend(kind: .zteMC7530CA, fetchFailures: [false, true, false])
        let zteCoordinator = ModemCoordinator(
            registry: try testRegistry(zte: zte),
            topologyProvider: FixedNetworkTopologyProvider(snapshot: NetworkTopologySnapshot(interfaces: [
                discoveryInterface(
                    name: "en8", index: 18, address: "192.168.254.20",
                    prefixLength: 24, router: "192.168.254.1"
                )
            ])),
            probeTimeoutNanoseconds: 100_000_000
        )
        let webCredentials = ModemConnectionCredentials([
            .zteMC7530CA: .web(WebCredentials(password: "fixture-web-password"))
        ])
        _ = try await zteCoordinator.read(
            preferences: ModemConnectionPreferences(selection: .zteMC7530CA),
            credentials: webCredentials
        )
        let recovered = try await zteCoordinator.read(
            preferences: ModemConnectionPreferences(selection: .zteMC7530CA),
            credentials: webCredentials
        )
        XCTAssertFalse(recovered.reusedActiveEndpoint)
        XCTAssertEqual(await zte.history().identifyCredentials.count, 2)
        XCTAssertEqual(await zte.history().fetchCredentials.count, 3)

        let vos = TestMockModemBackend(kind: .vos5G)
        let vosCoordinator = ModemCoordinator(
            registry: try testRegistry(vos: vos),
            topologyProvider: FixedNetworkTopologyProvider(snapshot: NetworkTopologySnapshot(interfaces: [
                discoveryInterface(
                    name: "en9", index: 19, address: "192.168.225.20",
                    prefixLength: 24, router: "192.168.225.1"
                )
            ])),
            probeTimeoutNanoseconds: 100_000_000
        )
        let ssh = ModemCredentials.ssh(SSHCredentials(username: "fixture", password: "fixture-ssh-password"))
        _ = try await vosCoordinator.read(
            preferences: ModemConnectionPreferences(selection: .vos5G),
            credentials: ModemConnectionCredentials([.vos5G: ssh])
        )
        let vosHistory = await vos.history()
        XCTAssertEqual(vosHistory.identifyCredentials, [ssh])
        XCTAssertEqual(vosHistory.fetchCredentials, [ssh])
    }

    func testLTEBandChannelAndBandwidth() throws {
        let radios = try QMIParser.activeRadios(from: data(lteBand))
        XCTAssertEqual(radios, [QMIRadioReading(kind: .lte, band: "B2", channel: 900, bandwidthMHz: 20)])
    }

    func testExtendedNRAndLTE() throws {
        let radios = try QMIParser.activeRadios(from: data(nrAndLTE))
        XCTAssertEqual(radios.map(\.band), ["n78", "B2"])
        XCTAssertEqual(radios.map(\.channel), [633_984, 900])
        XCTAssertEqual(radios.map(\.bandwidthMHz), [50, 20])
    }

    func testMultipleActiveNRComponentCarriers() throws {
        let radios = try QMIParser.activeRadios(from: data(nrCAAndLTE))
        XCTAssertEqual(radios.map(\.band), ["n77", "n77", "B2"])
        XCTAssertEqual(radios.map(\.channel), [640_608, 633_984, 900])
        XCTAssertEqual(radios.map(\.bandwidthMHz), [50, 30, 20])

        let snapshot = try VOSClient.makeSnapshot(
            host: "192.168.225.1",
            interfaceName: "en13",
            probe: VOSProbeOutput(
                band: data(nrCAAndLTE), signal: data(signal), serving: data(serving), ca: nil,
                location: data(nrCACellLocation), dsd: data(dsdNSA),
                modemVersion: nil, deviceFirmware: nil
            )
        )
        XCTAssertEqual(snapshot.nrPrimaryCell?.nrarfcn, 633_984)
        XCTAssertEqual(snapshot.nrPrimaryCell?.bandwidthMHz, 30)
        XCTAssertEqual(snapshot.nrSecondaryCells.map(\.nrarfcn), [640_608])
        XCTAssertEqual(snapshot.nrSecondaryCells.map(\.bandwidthMHz), [50])
    }

    func testNoActiveBandBecomesReachableNoServiceSnapshot() throws {
        XCTAssertThrowsError(try QMIParser.activeRadios(from: data(noActiveBand))) { error in
            XCTAssertEqual(error as? QMIParserError, .noActiveBand)
        }

        let snapshot = try VOSClient.makeSnapshot(
            host: "192.168.225.1",
            interfaceName: "en13",
            probe: VOSProbeOutput(
                band: data(noActiveBand), signal: data(signal), serving: nil, ca: data(ca),
                location: data(nrCellLocation), dsd: data(dsdNSA),
                modemVersion: nil, deviceFirmware: nil
            )
        )

        XCTAssertFalse(snapshot.hasRadioData)
        XCTAssertEqual(snapshot.modeLabel, "Searching")
        XCTAssertNil(snapshot.nrBand)
        XCTAssertNil(snapshot.lteBand)
        XCTAssertEqual(snapshot.nrSignal, .empty)
        XCTAssertEqual(snapshot.lteSignal, .empty)
        XCTAssertNil(snapshot.nrGlobalCellID)
        XCTAssertNil(snapshot.ltePrimaryCell)
        XCTAssertTrue(snapshot.lteSecondaryCells.isEmpty)
    }

    func testMalformedBandResponseStillFailsClosed() {
        XCTAssertThrowsError(try VOSClient.makeSnapshot(
            host: "192.168.225.1",
            interfaceName: "en13",
            probe: VOSProbeOutput(
                band: Data([0x02, 0x01]), signal: nil, serving: nil, ca: nil,
                dsd: nil, modemVersion: nil, deviceFirmware: nil
            )
        )) { error in
            guard let clientError = error as? VOSClientError,
                  case .qmiUnavailable = clientError else {
                return XCTFail("Malformed data must remain a QMI failure")
            }
        }
    }

    func testCellMapperLinksUseStablePublicPages() {
        XCTAssertEqual(
            CellMapperLink.destination(
                for: 385_739_387,
                radio: .lte,
                mcc: nil,
                mnc: nil
            )?.absoluteString,
            "https://www.cellmapper.net/enbid?net=LTE&cellid=385739387"
        )
        XCTAssertEqual(
            CellMapperLink.destination(
                for: 0x1234_5678,
                radio: .nr,
                mcc: "302",
                mnc: "220"
            )?.absoluteString,
            "https://www.cellmapper.net/map?MCC=302&MNC=220&type=NR&showTowers=true&showTowerLabels=true"
        )
        XCTAssertEqual(
            CellMapperLink.destination(for: 1, radio: .nr, mcc: nil, mnc: "220")?.absoluteString,
            "https://www.cellmapper.net/map?type=NR&showTowers=true&showTowerLabels=true"
        )
        XCTAssertEqual(
            CellMapperLink.destination(for: 1, radio: .nr, mcc: "30A", mnc: "220")?.absoluteString,
            "https://www.cellmapper.net/map?type=NR&showTowers=true&showTowerLabels=true"
        )
        XCTAssertTrue(CellMapperLink.copiesCellIDBeforeOpening(radio: .nr))
        XCTAssertFalse(CellMapperLink.copiesCellIDBeforeOpening(radio: .lte))
    }

    func testDSDOnlyUsesExplicitMode() throws {
        XCTAssertEqual(try QMIParser.systemMode(from: data(dsdNSA)), .nsa)
        XCTAssertEqual(try QMIParser.systemMode(from: data(dsdSA)), .sa)
        XCTAssertNil(try QMIParser.systemMode(from: data(dsdLTE)))
    }

    func testCompleteLTEAndNRSignalInfo() throws {
        let levels = try QMIParser.signalInfo(from: data(signal))
        XCTAssertEqual(levels.lteRSSI, -73)
        XCTAssertEqual(levels.lteRSRQ, -13)
        XCTAssertEqual(levels.lteRSRP, -108)
        XCTAssertEqual(levels.lteSNR, 4.6)
        XCTAssertEqual(levels.nrRSRQ, -11)
        XCTAssertEqual(levels.nrRSRP, -84)
        XCTAssertEqual(levels.nrSNR, 12.3)
    }

    func testNRCellLocationInfoFromSanitizedDeviceFixture() throws {
        let location = try QMIParser.cellLocationInfo(from: data(nrCellLocation))

        XCTAssertNil(location.lte)
        XCTAssertEqual(location.nrARFCN, 434_910)
        XCTAssertEqual(location.nr, QMINRCellLocation(
            plmn: [0x03, 0x02, 0x22],
            trackingAreaCode: [0x01, 0x02, 0x03],
            globalCellID: 0x1234_5678,
            physicalCellID: 41,
            signal: QMICellSignalMetrics(
                rsrqDB: -15,
                rsrpDBm: -112,
                rssiDBm: nil,
                snrDB: -1.5
            )
        ))
    }

    func testLTEIntrafrequencyCellLocationInfo() throws {
        var value = Data([0x00, 0x03, 0x02, 0x22])
        value.append(le16(0x1234))
        value.append(le32(0x89AB_CDEF))
        value.append(le16(900))
        value.append(le16(41))
        value.append(contentsOf: [7, 8, 9, 10, 2])
        value.append(lteLocationCell(pci: 41, rsrqTenths: -130, rsrpTenths: -1_060, rssiTenths: -730))
        value.append(lteLocationCell(pci: 99, rsrqTenths: -155, rsrpTenths: -1_121, rssiTenths: -802))

        let response = qmiResponse(message: 0x0043, tlvs: [(0x13, value)])
        let location = try QMIParser.cellLocationInfo(from: response)
        let lte = try XCTUnwrap(location.lte)

        XCTAssertEqual(lte.ueInIdle, false)
        XCTAssertEqual(lte.plmn, [0x03, 0x02, 0x22])
        XCTAssertEqual(lte.trackingAreaCode, 0x1234)
        XCTAssertEqual(lte.globalCellID, 0x89AB_CDEF)
        XCTAssertEqual(lte.earfcn, 900)
        XCTAssertEqual(lte.physicalCellID, 41)
        XCTAssertEqual(lte.cells, [
            QMILTECellMeasurement(
                physicalCellID: 41,
                signal: QMICellSignalMetrics(rsrqDB: -13, rsrpDBm: -106, rssiDBm: -73, snrDB: nil)
            ),
            QMILTECellMeasurement(
                physicalCellID: 99,
                signal: QMICellSignalMetrics(rsrqDB: -15.5, rsrpDBm: -112.1, rssiDBm: -80.2, snrDB: nil)
            )
        ])
        XCTAssertEqual(lte.servingCellMeasurement, lte.cells.first)
    }

    func testLTEInterfrequencyCellLocationInfo() throws {
        var value = Data([0, 2])
        value.append(le16(2_050))
        value.append(contentsOf: [1, 2, 3, 1])
        value.append(lteLocationCell(pci: 17, rsrqTenths: -125, rsrpTenths: -1_040, rssiTenths: -710))
        value.append(le16(8_640))
        value.append(contentsOf: [4, 5, 6, 1])
        value.append(lteLocationCell(pci: 42, rsrqTenths: -150, rsrpTenths: -1_115, rssiTenths: -790))

        let location = try QMIParser.cellLocationInfo(from: qmiResponse(
            message: 0x0043,
            tlvs: [(0x14, value)]
        ))
        XCTAssertEqual(location.lteInterfrequency, [
            QMILTEFrequencyLocation(
                earfcn: 2_050,
                cells: [QMILTECellMeasurement(
                    physicalCellID: 17,
                    signal: QMICellSignalMetrics(rsrqDB: -12.5, rsrpDBm: -104, rssiDBm: -71, snrDB: nil)
                )]
            ),
            QMILTEFrequencyLocation(
                earfcn: 8_640,
                cells: [QMILTECellMeasurement(
                    physicalCellID: 42,
                    signal: QMICellSignalMetrics(rsrqDB: -15, rsrpDBm: -111.5, rssiDBm: -79, snrDB: nil)
                )]
            )
        ])
    }

    func testCellLocationRejectsMalformedFixedAndArrayLengths() throws {
        XCTAssertThrowsError(try QMIParser.cellLocationInfo(from: qmiResponse(
            message: 0x0043,
            tlvs: [(0x2E, Data([0x01, 0x02, 0x03]))]
        )))
        XCTAssertThrowsError(try QMIParser.cellLocationInfo(from: qmiResponse(
            message: 0x0043,
            tlvs: [(0x2F, Data(repeating: 0, count: 21))]
        )))

        // This LTE value advertises one ten-byte cell but supplies none.
        var truncatedLTE = Data(repeating: 0, count: 19)
        truncatedLTE[18] = 1
        XCTAssertThrowsError(try QMIParser.cellLocationInfo(from: qmiResponse(
            message: 0x0043,
            tlvs: [(0x13, truncatedLTE)]
        )))
    }

    func testNRSignalSentinelsAreHidden() throws {
        let levels = try QMIParser.signalInfo(from: data(signalSentinels))
        XCTAssertNil(levels.nrRSRQ)
        XCTAssertNil(levels.nrRSRP)
        XCTAssertNil(levels.nrSNR)
        XCTAssertEqual(levels.lteRSSI, -73)
        XCTAssertEqual(levels.lteRSRQ, -13)
        XCTAssertEqual(levels.lteRSRP, -108)
        XCTAssertEqual(levels.lteSNR, 4.6)
    }

    func testDetailedLTECarrierAggregation() throws {
        let info = try QMIParser.lteCarrierAggregation(from: data(ca))
        XCTAssertEqual(info.primaryCell, QMILTECarrier(
            role: .primary,
            band: "B2",
            qmiBand: 121,
            earfcn: 900,
            bandwidthMHz: 20,
            physicalCellID: 223,
            state: nil,
            index: nil
        ))
        XCTAssertEqual(info.secondaryCells, [
            QMILTECarrier(
                role: .secondary,
                band: "B4",
                qmiBand: 123,
                earfcn: 2_050,
                bandwidthMHz: 20,
                physicalCellID: 41,
                state: .configuredActivated,
                index: 1
            ),
            QMILTECarrier(
                role: .secondary,
                band: "B25",
                qmiBand: 148,
                earfcn: 8_640,
                bandwidthMHz: 10,
                physicalCellID: 42,
                state: .configuredDeactivated,
                index: 2
            )
        ])
        XCTAssertEqual(info.activeSecondaryBands, ["B4"])
        XCTAssertEqual(try QMIParser.lteSecondaryBands(from: data(ca)), ["B4"])
    }

    func testLegacySecondaryCellAndIndex() throws {
        let info = try QMIParser.lteCarrierAggregation(from: data(legacyCA))
        XCTAssertEqual(info.secondaryCells.count, 1)
        XCTAssertEqual(info.secondaryCells.first?.band, "B4")
        XCTAssertEqual(info.secondaryCells.first?.earfcn, 2_050)
        XCTAssertEqual(info.secondaryCells.first?.physicalCellID, 17)
        XCTAssertEqual(info.secondaryCells.first?.state, .configuredActivated)
        XCTAssertEqual(info.secondaryCells.first?.index, 3)
    }

    func testSnapshotMapsSignalAndCarrierDetails() throws {
        let probe = VOSProbeOutput(
            band: data(nrAndLTE), signal: data(signal), serving: nil, ca: data(ca),
            dsd: data(dsdNSA), modemVersion: nil, deviceFirmware: nil
        )
        let snapshot = try VOSClient.makeSnapshot(
            host: "192.168.225.1",
            interfaceName: "en13",
            probe: probe
        )

        XCTAssertEqual(snapshot.nrSignal, RadioSignal(rsrpDBm: -84, rsrqDB: -11, rssiDBm: nil, snrDB: 12.3))
        XCTAssertEqual(snapshot.lteSignal, RadioSignal(rsrpDBm: -108, rsrqDB: -13, rssiDBm: -73, snrDB: 4.6))
        XCTAssertEqual(snapshot.ltePrimaryCell?.band, "B2")
        XCTAssertEqual(snapshot.ltePrimaryCell?.physicalCellID, 223)
        XCTAssertEqual(snapshot.lteSecondaryCells.map(\.band), ["B4", "B25"])
        XCTAssertEqual(snapshot.lteSecondaryCells.map(\.state), [.active, .configured])
    }

    func testSnapshotSuppressesDeconfiguredLegacyPlaceholder() throws {
        let probe = VOSProbeOutput(
            band: data(lteBand), signal: nil, serving: nil, ca: data(legacyNoCA),
            dsd: nil, modemVersion: nil, deviceFirmware: nil
        )
        let snapshot = try VOSClient.makeSnapshot(
            host: "192.168.225.1",
            interfaceName: "en13",
            probe: probe
        )
        XCTAssertTrue(snapshot.lteSecondaryCells.isEmpty)
    }

    func testHumanReadableChannelFrequencies() throws {
        XCTAssertEqual(try XCTUnwrap(ChannelFrequency.nrMHz(633_984)), 3_509.76, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(ChannelFrequency.lteMHz(band: "B2", earfcn: 900)), 1_960, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(ChannelFrequency.lteMHz(band: "B66", earfcn: 66_786)), 2_145, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(ChannelFrequency.lteMHz(band: "B44", earfcn: 45_590)), 703, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(ChannelFrequency.lteMHz(band: "B45", earfcn: 46_590)), 1_447, accuracy: 0.001)
        XCTAssertNil(ChannelFrequency.lteMHz(band: "B2", earfcn: 66_786))
    }

    func testSnapshotDoesNotGuessNSAWithoutDSD() throws {
        let probe = VOSProbeOutput(
            band: data(nrAndLTE), signal: nil, serving: nil, ca: nil,
            dsd: nil, modemVersion: nil, deviceFirmware: nil
        )
        let snapshot = try VOSClient.makeSnapshot(host: "192.168.225.1", interfaceName: "en13", probe: probe)
        XCTAssertEqual(snapshot.modeLabel, "NR + LTE")
        XCTAssertEqual(snapshot.detailedMenuTitle, "NR n78+B2")
    }

    func testCOPSCurrentSelectionWithFourFieldResponse() throws {
        let selection = try ATCOPSParser.selection(from: """
        AT+COPS?
        +COPS: 0,0,"TELUS",13
        OK
        """)

        XCTAssertEqual(selection.mode, .automatic)
        XCTAssertEqual(selection.operatorName, "TELUS")
        XCTAssertNil(selection.plmn)
        XCTAssertEqual(selection.accessTechnology, .lteNRDualConnectivity)
    }

    func testQMIGetPLMNNameParsesEONSAndBuildsRequest() throws {
        let name = try QMIParser.plmnName(from: data(telusPLMNName))
        XCTAssertEqual(name.shortName, "TELUS")
        XCTAssertEqual(name.longName, "TELUS")
        XCTAssertEqual(name.displayName, "TELUS")

        XCTAssertEqual(
            QMIParser.getPLMNNameRequest(mcc: 302, mnc: 220, transaction: 7),
            qmiRequest(
                message: 0x0044,
                transaction: 7,
                tlvs: [(0x01, le16(302) + le16(220))]
            )
        )
        XCTAssertEqual(
            QMIParser.getPLMNNameRequest(
                mcc: 302,
                mnc: 220,
                mncHasThreeDigits: true,
                transaction: 7
            ),
            qmiRequest(
                message: 0x0044,
                transaction: 7,
                tlvs: [(0x01, le16(302) + le16(220)), (0x11, Data([1]))]
            )
        )
    }

    func testServingInfoUsesPrecisePLMNWithoutServingName() throws {
        let precise = le16(302) + le16(220) + Data([1])
        let info = try QMIParser.servingInfo(from: qmiResponse(
            message: 0x0024,
            tlvs: [(0x27, precise)]
        ))
        XCTAssertNil(info.operatorName)
        XCTAssertEqual(info.mcc, "302")
        XCTAssertEqual(info.mnc, "220")
    }

    func testCOPSManualSelectionWithNumericPLMNAndEONS() throws {
        let selection = try ATCOPSParser.selection(from: """
        +COPS: 1,2,"302220","TELUS",13
        OK
        """)

        XCTAssertEqual(selection.mode, .manual)
        XCTAssertEqual(selection.operatorName, "TELUS")
        XCTAssertEqual(selection.plmn, "302220")
        XCTAssertEqual(selection.formattedPLMN, "302-220")
        XCTAssertEqual(selection.accessTechnology, .lteNRDualConnectivity)
    }

    func testCOPSManualSelectionWithoutEONSKeepsNumericValueAsPLMNOnly() throws {
        let selection = try ATCOPSParser.selection(from: """
        +COPS: 1,2,"302220",13
        OK
        """)

        XCTAssertNil(selection.operatorName)
        XCTAssertEqual(selection.plmn, "302220")
        XCTAssertEqual(selection.accessTechnology, .lteNRDualConnectivity)
    }

    func testOperatorDisplayIdentityUsesScannedNameAndNeverAddsLeadingSeparator() {
        let selection = OperatorSelection(
            mode: .automatic,
            operatorName: nil,
            plmn: "302220",
            accessTechnology: .nr5GC
        )
        let telus = CellularNetwork(
            longName: "TELUS",
            shortName: "TELUS",
            plmn: "302220",
            availability: .current,
            accessTechnologies: [.nr5GC]
        )

        XCTAssertEqual(
            OperatorDisplayIdentity.resolve(
                snapshotName: "",
                snapshotPLMN: "302-220",
                selection: selection,
                scannedNetworks: [telus]
            ).formatted,
            "TELUS · 302-220"
        )
        XCTAssertEqual(
            OperatorDisplayIdentity.resolve(
                snapshotName: "",
                snapshotPLMN: "302-220",
                selection: selection,
                scannedNetworks: []
            ).formatted,
            "302-220"
        )

        let bellSelection = OperatorSelection(
            mode: .manual,
            operatorName: nil,
            plmn: "302610",
            accessTechnology: .nr5GC
        )
        let bell = CellularNetwork(
            longName: "Bell",
            shortName: "BELL",
            plmn: "302610",
            availability: .current,
            accessTechnologies: [.nr5GC]
        )
        XCTAssertEqual(
            OperatorDisplayIdentity.resolve(
                snapshotName: "TELUS",
                snapshotPLMN: "302-220",
                selection: bellSelection,
                scannedNetworks: [bell]
            ).formatted,
            "Bell · 302-610"
        )
    }

    func testHeaderSubtitleShowsCarrierAndModemButNeverPLMN() {
        let named = OperatorDisplayIdentity(name: "TELUS", plmn: "302-220")
        XCTAssertEqual(
            named.headerSubtitle(
                modemName: "MC7530CA / G5 MAX",
                fallback: "Local modem"
            ),
            "TELUS · MC7530CA / G5 MAX"
        )
        XCTAssertEqual(
            named.headerSubtitle(modemName: nil, fallback: "Local modem"),
            "TELUS"
        )

        let numericOnly = OperatorDisplayIdentity(name: nil, plmn: "302-220")
        XCTAssertEqual(
            numericOnly.headerSubtitle(
                modemName: "MC7530CA / G5 MAX",
                fallback: "Local modem"
            ),
            "MC7530CA / G5 MAX"
        )
        XCTAssertEqual(
            numericOnly.headerSubtitle(modemName: nil, fallback: "Local modem"),
            "Local modem"
        )
    }

    func testIdentityUsesCompactZTEHeaderName() {
        let zte = ModemIdentity(
            kind: .zteMC7530CA,
            manufacturer: "ZTE",
            model: "MC7530CA",
            displayName: "ZTE MC7530CA / G5 MAX"
        )
        XCTAssertEqual(zte.compactDisplayName, "MC7530CA / G5 MAX")

        let vos = ModemIdentity(
            kind: .vos5G,
            manufacturer: "Generic",
            model: "VOS",
            displayName: "My VOS modem"
        )
        XCTAssertEqual(vos.compactDisplayName, "My VOS modem")
    }

    func testCOPSScanAggregatesRepeatedPLMNAndPreservesAvailability() throws {
        let networks = try ATCOPSParser.networks(from: """
        AT+COPS=?
        +COPS: (2,"TELUS","TELUS","302220",13),
        (1,"TELUS","TELUS","302220",7),
        (1,"Bell","BELL","302610",11),
        (1,"Bell","BELL","302610",7),
        (3,"Rogers Wireless","ROGERS","302720",7),
        (0,"Unknown","","46001",2),,(0,1,2,3,4),(0,1,2)
        OK
        """)

        XCTAssertEqual(networks.map(\.plmn), ["302220", "302610", "46001", "302720"])

        let telus = try XCTUnwrap(networks.first { $0.plmn == "302220" })
        XCTAssertEqual(telus.availability, .current)
        XCTAssertEqual(telus.accessTechnologies, [.lte, .lteNRDualConnectivity])
        XCTAssertEqual(telus.accessTechnologyLabel, "LTE, 5G NSA")

        let bell = try XCTUnwrap(networks.first { $0.plmn == "302610" })
        XCTAssertEqual(bell.availability, .available)
        XCTAssertEqual(bell.accessTechnologies, [.lte, .nr5GC])
        XCTAssertEqual(bell.accessTechnologyLabel, "LTE, 5G SA")

        XCTAssertEqual(networks.first { $0.plmn == "302720" }?.availability, .forbidden)
        XCTAssertEqual(networks.first { $0.plmn == "46001" }?.availability, .unknown)
    }

    func testCOPSAccessTechnologyLabelsCoverLTEAndNRModes() {
        XCTAssertEqual(CellularAccessTechnology.lte.label, "LTE")
        XCTAssertEqual(CellularAccessTechnology.lte5GC.label, "LTE / 5GC")
        XCTAssertEqual(CellularAccessTechnology.nr5GC.label, "5G SA")
        XCTAssertEqual(CellularAccessTechnology.ngRAN.label, "5G SA")
        XCTAssertEqual(CellularAccessTechnology.lteNRDualConnectivity.label, "5G NSA")
    }

    func testCOPSParserRejectsCommandFailure() {
        XCTAssertThrowsError(try ATCOPSParser.selection(from: "+CME ERROR: 30\n"))
        XCTAssertThrowsError(try ATCOPSParser.requireOK("+COPS: 0\n"))
    }

    func testQMIGetSystemSelectionPreferencesParsesModeAndExactMasks() throws {
        let saBytes = Data((0..<NRBandMask.byteCount).map { UInt8(truncatingIfNeeded: $0) })
        let nsaBytes = Data((0..<NRBandMask.byteCount).map { UInt8(truncatingIfNeeded: 255 - $0) })
        let response = qmiResponse(
            message: 0x0034,
            transaction: 0x1234,
            tlvs: [
                (0x11, le16(0x0050)),
                (0x2C, saBytes),
                (0x2D, nsaBytes)
            ]
        )

        let preferences = try QMIParser.systemSelectionPreferences(from: response)
        XCTAssertEqual(preferences.modePreference, 0x0050)
        XCTAssertEqual(preferences.saBands.bytes, saBytes)
        XCTAssertEqual(preferences.nsaBands.bytes, nsaBytes)
        XCTAssertEqual(preferences.architectureMode, .automatic)
    }

    func testQMIGetSystemSelectionPreferencesRequiresBothFullMasks() {
        let fullMask = Data(repeating: 0x55, count: NRBandMask.byteCount)
        let missingNSA = qmiResponse(
            message: 0x0034,
            tlvs: [(0x11, le16(0x0050)), (0x2C, fullMask)]
        )
        let shortNSA = qmiResponse(
            message: 0x0034,
            tlvs: [(0x2C, fullMask), (0x2D, Data(repeating: 0xAA, count: 63))]
        )

        XCTAssertThrowsError(try QMIParser.systemSelectionPreferences(from: missingNSA))
        XCTAssertThrowsError(try QMIParser.systemSelectionPreferences(from: shortNSA))
    }

    func testNRArchitectureClassificationUsesModeAndMasks() throws {
        let enabled = try XCTUnwrap(NRBandMask(Data(repeating: 0x55, count: NRBandMask.byteCount)))
        XCTAssertEqual(
            NRSystemSelectionPreferences(
                modePreference: 0x0010,
                saBands: enabled,
                nsaBands: enabled
            ).architectureMode,
            .lteOnly
        )
        XCTAssertEqual(
            NRSystemSelectionPreferences(
                modePreference: 0x001C,
                saBands: enabled,
                nsaBands: enabled
            ).architectureMode,
            .unavailable,
            "LTE plus legacy RAT bits must not be labeled LTE only"
        )
        XCTAssertEqual(
            NRSystemSelectionPreferences(
                modePreference: 0x0040,
                saBands: enabled,
                nsaBands: enabled
            ).architectureMode,
            .saOnly
        )
        XCTAssertEqual(
            NRSystemSelectionPreferences(
                modePreference: 0x0050,
                saBands: .zero,
                nsaBands: enabled
            ).architectureMode,
            .nsaOnly
        )
        XCTAssertEqual(
            NRSystemSelectionPreferences(
                modePreference: 0x0050,
                saBands: enabled,
                nsaBands: enabled
            ).architectureMode,
            .automatic
        )
    }

    func testRadioAccessPreferencePlansPreserveExistingModesAndAddLTEOnly() throws {
        let baselineLTE = try XCTUnwrap(LTEBandMask(bands: [2, 4, 25, 66]))
        let currentLTE = try XCTUnwrap(LTEBandMask(bands: [2, 66]))
        let baseline = NRSystemSelectionPreferences(
            modePreference: 0x0050,
            saBands: try XCTUnwrap(NRBandMask(bands: [77, 78])),
            nsaBands: try XCTUnwrap(NRBandMask(bands: [77, 78])),
            lteBands: baselineLTE
        )
        let current = NRSystemSelectionPreferences(
            modePreference: 0x0050,
            saBands: baseline.saBands,
            nsaBands: baseline.nsaBands,
            lteBands: currentLTE
        )

        let automatic = try RadioAccessPreferencePlan.make(
            mode: .automatic,
            baseline: baseline,
            current: current
        )
        XCTAssertEqual(automatic.target.modePreference, 0x0050)
        XCTAssertEqual(automatic.target.saBands, baseline.saBands)
        XCTAssertEqual(automatic.target.nsaBands, baseline.nsaBands)
        XCTAssertEqual(automatic.target.lteBands, currentLTE)
        XCTAssertNil(automatic.lteBandsToWrite)

        let saOnly = try RadioAccessPreferencePlan.make(
            mode: .saOnly,
            baseline: baseline,
            current: current
        )
        XCTAssertEqual(saOnly.target.modePreference, 0x0040)
        XCTAssertEqual(saOnly.target.saBands, baseline.saBands)
        XCTAssertTrue(saOnly.target.nsaBands.isEmpty)
        XCTAssertNil(saOnly.lteBandsToWrite)

        let nsaOnly = try RadioAccessPreferencePlan.make(
            mode: .nsaOnly,
            baseline: baseline,
            current: current
        )
        XCTAssertEqual(nsaOnly.target.modePreference, 0x0050)
        XCTAssertTrue(nsaOnly.target.saBands.isEmpty)
        XCTAssertEqual(nsaOnly.target.nsaBands, baseline.nsaBands)
        XCTAssertNil(nsaOnly.lteBandsToWrite)

        let lteOnly = try RadioAccessPreferencePlan.make(
            mode: .lteOnly,
            baseline: baseline,
            current: current
        )
        XCTAssertEqual(lteOnly.target.modePreference, 0x0010)
        XCTAssertTrue(lteOnly.target.saBands.isEmpty)
        XCTAssertTrue(lteOnly.target.nsaBands.isEmpty)
        XCTAssertEqual(lteOnly.target.lteBands, currentLTE)
        XCTAssertEqual(lteOnly.lteBandsToWrite, currentLTE)
        XCTAssertEqual(lteOnly.target.architectureMode, .lteOnly)
    }

    func testLTEOnlyPlanFallsBackToCapturedLTEAndIgnoresDormantNRLock() throws {
        let baselineLTE = try XCTUnwrap(LTEBandMask(bands: [2, 4]))
        let baseline = NRSystemSelectionPreferences(
            modePreference: 0x0050,
            saBands: try XCTUnwrap(NRBandMask(bands: [78])),
            nsaBands: try XCTUnwrap(NRBandMask(bands: [77])),
            lteBands: baselineLTE
        )
        let current = NRSystemSelectionPreferences(
            modePreference: 0x0050,
            saBands: baseline.saBands,
            nsaBands: baseline.nsaBands,
            lteBands: .zero
        )

        let plan = try RadioAccessPreferencePlan.make(
            mode: .lteOnly,
            baseline: baseline,
            current: current,
            activeNRBandLock: [78]
        )
        XCTAssertEqual(plan.lteBandsToWrite, baselineLTE)
        XCTAssertTrue(plan.target.saBands.isEmpty)
        XCTAssertTrue(plan.target.nsaBands.isEmpty)

        XCTAssertThrowsError(try NRBandLockPlan.make(
            requested: try XCTUnwrap(NRBandMask(bands: [78])),
            baseline: baseline,
            architecture: .lteOnly
        )) { error in
            XCTAssertEqual(error as? NRBandLockPlanError, .architectureUnavailable)
        }
    }

    func testLTEOnlyPlanHandlesMissingAndExplicitlyEmptyLTEMasks() throws {
        let nr = try XCTUnwrap(NRBandMask(bands: [77, 78]))
        let baselineWithoutLTE = NRSystemSelectionPreferences(
            modePreference: 0x0050,
            saBands: nr,
            nsaBands: nr,
            lteBands: nil
        )
        let plan = try RadioAccessPreferencePlan.make(
            mode: .lteOnly,
            baseline: baselineWithoutLTE,
            current: baselineWithoutLTE
        )
        XCTAssertNil(plan.lteBandsToWrite)
        XCTAssertNil(plan.target.lteBands)

        let currentWithExplicitEmptyLTE = NRSystemSelectionPreferences(
            modePreference: 0x0050,
            saBands: nr,
            nsaBands: nr,
            lteBands: .zero
        )
        XCTAssertThrowsError(try RadioAccessPreferencePlan.make(
            mode: .lteOnly,
            baseline: baselineWithoutLTE,
            current: currentWithExplicitEmptyLTE
        )) { error in
            XCTAssertEqual(error as? RadioAccessPreferencePlanError, .emptyLTEBandMask)
        }
    }

    func testNRBandLockPlanValidatesSAOnlyAndNSAOnlySeparately() throws {
        let baseline = NRSystemSelectionPreferences(
            modePreference: 0x0050,
            saBands: try XCTUnwrap(NRBandMask(bands: [78, 79])),
            nsaBands: try XCTUnwrap(NRBandMask(bands: [77, 78]))
        )

        let saPlan = try NRBandLockPlan.make(
            requested: try XCTUnwrap(NRBandMask(bands: [78])),
            baseline: baseline,
            architecture: .saOnly
        )
        XCTAssertEqual(saPlan.saBands.enabledBands, [78])
        XCTAssertTrue(saPlan.nsaBands.isEmpty)
        XCTAssertThrowsError(try NRBandLockPlan.make(
            requested: try XCTUnwrap(NRBandMask(bands: [77])),
            baseline: baseline,
            architecture: .saOnly
        )) { error in
            XCTAssertEqual(error as? NRBandLockPlanError, .unsupportedBands(sa: [77], nsa: []))
        }

        let nsaPlan = try NRBandLockPlan.make(
            requested: try XCTUnwrap(NRBandMask(bands: [77])),
            baseline: baseline,
            architecture: .nsaOnly
        )
        XCTAssertTrue(nsaPlan.saBands.isEmpty)
        XCTAssertEqual(nsaPlan.nsaBands.enabledBands, [77])
        XCTAssertThrowsError(try NRBandLockPlan.make(
            requested: try XCTUnwrap(NRBandMask(bands: [79])),
            baseline: baseline,
            architecture: .nsaOnly
        )) { error in
            XCTAssertEqual(error as? NRBandLockPlanError, .unsupportedBands(sa: [], nsa: [79]))
        }
    }

    func testNRBandLockPlanKeepsAutomaticModeDualArchitecture() throws {
        let baseline = NRSystemSelectionPreferences(
            modePreference: 0x0050,
            saBands: try XCTUnwrap(NRBandMask(bands: [78, 79])),
            nsaBands: try XCTUnwrap(NRBandMask(bands: [77, 78]))
        )
        let plan = try NRBandLockPlan.make(
            requested: try XCTUnwrap(NRBandMask(bands: [78])),
            baseline: baseline,
            architecture: .automatic
        )

        XCTAssertEqual(plan.saBands.enabledBands, [78])
        XCTAssertEqual(plan.nsaBands.enabledBands, [78])
        XCTAssertEqual(
            NRSystemSelectionPreferences(
                modePreference: 0x0050,
                saBands: plan.saBands,
                nsaBands: plan.nsaBands
            ).architectureMode,
            .automatic
        )
        XCTAssertThrowsError(try NRBandLockPlan.make(
            requested: try XCTUnwrap(NRBandMask(bands: [77])),
            baseline: baseline,
            architecture: .automatic
        )) { error in
            XCTAssertEqual(error as? NRBandLockPlanError, .unsupportedBands(sa: [77], nsa: []))
        }
        XCTAssertThrowsError(try NRBandLockPlan.make(
            requested: try XCTUnwrap(NRBandMask(bands: [79])),
            baseline: baseline,
            architecture: .automatic
        )) { error in
            XCTAssertEqual(error as? NRBandLockPlanError, .unsupportedBands(sa: [], nsa: [79]))
        }
    }

    func testActiveNRBandLockCannotSwitchToAnIncompatibleArchitecture() throws {
        let baseline = NRSystemSelectionPreferences(
            modePreference: 0x0050,
            saBands: try XCTUnwrap(NRBandMask(bands: [78])),
            nsaBands: try XCTUnwrap(NRBandMask(bands: [77]))
        )
        let saLock = try XCTUnwrap(NRBandMask(bands: [78]))
        XCTAssertNoThrow(try NRBandLockPlan.make(
            requested: saLock,
            baseline: baseline,
            architecture: .saOnly
        ))
        XCTAssertThrowsError(try NRBandLockPlan.make(
            requested: saLock,
            baseline: baseline,
            architecture: .nsaOnly
        ))
        XCTAssertThrowsError(try NRBandLockPlan.make(
            requested: saLock,
            baseline: baseline,
            architecture: .automatic
        ))

        let nsaLock = try XCTUnwrap(NRBandMask(bands: [77]))
        XCTAssertNoThrow(try NRBandLockPlan.make(
            requested: nsaLock,
            baseline: baseline,
            architecture: .nsaOnly
        ))
        XCTAssertThrowsError(try NRBandLockPlan.make(
            requested: nsaLock,
            baseline: baseline,
            architecture: .saOnly
        ))
        XCTAssertThrowsError(try NRBandLockPlan.make(
            requested: nsaLock,
            baseline: baseline,
            architecture: .automatic
        ))
    }

    func testQMIGetSystemSelectionRequestUsesExpectedMessageAndTransaction() {
        XCTAssertEqual(
            QMIParser.getSystemSelectionRequest(transaction: 0x1234),
            Data([0x00, 0x34, 0x12, 0x34, 0x00, 0x00, 0x00])
        )
    }

    func testQMISetSystemSelectionRequestBuildsSAOnlyPreference() throws {
        let sa = try XCTUnwrap(NRBandMask(Data(repeating: 0xA5, count: NRBandMask.byteCount)))

        let request = QMIParser.setNRSystemSelectionRequest(
            modePreference: 0x0040,
            saBands: sa,
            nsaBands: .zero,
            transaction: 0x1234
        )
        let expected = qmiRequest(
            message: 0x0033,
            transaction: 0x1234,
            tlvs: [
                (0x17, Data([0x00])),
                (0x11, le16(0x0040)),
                (0x2F, sa.bytes),
                (0x30, NRBandMask.zero.bytes)
            ]
        )

        XCTAssertEqual(request, expected)
    }

    func testQMISetSystemSelectionAutoPreservesBothCapturedMasks() throws {
        let sa = try XCTUnwrap(NRBandMask(Data(repeating: 0xA5, count: NRBandMask.byteCount)))
        let nsa = try XCTUnwrap(NRBandMask(Data(repeating: 0x5A, count: NRBandMask.byteCount)))
        let request = QMIParser.setNRSystemSelectionRequest(
            modePreference: 0x0050,
            saBands: sa,
            nsaBands: nsa
        )

        XCTAssertEqual(request, qmiRequest(
            message: 0x0033,
            tlvs: [
                (0x17, Data([0x00])),
                (0x11, le16(0x0050)),
                (0x2F, sa.bytes),
                (0x30, nsa.bytes)
            ]
        ))
    }

    func testQMISetSystemSelectionUsesLTEAndNRModeForAutoAndNSA() throws {
        let enabled = try XCTUnwrap(NRBandMask(Data(repeating: 0x11, count: NRBandMask.byteCount)))
        let request = QMIParser.setNRSystemSelectionRequest(
            modePreference: 0x0050,
            saBands: .zero,
            nsaBands: enabled
        )
        let expected = qmiRequest(
            message: 0x0033,
            tlvs: [
                (0x17, Data([0x00])),
                (0x11, le16(0x0050)),
                (0x2F, NRBandMask.zero.bytes),
                (0x30, enabled.bytes)
            ]
        )

        XCTAssertEqual(request, expected)
    }

    func testQMISetSystemSelectionBuildsLTEOnlyWithPreservedLTEMask() throws {
        let lte = try XCTUnwrap(LTEBandMask(bands: [2, 4, 25, 66]))
        let request = QMIParser.setNRSystemSelectionRequest(
            modePreference: 0x0010,
            saBands: .zero,
            nsaBands: .zero,
            lteBands: lte,
            transaction: 0x1234
        )

        XCTAssertEqual(request, qmiRequest(
            message: 0x0033,
            transaction: 0x1234,
            tlvs: [
                (0x17, Data([0x00])),
                (0x11, le16(0x0010)),
                (0x24, lte.bytes),
                (0x2F, NRBandMask.zero.bytes),
                (0x30, NRBandMask.zero.bytes)
            ]
        ))
    }

    func testQMISetSystemSelectionResponseValidation() {
        XCTAssertNoThrow(try QMIParser.validateSetSystemSelectionResponse(
            qmiResponse(message: 0x0033)
        ))
        XCTAssertThrowsError(try QMIParser.validateSetSystemSelectionResponse(
            qmiResponse(message: 0x0033, resultStatus: 1, resultError: 42)
        ))
    }

    func testOnlyLocalDeviceAddressesAreAccepted() {
        XCTAssertEqual(DeviceConfiguration(host: "192.168.225.1", username: "root", password: "x", refreshInterval: 5).sshHost, "192.168.225.1")
        XCTAssertNil(DeviceConfiguration(host: "example.com", username: "root", password: "x", refreshInterval: 5).sshHost)
    }

    private func mc7530Fixture(_ name: String) throws -> Data {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/MC7530CA", isDirectory: true)
        return try Data(contentsOf: directory.appendingPathComponent(name))
    }

    private func testRegistry(
        zte: TestMockModemBackend? = nil,
        vos: TestMockModemBackend? = nil
    ) throws -> ModemBackendRegistry {
        var registrations: [ModemBackendRegistration] = []
        if let zte {
            registrations.append(ModemBackendRegistration(
                backend: zte,
                discoveryProfile: ModemDiscoveryProfile(
                    kind: .zteMC7530CA,
                    defaultBaseURLs: [URL(string: "http://192.168.254.1")!]
                ),
                identificationCredentials: .configuredOrAnonymous(.web),
                statusCredentials: .configured(.web)
            ))
        }
        if let vos {
            registrations.append(ModemBackendRegistration(
                backend: vos,
                discoveryProfile: ModemDiscoveryProfile(
                    kind: .vos5G,
                    defaultBaseURLs: [URL(string: "http://192.168.225.1")!]
                ),
                identificationCredentials: .configured(.ssh),
                statusCredentials: .configured(.ssh)
            ))
        }
        return try ModemBackendRegistry(registrations: registrations)
    }

    private func discoveryInterface(
        name: String,
        index: UInt32,
        address: String,
        prefixLength: UInt8,
        router: String?,
        isPrimary: Bool = false,
        kind: NetworkInterfaceKind = .physical,
        isUp: Bool = true,
        isRunning: Bool = true
    ) -> NetworkInterfaceSnapshot {
        NetworkInterfaceSnapshot(
            name: name,
            index: index,
            serviceID: "fixture-\(name)",
            kind: kind,
            isUp: isUp,
            isRunning: isRunning,
            isPrimary: isPrimary,
            addresses: [IPv4InterfaceAddress(
                address: IPv4HostAddress(string: address)!,
                prefixLength: prefixLength
            )],
            router: router.flatMap(IPv4HostAddress.init(string:))
        )
    }

    private func data(_ hex: String) -> Data { try! QMIParser.data(fromHex: hex) }

    private func le16(_ value: UInt16) -> Data {
        Data([UInt8(truncatingIfNeeded: value), UInt8(truncatingIfNeeded: value >> 8)])
    }

    private func le32(_ value: UInt32) -> Data {
        Data([
            UInt8(truncatingIfNeeded: value),
            UInt8(truncatingIfNeeded: value >> 8),
            UInt8(truncatingIfNeeded: value >> 16),
            UInt8(truncatingIfNeeded: value >> 24)
        ])
    }

    private func lteLocationCell(
        pci: UInt16,
        rsrqTenths: Int16,
        rsrpTenths: Int16,
        rssiTenths: Int16
    ) -> Data {
        var result = le16(pci)
        result.append(le16(UInt16(bitPattern: rsrqTenths)))
        result.append(le16(UInt16(bitPattern: rsrpTenths)))
        result.append(le16(UInt16(bitPattern: rssiTenths)))
        result.append(le16(UInt16(bitPattern: -50)))
        return result
    }

    private func qmiResponse(
        message: UInt16,
        transaction: UInt16 = 1,
        tlvs: [(UInt8, Data)] = [],
        resultStatus: UInt16 = 0,
        resultError: UInt16 = 0
    ) -> Data {
        var result = le16(resultStatus)
        result.append(le16(resultError))
        var payload = tlv(0x02, result)
        for (type, value) in tlvs {
            payload.append(tlv(type, value))
        }

        var response = Data([0x02])
        response.append(contentsOf: le16(transaction))
        response.append(contentsOf: le16(message))
        response.append(contentsOf: le16(UInt16(payload.count)))
        response.append(payload)
        return response
    }

    private func qmiRequest(
        message: UInt16,
        transaction: UInt16 = 1,
        tlvs: [(UInt8, Data)]
    ) -> Data {
        var payload = Data()
        for (type, value) in tlvs { payload.append(tlv(type, value)) }

        var request = Data([0x00])
        request.append(le16(transaction))
        request.append(le16(message))
        request.append(le16(UInt16(payload.count)))
        request.append(payload)
        return request
    }

    private func tlv(_ type: UInt8, _ value: Data) -> Data {
        var result = Data([type])
        result.append(le16(UInt16(value.count)))
        result.append(value)
        return result
    }
}

private final class EmptyTestCredentialStore: CredentialStoring, @unchecked Sendable {
    func password(for account: String) throws -> String? { nil }
    func setPassword(_ password: String, for account: String) throws {}
    func removePassword(for account: String) throws {}
}

private struct FixedNetworkTopologyProvider: NetworkTopologyProviding {
    let storedSnapshot: NetworkTopologySnapshot

    init(snapshot: NetworkTopologySnapshot) {
        storedSnapshot = snapshot
    }

    func snapshot() -> NetworkTopologySnapshot { storedSnapshot }
}

private func modemIdentity(for kind: ModemKind) -> ModemIdentity {
    ModemIdentity(
        kind: kind,
        manufacturer: "fixture",
        model: "fixture-\(kind.rawValue)"
    )
}

private enum TestSupportError: Error {
    case missingResponse
    case plannedSnapshotFailure
}

private func testZTEResponse(_ json: String) -> ZTEHTTPResponse {
    ZTEHTTPResponse(statusCode: 200, headers: [:], body: Data(json.utf8))
}

private func testZTECallResponse(_ payloadObjectJSON: String) -> ZTEHTTPResponse {
    testZTEResponse("[{\"jsonrpc\":\"2.0\",\"id\":3,\"result\":[0,\(payloadObjectJSON)]}]")
}

private func testZTEStatusResponse(_ status: Int) -> ZTEHTTPResponse {
    testZTEResponse("[{\"jsonrpc\":\"2.0\",\"id\":3,\"result\":[\(status)]}]")
}

private struct TestZTERequestRecord: Sendable {
    let headers: [String: String]
    let bodyText: String
    let route: ZTEHTTPRoute
    let rpcMethod: String?
    let sessionID: String?
    let ubusMethod: String?
    let loginUsername: String?
    let loginPassword: String?

    func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

private actor TestScriptedZTEHTTPTransport: ZTEHTTPTransport {
    private let responses: [ZTEHTTPResponse]
    private var nextResponse = 0
    private var requestRecords: [TestZTERequestRecord] = []

    init(responses: [ZTEHTTPResponse]) {
        self.responses = responses
    }

    func send(_ request: URLRequest, route: ZTEHTTPRoute) async throws -> ZTEHTTPResponse {
        requestRecords.append(Self.record(request, route: route))
        guard nextResponse < responses.count else { throw TestSupportError.missingResponse }
        defer { nextResponse += 1 }
        return responses[nextResponse]
    }

    func records() -> [TestZTERequestRecord] { requestRecords }
    func requestCount() -> Int { requestRecords.count }

    private static func record(_ request: URLRequest, route: ZTEHTTPRoute) -> TestZTERequestRecord {
        let body = request.httpBody ?? Data()
        let batch = (try? JSONSerialization.jsonObject(with: body)) as? [[String: Any]]
        let rpc = batch?.first
        let params = rpc?["params"] as? [Any]
        let callParameters = params.flatMap { $0.count > 3 ? $0[3] as? [String: Any] : nil }
        return TestZTERequestRecord(
            headers: request.allHTTPHeaderFields ?? [:],
            bodyText: String(decoding: body, as: UTF8.self),
            route: route,
            rpcMethod: rpc?["method"] as? String,
            sessionID: params?.first as? String,
            ubusMethod: params.flatMap { $0.count > 2 ? $0[2] as? String : nil },
            loginUsername: callParameters?["username"] as? String,
            loginPassword: callParameters?["password"] as? String
        )
    }
}

private struct TestRacingExpiryHistory: Sendable {
    let loginCount: Int
    let netinfoSessions: [String]
}

/// Releases two stale-SID reads in an order that reproduces the race where a
/// late permission-denied response arrives after another read installed sid-two.
private actor TestRacingExpiryZTEHTTPTransport: ZTEHTTPTransport {
    private var loginCount = 0
    private var oldReadCount = 0
    private var netinfoSessions: [String] = []
    private var firstOldRead: CheckedContinuation<ZTEHTTPResponse, Never>?
    private var secondOldRead: CheckedContinuation<ZTEHTTPResponse, Never>?

    func send(_ request: URLRequest, route: ZTEHTTPRoute) async throws -> ZTEHTTPResponse {
        _ = route
        guard let body = request.httpBody,
              let batch = try JSONSerialization.jsonObject(with: body) as? [[String: Any]],
              let rpc = batch.first,
              let params = rpc["params"] as? [Any],
              params.count > 2,
              let sessionID = params[0] as? String,
              let method = params[2] as? String
        else { throw TestSupportError.missingResponse }

        switch method {
        case "web_login_info":
            return testZTECallResponse(#"{"zte_web_sault":"race-salt"}"#)
        case "web_login":
            loginCount += 1
            let sid: String
            switch loginCount {
            case 1: sid = "sid-one"
            case 2: sid = "sid-two"
            default: sid = "sid-three"
            }
            return testZTECallResponse("{\"result\":\"0\",\"ubus_rpc_session\":\"\(sid)\"}")
        case "nwinfo_get_netinfo":
            netinfoSessions.append(sessionID)
            if sessionID == "sid-one" {
                oldReadCount += 1
                if oldReadCount == 1 {
                    return await withCheckedContinuation { firstOldRead = $0 }
                }
                return await withCheckedContinuation { continuation in
                    secondOldRead = continuation
                    let first = firstOldRead
                    firstOldRead = nil
                    first?.resume(returning: testZTEStatusResponse(6))
                }
            }
            if sessionID == "sid-two", let delayed = secondOldRead {
                secondOldRead = nil
                delayed.resume(returning: testZTEStatusResponse(6))
            }
            return testZTECallResponse(#"{"network_type":"ENDC"}"#)
        default:
            throw TestSupportError.missingResponse
        }
    }

    func history() -> TestRacingExpiryHistory {
        TestRacingExpiryHistory(
            loginCount: loginCount,
            netinfoSessions: netinfoSessions
        )
    }
}

private struct TestBackendHistory: Sendable {
    let identifyCredentials: [ModemCredentials]
    let fetchCredentials: [ModemCredentials]
}

private actor TestMockModemBackend: ModemStatusBackend {
    nonisolated let kind: ModemKind
    nonisolated let capabilities: ModemCapability = [.identityRead, .statusRead]

    private let identity: ModemIdentity?
    private var fetchFailures: [Bool]
    private var identifyCredentials: [ModemCredentials] = []
    private var fetchCredentials: [ModemCredentials] = []

    init(kind: ModemKind, fetchFailures: [Bool] = [], identifies: Bool = true) {
        self.kind = kind
        self.fetchFailures = fetchFailures
        self.identity = identifies ? modemIdentity(for: kind) : nil
    }

    func identify(endpoint: ScopedEndpoint, credentials: ModemCredentials) async throws -> ModemIdentity? {
        _ = endpoint
        identifyCredentials.append(credentials)
        return identity
    }

    func fetchSnapshot(endpoint: ScopedEndpoint, credentials: ModemCredentials) async throws -> DeviceSnapshot {
        fetchCredentials.append(credentials)
        if !fetchFailures.isEmpty, fetchFailures.removeFirst() {
            throw TestSupportError.plannedSnapshotFailure
        }
        var snapshot = DeviceSnapshot.empty
        snapshot.host = endpoint.host ?? "fixture"
        snapshot.interfaceName = endpoint.interfaceName
        return snapshot
    }

    func history() -> TestBackendHistory {
        TestBackendHistory(
            identifyCredentials: identifyCredentials,
            fetchCredentials: fetchCredentials
        )
    }
}
