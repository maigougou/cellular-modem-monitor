import XCTest
@testable import SignalStatus

final class SignalStatusTests: XCTestCase {
    private let lteBand = "02010031002400020400000000000106000108790084031108000108790084030000120600010805000000"
    private let nrAndLTE = "0201003100270002040000000000110f00020c0d0180ac090008790084030000120b00020c0d0000000805000000"
    private let dsdNSA = "02010024001b000204000000000010110001000000000600000000000000000a0000"
    private let dsdSA = "02010024001b00020400000000001011000100000000060000000000000000120000"
    private let dsdLTE = "02010024001b00020400000000001011000100000000030000000010000000000000"

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

    func testDSDOnlyUsesExplicitMode() throws {
        XCTAssertEqual(try QMIParser.systemMode(from: data(dsdNSA)), .nsa)
        XCTAssertEqual(try QMIParser.systemMode(from: data(dsdSA)), .sa)
        XCTAssertNil(try QMIParser.systemMode(from: data(dsdLTE)))
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

    func testOnlyLocalDeviceAddressesAreAccepted() {
        XCTAssertEqual(DeviceConfiguration(host: "192.168.225.1", username: "root", password: "x", refreshInterval: 5).sshHost, "192.168.225.1")
        XCTAssertNil(DeviceConfiguration(host: "example.com", username: "root", password: "x", refreshInterval: 5).sshHost)
    }

    private func data(_ hex: String) -> Data { try! QMIParser.data(fromHex: hex) }
}
