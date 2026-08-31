import Foundation

enum ConnectionState: Equatable, Sendable {
    case connecting
    case online
    case stale
    case disconnected
    case authenticationFailed
    case qmiUnavailable

    var label: String {
        switch self {
        case .connecting: return "Connecting"
        case .online: return "Online"
        case .stale: return "Stale"
        case .disconnected: return "Disconnected"
        case .authenticationFailed: return "SSH login failed"
        case .qmiUnavailable: return "QMI unavailable"
        }
    }
}

enum NRSystemMode: String, Equatable, Sendable {
    case sa = "SA"
    case nsa = "NSA"
}

enum MenuBarStyle: String, CaseIterable, Identifiable, Sendable {
    case detailed
    case compact
    case iconOnly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .detailed: return "Detailed"
        case .compact: return "Compact"
        case .iconOnly: return "Icon only"
        }
    }
}

struct DeviceConfiguration: Equatable, Sendable {
    var host: String
    var username: String
    var password: String
    var refreshInterval: TimeInterval

    var sshHost: String? { baseURL?.host }

    var baseURL: URL? {
        let value = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        let candidate = value.contains("://") ? value : "http://\(value)"
        guard let components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let hostname = components.host,
              Self.isLocalHost(hostname)
        else {
            return nil
        }

        var normalized = components
        normalized.path = ""
        normalized.query = nil
        normalized.fragment = nil
        return normalized.url
    }

    static func isLocalHost(_ host: String) -> Bool {
        let lower = host.lowercased()
        if lower == "localhost" || lower.hasSuffix(".local") { return true }

        let parts = lower.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, parts.allSatisfy({ 0...255 ~= $0 }) else { return false }
        if parts[0] == 10 || parts[0] == 127 || parts[0] == 169 && parts[1] == 254 { return true }
        if parts[0] == 192 && parts[1] == 168 { return true }
        if parts[0] == 172 && (16...31).contains(parts[1]) { return true }
        if parts[0] == 100 && (64...127).contains(parts[1]) { return true }
        return false
    }
}

struct DeviceSnapshot: Equatable, Sendable {
    var host: String
    var interfaceName: String?
    var operatorName: String?
    var mcc: String?
    var mnc: String?
    var nrSystemMode: NRSystemMode?

    var nrBand: String?
    var nrChannel: String?
    var nrBandwidthMHz: Double?
    var nrRaw: String?
    var nrSignalDBm: Int?

    var lteBand: String?
    var lteChannel: String?
    var lteBandwidthMHz: Double?
    var lteRaw: String?
    var lteSignalDBm: Int?
    var lteSecondaryCells: [String]

    var moduleVersion: String?
    var deviceFirmware: String?
    var updatedAt: Date

    static let empty = DeviceSnapshot(
        host: "192.168.225.1",
        interfaceName: nil,
        operatorName: nil,
        mcc: nil,
        mnc: nil,
        nrSystemMode: nil,
        nrBand: nil,
        nrChannel: nil,
        nrBandwidthMHz: nil,
        nrRaw: nil,
        nrSignalDBm: nil,
        lteBand: nil,
        lteChannel: nil,
        lteBandwidthMHz: nil,
        lteRaw: nil,
        lteSignalDBm: nil,
        lteSecondaryCells: [],
        moduleVersion: nil,
        deviceFirmware: nil,
        updatedAt: .distantPast
    )

    var hasRadioData: Bool { nrBand != nil || lteBand != nil }

    var modeLabel: String {
        if let nrSystemMode, nrBand != nil { return nrSystemMode.rawValue }
        switch (nrBand, lteBand) {
        case (.some, .some): return "NR + LTE"
        case (.some, .none): return "NR"
        case (.none, .some): return "LTE"
        case (.none, .none): return "Searching"
        }
    }

    var bandCombination: String {
        var parts: [String] = []
        if let nrBand { parts.append(nrBand) }
        if let lteBand { parts.append(lteBand) }
        return parts.isEmpty ? "—" : parts.joined(separator: "+")
    }

    var displayCombination: String {
        var parts: [String] = []
        if let nrBand { parts.append(nrBand) }
        if let lteBand { parts.append(lteBand) }
        return parts.isEmpty ? "No active band" : parts.joined(separator: "  +  ")
    }

    var detailedMenuTitle: String {
        switch (nrBand, lteBand) {
        case let (.some(nr), .some(lte)):
            if nrSystemMode == .sa { return "SA \(nr)" }
            if nrSystemMode == .nsa { return "NSA \(nr)+\(lte)" }
            return "NR \(nr)+\(lte)"
        case let (.some(nr), .none):
            return "\(nrSystemMode?.rawValue ?? "NR") \(nr)"
        case let (.none, .some(lte)): return "LTE \(lte)"
        case (.none, .none): return "Cellular —"
        }
    }

    var compactMenuTitle: String {
        hasRadioData ? bandCombination : "Cellular —"
    }

    var plmn: String? {
        guard let mcc, let mnc, !mcc.isEmpty, !mnc.isEmpty else { return nil }
        return "\(mcc)-\(mnc)"
    }

    var diagnostics: String {
        var lines = [
            "Cellular Modem Monitor",
            "Updated: \(updatedAt.formatted(date: .numeric, time: .standard))",
            "Host: \(host)",
            "Interface: \(interfaceName ?? "—")",
            "Operator: \(operatorName ?? "—")",
            "PLMN: \(plmn ?? "—")",
            "Mode: \(nrSystemMode?.rawValue ?? modeLabel)",
            "Mode source: Qualcomm DSD over SSH/QRTR QMI",
            "NR: \(nrRaw ?? nrBand ?? "—")",
            "LTE: \(lteRaw ?? lteBand ?? "—")",
            "LTE CA: \(lteSecondaryCells.isEmpty ? "—" : lteSecondaryCells.joined(separator: ", "))",
            "NR signal: \(nrSignalDBm.map { "\($0) dBm" } ?? "—")",
            "LTE signal: \(lteSignalDBm.map { "\($0) dBm" } ?? "—")"
        ]
        if let nrBandwidthMHz { lines.append("NR bandwidth: \(Self.bandwidthText(nrBandwidthMHz))") }
        if let lteBandwidthMHz { lines.append("LTE bandwidth: \(Self.bandwidthText(lteBandwidthMHz))") }
        if let moduleVersion { lines.append("Module: \(moduleVersion)") }
        if let deviceFirmware { lines.append("Device firmware: \(deviceFirmware)") }
        return lines.joined(separator: "\n")
    }

    static func bandwidthText(_ value: Double) -> String {
        value.rounded() == value ? "\(Int(value)) MHz" : "\(value) MHz"
    }
}

enum BandParser {
    static func band(from raw: String?, radio: RadioKind) -> String? {
        guard let value = clean(raw) else { return nil }
        let patterns: [String]
        switch radio {
        case .nr:
            patterns = [#"(?i)NR5G\s*BAND\s*(\d+)"#, #"(?i)\bn\s*(\d+)\b"#, #"(?i)\bBAND\s*(\d+)\b"#]
        case .lte:
            patterns = [#"(?i)LTE\s*BAND\s*(\d+)"#, #"(?i)\bB\s*(\d+)\b"#, #"(?i)\bBAND\s*(\d+)\b"#]
        }
        guard let number = firstCapture(in: value, patterns: patterns) else { return nil }
        return radio == .nr ? "n\(number)" : "B\(number)"
    }

    static func channel(from raw: String?, radio: RadioKind) -> String? {
        guard let value = clean(raw) else { return nil }
        let patterns: [String]
        switch radio {
        case .nr:
            patterns = [#"(?i)(?:NR[-_ ]?ARFCN|NRARFCN)\s*[:=]?\s*(\d+)"#]
        case .lte:
            patterns = [#"(?i)(?:EARFCN|LTE[-_ ]?ARFCN)\s*[:=]?\s*(\d+)"#]
        }
        return firstCapture(in: value, patterns: patterns)
    }

    static func clean(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              !["NA", "N/A", "NONE", "NULL", "0", "-"].contains(value.uppercased())
        else { return nil }
        return value
    }

    private static func firstCapture(in value: String, patterns: [String]) -> String? {
        let range = NSRange(value.startIndex..., in: value)
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: value, range: range),
                  match.numberOfRanges > 1,
                  let capture = Range(match.range(at: 1), in: value)
            else { continue }
            return String(value[capture])
        }
        return nil
    }
}

enum RadioKind: Hashable, Sendable {
    case nr
    case lte
}
