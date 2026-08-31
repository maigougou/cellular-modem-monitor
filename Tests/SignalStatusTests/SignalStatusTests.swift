import XCTest
@testable import SignalStatus

final class SignalStatusTests: XCTestCase {
    private let lteBand = "02010031002400020400000000000106000108790084031108000108790084030000120600010805000000"
    private let nrAndLTE = "0201003100270002040000000000110f00020c0d0180ac090008790084030000120b00020c0d0000000805000000"
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

    func testAppLanguageDefaultsToChineseForChineseSystemLanguages() {
        XCTAssertEqual(AppLanguage.systemDefault(preferredLanguages: ["zh-Hans-CN", "en-CA"]), .simplifiedChinese)
        XCTAssertEqual(AppLanguage.systemDefault(preferredLanguages: ["zh-Hant-TW"]), .simplifiedChinese)
        XCTAssertEqual(AppLanguage.systemDefault(preferredLanguages: ["ZH-cn"]), .simplifiedChinese)
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
