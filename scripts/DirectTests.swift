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
        runMC7530ParserTests(failures: &failures)
        await runZTEAuthTests(failures: &failures)
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
                "saving another setting preserves an unreadable Keychain credential",
                failures: &failures
            )
        } catch {
            failures.append("preserve unreadable Keychain credential: \(error)")
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
                failures.append("credential transaction must not treat a Keychain read error as missing")
            } catch {}
            check(store.setCallCount() == 0,
                  "credential read failure performs no writes", failures: &failures)
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
                failures.append("Keychain read failure must be surfaced")
            } catch {}
            check(defaults.string(forKey: "sshPassword") == "legacy-must-remain",
                  "Keychain read failure preserves legacy preference", failures: &failures)
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
                    "Save retries a failed legacy Keychain migration before cleanup",
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
    }

    private static func runDiscoveryTests(failures: inout [String]) async {
        let builtInTimeouts = Dictionary(
            uniqueKeysWithValues: ModemDiscoveryProfile.builtIn.map {
                ($0.kind, $0.probeTimeoutNanoseconds)
            }
        )
        check(builtInTimeouts[.zteMC7530CA] == 2_000_000_000,
              "ZTE discovery keeps the short HTTP probe budget", failures: &failures)
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
        if let slate = ModemCandidateGenerator().candidates(
            topology: routed,
            allowedKinds: [.zteMC7530CA]
        ).first {
            check(slate.endpoint.connectionPath == .routed, "discovery Slate routed path", failures: &failures)
            check(slate.endpoint.sourceAddress == "192.168.8.23" && slate.endpoint.gateway == "192.168.8.1",
                  "discovery Slate route metadata", failures: &failures)
        } else {
            failures.append("discovery Slate candidate")
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
            check(zteHistory.identifyCredentials == [.none],
                  "coordinator ZTE identification is anonymous", failures: &failures)
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
                        category: .authentication
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
            check(standard.registration(for: .zteMC7530CA)?.identificationCredentials == .anonymous,
                  "standard registry ZTE anonymous identity policy", failures: &failures)
            check(standard.registration(for: .zteMC7530CA)?.statusCredentials == .configured(.web),
                  "standard registry ZTE web status policy", failures: &failures)
            check(standard.registration(for: .vos5G)?.identificationCredentials == .configured(.ssh),
                  "standard registry VOS SSH identity policy", failures: &failures)
        } catch {
            failures.append("standard backend registry: \(error)")
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
                identificationCredentials: .anonymous,
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

    private let identity: ModemIdentity
    private var fetchFailures: [Bool]
    private let typedFetchFailure: DirectMockTypedFetchFailure?
    private var identifyCredentials: [ModemCredentials] = []
    private var fetchCredentials: [ModemCredentials] = []
    private var identifyScopeKeys: [String] = []
    private var fetchScopeKeys: [String] = []

    init(
        kind: ModemKind,
        fetchFailures: [Bool] = [],
        typedFetchFailure: DirectMockTypedFetchFailure? = nil
    ) {
        self.kind = kind
        self.fetchFailures = fetchFailures
        self.typedFetchFailure = typedFetchFailure
        self.identity = directIdentity(kind)
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
