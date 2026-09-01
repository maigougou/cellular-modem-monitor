import Foundation

@main
enum DirectTests {
    private static let lteBand = "02010031002400020400000000000106000108790084031108000108790084030000120600010805000000"
    private static let noActiveBand = "0201003100070002040000000000"
    private static let signal = "0202004f001c0002040000000000140600b7f394ff2e00170400008000801802000080"
    private static let completeSignal = "0202004f001c0002040000000000140600b7f394ff2e00170400acff7b00180200f5ff"
    private static let serving = "02030024004c000204000000000001060001010102010810010001110200010b120a002e01dc000554454c55531503000108011b0100011d040001000000210500000000000024020001002705002e01dc0001"
    private static let noCA = "020400ac004e00020400000000001008000100640000000000110400ff000000120e0000000000ff000000780000000000130a00010064000500000079001401000015010000160400640000001701000018010000"
    private static let nrAndLTE = "0201003100270002040000000000110f00020c0d0180ac090008790084030000120b00020c0d0000000805000000"
    private static let dsdNSA = "02010024001b000204000000000010110001000000000600000000000000000a0000"
    private static let dsdSA = "02010024001b00020400000000001011000100000000060000000000000000120000"
    private static let dsdLTE = "02010024001b00020400000000001011000100000000030000000010000000000000"
    private static let ca = "020100ac00360002040000000000130a00df008403050000007900151f000229000208050000007b0002000000012a00c0210300000094000100000002"
    private static let legacyNoCA = "020100ac00180002040000000000120e0000000000ff000000780000000000"
    private static let nrCellLocation = "02050043002700020400000000002e0400dea206002f1600030222010203785634120000000029006affa0fbf1ff"
    private static let telusPLMNName = "020700440029000204000000000010140000000000000554454c55530000000554454c55531504000400000016010000"

    static func main() async {
        var failures: [String] = []

        do {
            check(AppLanguage.systemDefault(preferredLanguages: ["zh-Hans-CN", "en-CA"]) == .simplifiedChinese,
                  "Chinese system language default", failures: &failures)
            check(AppLanguage.systemDefault(preferredLanguages: ["en-CA", "zh-Hans-CN"]) == .english,
                  "English system language default", failures: &failures)
            check(AppLanguage.systemDefault(preferredLanguages: []) == .english,
                  "missing system language default", failures: &failures)
            check(
                AppLanguage.resolved(storedValue: AppLanguage.english.rawValue, preferredLanguages: ["zh-Hans"]) == .english,
                "saved language overrides system language",
                failures: &failures
            )
            check(L10n.text("Online", language: .simplifiedChinese) == "在线",
                  "Simplified Chinese lookup", failures: &failures)
            check(L10n.text("Unmapped technical value", language: .simplifiedChinese) == "Unmapped technical value",
                  "localization fallback", failures: &failures)
            check(L10n.format("Selecting %@…", language: .simplifiedChinese, "302-220") == "正在选择 302-220…",
                  "localized format", failures: &failures)
            check(
                NetworkControlOperation.changingArchitecture(.saOnly)
                    .localizedLabel(language: .simplifiedChinese) == "正在应用 仅 SA…",
                "localized operation label",
                failures: &failures
            )
            check(NRArchitectureMode.lteOnly.localizedLabel(language: .simplifiedChinese) == "仅 LTE",
                  "localized LTE-only label", failures: &failures)

            check(
                ModemCapability.neighborMeasurements.supportsDeviceControlSurface,
                "neighbor measurements expose the shared device-control surface",
                failures: &failures
            )
            check(
                !ModemCapability.neighborMeasurements.supportsControlSession &&
                    ModemCapability.networkScan.supportsControlSession,
                "read-only neighbor capability does not open a control session",
                failures: &failures
            )
            check(
                !ModemCapability.statusRead.supportsDeviceControlSurface,
                "status-only capability does not expose device controls",
                failures: &failures
            )

            let ztePresentationIdentity = ModemIdentity(
                kind: .zteMC7530CA,
                manufacturer: "ZTE",
                model: "MC7530CA",
                displayName: "ZTE MC7530CA / G5 MAX"
            )
            check(
                ztePresentationIdentity.compactDisplayName == "MC7530CA / G5 MAX",
                "ZTE compact header presentation",
                failures: &failures
            )
            let vosPresentationIdentity = ModemIdentity(
                kind: .vos5G,
                manufacturer: "Generic",
                model: "VOS",
                displayName: "My VOS modem"
            )
            check(
                vosPresentationIdentity.compactDisplayName == "My VOS modem",
                "VOS header preserves its configured display name",
                failures: &failures
            )

            let presentationEndpointA = ScopedEndpoint(
                baseURL: URL(string: "http://192.168.254.1")!,
                interfaceName: "en8",
                interfaceIndex: 8,
                sourceAddress: "192.168.254.2"
            )
            let presentationEndpointB = ScopedEndpoint(
                baseURL: URL(string: "http://192.168.254.1")!,
                interfaceName: "en9",
                interfaceIndex: 9,
                sourceAddress: "192.168.254.3",
                connectionPath: .routed,
                gateway: "192.168.8.1"
            )
            check(
                ControlPresentationInvalidation.transition(
                    previousModemID: "modem-a",
                    nextModemID: "modem-a",
                    previousEndpoint: presentationEndpointA,
                    nextEndpoint: presentationEndpointA,
                    previousPLMN: "00101",
                    nextPLMN: "00102"
                ) == .operatorContext &&
                    ControlPresentationInvalidation.transition(
                        previousModemID: "modem-a",
                        nextModemID: "modem-b",
                        previousEndpoint: presentationEndpointA,
                        nextEndpoint: presentationEndpointA,
                        previousPLMN: "00101",
                        nextPLMN: "00101"
                    ) == .all &&
                    ControlPresentationInvalidation.transition(
                        previousModemID: "modem-a",
                        nextModemID: "modem-a",
                        previousEndpoint: presentationEndpointA,
                        nextEndpoint: presentationEndpointA,
                        previousPLMN: "00101",
                        nextPLMN: "00101"
                    ) == .none &&
                    ControlPresentationInvalidation.transition(
                        previousModemID: "modem-a",
                        nextModemID: "modem-a",
                        previousEndpoint: presentationEndpointA,
                        nextEndpoint: presentationEndpointB,
                        previousPLMN: "00101",
                        nextPLMN: "00101"
                    ) == .all,
                "control presentation invalidation distinguishes PLMN and modem changes",
                failures: &failures
            )
            check(
                ModemOperationInterruption.isCancellation(CancellationError()) &&
                    !ModemOperationInterruption.isCancellation(
                        ModemControlError.commandRejected("fixture")
                    ) &&
                    ModemOperationInterruption.shouldIgnoreRefreshFailure(
                        ModemCoordinatorError.noMatchingModem,
                        taskIsCancelled: true
                    ) &&
                    !ModemOperationInterruption.shouldIgnoreRefreshFailure(
                        ModemControlError.rollbackFailed(
                            operation: "fixture",
                            rollback: "fixture"
                        ),
                        taskIsCancelled: false
                    ),
                "cancellation is quiet while real refresh/control failures remain visible",
                failures: &failures
            )

            let priorSelection = OperatorSelection(
                mode: .manual,
                operatorName: "Fixture",
                plmn: "00101",
                accessTechnology: .lte5GC
            )
            let priorControlState = ModemControlState(
                operatorSelection: priorSelection,
                architecture: .nsaOnly,
                saBands: [77],
                nsaBands: [66, 77],
                lteBands: [2, 4, 66],
                canRestoreDefaults: true,
                preferenceLifetime: .persistent
            )
            let plmnChangedState = priorControlState.clearingOperatorSelection()
            check(
                plmnChangedState.operatorSelection == nil &&
                    plmnChangedState.architecture == priorControlState.architecture &&
                    plmnChangedState.saBands == priorControlState.saBands &&
                    plmnChangedState.nsaBands == priorControlState.nsaBands &&
                    plmnChangedState.lteBands == priorControlState.lteBands &&
                    plmnChangedState.canRestoreDefaults == priorControlState.canRestoreDefaults &&
                    plmnChangedState.preferenceLifetime == priorControlState.preferenceLifetime,
                "PLMN change preserves verified radio and restore state",
                failures: &failures
            )

            let presentationSuiteName = "DirectTests.control-result.\(UUID().uuidString)"
            let presentationDefaults = UserDefaults(suiteName: presentationSuiteName)!
            presentationDefaults.removePersistentDomain(forName: presentationSuiteName)
            let previousDemoEnvironment = ProcessInfo.processInfo.environment["SIGNAL_STATUS_DEMO"]
            setenv("SIGNAL_STATUS_DEMO", "1", 1)
            let presentationModel = await MainActor.run {
                StatusModel(
                    defaults: presentationDefaults,
                    credentialStore: DirectCredentialStore(values: [:])
                )
            }
            if let previousDemoEnvironment {
                setenv("SIGNAL_STATUS_DEMO", previousDemoEnvironment, 1)
            } else {
                unsetenv("SIGNAL_STATUS_DEMO")
            }
            let selectionSynchronization = await MainActor.run { () -> (Bool, Bool) in
                presentationModel.applyControlResult(ModemControlResult(state: priorControlState))
                let populated = presentationModel.operatorSelection == priorSelection
                presentationModel.applyControlResult(ModemControlResult(state: plmnChangedState))
                let cleared = presentationModel.operatorSelection == nil &&
                    presentationModel.controlState?.operatorSelection == nil &&
                    presentationModel.controlState?.architecture == .nsaOnly &&
                    presentationModel.canRestoreControlDefaults
                return (populated, cleared)
            }
            presentationDefaults.removePersistentDomain(forName: presentationSuiteName)
            check(
                selectionSynchronization.0 && selectionSynchronization.1,
                "authoritative nil operator selection clears stale UI state",
                failures: &failures
            )

            check(
                ModemControlError.rollbackFailed(
                    operation: "Band update failed.",
                    rollback: "Reset was rejected"
                ).errorDescription ==
                    "Band update failed. Automatic rollback also failed: Reset was rejected. The modem control state is unknown.",
                "rollback failure message separates recovery detail",
                failures: &failures
            )
            check(
                ModemControlError.rollbackFailed(
                    operation: "Band update failed.",
                    rollback: "Reset timed out!"
                ).errorDescription ==
                    "Band update failed. Automatic rollback also failed: Reset timed out! The modem control state is unknown.",
                "rollback failure message preserves existing punctuation",
                failures: &failures
            )
            check(
                ModemControlError.rollbackFailed(
                    operation: "Band update failed.",
                    rollback: ""
                ).errorDescription ==
                    "Band update failed. Automatic rollback also failed: No rollback detail was reported. The modem control state is unknown.",
                "rollback failure message handles missing recovery detail",
                failures: &failures
            )

            let operationGuard = ControlOperationDeviceGuard(expectedFingerprint: "device-a")
            try operationGuard.validate(currentFingerprint: "device-a")
            check(operationGuard.isValid, "control operation accepts its bound device", failures: &failures)
            do {
                try operationGuard.validate(currentFingerprint: "device-b")
                failures.append("control operation rejects a replacement device")
            } catch let error as ControlOperationDeviceGuardError {
                check(error == .deviceChanged,
                      "control operation reports device replacement", failures: &failures)
            }
            check(!operationGuard.isValid,
                  "control operation is invalidated after device replacement", failures: &failures)
            check(operationGuard.expectedFingerprint == "device-a",
                  "control operation fingerprint is immutable", failures: &failures)
            checkThrows(
                "invalidated control operation cannot resume on the original device",
                failures: &failures
            ) {
                try operationGuard.validate(currentFingerprint: "device-a")
            }

            check(
                StatusPollingPolicy.interval(userInterval: 30, connectionState: .online) == 30,
                "online polling uses the configured interval",
                failures: &failures
            )
            for state in [
                ConnectionState.connecting,
                .stale,
                .disconnected,
                .authenticationFailed,
                .qmiUnavailable
            ] {
                check(
                    StatusPollingPolicy.interval(userInterval: 60, connectionState: state) == 5,
                    "non-online polling retries every five seconds",
                    failures: &failures
                )
                check(
                    StatusPollingPolicy.interval(userInterval: 1, connectionState: state) == 1,
                    "reconnect polling is not slower than the configured interval",
                    failures: &failures
                )
            }

            let speedEndpoint = ScopedEndpoint(
                baseURL: URL(string: "http://192.168.254.1")!,
                interfaceName: "en8",
                interfaceIndex: 18,
                sourceAddress: "192.168.254.20",
                connectionPath: .directUSB
            )
            let speedActiveModem = ActiveModem(
                identity: ModemIdentity(
                    kind: .zteMC7530CA,
                    manufacturer: "ZTE",
                    model: "MC7530CA",
                    displayName: "G5 MAX",
                    stableIdentifier: "fixture-speed-modem"
                ),
                endpoint: speedEndpoint,
                capabilities: [.statusRead]
            )
            let speedBinding = try SpeedTestBinding(
                activeModem: speedActiveModem,
                settingsGeneration: 7
            )
            check(
                speedBinding.modemID == "fixture-speed-modem" &&
                    speedBinding.interfaceName == "en8" &&
                    speedBinding.interfaceIndex == 18 &&
                    speedBinding.endpoint.sourceAddress == "192.168.254.20" &&
                    speedBinding.settingsGeneration == 7,
                "speed test freezes modem, endpoint, interface and settings identity",
                failures: &failures
            )
            do {
                _ = try SpeedTestBinding(
                    activeModem: ActiveModem(
                        identity: speedActiveModem.identity,
                        endpoint: ScopedEndpoint(baseURL: speedEndpoint.baseURL),
                        capabilities: [.statusRead]
                    ),
                    settingsGeneration: 7
                )
                failures.append("speed test must reject an unscoped modem endpoint")
            } catch let error as SpeedTestError {
                check(
                    error == .interfaceBindingUnavailable,
                    "speed test reports missing interface binding",
                    failures: &failures
                )
            }

            let speedJSON = Data(#"""
            {
                "interface_name":"en8",
                "dl_throughput":812345678.0,
                "ul_throughput":"123456789",
                "responsiveness":481,
                "base_rtt":31.5,
                "duration":16.25
            }
            """#.utf8)
            let parsedSpeed = try NetworkQualityResultParser.parse(
                speedJSON,
                binding: speedBinding,
                completedAt: Date(timeIntervalSince1970: 123)
            )
            check(
                parsedSpeed.downloadBitsPerSecond == 812_345_678 &&
                    parsedSpeed.uploadBitsPerSecond == 123_456_789 &&
                    parsedSpeed.responsivenessRPM == 481 &&
                    parsedSpeed.idleLatencyMilliseconds == 31.5 &&
                    parsedSpeed.duration == 16.25 &&
                    parsedSpeed.binding == speedBinding,
                "networkQuality JSON preserves final throughput and verified binding",
                failures: &failures
            )

            check(
                NetworkQualityCommand.arguments(interfaceName: "en8", maximumRuntime: 30) == [
                    "-I", "en8",
                    "-M", "30",
                    "-s",
                    "-c"
                ],
                "networkQuality runs download and upload sequentially",
                failures: &failures
            )

            check(
                OoklaSpeedTestCommand.arguments(interfaceName: "en8") == [
                    "--interface=en8",
                    "--format=json",
                    "--progress=no",
                    "--accept-license",
                    "--accept-gdpr"
                ],
                "Ookla command binds only the frozen interface and requests structured output",
                failures: &failures
            )
            let ooklaJSON = Data(#"""
            {
              "type":"result",
              "ping":{"jitter":5.842,"latency":28.963},
              "download":{"bandwidth":18776068,"bytes":133558656,"elapsed":7206},
              "upload":{"bandwidth":2268752,"bytes":12857728,"elapsed":5701},
              "packetLoss":0,
              "interface":{"internalIp":"192.168.254.20","name":"en8"},
              "server":{"name":"Bell Mobility","location":"Nepean, ON"},
              "result":{"url":"https://www.speedtest.net/result/c/fixture-result"}
            }
            """#.utf8)
            let parsedOokla = try OoklaSpeedTestResultParser.parse(
                ooklaJSON,
                binding: speedBinding,
                completedAt: Date(timeIntervalSince1970: 456)
            )
            check(
                parsedOokla.downloadBitsPerSecond == 150_208_544 &&
                    parsedOokla.uploadBitsPerSecond == 18_150_016 &&
                    parsedOokla.idleLatencyMilliseconds == 28.963 &&
                    parsedOokla.jitterMilliseconds == 5.842 &&
                    parsedOokla.packetLossPercent == 0 &&
                    parsedOokla.serverName == "Bell Mobility · Nepean, ON" &&
                    parsedOokla.resultURL?.absoluteString ==
                        "https://www.speedtest.net/result/c/fixture-result" &&
                    parsedOokla.binding == speedBinding,
                "Ookla JSON converts byte rates and preserves verified path metadata",
                failures: &failures
            )
            do {
                let wrongSource = Data(#"""
                {
                  "type":"result",
                  "download":{"bandwidth":1},
                  "upload":{"bandwidth":1},
                  "interface":{"internalIp":"192.168.254.99","name":"en8"}
                }
                """#.utf8)
                _ = try OoklaSpeedTestResultParser.parse(wrongSource, binding: speedBinding)
                failures.append("Ookla result must reject a changed source address")
            } catch let error as SpeedTestError {
                check(
                    error == .reportedSourceAddressMismatch(
                        expected: "192.168.254.20",
                        actual: "192.168.254.99"
                    ),
                    "Ookla result fails closed on source-address mismatch",
                    failures: &failures
                )
            }

            let unavailableModel = await MainActor.run {
                SpeedTestModel(runner: DirectUnavailableSpeedTestRunner())
            }
            await MainActor.run {
                unavailableModel.updateActiveModem(speedActiveModem, settingsGeneration: 7)
            }
            let unavailablePresentation = await MainActor.run {
                (unavailableModel.state, unavailableModel.canStart)
            }
            check(
                unavailablePresentation.0 == .unavailable(.ooklaCLIUnavailable) &&
                    !unavailablePresentation.1,
                "missing official Ookla CLI is visible before a test can start",
                failures: &failures
            )

            var firstInterfaceMessage = if_msghdr2()
            firstInterfaceMessage.ifm_msglen = UInt16(MemoryLayout<if_msghdr2>.size)
            firstInterfaceMessage.ifm_type = UInt8(RTM_IFINFO2)
            firstInterfaceMessage.ifm_index = 1
            firstInterfaceMessage.ifm_data.ifi_ibytes = 10
            firstInterfaceMessage.ifm_data.ifi_obytes = 20
            var shortAddressMessage = Data(repeating: 0, count: 60)
            shortAddressMessage.withUnsafeMutableBytes { raw in
                raw.storeBytes(of: UInt16(60), as: UInt16.self)
                raw[3] = UInt8(RTM_NEWADDR)
            }
            var targetInterfaceMessage = if_msghdr2()
            targetInterfaceMessage.ifm_msglen = UInt16(MemoryLayout<if_msghdr2>.size)
            targetInterfaceMessage.ifm_type = UInt8(RTM_IFINFO2)
            targetInterfaceMessage.ifm_index = 18
            targetInterfaceMessage.ifm_data.ifi_ibytes = 987_654_321
            targetInterfaceMessage.ifm_data.ifi_obytes = 123_456_789
            var mixedRouteMessages = withUnsafeBytes(of: &firstInterfaceMessage) { Data($0) }
            mixedRouteMessages.append(shortAddressMessage)
            mixedRouteMessages.append(withUnsafeBytes(of: &targetInterfaceMessage) { Data($0) })
            check(
                NetworkInterfaceTrafficMessageParser.counters(
                    in: mixedRouteMessages,
                    interfaceIndex: 18
                ) == NetworkInterfaceByteCounters(
                    receivedBytes: 987_654_321,
                    sentBytes: 123_456_789
                ),
                "IFLIST2 parser skips short NEWADDR records before the target interface",
                failures: &failures
            )
            do {
                _ = try NetworkQualityResultParser.parse(
                    Data(#"{"interface_name":"en0","dl_throughput":1,"ul_throughput":1}"#.utf8),
                    binding: speedBinding
                )
                failures.append("speed test must reject a result from another interface")
            } catch let error as SpeedTestError {
                check(
                    error == .reportedInterfaceMismatch(expected: "en8", actual: "en0"),
                    "speed test fails closed on final interface mismatch",
                    failures: &failures
                )
            }

            let routedBinding = try SpeedTestBinding(
                activeModem: ActiveModem(
                    identity: speedActiveModem.identity,
                    endpoint: ScopedEndpoint(
                        baseURL: speedEndpoint.baseURL,
                        interfaceName: "en8",
                        interfaceIndex: 18,
                        sourceAddress: "192.168.8.25",
                        connectionPath: .routed,
                        gateway: "192.168.8.1"
                    ),
                    capabilities: [.statusRead]
                ),
                settingsGeneration: 7
            )
            let changedGatewayReader = SystemNetworkInterfaceTrafficReader(
                topologyProvider: DirectFixedNetworkTopologyProvider(
                    snapshot: NetworkTopologySnapshot(interfaces: [
                        NetworkInterfaceSnapshot(
                            name: "en8",
                            index: 18,
                            serviceID: "fixture",
                            kind: .physical,
                            isUp: true,
                            isRunning: true,
                            isPrimary: true,
                            addresses: [IPv4InterfaceAddress(
                                address: IPv4HostAddress(string: "192.168.8.25")!,
                                prefixLength: 24
                            )],
                            router: IPv4HostAddress(string: "192.168.8.254")
                        )
                    ])
                )
            )
            do {
                _ = try changedGatewayReader.read(binding: routedBinding)
                failures.append("speed test must reject a changed Mac-side gateway")
            } catch let error as SpeedTestError {
                check(
                    error == .gatewayChanged(
                        expected: "192.168.8.1",
                        actual: "192.168.8.254"
                    ),
                    "speed test fails closed when the routed next hop changes",
                    failures: &failures
                )
            }

            let counterStart = ContinuousClock.now
            let failingTraffic = DirectSpeedTestTrafficReader(results: [
                .success(NetworkInterfaceTraffic(
                    receivedBytes: 100,
                    sentBytes: 50,
                    sampledAt: counterStart
                )),
                .failure(.interfaceInactive("en8"))
            ])
            let suspendedProcess = DirectNetworkQualityProcess(
                output: NetworkQualityProcessOutput(
                    standardOutput: speedJSON,
                    standardError: Data(),
                    terminationStatus: 0
                ),
                suspend: true
            )
            let failClosedRunner = NetworkQualitySpeedTestRunner(
                process: suspendedProcess,
                trafficReader: failingTraffic,
                maximumRuntime: 30,
                sampleIntervalNanoseconds: 1_000_000
            )
            do {
                _ = try await failClosedRunner.run(binding: speedBinding) { _ in }
                failures.append("speed test must stop when its bound interface changes")
            } catch let error as SpeedTestError {
                check(
                    error == .interfaceInactive("en8"),
                    "sampler topology failure aborts the in-flight speed test",
                    failures: &failures
                )
            }

            let switchRunner = DirectSpeedTestRunner(suspend: true)
            let switchModel = await MainActor.run { SpeedTestModel(runner: switchRunner) }
            await MainActor.run {
                switchModel.updateActiveModem(speedActiveModem, settingsGeneration: 7)
                switchModel.start()
            }
            await switchRunner.waitForRun()
            let replacementModem = ActiveModem(
                identity: ModemIdentity(
                    kind: .zteMC7530CA,
                    manufacturer: "ZTE",
                    model: "MC7530CA",
                    displayName: "Replacement",
                    stableIdentifier: "fixture-speed-replacement"
                ),
                endpoint: ScopedEndpoint(
                    baseURL: URL(string: "http://192.168.254.1")!,
                    interfaceName: "en9",
                    interfaceIndex: 19,
                    sourceAddress: "192.168.254.21",
                    connectionPath: .directEthernet
                ),
                capabilities: [.statusRead]
            )
            await MainActor.run {
                switchModel.updateActiveModem(replacementModem, settingsGeneration: 8)
            }
            let switchCancelled = await switchRunner.waitForCancel()
            let switchedPresentation = await MainActor.run {
                (switchModel.state, switchModel.boundInterfaceName, switchModel.canStart)
            }
            check(
                switchCancelled &&
                    switchedPresentation.0 == .ready &&
                    switchedPresentation.1 == "en9" &&
                    switchedPresentation.2,
                "device replacement cancels and clears the old speed test before rebinding",
                failures: &failures
            )

            let rapidRunner = DirectSpeedTestRunner(suspend: true)
            let rapidModel = await MainActor.run { SpeedTestModel(runner: rapidRunner) }
            await MainActor.run {
                rapidModel.updateActiveModem(speedActiveModem, settingsGeneration: 7)
                rapidModel.start()
            }
            await rapidRunner.waitForRun()
            await MainActor.run {
                rapidModel.updateActiveModem(replacementModem, settingsGeneration: 8)
                rapidModel.start()
            }
            let rapidSecondRunStarted = await rapidRunner.waitForRuns(2)
            let rapidOldRunCancelled = await rapidRunner.waitForCancel()
            let rapidPresentation = await MainActor.run {
                (rapidModel.isRunning, rapidModel.boundInterfaceName)
            }
            check(
                rapidSecondRunStarted && rapidOldRunCancelled &&
                    rapidPresentation.0 && rapidPresentation.1 == "en9",
                "immediate restart after modem replacement keeps the new bound test",
                failures: &failures
            )
            await MainActor.run { rapidModel.cancel() }

            let repeatRunner = DirectSpeedTestRunner(suspend: false)
            let repeatModel = await MainActor.run { SpeedTestModel(runner: repeatRunner) }
            await MainActor.run {
                repeatModel.updateActiveModem(speedActiveModem, settingsGeneration: 7)
                repeatModel.start()
            }
            await repeatRunner.waitForRuns(1)
            await waitForDirectSpeedTestCompletion(repeatModel)
            await MainActor.run { repeatModel.start() }
            await repeatRunner.waitForRuns(2)
            await waitForDirectSpeedTestCompletion(repeatModel)
            let repeatedState = await MainActor.run { repeatModel.state }
            let repeatedRunCount = await repeatRunner.runCount()
            check(
                repeatedRunCount == 2 && {
                    if case .completed = repeatedState { return true }
                    return false
                }(),
                "completed speed tests can be run again with a fresh bound operation",
                failures: &failures
            )

            var refreshCoalescer = RefreshCoalescer()
            check(
                refreshCoalescer.request(isRefreshing: false, isControlBusy: false),
                "idle refresh starts immediately",
                failures: &failures
            )
            refreshCoalescer.beginRefresh()
            check(
                !refreshCoalescer.request(isRefreshing: true, isControlBusy: false) &&
                    refreshCoalescer.isPending,
                "in-flight refresh is coalesced",
                failures: &failures
            )
            check(
                refreshCoalescer.shouldDrain(isRefreshing: false, isControlBusy: false),
                "coalesced refresh drains when idle",
                failures: &failures
            )
            refreshCoalescer.beginRefresh()
            check(
                !refreshCoalescer.request(isRefreshing: false, isControlBusy: true) &&
                    refreshCoalescer.isPending,
                "control-busy refresh is retained",
                failures: &failures
            )

            let interfaceCandidates = [
                LocalInterfaceCandidate(name: "en12", address: "192.168.225.10", isActive: false),
                LocalInterfaceCandidate(name: "en13", address: "10.0.0.2", isActive: true),
                LocalInterfaceCandidate(name: "en14", address: "192.168.225.20", isActive: true),
                LocalInterfaceCandidate(name: "en15", address: "192.168.225.30", isActive: true)
            ]
            check(
                LocalInterface.selectVOSInterface(
                    candidates: interfaceCandidates,
                    routedSourceAddress: "192.168.225.30"
                ) == interfaceCandidates[3],
                "VOS interface selection prefers the active routed source",
                failures: &failures
            )
            check(
                LocalInterface.selectVOSInterface(
                    candidates: interfaceCandidates,
                    routedSourceAddress: "192.168.225.10"
                ) == interfaceCandidates[3],
                "VOS interface selection rejects stale routes and prefers the newest active interface",
                failures: &failures
            )
            check(
                LocalInterface.selectVOSInterface(
                    candidates: interfaceCandidates,
                    routedSourceAddress: nil
                ) == interfaceCandidates[3],
                "VOS interface selection prefers the newest active interface without a route",
                failures: &failures
            )

            let radios = try QMIParser.activeRadios(from: data(lteBand))
            check(radios.count == 1, "LTE RF count", failures: &failures)
            check(radios.first?.band == "B2", "LTE B2", failures: &failures)
            check(radios.first?.channel == 900, "LTE EARFCN", failures: &failures)
            check(radios.first?.bandwidthMHz == 20, "LTE bandwidth", failures: &failures)

            let combined = try QMIParser.activeRadios(from: data(nrAndLTE))
            check(combined.map(\.band) == ["n78", "B2"], "NR/LTE bands", failures: &failures)
            check(combined.map(\.channel) == [633_984, 900], "NR/LTE channels", failures: &failures)
            check(combined.map(\.bandwidthMHz) == [50, 20], "parallel bandwidths", failures: &failures)

            let noServiceSnapshot = try VOSClient.makeSnapshot(
                host: "192.168.225.1",
                interfaceName: "en13",
                probe: VOSProbeOutput(
                    band: data(noActiveBand), signal: data(completeSignal), serving: nil, ca: data(ca),
                    location: data(nrCellLocation), dsd: data(dsdNSA),
                    modemVersion: nil, deviceFirmware: nil
                )
            )
            check(!noServiceSnapshot.hasRadioData, "no-band response is reachable no-service", failures: &failures)
            check(noServiceSnapshot.modeLabel == "Searching", "no-band response is searching", failures: &failures)
            check(noServiceSnapshot.nrSignal == .empty && noServiceSnapshot.lteSignal == .empty,
                  "no-band response clears radio metrics", failures: &failures)
            check(noServiceSnapshot.nrGlobalCellID == nil && noServiceSnapshot.ltePrimaryCell == nil,
                  "no-band response clears stale cell details", failures: &failures)
            check(
                CellMapperLink.destination(
                    for: 385_739_387,
                    radio: .lte,
                    mcc: nil,
                    mnc: nil
                )?.absoluteString == "https://www.cellmapper.net/enbid?net=LTE&cellid=385739387",
                "CellMapper LTE calculator link",
                failures: &failures
            )
            check(
                CellMapperLink.destination(
                    for: 0x1234_5678,
                    radio: .nr,
                    mcc: "302",
                    mnc: "220"
                )?.absoluteString == "https://www.cellmapper.net/map?MCC=302&MNC=220&type=NR&showTowers=true&showTowerLabels=true",
                "CellMapper NR provider-map link",
                failures: &failures
            )
            check(
                CellMapperLink.destination(
                    for: 1,
                    radio: .nr,
                    mcc: "30A",
                    mnc: "220"
                )?.absoluteString == "https://www.cellmapper.net/map?type=NR&showTowers=true&showTowerLabels=true",
                "CellMapper omits malformed PLMN",
                failures: &failures
            )

            let levels = try QMIParser.signalInfo(from: data(signal))
            check(levels.lteRSSI == -73, "LTE RSSI", failures: &failures)
            check(levels.lteRSRQ == -13, "LTE RSRQ", failures: &failures)
            check(levels.lteRSRP == -108, "LTE RSRP", failures: &failures)
            check(levels.lteSNR == 4.6, "LTE SNR", failures: &failures)
            check(levels.nrRSRP == nil, "NR sentinel hidden", failures: &failures)
            check(levels.nrRSRQ == nil && levels.nrSNR == nil, "NR metric sentinels hidden", failures: &failures)

            let completeLevels = try QMIParser.signalInfo(from: data(completeSignal))
            check(completeLevels.nrRSRQ == -11, "NR RSRQ", failures: &failures)
            check(completeLevels.nrRSRP == -84, "NR RSRP", failures: &failures)
            check(completeLevels.nrSNR == 12.3, "NR SNR", failures: &failures)

            let network = try QMIParser.servingInfo(from: data(serving))
            check(network.operatorName == "TELUS", "operator", failures: &failures)
            check(network.mcc == "302" && network.mnc == "220", "PLMN", failures: &failures)
            let eons = try QMIParser.plmnName(from: data(telusPLMNName))
            check(eons.displayName == "TELUS", "QMI PLMN-name fallback", failures: &failures)
            check(
                QMIParser.getPLMNNameRequest(
                    mcc: 302,
                    mnc: 220,
                    mncHasThreeDigits: true,
                    transaction: 7
                ) == qmiRequest(
                    message: 0x0044,
                    transaction: 7,
                    tlvs: [(0x01, le16(302) + le16(220)), (0x11, Data([1]))]
                ),
                "QMI PLMN-name three-digit MNC request",
                failures: &failures
            )
            let cellLocation = try QMIParser.cellLocationInfo(from: data(nrCellLocation))
            check(cellLocation.nrARFCN == 434_910, "NR location ARFCN", failures: &failures)
            check(cellLocation.nr?.globalCellID == 0x1234_5678, "NR global Cell ID", failures: &failures)
            check(cellLocation.nr?.physicalCellID == 41, "NR location PCI", failures: &failures)
            var interfrequency = Data([0, 1])
            interfrequency.append(le16(2_050))
            interfrequency.append(contentsOf: [1, 2, 3, 1])
            interfrequency.append(lteLocationCell(
                pci: 17,
                rsrqTenths: -125,
                rsrpTenths: -1_040,
                rssiTenths: -710
            ))
            let interfrequencyLocation = try QMIParser.cellLocationInfo(from: qmiResponse(
                message: 0x0043,
                tlvs: [(0x14, interfrequency)]
            ))
            check(interfrequencyLocation.lteInterfrequency.first?.earfcn == 2_050, "LTE interfrequency EARFCN", failures: &failures)
            check(interfrequencyLocation.lteInterfrequency.first?.cells.first?.physicalCellID == 17, "LTE interfrequency PCI", failures: &failures)
            check(interfrequencyLocation.lteInterfrequency.first?.cells.first?.signal.rsrpDBm == -104, "LTE interfrequency RSRP", failures: &failures)
            check(try QMIParser.lteSecondaryBands(from: data(noCA)).isEmpty, "inactive CA ignored", failures: &failures)
            let carrierAggregation = try QMIParser.lteCarrierAggregation(from: data(ca))
            check(carrierAggregation.primaryCell?.band == "B2", "LTE CA PCell band", failures: &failures)
            check(carrierAggregation.primaryCell?.earfcn == 900, "LTE CA PCell EARFCN", failures: &failures)
            check(carrierAggregation.primaryCell?.physicalCellID == 223, "LTE CA PCell PCI", failures: &failures)
            check(carrierAggregation.secondaryCells.count == 2, "LTE CA SCell count", failures: &failures)
            check(carrierAggregation.secondaryCells.first?.band == "B4", "LTE CA active SCell", failures: &failures)
            check(carrierAggregation.secondaryCells.last?.state == .configuredDeactivated, "LTE CA inactive SCell state", failures: &failures)
            check(carrierAggregation.activeSecondaryBands == ["B4"], "LTE CA active bands", failures: &failures)

            check(try QMIParser.systemMode(from: data(dsdNSA)) == .nsa, "explicit NSA", failures: &failures)
            check(try QMIParser.systemMode(from: data(dsdSA)) == .sa, "explicit SA", failures: &failures)
            check(try QMIParser.systemMode(from: data(dsdLTE)) == nil, "LTE is not SA/NSA", failures: &failures)

            let currentSelection = try ATCOPSParser.selection(from: """
            AT+COPS?
            +COPS: 0,0,"TELUS",13
            OK
            """)
            check(currentSelection.mode == .automatic, "COPS automatic selection", failures: &failures)
            check(currentSelection.operatorName == "TELUS", "COPS current operator", failures: &failures)
            check(currentSelection.plmn == nil, "COPS alpha operator is not PLMN", failures: &failures)
            check(currentSelection.accessTechnology == .lteNRDualConnectivity, "COPS current NSA access", failures: &failures)

            let manualSelection = try ATCOPSParser.selection(from: """
            +COPS: 1,2,"302220","TELUS",13
            OK
            """)
            check(manualSelection.mode == .manual, "COPS manual selection", failures: &failures)
            check(manualSelection.plmn == "302220", "COPS numeric PLMN", failures: &failures)
            check(manualSelection.operatorName == "TELUS", "COPS EONS operator name", failures: &failures)
            check(manualSelection.formattedPLMN == "302-220", "COPS formatted MCC-MNC", failures: &failures)

            let manualWithoutEONS = try ATCOPSParser.selection(from: """
            +COPS: 1,2,"302220",13
            OK
            """)
            check(manualWithoutEONS.operatorName == nil, "COPS numeric value is not used as an operator name", failures: &failures)

            let identity = OperatorDisplayIdentity.resolve(
                snapshotName: "TELUS",
                snapshotPLMN: "302-220",
                selection: OperatorSelection(
                    mode: .manual,
                    operatorName: nil,
                    plmn: "302610",
                    accessTechnology: .nr5GC
                ),
                scannedNetworks: [CellularNetwork(
                    longName: "Bell",
                    shortName: "BELL",
                    plmn: "302610",
                    availability: .current,
                    accessTechnologies: [.nr5GC]
                )]
            )
            check(identity.formatted == "Bell · 302-610", "operator identity rejects stale snapshot name", failures: &failures)

            let scannedNetworks = try ATCOPSParser.networks(from: """
            AT+COPS=?
            +COPS: (2,"TELUS","TELUS","302220",13),
            (1,"TELUS","TELUS","302220",7),
            (1,"Bell","BELL","302610",11),
            (1,"Bell","BELL","302610",7),
            (3,"Rogers Wireless","ROGERS","302720",7),
            (0,"Unknown","","46001",2),,(0,1,2,3,4),(0,1,2)
            OK
            """)
            check(scannedNetworks.map(\.plmn) == ["302220", "302610", "46001", "302720"], "COPS scan ordering", failures: &failures)
            let telusScan = scannedNetworks.first { $0.plmn == "302220" }
            check(telusScan?.availability == .current, "COPS current beats available", failures: &failures)
            check(telusScan?.accessTechnologies == [.lte, .lteNRDualConnectivity], "COPS repeated PLMN aggregation", failures: &failures)
            check(telusScan?.accessTechnologyLabel == "LTE, 5G NSA", "COPS LTE/NSA label", failures: &failures)
            let bellScan = scannedNetworks.first { $0.plmn == "302610" }
            check(bellScan?.availability == .available, "COPS available network", failures: &failures)
            check(bellScan?.accessTechnologies == [.lte, .nr5GC], "COPS LTE/SA capability", failures: &failures)
            check(scannedNetworks.first { $0.plmn == "302720" }?.availability == .forbidden, "COPS forbidden network", failures: &failures)
            check(scannedNetworks.first { $0.plmn == "46001" }?.availability == .unknown, "COPS unknown network", failures: &failures)
            check(CellularAccessTechnology.lte5GC.label == "LTE / 5GC", "COPS LTE 5GC label", failures: &failures)
            check(CellularAccessTechnology.nr5GC.label == "5G SA", "COPS SA label", failures: &failures)
            check(CellularAccessTechnology.lteNRDualConnectivity.label == "5G NSA", "COPS NSA label", failures: &failures)

            let saBytes = Data((0..<NRBandMask.byteCount).map { UInt8(truncatingIfNeeded: $0) })
            let nsaBytes = Data((0..<NRBandMask.byteCount).map { UInt8(truncatingIfNeeded: 255 - $0) })
            let lteBytes = Data((0..<LTEBandMask.byteCount).map { UInt8(truncatingIfNeeded: $0 * 3) })
            let systemPreferenceResponse = qmiResponse(
                message: 0x0034,
                transaction: 0x1234,
                tlvs: [
                    (0x11, le16(0x0050)),
                    (0x23, lteBytes),
                    (0x2C, saBytes),
                    (0x2D, nsaBytes)
                ]
            )
            let systemPreferences = try QMIParser.systemSelectionPreferences(from: systemPreferenceResponse)
            check(systemPreferences.modePreference == 0x0050, "QMI system mode preference", failures: &failures)
            check(systemPreferences.saBands.bytes == saBytes, "QMI exact SA mask", failures: &failures)
            check(systemPreferences.nsaBands.bytes == nsaBytes, "QMI exact NSA mask", failures: &failures)
            check(systemPreferences.lteBands?.bytes == lteBytes, "QMI exact extended LTE mask", failures: &failures)
            check(systemPreferences.architectureMode == .automatic, "QMI automatic SA/NSA", failures: &failures)
            check(
                QMIParser.getSystemSelectionRequest(transaction: 0x1234) == Data([0x00, 0x34, 0x12, 0x34, 0x00, 0x00, 0x00]),
                "QMI get system preference request",
                failures: &failures
            )

            let saMask = NRBandMask(Data(repeating: 0xA5, count: NRBandMask.byteCount))!
            let nsaMask = NRBandMask(Data(repeating: 0x5A, count: NRBandMask.byteCount))!
            let lteMask = LTEBandMask(bands: [2, 4, 25, 66])!
            check(lteMask.enabledBands == [2, 4, 25, 66], "LTE band-mask bit mapping", failures: &failures)
            check(NRBandMask(bands: [77, 78])?.enabledBands == [77, 78], "NR band-mask bit mapping", failures: &failures)
            check(
                NRSystemSelectionPreferences(modePreference: 0x0010, saBands: saMask, nsaBands: nsaMask).architectureMode == .lteOnly,
                "LTE mode bit without NR is LTE-only",
                failures: &failures
            )
            check(
                NRSystemSelectionPreferences(modePreference: 0x001C, saBands: saMask, nsaBands: nsaMask).architectureMode == .unavailable,
                "LTE plus legacy RAT bits is not mislabeled LTE-only",
                failures: &failures
            )
            check(
                NRSystemSelectionPreferences(modePreference: 0x0040, saBands: saMask, nsaBands: nsaMask).architectureMode == .saOnly,
                "NR-only mode cannot be misclassified as automatic",
                failures: &failures
            )
            check(
                NRSystemSelectionPreferences(modePreference: 0x0050, saBands: .zero, nsaBands: nsaMask).architectureMode == .nsaOnly,
                "LTE+NR with zero SA mask is NSA-only",
                failures: &failures
            )
            let asymmetricBaseline = NRSystemSelectionPreferences(
                modePreference: 0x0050,
                saBands: NRBandMask(bands: [78, 79])!,
                nsaBands: NRBandMask(bands: [77, 78])!,
                lteBands: lteMask
            )
            let currentLTELock = LTEBandMask(bands: [2, 66])!
            let currentPreferences = NRSystemSelectionPreferences(
                modePreference: 0x0050,
                saBands: asymmetricBaseline.saBands,
                nsaBands: asymmetricBaseline.nsaBands,
                lteBands: currentLTELock
            )
            let automaticPreference = try RadioAccessPreferencePlan.make(
                mode: .automatic,
                baseline: asymmetricBaseline,
                current: currentPreferences
            )
            check(automaticPreference.target.modePreference == 0x0050 &&
                  automaticPreference.target.saBands == asymmetricBaseline.saBands &&
                  automaticPreference.target.nsaBands == asymmetricBaseline.nsaBands &&
                  automaticPreference.lteBandsToWrite == nil,
                  "automatic preference plan remains unchanged", failures: &failures)
            let saPreference = try RadioAccessPreferencePlan.make(
                mode: .saOnly,
                baseline: asymmetricBaseline,
                current: currentPreferences
            )
            check(saPreference.target.modePreference == 0x0040 &&
                  saPreference.target.saBands == asymmetricBaseline.saBands &&
                  saPreference.target.nsaBands.isEmpty &&
                  saPreference.lteBandsToWrite == nil,
                  "SA-only preference plan remains unchanged", failures: &failures)
            let nsaPreference = try RadioAccessPreferencePlan.make(
                mode: .nsaOnly,
                baseline: asymmetricBaseline,
                current: currentPreferences
            )
            check(nsaPreference.target.modePreference == 0x0050 &&
                  nsaPreference.target.saBands.isEmpty &&
                  nsaPreference.target.nsaBands == asymmetricBaseline.nsaBands &&
                  nsaPreference.lteBandsToWrite == nil,
                  "NSA-only preference plan remains unchanged", failures: &failures)
            let ltePreference = try RadioAccessPreferencePlan.make(
                mode: .lteOnly,
                baseline: asymmetricBaseline,
                current: currentPreferences,
                activeNRBandLock: [79]
            )
            check(ltePreference.target.modePreference == 0x0010 &&
                  ltePreference.target.saBands.isEmpty &&
                  ltePreference.target.nsaBands.isEmpty &&
                  ltePreference.target.lteBands == currentLTELock &&
                  ltePreference.lteBandsToWrite == currentLTELock &&
                  ltePreference.target.architectureMode == .lteOnly,
                  "LTE-only plan disables NR and preserves the current LTE mask", failures: &failures)
            checkThrows("NR band lock is unavailable in LTE-only mode", failures: &failures) {
                _ = try NRBandLockPlan.make(
                    requested: NRBandMask(bands: [78])!,
                    baseline: asymmetricBaseline,
                    architecture: .lteOnly
                )
            }
            let baselineWithoutLTE = NRSystemSelectionPreferences(
                modePreference: 0x0050,
                saBands: asymmetricBaseline.saBands,
                nsaBands: asymmetricBaseline.nsaBands,
                lteBands: nil
            )
            let lteWithoutReportedMask = try RadioAccessPreferencePlan.make(
                mode: .lteOnly,
                baseline: baselineWithoutLTE,
                current: baselineWithoutLTE
            )
            check(
                lteWithoutReportedMask.lteBandsToWrite == nil &&
                    lteWithoutReportedMask.target.lteBands == nil,
                "LTE-only omits an unavailable extended LTE mask",
                failures: &failures
            )
            checkThrows("LTE-only rejects an explicitly empty LTE mask", failures: &failures) {
                _ = try RadioAccessPreferencePlan.make(
                    mode: .lteOnly,
                    baseline: baselineWithoutLTE,
                    current: NRSystemSelectionPreferences(
                        modePreference: 0x0050,
                        saBands: asymmetricBaseline.saBands,
                        nsaBands: asymmetricBaseline.nsaBands,
                        lteBands: .zero
                    )
                )
            }
            let saOnlyPlan = try NRBandLockPlan.make(
                requested: NRBandMask(bands: [78])!,
                baseline: asymmetricBaseline,
                architecture: .saOnly
            )
            check(saOnlyPlan.saBands.enabledBands == [78] && saOnlyPlan.nsaBands.isEmpty,
                  "SA-only band lock preserves a nonempty SA mask", failures: &failures)
            checkNRPlanError(
                .unsupportedBands(sa: [77], nsa: []),
                "SA-only band lock rejects an NSA-only band",
                failures: &failures
            ) {
                _ = try NRBandLockPlan.make(
                    requested: NRBandMask(bands: [77])!,
                    baseline: asymmetricBaseline,
                    architecture: .saOnly
                )
            }

            let nsaOnlyPlan = try NRBandLockPlan.make(
                requested: NRBandMask(bands: [77])!,
                baseline: asymmetricBaseline,
                architecture: .nsaOnly
            )
            check(nsaOnlyPlan.saBands.isEmpty && nsaOnlyPlan.nsaBands.enabledBands == [77],
                  "NSA-only band lock preserves a nonempty NSA mask", failures: &failures)
            checkNRPlanError(
                .unsupportedBands(sa: [], nsa: [79]),
                "NSA-only band lock rejects an SA-only band",
                failures: &failures
            ) {
                _ = try NRBandLockPlan.make(
                    requested: NRBandMask(bands: [79])!,
                    baseline: asymmetricBaseline,
                    architecture: .nsaOnly
                )
            }

            let automaticPlan = try NRBandLockPlan.make(
                requested: NRBandMask(bands: [78])!,
                baseline: asymmetricBaseline,
                architecture: .automatic
            )
            check(
                NRSystemSelectionPreferences(
                    modePreference: 0x0050,
                    saBands: automaticPlan.saBands,
                    nsaBands: automaticPlan.nsaBands
                ).architectureMode == .automatic,
                "automatic band lock cannot collapse to one architecture",
                failures: &failures
            )
            checkNRPlanError(
                .unsupportedBands(sa: [77], nsa: []),
                "automatic band lock rejects a band missing from SA",
                failures: &failures
            ) {
                _ = try NRBandLockPlan.make(
                    requested: NRBandMask(bands: [77])!,
                    baseline: asymmetricBaseline,
                    architecture: .automatic
                )
            }
            checkNRPlanError(
                .unsupportedBands(sa: [], nsa: [79]),
                "automatic band lock rejects a band missing from NSA",
                failures: &failures
            ) {
                _ = try NRBandLockPlan.make(
                    requested: NRBandMask(bands: [79])!,
                    baseline: asymmetricBaseline,
                    architecture: .automatic
                )
            }

            let disjointBaseline = NRSystemSelectionPreferences(
                modePreference: 0x0050,
                saBands: NRBandMask(bands: [78])!,
                nsaBands: NRBandMask(bands: [77])!
            )
            let activeSALock = NRBandMask(bands: [78])!
            _ = try NRBandLockPlan.make(
                requested: activeSALock,
                baseline: disjointBaseline,
                architecture: .saOnly
            )
            checkThrows("active SA lock cannot switch to NSA-only", failures: &failures) {
                _ = try NRBandLockPlan.make(
                    requested: activeSALock,
                    baseline: disjointBaseline,
                    architecture: .nsaOnly
                )
            }
            checkThrows("active SA lock cannot switch to Auto", failures: &failures) {
                _ = try NRBandLockPlan.make(
                    requested: activeSALock,
                    baseline: disjointBaseline,
                    architecture: .automatic
                )
            }
            let activeNSALock = NRBandMask(bands: [77])!
            _ = try NRBandLockPlan.make(
                requested: activeNSALock,
                baseline: disjointBaseline,
                architecture: .nsaOnly
            )
            checkThrows("active NSA lock cannot switch to SA-only", failures: &failures) {
                _ = try NRBandLockPlan.make(
                    requested: activeNSALock,
                    baseline: disjointBaseline,
                    architecture: .saOnly
                )
            }
            checkThrows("active NSA lock cannot switch to Auto", failures: &failures) {
                _ = try NRBandLockPlan.make(
                    requested: activeNSALock,
                    baseline: disjointBaseline,
                    architecture: .automatic
                )
            }
            let setSAOnly = QMIParser.setNRSystemSelectionRequest(
                modePreference: 0x0040,
                saBands: saMask,
                nsaBands: .zero,
                transaction: 0x1234
            )
            check(setSAOnly == qmiRequest(
                message: 0x0033,
                transaction: 0x1234,
                tlvs: [
                    (0x17, Data([0x00])),
                    (0x11, le16(0x0040)),
                    (0x2F, saMask.bytes),
                    (0x30, NRBandMask.zero.bytes)
                ]
            ), "QMI SA-only request", failures: &failures)

            let setNSAOnly = QMIParser.setNRSystemSelectionRequest(
                modePreference: 0x0050,
                saBands: .zero,
                nsaBands: nsaMask
            )
            check(setNSAOnly == qmiRequest(
                message: 0x0033,
                tlvs: [
                    (0x17, Data([0x00])),
                    (0x11, le16(0x0050)),
                    (0x2F, NRBandMask.zero.bytes),
                    (0x30, nsaMask.bytes)
                ]
            ), "QMI NSA-only request", failures: &failures)

            let setLTEOnly = QMIParser.setNRSystemSelectionRequest(
                modePreference: 0x0010,
                saBands: .zero,
                nsaBands: .zero,
                lteBands: currentLTELock,
                transaction: 0x1234
            )
            check(setLTEOnly == qmiRequest(
                message: 0x0033,
                transaction: 0x1234,
                tlvs: [
                    (0x17, Data([0x00])),
                    (0x11, le16(0x0010)),
                    (0x24, currentLTELock.bytes),
                    (0x2F, NRBandMask.zero.bytes),
                    (0x30, NRBandMask.zero.bytes)
                ]
            ), "QMI LTE-only request", failures: &failures)

            let setAutomatic = QMIParser.setNRSystemSelectionRequest(
                modePreference: 0x0050,
                saBands: saMask,
                nsaBands: nsaMask,
                lteBands: lteMask
            )
            check(setAutomatic == qmiRequest(
                message: 0x0033,
                tlvs: [
                    (0x17, Data([0x00])),
                    (0x11, le16(0x0050)),
                    (0x24, lteMask.bytes),
                    (0x2F, saMask.bytes),
                    (0x30, nsaMask.bytes)
                ]
            ), "QMI automatic SA/NSA restore request", failures: &failures)

            try QMIParser.validateSetSystemSelectionResponse(qmiResponse(message: 0x0033))

            let probe = VOSProbeOutput(
                band: data(nrAndLTE),
                signal: data(signal),
                serving: data(serving),
                ca: data(noCA),
                location: data(nrCellLocation),
                dsd: data(dsdNSA),
                modemVersion: "AT+GMR\r\nRXMG1.20.00.326_0R05\r\nOK\r\n",
                deviceFirmware: "RXMG1.20.00.326.73_0R19"
            )
            let snapshot = try VOSClient.makeSnapshot(
                host: "192.168.225.1",
                interfaceName: "en13",
                probe: probe,
                now: Date(timeIntervalSince1970: 1)
            )
            check(snapshot.detailedMenuTitle == "NSA n78+B2", "menu uses explicit NSA", failures: &failures)
            check(snapshot.modeLabel == "NSA", "mode label", failures: &failures)
            check(snapshot.nrBandwidthMHz == 50 && snapshot.lteBandwidthMHz == 20, "snapshot bandwidth", failures: &failures)
            check(snapshot.lteSignal.rssiDBm == -73, "snapshot LTE RSSI", failures: &failures)
            check(snapshot.lteSignal.rsrqDB == -13, "snapshot LTE RSRQ", failures: &failures)
            check(snapshot.lteSignal.snrDB == 4.6, "snapshot LTE SNR", failures: &failures)
            check(snapshot.nrSignal.rsrpDBm == -112, "snapshot NR location-signal fallback", failures: &failures)
            check(snapshot.nrGlobalCellID == 0x1234_5678, "snapshot NR global Cell ID", failures: &failures)
            check(snapshot.nrPhysicalCellID == 41, "snapshot NR PCI", failures: &failures)
            check(snapshot.diagnostics.contains("NR Cell ID: 305419896"), "diagnostics use decimal Cell ID", failures: &failures)
            check(!snapshot.diagnostics.contains("PCI"), "diagnostics omit PCI", failures: &failures)
            check(snapshot.ltePrimaryCell?.band == "B2", "snapshot LTE PCell", failures: &failures)
            check(snapshot.moduleVersion?.hasSuffix("_0R05") == true, "modem version", failures: &failures)
            check(snapshot.deviceFirmware == "326.73_0R19", "device firmware", failures: &failures)

            check(abs((ChannelFrequency.nrMHz(633_984) ?? 0) - 3_509.76) < 0.001, "NR frequency", failures: &failures)
            check(ChannelFrequency.lteMHz(band: "B2", earfcn: 900) == 1_960, "LTE B2 frequency", failures: &failures)
            check(ChannelFrequency.lteMHz(band: "B66", earfcn: 66_786) == 2_145, "LTE B66 frequency", failures: &failures)
            check(ChannelFrequency.lteMHz(band: "B44", earfcn: 45_590) == 703, "LTE B44 frequency", failures: &failures)
            check(ChannelFrequency.lteMHz(band: "B45", earfcn: 46_590) == 1_447, "LTE B45 frequency", failures: &failures)

            let unknownProbe = VOSProbeOutput(
                band: data(nrAndLTE), signal: nil, serving: nil, ca: nil,
                dsd: nil, modemVersion: nil, deviceFirmware: nil
            )
            let unknown = try VOSClient.makeSnapshot(host: "192.168.225.1", interfaceName: nil, probe: unknownProbe)
            check(unknown.detailedMenuTitle == "NR n78+B2", "does not infer NSA", failures: &failures)

            let legacyPlaceholder = VOSProbeOutput(
                band: data(lteBand), signal: nil, serving: nil, ca: data(legacyNoCA),
                dsd: nil, modemVersion: nil, deviceFirmware: nil
            )
            let withoutCA = try VOSClient.makeSnapshot(
                host: "192.168.225.1", interfaceName: nil, probe: legacyPlaceholder
            )
            check(withoutCA.lteSecondaryCells.isEmpty, "deconfigured legacy CA hidden", failures: &failures)

            var handedOverLTE = Data([0, 0x03, 0x02, 0x22])
            handedOverLTE.append(le16(0x1234))
            handedOverLTE.append(le32(0x89AB_CDEF))
            handedOverLTE.append(le16(900))
            handedOverLTE.append(le16(224))
            handedOverLTE.append(contentsOf: [7, 8, 9, 10, 1])
            handedOverLTE.append(lteLocationCell(
                pci: 224,
                rsrqTenths: -130,
                rsrpTenths: -1_060,
                rssiTenths: -730
            ))
            let handoverLocation = qmiResponse(message: 0x0043, tlvs: [(0x13, handedOverLTE)])
            let handedOverSnapshot = try VOSClient.makeSnapshot(
                host: "192.168.225.1",
                interfaceName: nil,
                probe: VOSProbeOutput(
                    band: data(lteBand),
                    signal: data(completeSignal),
                    serving: nil,
                    ca: data(ca),
                    location: handoverLocation,
                    dsd: nil,
                    modemVersion: nil,
                    deviceFirmware: nil
                )
            )
            check(handedOverSnapshot.ltePrimaryCell?.globalCellID == nil, "handover does not mislabel PCell ID", failures: &failures)
            check(handedOverSnapshot.ltePrimaryCell?.signal == .empty, "handover does not mislabel PCell signal", failures: &failures)
        } catch {
            failures.append("unexpected error: \(error)")
        }

        check(
            DeviceConfiguration(host: "example.com", username: "root", password: "x", refreshInterval: 5).sshHost == nil,
            "rejects public hosts",
            failures: &failures
        )
        checkThrows("truncated QMI", failures: &failures) {
            _ = try QMIParser.activeRadios(from: Data([0x02, 0x01]))
        }
        checkThrows("COPS command error", failures: &failures) {
            _ = try ATCOPSParser.selection(from: "+CME ERROR: 30\n")
        }
        checkThrows("QMI missing NSA system preference", failures: &failures) {
            let fullMask = Data(repeating: 0x55, count: NRBandMask.byteCount)
            _ = try QMIParser.systemSelectionPreferences(from: qmiResponse(
                message: 0x0034,
                tlvs: [(0x11, le16(0x0050)), (0x2C, fullMask)]
            ))
        }
        checkThrows("QMI short NSA system preference", failures: &failures) {
            let fullMask = Data(repeating: 0x55, count: NRBandMask.byteCount)
            _ = try QMIParser.systemSelectionPreferences(from: qmiResponse(
                message: 0x0034,
                tlvs: [(0x2C, fullMask), (0x2D, Data(repeating: 0xAA, count: 63))]
            ))
        }
        checkThrows("QMI set system preference failure", failures: &failures) {
            try QMIParser.validateSetSystemSelectionResponse(qmiResponse(
                message: 0x0033,
                resultStatus: 1,
                resultError: 42
            ))
        }

        failures.append(contentsOf: await modernModemFailures())

        if ProcessInfo.processInfo.environment["MODEM_SIGNAL_HARDWARE_TEST"] == "1" {
            do {
                let snapshot = try await VOSClient().fetchSnapshot(configuration: DeviceConfiguration(
                    host: "192.168.225.1", username: "root", password: "oelinux123", refreshInterval: 5
                ))
                check(snapshot.hasRadioData, "hardware active band", failures: &failures)
                print("Hardware probe:\n\(snapshot.diagnostics)")
            } catch {
                failures.append("hardware probe: \(error.localizedDescription)")
            }
        }

        if failures.isEmpty {
            print("All Cellular Modem Monitor tests passed")
        } else {
            for failure in failures { fputs("FAIL: \(failure)\n", stderr) }
            exit(1)
        }
    }

    private static func modernModemFailures() async -> [String] {
        var failures: [String] = []
        await runCredentialTests(failures: &failures)
        runFailureClassificationTests(failures: &failures)
        await runVOSNetworkScanSafetyTests(failures: &failures)
        await runVOSCancellationTests(failures: &failures)
        runMC7530ParserTests(failures: &failures)
        await runZTEAuthTests(failures: &failures)
        await runMC7530ControlTests(failures: &failures)
        await runDiscoveryTests(failures: &failures)
        await runCoordinatorTests(failures: &failures)
        return failures
    }

    @MainActor
    private static func runCredentialTests(failures: inout [String]) {
        let plannedUpdates = CredentialSavePlanner.updates(for: [
            CredentialEdit(account: "unchanged", password: "same", loadState: .loaded("same")),
            CredentialEdit(account: "clear", password: "", loadState: .loaded("old")),
            CredentialEdit(account: "unreadable", password: "", loadState: .unavailable("denied")),
            CredentialEdit(account: "replacement", password: "new-secret", loadState: .unavailable("denied"))
        ])
        check(
            plannedUpdates == [
                CredentialUpdate(account: "clear", password: ""),
                CredentialUpdate(account: "replacement", password: "new-secret")
            ],
            "credential planner distinguishes explicit edits from unreadable empty fields",
            failures: &failures
        )

        do {
            let store = DirectCredentialStore(values: [
                "unreadable": "must-survive",
                "editable": "old-value"
            ])
            let updates = CredentialSavePlanner.updates(for: [
                CredentialEdit(
                    account: "unreadable",
                    password: "",
                    loadState: .unavailable("transient denial")
                ),
                CredentialEdit(
                    account: "editable",
                    password: "new-value",
                    loadState: .loaded("old-value")
                )
            ])
            try CredentialTransaction.apply(updates, store: store)
            check(
                store.snapshot() == [
                    "unreadable": "must-survive",
                    "editable": "new-value"
                ],
                "saving another setting preserves an unreadable local credential",
                failures: &failures
            )
        } catch {
            failures.append("preserve unreadable local credential: \(error)")
        }

        do {
            let store = DirectCredentialStore(
                values: ["vos": "old-vos", "zte": "old-zte"],
                failingSetAccount: "zte"
            )
            do {
                try CredentialTransaction.apply([
                    CredentialUpdate(account: "vos", password: "new-vos"),
                    CredentialUpdate(account: "zte", password: "new-zte")
                ], store: store)
                failures.append("credential transaction must report the planned second write failure")
            } catch {}
            check(
                store.snapshot() == ["vos": "old-vos", "zte": "old-zte"],
                "credential transaction rolls back both accounts",
                failures: &failures
            )
        }

        do {
            let store = DirectCredentialStore(values: [:], failsReads: true)
            do {
                try CredentialTransaction.apply([
                    CredentialUpdate(account: "vos", password: "new-vos")
                ], store: store)
                failures.append("credential transaction must not treat a credential read error as missing")
            } catch {}
            check(store.setCallCount() == 0,
                  "credential read failure performs no writes", failures: &failures)
        }

        do {
            let fileManager = FileManager.default
            let root = fileManager.temporaryDirectory.appendingPathComponent(
                "CellularModemMonitor.DirectTests.LocalCredentialStore.\(UUID().uuidString)",
                isDirectory: true
            )
            defer { try? fileManager.removeItem(at: root) }
            let fileURL = root
                .appendingPathComponent("private", isDirectory: true)
                .appendingPathComponent("credentials.json", isDirectory: false)
            let store = LocalCredentialStore(fileURL: fileURL, fileManager: fileManager)

            try store.setPassword("fixture-vos-secret", for: "vos")
            try store.setPassword("fixture-zte-secret", for: "zte")
            check(
                try store.password(for: "vos") == "fixture-vos-secret" &&
                    store.password(for: "zte") == "fixture-zte-secret",
                "local credential store round-trips independent accounts",
                failures: &failures
            )

            let directoryAttributes = try fileManager.attributesOfItem(
                atPath: fileURL.deletingLastPathComponent().path
            )
            let fileAttributes = try fileManager.attributesOfItem(atPath: fileURL.path)
            let directoryMode = (directoryAttributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
            let fileMode = (fileAttributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
            check(directoryMode & 0o777 == 0o700,
                  "local credential directory is mode 0700", failures: &failures)
            check(fileMode & 0o777 == 0o600,
                  "local credential file is mode 0600", failures: &failures)

            try fileManager.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: fileURL.deletingLastPathComponent().path
            )
            try fileManager.setAttributes(
                [.posixPermissions: 0o644],
                ofItemAtPath: fileURL.path
            )
            _ = try store.password(for: "zte")
            let repairedDirectoryMode = (
                try fileManager.attributesOfItem(
                    atPath: fileURL.deletingLastPathComponent().path
                )[.posixPermissions] as? NSNumber
            )?.intValue ?? -1
            let repairedFileMode = (
                try fileManager.attributesOfItem(atPath: fileURL.path)[.posixPermissions] as? NSNumber
            )?.intValue ?? -1
            check(repairedDirectoryMode & 0o777 == 0o700 &&
                    repairedFileMode & 0o777 == 0o600,
                  "local credential read restores private directory/file modes",
                  failures: &failures)

            try store.removePassword(for: "vos")
            check(
                try store.password(for: "vos") == nil &&
                    store.password(for: "zte") == "fixture-zte-secret",
                "removing one local credential preserves the other account",
                failures: &failures
            )
        } catch {
            failures.append("local credential round-trip and permissions: \(error)")
        }

        do {
            let fileManager = FileManager.default
            let root = fileManager.temporaryDirectory.appendingPathComponent(
                "CellularModemMonitor.DirectTests.LocalCredentialSymlink.\(UUID().uuidString)",
                isDirectory: true
            )
            defer { try? fileManager.removeItem(at: root) }
            try fileManager.createDirectory(
                at: root,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let targetURL = root.appendingPathComponent("target.json", isDirectory: false)
            let targetData = Data(#"{"existing":"must-survive"}"#.utf8)
            try targetData.write(to: targetURL)
            let fileURL = root.appendingPathComponent("credentials.json", isDirectory: false)
            try fileManager.createSymbolicLink(
                atPath: fileURL.path,
                withDestinationPath: targetURL.path
            )
            let store = LocalCredentialStore(fileURL: fileURL, fileManager: fileManager)
            do {
                try store.setPassword("must-not-write", for: "new")
                failures.append("local credential symlink path must fail closed")
            } catch let error as LocalCredentialStoreError {
                if case .unsafePath = error {} else {
                    failures.append("local credential symlink reports the wrong error: \(error)")
                }
            }
            check(
                try Data(contentsOf: targetURL) == targetData,
                "local credential symlink rejection leaves its target untouched",
                failures: &failures
            )
        } catch {
            failures.append("local credential symlink fail-closed setup: \(error)")
        }

        do {
            let fileManager = FileManager.default
            let root = fileManager.temporaryDirectory.appendingPathComponent(
                "CellularModemMonitor.DirectTests.LocalCredentialMalformed.\(UUID().uuidString)",
                isDirectory: true
            )
            defer { try? fileManager.removeItem(at: root) }
            try fileManager.createDirectory(
                at: root,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let fileURL = root.appendingPathComponent("credentials.json", isDirectory: false)
            try Data("{not-json".utf8).write(to: fileURL)
            let store = LocalCredentialStore(fileURL: fileURL, fileManager: fileManager)
            do {
                _ = try store.password(for: "zte")
                failures.append("malformed local credential JSON must fail closed")
            } catch let error as LocalCredentialStoreError {
                check(error == .invalidFormat,
                      "malformed local credential JSON reports invalid format", failures: &failures)
            }
        } catch {
            failures.append("malformed local credential setup: \(error)")
        }

        let suiteName = "CellularModemMonitor.DirectTests.\(UUID().uuidString)"
        if let defaults = UserDefaults(suiteName: suiteName) {
            defer { defaults.removePersistentDomain(forName: suiteName) }
            defaults.set("legacy-fixture-password", forKey: "sshPassword")
            let store = DirectCredentialStore(values: [:])
            do {
                let migrated = try StatusModel.loadVOSPassword(
                    defaults: defaults,
                    credentialStore: store
                )
                check(migrated == "legacy-fixture-password",
                      "legacy VOS password migration returns the original value", failures: &failures)
                check(!defaults.dictionaryRepresentation().keys.contains("sshPassword"),
                      "legacy VOS preference is removed after successful migration", failures: &failures)
                check(store.snapshot().values.contains("legacy-fixture-password"),
                      "legacy VOS password is written to credential store", failures: &failures)
            } catch {
                failures.append("legacy VOS password migration: \(error)")
            }
        } else {
            failures.append("create isolated UserDefaults suite")
        }

        let errorSuiteName = "CellularModemMonitor.DirectTests.Error.\(UUID().uuidString)"
        if let defaults = UserDefaults(suiteName: errorSuiteName) {
            defer { defaults.removePersistentDomain(forName: errorSuiteName) }
            defaults.set("legacy-must-remain", forKey: "sshPassword")
            let store = DirectCredentialStore(values: [:], failsReads: true)
            do {
                _ = try StatusModel.loadVOSPassword(defaults: defaults, credentialStore: store)
                failures.append("local credential read failure must be surfaced")
            } catch {}
            check(defaults.string(forKey: "sshPassword") == "legacy-must-remain",
                  "local credential read failure preserves legacy preference", failures: &failures)
        }

        let migrationSuiteName = "CellularModemMonitor.DirectTests.Migration.\(UUID().uuidString)"
        if let defaults = UserDefaults(suiteName: migrationSuiteName) {
            defer { defaults.removePersistentDomain(forName: migrationSuiteName) }
            defaults.set("legacy-must-remain", forKey: "sshPassword")
            let store = DirectCredentialStore(
                values: [:],
                failingSetAccount: "vos-5g-ssh",
                failingSetPasswordPrefix: "legacy-"
            )
            do {
                let result = try StatusModel.loadVOSCredential(
                    defaults: defaults,
                    credentialStore: store
                )
                check(result.password == "legacy-must-remain",
                      "failed legacy migration keeps the usable in-memory password", failures: &failures)
                guard case .unavailable = result.state else {
                    failures.append("failed legacy migration remains marked unavailable")
                    return
                }
                check(defaults.string(forKey: "sshPassword") == "legacy-must-remain",
                      "failed legacy migration keeps the only durable password copy", failures: &failures)
                check(
                    CredentialSavePlanner.updates(for: [CredentialEdit(
                        account: "vos-5g-ssh",
                        password: result.password,
                        loadState: result.state
                    )]) == [CredentialUpdate(account: "vos-5g-ssh", password: "legacy-must-remain")],
                    "Save retries a failed legacy credential migration before cleanup",
                    failures: &failures
                )
            } catch {
                failures.append("failed legacy migration state: \(error)")
            }
        }

        check(StatusModel.isBuiltInDefault(kind: .vos5G, address: "http://192.168.225.1/"),
              "VOS default address is not promoted to a manual hint", failures: &failures)
        check(StatusModel.isBuiltInDefault(kind: .zteMC7530CA, address: "192.168.254.1"),
              "ZTE default address is not promoted to a manual hint", failures: &failures)
        check(!StatusModel.isBuiltInDefault(kind: .zteMC7530CA, address: "192.168.254.99"),
              "changed ZTE address remains a manual hint", failures: &failures)
    }

    private static func runFailureClassificationTests(failures: inout [String]) {
        check(
            ModemFailureClassifier.category(of: VOSClientError.authenticationFailed) == .authentication,
            "VOS authentication errors use structured classification",
            failures: &failures
        )
        check(
            ModemFailureClassifier.category(of: ZTEUBusError.authenticationFailed) == .authentication,
            "ZTE authentication errors use structured classification",
            failures: &failures
        )
        check(
            ModemFailureClassifier.category(of: ModemBackendError.credentialsRequired(.web)) == .authentication,
            "backend credential errors use structured classification",
            failures: &failures
        )
        check(
            ModemFailureClassifier.category(of: VOSClientError.qmiUnavailable(nil)) == .qmiUnavailable,
            "VOS QMI errors use structured classification",
            failures: &failures
        )
        check(
            ModemFailureClassifier.category(of: DirectMisleadingAuthenticationError()) == .other,
            "authentication-like English text does not alter structured classification",
            failures: &failures
        )
    }

    private static func runVOSNetworkScanSafetyTests(failures: inout [String]) async {
        let configuration = DeviceConfiguration(
            host: "192.168.225.1",
            username: "root",
            password: "fixture",
            refreshInterval: 30
        )
        let baseline = DirectVOSControlTransport.baselinePreferences
        let lteBands = LTEBandMask(bands: [2, 4, 66])!
        let scenarios: [(String, NRSystemSelectionPreferences)] = [
            ("automatic", baseline),
            ("SA only", NRSystemSelectionPreferences(
                modePreference: 0x0040,
                saBands: baseline.saBands,
                nsaBands: .zero,
                lteBands: lteBands
            )),
            ("NSA only", NRSystemSelectionPreferences(
                modePreference: 0x0050,
                saBands: .zero,
                nsaBands: baseline.nsaBands,
                lteBands: lteBands
            )),
            ("LTE only", NRSystemSelectionPreferences(
                modePreference: 0x0010,
                saBands: .zero,
                nsaBands: .zero,
                lteBands: lteBands
            ))
        ]

        for (name, previous) in scenarios {
            do {
                let transport = DirectVOSControlTransport()
                await transport.seedPreferences(previous)
                let session = try await VOSControlSession.open(
                    client: transport,
                    configuration: configuration,
                    timing: .immediate
                )
                let result = try await session.perform(.scanNetworks)
                let state = await transport.snapshot()
                let expectedWrites = previous.architectureMode == .lteOnly ? 1 : 2
                check(
                    result.scannedNetworks?.first?.plmn == "00101" &&
                        result.state.architecture == previous.architectureMode &&
                        state.scanArchitectures == [.lteOnly] &&
                        state.preferences == previous &&
                        state.preferenceHistory.count == expectedWrites &&
                        state.preferenceHistory.first?.architectureMode == .lteOnly &&
                        state.preferenceHistory.last == previous,
                    "VOS \(name) scan enters verified LTE-only mode and restores the exact tuple",
                    failures: &failures
                )
            } catch {
                failures.append("VOS \(name) safe network scan: \(error)")
            }
        }

        do {
            let unavailable = NRSystemSelectionPreferences(
                modePreference: 0x0040,
                saBands: .zero,
                nsaBands: .zero,
                lteBands: lteBands
            )
            let transport = DirectVOSControlTransport()
            await transport.seedPreferences(unavailable)
            let session = try await VOSControlSession.open(
                client: transport,
                configuration: configuration,
                timing: .immediate
            )
            do {
                _ = try await session.perform(.scanNetworks)
                failures.append("VOS unavailable radio mode must block the unsafe AT scan")
            } catch let error as ModemControlError {
                guard case .invalidState = error else {
                    failures.append("VOS unavailable scan error type: \(error)")
                    return
                }
            }
            let state = await transport.snapshot()
            check(
                state.scanArchitectures.isEmpty && state.preferenceHistory.isEmpty,
                "VOS unavailable radio mode fails closed before any scan or write",
                failures: &failures
            )
        } catch {
            failures.append("VOS unavailable scan guard: \(error)")
        }

        do {
            let previous = scenarios[1].1
            let transport = DirectVOSControlTransport(scanFailures: 1)
            await transport.seedPreferences(previous)
            let session = try await VOSControlSession.open(
                client: transport,
                configuration: configuration,
                timing: .immediate
            )
            do {
                _ = try await session.perform(.scanNetworks)
                failures.append("VOS failed scan must not report success")
            } catch {
                let state = await transport.snapshot()
                check(
                    state.scanArchitectures == [.lteOnly] &&
                        state.preferences == previous &&
                        state.preferenceHistory.map(\.architectureMode) == [.lteOnly, .saOnly],
                    "VOS failed scan restores the exact pre-scan SA tuple",
                    failures: &failures
                )
            }
        } catch {
            failures.append("VOS failed scan rollback: \(error)")
        }

        do {
            let previous = scenarios[2].1
            let transport = DirectVOSControlTransport(suspendScanOnce: true)
            await transport.seedPreferences(previous)
            let session = try await VOSControlSession.open(
                client: transport,
                configuration: configuration,
                timing: .immediate
            )
            let operation = Task { try await session.perform(.scanNetworks) }
            let scanStarted = await transport.waitForScan()
            operation.cancel()
            do {
                _ = try await operation.value
                failures.append("VOS cancelled scan must not report success")
            } catch {
                let state = await transport.snapshot()
                check(
                    scanStarted && error is CancellationError &&
                        state.scanArchitectures == [.lteOnly] &&
                        state.preferences == previous &&
                        state.preferenceHistory.map(\.architectureMode) == [.lteOnly, .nsaOnly],
                    "VOS cancelled scan restores the exact pre-scan NSA tuple",
                    failures: &failures
                )
            }
        } catch {
            failures.append("VOS cancelled scan rollback: \(error)")
        }
    }

    private static func runVOSCancellationTests(failures: inout [String]) async {
        let configuration = DeviceConfiguration(
            host: "192.168.225.1",
            username: "root",
            password: "fixture",
            refreshInterval: 30
        )
        let selectedNetwork = CellularNetwork(
            longName: "Fixture Carrier",
            shortName: "Fixture",
            plmn: "00101",
            availability: .available,
            accessTechnologies: [.lte]
        )

        do {
            let transport = DirectVOSControlTransport(suspendManualSelectionOnce: true)
            let session = try await VOSControlSession.open(
                client: transport,
                configuration: configuration
            )
            let operation = Task {
                try await session.perform(.selectNetwork(selectedNetwork))
            }
            await transport.waitForManualMutation()
            operation.cancel()
            do {
                _ = try await operation.value
                failures.append("VOS cancelled manual selection must not report success")
            } catch {
                check(
                    error is CancellationError,
                    "VOS preserves cancellation after verified automatic recovery",
                    failures: &failures
                )
            }
            let reconciled = try await session.refresh()
            let state = await transport.snapshot()
            check(
                state.selection.mode == .automatic &&
                    state.preferences == DirectVOSControlTransport.baselinePreferences &&
                    state.automaticWrites == 1 &&
                    state.preferenceWrites >= 2 &&
                    reconciled.operatorSelection?.mode == .automatic &&
                    reconciled.architecture == .automatic,
                "VOS cancelled manual selection restores and reconciles operator/radio state",
                failures: &failures
            )
        } catch {
            failures.append("VOS cancellation-safe manual selection: \(error)")
        }

        do {
            let transport = DirectVOSControlTransport(
                suspendManualSelectionOnce: true,
                automaticFailures: 1
            )
            let session = try await VOSControlSession.open(
                client: transport,
                configuration: configuration
            )
            let operation = Task {
                try await session.perform(.selectNetwork(selectedNetwork))
            }
            await transport.waitForManualMutation()
            operation.cancel()
            do {
                _ = try await operation.value
                failures.append("VOS failed cancellation recovery must not report success")
            } catch {
                check(
                    !(error is CancellationError) &&
                        error.localizedDescription.contains("state is unknown"),
                    "VOS failed cancellation recovery remains a visible unknown-state error",
                    failures: &failures
                )
            }
        } catch {
            failures.append("VOS cancellation recovery failure: \(error)")
        }

        do {
            let transport = DirectVOSControlTransport(suspendAutomaticSelectionOnce: true)
            let session = try await VOSControlSession.open(
                client: transport,
                configuration: configuration
            )
            _ = try await session.refresh()
            await transport.seedNondefaultState()
            let operation = Task {
                try await session.perform(.restoreDefaults)
            }
            await transport.waitForAutomaticMutation()
            operation.cancel()
            do {
                _ = try await operation.value
                failures.append("VOS cancelled restore must not report success")
            } catch {
                check(
                    error is CancellationError,
                    "VOS preserves cancellation after completing restore",
                    failures: &failures
                )
            }
            let reconciled = try await session.refresh()
            let state = await transport.snapshot()
            check(
                state.selection.mode == .automatic &&
                    state.preferences == DirectVOSControlTransport.baselinePreferences &&
                    state.automaticWrites == 2 &&
                    state.preferenceWrites == 1 &&
                    reconciled.operatorSelection?.mode == .automatic &&
                    reconciled.architecture == .automatic,
                "VOS cancelled restore completes both steps and reconciles authoritative state",
                failures: &failures
            )
        } catch {
            failures.append("VOS cancellation-safe restore defaults: \(error)")
        }

        do {
            let temporaryDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("SignalStatusSSHCancel-\(UUID().uuidString)")
            try FileManager.default.createDirectory(
                at: temporaryDirectory,
                withIntermediateDirectories: true
            )
            defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
            let executable = temporaryDirectory.appendingPathComponent("fake-ssh.sh")
            let started = temporaryDirectory.appendingPathComponent("started")
            let script = """
            #!/bin/sh
            : > '\(started.path)'
            sleep 0.05
            exit 23
            """
            try Data(script.utf8).write(to: executable, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: executable.path
            )
            let executor = SystemSSHExecutor(
                sshPath: executable.path,
                askPassPath: "/usr/bin/true"
            )
            let operation = Task {
                try await executor.run(
                    host: "192.168.225.1",
                    username: "root",
                    password: "fixture",
                    sourceAddress: nil,
                    script: "fixture",
                    timeout: 1
                )
            }
            for _ in 0..<1_000 {
                if FileManager.default.fileExists(atPath: started.path) { break }
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            operation.cancel()
            do {
                _ = try await operation.value
                failures.append("cancelled failing SSH worker must not report success")
            } catch {
                check(
                    error is CancellationError,
                    "cancelled SSH caller wins over the detached worker's later command error",
                    failures: &failures
                )
            }
        } catch {
            failures.append("SSH cancellation/error precedence: \(error)")
        }
    }

    private static func runMC7530ParserTests(failures: inout [String]) {
        do {
            let endc = try MC7530Parser.parse(data: fixture("MC7530CA/endc-mixed-types.json"))
            check(endc.networkType == "ENDC", "MC7530 ENDC network type", failures: &failures)
            check(endc.operatorName == "Example Carrier", "MC7530 operator", failures: &failures)
            check(endc.mcc == "302" && endc.mnc == "220", "MC7530 mixed PLMN types", failures: &failures)
            check(endc.nrSystemMode == .nsa, "MC7530 ENDC maps to NSA", failures: &failures)
            check(endc.nrBand == "n66" && endc.nrChannel == "434910", "MC7530 NR band/channel", failures: &failures)
            check(endc.nrBandwidthMHz == 20, "MC7530 NR bandwidth", failures: &failures)
            check(
                endc.nrSignal == RadioSignal(rsrpDBm: -104, rsrqDB: -12, rssiDBm: -99, snrDB: 10.5),
                "MC7530 NR mixed numeric signal",
                failures: &failures
            )
            check(endc.nrPhysicalCellID == 41 && endc.nrGlobalCellID == nil,
                  "MC7530 nullable NR Cell ID", failures: &failures)
            check(endc.lteBand == "B2" && endc.lteChannel == "900", "MC7530 LTE band/channel", failures: &failures)
            check(
                endc.lteSignal == RadioSignal(rsrpDBm: -99, rsrqDB: -15.5, rssiDBm: -65, snrDB: 2),
                "MC7530 LTE mixed numeric signal",
                failures: &failures
            )
            check(endc.lteGlobalCellID == 19_088_743 && endc.ltePhysicalCellID == 223,
                  "MC7530 LTE cell identifiers", failures: &failures)
            check(endc.ltePrimaryCell?.band == "B2" && endc.ltePrimaryCell?.earfcn == 900,
                  "MC7530 LTE primary carrier", failures: &failures)
            check(endc.lteSecondaryCells.count == 1 && endc.lteSecondaryCells.first?.band == "B66",
                  "MC7530 LTE secondary carrier", failures: &failures)
            check(endc.lteSecondaryCells.first?.earfcn == 66_811 && endc.lteSecondaryCells.first?.bandwidthMHz == 15,
                  "MC7530 LTE secondary channel/bandwidth", failures: &failures)
            check(endc.unparsedLTECASignal != nil && endc.unparsedNRCA == "opaque-vendor-value",
                  "MC7530 undocumented CA fields retained", failures: &failures)

            let snapshot = endc.snapshot(
                host: "192.168.254.1",
                interfaceName: "en8",
                now: Date(timeIntervalSince1970: 1)
            )
            check(snapshot.host == "192.168.254.1" && snapshot.interfaceName == "en8",
                  "MC7530 scoped snapshot", failures: &failures)
            check(snapshot.detailedMenuTitle == "NSA n66+B2", "MC7530 snapshot mode title", failures: &failures)

            let sa = try MC7530Parser.parse(data: fixture("MC7530CA/sa.json"))
            check(sa.nrSystemMode == .sa && sa.nrBand == "n77", "MC7530 SA numeric band", failures: &failures)
            check(sa.nrChannel == "650000" && sa.nrBandwidthMHz == 100,
                  "MC7530 SA channel/bandwidth", failures: &failures)
            check(sa.nrGlobalCellID == 305_419_896 && sa.nrPhysicalCellID == 512,
                  "MC7530 SA cell identifiers", failures: &failures)
            check(sa.lteBand == nil && sa.lteSignal == .empty,
                  "MC7530 SA clears inactive LTE", failures: &failures)

            let lte = try MC7530Parser.parse(data: fixture("MC7530CA/lte-sentinels.json"))
            check(lte.lteBand == "B12" && lte.lteChannel == "5010", "MC7530 LTE-only fixture", failures: &failures)
            check(lte.lteSignal == .empty, "MC7530 signal sentinels hidden", failures: &failures)
            check(lte.nrBand == nil && lte.nrSignal == .empty && lte.nrSystemMode == nil,
                  "MC7530 inactive NR cleared", failures: &failures)
            check(lte.mcc == "001" && lte.mnc == "01", "MC7530 PLMN zero padding", failures: &failures)

            let ranges = try MC7530Parser.parse(data: fixture("MC7530CA/range-sentinels.json"))
            check(ranges.lteBand == "B12" && ranges.lteChannel == nil,
                  "MC7530 rejects out-of-range LTE channel", failures: &failures)
            check(ranges.lteGlobalCellID == nil && ranges.ltePhysicalCellID == nil,
                  "MC7530 rejects out-of-range LTE identifiers", failures: &failures)
            check(ranges.ltePrimaryCell == nil && ranges.lteSecondaryCells.isEmpty,
                  "MC7530 rejects malformed LTE carrier aggregation", failures: &failures)
            check(ranges.nrBand == "n77" && ranges.nrChannel == nil,
                  "MC7530 rejects out-of-range NR channel", failures: &failures)
            check(ranges.nrBandwidthMHz == nil && ranges.nrGlobalCellID == nil && ranges.nrPhysicalCellID == nil,
                  "MC7530 rejects out-of-range NR fields", failures: &failures)

            checkThrows("MC7530 malformed payload rejected", failures: &failures) {
                _ = try MC7530Parser.parse(data: Data("[]".utf8))
            }
        } catch {
            failures.append("MC7530 parser fixtures: \(error)")
        }
    }

    private static func runZTEAuthTests(failures: inout [String]) async {
        do {
            let http = DirectScriptedZTEHTTPTransport(responses: [
                zteResponse(#"[{"jsonrpc":"2.0","id":1,"result":{"zte_nwinfo_api":{"nwinfo_get_netinfo":{}}}}]"#)
            ])
            let transport = try ZTEUBusTransport(
                baseURL: URL(string: "http://192.168.254.1")!,
                route: ZTEHTTPRoute(interfaceName: "en8", interfaceIndex: 18, sourceAddress: "192.168.254.20"),
                http: http
            )
            let hasSchema = try await transport.hasMC7530Schema()
            check(hasSchema, "ZTE anonymous schema fingerprint", failures: &failures)
            let records = await http.records()
            check(records.count == 1, "ZTE schema request count", failures: &failures)
            if let request = records.first {
                check(request.rpcMethod == "list" && request.sessionID == ZTEUBusTransport.zeroSessionID,
                      "ZTE schema uses anonymous list", failures: &failures)
                check((request.urlPath == "/ubus" || request.urlPath == "/ubus/") && request.httpMethod == "POST",
                      "ZTE UBus endpoint", failures: &failures)
                check(request.header("Origin") == "http://192.168.254.1",
                      "ZTE Origin header", failures: &failures)
                check(request.header("Referer") == "http://192.168.254.1/",
                      "ZTE Referer header", failures: &failures)
                check(request.header("Z-Mode") == "0" && request.header("Z-Tag") == "",
                      "ZTE CSRF compatibility headers", failures: &failures)
                check(request.route.interfaceName == "en8" && request.route.interfaceIndex == 18,
                      "ZTE request preserves interface scope", failures: &failures)
            }
        } catch {
            failures.append("ZTE anonymous schema/headers: \(error)")
        }

        do {
            let http = DirectScriptedZTEHTTPTransport(responses: [
                zteResponse(#"[{"jsonrpc":"2.0","id":1,"result":{"zte_nwinfo_api":{"nwinfo_get_netinfo":{}}}}]"#),
                zteCallResponse(#"{"values":{"wa_inner_version":"MC7530CAV2.6"}}"#),
                zteCallResponse(#"{"zte_web_sault":"fixture-salt"}"#),
                zteCallResponse(#"{"result":"0","ubus_rpc_session":"fixture-sid"}"#),
                zteCallResponse(#"{"values":{"wa_inner_version":"MC7530CAV2.6"}}"#),
                zteCallResponse(#"{"modem_msn":"fixture-device-alpha"}"#),
                zteCallResponse(#"{"values":{"wa_inner_version":"MC7530CAV2.6"}}"#),
                zteCallResponse(#"{"network_type":"LTE","wan_active_band":"B12","wan_active_channel":5010,"lte_pci":7}"#)
            ])
            let backend = MC7530Backend(httpTransport: http)
            let endpoint = ScopedEndpoint(
                baseURL: URL(string: "http://192.168.254.1")!,
                interfaceName: "en8",
                interfaceIndex: 18,
                sourceAddress: "192.168.254.20",
                connectionPath: .directUSB,
                gateway: "192.168.254.1"
            )
            let credentials = ModemCredentials.web(
                WebCredentials(password: "fixture-password")
            )
            let identity = try await backend.identify(
                endpoint: endpoint,
                credentials: credentials
            )
            let snapshot = try await backend.fetchSnapshot(
                endpoint: endpoint,
                credentials: credentials
            )
            let expected = try MC7530ControlSession.fingerprint(
                modemMSN: "fixture-device-alpha"
            )
            check(identity?.kind == .zteMC7530CA &&
                    identity?.stableIdentifier == expected,
                  "ZTE discovery binds authenticated MSN digest after anonymous model preflight",
                  failures: &failures)
            check(snapshot.lteBand == "B12",
                  "ZTE status follows authenticated identity", failures: &failures)
            let records = await http.records()
            let identityRecords = Array(records.prefix(6))
            check(records.count == 8 &&
                    identityRecords.prefix(4).allSatisfy {
                        $0.sessionID == ZTEUBusTransport.zeroSessionID
                    } &&
                    records.suffix(4).allSatisfy { $0.sessionID == "fixture-sid" },
                  "ZTE identity switches to the authenticated SID only after preflight and login",
                  failures: &failures)
            check(identityRecords.map(\.ubusMethod) == [
                nil, "get", "web_login_info", "web_login", "get", "get_modem_msn"
            ] &&
                    records[1].parameters == [
                        "config": "zwrt_common_info", "section": "common_config"
                    ] && records[4].parameters == [
                        "config": "zwrt_common_info", "section": "common_config"
                    ],
                  "ZTE identity performs anonymous schema/model checks then authenticated retail identity reads",
                  failures: &failures)
            check(records[2].object == "zwrt_web" &&
                    records[3].object == "zwrt_web" &&
                    records[5].object == "zwrt_zte_mdm.api" &&
                    records[5].header("Z-Tag") == "get_modem_msn",
                  "ZTE identity uses the verified authenticated get_modem_msn method",
                  failures: &failures)
            check(records.filter { $0.ubusMethod == "web_login" }.count == 1 &&
                    records.suffix(2).map(\.ubusMethod) == ["get", "nwinfo_get_netinfo"],
                  "ZTE identity and first status read reuse one authenticated session",
                  failures: &failures)
        } catch {
            failures.append("ZTE authenticated exact identity: \(error)")
        }

        do {
            let http = DirectScriptedZTEHTTPTransport(responses: [
                zteResponse(#"[{"jsonrpc":"2.0","id":1,"result":{"zte_nwinfo_api":{"nwinfo_get_netinfo":{}}}}]"#),
                zteCallResponse(#"{"values":{"wa_inner_version":"MC7530CAV2.6"}}"#)
            ])
            let backend = MC7530Backend(httpTransport: http)
            do {
                _ = try await backend.identify(
                    endpoint: ScopedEndpoint(baseURL: URL(string: "http://192.168.254.1")!),
                    credentials: .none
                )
                failures.append("ZTE identity without Web credentials must fail closed")
            } catch let error as ModemBackendError {
                check(error == .credentialsRequired(.web),
                      "ZTE identity without a password reports required Web credentials",
                      failures: &failures)
            }
            let records = await http.records()
            check(records.map(\.ubusMethod) == [nil, "get"] &&
                    records.allSatisfy { $0.sessionID == ZTEUBusTransport.zeroSessionID },
                  "ZTE missing credentials stop after anonymous schema/model preflight",
                  failures: &failures)
        } catch {
            failures.append("ZTE missing identity credentials setup: \(error)")
        }

        do {
            let http = DirectScriptedZTEHTTPTransport(responses: [
                zteResponse(#"[{"jsonrpc":"2.0","id":1,"result":{"zte_nwinfo_api":{"nwinfo_get_netinfo":{}}}}]"#),
                zteCallResponse(#"{"values":{"wa_inner_version":"MC7530CAV2.6"}}"#),
                zteCallResponse(#"{"zte_web_sault":"fixture-salt"}"#),
                zteCallResponse(#"{"result":"1"}"#)
            ])
            let backend = MC7530Backend(httpTransport: http)
            do {
                _ = try await backend.identify(
                    endpoint: ScopedEndpoint(baseURL: URL(string: "http://192.168.254.1")!),
                    credentials: .web(WebCredentials(password: "wrong-fixture-password"))
                )
                failures.append("ZTE identity with a rejected password must fail closed")
            } catch let error as ZTEUBusError {
                check(error == .authenticationFailed,
                      "ZTE identity surfaces structured authentication failure",
                      failures: &failures)
            }
            let records = await http.records()
            check(records.map(\.ubusMethod) == [nil, "get", "web_login_info", "web_login"],
                  "ZTE rejected identity password stops before authenticated model/MSN reads",
                  failures: &failures)
        } catch {
            failures.append("ZTE rejected identity credentials setup: \(error)")
        }

        do {
            let expectedHash = "8D1C7328B6F8EFB7E5D58D42216F27B67BE22C038BF4468A546DBA881440F62C"
            check(ZTEAuthSession.loginHash(password: "secret", salt: "pepper") == expectedHash,
                  "ZTE double SHA-256 login hash", failures: &failures)
            let http = DirectScriptedZTEHTTPTransport(responses: [
                zteCallResponse(#"{"zte_web_sault":"pepper"}"#),
                zteCallResponse(#"{"result":"0","ubus_rpc_session":"sid-one"}"#),
                zteCallResponse(#"{"network_type":"LTE","wan_active_band":"B2"}"#)
            ])
            let session = ZTEAuthSession(
                transport: try ZTEUBusTransport(baseURL: URL(string: "http://192.168.254.1")!, http: http),
                username: "admin",
                password: "secret"
            )
            let payload = try await session.read(object: "zte_nwinfo_api", method: "nwinfo_get_netinfo")
            check(payload["network_type"]?.stringValue == "LTE", "ZTE authenticated read", failures: &failures)
            let records = await http.records()
            check(records.map(\.ubusMethod) == ["web_login_info", "web_login", "nwinfo_get_netinfo"],
                  "ZTE login/read request sequence", failures: &failures)
            check(records.dropFirst().first?.loginPassword == expectedHash,
                  "ZTE login sends challenge hash", failures: &failures)
            check(records.dropFirst().first?.loginUsername == "admin",
                  "ZTE optional username", failures: &failures)
            check(records.last?.sessionID == "sid-one", "ZTE read uses returned SID", failures: &failures)
            check(records.allSatisfy { !$0.bodyText.contains("secret") },
                  "ZTE request never sends plaintext password", failures: &failures)
        } catch {
            failures.append("ZTE successful authentication: \(error)")
        }

        do {
            let http = DirectScriptedZTEHTTPTransport(responses: [
                zteCallResponse(#"{"zte_web_sault":"salt-one"}"#),
                zteCallResponse(#"{"result":"0","ubus_rpc_session":"sid-one"}"#),
                zteStatusResponse(6),
                zteCallResponse(#"{"zte_web_sault":"salt-two"}"#),
                zteCallResponse(#"{"result":"0","ubus_rpc_session":"sid-two"}"#),
                zteCallResponse(#"{"network_type":"NR5G SA","nr5g_action_band":"n77"}"#)
            ])
            let session = ZTEAuthSession(
                transport: try ZTEUBusTransport(baseURL: URL(string: "http://192.168.254.1")!, http: http),
                password: "fixture-password"
            )
            let payload = try await session.read(object: "zte_nwinfo_api", method: "nwinfo_get_netinfo")
            check(payload["network_type"]?.stringValue == "NR5G SA",
                  "ZTE expired session read succeeds after relogin", failures: &failures)
            let records = await http.records()
            check(records.count == 6, "ZTE expiry retries exactly once", failures: &failures)
            check(records.filter { $0.ubusMethod == "web_login" }.count == 2,
                  "ZTE expiry performs second login", failures: &failures)
            check(records.filter { $0.ubusMethod == "nwinfo_get_netinfo" }.map(\.sessionID) == ["sid-one", "sid-two"],
                  "ZTE expiry replaces SID", failures: &failures)
        } catch {
            failures.append("ZTE expired-session relogin: \(error)")
        }

        do {
            let http = DirectScriptedZTEHTTPTransport(responses: [
                zteCallResponse(#"{"zte_web_sault":"write-salt"}"#),
                zteCallResponse(#"{"result":"0","ubus_rpc_session":"write-sid"}"#),
                zteCallResponse(#"{"result":"success"}"#)
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
            check(payload["result"]?.stringValue == "success",
                  "ZTE generic write returns payload", failures: &failures)
            let records = await http.records()
            if let write = records.last {
                check(write.sessionID == "write-sid" && write.ubusMethod == "nwinfo_set_netselect",
                      "ZTE generic write uses authenticated SID", failures: &failures)
                check(write.header("Z-Mode") == "1" && write.header("Z-Tag") == "fixture-tag",
                      "ZTE generic write uses retail action headers", failures: &failures)
                check(write.bodyText.contains(#""net_select":"Only_LTE""#),
                      "ZTE generic write preserves parameters", failures: &failures)
            } else {
                failures.append("ZTE generic write request was not recorded")
            }
            check(records.prefix(2).allSatisfy { $0.header("Z-Mode") == "0" },
                  "ZTE login requests remain read mode", failures: &failures)
        } catch {
            failures.append("ZTE generic authenticated write: \(error)")
        }

        do {
            let http = DirectScriptedZTEHTTPTransport(responses: [
                zteCallResponse(#"{"zte_web_sault":"salt-one"}"#),
                zteCallResponse(#"{"result":"0","ubus_rpc_session":"sid-one"}"#),
                zteStatusResponse(6),
                zteCallResponse(#"{"zte_web_sault":"salt-two"}"#),
                zteCallResponse(#"{"result":"0","ubus_rpc_session":"sid-two"}"#),
                zteCallResponse(#"{"result":"success"}"#)
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
            check(writes.map(\.sessionID) == ["sid-one", "sid-two"],
                  "ZTE expired generic write replaces SID once", failures: &failures)
            check(writes.allSatisfy {
                $0.header("Z-Mode") == "1" && $0.header("Z-Tag") == "band-lock"
            }, "ZTE expired generic write preserves headers", failures: &failures)
            check(records.filter { $0.ubusMethod == "web_login" }.count == 2,
                  "ZTE expired generic write relogs once", failures: &failures)
        } catch {
            failures.append("ZTE generic write expiry retry: \(error)")
        }

        do {
            let http = DirectScriptedZTEHTTPTransport(responses: [
                zteCallResponse(#"{"zte_web_sault":"salt-one"}"#),
                zteCallResponse(#"{"result":"0","ubus_rpc_session":"sid-one"}"#),
                zteResponse(#"[{"jsonrpc":"2.0","id":3,"error":{"code":-32002,"message":"Access denied"}}]"#),
                zteCallResponse(#"{"zte_web_sault":"salt-two"}"#),
                zteCallResponse(#"{"result":"0","ubus_rpc_session":"sid-two"}"#),
                zteStatusResponse(0)
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
            check(records.count == 6,
                  "MC7530 payload-free setter succeeds after exactly one access-denied retry",
                  failures: &failures)
            let setters = records.filter { $0.ubusMethod == "nwinfo_set_netselect" }
            check(setters.map(\.sessionID) == ["sid-one", "sid-two"],
                  "MC7530 header form replaces an access-denied SID once", failures: &failures)
            check(setters.allSatisfy {
                $0.header("Z-Mode") == "0" && $0.header("Z-Tag") == ""
            }, "MC7530 header form survives access-denied retry unchanged", failures: &failures)
            check(records.filter { $0.ubusMethod == "web_login" }.count == 2,
                  "MC7530 access-denied setter relogs once", failures: &failures)
        } catch {
            failures.append("MC7530 access-denied setter retry: \(error)")
        }

        do {
            let http = DirectScriptedZTEHTTPTransport(responses: [
                zteCallResponse(#"{"zte_web_sault":"fixture-salt"}"#),
                zteCallResponse(#"{"result":"0","ubus_rpc_session":"fixture-sid"}"#),
                zteStatusResponse(0)
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
                failures.append("ZTE payload-free read must fail")
            } catch let error as ZTEUBusError {
                check(error == .invalidResponse,
                      "ZTE payload-free read remains strict", failures: &failures)
            }
        } catch {
            failures.append("ZTE payload-free read response: \(error)")
        }

        do {
            let http = DirectScriptedZTEHTTPTransport(responses: [
                zteCallResponse(#"{"zte_web_sault":"salt-one"}"#),
                zteCallResponse(#"{"result":"0","ubus_rpc_session":"sid-one"}"#),
                zteStatusResponse(6),
                zteCallResponse(#"{"zte_web_sault":"salt-two"}"#),
                zteCallResponse(#"{"result":"0","ubus_rpc_session":"sid-two"}"#),
                zteResponse(#"[{"jsonrpc":"2.0","id":3,"error":{"code":-32002,"message":"Access denied"}}]"#)
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
                failures.append("ZTE replacement SID denial must fail")
            } catch let error as ZTEUBusError {
                check(error == .rpc(code: -32_002, message: "Access denied"),
                      "ZTE replacement SID denial is returned", failures: &failures)
            }
            let records = await http.records()
            check(records.count == 6,
                  "ZTE replacement SID denial is not retried again", failures: &failures)
            check(records.filter { $0.ubusMethod == "web_login" }.count == 2,
                  "ZTE replacement SID denial has only one relogin", failures: &failures)
            check(records.filter { $0.ubusMethod == "nwinfo_set_netselect" }.map(\.sessionID) == ["sid-one", "sid-two"],
                  "ZTE replacement SID denial has only two writes", failures: &failures)
        } catch {
            failures.append("ZTE replacement SID denial retry bound: \(error)")
        }

        do {
            let statusHTTP = DirectScriptedZTEHTTPTransport(responses: [
                zteCallResponse(#"{"zte_web_sault":"status-salt"}"#),
                zteCallResponse(#"{"result":"0","ubus_rpc_session":"status-sid"}"#),
                zteStatusResponse(5)
            ])
            let statusSession = ZTEAuthSession(
                transport: try ZTEUBusTransport(baseURL: URL(string: "http://192.168.254.1")!, http: statusHTTP),
                password: "fixture-password"
            )
            do {
                _ = try await statusSession.call(
                    object: "zte_nwinfo_api",
                    method: "nwinfo_set_netselect",
                    mode: .write
                )
                failures.append("ZTE non-zero UBus status must fail")
            } catch let error as ZTEUBusError {
                check(error == .ubusStatus(5), "ZTE non-zero UBus status is typed", failures: &failures)
            }

            let rpcHTTP = DirectScriptedZTEHTTPTransport(responses: [
                zteCallResponse(#"{"zte_web_sault":"rpc-salt"}"#),
                zteCallResponse(#"{"result":"0","ubus_rpc_session":"rpc-sid"}"#),
                zteResponse(#"[{"jsonrpc":"2.0","id":3,"error":{"code":-32601,"message":"fixture missing method"}}]"#)
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
                failures.append("ZTE JSON-RPC error must fail")
            } catch let error as ZTEUBusError {
                check(error == .rpc(code: -32_601, message: "fixture missing method"),
                      "ZTE JSON-RPC error is typed", failures: &failures)
            }
        } catch {
            failures.append("ZTE generic call status handling: \(error)")
        }

        do {
            let http = DirectScriptedZTEHTTPTransport(responses: [
                zteCallResponse(#"{"zte_web_sault":"pepper"}"#),
                zteCallResponse(#"{"result":"1"}"#)
            ])
            let session = ZTEAuthSession(
                transport: try ZTEUBusTransport(baseURL: URL(string: "http://192.168.254.1")!, http: http),
                password: "wrong-fixture-password"
            )
            for attempt in 1...2 {
                do {
                    _ = try await session.read(object: "zte_nwinfo_api", method: "nwinfo_get_netinfo")
                    failures.append("ZTE wrong-password attempt \(attempt) must fail")
                } catch let error as ZTEUBusError {
                    check(error == .authenticationFailed,
                          "ZTE wrong-password error \(attempt)", failures: &failures)
                } catch {
                    failures.append("ZTE wrong-password error \(attempt): \(error)")
                }
            }
            let requestCount = await http.requestCount()
            check(requestCount == 2,
                  "ZTE wrong-password gate prevents repeated login", failures: &failures)
        } catch {
            failures.append("ZTE wrong-password gate setup: \(error)")
        }

        do {
            let http = DirectScriptedZTEHTTPTransport(responses: [
                zteCallResponse(#"{"zte_web_sault":"bad-routed"}"#),
                zteCallResponse(#"{"result":"1"}"#),
                zteCallResponse(#"{"zte_web_sault":"bad-direct"}"#),
                zteCallResponse(#"{"result":"1"}"#),
                zteCallResponse(#"{"zte_web_sault":"good-routed"}"#),
                zteCallResponse(#"{"result":"0","ubus_rpc_session":"good-sid"}"#),
                zteCallResponse(#"{"values":{"wa_inner_version":"MC7530CAV2.6"}}"#),
                zteCallResponse(#"{"network_type":"LTE","wan_active_band":"B12","wan_active_channel":5010,"lte_pci":7}"#)
            ])
            let backend = MC7530Backend(httpTransport: http)
            let routed = ScopedEndpoint(
                baseURL: URL(string: "http://192.168.254.1")!,
                interfaceName: "en1", interfaceIndex: 11,
                sourceAddress: "192.168.8.25", connectionPath: .routed,
                gateway: "192.168.8.1"
            )
            let direct = ScopedEndpoint(
                baseURL: URL(string: "http://192.168.254.1")!,
                interfaceName: "en8", interfaceIndex: 18,
                sourceAddress: "192.168.254.20", connectionPath: .directUSB,
                gateway: "192.168.254.1"
            )
            let rejected: ModemCredentials = .web(
                WebCredentials(password: "wrong-fixture-password")
            )
            for endpoint in [routed, direct] {
                do {
                    _ = try await backend.fetchSnapshot(
                        endpoint: endpoint,
                        credentials: rejected
                    )
                    failures.append("ZTE rejected credential must fail per endpoint")
                } catch let error as ZTEUBusError {
                    check(error == .authenticationFailed,
                          "ZTE scoped rejected credential error", failures: &failures)
                }
            }
            let afterRejected = await http.requestCount()
            check(afterRejected == 4,
                  "ZTE rejected endpoint does not poison another scope",
                  failures: &failures)
            let snapshot = try await backend.fetchSnapshot(
                endpoint: routed,
                credentials: .web(WebCredentials(password: "changed-fixture-password"))
            )
            let finalRequestCount = await http.requestCount()
            check(snapshot.lteBand == "B12" && finalRequestCount == 8,
                  "ZTE credential change reopens only its scoped session",
                  failures: &failures)
        } catch {
            failures.append("ZTE per-endpoint credential gate: \(error)")
        }

        do {
            let http = DirectScriptedZTEHTTPTransport(responses: [
                zteCallResponse(#"{"zte_web_sault":"fixture-salt"}"#),
                zteCallResponse(#"{"result":"0","ubus_rpc_session":"fixture-sid"}"#),
                zteCallResponse(#"{"values":{"wa_inner_version":"MC889V1.0"}}"#)
            ])
            let backend = MC7530Backend(httpTransport: http)
            let endpoint = ScopedEndpoint(baseURL: URL(string: "http://192.168.254.1")!)
            do {
                _ = try await backend.fetchSnapshot(
                    endpoint: endpoint,
                    credentials: .web(WebCredentials(password: "fixture-password"))
                )
                failures.append("ZTE model mismatch must fail before status collection")
            } catch let error as ModemBackendError {
                check(
                    error == .deviceModelMismatch(expected: "MC7530CA", actual: "MC889V1.0"),
                    "ZTE model mismatch is typed",
                    failures: &failures
                )
            }
            let records = await http.records()
            check(records.map(\.ubusMethod) == ["web_login_info", "web_login", "get"],
                  "ZTE model mismatch stops before netinfo", failures: &failures)
            check(records.last?.object == "uci" &&
                    records.last?.header("Z-Mode") == "0" &&
                    records.last?.header("Z-Tag") == "zwrt_common_info",
                  "ZTE model identity uses authenticated retail UCI read", failures: &failures)
        } catch {
            failures.append("ZTE model identity gate: \(error)")
        }
    }

    private static func runMC7530ControlTests(failures: inout [String]) async {
        let timing = MC7530ControlTiming(
            pollIntervalNanoseconds: 0,
            scanAttempts: 3,
            registrationAttempts: 3,
            verificationAttempts: 1,
            resetAttempts: 2
        )

        do {
            let http = DirectStatefulMC7530HTTPTransport(state: .baseline)
            let session = try await openMC7530ControlSession(http: http, timing: timing)
            let state = try await session.refresh()
            check(state.architecture == .nsaOnly,
                  "MC7530 net_select maps to neutral NSA-only state", failures: &failures)
            check(state.operatorSelection == OperatorSelection(
                mode: .automatic,
                operatorName: "Fixture Carrier",
                plmn: "00101",
                accessTechnology: .lteNRDualConnectivity
            ), "MC7530 netinfo maps operator state", failures: &failures)
            check(state.lteBands == Set([2, 4, 66]) &&
                    state.saBands == Set([5, 77]) &&
                    state.nsaBands == Set([2, 66, 77]),
                  "MC7530 netinfo maps all band sets", failures: &failures)
            check(state.canRestoreDefaults && state.preferenceLifetime == .persistent,
                  "MC7530 neutral state reports persistent/restorable controls", failures: &failures)
            let records = await http.records()
            let controlCalls = records.filter { $0.object == "zte_nwinfo_api" }
            check(controlCalls.allSatisfy {
                $0.header("Z-Mode") == "0" && $0.header("Z-Tag") == ""
            }, "MC7530 control reads use the verified SID-authenticated header form",
               failures: &failures)
            let identityCalls = records.filter { $0.object == "zwrt_zte_mdm.api" }
            check(identityCalls.allSatisfy {
                $0.header("Z-Mode") == "0" && $0.header("Z-Tag") == $0.ubusMethod
            }, "MC7530 identity reads preserve their verified method tags", failures: &failures)
        } catch {
            failures.append("MC7530 neutral control-state parsing: \(error)")
        }

        do {
            var lte5GC = DirectMC7530FixtureState.baseline
            lte5GC.netSelect = "Only_LTE"
            lte5GC.networkType = "LTE 5GC"
            let http = DirectStatefulMC7530HTTPTransport(state: lte5GC)
            let session = try await openMC7530ControlSession(http: http, timing: timing)
            let state = try await session.refresh()
            check(state.operatorSelection?.accessTechnology == .lte5GC,
                  "MC7530 LTE 5GC readback is not misclassified as generic NR/LTE",
                  failures: &failures)
        } catch {
            failures.append("MC7530 LTE 5GC mapping: \(error)")
        }

        do {
            let http = DirectStatefulMC7530HTTPTransport(
                state: .baseline,
                emitNumericPLMNComponents: true
            )
            let session = try await openMC7530ControlSession(http: http, timing: timing)
            let state = try await session.refresh()
            check(state.operatorSelection?.plmn == "00101",
                  "MC7530 numeric MCC/MNC preserves leading zeros with typed formatting",
                  failures: &failures)
        } catch {
            failures.append("MC7530 numeric PLMN component formatting: \(error)")
        }

        do {
            var unknownMode = DirectMC7530FixtureState.baseline
            unknownMode.netSelect = "UNVERIFIED_VENDOR_TOKEN"
            var emptyBands = DirectMC7530FixtureState.baseline
            emptyBands.lteBands = []
            for (label, fixtureState) in [
                ("unknown net_select", unknownMode),
                ("empty LTE band baseline", emptyBands)
            ] {
                let http = DirectStatefulMC7530HTTPTransport(state: fixtureState)
                let session = try await openMC7530ControlSession(http: http, timing: timing)
                do {
                    _ = try await session.perform(.lockLTEBands(Set([2])))
                    failures.append("MC7530 \(label) must fail closed")
                } catch let error as ZTEUBusError {
                    check(error == .invalidResponse,
                          "MC7530 \(label) is rejected as invalid readback",
                          failures: &failures)
                }
                let records = await http.records()
                check(records.allSatisfy {
                    !($0.ubusMethod ?? "").hasPrefix("nwinfo_set_") &&
                        !($0.ubusMethod ?? "").hasPrefix("nwinfo_lock_")
                }, "MC7530 \(label) blocks all writes", failures: &failures)
            }
        } catch {
            failures.append("MC7530 fail-closed raw state gate: \(error)")
        }

        do {
            for polluted in [
                "2,Fixture,302evil220,13;",
                "2,Fixture,302-220,13;",
                "2,Fixture,３０２２２０,13;",
                "2,Fixture,302220,13junk;"
            ] {
                do {
                    _ = try MC7530ControlSession.parseNetworks(polluted)
                    failures.append("MC7530 polluted scan PLMN/RAT must be rejected: \(polluted)")
                } catch let error as ModemControlError {
                    if case .verificationFailed = error {} else {
                        failures.append("MC7530 polluted scan token error type: \(error)")
                    }
                }
            }
            var malformedIdentity = DirectMC7530FixtureState.baseline
            malformedIdentity.mcc = "00x1"
            let http = DirectStatefulMC7530HTTPTransport(state: malformedIdentity)
            let session = try await openMC7530ControlSession(http: http, timing: timing)
            do {
                _ = try await session.perform(.lockLTEBands(Set([2])))
                failures.append("MC7530 malformed MCC must fail closed")
            } catch let error as ZTEUBusError {
                check(error == .invalidResponse,
                      "MC7530 malformed MCC is rejected as authoritative readback",
                      failures: &failures)
            }
            let malformedRecords = await http.records()
            check(malformedRecords.allSatisfy {
                !($0.ubusMethod ?? "").hasPrefix("nwinfo_set_") &&
                    !($0.ubusMethod ?? "").hasPrefix("nwinfo_lock_")
            }, "MC7530 malformed MCC blocks every write", failures: &failures)
        } catch {
            failures.append("MC7530 strict PLMN parsing: \(error)")
        }

        do {
            let http = DirectStatefulMC7530HTTPTransport(
                state: .baseline,
                scanStatuses: ["manual_selecting", "manual_complete"],
                scanContents: "1,Fixture Alpha,00101,7;2,Fixture Beta,00102,13;3,Fixture Gamma,00103,11;"
            )
            let session = try await openMC7530ControlSession(http: http, timing: timing)
            let networks = try await session.perform(.scanNetworks).scannedNetworks ?? []
            check(networks.map(\.plmn) == ["00102", "00101", "00103"],
                  "MC7530 scan parses and sorts current/available/forbidden rows", failures: &failures)
            check(networks.map(\.selectionToken) == ["13", "7", "11"],
                  "MC7530 scan preserves exact m_rat selection tokens", failures: &failures)
            check(networks.first?.accessTechnologies == [.lteNRDualConnectivity] &&
                    networks.last?.accessTechnologies == [.nr5GC],
                  "MC7530 scan maps registration RAT values", failures: &failures)
            let records = await http.records()
            let scanMethods = Set([
                "nwinfo_manual_scan", "nwinfo_m_netselect_status", "nwinfo_m_netselect_contents"
            ])
            let actions = records.filter { scanMethods.contains($0.ubusMethod ?? "") }
            check(actions.map(\.ubusMethod) == [
                "nwinfo_manual_scan", "nwinfo_m_netselect_status",
                "nwinfo_m_netselect_status", "nwinfo_m_netselect_contents"
            ], "MC7530 scan polls status before reading contents", failures: &failures)
            check(actions.allSatisfy {
                $0.header("Z-Mode") == "0" && $0.header("Z-Tag") == ""
            }, "MC7530 scan and polling use the verified SID-authenticated header form",
               failures: &failures)
        } catch {
            failures.append("MC7530 scan/status/contents: \(error)")
        }

        do {
            let http = DirectStatefulMC7530HTTPTransport(
                state: .baseline,
                registrationResults: ["manual_selecting", "manual_success"]
            )
            let session = try await openMC7530ControlSession(http: http, timing: timing)
            let network = CellularNetwork(
                longName: "Fixture Selected", shortName: "Fixture", plmn: "00102",
                availability: .available, accessTechnologies: [.lteNRDualConnectivity],
                selectionToken: "13"
            )
            let result = try await session.perform(.selectNetwork(network))
            check(result.state.operatorSelection?.mode == .manual &&
                    result.state.operatorSelection?.plmn == "00102",
                  "MC7530 manual registration verifies selected PLMN", failures: &failures)
            let records = await http.records()
            let register = records.first { $0.ubusMethod == "nwinfo_manual_register" }
            check(register?.parameters == ["m_mcc_mnc": "00102", "m_rat": "13"],
                  "MC7530 manual registration sends exact PLMN/RAT parameters", failures: &failures)
            check(register?.header("Z-Mode") == "0" && register?.header("Z-Tag") == "",
                  "MC7530 manual registration uses the verified SID-authenticated header form",
                  failures: &failures)
            let polls = records.filter { $0.ubusMethod == "nwinfo_m_netselect_result" }
            check(polls.count == 2 && polls.allSatisfy {
                $0.header("Z-Mode") == "0" && $0.header("Z-Tag") == ""
            }, "MC7530 manual registration polls authenticated result", failures: &failures)
        } catch {
            failures.append("MC7530 manual registration/readback: \(error)")
        }

        do {
            let http = DirectStatefulMC7530HTTPTransport(
                state: .baseline,
                scanContents: "2,Fixture Carrier,00101,13;"
            )
            let session = try await openMC7530ControlSession(http: http, timing: timing)
            _ = try await session.perform(.selectNetwork(CellularNetwork(
                longName: "Fixture LTE",
                shortName: "Fixture",
                plmn: "00101",
                availability: .available,
                accessTechnologies: [.lte],
                selectionToken: "7"
            )))
            _ = try await session.perform(.scanNetworks)
            _ = try await session.perform(.setArchitecture(.nsaOnly))
            let registrations = await http.records()
                .filter { $0.ubusMethod == "nwinfo_manual_register" }
            check(registrations.map { $0.parameters["m_rat"] } == ["7", "13"],
                  "MC7530 fresh current scan row replaces cached RAT for same PLMN",
                  failures: &failures)
        } catch {
            failures.append("MC7530 fresh scan RAT cache replacement: \(error)")
        }

        do {
            let http = DirectStatefulMC7530HTTPTransport(state: .baseline)
            let session = try await openMC7530ControlSession(http: http, timing: timing)
            let incompatible = CellularNetwork(
                longName: "Fixture SA", shortName: "Fixture", plmn: "00102",
                availability: .available, accessTechnologies: [.nr5GC],
                selectionToken: "11"
            )
            do {
                _ = try await session.perform(.selectNetwork(incompatible))
                failures.append("MC7530 incompatible manual RAT must fail")
            } catch let error as ModemControlError {
                if case .invalidState = error {} else {
                    failures.append("MC7530 incompatible manual RAT error type: \(error)")
                }
            }
            let records = await http.records()
            check(records.allSatisfy {
                $0.ubusMethod != "nwinfo_manual_register" &&
                    $0.ubusMethod != "nwinfo_reset_band_cell_setting"
            }, "MC7530 incompatible manual RAT is rejected before every write", failures: &failures)
        } catch {
            failures.append("MC7530 manual RAT/net_select compatibility: \(error)")
        }

        for (mode, token) in [
            (NRArchitectureMode.automatic, "WL_AND_NSA"),
            (.nsaOnly, "LTE_AND_5G"), (.saOnly, "Only_5G"), (.lteOnly, "Only_LTE")
        ] {
            do {
                let http = DirectStatefulMC7530HTTPTransport(state: .baseline)
                let session = try await openMC7530ControlSession(http: http, timing: timing)
                let result = try await session.perform(.setArchitecture(mode))
                let writes = await http.records().filter { $0.ubusMethod == "nwinfo_set_netselect" }
                check(writes.count == 1 && writes[0].parameters == ["net_select": token],
                      "MC7530 \(mode.rawValue) uses exact ZTE token", failures: &failures)
                check(writes[0].header("Z-Mode") == "0" && writes[0].header("Z-Tag") == "",
                      "MC7530 \(mode.rawValue) uses the verified SID-authenticated header form",
                      failures: &failures)
                check(result.state.architecture == mode,
                      "MC7530 \(mode.rawValue) verifies neutral readback", failures: &failures)
            } catch {
                failures.append("MC7530 architecture token \(token): \(error)")
            }
        }

        do {
            var manualSA = DirectMC7530FixtureState.baseline
            manualSA.netSelect = "Only_5G"
            manualSA.netSelectMode = "manual_select"
            manualSA.networkType = "NR5G SA"
            let blockedHTTP = DirectStatefulMC7530HTTPTransport(state: manualSA)
            let blockedSession = try await openMC7530ControlSession(http: blockedHTTP, timing: timing)
            do {
                _ = try await blockedSession.perform(.selectAutomaticNetwork)
                failures.append("MC7530 unknown manual RAT must block automatic selection")
            } catch let error as ModemControlError {
                if case .invalidState = error {} else {
                    failures.append("MC7530 unknown manual RAT error type: \(error)")
                }
            }
            let blockedRecords = await blockedHTTP.records()
            check(blockedRecords.allSatisfy { $0.ubusMethod != "nwinfo_set_netselect" },
                  "MC7530 unknown manual RAT fails before destructive write", failures: &failures)

            let http = DirectStatefulMC7530HTTPTransport(
                state: manualSA,
                scanContents: "2,Fixture Carrier,00101,11;"
            )
            let session = try await openMC7530ControlSession(http: http, timing: timing)
            _ = try await session.perform(.scanNetworks)
            let result = try await session.perform(.selectAutomaticNetwork)
            let write = await http.records().first { $0.ubusMethod == "nwinfo_set_netselect" }
            check(write?.parameters == ["net_select": "Only_5G"],
                  "MC7530 scanned manual RAT allows automatic selection with preserved architecture", failures: &failures)
            check(result.state.operatorSelection?.mode == .automatic && result.state.architecture == .saOnly,
                  "MC7530 automatic operator selection readback preserves SA-only mode", failures: &failures)

            let incompatibleHTTP = DirectStatefulMC7530HTTPTransport(
                state: manualSA,
                scanContents: "2,Fixture Carrier,00101,11;"
            )
            let incompatibleSession = try await openMC7530ControlSession(
                http: incompatibleHTTP,
                timing: timing
            )
            _ = try await incompatibleSession.perform(.scanNetworks)
            do {
                _ = try await incompatibleSession.perform(.setArchitecture(.lteOnly))
                failures.append("MC7530 manual SA RAT must not be replayed into LTE-only")
            } catch let error as ModemControlError {
                if case .invalidState = error {} else {
                    failures.append("MC7530 incompatible architecture replay type: \(error)")
                }
            }
            let incompatibleRecords = await incompatibleHTTP.records()
            check(incompatibleRecords.allSatisfy {
                $0.ubusMethod != "nwinfo_set_netselect" &&
                    $0.ubusMethod != "nwinfo_manual_register"
            }, "MC7530 incompatible architecture is blocked before persistent writes",
               failures: &failures)
        } catch {
            failures.append("MC7530 automatic operator selection: \(error)")
        }

        do {
            var automatic = DirectMC7530FixtureState.baseline
            automatic.netSelect = "WL_AND_NSA"
            let http = DirectStatefulMC7530HTTPTransport(state: automatic)
            let session = try await openMC7530ControlSession(http: http, timing: timing)
            let nrResult = try await session.perform(.lockNRBands(Set([5, 77])))
            let lteResult = try await session.perform(.lockLTEBands(Set([2, 66])))
            check(nrResult.state.saBands == Set([5, 77]) && nrResult.state.nsaBands == Set([5, 77]),
                  "MC7530 automatic mode verifies both SA and NSA locks", failures: &failures)
            check(lteResult.state.lteBands == Set([2, 66]),
                  "MC7530 verifies LTE lock readback", failures: &failures)
            let records = await http.records()
            let nrWrites = records.filter { $0.ubusMethod == "nwinfo_set_nrbandlock" }
            check(nrWrites.map(\.parameters) == [
                ["nr5g_band": "5,77", "nr5g_type": "0"],
                ["nr5g_band": "5,77", "nr5g_type": "1"]
            ], "MC7530 NR lock writes exact sorted SA/NSA parameters", failures: &failures)
            let lteWrite = records.first { $0.ubusMethod == "nwinfo_set_lte_ext_band" }
            check(lteWrite?.parameters == ["lte_band": "2,66"],
                  "MC7530 LTE lock writes exact sorted parameters", failures: &failures)
            check((nrWrites + [lteWrite].compactMap { $0 }).allSatisfy {
                $0.header("Z-Mode") == "0" && $0.header("Z-Tag") == ""
            }, "MC7530 band locks use the verified SID-authenticated header form",
               failures: &failures)
        } catch {
            failures.append("MC7530 NR/LTE band locks: \(error)")
        }

        await runMC7530RollbackRestoreAndIdentityTests(timing: timing, failures: &failures)
    }

    private static func runMC7530RollbackRestoreAndIdentityTests(
        timing: MC7530ControlTiming,
        failures: inout [String]
    ) async {
        do {
            let baseline = DirectMC7530FixtureState.baseline
            let http = DirectStatefulMC7530HTTPTransport(
                state: baseline,
                ignoredLTEWriteApplications: 1
            )
            let session = try await openMC7530ControlSession(http: http, timing: timing)
            do {
                _ = try await session.perform(.lockLTEBands(Set([2, 66])))
                failures.append("MC7530 unverified LTE setter must fail")
            } catch let error as ModemControlError {
                if case .verificationFailed = error {} else {
                    failures.append("MC7530 LTE readback failure type: \(error)")
                }
            }
            let records = await http.records()
            let lteWrites = records.filter { $0.ubusMethod == "nwinfo_set_lte_ext_band" }
            check(lteWrites.map(\.parameters) == [
                ["lte_band": "2,66"], ["lte_band": "2,4,66"]
            ], "MC7530 accepted-but-unverified LTE write restores original bands", failures: &failures)
            check(records.contains { $0.ubusMethod == "nwinfo_reset_band_cell_setting" } &&
                    records.contains { $0.ubusMethod == "nwinfo_set_nrbandlock" } &&
                    records.contains { $0.ubusMethod == "nwinfo_set_netselect" },
                  "MC7530 LTE failure rebuilds every persistent field from the verified baseline",
                  failures: &failures)
            let recovered = await http.currentState()
            check(recovered == baseline,
                  "MC7530 LTE rollback confirms full original state", failures: &failures)
        } catch {
            failures.append("MC7530 LTE readback rollback: \(error)")
        }

        do {
            let baseline = DirectMC7530FixtureState.baseline
            let http = DirectStatefulMC7530HTTPTransport(
                state: baseline,
                collateralGWChangesAfterLTEApplications: 1
            )
            let session = try await openMC7530ControlSession(http: http, timing: timing)
            do {
                _ = try await session.perform(.lockLTEBands(Set([2, 66])))
                failures.append("MC7530 collateral setter change must fail verification")
            } catch let error as ModemControlError {
                if case .verificationFailed = error {} else {
                    failures.append("MC7530 collateral change failure type: \(error)")
                }
            }
            let recovered = await http.currentState()
            check(recovered == baseline,
                  "MC7530 collateral GW change is detected and fully restored",
                  failures: &failures)
        } catch {
            failures.append("MC7530 collateral write detection: \(error)")
        }

        do {
            let baseline = DirectMC7530FixtureState.baseline
            let http = DirectStatefulMC7530HTTPTransport(
                state: baseline,
                lostLTEResponsesAfterApplications: 1
            )
            let session = try await openMC7530ControlSession(http: http, timing: timing)
            do {
                _ = try await session.perform(.lockLTEBands(Set([2, 66])))
                failures.append("MC7530 lost applied-write response must fail the command")
            } catch {}
            let recovered = await http.currentState()
            check(recovered == baseline,
                  "MC7530 ambiguous applied LTE write is reconciled by full readback/restore",
                  failures: &failures)
        } catch {
            failures.append("MC7530 ambiguous write recovery: \(error)")
        }

        do {
            let baseline = DirectMC7530FixtureState.baseline
            let http = DirectStatefulMC7530HTTPTransport(
                state: baseline,
                ignoredLTEWriteApplications: 1,
                lostResetResponsesAfterApplications: 1
            )
            let session = try await openMC7530ControlSession(http: http, timing: timing)
            do {
                _ = try await session.perform(.lockLTEBands(Set([2, 66])))
                failures.append("MC7530 unverified write with lost reset response must fail")
            } catch let error as ModemControlError {
                if case .verificationFailed = error {} else {
                    failures.append("MC7530 reconciled rollback should preserve original error: \(error)")
                }
            }
            let records = await http.records()
            let recovered = await http.currentState()
            check(recovered == baseline &&
                    records.contains { $0.ubusMethod == "nwinfo_set_gwl_bandlock" } &&
                    records.contains { $0.ubusMethod == "nwinfo_set_netselect" },
                  "MC7530 rollback continues after a lost reset response and trusts exact final readback",
                  failures: &failures)
        } catch {
            failures.append("MC7530 best-effort rollback sequencing: \(error)")
        }

        do {
            let baseline = DirectMC7530FixtureState.baseline
            let http = DirectStatefulMC7530HTTPTransport(
                state: baseline,
                suspendedLTEResponsesAfterApplications: 1
            )
            let session = try await openMC7530ControlSession(http: http, timing: timing)
            let operation = Task {
                try await session.perform(.lockLTEBands(Set([2, 66])))
            }
            for _ in 0..<200 {
                if (await http.records()).contains(where: {
                    $0.ubusMethod == "nwinfo_set_lte_ext_band"
                }) { break }
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            operation.cancel()
            do {
                _ = try await operation.value
                failures.append("MC7530 canceled applied write must not report success")
            } catch {
                check(error is CancellationError,
                      "MC7530 preserves cancellation after cleanup", failures: &failures)
            }
            let recovered = await http.currentState()
            let records = await http.records()
            check(recovered == baseline && records.contains {
                $0.ubusMethod == "nwinfo_reset_band_cell_setting"
            },
                  "MC7530 cancellation runs rollback in an uncancelled cleanup task",
                  failures: &failures)
        } catch {
            failures.append("MC7530 cancellation-safe rollback: \(error)")
        }

        do {
            var automatic = DirectMC7530FixtureState.baseline
            automatic.netSelect = "WL_AND_NSA"
            let http = DirectStatefulMC7530HTTPTransport(
                state: automatic,
                ignoredNRWriteApplications: ["1": 1]
            )
            let session = try await openMC7530ControlSession(http: http, timing: timing)
            do {
                _ = try await session.perform(.lockNRBands(Set([5, 71])))
                failures.append("MC7530 partially applied NR setter must fail")
            } catch let error as ModemControlError {
                if case .verificationFailed = error {} else {
                    failures.append("MC7530 NR readback failure type: \(error)")
                }
            }
            let records = await http.records()
            let nrWrites = records.filter { $0.ubusMethod == "nwinfo_set_nrbandlock" }
            check(nrWrites.map(\.parameters) == [
                ["nr5g_band": "5,71", "nr5g_type": "0"],
                ["nr5g_band": "5,71", "nr5g_type": "1"],
                ["nr5g_band": "5,77", "nr5g_type": "0"],
                ["nr5g_band": "2,66,77", "nr5g_type": "1"]
            ], "MC7530 partial NR write restores original SA/NSA bands", failures: &failures)
            check(records.contains { $0.ubusMethod == "nwinfo_reset_band_cell_setting" } &&
                    records.contains { $0.ubusMethod == "nwinfo_set_lte_ext_band" } &&
                    records.contains { $0.ubusMethod == "nwinfo_set_netselect" },
                  "MC7530 NR failure rebuilds every persistent field from the verified baseline",
                  failures: &failures)
            let recovered = await http.currentState()
            check(recovered == automatic,
                  "MC7530 NR rollback confirms full original state", failures: &failures)
        } catch {
            failures.append("MC7530 NR readback rollback: \(error)")
        }

        do {
            let baseline = DirectMC7530FixtureState.baseline
            let http = DirectStatefulMC7530HTTPTransport(
                state: baseline,
                ignoredNetSelectWriteApplications: 1
            )
            let session = try await openMC7530ControlSession(http: http, timing: timing)
            do {
                _ = try await session.perform(.setArchitecture(.lteOnly))
                failures.append("MC7530 unverified architecture setter must fail")
            } catch let error as ModemControlError {
                if case .verificationFailed = error {} else {
                    failures.append("MC7530 architecture readback failure type: \(error)")
                }
            }
            let tokens = await http.records()
                .filter { $0.ubusMethod == "nwinfo_set_netselect" }
                .compactMap { $0.parameters["net_select"] }
            check(tokens == ["Only_LTE", baseline.netSelect],
                  "MC7530 failed mode readback restores exact original token", failures: &failures)
            let recovered = await http.currentState()
            check(recovered == baseline,
                  "MC7530 mode rollback confirms full original state", failures: &failures)
        } catch {
            failures.append("MC7530 architecture readback rollback: \(error)")
        }

        do {
            var malformed = DirectMC7530FixtureState.baseline
            malformed.lteCellLock = "17,5010,unexpected"
            let http = DirectStatefulMC7530HTTPTransport(state: malformed)
            let session = try await openMC7530ControlSession(http: http, timing: timing)
            do {
                _ = try await session.perform(.restoreDefaults)
                failures.append("MC7530 malformed rollback cell state must block restore")
            } catch let error as ModemControlError {
                if case .invalidState = error {} else {
                    failures.append("MC7530 malformed rollback preflight type: \(error)")
                }
            }
            let records = await http.records()
            check(records.allSatisfy {
                $0.ubusMethod != "nwinfo_reset_band_cell_setting" &&
                    !($0.ubusMethod ?? "").hasPrefix("nwinfo_set_") &&
                    !($0.ubusMethod ?? "").hasPrefix("nwinfo_lock_")
            }, "MC7530 malformed cell rollback is rejected before every write", failures: &failures)
        } catch {
            failures.append("MC7530 restore rollback preflight: \(error)")
        }

        do {
            var nondefaultNRDC = DirectMC7530FixtureState.baseline
            nondefaultNRDC.nrdcBands = Set([77])
            let http = DirectStatefulMC7530HTTPTransport(state: nondefaultNRDC)
            let session = try await openMC7530ControlSession(http: http, timing: timing)
            do {
                _ = try await session.perform(.lockLTEBands(Set([2, 66])))
                failures.append("MC7530 nondefault NRDC must block an unrecoverable write")
            } catch let error as ModemControlError {
                if case .invalidState = error {} else {
                    failures.append("MC7530 nondefault NRDC preflight type: \(error)")
                }
            }
            let records = await http.records()
            check(records.allSatisfy {
                $0.ubusMethod != "nwinfo_reset_band_cell_setting" &&
                    !($0.ubusMethod ?? "").hasPrefix("nwinfo_set_") &&
                    !($0.ubusMethod ?? "").hasPrefix("nwinfo_lock_")
            }, "MC7530 nondefault NRDC blocks every write before mutation", failures: &failures)
        } catch {
            failures.append("MC7530 NRDC rollback preflight: \(error)")
        }

        do {
            var restricted = DirectMC7530FixtureState.baseline
            restricted.netSelect = "Only_LTE"
            restricted.lteBands = Set([2, 66])
            restricted.saBands = Set([77])
            restricted.nsaBands = Set([66, 77])
            restricted.gwBandLock = "0x123"
            restricted.lteCellLock = "17,5010"
            restricted.nrCellLock = "42,640000,77"
            let http = DirectStatefulMC7530HTTPTransport(
                state: restricted,
                ignoredNetSelectWriteApplications: 1
            )
            let session = try await openMC7530ControlSession(http: http, timing: timing)
            do {
                _ = try await session.perform(.restoreDefaults)
                failures.append("MC7530 unverified restore mode must fail")
            } catch let error as ModemControlError {
                if case .verificationFailed = error {} else {
                    failures.append("MC7530 failed restore readback type: \(error)")
                }
            }
            let recovered = await http.currentState()
            check(recovered == restricted,
                  "MC7530 failed global restore recovers exact GW/band/cell/mode state",
                  failures: &failures)
            let rollbackRecords = await http.records()
            let gwWrite = rollbackRecords.first {
                $0.ubusMethod == "nwinfo_set_gwl_bandlock"
            }
            check(gwWrite?.parameters == [
                "is_gw_band": "1", "gw_band_mask": "0x123",
                "is_lte_band": "0", "lte_band_mask": "0"
            ], "MC7530 rollback uses exact GW UBus schema", failures: &failures)
        } catch {
            failures.append("MC7530 complete global restore rollback: \(error)")
        }

        do {
            var restricted = DirectMC7530FixtureState.baseline
            restricted.netSelect = "Only_LTE"
            restricted.lteBands = Set([2, 66])
            restricted.saBands = Set([77])
            restricted.nsaBands = Set([66, 77])
            restricted.gwBandLock = "0x123"
            restricted.lteCellLock = "17,5010"
            restricted.nrCellLock = "42,640000,77"
            let http = DirectStatefulMC7530HTTPTransport(state: restricted)
            let session = try await openMC7530ControlSession(http: http, timing: timing)
            let result = try await session.perform(.restoreDefaults)
            check(result.state.architecture == .automatic &&
                    result.state.lteBands == MC7530ControlSession.defaultLTEBands &&
                    result.state.saBands == MC7530ControlSession.defaultNRBands &&
                    result.state.nsaBands == MC7530ControlSession.defaultNRBands,
                  "MC7530 restore verifies automatic mode and retail default bands", failures: &failures)
            let restored = await http.currentState()
            check(restored.gwBandLock == MC7530ControlSession.defaultGWBandMask &&
                    restored.nrdcBands == restricted.nrdcBands &&
                    restored.lteCellLock.isEmpty && restored.nrCellLock.isEmpty,
                  "MC7530 restore verifies GW default, NRDC invariant, and cleared cell locks",
                  failures: &failures)
            let records = await http.records()
            let reset = records.first { $0.ubusMethod == "nwinfo_reset_band_cell_setting" }
            check(reset?.parameters.isEmpty == true && reset?.header("Z-Mode") == "0" &&
                    reset?.header("Z-Tag") == "",
                  "MC7530 restore sends the exact reset with the verified header form",
                  failures: &failures)
            let mode = records.last { $0.ubusMethod == "nwinfo_set_netselect" }
            check(mode?.parameters == ["net_select": "WL_AND_NSA"],
                  "MC7530 restore finishes with exact WL_AND_NSA token", failures: &failures)
        } catch {
            failures.append("MC7530 restore defaults: \(error)")
        }

        do {
            let http = DirectScriptedZTEHTTPTransport(responses: [
                zteCallResponse(#"{"zte_web_sault":"fixture-salt"}"#),
                zteCallResponse(#"{"result":"0","ubus_rpc_session":"fixture-sid"}"#),
                zteCallResponse(#"{"serial":"fixture-but-unverified-field"}"#)
            ])
            let auth = ZTEAuthSession(
                transport: try ZTEUBusTransport(
                    baseURL: URL(string: "http://192.0.2.1")!, http: http
                ),
                password: "fixture-password"
            )
            do {
                _ = try await MC7530ControlSession.open(
                    session: auth,
                    timing: timing,
                    sleep: { _ in }
                )
                failures.append("MC7530 unknown MSN field must fail closed")
            } catch let error as ModemBackendError {
                check(error == .identityUnavailable,
                      "MC7530 unknown MSN field error", failures: &failures)
            }
            let records = await http.records()
            check(records.count == 3 && records.last?.ubusMethod == "get_modem_msn",
                  "MC7530 unknown MSN field stops during session binding", failures: &failures)
            check(records.allSatisfy { !($0.ubusMethod ?? "").hasPrefix("nwinfo_set_") },
                  "MC7530 unknown MSN field performs no write", failures: &failures)
        } catch {
            failures.append("MC7530 unknown MSN fail-closed setup: \(error)")
        }

        do {
            let http = DirectStatefulMC7530HTTPTransport(
                state: .baseline,
                fingerprintSequence: ["fixture-device-alpha", "fixture-device-beta"]
            )
            let session = try await openMC7530ControlSession(http: http, timing: timing)
            for attempt in 1...2 {
                do {
                    _ = try await session.perform(.setArchitecture(.lteOnly))
                    failures.append("MC7530 changed-device attempt \(attempt) must fail")
                } catch let error as ModemControlError {
                    check(error == .deviceChanged,
                          "MC7530 changed-device error \(attempt)", failures: &failures)
                }
            }
            let records = await http.records()
            check(records.filter { $0.ubusMethod == "get_modem_msn" }.count == 2,
                  "MC7530 fingerprint mismatch permanently invalidates session", failures: &failures)
            check(records.allSatisfy { $0.ubusMethod != "nwinfo_set_netselect" },
                  "MC7530 fingerprint mismatch blocks all writes", failures: &failures)
        } catch {
            failures.append("MC7530 fingerprint change guard: \(error)")
        }
    }

    private static func openMC7530ControlSession(
        http: DirectStatefulMC7530HTTPTransport,
        timing: MC7530ControlTiming
    ) async throws -> MC7530ControlSession {
        let auth = ZTEAuthSession(
            transport: try ZTEUBusTransport(baseURL: URL(string: "http://192.0.2.1")!, http: http),
            password: "fixture-password"
        )
        return try await MC7530ControlSession.open(
            session: auth,
            timing: timing,
            sleep: { _ in }
        )
    }

    private static func runDiscoveryTests(failures: inout [String]) async {
        let builtInTimeouts = Dictionary(
            uniqueKeysWithValues: ModemDiscoveryProfile.builtIn.map {
                ($0.kind, $0.probeTimeoutNanoseconds)
            }
        )
        check(builtInTimeouts[.zteMC7530CA] == 5_000_000_000,
              "ZTE discovery budget covers authenticated identity chain", failures: &failures)
        check(builtInTimeouts[.vos5G] == 9_000_000_000,
              "VOS discovery exceeds the SSH probe budget", failures: &failures)

        let direct = NetworkTopologySnapshot(interfaces: [directDiscoveryInterface(
            name: "en8", index: 18, address: "192.168.254.20", prefixLength: 24,
            router: "192.168.254.1"
        )])
        let directCandidates = ModemCandidateGenerator().candidates(
            topology: direct,
            allowedKinds: [.zteMC7530CA]
        )
        check(directCandidates.count == 1, "discovery direct candidate count", failures: &failures)
        if let candidate = directCandidates.first {
            check(candidate.key.host == "192.168.254.1" && candidate.key.interfaceIndex == 18,
                  "discovery host plus interface scope", failures: &failures)
            check(candidate.endpoint.sourceAddress == "192.168.254.20" && candidate.endpoint.gateway == "192.168.254.1",
                  "discovery direct route metadata", failures: &failures)
            check(candidate.endpoint.connectionPath == .unknown,
                  "discovery direct enX avoids guessing USB versus RJ45", failures: &failures)
            check(candidate.sources.contains(.matchingSubnet) && candidate.sources.contains(.matchingGateway),
                  "discovery direct evidence", failures: &failures)
        }

        let routed = NetworkTopologySnapshot(interfaces: [directDiscoveryInterface(
            name: "en1", index: 6, address: "192.168.8.23", prefixLength: 24,
            router: "192.168.8.1", isPrimary: true
        )])
        if let routedRouter = ModemCandidateGenerator().candidates(
            topology: routed,
            allowedKinds: [.zteMC7530CA]
        ).first {
            check(routedRouter.endpoint.connectionPath == .routed, "discovery routed-router path", failures: &failures)
            check(routedRouter.endpoint.sourceAddress == "192.168.8.23" && routedRouter.endpoint.gateway == "192.168.8.1",
                  "discovery routed-router metadata", failures: &failures)
        } else {
            failures.append("discovery routed-router candidate")
        }

        let multi = NetworkTopologySnapshot(interfaces: [
            directDiscoveryInterface(name: "en5", index: 12, address: "192.168.254.20", prefixLength: 24, router: "192.168.254.1"),
            directDiscoveryInterface(name: "en8", index: 18, address: "192.168.254.30", prefixLength: 24, router: "192.168.254.1"),
            directDiscoveryInterface(name: "utun4", index: 20, address: "10.0.0.2", prefixLength: 24, router: nil, kind: .tunnel),
            directDiscoveryInterface(name: "awdl0", index: 21, address: "169.254.5.2", prefixLength: 16, router: nil, kind: .peerToPeer)
        ])
        let multiCandidates = ModemCandidateGenerator().candidates(
            topology: multi,
            allowedKinds: [.zteMC7530CA]
        )
        check(multiCandidates.count == 2, "discovery excludes tunnel/peer interfaces", failures: &failures)
        check(Set(multiCandidates.map { $0.key.interfaceIndex }) == [12, 18],
              "discovery preserves duplicate private host per interface", failures: &failures)
        check(Set(multiCandidates.map(\.id)).count == 2,
              "discovery scoped candidate identifiers", failures: &failures)

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
        let ranked = ModemCandidateGenerator().candidates(
            topology: direct,
            hints: hints,
            allowedKinds: [.zteMC7530CA]
        )
        if let first = ranked.first,
           let manual = ranked.first(where: { $0.key.effectivePort == 8080 }),
           let cached = ranked.first(where: { $0.key.effectivePort == 80 }) {
            check(first.id == manual.id && first.priority == ModemDiscoveryCandidateSource.manual.rawValue,
                  "discovery manual address outranks cached endpoint", failures: &failures)
            check(cached.sources.contains(.knownDefault) && cached.sources.contains(.matchingSubnet),
                  "discovery merges cached/default evidence", failures: &failures)
            check(manual.priority == ModemDiscoveryCandidateSource.manual.rawValue,
                  "discovery manual priority", failures: &failures)
        } else {
            failures.append("discovery ranked hints")
        }

        let portProfile = ModemDiscoveryProfile(
            kind: .zteMC7530CA,
            defaultBaseURLs: [
                URL(string: "http://192.168.50.1")!,
                URL(string: "http://192.168.50.1:80")!,
                URL(string: "https://192.168.50.1")!,
                URL(string: "http://192.168.50.1:8080")!
            ]
        )
        let portTopology = NetworkTopologySnapshot(interfaces: [directDiscoveryInterface(
            name: "en2", index: 7, address: "192.168.50.20", prefixLength: 24, router: "192.168.50.1"
        )])
        let portCandidates = ModemCandidateGenerator(profiles: [portProfile]).candidates(topology: portTopology)
        check(Set(portCandidates.map { $0.key.description }) == [
            "http://192.168.50.1:80%7",
            "https://192.168.50.1:443%7",
            "http://192.168.50.1:8080%7"
        ], "discovery scheme/port identity", failures: &failures)

        let provider = DirectFixedNetworkTopologyProvider(snapshot: routed)
        let engine = ModemDiscoveryEngine(
            topologyProvider: provider,
            probe: ClosureModemDiscoveryProbe { candidate in
                let delay: UInt64 = candidate.kind == .vos5G ? 40_000_000 : 1_000_000
                try await Task.sleep(nanoseconds: delay)
                return directIdentity(candidate.kind)
            },
            maximumConcurrentProbes: 2,
            probeTimeoutNanoseconds: 500_000_000
        )
        let expectedOrder = engine.candidates().map(\.id)
        let orderedReport = await engine.discover()
        check(orderedReport.attempts.map { $0.candidate.id } == expectedOrder,
              "discovery result order is deterministic", failures: &failures)
        let zteOnly = await engine.discover(allowedKinds: [.zteMC7530CA])
        check(zteOnly.attempts.count == 1 && zteOnly.attempts.first?.candidate.kind == .zteMC7530CA,
              "discovery allowedKinds filters before probe", failures: &failures)

        let timeoutEngine = ModemDiscoveryEngine(
            topologyProvider: provider,
            probe: ClosureModemDiscoveryProbe { candidate in
                await withCheckedContinuation { continuation in
                    DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(500)) {
                        continuation.resume()
                    }
                }
                return directIdentity(candidate.kind)
            },
            maximumConcurrentProbes: 2,
            probeTimeoutNanoseconds: 1_000_000
        )
        let start = Date()
        let timeoutReport = await timeoutEngine.discover()
        check(timeoutReport.attempts.allSatisfy { $0.result == .timedOut },
              "discovery non-cooperative probes time out", failures: &failures)
        check(Date().timeIntervalSince(start) < 0.25,
              "discovery timeout does not await non-cooperative probe", failures: &failures)
    }

    private static func runCoordinatorTests(failures: inout [String]) async {
        do {
            let zte = DirectMockModemBackend(kind: .zteMC7530CA)
            let vos = DirectMockModemBackend(kind: .vos5G)
            let registry = try directRegistry(zte: zte, vos: vos)
            let topology = NetworkTopologySnapshot(interfaces: [directDiscoveryInterface(
                name: "en8", index: 18, address: "192.168.254.20", prefixLength: 24,
                router: "192.168.254.1"
            )])
            let coordinator = ModemCoordinator(
                registry: registry,
                topologyProvider: DirectFixedNetworkTopologyProvider(snapshot: topology),
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
            check(!first.reusedActiveEndpoint && second.reusedActiveEndpoint,
                  "coordinator reuses active endpoint", failures: &failures)
            let zteHistory = await zte.history()
            let vosHistory = await vos.history()
            check(zteHistory.identifyCredentials == [web],
                  "coordinator ZTE identification receives available Web credentials", failures: &failures)
            check(zteHistory.fetchCredentials == [web, web],
                  "coordinator ZTE status uses web credential", failures: &failures)
            check(vosHistory.identifyCredentials.isEmpty && vosHistory.fetchCredentials.isEmpty,
                  "coordinator selection filters VOS before probing", failures: &failures)

            let preferences = ModemConnectionPreferences(
                selection: .zteMC7530CA,
                manualEndpoints: [ModemEndpointPreference(
                    kind: .zteMC7530CA,
                    baseURL: URL(string: "http://192.168.254.1")!,
                    interfaceName: "en8",
                    interfaceIndex: 18
                )],
                lastSuccessfulScopeKey: first.lastSuccessfulScopeKey,
                lastSuccessfulEndpoint: first.lastSuccessfulEndpoint
            )
            let encoded = try JSONEncoder().encode(preferences)
            check(try JSONDecoder().decode(ModemConnectionPreferences.self, from: encoded) == preferences,
                  "coordinator preferences Codable round trip", failures: &failures)
            check(!String(decoding: encoded, as: UTF8.self).contains("fixture-web-password"),
                  "coordinator preferences exclude secrets", failures: &failures)
        } catch {
            failures.append("coordinator ZTE policy/reuse: \(error)")
        }

        do {
            let topology = NetworkTopologySnapshot(interfaces: [directDiscoveryInterface(
                name: "en8", index: 18, address: "192.168.254.20", prefixLength: 24,
                router: "192.168.254.1"
            )])
            let matchingZTE = DirectMockModemBackend(kind: .zteMC7530CA)
            let matchingCoordinator = ModemCoordinator(
                registry: try directRegistry(zte: matchingZTE),
                topologyProvider: DirectFixedNetworkTopologyProvider(snapshot: topology),
                probeTimeoutNanoseconds: 100_000_000
            )
            do {
                _ = try await matchingCoordinator.read(
                    preferences: ModemConnectionPreferences(selection: .automatic),
                    credentials: ModemConnectionCredentials()
                )
                failures.append("automatic ZTE discovery must require Web credentials after a match")
            } catch let error as ModemCoordinatorError {
                if case let .authenticationFailed(kind, _) = error {
                    check(kind == .zteMC7530CA,
                          "automatic matching ZTE reports its Web credential requirement",
                          failures: &failures)
                } else {
                    failures.append("automatic matching ZTE reports wrong error: \(error)")
                }
            }
            let matchingHistory = await matchingZTE.history()
            check(matchingHistory.identifyCredentials == [.none] &&
                    matchingHistory.fetchCredentials.isEmpty,
                  "automatic ZTE performs anonymous preflight before requiring a password",
                  failures: &failures)

            let unrelated = DirectMockModemBackend(kind: .zteMC7530CA, identifies: false)
            let unrelatedCoordinator = ModemCoordinator(
                registry: try directRegistry(zte: unrelated),
                topologyProvider: DirectFixedNetworkTopologyProvider(snapshot: topology),
                probeTimeoutNanoseconds: 100_000_000
            )
            do {
                _ = try await unrelatedCoordinator.read(
                    preferences: ModemConnectionPreferences(selection: .automatic),
                    credentials: ModemConnectionCredentials()
                )
                failures.append("an unrelated automatic candidate must not match ZTE")
            } catch let error as ModemCoordinatorError {
                check(error == .noMatchingModem,
                      "unrelated automatic candidate is not mislabeled as authentication failure",
                      failures: &failures)
            }
            let unrelatedHistory = await unrelated.history()
            check(unrelatedHistory.identifyCredentials == [.none] &&
                    unrelatedHistory.fetchCredentials.isEmpty,
                  "unrelated automatic candidate receives anonymous preflight only",
                  failures: &failures)
        } catch {
            failures.append("coordinator automatic ZTE two-stage credential policy: \(error)")
        }

        do {
            let http = DirectScriptedZTEHTTPTransport(responses: [
                zteResponse(#"[{"jsonrpc":"2.0","id":1,"result":{"zte_nwinfo_api":{"nwinfo_get_netinfo":{}}}}]"#),
                zteCallResponse(#"{"values":{"wa_inner_version":"MC7530CAV2.6"}}"#)
            ])
            let backend = MC7530Backend(httpTransport: http)
            let profile = ModemDiscoveryProfile(
                kind: .zteMC7530CA,
                defaultBaseURLs: [URL(string: "http://192.168.254.1")!],
                probeTimeoutNanoseconds: 100_000_000
            )
            let registry = try ModemBackendRegistry(registrations: [
                ModemBackendRegistration(
                    backend: backend,
                    discoveryProfile: profile,
                    identificationCredentials: .configuredOrAnonymous(.web),
                    statusCredentials: .configured(.web)
                )
            ])
            let routedTopology = NetworkTopologySnapshot(interfaces: [
                directDiscoveryInterface(
                    name: "en1", index: 6, address: "192.168.8.23", prefixLength: 24,
                    router: "192.168.8.1", isPrimary: true
                )
            ])
            let coordinator = ModemCoordinator(
                registry: registry,
                topologyProvider: DirectFixedNetworkTopologyProvider(snapshot: routedTopology),
                probeTimeoutNanoseconds: 100_000_000
            )
            do {
                _ = try await coordinator.read(
                    preferences: ModemConnectionPreferences(selection: .automatic),
                    credentials: ModemConnectionCredentials()
                )
                failures.append("routed MC7530 preflight must request its missing Web password")
            } catch let error as ModemCoordinatorError {
                if case let .authenticationFailed(kind, _) = error {
                    check(kind == .zteMC7530CA,
                          "routed MC7530 product match survives weak-topology filtering",
                          failures: &failures)
                } else {
                    failures.append("routed MC7530 preflight reports wrong error: \(error)")
                }
            }
            let report = await coordinator.lastDiscoveryReport
            if let attempt = report?.attempts.first,
               case let .failed(_, category, confirmedProduct) = attempt.result {
                let strongEvidence: Set<ModemDiscoveryCandidateSource> = [
                    .matchingSubnet, .matchingGateway, .manual, .lastSuccessful
                ]
                check(category == .authentication && confirmedProduct &&
                        attempt.candidate.sources.isDisjoint(with: strongEvidence),
                      "routed authenticated identity failure retains confirmed-product evidence",
                      failures: &failures)
            } else {
                failures.append("routed MC7530 preflight did not record its confirmed failure")
            }
        } catch {
            failures.append("coordinator routed ZTE confirmed-product credential path: \(error)")
        }

        do {
            let zte = DirectMockModemBackend(kind: .zteMC7530CA, fetchFailures: [false, true, false])
            let registry = try directRegistry(zte: zte)
            let topology = NetworkTopologySnapshot(interfaces: [directDiscoveryInterface(
                name: "en8", index: 18, address: "192.168.254.20", prefixLength: 24,
                router: "192.168.254.1"
            )])
            let coordinator = ModemCoordinator(
                registry: registry,
                topologyProvider: DirectFixedNetworkTopologyProvider(snapshot: topology),
                probeTimeoutNanoseconds: 100_000_000
            )
            let credentials = ModemConnectionCredentials([
                .zteMC7530CA: .web(WebCredentials(password: "fixture-web-password"))
            ])
            _ = try await coordinator.read(
                preferences: ModemConnectionPreferences(selection: .zteMC7530CA),
                credentials: credentials
            )
            let recovered = try await coordinator.read(
                preferences: ModemConnectionPreferences(selection: .zteMC7530CA),
                credentials: credentials
            )
            let history = await zte.history()
            check(!recovered.reusedActiveEndpoint && history.identifyCredentials.count == 2,
                  "coordinator failed active read triggers rediscovery", failures: &failures)
            check(history.fetchCredentials.count == 3,
                  "coordinator retries snapshot only after re-identification", failures: &failures)
        } catch {
            failures.append("coordinator rediscovery: \(error)")
        }

        do {
            let vos = DirectMockModemBackend(kind: .vos5G)
            let registry = try directRegistry(vos: vos)
            let topology = NetworkTopologySnapshot(interfaces: [directDiscoveryInterface(
                name: "en9", index: 19, address: "192.168.225.20", prefixLength: 24,
                router: "192.168.225.1"
            )])
            let coordinator = ModemCoordinator(
                registry: registry,
                topologyProvider: DirectFixedNetworkTopologyProvider(snapshot: topology),
                probeTimeoutNanoseconds: 100_000_000
            )
            let ssh = ModemCredentials.ssh(SSHCredentials(username: "fixture", password: "fixture-ssh-password"))
            _ = try await coordinator.read(
                preferences: ModemConnectionPreferences(selection: .vos5G),
                credentials: ModemConnectionCredentials([.vos5G: ssh])
            )
            let history = await vos.history()
            check(history.identifyCredentials == [ssh] && history.fetchCredentials == [ssh],
                  "coordinator VOS identification/status use SSH", failures: &failures)
        } catch {
            failures.append("coordinator VOS credential policy: \(error)")
        }

        do {
            let zte = DirectMockModemBackend(kind: .zteMC7530CA)
            let registry = try directRegistry(zte: zte)
            let firstEndpoint = ScopedEndpoint(
                baseURL: URL(string: "http://192.168.254.1")!,
                interfaceName: "en5",
                interfaceIndex: 12,
                sourceAddress: "192.168.254.20"
            )
            let preferredEndpoint = ScopedEndpoint(
                baseURL: URL(string: "http://192.168.254.1")!,
                interfaceName: "en8",
                interfaceIndex: 18,
                sourceAddress: "192.168.254.30"
            )
            let report = ModemDiscoveryReport(
                topology: .empty,
                attempts: [firstEndpoint, preferredEndpoint].map { endpoint in
                    ModemDiscoveryAttempt(
                        candidate: ModemDiscoveryCandidate(
                            kind: .zteMC7530CA,
                            endpoint: endpoint,
                            sources: [.knownDefault],
                            priority: ModemDiscoveryCandidateSource.knownDefault.rawValue
                        ),
                        result: .matched(directIdentity(.zteMC7530CA))
                    )
                }
            )
            let coordinator = ModemCoordinator(registry: registry) { _, allowedKinds, _ in
                allowedKinds == [.zteMC7530CA] ? report : ModemDiscoveryReport(topology: .empty, attempts: [])
            }
            let result = try await coordinator.read(
                preferences: ModemConnectionPreferences(
                    selection: .zteMC7530CA,
                    lastSuccessfulScopeKey: preferredEndpoint.scopeKey
                ),
                credentials: ModemConnectionCredentials([
                    .zteMC7530CA: .web(WebCredentials(password: "fixture-web-password"))
                ])
            )
            check(result.activeModem.endpoint == preferredEndpoint,
                  "coordinator prefers last successful scope", failures: &failures)
        } catch {
            failures.append("coordinator last-success ordering: \(error)")
        }

        do {
            let zte = DirectMockModemBackend(kind: .zteMC7530CA)
            let registry = try directRegistry(zte: zte)
            let topology = NetworkTopologySnapshot(interfaces: [directDiscoveryInterface(
                name: "en8", index: 18, address: "192.168.254.20", prefixLength: 24,
                router: "192.168.254.1"
            )])
            let coordinator = ModemCoordinator(
                registry: registry,
                topologyProvider: DirectFixedNetworkTopologyProvider(snapshot: topology),
                probeTimeoutNanoseconds: 100_000_000
            )
            do {
                _ = try await coordinator.read(
                    preferences: ModemConnectionPreferences(selection: .zteMC7530CA),
                    credentials: ModemConnectionCredentials([
                        .zteMC7530CA: .ssh(SSHCredentials(username: "wrong-kind", password: "fixture"))
                    ])
                )
                failures.append("coordinator rejects wrong ZTE credential kind")
            } catch let error as ModemBackendError {
                check(
                    error == .incompatibleCredentials(expected: .web, actual: .ssh),
                    "coordinator reports incompatible credential before discovery",
                    failures: &failures
                )
            }
            let history = await zte.history()
            check(history.identifyCredentials.isEmpty && history.fetchCredentials.isEmpty,
                  "coordinator explicit credential gate runs before probes", failures: &failures)
        } catch {
            failures.append("coordinator credential gate setup: \(error)")
        }

        do {
            let vos = DirectMockModemBackend(kind: .vos5G)
            let coordinator = ModemCoordinator(
                registry: try directRegistry(vos: vos),
                discover: { _, _, _ in
                    ModemDiscoveryReport(topology: .empty, attempts: [])
                }
            )
            do {
                _ = try await coordinator.read(
                    preferences: ModemConnectionPreferences(selection: .vos5G),
                    credentials: ModemConnectionCredentials()
                )
                failures.append("coordinator explicit VOS selection requires credentials")
            } catch let error as ModemBackendError {
                check(error == .credentialsRequired(.ssh),
                      "coordinator reports missing VOS credentials before discovery", failures: &failures)
            }
            let history = await vos.history()
            check(history.identifyCredentials.isEmpty && history.fetchCredentials.isEmpty,
                  "missing VOS credentials start no probes", failures: &failures)
        } catch {
            failures.append("coordinator missing VOS credential setup: \(error)")
        }

        do {
            let vos = DirectMockModemBackend(kind: .vos5G)
            let candidate = ModemDiscoveryCandidate(
                kind: .vos5G,
                endpoint: ScopedEndpoint(
                    baseURL: URL(string: "http://192.168.225.1")!,
                    interfaceName: "en9",
                    interfaceIndex: 19,
                    sourceAddress: "192.168.225.20"
                ),
                sources: [.matchingSubnet],
                priority: ModemDiscoveryCandidateSource.matchingSubnet.rawValue
            )
            let report = ModemDiscoveryReport(
                topology: .empty,
                attempts: [ModemDiscoveryAttempt(
                    candidate: candidate,
                    result: .failed(
                        VOSClientError.authenticationFailed.localizedDescription,
                        category: .authentication,
                        confirmedProduct: false
                    )
                )]
            )
            let coordinator = ModemCoordinator(registry: try directRegistry(vos: vos)) { _, _, _ in report }
            do {
                _ = try await coordinator.read(
                    preferences: ModemConnectionPreferences(selection: .vos5G),
                    credentials: ModemConnectionCredentials([
                        .vos5G: .ssh(SSHCredentials(
                            username: "fixture",
                            password: "rejected-fixture-password"
                        ))
                    ])
                )
                failures.append("coordinator must surface likely-endpoint authentication failure")
            } catch let error as ModemCoordinatorError {
                guard case let .authenticationFailed(kind, messages) = error else {
                    failures.append("coordinator identification failure type: \(error)")
                    return
                }
                check(kind == .vos5G && messages.count == 1 && messages[0].contains("password was rejected"),
                      "coordinator preserves discovery authentication reason", failures: &failures)
                check(ModemFailureClassifier.category(of: error) == .authentication,
                      "coordinator preserves discovery authentication category", failures: &failures)
            }
        } catch {
            failures.append("coordinator discovery failure classification setup: \(error)")
        }

        do {
            let zte = DirectMockModemBackend(
                kind: .zteMC7530CA,
                typedFetchFailure: .zteAuthentication
            )
            let candidate = ModemDiscoveryCandidate(
                kind: .zteMC7530CA,
                endpoint: ScopedEndpoint(
                    baseURL: URL(string: "http://192.168.254.1")!,
                    interfaceName: "en8",
                    interfaceIndex: 18,
                    sourceAddress: "192.168.254.20"
                ),
                sources: [.matchingSubnet],
                priority: ModemDiscoveryCandidateSource.matchingSubnet.rawValue
            )
            let report = ModemDiscoveryReport(
                topology: .empty,
                attempts: [ModemDiscoveryAttempt(
                    candidate: candidate,
                    result: .matched(directIdentity(.zteMC7530CA))
                )]
            )
            let coordinator = ModemCoordinator(registry: try directRegistry(zte: zte)) { _, _, _ in report }
            do {
                _ = try await coordinator.read(
                    preferences: ModemConnectionPreferences(selection: .zteMC7530CA),
                    credentials: ModemConnectionCredentials([
                        .zteMC7530CA: .web(WebCredentials(password: "rejected-fixture-password"))
                    ])
                )
                failures.append("coordinator must preserve ZTE fetch authentication failure")
            } catch let error as ModemCoordinatorError {
                guard case let .authenticationFailed(kind, messages) = error else {
                    failures.append("coordinator ZTE fetch failure type: \(error)")
                    return
                }
                check(kind == .zteMC7530CA && !messages.isEmpty,
                      "coordinator preserves ZTE fetch authentication context", failures: &failures)
                check(ModemFailureClassifier.category(of: error) == .authentication,
                      "coordinator preserves ZTE fetch authentication category", failures: &failures)
            }
        } catch {
            failures.append("coordinator ZTE fetch classification setup: \(error)")
        }

        do {
            let zte = DirectMockModemBackend(kind: .zteMC7530CA)
            let oldEndpoint = ScopedEndpoint(
                baseURL: URL(string: "http://192.168.254.1")!,
                interfaceName: "en8",
                interfaceIndex: 18,
                sourceAddress: "192.168.254.20"
            )
            let manualEndpoint = ScopedEndpoint(
                baseURL: URL(string: "http://192.168.254.99")!,
                interfaceName: "en8",
                interfaceIndex: 18,
                sourceAddress: "192.168.254.20"
            )
            let attempts = [
                ModemDiscoveryAttempt(
                    candidate: ModemDiscoveryCandidate(
                        kind: .zteMC7530CA,
                        endpoint: oldEndpoint,
                        sources: [.lastSuccessful],
                        priority: ModemDiscoveryCandidateSource.lastSuccessful.rawValue
                    ),
                    result: .matched(directIdentity(.zteMC7530CA))
                ),
                ModemDiscoveryAttempt(
                    candidate: ModemDiscoveryCandidate(
                        kind: .zteMC7530CA,
                        endpoint: manualEndpoint,
                        sources: [.manual],
                        priority: ModemDiscoveryCandidateSource.manual.rawValue
                    ),
                    result: .matched(directIdentity(.zteMC7530CA))
                )
            ]
            let coordinator = ModemCoordinator(registry: try directRegistry(zte: zte)) { _, _, _ in
                ModemDiscoveryReport(topology: .empty, attempts: attempts)
            }
            let result = try await coordinator.read(
                preferences: ModemConnectionPreferences(
                    selection: .zteMC7530CA,
                    manualEndpoints: [ModemEndpointPreference(
                        kind: .zteMC7530CA,
                        baseURL: manualEndpoint.baseURL
                    )],
                    lastSuccessfulScopeKey: oldEndpoint.scopeKey,
                    lastSuccessfulEndpoint: ModemEndpointPreference(
                        kind: .zteMC7530CA,
                        baseURL: oldEndpoint.baseURL,
                        interfaceName: oldEndpoint.interfaceName,
                        interfaceIndex: oldEndpoint.interfaceIndex
                    )
                ),
                credentials: ModemConnectionCredentials([
                    .zteMC7530CA: .web(WebCredentials(password: "fixture-web-password"))
                ])
            )
            check(result.activeModem.endpoint == manualEndpoint,
                  "manual endpoint supersedes stale preferred scope", failures: &failures)
        } catch {
            failures.append("coordinator manual endpoint precedence: \(error)")
        }

        do {
            let reader = DirectVOSStatusReader()
            let backend = VOSBackend(client: reader)
            check(!backend.capabilities.contains(.deviceControls),
                  "VOS status-only client does not advertise device controls",
                  failures: &failures)
            let firstEndpoint = ScopedEndpoint(
                baseURL: URL(string: "http://192.168.225.1")!,
                interfaceName: "en9",
                interfaceIndex: 19,
                sourceAddress: "192.168.225.20"
            )
            let secondEndpoint = ScopedEndpoint(
                baseURL: URL(string: "http://192.168.225.1")!,
                interfaceName: "en10",
                interfaceIndex: 20,
                sourceAddress: "192.168.225.30"
            )
            let rejected: ModemCredentials = .ssh(SSHCredentials(
                username: "fixture",
                password: "rejected-fixture-password"
            ))
            for endpoint in [firstEndpoint, secondEndpoint] {
                do {
                    _ = try await backend.identify(endpoint: endpoint, credentials: rejected)
                    failures.append("VOS rejected credentials must stay gated across endpoints")
                } catch let error as VOSClientError {
                    check(error == .authenticationFailed,
                          "VOS rejected credential error", failures: &failures)
                }
            }
            let rejectedCallCount = await reader.callCount()
            check(rejectedCallCount == 1,
                  "VOS backend sends rejected credentials only once", failures: &failures)
            let identity = try await backend.identify(
                endpoint: secondEndpoint,
                credentials: .ssh(SSHCredentials(
                    username: "fixture",
                    password: "changed-fixture-password"
                ))
            )
            let changedCallCount = await reader.callCount()
            check(identity?.kind == .vos5G && changedCallCount == 2,
                  "VOS credential change reopens authentication", failures: &failures)
        } catch {
            failures.append("VOS backend credential gate: \(error)")
        }

        do {
            let http = DirectScriptedZTEHTTPTransport(responses: [])
            let standard = try ModemBackendRegistry.standard(
                vosClient: VOSClient(),
                zteHTTPTransport: http
            )
            check(standard.registration(for: .zteMC7530CA)?.identificationCredentials == .configuredOrAnonymous(.web),
                  "standard registry ZTE preflight identity policy", failures: &failures)
            check(standard.registration(for: .zteMC7530CA)?.statusCredentials == .configured(.web),
                  "standard registry ZTE web status policy", failures: &failures)
            check(standard.registration(for: .vos5G)?.identificationCredentials == .configured(.ssh),
                  "standard registry VOS SSH identity policy", failures: &failures)
        } catch {
            failures.append("standard backend registry: \(error)")
        }

        do {
            let openGate = DirectAsyncGate()
            let backend = DirectCoordinatorControlBackend(openGate: openGate)
            let endpoint = ScopedEndpoint(
                baseURL: URL(string: "http://192.168.254.1")!,
                interfaceName: "en8",
                interfaceIndex: 18,
                sourceAddress: "192.168.254.20"
            )
            let report = ModemDiscoveryReport(
                topology: .empty,
                attempts: [ModemDiscoveryAttempt(
                    candidate: ModemDiscoveryCandidate(
                        kind: .zteMC7530CA,
                        endpoint: endpoint,
                        sources: [.knownDefault],
                        priority: ModemDiscoveryCandidateSource.knownDefault.rawValue
                    ),
                    result: .matched(directIdentity(.zteMC7530CA))
                )]
            )
            let coordinator = ModemCoordinator(
                registry: try directControlRegistry(backend: backend)
            ) { _, _, _ in report }
            let credentials = ModemConnectionCredentials([
                .zteMC7530CA: .web(WebCredentials(password: "fixture-web-password"))
            ])
            _ = try await coordinator.read(
                preferences: ModemConnectionPreferences(selection: .zteMC7530CA),
                credentials: credentials
            )

            let firstOpen = Task {
                try await coordinator.controlSession(credentials: credentials)
            }
            let secondOpen = Task {
                try await coordinator.controlSession(credentials: credentials)
            }
            await openGate.waitForArrivals(2)
            await openGate.releaseAll()
            let first = try await firstOpen.value
            let second = try await secondOpen.value
            guard let firstSession = first as? DirectCoordinatorControlSession,
                  let secondSession = second as? DirectCoordinatorControlSession
            else {
                failures.append("coordinator concurrent control open returns fixture sessions")
                return
            }
            check(firstSession.instanceID == secondSession.instanceID,
                  "coordinator concurrent same-key opens return one cached session",
                  failures: &failures)
            let created = await backend.controlSessions()
            var liveSessionIDs: [Int] = []
            for session in created where !(await session.isInvalidated()) {
                liveSessionIDs.append(session.instanceID)
            }
            check(created.count == 2 && liveSessionIDs == [firstSession.instanceID],
                  "coordinator concurrent same-key open retires the losing session",
                  failures: &failures)
        } catch {
            failures.append("coordinator concurrent control-session cache: \(error)")
        }

        do {
            let fetchGate = DirectAsyncGate()
            let backend = DirectCoordinatorControlBackend(
                fetchGate: fetchGate,
                gatedFetchCall: 2
            )
            let endpoint = ScopedEndpoint(
                baseURL: URL(string: "http://192.168.254.1")!,
                interfaceName: "en8",
                interfaceIndex: 18,
                sourceAddress: "192.168.254.20"
            )
            let report = ModemDiscoveryReport(
                topology: .empty,
                attempts: [ModemDiscoveryAttempt(
                    candidate: ModemDiscoveryCandidate(
                        kind: .zteMC7530CA,
                        endpoint: endpoint,
                        sources: [.knownDefault],
                        priority: ModemDiscoveryCandidateSource.knownDefault.rawValue
                    ),
                    result: .matched(directIdentity(.zteMC7530CA))
                )]
            )
            let coordinator = ModemCoordinator(
                registry: try directControlRegistry(backend: backend)
            ) { _, _, _ in report }
            let credentials = ModemConnectionCredentials([
                .zteMC7530CA: .web(WebCredentials(password: "fixture-web-password"))
            ])
            let preferences = ModemConnectionPreferences(selection: .zteMC7530CA)
            _ = try await coordinator.read(preferences: preferences, credentials: credentials)

            let staleRead = Task {
                try await coordinator.read(preferences: preferences, credentials: credentials)
            }
            await fetchGate.waitForArrivals(1)
            await coordinator.invalidateActiveModem()
            await fetchGate.releaseAll()
            do {
                _ = try await staleRead.value
                failures.append("coordinator invalidated read must not commit")
            } catch let error as ModemControlError {
                check(error == .deviceChanged,
                      "coordinator invalidated read reports generation change",
                      failures: &failures)
            }
            let activeAfterInvalidation = await coordinator.currentActiveModem()
            check(activeAfterInvalidation == nil,
                  "coordinator invalidated read leaves no active modem",
                  failures: &failures)
        } catch {
            failures.append("coordinator read/invalidate generation race: \(error)")
        }
    }

    private static func fixture(_ relativePath: String) throws -> Data {
        guard let root = ProcessInfo.processInfo.environment["SIGNAL_STATUS_TEST_FIXTURES"] else {
            throw DirectTestSupportError.missingFixtureRoot
        }
        return try Data(contentsOf: URL(fileURLWithPath: root, isDirectory: true)
            .appendingPathComponent(relativePath))
    }

    private static func zteResponse(_ json: String) -> ZTEHTTPResponse {
        ZTEHTTPResponse(statusCode: 200, headers: [:], body: Data(json.utf8))
    }

    private static func zteCallResponse(_ payloadObjectJSON: String) -> ZTEHTTPResponse {
        zteResponse("[{\"jsonrpc\":\"2.0\",\"id\":3,\"result\":[0,\(payloadObjectJSON)]}]")
    }

    private static func zteStatusResponse(_ status: Int) -> ZTEHTTPResponse {
        zteResponse("[{\"jsonrpc\":\"2.0\",\"id\":3,\"result\":[\(status)]}]")
    }

    private static func directDiscoveryInterface(
        name: String,
        index: UInt32,
        address: String,
        prefixLength: UInt8,
        router: String?,
        isPrimary: Bool = false,
        kind: NetworkInterfaceKind = .physical
    ) -> NetworkInterfaceSnapshot {
        NetworkInterfaceSnapshot(
            name: name,
            index: index,
            serviceID: "fixture-\(name)",
            kind: kind,
            isUp: true,
            isRunning: true,
            isPrimary: isPrimary,
            addresses: [IPv4InterfaceAddress(
                address: IPv4HostAddress(string: address)!,
                prefixLength: prefixLength
            )],
            router: router.flatMap(IPv4HostAddress.init(string:))
        )
    }

    private static func directRegistry(
        zte: DirectMockModemBackend? = nil,
        vos: DirectMockModemBackend? = nil
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

    private static func directControlRegistry(
        backend: DirectCoordinatorControlBackend
    ) throws -> ModemBackendRegistry {
        try ModemBackendRegistry(registrations: [ModemBackendRegistration(
            backend: backend,
            discoveryProfile: ModemDiscoveryProfile(
                kind: .zteMC7530CA,
                defaultBaseURLs: [URL(string: "http://192.168.254.1")!]
            ),
            identificationCredentials: .anonymous,
            statusCredentials: .configured(.web)
        )])
    }

    private static func data(_ hex: String) -> Data {
        try! QMIParser.data(fromHex: hex)
    }

    private static func le16(_ value: UInt16) -> Data {
        Data([UInt8(truncatingIfNeeded: value), UInt8(truncatingIfNeeded: value >> 8)])
    }

    private static func le32(_ value: UInt32) -> Data {
        Data([
            UInt8(truncatingIfNeeded: value),
            UInt8(truncatingIfNeeded: value >> 8),
            UInt8(truncatingIfNeeded: value >> 16),
            UInt8(truncatingIfNeeded: value >> 24)
        ])
    }

    private static func lteLocationCell(
        pci: UInt16,
        rsrqTenths: Int16,
        rsrpTenths: Int16,
        rssiTenths: Int16
    ) -> Data {
        var value = le16(pci)
        value.append(le16(UInt16(bitPattern: rsrqTenths)))
        value.append(le16(UInt16(bitPattern: rsrpTenths)))
        value.append(le16(UInt16(bitPattern: rssiTenths)))
        value.append(le16(0))
        return value
    }

    private static func qmiResponse(
        message: UInt16,
        transaction: UInt16 = 1,
        tlvs: [(UInt8, Data)] = [],
        resultStatus: UInt16 = 0,
        resultError: UInt16 = 0
    ) -> Data {
        var result = le16(resultStatus)
        result.append(le16(resultError))
        var payload = tlv(0x02, result)
        for (type, value) in tlvs { payload.append(tlv(type, value)) }

        var response = Data([0x02])
        response.append(le16(transaction))
        response.append(le16(message))
        response.append(le16(UInt16(payload.count)))
        response.append(payload)
        return response
    }

    private static func qmiRequest(
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

    private static func tlv(_ type: UInt8, _ value: Data) -> Data {
        var result = Data([type])
        result.append(le16(UInt16(value.count)))
        result.append(value)
        return result
    }

    private static func check(_ condition: @autoclosure () throws -> Bool, _ name: String, failures: inout [String]) {
        do {
            if try !condition() { failures.append(name) }
        } catch {
            failures.append("\(name): \(error)")
        }
    }

    private static func checkThrows(_ name: String, failures: inout [String], operation: () throws -> Void) {
        do {
            try operation()
            failures.append(name)
        } catch {}
    }

    private static func checkNRPlanError(
        _ expected: NRBandLockPlanError,
        _ name: String,
        failures: inout [String],
        operation: () throws -> Void
    ) {
        do {
            try operation()
            failures.append(name)
        } catch let error as NRBandLockPlanError {
            if error != expected { failures.append("\(name): \(error)") }
        } catch {
            failures.append("\(name): \(error)")
        }
    }
}

private enum DirectTestSupportError: Error {
    case missingFixtureRoot
    case missingScriptedResponse
    case plannedSnapshotFailure
    case plannedCredentialFailure
}

/// Deterministic suspension point for actor-reentrancy tests. Tests first wait
/// until the expected number of operations have arrived, then open the gate.
private actor DirectAsyncGate {
    private struct ArrivalWaiter {
        let target: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private var arrivalCount = 0
    private var isReleased = false
    private var blocked: [CheckedContinuation<Void, Never>] = []
    private var arrivalWaiters: [ArrivalWaiter] = []

    func arriveAndWait() async {
        arrivalCount += 1
        let ready = arrivalWaiters.filter { arrivalCount >= $0.target }
        arrivalWaiters.removeAll { arrivalCount >= $0.target }
        for waiter in ready { waiter.continuation.resume() }
        guard !isReleased else { return }
        await withCheckedContinuation { continuation in
            blocked.append(continuation)
        }
    }

    func waitForArrivals(_ target: Int) async {
        guard arrivalCount < target else { return }
        await withCheckedContinuation { continuation in
            arrivalWaiters.append(ArrivalWaiter(
                target: target,
                continuation: continuation
            ))
        }
    }

    func releaseAll() {
        isReleased = true
        let continuations = blocked
        blocked.removeAll()
        for continuation in continuations { continuation.resume() }
    }
}

private actor DirectCoordinatorControlSession: ModemControlSession {
    nonisolated let instanceID: Int
    nonisolated let kind: ModemKind = .zteMC7530CA
    nonisolated let capabilities: ModemCapability = [.operatorSelection]
    nonisolated let stableIdentifier = directIdentity(.zteMC7530CA).stableIdentifier!

    private var invalidated = false

    init(instanceID: Int) {
        self.instanceID = instanceID
    }

    func invalidate() async {
        invalidated = true
    }

    func refresh() async throws -> ModemControlState {
        guard !invalidated else { throw ModemControlError.deviceChanged }
        return ModemControlState(
            operatorSelection: nil,
            architecture: .automatic,
            saBands: [],
            nsaBands: [],
            lteBands: [],
            canRestoreDefaults: true,
            preferenceLifetime: .persistent
        )
    }

    func perform(_ command: ModemControlCommand) async throws -> ModemControlResult {
        guard !invalidated else { throw ModemControlError.deviceChanged }
        return ModemControlResult(state: try await refresh())
    }

    func isInvalidated() -> Bool { invalidated }
}

private actor DirectCoordinatorControlBackend: ModemControlBackend {
    nonisolated let kind: ModemKind = .zteMC7530CA
    nonisolated let capabilities: ModemCapability = [
        .identityRead,
        .statusRead,
        .operatorSelection
    ]

    private let identity = directIdentity(.zteMC7530CA)
    private let openGate: DirectAsyncGate?
    private let fetchGate: DirectAsyncGate?
    private let gatedFetchCall: Int?
    private var fetchCallCount = 0
    private var sessions: [DirectCoordinatorControlSession] = []

    init(
        openGate: DirectAsyncGate? = nil,
        fetchGate: DirectAsyncGate? = nil,
        gatedFetchCall: Int? = nil
    ) {
        self.openGate = openGate
        self.fetchGate = fetchGate
        self.gatedFetchCall = gatedFetchCall
    }

    func identify(
        endpoint: ScopedEndpoint,
        credentials: ModemCredentials
    ) async throws -> ModemIdentity? {
        identity
    }

    func fetchSnapshot(
        endpoint: ScopedEndpoint,
        credentials: ModemCredentials
    ) async throws -> DeviceSnapshot {
        fetchCallCount += 1
        if fetchCallCount == gatedFetchCall, let fetchGate {
            await fetchGate.arriveAndWait()
        }
        var snapshot = DeviceSnapshot.empty
        snapshot.host = endpoint.host ?? "fixture"
        snapshot.interfaceName = endpoint.interfaceName
        return snapshot
    }

    func openControlSession(
        endpoint: ScopedEndpoint,
        credentials: ModemCredentials
    ) async throws -> any ModemControlSession {
        let session = DirectCoordinatorControlSession(instanceID: sessions.count + 1)
        sessions.append(session)
        if let openGate { await openGate.arriveAndWait() }
        return session
    }

    func controlSessions() -> [DirectCoordinatorControlSession] { sessions }
}

private struct DirectMisleadingAuthenticationError: LocalizedError {
    var errorDescription: String? {
        "A password or credential was rejected and requires attention."
    }
}

private final class DirectCredentialStore: CredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String]
    private let failingSetAccount: String?
    private let failingSetPasswordPrefix: String
    private let failsReads: Bool
    private var numberOfSetCalls = 0

    init(
        values: [String: String],
        failingSetAccount: String? = nil,
        failingSetPasswordPrefix: String = "new-",
        failsReads: Bool = false
    ) {
        self.values = values
        self.failingSetAccount = failingSetAccount
        self.failingSetPasswordPrefix = failingSetPasswordPrefix
        self.failsReads = failsReads
    }

    func password(for account: String) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        if failsReads { throw DirectTestSupportError.plannedCredentialFailure }
        return values[account]
    }

    func setPassword(_ password: String, for account: String) throws {
        lock.lock()
        defer { lock.unlock() }
        numberOfSetCalls += 1
        if account == failingSetAccount, password.hasPrefix(failingSetPasswordPrefix) {
            throw DirectTestSupportError.plannedCredentialFailure
        }
        if password.isEmpty {
            values.removeValue(forKey: account)
        } else {
            values[account] = password
        }
    }

    func removePassword(for account: String) throws {
        lock.lock()
        defer { lock.unlock() }
        values.removeValue(forKey: account)
    }

    func snapshot() -> [String: String] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }

    func setCallCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return numberOfSetCalls
    }
}

private struct DirectZTERequestRecord: Sendable {
    let httpMethod: String
    let urlPath: String
    let headers: [String: String]
    let bodyText: String
    let route: ZTEHTTPRoute
    let rpcMethod: String?
    let sessionID: String?
    let object: String?
    let ubusMethod: String?
    let parameters: [String: String]
    let loginUsername: String?
    let loginPassword: String?

    func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

private actor DirectScriptedZTEHTTPTransport: ZTEHTTPTransport {
    private let responses: [ZTEHTTPResponse]
    private var nextResponse = 0
    private var requestRecords: [DirectZTERequestRecord] = []

    init(responses: [ZTEHTTPResponse]) {
        self.responses = responses
    }

    func send(_ request: URLRequest, route: ZTEHTTPRoute) async throws -> ZTEHTTPResponse {
        requestRecords.append(Self.record(request, route: route))
        guard nextResponse < responses.count else {
            throw DirectTestSupportError.missingScriptedResponse
        }
        defer { nextResponse += 1 }
        return responses[nextResponse]
    }

    func records() -> [DirectZTERequestRecord] { requestRecords }
    func requestCount() -> Int { requestRecords.count }

    private static func record(_ request: URLRequest, route: ZTEHTTPRoute) -> DirectZTERequestRecord {
        let body = request.httpBody ?? Data()
        let bodyText = String(decoding: body, as: UTF8.self)
        let batch = (try? JSONSerialization.jsonObject(with: body)) as? [[String: Any]]
        let rpc = batch?.first
        let params = rpc?["params"] as? [Any]
        let callParameters = params.flatMap { $0.count > 3 ? $0[3] as? [String: Any] : nil }
        return DirectZTERequestRecord(
            httpMethod: request.httpMethod ?? "",
            urlPath: request.url?.path ?? "",
            headers: request.allHTTPHeaderFields ?? [:],
            bodyText: bodyText,
            route: route,
            rpcMethod: rpc?["method"] as? String,
            sessionID: params?.first as? String,
            object: params.flatMap { $0.count > 1 ? $0[1] as? String : nil },
            ubusMethod: params.flatMap { $0.count > 2 ? $0[2] as? String : nil },
            parameters: callParameters?.reduce(into: [:]) { result, pair in
                if let value = pair.value as? String { result[pair.key] = value }
            } ?? [:],
            loginUsername: callParameters?["username"] as? String,
            loginPassword: callParameters?["password"] as? String
        )
    }
}

private struct DirectMC7530FixtureState: Equatable, Sendable {
    var netSelect: String
    var netSelectMode: String
    var operatorName: String
    var mcc: String
    var mnc: String
    var networkType: String
    var lteBands: Set<Int>
    var saBands: Set<Int>
    var nsaBands: Set<Int>
    var nrdcBands: Set<Int>
    var gwBandLock: String
    var lteCellLock: String
    var nrCellLock: String

    static let baseline = DirectMC7530FixtureState(
        netSelect: "LTE_AND_5G",
        netSelectMode: "auto_select",
        operatorName: "Fixture Carrier",
        mcc: "001",
        mnc: "01",
        networkType: "ENDC",
        lteBands: Set([2, 4, 66]),
        saBands: Set([5, 77]),
        nsaBands: Set([2, 66, 77]),
        nrdcBands: MC7530ControlSession.defaultNRDCBands,
        gwBandLock: "0x006800000",
        lteCellLock: "",
        nrCellLock: ""
    )
}

/// Stateful retail-UBus fixture. Setter responses always return success; the
/// optional ignored-application counters model firmware that accepts a call
/// but fails to change authoritative `nwinfo_get_netinfo` readback.
private actor DirectStatefulMC7530HTTPTransport: ZTEHTTPTransport {
    private var state: DirectMC7530FixtureState
    private var scanStatuses: [String]
    private let scanContents: String
    private var registrationResults: [String]
    private var pendingManualPLMN: String?
    private var pendingManualRAT: String?
    private var ignoredLTEWriteApplications: Int
    private var collateralGWChangesAfterLTEApplications: Int
    private var lostLTEResponsesAfterApplications: Int
    private var suspendedLTEResponsesAfterApplications: Int
    private var ignoredNRWriteApplications: [String: Int]
    private var ignoredNetSelectWriteApplications: Int
    private var lostResetResponsesAfterApplications: Int
    private let fingerprintSequence: [String]
    private let emitNumericPLMNComponents: Bool
    private var fingerprintIndex = 0
    private var requestRecords: [DirectZTERequestRecord] = []

    init(
        state: DirectMC7530FixtureState,
        scanStatuses: [String] = ["manual_complete"],
        scanContents: String = "2,Fixture Carrier,00101,13;",
        registrationResults: [String] = ["manual_success"],
        ignoredLTEWriteApplications: Int = 0,
        collateralGWChangesAfterLTEApplications: Int = 0,
        lostLTEResponsesAfterApplications: Int = 0,
        suspendedLTEResponsesAfterApplications: Int = 0,
        ignoredNRWriteApplications: [String: Int] = [:],
        ignoredNetSelectWriteApplications: Int = 0,
        lostResetResponsesAfterApplications: Int = 0,
        fingerprintSequence: [String] = ["fixture-device-alpha"],
        emitNumericPLMNComponents: Bool = false
    ) {
        self.state = state
        self.scanStatuses = scanStatuses
        self.scanContents = scanContents
        self.registrationResults = registrationResults
        self.ignoredLTEWriteApplications = ignoredLTEWriteApplications
        self.collateralGWChangesAfterLTEApplications = collateralGWChangesAfterLTEApplications
        self.lostLTEResponsesAfterApplications = lostLTEResponsesAfterApplications
        self.suspendedLTEResponsesAfterApplications = suspendedLTEResponsesAfterApplications
        self.ignoredNRWriteApplications = ignoredNRWriteApplications
        self.ignoredNetSelectWriteApplications = ignoredNetSelectWriteApplications
        self.lostResetResponsesAfterApplications = lostResetResponsesAfterApplications
        self.fingerprintSequence = fingerprintSequence.isEmpty
            ? ["fixture-device-alpha"] : fingerprintSequence
        self.emitNumericPLMNComponents = emitNumericPLMNComponents
    }

    func send(_ request: URLRequest, route: ZTEHTTPRoute) async throws -> ZTEHTTPResponse {
        let record = try Self.record(request, route: route)
        requestRecords.append(record)

        switch record.ubusMethod {
        case "web_login_info":
            return try Self.response(["zte_web_sault": "fixture-salt"])
        case "web_login":
            return try Self.response(["result": "0", "ubus_rpc_session": "fixture-session"])
        case "get_modem_msn":
            let index = min(fingerprintIndex, fingerprintSequence.count - 1)
            let value = fingerprintSequence[index]
            fingerprintIndex += 1
            return try Self.response(["modem_msn": value])
        case "nwinfo_get_netinfo":
            return try Self.response(netinfoObject())
        case "nwinfo_manual_scan":
            return try Self.successResponse()
        case "nwinfo_m_netselect_status":
            let value = scanStatuses.isEmpty ? "manual_complete" : scanStatuses.removeFirst()
            return try Self.response(["m_netselect_status": value])
        case "nwinfo_m_netselect_contents":
            return try Self.response(["m_netselect_contents": scanContents])
        case "nwinfo_manual_register":
            pendingManualPLMN = record.parameters["m_mcc_mnc"]
            pendingManualRAT = record.parameters["m_rat"]
            return try Self.successResponse()
        case "nwinfo_m_netselect_result":
            let value = registrationResults.isEmpty ? "manual_success" : registrationResults.removeFirst()
            if value == "manual_success" { applyPendingManualRegistration() }
            return try Self.response(["m_netselect_result": value])
        case "nwinfo_set_netselect":
            if ignoredNetSelectWriteApplications > 0 {
                ignoredNetSelectWriteApplications -= 1
            } else if let token = record.parameters["net_select"] {
                state.netSelect = token
                state.netSelectMode = "auto_select"
            }
            return try Self.successResponse()
        case "nwinfo_set_lte_ext_band":
            if ignoredLTEWriteApplications > 0 {
                ignoredLTEWriteApplications -= 1
            } else if let value = record.parameters["lte_band"] {
                state.lteBands = Self.parseBands(value)
                if collateralGWChangesAfterLTEApplications > 0 {
                    collateralGWChangesAfterLTEApplications -= 1
                    state.gwBandLock = "0xDEADBEEF"
                }
                if lostLTEResponsesAfterApplications > 0 {
                    lostLTEResponsesAfterApplications -= 1
                    throw URLError(.timedOut)
                }
                if suspendedLTEResponsesAfterApplications > 0 {
                    suspendedLTEResponsesAfterApplications -= 1
                    try await Task.sleep(nanoseconds: 10_000_000_000)
                }
            }
            return try Self.successResponse()
        case "nwinfo_set_nrbandlock":
            guard let value = record.parameters["nr5g_band"],
                  let type = record.parameters["nr5g_type"]
            else { throw DirectTestSupportError.missingScriptedResponse }
            if ignoredNRWriteApplications[type, default: 0] > 0 {
                ignoredNRWriteApplications[type, default: 0] -= 1
            } else {
                if type == "0" { state.saBands = Self.parseBands(value) }
                if type == "1" { state.nsaBands = Self.parseBands(value) }
            }
            return try Self.successResponse()
        case "nwinfo_set_gwl_bandlock":
            guard record.parameters["is_gw_band"] == "1",
                  record.parameters["is_lte_band"] == "0",
                  let value = record.parameters["gw_band_mask"]
            else { throw DirectTestSupportError.missingScriptedResponse }
            state.gwBandLock = value
            return try Self.successResponse()
        case "nwinfo_reset_band_cell_setting":
            state.lteBands = MC7530ControlSession.defaultLTEBands
            state.saBands = MC7530ControlSession.defaultNRBands
            state.nsaBands = MC7530ControlSession.defaultNRBands
            state.gwBandLock = "0x006800000"
            state.lteCellLock = ""
            state.nrCellLock = ""
            if lostResetResponsesAfterApplications > 0 {
                lostResetResponsesAfterApplications -= 1
                throw URLError(.timedOut)
            }
            return try Self.successResponse()
        case "nwinfo_lock_lte_cell":
            guard let pci = record.parameters["lock_lte_pci"],
                  let earfcn = record.parameters["lock_lte_earfcn"]
            else { throw DirectTestSupportError.missingScriptedResponse }
            state.lteCellLock = "\(pci),\(earfcn)"
            return try Self.successResponse()
        case "nwinfo_lock_nr_cell":
            guard let pci = record.parameters["lock_nr_pci"],
                  let earfcn = record.parameters["lock_nr_earfcn"],
                  let band = record.parameters["lock_nr_cell_band"]
            else { throw DirectTestSupportError.missingScriptedResponse }
            state.nrCellLock = "\(pci),\(earfcn),\(band)"
            return try Self.successResponse()
        default:
            throw DirectTestSupportError.missingScriptedResponse
        }
    }

    func records() -> [DirectZTERequestRecord] { requestRecords }
    func currentState() -> DirectMC7530FixtureState { state }

    private func netinfoObject() -> [String: Any] {
        [
            "net_select": state.netSelect,
            "net_select_mode": state.netSelectMode,
            "network_provider_fullname": state.operatorName,
            "rmcc": emitNumericPLMNComponents ? (Int(state.mcc) ?? -1) : state.mcc,
            "rmnc": emitNumericPLMNComponents ? (Int(state.mnc) ?? -1) : state.mnc,
            "network_type": state.networkType,
            "lte_band": Self.bandCSV(state.lteBands),
            "nr5g_sa_band_lock": Self.bandCSV(state.saBands),
            "nr5g_nsa_band_lock": Self.bandCSV(state.nsaBands),
            "nr5g_nrdc_band_lock": Self.bandCSV(state.nrdcBands),
            "gw_band_lock": state.gwBandLock,
            "lock_lte_cell": state.lteCellLock,
            "lock_nr_cell": state.nrCellLock
        ]
    }

    private func applyPendingManualRegistration() {
        if let plmn = pendingManualPLMN, plmn.count >= 5 {
            state.mcc = String(plmn.prefix(3))
            state.mnc = String(plmn.dropFirst(3))
        }
        switch pendingManualRAT {
        case "13": state.networkType = "ENDC"
        case "9", "11", "12": state.networkType = "NR5G SA"
        case "14": state.networkType = "LTE 5GC"
        case "7": state.networkType = "LTE"
        case "2": state.networkType = "WCDMA"
        case "0": state.networkType = "GSM"
        default: break
        }
        state.netSelectMode = "manual_select"
    }

    private static func parseBands(_ value: String) -> Set<Int> {
        Set(value.split(separator: ",").compactMap { Int($0) })
    }

    private static func bandCSV(_ values: Set<Int>) -> String {
        values.sorted().map(String.init).joined(separator: ",")
    }

    private static func successResponse() throws -> ZTEHTTPResponse {
        let json: [[String: Any]] = [[
            "jsonrpc": "2.0",
            "id": 3,
            "result": [0]
        ]]
        return ZTEHTTPResponse(
            statusCode: 200,
            headers: [:],
            body: try JSONSerialization.data(withJSONObject: json)
        )
    }

    private static func response(_ payload: [String: Any]) throws -> ZTEHTTPResponse {
        let json: [[String: Any]] = [[
            "jsonrpc": "2.0",
            "id": 3,
            "result": [0, payload]
        ]]
        return ZTEHTTPResponse(
            statusCode: 200,
            headers: [:],
            body: try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        )
    }

    private static func record(
        _ request: URLRequest,
        route: ZTEHTTPRoute
    ) throws -> DirectZTERequestRecord {
        let body = request.httpBody ?? Data()
        guard let batch = try JSONSerialization.jsonObject(with: body) as? [[String: Any]],
              let rpc = batch.first,
              let params = rpc["params"] as? [Any]
        else { throw DirectTestSupportError.missingScriptedResponse }
        let callParameters = params.count > 3 ? params[3] as? [String: Any] : nil
        let strings = callParameters?.reduce(into: [String: String]()) { result, pair in
            if let value = pair.value as? String { result[pair.key] = value }
        } ?? [:]
        return DirectZTERequestRecord(
            httpMethod: request.httpMethod ?? "",
            urlPath: request.url?.path ?? "",
            headers: request.allHTTPHeaderFields ?? [:],
            bodyText: String(decoding: body, as: UTF8.self),
            route: route,
            rpcMethod: rpc["method"] as? String,
            sessionID: params.first as? String,
            object: params.count > 1 ? params[1] as? String : nil,
            ubusMethod: params.count > 2 ? params[2] as? String : nil,
            parameters: strings,
            loginUsername: callParameters?["username"] as? String,
            loginPassword: callParameters?["password"] as? String
        )
    }
}

private struct DirectBackendHistory: Sendable {
    let identifyCredentials: [ModemCredentials]
    let fetchCredentials: [ModemCredentials]
    let identifyScopeKeys: [String]
    let fetchScopeKeys: [String]
}

private enum DirectMockTypedFetchFailure: Sendable {
    case zteAuthentication
}

private actor DirectMockModemBackend: ModemStatusBackend {
    nonisolated let kind: ModemKind
    nonisolated let capabilities: ModemCapability = [.identityRead, .statusRead]

    private let identity: ModemIdentity?
    private var fetchFailures: [Bool]
    private let typedFetchFailure: DirectMockTypedFetchFailure?
    private var identifyCredentials: [ModemCredentials] = []
    private var fetchCredentials: [ModemCredentials] = []
    private var identifyScopeKeys: [String] = []
    private var fetchScopeKeys: [String] = []

    init(
        kind: ModemKind,
        fetchFailures: [Bool] = [],
        typedFetchFailure: DirectMockTypedFetchFailure? = nil,
        identifies: Bool = true
    ) {
        self.kind = kind
        self.fetchFailures = fetchFailures
        self.typedFetchFailure = typedFetchFailure
        self.identity = identifies ? directIdentity(kind) : nil
    }

    func identify(
        endpoint: ScopedEndpoint,
        credentials: ModemCredentials
    ) async throws -> ModemIdentity? {
        identifyCredentials.append(credentials)
        identifyScopeKeys.append(endpoint.scopeKey)
        return identity
    }

    func fetchSnapshot(
        endpoint: ScopedEndpoint,
        credentials: ModemCredentials
    ) async throws -> DeviceSnapshot {
        fetchCredentials.append(credentials)
        fetchScopeKeys.append(endpoint.scopeKey)
        if let typedFetchFailure {
            switch typedFetchFailure {
            case .zteAuthentication:
                throw ZTEUBusError.authenticationFailed
            }
        }
        if !fetchFailures.isEmpty, fetchFailures.removeFirst() {
            throw DirectTestSupportError.plannedSnapshotFailure
        }
        var snapshot = DeviceSnapshot.empty
        snapshot.host = endpoint.host ?? "fixture"
        snapshot.interfaceName = endpoint.interfaceName
        return snapshot
    }

    func history() -> DirectBackendHistory {
        DirectBackendHistory(
            identifyCredentials: identifyCredentials,
            fetchCredentials: fetchCredentials,
            identifyScopeKeys: identifyScopeKeys,
            fetchScopeKeys: fetchScopeKeys
        )
    }
}

private actor DirectVOSControlTransport: VOSControlTransport {
    static let baselinePreferences = NRSystemSelectionPreferences(
        modePreference: 0x0050,
        saBands: NRBandMask(bands: [77, 78])!,
        nsaBands: NRBandMask(bands: [66, 77, 78])!,
        lteBands: LTEBandMask(bands: [2, 4, 66])!
    )

    private var selection = OperatorSelection(
        mode: .automatic,
        operatorName: "Fixture Carrier",
        plmn: "00101",
        accessTechnology: .lteNRDualConnectivity
    )
    private var preferences = baselinePreferences
    private var suspendManualSelectionOnce: Bool
    private var suspendAutomaticSelectionOnce: Bool
    private var suspendScanOnce: Bool
    private var automaticFailures: Int
    private var scanFailures: Int
    private var manualWrites = 0
    private var automaticWrites = 0
    private var preferenceWrites = 0
    private var scanCalls = 0
    private var scanArchitectures: [NRArchitectureMode] = []
    private var preferenceHistory: [NRSystemSelectionPreferences] = []

    init(
        suspendManualSelectionOnce: Bool = false,
        suspendAutomaticSelectionOnce: Bool = false,
        automaticFailures: Int = 0,
        suspendScanOnce: Bool = false,
        scanFailures: Int = 0
    ) {
        self.suspendManualSelectionOnce = suspendManualSelectionOnce
        self.suspendAutomaticSelectionOnce = suspendAutomaticSelectionOnce
        self.automaticFailures = automaticFailures
        self.suspendScanOnce = suspendScanOnce
        self.scanFailures = scanFailures
    }

    func fetchDeviceFingerprint(configuration: DeviceConfiguration) async throws -> String {
        "fixture-vos-control-device"
    }

    func fetchOperatorSelection(
        configuration: DeviceConfiguration
    ) async throws -> OperatorSelection {
        selection
    }

    func scanNetworks(configuration: DeviceConfiguration) async throws -> [CellularNetwork] {
        scanCalls += 1
        scanArchitectures.append(preferences.architectureMode)
        if suspendScanOnce {
            suspendScanOnce = false
            try await Task.sleep(nanoseconds: 10_000_000_000)
        }
        if scanFailures > 0 {
            scanFailures -= 1
            throw DirectTestSupportError.plannedSnapshotFailure
        }
        return [CellularNetwork(
            longName: "Fixture Carrier",
            shortName: "Fixture",
            plmn: "00101",
            availability: .available,
            accessTechnologies: [.lte]
        )]
    }

    func selectNetwork(
        plmn: String,
        configuration: DeviceConfiguration
    ) async throws -> OperatorSelection {
        manualWrites += 1
        selection = OperatorSelection(
            mode: .manual,
            operatorName: "Fixture Carrier",
            plmn: plmn,
            accessTechnology: .lte
        )
        if suspendManualSelectionOnce {
            suspendManualSelectionOnce = false
            try await Task.sleep(nanoseconds: 10_000_000_000)
        }
        return selection
    }

    func selectAutomaticNetwork(
        configuration: DeviceConfiguration
    ) async throws -> OperatorSelection {
        automaticWrites += 1
        selection = OperatorSelection(
            mode: .automatic,
            operatorName: "Fixture Carrier",
            plmn: "00101",
            accessTechnology: .lteNRDualConnectivity
        )
        if suspendAutomaticSelectionOnce {
            suspendAutomaticSelectionOnce = false
            try await Task.sleep(nanoseconds: 10_000_000_000)
        }
        if automaticFailures > 0 {
            automaticFailures -= 1
            throw DirectTestSupportError.plannedSnapshotFailure
        }
        return selection
    }

    func fetchNRSystemSelectionPreferences(
        configuration: DeviceConfiguration
    ) async throws -> NRSystemSelectionPreferences {
        preferences
    }

    func setNRSystemSelectionPreferences(
        modePreference: UInt16,
        saBands: NRBandMask,
        nsaBands: NRBandMask,
        lteBands: LTEBandMask?,
        configuration: DeviceConfiguration
    ) async throws -> NRSystemSelectionPreferences {
        preferenceWrites += 1
        let updated = NRSystemSelectionPreferences(
            modePreference: modePreference,
            saBands: saBands,
            nsaBands: nsaBands,
            lteBands: lteBands
        )
        preferences = updated
        preferenceHistory.append(updated)
        return preferences
    }

    func seedPreferences(_ value: NRSystemSelectionPreferences) {
        preferences = value
        preferenceWrites = 0
        preferenceHistory = []
        scanCalls = 0
        scanArchitectures = []
    }

    func seedNondefaultState() {
        selection = OperatorSelection(
            mode: .manual,
            operatorName: "Other Carrier",
            plmn: "00102",
            accessTechnology: .lte
        )
        preferences = NRSystemSelectionPreferences(
            modePreference: 0x0010,
            saBands: .zero,
            nsaBands: .zero,
            lteBands: LTEBandMask(bands: [2])!
        )
        automaticWrites = 0
        preferenceWrites = 0
        preferenceHistory = []
        scanCalls = 0
        scanArchitectures = []
    }

    func waitForScan() async -> Bool {
        for _ in 0..<2_000 {
            if scanCalls > 0 { return true }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return false
    }

    func waitForManualMutation() async {
        for _ in 0..<2_000 {
            if manualWrites > 0 { return }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    func waitForAutomaticMutation() async {
        for _ in 0..<2_000 {
            if automaticWrites > 0 { return }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    func snapshot() -> (
        selection: OperatorSelection,
        preferences: NRSystemSelectionPreferences,
        automaticWrites: Int,
        preferenceWrites: Int,
        scanArchitectures: [NRArchitectureMode],
        preferenceHistory: [NRSystemSelectionPreferences]
    ) {
        (
            selection,
            preferences,
            automaticWrites,
            preferenceWrites,
            scanArchitectures,
            preferenceHistory
        )
    }
}

private actor DirectVOSStatusReader: VOSStatusReading {
    private var fingerprintCalls = 0

    func fetchDeviceFingerprint(configuration: DeviceConfiguration) async throws -> String {
        fingerprintCalls += 1
        if configuration.password == "rejected-fixture-password" {
            throw VOSClientError.authenticationFailed
        }
        return "fixture-vos-fingerprint"
    }

    func fetchSnapshot(configuration: DeviceConfiguration) async throws -> DeviceSnapshot {
        var snapshot = DeviceSnapshot.empty
        snapshot.host = configuration.sshHost ?? "fixture"
        snapshot.interfaceName = configuration.interfaceName
        return snapshot
    }

    func callCount() -> Int { fingerprintCalls }
}

private final class DirectSpeedTestTrafficReader: NetworkInterfaceTrafficReading, @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Result<NetworkInterfaceTraffic, SpeedTestError>]

    init(results: [Result<NetworkInterfaceTraffic, SpeedTestError>]) {
        self.results = results
    }

    func read(binding: SpeedTestBinding) throws -> NetworkInterfaceTraffic {
        lock.lock()
        defer { lock.unlock() }
        guard !results.isEmpty else {
            throw SpeedTestError.interfaceUnavailable(binding.interfaceName)
        }
        return try results.removeFirst().get()
    }
}

private actor DirectNetworkQualityProcess: NetworkQualityProcessExecuting {
    private let output: NetworkQualityProcessOutput
    private let suspend: Bool

    init(output: NetworkQualityProcessOutput, suspend: Bool) {
        self.output = output
        self.suspend = suspend
    }

    func execute(
        interfaceName: String,
        maximumRuntime: TimeInterval
    ) async throws -> NetworkQualityProcessOutput {
        if suspend {
            try await Task.sleep(nanoseconds: 10_000_000_000)
        }
        return output
    }

}

private actor DirectSpeedTestRunner: SpeedTestRunning {
    private let suspend: Bool
    private var runs = 0
    private var cancellations = 0

    init(suspend: Bool) {
        self.suspend = suspend
    }

    func run(
        binding: SpeedTestBinding,
        progress: @escaping @Sendable (SpeedTestProgress) async -> Void
    ) async throws -> SpeedTestResult {
        runs += 1
        await progress(SpeedTestProgress(
            downloadBitsPerSecond: 10_000_000,
            uploadBitsPerSecond: 2_000_000,
            elapsed: 0.1
        ))
        if suspend {
            do {
                try await Task.sleep(nanoseconds: 10_000_000_000)
            } catch {
                cancellations += 1
                throw error
            }
        }
        return SpeedTestResult(
            binding: binding,
            downloadBitsPerSecond: 100_000_000,
            uploadBitsPerSecond: 20_000_000,
            responsivenessRPM: 300,
            idleLatencyMilliseconds: 25,
            duration: 10,
            completedAt: Date(timeIntervalSince1970: 123)
        )
    }

    @discardableResult
    func waitForRun() async -> Bool {
        await waitForRuns(1)
    }

    @discardableResult
    func waitForRuns(_ expected: Int) async -> Bool {
        for _ in 0..<2_000 {
            if runs >= expected { return true }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return false
    }

    @discardableResult
    func waitForCancel() async -> Bool {
        for _ in 0..<2_000 {
            if cancellations > 0 { return true }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return false
    }

    func runCount() -> Int { runs }
}

private actor DirectUnavailableSpeedTestRunner: SpeedTestRunning {
    nonisolated let availabilityError: SpeedTestError? = .ooklaCLIUnavailable

    func run(
        binding: SpeedTestBinding,
        progress: @escaping @Sendable (SpeedTestProgress) async -> Void
    ) async throws -> SpeedTestResult {
        throw SpeedTestError.ooklaCLIUnavailable
    }
}

private func waitForDirectSpeedTestCompletion(_ model: SpeedTestModel) async {
    for _ in 0..<2_000 {
        let completed = await MainActor.run { () -> Bool in
            if case .completed = model.state { return true }
            return false
        }
        if completed { return }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
}

private struct DirectFixedNetworkTopologyProvider: NetworkTopologyProviding {
    let storedSnapshot: NetworkTopologySnapshot

    init(snapshot: NetworkTopologySnapshot) {
        storedSnapshot = snapshot
    }

    func snapshot() -> NetworkTopologySnapshot { storedSnapshot }
}

private func directIdentity(_ kind: ModemKind) -> ModemIdentity {
    ModemIdentity(
        kind: kind,
        manufacturer: "fixture",
        model: "fixture-\(kind.rawValue)",
        stableIdentifier: "fixture-\(kind.rawValue)-identity"
    )
}
