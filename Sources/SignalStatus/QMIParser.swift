import Foundation

enum QMIParserError: LocalizedError, Equatable {
    case invalidHex
    case truncated
    case unexpectedMessage
    case requestFailed(UInt16)
    case malformedTLV
    case noActiveBand

    var errorDescription: String? {
        switch self {
        case .invalidHex: return "The VOS QMI probe returned invalid hexadecimal data."
        case .truncated: return "The VOS QMI response was truncated."
        case .unexpectedMessage: return "The VOS QMI response did not match the request."
        case let .requestFailed(code): return "The Qualcomm QMI request failed (\(code))."
        case .malformedTLV: return "The VOS QMI response contains an invalid TLV."
        case .noActiveBand: return "Qualcomm NAS did not report an active radio band."
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
    var nrRSRP: Int?
    var lteRSRP: Int?
}

struct QMIServingInfo: Equatable, Sendable {
    var operatorName: String?
    var mcc: String?
    var mnc: String?
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
        if let lte = response.firstTLV(0x14), lte.count >= 4 {
            result.lteRSRP = validRSRP(Int(Int16(bitPattern: lte.u16le(at: 2))))
        }
        // QMI NAS NR5G signal info: RSRP i16 and SNR i16. TLV 0x18 is RSRQ.
        if let nr = response.firstTLV(0x17), nr.count >= 2 {
            result.nrRSRP = validRSRP(Int(Int16(bitPattern: nr.u16le(at: 0))))
        }
        return result
    }

    static func servingInfo(from data: Data) throws -> QMIServingInfo {
        let response = try QMIResponse(data: data, expectedMessage: 0x0024)
        guard let name = response.firstTLV(0x12), name.count >= 5 else {
            return QMIServingInfo()
        }
        let length = Int(name.byte(at: 4))
        guard 5 + length <= name.count else { throw QMIParserError.malformedTLV }
        let operatorData = name.subdata(in: 5..<(5 + length))
        let precisePLMN = response.firstTLV(0x27)
        let mcc = precisePLMN.flatMap { $0.count >= 5 ? $0.u16le(at: 0) : nil } ?? name.u16le(at: 0)
        let mnc = precisePLMN.flatMap { $0.count >= 5 ? $0.u16le(at: 2) : nil } ?? name.u16le(at: 2)
        let hasThreeDigitMNC = precisePLMN.map { $0.count >= 5 && $0.byte(at: 4) != 0 }
        return QMIServingInfo(
            operatorName: String(data: operatorData, encoding: .utf8),
            mcc: String(format: "%03d", mcc),
            mnc: String(format: hasThreeDigitMNC == false ? "%02d" : "%03d", mnc)
        )
    }

    static func lteSecondaryBands(from data: Data) throws -> [String] {
        let response = try QMIResponse(data: data, expectedMessage: 0x00ac)
        var values: [(band: UInt16, state: UInt32)] = []

        if let list = response.firstTLV(0x15), !list.isEmpty {
            let count = Int(list.byte(at: 0))
            var offset = 1
            for _ in 0..<count {
                guard offset + 15 <= list.count else { throw QMIParserError.malformedTLV }
                values.append((list.u16le(at: offset + 8), list.u32le(at: offset + 10)))
                offset += 15
            }
        } else if let legacy = response.firstTLV(0x12), legacy.count >= 14 {
            values.append((legacy.u16le(at: 8), legacy.u32le(at: 10)))
        }

        var seen = Set<String>()
        return values.compactMap { entry in
            guard entry.state == 2,
                  let number = lteBands[entry.band]
            else { return nil }
            let label = "B\(number)"
            return seen.insert(label).inserted ? label : nil
        }
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
}
