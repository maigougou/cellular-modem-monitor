import Foundation

enum MC7530ParserError: LocalizedError, Equatable {
    case invalidPayload

    var errorDescription: String? {
        "The MC7530CA radio response is malformed."
    }
}

struct MC7530RadioInfo: Equatable, Sendable {
    var networkType: String?
    var operatorName: String?
    var mcc: String?
    var mnc: String?
    var nrSystemMode: NRSystemMode?

    var nrBand: String?
    var nrChannel: String?
    var nrBandwidthMHz: Double?
    var nrSignal: RadioSignal
    var nrGlobalCellID: UInt64?
    var nrPhysicalCellID: UInt16?
    var nrPrimaryCell: NRCarrier?
    var nrSecondaryCells: [NRCarrier]

    var lteBand: String?
    var lteChannel: String?
    var lteBandwidthMHz: Double?
    var lteSignal: RadioSignal
    var lteGlobalCellID: UInt64?
    var ltePhysicalCellID: UInt16?
    var ltePrimaryCell: LTECarrier?
    var lteSecondaryCells: [LTECarrier]

    /// Retained for diagnostics even when the supported carrier fields parse.
    var unparsedLTECASignal: String?
    var unparsedNRCA: String?

    func snapshot(
        host: String,
        interfaceName: String?,
        now: Date = Date()
    ) -> DeviceSnapshot {
        DeviceSnapshot(
            host: host,
            interfaceName: interfaceName,
            operatorName: operatorName,
            mcc: mcc,
            mnc: mnc,
            nrSystemMode: nrSystemMode,
            nrBand: nrBand,
            nrChannel: nrChannel,
            nrBandwidthMHz: nrBandwidthMHz,
            nrRaw: Self.rawDescription(prefix: "NR5G", band: nrBand, channelLabel: "NR-ARFCN", channel: nrChannel),
            nrSignal: nrSignal,
            nrGlobalCellID: nrGlobalCellID,
            nrPhysicalCellID: nrPhysicalCellID,
            nrPrimaryCell: nrPrimaryCell,
            nrSecondaryCells: nrSecondaryCells,
            lteBand: lteBand,
            lteChannel: lteChannel,
            lteBandwidthMHz: lteBandwidthMHz,
            lteRaw: Self.rawDescription(prefix: "LTE", band: lteBand, channelLabel: "EARFCN", channel: lteChannel),
            lteSignal: lteSignal,
            lteGlobalCellID: lteGlobalCellID,
            ltePhysicalCellID: ltePhysicalCellID,
            ltePrimaryCell: ltePrimaryCell,
            lteSecondaryCells: lteSecondaryCells,
            lteNeighborCells: [],
            moduleVersion: nil,
            deviceFirmware: nil,
            updatedAt: now
        )
    }

    private static func rawDescription(
        prefix: String,
        band: String?,
        channelLabel: String,
        channel: String?
    ) -> String? {
        guard let band else { return nil }
        if let channel { return "\(prefix) BAND \(band), \(channelLabel) \(channel)" }
        return "\(prefix) BAND \(band)"
    }
}

enum MC7530Parser {
    private static let ltePCIRange: ClosedRange<UInt16> = 0 ... 503
    private static let nrPCIRange: ClosedRange<UInt16> = 0 ... 1_007
    private static let lteEARFCNRange: ClosedRange<UInt32> = 0 ... 70_645
    private static let nrARFCNRange: ClosedRange<UInt32> = 1 ... 3_279_165
    private static let maximumLTECellID: UInt64 = (1 << 28) - 1
    private static let maximumNRCellID: UInt64 = (1 << 36) - 1
    private static let lteBandwidthsMHz: Set<Double> = [1.4, 3, 5, 10, 15, 20]
    private static let nrBandwidthsMHz: Set<Double> = [5, 10, 15, 20, 25, 30, 40, 50, 60, 70, 80, 90, 100, 200, 400]

    static func parse(_ payload: ZTEJSONValue) throws -> MC7530RadioInfo {
        guard let object = unwrapObject(payload) else { throw MC7530ParserError.invalidPayload }

        let networkType = cleanString(object["network_type"])
        let nrBand = normalizeNRBand(cleanString(object["nr5g_action_band"]))
        let lteBand = normalizeLTEBand(cleanString(object["wan_active_band"]))
        let nrChannelValue = boundedUInt32(object["nr5g_action_channel"], range: nrARFCNRange)
        let lteChannelValue = boundedUInt32(object["wan_active_channel"], range: lteEARFCNRange)
        let nrPCI = boundedUInt16(object["nr5g_pci"], range: nrPCIRange)
        let ltePCI = boundedUInt16(object["lte_pci"], range: ltePCIRange)
        let nrMode = systemMode(networkType: networkType, hasActiveNR: nrBand != nil)

        let lteSignal = lteBand == nil ? .empty : RadioSignal(
            rsrpDBm: boundedInteger(object["lte_rsrp"], range: -160 ... -40),
            rsrqDB: boundedDouble(object["lte_rsrq"], range: -40 ... 0),
            rssiDBm: boundedInteger(object["lte_rssi"], range: -140 ... -20),
            snrDB: boundedDouble(object["lte_snr"], range: -30 ... 50)
        )
        let nrSignal = nrBand == nil ? .empty : RadioSignal(
            rsrpDBm: boundedInteger(object["nr5g_rsrp"], range: -160 ... -40),
            rsrqDB: boundedDouble(object["nr5g_rsrq"], range: -43 ... 0),
            rssiDBm: boundedInteger(object["nr5g_rssi"], range: -140 ... -20),
            snrDB: boundedDouble(object["nr5g_snr"], range: -30 ... 50)
        )

        let nrBandwidth = nrBand == nil ? nil : standardBandwidth(
            object["nr5g_bandwidth"],
            allowed: nrBandwidthsMHz
        )
        let nrGlobalCellID = nrBand == nil ? nil : boundedPositiveUInt64(
            object["nr5g_cell_id"],
            maximum: maximumNRCellID
        )
        let nrSecondaryCells = nrBand != nil && nrChannelValue != nil
            ? parseNRSecondaryCarriers(cleanString(object["nrca"]))
            : []
        let nrPrimaryCell = nrBand.flatMap { band in
            nrChannelValue.map { nrarfcn in
                NRCarrier(
                    role: .primary,
                    band: band,
                    nrarfcn: nrarfcn,
                    bandwidthMHz: nrBandwidth,
                    physicalCellID: nrPCI,
                    state: .active,
                    globalCellID: nrGlobalCellID,
                    signal: nrSignal
                )
            }
        }

        let ca = parseLTECarriers(
            cleanString(object["lteca"]),
            secondarySignalRaw: cleanString(object["ltecasig"]),
            primarySignal: lteSignal
        )
        var primary = ca.primary
        if primary == nil,
           let band = lteBand,
           let channel = lteChannelValue,
           let pci = ltePCI {
            primary = LTECarrier(
                role: .primary,
                band: band,
                earfcn: channel,
                bandwidthMHz: nil,
                physicalCellID: pci,
                state: .active,
                globalCellID: boundedPositiveUInt64(
                    object["cell_id"],
                    maximum: maximumLTECellID
                ),
                signal: lteSignal
            )
        }
        if var identifiedPrimary = primary {
            identifiedPrimary.globalCellID = boundedPositiveUInt64(
                object["cell_id"],
                maximum: maximumLTECellID
            )
            primary = identifiedPrimary
        }
        let effectiveLTEChannel = lteChannelValue ?? primary?.earfcn
        let effectiveLTEPCI = ltePCI ?? primary?.physicalCellID

        return MC7530RadioInfo(
            networkType: networkType,
            operatorName: cleanString(object["network_provider_fullname"])
                ?? cleanString(object["network_provider"]),
            mcc: formattedMCC(object["rmcc"]),
            mnc: formattedMNC(object["rmnc"]),
            nrSystemMode: nrMode,
            nrBand: nrBand,
            nrChannel: nrBand == nil ? nil : nrChannelValue.map(String.init),
            nrBandwidthMHz: nrBandwidth,
            nrSignal: nrSignal,
            nrGlobalCellID: nrGlobalCellID,
            nrPhysicalCellID: nrBand == nil ? nil : nrPCI,
            nrPrimaryCell: nrPrimaryCell,
            nrSecondaryCells: nrSecondaryCells.filter {
                $0.nrarfcn != nrPrimaryCell?.nrarfcn
            },
            lteBand: lteBand,
            lteChannel: lteBand == nil ? nil : effectiveLTEChannel.map(String.init),
            lteBandwidthMHz: primary?.bandwidthMHz,
            lteSignal: lteSignal,
            lteGlobalCellID: lteBand == nil ? nil : boundedPositiveUInt64(
                object["cell_id"],
                maximum: maximumLTECellID
            ),
            ltePhysicalCellID: lteBand == nil ? nil : effectiveLTEPCI,
            ltePrimaryCell: primary,
            lteSecondaryCells: ca.secondary,
            unparsedLTECASignal: cleanString(object["ltecasig"]),
            unparsedNRCA: cleanString(object["nrca"])
        )
    }

    /// Convenience for fixture tests. Accepts either the raw netinfo object or
    /// the complete one-element UBus batch response.
    static func parse(data: Data) throws -> MC7530RadioInfo {
        let value = try JSONDecoder().decode(ZTEJSONValue.self, from: data)
        return try parse(value)
    }

    static func makeSnapshot(
        from payload: ZTEJSONValue,
        host: String,
        interfaceName: String?,
        now: Date = Date()
    ) throws -> DeviceSnapshot {
        try parse(payload).snapshot(host: host, interfaceName: interfaceName, now: now)
    }

    private static func unwrapObject(_ value: ZTEJSONValue) -> [String: ZTEJSONValue]? {
        if let object = value.objectValue { return object }
        guard let outer = value.arrayValue else { return nil }

        // Raw UBus result: [0, {...}]
        if outer.first?.int64Value == 0, outer.count > 1 {
            return outer[1].objectValue
        }
        // Complete batch: [{"result":[0,{...}]}]
        if outer.count == 1,
           let reply = outer[0].objectValue,
           let result = reply["result"]?.arrayValue,
           result.first?.int64Value == 0,
           result.count > 1 {
            return result[1].objectValue
        }
        return nil
    }

    private static func systemMode(networkType: String?, hasActiveNR: Bool) -> NRSystemMode? {
        guard hasActiveNR, let networkType else { return nil }
        let normalized = networkType.uppercased().filter(\.isLetter)
        if normalized.contains("ENDC") || normalized.contains("NSA") { return .nsa }
        if normalized == "SA"
            || (normalized.hasSuffix("SA") && normalized.contains("G")) {
            return .sa
        }
        return nil
    }

    private static func parseLTECarriers(
        _ raw: String?,
        secondarySignalRaw: String?,
        primarySignal: RadioSignal
    ) -> (primary: LTECarrier?, secondary: [LTECarrier]) {
        guard let raw else { return (nil, []) }
        var primary: LTECarrier?
        var secondary: [LTECarrier] = []
        let signalEntries = secondarySignalRaw?
            .split(separator: ";", omittingEmptySubsequences: true)
            .map(String.init) ?? []

        for (entryIndex, entry) in raw
            .split(separator: ";", omittingEmptySubsequences: true)
            .enumerated() {
            let fields = entry.split(separator: ",", omittingEmptySubsequences: false)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            guard fields.count >= 5,
                  let pci = UInt16(fields[0]),
                  ltePCIRange.contains(pci),
                  let band = normalizeLTEBand(fields[1]),
                  let role = Int(fields[2]),
                  let earfcn = UInt32(fields[3]),
                  lteEARFCNRange.contains(earfcn),
                  let bandwidth = Double(fields[4]),
                  lteBandwidthsMHz.contains(bandwidth)
            else { continue }

            if role == 0, primary == nil {
                primary = LTECarrier(
                    role: .primary,
                    band: band,
                    earfcn: earfcn,
                    bandwidthMHz: bandwidth,
                    physicalCellID: pci,
                    state: .active,
                    signal: primarySignal
                )
            } else if role != 0 {
                let signal = parseLTESecondarySignal(
                    entryIndex > 0 && signalEntries.indices.contains(entryIndex - 1)
                        ? signalEntries[entryIndex - 1]
                        : nil
                )
                secondary.append(LTECarrier(
                    role: .secondary(index: secondary.count + 1),
                    band: band,
                    earfcn: earfcn,
                    bandwidthMHz: bandwidth,
                    physicalCellID: pci,
                    state: signal.state,
                    signal: signal.metrics
                ))
            }
        }
        return (primary, secondary)
    }

    /// `ltecasig` contains one record per LTE SCell, in the same order as the
    /// non-primary `lteca` records: `rsrp,rsrq,snr,rssi,ulConfigured,state;`.
    /// The retail Web UI defines state 2 as active and state 1 as non-active.
    private static func parseLTESecondarySignal(
        _ raw: String?
    ) -> (state: RadioCarrierState, metrics: RadioSignal) {
        guard let raw else { return (.unknown, .empty) }
        let fields = raw.split(separator: ",", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        guard fields.count >= 6 else { return (.unknown, .empty) }

        let state: RadioCarrierState = switch Int(fields[5]) {
        case 2: .active
        case 1: .configured
        default: .unknown
        }
        let rsrp = Double(fields[0])
        let rssi = Double(fields[3])
        if rsrp.map({ $0 <= -255 }) == true || rssi == 0 {
            return (state, .empty)
        }
        return (
            state,
            RadioSignal(
                rsrpDBm: roundedIntegerText(fields[0], range: -160 ... -40),
                rsrqDB: doubleText(fields[1], range: -40 ... 0),
                rssiDBm: roundedIntegerText(fields[3], range: -140 ... -20),
                snrDB: doubleText(fields[2], range: -30 ... 50)
            )
        )
    }

    /// MC7530CA reports NR component carriers as semicolon-separated
    /// records. A verified unit reports SCells in this layout:
    /// `vendor,pci,state,band,nrarfcn,bandwidth,vendor,rsrp,rsrq,snr,rssi;`.
    /// The retail Web UI defines state 2 as active and state 1 as non-active.
    /// Only the stable identity fields are mandatory; unavailable signal
    /// columns are ignored independently so one bad metric cannot hide a CC.
    private static func parseNRSecondaryCarriers(_ raw: String?) -> [NRCarrier] {
        guard let raw else { return [] }
        var secondary: [NRCarrier] = []
        var seen = Set<String>()

        for entry in raw.split(separator: ";", omittingEmptySubsequences: true) {
            let fields = entry.split(separator: ",", omittingEmptySubsequences: false)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            guard fields.count >= 6,
                  let band = normalizeNRBand(fields[3]),
                  let nrarfcn = UInt32(fields[4]),
                  nrARFCNRange.contains(nrarfcn),
                  let bandwidth = bandwidthText(fields[5]),
                  nrBandwidthsMHz.contains(bandwidth)
            else { continue }
            let pci = uint16Text(fields[1], range: nrPCIRange)
            let state: RadioCarrierState = switch Int(fields[2]) {
            case 2: .active
            case 1: .configured
            default: .unknown
            }
            guard seen.insert("\(band)-\(nrarfcn)-\(pci.map(String.init) ?? "-")").inserted else {
                continue
            }

            let signal = parseNRSecondarySignal(fields)
            let carrier = NRCarrier(
                role: .secondary(index: secondary.count + 1),
                band: band,
                nrarfcn: nrarfcn,
                bandwidthMHz: bandwidth,
                physicalCellID: pci,
                state: state,
                signal: signal
            )

            secondary.append(carrier)
        }
        return secondary
    }

    private static func parseNRSecondarySignal(_ fields: [String]) -> RadioSignal {
        let rsrpText = field(fields, at: 7)
        let rsrqText = field(fields, at: 8)
        let snrText = field(fields, at: 9)
        let rssiText = field(fields, at: 10)
        if let rsrpText,
           let rsrqText,
           let snrText,
           let rssiText,
           let rsrp = Double(rsrpText),
           let rsrq = Double(rsrqText),
           let snr = Double(snrText),
           let rssi = Double(rssiText),
           rsrp <= -140,
           rsrq <= -43,
           snr <= -23,
           rssi <= -120 {
            return .empty
        }
        return RadioSignal(
            rsrpDBm: roundedIntegerText(rsrpText, range: -160 ... -40),
            rsrqDB: doubleText(rsrqText, range: -43 ... 0),
            rssiDBm: roundedIntegerText(rssiText, range: -140 ... -20),
            snrDB: doubleText(snrText, range: -30 ... 50)
        )
    }

    private static func cleanString(_ value: ZTEJSONValue?) -> String? {
        guard let raw = value?.stringValue?
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              raw != "-",
              raw.lowercased() != "null"
        else { return nil }
        return raw
    }

    private static func normalizeLTEBand(_ value: String?) -> String? {
        guard var value = value?.uppercased().trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else { return nil }
        value = value.replacingOccurrences(of: "LTE", with: "")
        value = value.replacingOccurrences(of: "BAND", with: "")
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("B") { value.removeFirst() }
        guard let band = Int(value), band > 0 else { return nil }
        return "B\(band)"
    }

    private static func normalizeNRBand(_ value: String?) -> String? {
        guard var value = value?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              value != "0"
        else { return nil }
        value = value.replacingOccurrences(of: "nr5g", with: "")
        value = value.replacingOccurrences(of: "band", with: "")
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("n") { value.removeFirst() }
        guard let band = Int(value), band > 0 else { return nil }
        return "n\(band)"
    }

    private static func finiteDouble(_ value: ZTEJSONValue?) -> Double? {
        value?.doubleValue
    }

    private static func field(_ values: [String], at index: Int) -> String? {
        values.indices.contains(index) ? values[index] : nil
    }

    private static func bandwidthText(_ value: String) -> Double? {
        Double(value.lowercased().replacingOccurrences(of: "mhz", with: ""))
    }

    private static func uint16Text(_ value: String, range: ClosedRange<UInt16>) -> UInt16? {
        guard let result = UInt16(value), range.contains(result) else { return nil }
        return result
    }

    private static func integerText(_ value: String?, range: ClosedRange<Int>) -> Int? {
        guard let value, let number = Double(value), number.isFinite else { return nil }
        let rounded = number.rounded()
        guard rounded == number,
              let result = Int(exactly: rounded),
              range.contains(result)
        else { return nil }
        return result
    }

    private static func roundedIntegerText(_ value: String?, range: ClosedRange<Int>) -> Int? {
        guard let value,
              let number = Double(value),
              number.isFinite,
              number >= Double(range.lowerBound),
              number <= Double(range.upperBound),
              let result = Int(exactly: number.rounded())
        else { return nil }
        return result
    }

    private static func doubleText(_ value: String?, range: ClosedRange<Double>) -> Double? {
        guard let value, let result = Double(value), result.isFinite, range.contains(result) else {
            return nil
        }
        return result
    }

    private static func standardBandwidth(
        _ value: ZTEJSONValue?,
        allowed: Set<Double>
    ) -> Double? {
        guard let result = finiteDouble(value), allowed.contains(result) else { return nil }
        return result
    }

    private static func boundedDouble(
        _ value: ZTEJSONValue?,
        range: ClosedRange<Double>
    ) -> Double? {
        guard let result = finiteDouble(value), range.contains(result) else { return nil }
        return result
    }

    private static func boundedInteger(
        _ value: ZTEJSONValue?,
        range: ClosedRange<Int>
    ) -> Int? {
        guard let raw = value?.int64Value,
              let result = Int(exactly: raw),
              range.contains(result)
        else { return nil }
        return result
    }

    private static func boundedUInt16(
        _ value: ZTEJSONValue?,
        range: ClosedRange<UInt16>
    ) -> UInt16? {
        guard let raw = value?.int64Value,
              let result = UInt16(exactly: raw),
              range.contains(result)
        else { return nil }
        return result
    }

    private static func boundedUInt32(
        _ value: ZTEJSONValue?,
        range: ClosedRange<UInt32>
    ) -> UInt32? {
        guard let raw = value?.int64Value,
              let result = UInt32(exactly: raw),
              range.contains(result)
        else { return nil }
        return result
    }

    private static func boundedPositiveUInt64(
        _ value: ZTEJSONValue?,
        maximum: UInt64
    ) -> UInt64? {
        guard let raw = value?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              let result = UInt64(raw),
              result > 0,
              result <= maximum
        else { return nil }
        return result
    }

    private static func formattedMCC(_ value: ZTEJSONValue?) -> String? {
        guard let raw = cleanString(value), let number = Int(raw), number >= 0 else { return nil }
        return String(format: "%03d", number)
    }

    private static func formattedMNC(_ value: ZTEJSONValue?) -> String? {
        guard let raw = cleanString(value), let number = Int(raw), number >= 0 else { return nil }
        if raw.count == 2 || raw.count == 3 { return raw }
        return String(format: number < 100 ? "%02d" : "%03d", number)
    }
}
