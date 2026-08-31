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
