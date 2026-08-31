import AppKit
import Foundation
import ServiceManagement

@MainActor
final class StatusModel: ObservableObject {
    @Published private(set) var snapshot = DeviceSnapshot.empty
    @Published private(set) var connectionState: ConnectionState = .connecting
    @Published private(set) var lastError: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var menuBarTitle = "Cellular …"

    @Published var host: String
    @Published var username: String
    @Published var password: String
    @Published var refreshInterval: Double
    @Published var menuBarStyle: MenuBarStyle

    private let client = VOSClient()
    private var pollingTask: Task<Void, Never>?
    private var consecutiveFailures = 0
    private var candidateTitle: String?
    private var candidateTitleCount = 0
    private let demoMode: Bool

    private enum Key {
        static let host = "deviceHost"
        static let username = "sshUsername"
        static let password = "sshPassword"
        static let interval = "refreshInterval"
        static let intervalSchema = "refreshIntervalSchema"
        static let menuStyle = "menuBarStyle"
    }

    private static let refreshIntervals = [1.0, 5.0, 10.0, 15.0, 30.0, 60.0]
    private static let currentIntervalSchema = 1

    init(defaults: UserDefaults = .standard) {
        demoMode = ProcessInfo.processInfo.environment["SIGNAL_STATUS_DEMO"] == "1" ||
            ProcessInfo.processInfo.arguments.contains("--demo")
        host = defaults.string(forKey: Key.host) ?? "192.168.225.1"
        username = defaults.string(forKey: Key.username) ?? "root"
        password = defaults.string(forKey: Key.password) ?? "oelinux123"
        let storedInterval = defaults.double(forKey: Key.interval)
        let storedSchema = defaults.integer(forKey: Key.intervalSchema)
        let resolvedInterval = storedSchema < Self.currentIntervalSchema
            ? 30
            : (Self.refreshIntervals.contains(storedInterval) ? storedInterval : 30)
        refreshInterval = resolvedInterval
        if storedInterval != resolvedInterval || storedSchema != Self.currentIntervalSchema {
            defaults.set(resolvedInterval, forKey: Key.interval)
            defaults.set(Self.currentIntervalSchema, forKey: Key.intervalSchema)
        }
        menuBarStyle = MenuBarStyle(rawValue: defaults.string(forKey: Key.menuStyle) ?? "") ?? .detailed

        if demoMode {
            snapshot = DeviceSnapshot(
                host: "192.168.225.1",
                interfaceName: "en12",
                operatorName: "TELUS",
                mcc: "302",
                mnc: "220",
                nrSystemMode: .nsa,
                nrBand: "n78",
                nrChannel: "640608",
                nrBandwidthMHz: 50,
                nrRaw: "NR5G BAND 78, NR-ARFCN 640608",
                nrSignalDBm: -102,
                lteBand: "B2",
                lteChannel: "900",
                lteBandwidthMHz: 20,
                lteRaw: "LTE BAND 2, EARFCN 900",
                lteSignalDBm: -109,
                lteSecondaryCells: ["B66"],
                moduleVersion: "0R05",
                deviceFirmware: "326.73_0R19",
                updatedAt: Date()
            )
            connectionState = .online
            menuBarTitle = snapshot.detailedMenuTitle
            return
        }

        Task { [weak self] in
            self?.start()
        }
    }

    deinit {
        pollingTask?.cancel()
    }

    var statusSymbol: String {
        switch connectionState {
        case .online: return "antenna.radiowaves.left.and.right"
        case .connecting: return "antenna.radiowaves.left.and.right"
        case .stale: return "exclamationmark.triangle"
        case .disconnected, .authenticationFailed, .qmiUnavailable:
            return "antenna.radiowaves.left.and.right.slash"
        }
    }

    var launchAtLogin: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    func start() {
        guard !demoMode, pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refresh()
                let interval = UInt64(max(1, self.refreshInterval) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: interval)
            }
        }
    }

    func refreshNow() {
        Task { [weak self] in
            await self?.refresh()
        }
    }

    func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(host.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Key.host)
        defaults.set(username, forKey: Key.username)
        defaults.set(password, forKey: Key.password)
        defaults.set(refreshInterval, forKey: Key.interval)
        defaults.set(menuBarStyle.rawValue, forKey: Key.menuStyle)
        updateMenuTitle(force: true)
        consecutiveFailures = 0
        connectionState = .connecting
        lastError = nil
        refreshNow()
    }

    func setLaunchAtLogin(_ enabled: Bool) throws {
        guard #available(macOS 13.0, *) else { return }
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
        objectWillChange.send()
    }

    func copyDiagnostics() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(snapshot.diagnostics, forType: .string)
    }

    func openWebUI() {
        let value = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = value.contains("://") ? value : "http://\(value)"
        if let url = URL(string: candidate) {
            NSWorkspace.shared.open(url)
        }
    }

    func showAbout() {
        let marketingVersion = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "1.0.0"
        let credits = NSMutableAttributedString(
            string: "Author: Maigougou\n\n",
            attributes: [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.labelColor
            ]
        )
        credits.append(NSAttributedString(
            string: "🇨🇦\n",
            attributes: [.font: NSFont.systemFont(ofSize: 30)]
        ))
        credits.append(NSAttributedString(
            string: "Made in Canada\n\n",
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        ))
        if let url = URL(string: "https://github.com/maigougou/cellular-modem-monitor") {
            let link = NSMutableAttributedString(
                string: "GitHub",
                attributes: [
                    .link: url,
                    .foregroundColor: NSColor.linkColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ]
            )
            credits.append(link)
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        credits.addAttribute(
            .paragraphStyle,
            value: paragraph,
            range: NSRange(location: 0, length: credits.length)
        )

        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .applicationName: "Cellular Modem Monitor",
            .version: "",
            .applicationVersion: marketingVersion,
            .credits: credits
        ])
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let configuration = DeviceConfiguration(
            host: host,
            username: username,
            password: password,
            refreshInterval: refreshInterval
        )

        do {
            let latest = try await client.fetchSnapshot(configuration: configuration)
            snapshot = latest
            consecutiveFailures = 0
            connectionState = .online
            lastError = nil
            updateMenuTitle(force: snapshot.updatedAt == .distantPast)
        } catch {
            consecutiveFailures += 1
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            if error as? VOSClientError == .authenticationFailed {
                connectionState = .authenticationFailed
            } else if let clientError = error as? VOSClientError,
                      case .qmiUnavailable = clientError {
                connectionState = .qmiUnavailable
            } else if consecutiveFailures >= 3 {
                connectionState = .disconnected
            } else if snapshot.hasRadioData {
                connectionState = .stale
            } else {
                connectionState = .connecting
            }
            if consecutiveFailures >= 3 || !snapshot.hasRadioData {
                updateMenuTitle(force: true)
            }
        }
    }

    private func updateMenuTitle(force: Bool) {
        let proposed: String
        if connectionState == .disconnected || connectionState == .authenticationFailed || connectionState == .qmiUnavailable {
            proposed = "Cellular —"
        } else if !snapshot.hasRadioData {
            proposed = "Cellular …"
        } else {
            switch menuBarStyle {
            case .detailed: proposed = snapshot.detailedMenuTitle
            case .compact: proposed = snapshot.compactMenuTitle
            case .iconOnly: proposed = ""
            }
        }

        if force || menuBarTitle.hasPrefix("Cellular") {
            menuBarTitle = proposed
            candidateTitle = nil
            candidateTitleCount = 0
            return
        }

        if candidateTitle == proposed {
            candidateTitleCount += 1
        } else {
            candidateTitle = proposed
            candidateTitleCount = 1
        }
        if candidateTitleCount >= 2 {
            menuBarTitle = proposed
            candidateTitle = nil
            candidateTitleCount = 0
        }
    }
}
