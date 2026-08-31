import Foundation

enum QMIParserError: LocalizedError, Equatable {
    case invalidHex
    case truncated
    case unexpectedMessage
    case requestFailed(UInt16)
    case malformedTLV
    case noActiveBand
    case systemPreferenceUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidHex: return "The VOS QMI probe returned invalid hexadecimal data."
        case .truncated: return "The VOS QMI response was truncated."
        case .unexpectedMessage: return "The VOS QMI response did not match the request."
        case let .requestFailed(code): return "The Qualcomm QMI request failed (\(code))."
        case .malformedTLV: return "The VOS QMI response contains an invalid TLV."
        case .noActiveBand: return "Qualcomm NAS did not report an active radio band."
        case .systemPreferenceUnavailable: return "Qualcomm NAS did not report separate SA and NSA preferences."
        }
    }
}

struct QMIRadioReading: Equatable, Sendable {
    let kind: RadioKind
    let band: String
    let channel: UInt32
    var bandwidthMHz: Double?

    var rawDescription: String {
        switch kind {
        case .nr: return "NR5G BAND \(band.dropFirst()), NR-ARFCN \(channel)"
        case .lte: return "LTE BAND \(band.dropFirst()), EARFCN \(channel)"
        }
    }
}

struct QMISignalInfo: Equatable, Sendable {
    var nrRSRQ: Int?
    var nrRSRP: Int?
    var nrSNR: Double?
    var lteRSSI: Int?
    var lteRSRQ: Int?
    var lteRSRP: Int?
    var lteSNR: Double?
}

enum QMILTECarrierRole: Equatable, Sendable {
    case primary
    case secondary
}

enum QMILTESecondaryCellState: Equatable, Sendable {
    case deconfigured
    case configuredDeactivated
    case configuredActivated
    case unknown(UInt32)

    init(rawValue: UInt32) {
        switch rawValue {
        case 0: self = .deconfigured
        case 1: self = .configuredDeactivated
        case 2: self = .configuredActivated
        default: self = .unknown(rawValue)
        }
    }

    var isActive: Bool { self == .configuredActivated }
}

struct QMILTECarrier: Equatable, Sendable {
    let role: QMILTECarrierRole
    let band: String?
    let qmiBand: UInt16
    let earfcn: UInt32
    let bandwidthMHz: Double?
    let physicalCellID: UInt16
    let state: QMILTESecondaryCellState?
    let index: UInt8?
}

struct QMILTECAInfo: Equatable, Sendable {
    var primaryCell: QMILTECarrier?
    var secondaryCells: [QMILTECarrier]

    var activeSecondaryBands: [String] {
        var seen = Set<String>()
        return secondaryCells.compactMap { cell in
            guard cell.state?.isActive == true,
                  let band = cell.band,
                  seen.insert(band).inserted
            else { return nil }
            return band
        }
    }
}

struct QMIServingInfo: Equatable, Sendable {
    var operatorName: String?
    var mcc: String?
    var mnc: String?
}

/// Signal measurements reported for one physical cell by NAS Get Cell
/// Location Info (0x0043). QMI encodes these values in tenths of a decibel;
/// `nil` represents its signed 16-bit unavailable sentinel.
struct QMICellSignalMetrics: Equatable, Sendable {
    let rsrqDB: Double?
    let rsrpDBm: Double?
    let rssiDBm: Double?
    let snrDB: Double?
}

struct QMILTECellMeasurement: Equatable, Sendable {
    let physicalCellID: UInt16
    let signal: QMICellSignalMetrics
}

struct QMILTECellLocation: Equatable, Sendable {
    let ueInIdle: Bool
    let plmn: [UInt8]
    let trackingAreaCode: UInt16
    let globalCellID: UInt32
    let earfcn: UInt32
    let physicalCellID: UInt16
    let cells: [QMILTECellMeasurement]

    var servingCellMeasurement: QMILTECellMeasurement? {
        cells.first { $0.physicalCellID == physicalCellID }
    }
}

struct QMILTEFrequencyLocation: Equatable, Sendable {
    let earfcn: UInt32
    let cells: [QMILTECellMeasurement]
}

struct QMINRCellLocation: Equatable, Sendable {
    let plmn: [UInt8]
    let trackingAreaCode: [UInt8]
    let globalCellID: UInt64
    let physicalCellID: UInt16
    let signal: QMICellSignalMetrics
}

struct QMICellLocationInfo: Equatable, Sendable {
    let lte: QMILTECellLocation?
    let lteInterfrequency: [QMILTEFrequencyLocation]
    let nrARFCN: UInt32?
    let nr: QMINRCellLocation?
}

struct QMIPLMNName: Equatable, Sendable {
    var longName: String?
    var shortName: String?
    var serviceProviderName: String? = nil

    var displayName: String? { longName ?? shortName ?? serviceProviderName }
}

private struct QMIResponse {
    let message: UInt16
    let tlvs: [UInt8: [Data]]

    init(data: Data, expectedMessage: UInt16) throws {
        guard data.count >= 7 else { throw QMIParserError.truncated }
        guard data.byte(at: 0) == 0x02,
              data.u16le(at: 3) == expectedMessage
        else { throw QMIParserError.unexpectedMessage }

        let payloadLength = Int(data.u16le(at: 5))
        let limit = 7 + payloadLength
        guard data.count >= limit else { throw QMIParserError.truncated }

        var parsed: [UInt8: [Data]] = [:]
        var offset = 7
        while offset < limit {
            guard offset + 3 <= limit else { throw QMIParserError.malformedTLV }
            let type = data.byte(at: offset)
            let length = Int(data.u16le(at: offset + 1))
            let valueStart = offset + 3
            let valueEnd = valueStart + length
            guard valueEnd <= limit else { throw QMIParserError.malformedTLV }
            parsed[type, default: []].append(data.subdata(in: valueStart..<valueEnd))
            offset = valueEnd
        }

        guard let result = parsed[0x02]?.first, result.count >= 4 else {
            throw QMIParserError.malformedTLV
        }
        let status = result.u16le(at: 0)
        let error = result.u16le(at: 2)
        guard status == 0, error == 0 else { throw QMIParserError.requestFailed(error) }

        message = expectedMessage
        tlvs = parsed
    }

    func firstTLV(_ type: UInt8) -> Data? { tlvs[type]?.first }
}

enum QMIParser {
    static func data(fromHex value: String) throws -> Data {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count.isMultiple(of: 2) else { throw QMIParserError.invalidHex }
        var result = Data(capacity: value.count / 2)
        var index = value.startIndex
        while index < value.endIndex {
            let next = value.index(index, offsetBy: 2)
            guard let byte = UInt8(value[index..<next], radix: 16) else { throw QMIParserError.invalidHex }
            result.append(byte)
            index = next
        }
        return result
    }

    static func activeRadios(from data: Data) throws -> [QMIRadioReading] {
        let response = try QMIResponse(data: data, expectedMessage: 0x0031)
        let bandwidths = parseBandwidthList(response.firstTLV(0x12))
        let readings: [QMIRadioReading]
        if let extended = response.firstTLV(0x11) {
            readings = try parseBandList(extended, channelBytes: 4, bandwidths: bandwidths)
        } else if let legacy = response.firstTLV(0x01) {
            readings = try parseBandList(legacy, channelBytes: 2, bandwidths: bandwidths)
        } else {
            throw QMIParserError.noActiveBand
        }

        guard !readings.isEmpty else { throw QMIParserError.noActiveBand }
        return readings
    }

    static func systemMode(from data: Data) throws -> NRSystemMode? {
        // Some tested VOS DSD responses contain vendor TLVs after the standard
        // system list. Parse only the successful result and first 0x10 TLV so
        // an unrelated vendor tail cannot invalidate a trustworthy mode.
        let systems = try preferredSystemTLV(from: data)
        guard systems.count >= 17,
              systems.byte(at: 0) > 0
        else { return nil }

        // The first 16-byte entry is DSD's preferred data system. SA/NSA is
        // accepted only for a 3GPP 5G RAT with exactly one explicit SO bit.
        let technology = systems.u32le(at: 1)
        let rat = systems.u32le(at: 5)
        let maskHigh = systems.u32le(at: 13)
        guard technology == 0, rat == 6 else { return nil }
        let nsa = maskHigh & (1 << 11) != 0 // service-option bit 43
        let sa = maskHigh & (1 << 12) != 0  // service-option bit 44
        guard sa != nsa else { return nil }
        return sa ? .sa : .nsa
    }

    static func signalInfo(from data: Data) throws -> QMISignalInfo {
        let response = try QMIResponse(data: data, expectedMessage: 0x004f)
        var result = QMISignalInfo()

        // QMI NAS LTE signal info: RSSI i8, RSRQ i8, RSRP i16, SNR i16.
        if let lte = response.firstTLV(0x14), lte.count >= 6 {
            result.lteRSSI = validInt8(lte.byte(at: 0))
            result.lteRSRQ = validInt8(lte.byte(at: 1))
            result.lteRSRP = validRSRP(Int(Int16(bitPattern: lte.u16le(at: 2))))
            result.lteSNR = decibelTenths(lte.u16le(at: 4))
        }
        // QMI NAS NR5G signal info: RSRP i16 and SNR i16. TLV 0x18 is RSRQ i16.
        if let nr = response.firstTLV(0x17), nr.count >= 4 {
            result.nrRSRP = validRSRP(Int(Int16(bitPattern: nr.u16le(at: 0))))
            result.nrSNR = decibelTenths(nr.u16le(at: 2))
        }
        if let nrRSRQ = response.firstTLV(0x18), nrRSRQ.count >= 2 {
            result.nrRSRQ = signedInt16UnlessSentinel(nrRSRQ.u16le(at: 0))
        }
        return result
    }

    static func servingInfo(from data: Data) throws -> QMIServingInfo {
        let response = try QMIResponse(data: data, expectedMessage: 0x0024)
        let name = response.firstTLV(0x12)
        let precisePLMN = response.firstTLV(0x27)
        if let name, name.count < 5 { throw QMIParserError.malformedTLV }
        if let precisePLMN, precisePLMN.count < 5 { throw QMIParserError.malformedTLV }
        guard name != nil || precisePLMN != nil else { return QMIServingInfo() }

        var operatorName: String?
        if let name {
            let length = Int(name.byte(at: 4))
            guard 5 + length <= name.count else { throw QMIParserError.malformedTLV }
            operatorName = String(data: name.subdata(in: 5..<(5 + length)), encoding: .utf8)?
                .replacingOccurrences(of: "\0", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Precise PLMN is preferred when available, but some NAS responses
        // omit the serving-name TLV entirely. Keep those responses usable so
        // the caller can still resolve a readable name through Get PLMN Name.
        guard let identity = precisePLMN ?? name else { return QMIServingInfo() }
        let mcc = identity.u16le(at: 0)
        let mnc = identity.u16le(at: 2)
        let hasThreeDigitMNC = precisePLMN.map { $0.count >= 5 && $0.byte(at: 4) != 0 }
        return QMIServingInfo(
            operatorName: operatorName?.isEmpty == false ? operatorName : nil,
            mcc: String(format: "%03d", mcc),
            mnc: String(format: hasThreeDigitMNC == false ? "%02d" : "%03d", mnc)
        )
    }

    static func cellLocationInfo(from data: Data) throws -> QMICellLocationInfo {
        let response = try QMIResponse(data: data, expectedMessage: 0x0043)

        let lte = try response.firstTLV(0x13).map(parseLTEIntrafrequencyLocation)
        let lteInterfrequency = try response.firstTLV(0x14).map(parseLTEInterfrequencyLocation) ?? []

        let nrARFCN = try response.firstTLV(0x2E).map { value in
            guard value.count == 4 else { throw QMIParserError.malformedTLV }
            return value.u32le(at: 0)
        }

        let nr = try response.firstTLV(0x2F).map { value in
            // PLMN[3], TAC[3], NCI u64, PCI u16, then three i16 values.
            guard value.count == 22 else { throw QMIParserError.malformedTLV }
            return QMINRCellLocation(
                plmn: Array(value[0..<3]),
                trackingAreaCode: Array(value[3..<6]),
                globalCellID: value.u64le(at: 6),
                physicalCellID: value.u16le(at: 14),
                signal: QMICellSignalMetrics(
                    rsrqDB: decibelTenths(value.u16le(at: 16)),
                    rsrpDBm: decibelTenths(value.u16le(at: 18)),
                    rssiDBm: nil,
                    snrDB: decibelTenths(value.u16le(at: 20))
                )
            )
        }

        return QMICellLocationInfo(
            lte: lte,
            lteInterfrequency: lteInterfrequency,
            nrARFCN: nrARFCN,
            nr: nr
        )
    }

    static func plmnName(from data: Data) throws -> QMIPLMNName {
        let response = try QMIResponse(data: data, expectedMessage: 0x0044)
        guard let eons = response.firstTLV(0x10) else { return QMIPLMNName() }

        // EONS encodes SPN first, followed by short and long operator names.
        // Each operator name has encoding/country/spare metadata and a byte
        // length. VOS currently returns UTF-8-compatible names (for example
        // TELUS); unknown encodings fail closed to nil.
        guard eons.count >= 2 else { throw QMIParserError.malformedTLV }
        let spnEncoding = eons.byte(at: 0)
        let spnLength = Int(eons.byte(at: 1))
        guard 2 + spnLength <= eons.count else { throw QMIParserError.malformedTLV }
        let serviceProviderName = decodeNetworkName(
            eons.subdata(in: 2..<(2 + spnLength)),
            encoding: spnEncoding
        )
        var offset = 2 + spnLength
        let shortName = try parseEONSName(eons, offset: &offset)
        let longName = try parseEONSName(eons, offset: &offset)
        return QMIPLMNName(
            longName: longName,
            shortName: shortName,
            serviceProviderName: serviceProviderName
        )
    }

    static func getPLMNNameRequest(
        mcc: UInt16,
        mnc: UInt16,
        mncHasThreeDigits: Bool? = nil,
        transaction: UInt16 = 1
    ) -> Data {
        var identity = Data()
        identity.appendUInt16LE(mcc)
        identity.appendUInt16LE(mnc)

        var payload = Data()
        payload.append(tlv(type: 0x01, value: identity))
        if let mncHasThreeDigits {
            payload.append(tlv(type: 0x11, value: Data([mncHasThreeDigits ? 1 : 0])))
        }

        var request = Data([0x00])
        request.appendUInt16LE(transaction)
        request.appendUInt16LE(0x0044)
        request.appendUInt16LE(UInt16(payload.count))
        request.append(payload)
        return request
    }

    static func lteCarrierAggregation(from data: Data) throws -> QMILTECAInfo {
        let response = try QMIResponse(data: data, expectedMessage: 0x00ac)
        let primaryCell = try response.firstTLV(0x13).map { value in
            guard value.count >= 10 else { throw QMIParserError.malformedTLV }
            return lteCarrier(
                role: .primary,
                value: value,
                state: nil,
                index: nil
            )
        }

        var secondaryCells: [QMILTECarrier] = []
        if let list = response.firstTLV(0x15) {
            guard !list.isEmpty else { throw QMIParserError.malformedTLV }
            let count = Int(list.byte(at: 0))
            var offset = 1
            for _ in 0..<count {
                guard offset + 15 <= list.count else { throw QMIParserError.malformedTLV }
                let entry = list.subdata(in: offset..<(offset + 15))
                secondaryCells.append(lteCarrier(
                    role: .secondary,
                    value: entry,
                    state: QMILTESecondaryCellState(rawValue: entry.u32le(at: 10)),
                    index: entry.byte(at: 14)
                ))
                offset += 15
            }
        } else if let legacy = response.firstTLV(0x12), legacy.count >= 14 {
            secondaryCells.append(lteCarrier(
                role: .secondary,
                value: legacy,
                state: QMILTESecondaryCellState(rawValue: legacy.u32le(at: 10)),
                index: response.firstTLV(0x14).flatMap { $0.isEmpty ? nil : $0.byte(at: 0) }
            ))
        } else if let legacy = response.firstTLV(0x12), !legacy.isEmpty {
            throw QMIParserError.malformedTLV
        }

        return QMILTECAInfo(primaryCell: primaryCell, secondaryCells: secondaryCells)
    }

    static func lteSecondaryBands(from data: Data) throws -> [String] {
        try lteCarrierAggregation(from: data).activeSecondaryBands
    }

    static func systemSelectionPreferences(from data: Data) throws -> NRSystemSelectionPreferences {
        let response = try QMIResponse(data: data, expectedMessage: 0x0034)
        guard let rawMode = response.firstTLV(0x11), rawMode.count == 2,
              let rawSA = response.firstTLV(0x2C),
              let rawNSA = response.firstTLV(0x2D),
              let sa = NRBandMask(rawSA),
              let nsa = NRBandMask(rawNSA)
        else { throw QMIParserError.systemPreferenceUnavailable }

        return NRSystemSelectionPreferences(
            modePreference: rawMode.u16le(at: 0),
            saBands: sa,
            nsaBands: nsa,
            lteBands: response.firstTLV(0x23).flatMap(LTEBandMask.init)
        )
    }

    static func setNRSystemSelectionRequest(
        modePreference: UInt16,
        saBands: NRBandMask,
        nsaBands: NRBandMask,
        lteBands: LTEBandMask? = nil,
        transaction: UInt16 = 1
    ) -> Data {
        var payload = Data()
        // QMI NAS change duration 0 means until the next power cycle. This
        // keeps a bad travel-mode choice recoverable by reconnecting VOS.
        payload.append(tlv(type: 0x17, value: Data([0x00])))
        var mode = Data()
        mode.appendUInt16LE(modePreference)
        payload.append(tlv(type: 0x11, value: mode))
        if let lteBands {
            payload.append(tlv(type: 0x24, value: lteBands.bytes))
        }
        payload.append(tlv(type: 0x2F, value: saBands.bytes))
        payload.append(tlv(type: 0x30, value: nsaBands.bytes))

        var request = Data([0x00])
        request.appendUInt16LE(transaction)
        request.appendUInt16LE(0x0033)
        request.appendUInt16LE(UInt16(payload.count))
        request.append(payload)
        return request
    }

    static func validateSetSystemSelectionResponse(_ data: Data) throws {
        _ = try QMIResponse(data: data, expectedMessage: 0x0033)
    }

    static func getSystemSelectionRequest(transaction: UInt16 = 1) -> Data {
        var request = Data([0x00])
        request.appendUInt16LE(transaction)
        request.appendUInt16LE(0x0034)
        request.appendUInt16LE(0)
        return request
    }

    private static func parseBandList(
        _ value: Data,
        channelBytes: Int,
        bandwidths: [(kind: RadioKind?, width: Double?)]
    ) throws -> [QMIRadioReading] {
        guard !value.isEmpty else { throw QMIParserError.malformedTLV }
        let count = Int(value.byte(at: 0))
        let entrySize = 3 + channelBytes
        var offset = 1
        var readings: [QMIRadioReading] = []
        for sourceIndex in 0..<count {
            guard offset + entrySize <= value.count else { throw QMIParserError.malformedTLV }
            let radio = value.byte(at: offset)
            let activeBand = value.u16le(at: offset + 1)
            let channel = channelBytes == 4
                ? value.u32le(at: offset + 3)
                : UInt32(value.u16le(at: offset + 3))
            if let kind = radioKind(code: radio), let label = bandLabel(kind: kind, value: activeBand) {
                let width = sourceIndex < bandwidths.count && bandwidths[sourceIndex].kind == kind
                    ? bandwidths[sourceIndex].width
                    : nil
                readings.append(QMIRadioReading(kind: kind, band: label, channel: channel, bandwidthMHz: width))
            }
            offset += entrySize
        }
        return readings
    }

    private static func tlv(type: UInt8, value: Data) -> Data {
        var result = Data([type])
        result.appendUInt16LE(UInt16(value.count))
        result.append(value)
        return result
    }

    private static func parseBandwidthList(_ value: Data?) -> [(kind: RadioKind?, width: Double?)] {
        guard let value, !value.isEmpty else { return [] }
        let count = Int(value.byte(at: 0))
        var offset = 1
        var result: [(kind: RadioKind?, width: Double?)] = []
        for _ in 0..<count {
            guard offset + 5 <= value.count else { break }
            result.append((
                radioKind(code: value.byte(at: offset)),
                bandwidthMap[value.u32le(at: offset + 1)]
            ))
            offset += 5
        }
        return result
    }

    private static func parseEONSName(_ value: Data, offset: inout Int) throws -> String? {
        guard offset + 4 <= value.count else { throw QMIParserError.malformedTLV }
        let encoding = value.byte(at: offset)
        let length = Int(value.byte(at: offset + 3))
        let start = offset + 4
        let end = start + length
        guard end <= value.count else { throw QMIParserError.malformedTLV }
        offset = end
        guard length > 0 else { return nil }
        return decodeNetworkName(value.subdata(in: start..<end), encoding: encoding)
    }

    private static func decodeNetworkName(_ data: Data, encoding: UInt8) -> String? {
        let name: String?
        switch encoding {
        case 0x00, 0x01:
            name = String(data: data, encoding: .utf8)
        case 0x04:
            name = String(data: data, encoding: .utf16LittleEndian)
        default:
            // QMI also defines GSM 7-bit and several broadcast-specific
            // encodings. Returning nil is safer than displaying mojibake.
            name = nil
        }
        let cleaned = name?
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned?.isEmpty == false ? cleaned : nil
    }

    private static func preferredSystemTLV(from data: Data) throws -> Data {
        guard data.count >= 7 else { throw QMIParserError.truncated }
        guard data.byte(at: 0) == 0x02, data.u16le(at: 3) == 0x0024 else {
            throw QMIParserError.unexpectedMessage
        }
        let limit = 7 + Int(data.u16le(at: 5))
        guard data.count >= limit else { throw QMIParserError.truncated }

        var offset = 7
        var resultOK = false
        while offset + 3 <= limit {
            let type = data.byte(at: offset)
            let length = Int(data.u16le(at: offset + 1))
            let start = offset + 3
            let end = start + length
            guard end <= limit else { throw QMIParserError.malformedTLV }
            let value = data.subdata(in: start..<end)
            if type == 0x02, value.count >= 4 {
                let status = value.u16le(at: 0)
                let error = value.u16le(at: 2)
                guard status == 0, error == 0 else { throw QMIParserError.requestFailed(error) }
                resultOK = true
            } else if type == 0x10, resultOK {
                return value
            }
            offset = end
        }
        throw QMIParserError.malformedTLV
    }

    private static func validRSRP(_ value: Int) -> Int? {
        (-200 ... -1).contains(value) ? value : nil
    }

    private static func validInt8(_ rawValue: UInt8) -> Int? {
        let value = Int(Int8(bitPattern: rawValue))
        return value == Int(Int8.min) ? nil : value
    }

    private static func signedInt16UnlessSentinel(_ rawValue: UInt16) -> Int? {
        let value = Int16(bitPattern: rawValue)
        return value == Int16.min ? nil : Int(value)
    }

    private static func decibelTenths(_ rawValue: UInt16) -> Double? {
        signedInt16UnlessSentinel(rawValue).map { Double($0) / 10 }
    }

    private static func parseLTEIntrafrequencyLocation(_ value: Data) throws -> QMILTECellLocation {
        // Fixed fields through the cell-count byte occupy 19 bytes. Each cell
        // then contains PCI, RSRQ, RSRP, RSSI, and RX level as five u16/i16
        // fields. Requiring exact consumption prevents truncated arrays and
        // silently accepted trailing bytes.
        guard value.count >= 19 else { throw QMIParserError.malformedTLV }
        let count = Int(value.byte(at: 18))
        let entrySize = 10
        guard count <= (Int.max - 19) / entrySize,
              value.count == 19 + count * entrySize
        else { throw QMIParserError.malformedTLV }

        var cells: [QMILTECellMeasurement] = []
        cells.reserveCapacity(count)
        var offset = 19
        for _ in 0..<count {
            cells.append(QMILTECellMeasurement(
                physicalCellID: value.u16le(at: offset),
                signal: QMICellSignalMetrics(
                    rsrqDB: decibelTenths(value.u16le(at: offset + 2)),
                    rsrpDBm: decibelTenths(value.u16le(at: offset + 4)),
                    rssiDBm: decibelTenths(value.u16le(at: offset + 6)),
                    snrDB: nil
                )
            ))
            // The final i16 is cell-selection RX level, not another signal
            // metric exposed by this parser.
            offset += entrySize
        }

        return QMILTECellLocation(
            ueInIdle: value.byte(at: 0) != 0,
            plmn: Array(value[1..<4]),
            trackingAreaCode: value.u16le(at: 4),
            globalCellID: value.u32le(at: 6),
            earfcn: UInt32(value.u16le(at: 10)),
            physicalCellID: value.u16le(at: 12),
            cells: cells
        )
    }

    private static func parseLTEInterfrequencyLocation(_ value: Data) throws -> [QMILTEFrequencyLocation] {
        guard value.count >= 2 else { throw QMIParserError.malformedTLV }
        let frequencyCount = Int(value.byte(at: 1))
        var offset = 2
        var result: [QMILTEFrequencyLocation] = []
        result.reserveCapacity(frequencyCount)

        for _ in 0..<frequencyCount {
            // EARFCN u16, low/high thresholds, priority and cell-count.
            guard offset + 6 <= value.count else { throw QMIParserError.malformedTLV }
            let earfcn = UInt32(value.u16le(at: offset))
            let cellCount = Int(value.byte(at: offset + 5))
            offset += 6
            guard cellCount <= (value.count - offset) / 10 else {
                throw QMIParserError.malformedTLV
            }
            var cells: [QMILTECellMeasurement] = []
            cells.reserveCapacity(cellCount)
            for _ in 0..<cellCount {
                cells.append(QMILTECellMeasurement(
                    physicalCellID: value.u16le(at: offset),
                    signal: QMICellSignalMetrics(
                        rsrqDB: decibelTenths(value.u16le(at: offset + 2)),
                        rsrpDBm: decibelTenths(value.u16le(at: offset + 4)),
                        rssiDBm: decibelTenths(value.u16le(at: offset + 6)),
                        snrDB: nil
                    )
                ))
                offset += 10
            }
            result.append(QMILTEFrequencyLocation(earfcn: earfcn, cells: cells))
        }
        guard offset == value.count else { throw QMIParserError.malformedTLV }
        return result
    }

    private static func lteCarrier(
        role: QMILTECarrierRole,
        value: Data,
        state: QMILTESecondaryCellState?,
        index: UInt8?
    ) -> QMILTECarrier {
        let rawBand = value.u16le(at: 8)
        return QMILTECarrier(
            role: role,
            band: lteBands[rawBand].map { "B\($0)" },
            qmiBand: rawBand,
            earfcn: UInt32(value.u16le(at: 2)),
            bandwidthMHz: bandwidthMap[value.u32le(at: 4)],
            physicalCellID: value.u16le(at: 0),
            state: state,
            index: index
        )
    }

    private static func radioKind(code: UInt8) -> RadioKind? {
        if code == 12 { return .nr }
        if code == 8 { return .lte }
        return nil
    }

    private static func bandLabel(kind: RadioKind, value: UInt16) -> String? {
        switch kind {
        case .nr: return nrBands[value].map { "n\($0)" }
        case .lte: return lteBands[value].map { "B\($0)" }
        }
    }

    private static let bandwidthMap: [UInt32: Double] = [
        0: 1.4, 1: 3, 2: 5, 3: 10, 4: 15, 5: 20,
        6: 5, 7: 10, 8: 15, 9: 20, 10: 25, 11: 30, 12: 40,
        13: 50, 14: 60, 15: 80, 16: 90, 17: 100, 18: 200,
        19: 400, 20: 0.2, 21: 1.6, 22: 5, 23: 10, 24: 70
    ]

    // QmiNasActiveBand values from libqmi's qmi-enums-nas.h.
    private static let lteBands: [UInt16: Int] = [
        120: 1, 121: 2, 122: 3, 123: 4, 124: 5, 125: 6, 126: 7,
        127: 8, 128: 9, 129: 10, 130: 11, 131: 12, 132: 13, 133: 14,
        134: 17, 143: 18, 144: 19, 145: 20, 146: 21, 152: 23,
        147: 24, 148: 25, 153: 26, 164: 27, 158: 28, 159: 29,
        160: 30, 165: 31, 154: 32, 135: 33, 136: 34, 137: 35,
        138: 36, 139: 37, 140: 38, 141: 39, 142: 40, 149: 41,
        150: 42, 151: 43, 163: 46, 166: 47, 167: 48, 161: 66,
        168: 71, 155: 125, 156: 126, 157: 127, 162: 250
    ]

    private static let nrBands: [UInt16: Int] = [
        250: 1, 251: 2, 252: 3, 253: 5, 254: 7, 255: 8, 256: 20,
        257: 28, 258: 38, 259: 41, 260: 50, 261: 51, 262: 66,
        263: 70, 264: 71, 265: 74, 266: 75, 267: 76, 268: 77,
        269: 78, 270: 79, 271: 80, 272: 81, 273: 82, 274: 83,
        275: 84, 276: 85, 277: 257, 278: 258, 279: 259, 280: 260,
        281: 261, 282: 12, 283: 25, 284: 34, 285: 39, 286: 40,
        287: 65, 288: 86, 289: 48, 290: 14, 291: 13, 292: 18,
        293: 26, 294: 30, 295: 29, 296: 53, 297: 46, 298: 91,
        299: 92, 300: 93, 301: 94, 315: 100, 316: 101
    ]
}

private extension Data {
    func byte(at offset: Int) -> UInt8 { self[startIndex + offset] }

    func u16le(at offset: Int) -> UInt16 {
        UInt16(byte(at: offset)) | UInt16(byte(at: offset + 1)) << 8
    }

    func u32le(at offset: Int) -> UInt32 {
        UInt32(byte(at: offset)) |
            UInt32(byte(at: offset + 1)) << 8 |
            UInt32(byte(at: offset + 2)) << 16 |
            UInt32(byte(at: offset + 3)) << 24
    }

    func u64le(at offset: Int) -> UInt64 {
        UInt64(u32le(at: offset)) | UInt64(u32le(at: offset + 4)) << 32
    }

    mutating func appendUInt16LE(_ value: UInt16) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
    }
}
