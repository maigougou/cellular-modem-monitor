import AppKit
import Foundation
import ServiceManagement

enum ControlPresentationInvalidation: Equatable, Sendable {
    case none
    case operatorContext
    case all

    static func transition(
        previousModemID: String?,
        nextModemID: String,
        previousEndpoint: ScopedEndpoint?,
        nextEndpoint: ScopedEndpoint,
        previousPLMN: String?,
        nextPLMN: String?
    ) -> ControlPresentationInvalidation {
        guard previousModemID == nextModemID,
              previousEndpoint == nextEndpoint
        else { return .all }
        guard previousPLMN == nextPLMN else { return .operatorContext }
        return .none
    }
}

enum ModemOperationInterruption {
    static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError
    }

    /// Discovery is intentionally nonthrowing and may translate a cancelled
    /// probe into a timeout/no-match result. The task flag therefore remains
    /// authoritative for status refreshes even when the final error was
    /// wrapped by a lower layer.
    static func shouldIgnoreRefreshFailure(
        _ error: Error,
        taskIsCancelled: Bool
    ) -> Bool {
        taskIsCancelled || isCancellation(error)
    }
}

@MainActor
final class StatusModel: ObservableObject {
    @Published private(set) var snapshot = DeviceSnapshot.empty
    @Published private(set) var connectionState: ConnectionState = .connecting
    @Published private(set) var lastError: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var menuBarTitle = "Cellular …"
    @Published private(set) var operatorSelection: OperatorSelection?
    @Published private(set) var scannedNetworks: [CellularNetwork] = []
    @Published private(set) var controlState: ModemControlState?
    @Published private(set) var controlOperation: NetworkControlOperation?
    @Published private(set) var controlError: String?
    @Published private(set) var controlNotice: String?
    @Published private(set) var activeModem: ActiveModem?
    @Published private(set) var settingsError: String?

    @Published var modemSelection: ModemSelection
    @Published var host: String
    @Published var username: String
    @Published var password: String
    @Published var zteHost: String
    @Published var ztePassword: String
    @Published var refreshInterval: Double
    @Published var menuBarStyle: MenuBarStyle
    @Published var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: Key.language)
            updateMenuTitle(force: true)
        }
    }

    private let coordinator: ModemCoordinator?
    private let credentialStore: any CredentialStoring
    private let backendSetupError: Error?
    private let defaults: UserDefaults
    private var pollingTask: Task<Void, Never>?
    private var pollingGeneration: UInt64 = 0
    private var settingsGeneration: UInt64 = 0
    private var refreshCoalescer = RefreshCoalescer()
    private var consecutiveFailures = 0
    private var candidateTitle: String?
    private var candidateTitleCount = 0
    private let demoMode: Bool
    private var lastSuccessfulScopeKey: String?
    private var lastSuccessfulEndpoint: ModemEndpointPreference?
    private var credentialLoadStates: [ModemKind: CredentialLoadState] = [:]
    private var queuedControlToken: UUID?

    /// Immutable context captured synchronously at the UI action boundary.
    /// The queued Task must never reinterpret an action for a later modem.
    private struct ControlActionContext: Sendable {
        let token: UUID
        let modemID: String
        let endpoint: ScopedEndpoint
        let settingsGeneration: UInt64
        let credentials: ModemConnectionCredentials
    }

    private enum Key {
        static let host = "deviceHost"
        static let username = "sshUsername"
        // Legacy only. New versions migrate this value to the private local
        // credential file and then delete it from UserDefaults.
        static let password = "sshPassword"
        static let zteHost = "zteDeviceHost"
        static let modemSelection = "modemSelection"
        static let lastSuccessfulScopeKey = "lastSuccessfulModemScopeKey"
        static let lastSuccessfulEndpoint = "lastSuccessfulModemEndpoint"
        static let interval = "refreshInterval"
        static let intervalSchema = "refreshIntervalSchema"
        static let menuStyle = "menuBarStyle"
        static let language = "appLanguage"
    }

    private static let refreshIntervals = [1.0, 5.0, 10.0, 15.0, 30.0, 60.0]
    private static let currentIntervalSchema = 1
    private static let vosCredentialAccount = "vos-5g-ssh"
    private static let zteCredentialAccount = "zte-mc7530ca-web-admin"
    private static let defaultVOSHost = "192.168.225.1"
    private static let defaultZTEHost = "192.168.254.1"

    init(
        defaults: UserDefaults = .standard,
        credentialStore: any CredentialStoring = LocalCredentialStore.shared
    ) {
        self.defaults = defaults
        self.credentialStore = credentialStore

        let vosClient = VOSClient()
        do {
            let registry = try ModemBackendRegistry.standard(vosClient: vosClient)
            coordinator = ModemCoordinator(registry: registry)
            backendSetupError = nil
        } catch {
            coordinator = nil
            backendSetupError = error
        }

        let arguments = ProcessInfo.processInfo.arguments
        let isSADemo = arguments.contains("--demo-sa")
        let showsDemoControls = arguments.contains("--demo-controls")
        demoMode = ProcessInfo.processInfo.environment["SIGNAL_STATUS_DEMO"] == "1" ||
            arguments.contains("--demo") || arguments.contains("--demo-nsa") || isSADemo || showsDemoControls
        modemSelection = ModemSelection(
            rawValue: defaults.string(forKey: Key.modemSelection) ?? ""
        ) ?? .automatic
        host = defaults.string(forKey: Key.host) ?? Self.defaultVOSHost
        username = defaults.string(forKey: Key.username) ?? "root"
        var credentialLoadErrors: [String] = []
        var initialCredentialStates: [ModemKind: CredentialLoadState] = [:]
        do {
            let result = try Self.loadVOSCredential(
                defaults: defaults,
                credentialStore: credentialStore
            )
            password = result.password
            initialCredentialStates[.vos5G] = result.state
            if case let .unavailable(message) = result.state {
                credentialLoadErrors.append(message)
            }
        } catch {
            // An unreadable local file is not the same as a missing item. Do
            // not overwrite a credential that may still exist on disk.
            password = ""
            let message = error.localizedDescription
            initialCredentialStates[.vos5G] = .unavailable(message)
            credentialLoadErrors.append(message)
        }
        zteHost = defaults.string(forKey: Key.zteHost) ?? Self.defaultZTEHost
        do {
            let loadedPassword = try credentialStore.password(for: Self.zteCredentialAccount) ?? ""
            ztePassword = loadedPassword
            initialCredentialStates[.zteMC7530CA] = .loaded(loadedPassword)
        } catch {
            ztePassword = ""
            let message = error.localizedDescription
            initialCredentialStates[.zteMC7530CA] = .unavailable(message)
            credentialLoadErrors.append(message)
        }
        lastSuccessfulScopeKey = defaults.string(forKey: Key.lastSuccessfulScopeKey)
        lastSuccessfulEndpoint = Self.loadLastSuccessfulEndpoint(defaults: defaults)
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
        language = AppLanguage.resolved(
            storedValue: defaults.string(forKey: Key.language),
            preferredLanguages: Locale.preferredLanguages
        )
        credentialLoadStates = initialCredentialStates
        if !credentialLoadErrors.isEmpty {
            settingsError = credentialLoadErrors.joined(separator: "; ")
        }

        if demoMode {
            modemSelection = .vos5G
            snapshot = DeviceSnapshot(
                host: "192.168.225.1",
                interfaceName: "en12",
                operatorName: "TELUS",
                mcc: "302",
                mnc: "220",
                nrSystemMode: isSADemo ? .sa : .nsa,
                nrBand: "n78",
                nrChannel: "640608",
                nrBandwidthMHz: 50,
                nrRaw: "NR5G BAND 78, NR-ARFCN 640608",
                nrSignal: RadioSignal(rsrpDBm: -102, rsrqDB: -12, rssiDBm: nil, snrDB: 8.4),
                // Synthetic demo identities; never embed a live user's Cell ID.
                nrGlobalCellID: 0x1234_5678,
                nrPhysicalCellID: 41,
                lteBand: isSADemo ? nil : "B2",
                lteChannel: isSADemo ? nil : "900",
                lteBandwidthMHz: isSADemo ? nil : 20,
                lteRaw: isSADemo ? nil : "LTE BAND 2, EARFCN 900",
                lteSignal: isSADemo
                    ? .empty
                    : RadioSignal(rsrpDBm: -109, rsrqDB: -14, rssiDBm: -74, snrDB: 2.4),
                lteGlobalCellID: isSADemo ? nil : 0x0123_4567,
                ltePhysicalCellID: isSADemo ? nil : 223,
                ltePrimaryCell: isSADemo ? nil : LTECarrier(
                    role: .primary,
                    band: "B2",
                    earfcn: 900,
                    bandwidthMHz: 20,
                    physicalCellID: 223,
                    state: nil,
                    globalCellID: 0x0123_4567,
                    signal: RadioSignal(rsrpDBm: -109, rsrqDB: -14, rssiDBm: -74, snrDB: 2.4)
                ),
                lteSecondaryCells: isSADemo ? [] : [LTECarrier(
                    role: .secondary(index: 1),
                    band: "B66",
                    earfcn: 66_786,
                    bandwidthMHz: 30,
                    physicalCellID: 223,
                    state: .active,
                    signal: RadioSignal(rsrpDBm: -104, rsrqDB: -12.5, rssiDBm: -72, snrDB: nil)
                )],
                lteNeighborCells: showsDemoControls && !isSADemo ? [
                    LTECellNeighbor(
                        band: "B2",
                        earfcn: 925,
                        physicalCellID: 17,
                        signal: RadioSignal(rsrpDBm: -111, rsrqDB: -15, rssiDBm: -79, snrDB: 1.8)
                    )
                ] : [],
                moduleVersion: "0R05",
                deviceFirmware: "326.73_0R19",
                updatedAt: Date()
            )
            activeModem = ActiveModem(
                identity: ModemIdentity(
                    kind: .vos5G,
                    manufacturer: "VOS",
                    model: "VOS 5G"
                ),
                endpoint: ScopedEndpoint(
                    baseURL: URL(string: "http://192.168.225.1")!,
                    interfaceName: "en12",
                    connectionPath: .directUSB
                ),
                capabilities: [.statusRead, .identityRead, .webUI, .vosControls]
            )
            connectionState = .online
            menuBarTitle = snapshot.detailedMenuTitle
            if showsDemoControls {
                operatorSelection = OperatorSelection(
                    mode: .automatic,
                    operatorName: "TELUS",
                    plmn: "302220",
                    accessTechnology: isSADemo ? .nr5GC : .lteNRDualConnectivity
                )
                scannedNetworks = [
                    CellularNetwork(
                        longName: "TELUS",
                        shortName: "TELUS",
                        plmn: "302220",
                        availability: .current,
                        accessTechnologies: [.lte, .lteNRDualConnectivity]
                    ),
                    CellularNetwork(
                        longName: "Bell",
                        shortName: "Bell",
                        plmn: "302610",
                        availability: .available,
                        accessTechnologies: [.lte, .nr5GC]
                    ),
                    CellularNetwork(
                        longName: "Rogers Wireless",
                        shortName: "Rogers",
                        plmn: "302720",
                        availability: .available,
                        accessTechnologies: [.lte, .lteNRDualConnectivity]
                    )
                ]
                controlState = ModemControlState(
                    operatorSelection: operatorSelection,
                    architecture: .automatic,
                    saBands: [77, 78],
                    nsaBands: [77, 78],
                    lteBands: [2, 4, 25, 66],
                    canRestoreDefaults: true,
                    preferenceLifetime: .untilPowerLoss
                )
            }
            return
        }

        menuBarTitle = L10n.text("Cellular …", language: language)

        start()
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

    var isControlBusy: Bool { controlOperation != nil }
    var canRestoreControlDefaults: Bool { controlState?.canRestoreDefaults == true }
    var supportsDeviceControls: Bool {
        activeModem?.capabilities.supportsDeviceControlSurface == true
    }
    var supportsControlSession: Bool {
        activeModem?.capabilities.supportsControlSession == true
    }

    func supportsControl(_ capability: ModemCapability) -> Bool {
        activeModem?.capabilities.contains(capability) == true
    }

    var activeModemName: String {
        activeModem?.identity.displayName ?? L10n.text("Not detected", language: language)
    }

    var activeManagementEndpoint: String {
        if let endpoint = activeModem?.endpoint.baseURL.absoluteString { return endpoint }
        switch modemSelection {
        case .zteMC7530CA: return zteHost
        case .automatic, .vos5G: return snapshot.host
        }
    }

    var activeInterfaceName: String {
        activeModem?.endpoint.interfaceName
            ?? snapshot.interfaceName
            ?? L10n.text("Not detected", language: language)
    }

    var activeConnectionPath: String {
        guard let path = activeModem?.endpoint.connectionPath else {
            return L10n.text("Not detected", language: language)
        }
        let label: String
        switch path {
        case .directUSB: label = "Direct USB"
        case .directEthernet: label = "Direct Ethernet"
        case .routed: label = "Routed"
        case .unknown: label = "Direct link (USB or Ethernet)"
        }
        return L10n.text(label, language: language)
    }

    var activeDataSource: String {
        switch activeModem?.identity.kind {
        case .vos5G: return "SSH → QRTR/QMI"
        case .zteMC7530CA: return L10n.text("Authenticated Web UBus", language: language)
        case nil: return "—"
        }
    }

    func start() {
        guard !demoMode, pollingTask == nil else { return }
        pollingGeneration &+= 1
        let generation = pollingGeneration
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let interval = await self?.pollOnceAndNextInterval() else { return }
                do {
                    try await Task.sleep(nanoseconds: interval)
                } catch {
                    break
                }
            }
            self?.pollingDidFinish(generation: generation)
        }
    }

    func refreshNow() {
        Task { [weak self] in
            await self?.refresh()
        }
    }

    func loadNetworkControls() {
        enqueueControl(.loading, command: nil)
    }

    func scanNetworks() {
        enqueueControl(.scanning, command: .scanNetworks)
    }

    func selectNetwork(_ network: CellularNetwork) {
        enqueueControl(
            .selecting(network.formattedPLMN),
            command: .selectNetwork(network)
        )
    }

    func selectAutomaticNetwork() {
        enqueueControl(.automaticSelection, command: .selectAutomaticNetwork)
    }

    func setNRArchitecture(_ mode: NRArchitectureMode) {
        guard mode != .unavailable else { return }
        enqueueControl(
            .changingArchitecture(mode),
            command: .setArchitecture(mode)
        )
    }

    func lockNRBands(_ bands: Set<Int>) {
        enqueueControl(.lockingNRBands, command: .lockNRBands(bands))
    }

    func lockLTEBands(_ bands: Set<Int>) {
        enqueueControl(.lockingLTEBands, command: .lockLTEBands(bands))
    }

    func restoreAutomaticDefaults() {
        enqueueControl(.restoring, command: .restoreDefaults)
    }

    private func enqueueControl(
        _ operation: NetworkControlOperation,
        command: ModemControlCommand?
    ) {
        guard !demoMode,
              supportsControlSession,
              controlOperation == nil,
              queuedControlToken == nil,
              let activeModem
        else { return }
        let token = UUID()
        let context = ControlActionContext(
            token: token,
            modemID: activeModem.id,
            endpoint: activeModem.endpoint,
            settingsGeneration: settingsGeneration,
            credentials: currentCredentials
        )
        // Reserve the operation synchronously so two UI actions cannot both be
        // queued before either Task receives MainActor time.
        queuedControlToken = token
        controlOperation = operation
        Task { [weak self] in
            await self?.runControl(operation, command: command, context: context)
        }
    }

    @discardableResult
    func saveSettings() -> Bool {
        settingsError = nil
        let savedVOSHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let savedZTEHost = zteHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let previousVOSHost = defaults.string(forKey: Key.host) ?? Self.defaultVOSHost
        let previousZTEHost = defaults.string(forKey: Key.zteHost) ?? Self.defaultZTEHost
        var changedEndpointKinds: Set<ModemKind> = []
        if Self.normalizedManagementURL(previousVOSHost) != Self.normalizedManagementURL(savedVOSHost) {
            changedEndpointKinds.insert(.vos5G)
        }
        if Self.normalizedManagementURL(previousZTEHost) != Self.normalizedManagementURL(savedZTEHost) {
            changedEndpointKinds.insert(.zteMC7530CA)
        }
        let credentialUpdates = CredentialSavePlanner.updates(for: [
            CredentialEdit(
                account: Self.vosCredentialAccount,
                password: password,
                loadState: credentialLoadStates[.vos5G]
                    ?? .unavailable("The VOS credential state is unavailable.")
            ),
            CredentialEdit(
                account: Self.zteCredentialAccount,
                password: ztePassword,
                loadState: credentialLoadStates[.zteMC7530CA]
                    ?? .unavailable("The ZTE credential state is unavailable.")
            )
        ])
        do {
            try CredentialTransaction.apply(credentialUpdates, store: credentialStore)
        } catch {
            settingsError = localizedError(error)
            return false
        }
        for update in credentialUpdates {
            switch update.account {
            case Self.vosCredentialAccount:
                credentialLoadStates[.vos5G] = .loaded(password)
            case Self.zteCredentialAccount:
                credentialLoadStates[.zteMC7530CA] = .loaded(ztePassword)
            default:
                break
            }
        }
        settingsError = unresolvedCredentialLoadError

        if let state = credentialLoadStates[.vos5G], case .loaded = state {
            defaults.removeObject(forKey: Key.password)
        }
        defaults.set(modemSelection.rawValue, forKey: Key.modemSelection)
        defaults.set(savedVOSHost, forKey: Key.host)
        defaults.set(username.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Key.username)
        defaults.set(savedZTEHost, forKey: Key.zteHost)
        defaults.set(refreshInterval, forKey: Key.interval)
        defaults.set(menuBarStyle.rawValue, forKey: Key.menuStyle)
        if let lastKind = lastSuccessfulEndpoint?.kind {
            if changedEndpointKinds.contains(lastKind) { clearLastSuccessfulEndpoint() }
        } else if !changedEndpointKinds.isEmpty {
            clearLastSuccessfulEndpoint()
        }
        updateMenuTitle(force: true)
        settingsGeneration &+= 1
        consecutiveFailures = 0
        connectionState = .connecting
        lastError = nil
        activeModem = nil
        clearControlState()
        Task { [weak self] in
            guard let self else { return }
            if let coordinator = self.coordinator {
                await coordinator.invalidateActiveModem()
            }
            await self.refresh()
        }
        return true
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
        let diagnostics = [
            "Backend: \(activeModem?.identity.kind.rawValue ?? "—")",
            "Device: \(activeModem?.identity.displayName ?? "—")",
            "Endpoint: \(activeManagementEndpoint)",
            "Path: \(activeModem?.endpoint.connectionPath.rawValue ?? "—")",
            snapshot.diagnostics
        ].joined(separator: "\n")
        pasteboard.setString(diagnostics, forType: .string)
    }

    func openWebUI() {
        let fallback = modemSelection == .zteMC7530CA ? zteHost : host
        let value = activeModem?.endpoint.baseURL.absoluteString
            ?? fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = value.contains("://") ? value : "http://\(value)"
        if let url = URL(string: candidate) {
            NSWorkspace.shared.open(url)
        }
    }

    func showAbout() {
        let marketingVersion = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "1.3.4"
        let credits = NSMutableAttributedString(
            string: "\(L10n.text("Author", language: language)): Maigougou\n\n",
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
            string: "\(L10n.text("Made in Canada", language: language))\n\n",
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

    private func pollOnceAndNextInterval() async -> UInt64 {
        await refresh()
        // A rejected credential is actionable in Settings and should not cause
        // repeated SSH/Web login attempts every five seconds. Saving a corrected
        // credential still triggers an immediate refresh.
        let seconds = connectionState == .authenticationFailed
            ? max(refreshInterval, 60)
            : StatusPollingPolicy.interval(
                userInterval: refreshInterval,
                connectionState: connectionState
            )
        return UInt64(seconds * 1_000_000_000)
    }

    private func pollingDidFinish(generation: UInt64) {
        guard pollingGeneration == generation else { return }
        pollingTask = nil
    }

    private func refresh() async {
        guard !Task.isCancelled else { return }
        guard refreshCoalescer.request(
            isRefreshing: isRefreshing,
            isControlBusy: isControlBusy
        ) else { return }

        repeat {
            refreshCoalescer.beginRefresh()
            await performRefresh()
            if Task.isCancelled { return }
        } while refreshCoalescer.shouldDrain(
            isRefreshing: isRefreshing,
            isControlBusy: isControlBusy
        )
    }

    private func performRefresh() async {
        let generation = settingsGeneration
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            if let backendSetupError { throw backendSetupError }
            guard let coordinator else {
                throw ModemCoordinatorError.noMatchingModem
            }
            let result = try await coordinator.read(
                preferences: currentConnectionPreferences,
                credentials: currentCredentials
            )
            // Detached SSH work and nonthrowing discovery can finish after the
            // polling task has been cancelled. Never commit that retired
            // result to the visible model.
            try Task.checkCancellation()
            guard settingsGeneration == generation else { return }
            let latest = result.snapshot
            let previousActiveModemID = activeModem?.id
            let previousActiveEndpoint = activeModem?.endpoint
            let radioAvailabilityChanged = snapshot.hasRadioData != latest.hasRadioData
            let controlInvalidation = ControlPresentationInvalidation.transition(
                previousModemID: previousActiveModemID,
                nextModemID: result.activeModem.id,
                previousEndpoint: previousActiveEndpoint,
                nextEndpoint: result.activeModem.endpoint,
                previousPLMN: snapshot.plmn,
                nextPLMN: latest.plmn
            )
            snapshot = latest
            activeModem = result.activeModem
            switch controlInvalidation {
            case .none:
                break
            case .operatorContext:
                // A powered SIM replacement can leave the USB device and SSH
                // identity unchanged while registration moves to a different
                // PLMN (or temporarily disappears). Do not keep presenting a
                // selection or scan result captured for the previous card.
                // Serving PLMN is not a SIM identity: a normal manual operator
                // change must not discard the physical modem's restore tuple.
                clearOperatorContext()
            case .all:
                clearControlState()
            }
            persistLastSuccessful(result)
            consecutiveFailures = 0
            // During a physical SIM swap QMI remains reachable but may report
            // no serving band while the new card initializes. Treat that as a
            // reconnecting state so polling accelerates to the five-second
            // recovery cadence instead of waiting the full user interval.
            connectionState = latest.hasRadioData ? .online : .connecting
            lastError = nil
            updateMenuTitle(force: snapshot.updatedAt == .distantPast || radioAvailabilityChanged)
        } catch {
            guard !ModemOperationInterruption.shouldIgnoreRefreshFailure(
                error,
                taskIsCancelled: Task.isCancelled
            ) else { return }
            guard settingsGeneration == generation else { return }
            consecutiveFailures += 1
            lastError = localizedError(error)
            if isAuthenticationError(error) {
                connectionState = .authenticationFailed
                activeModem = nil
                clearControlState()
            } else if isQMIUnavailableError(error) {
                connectionState = .qmiUnavailable
                activeModem = nil
                clearControlState()
            } else if consecutiveFailures >= 3 {
                connectionState = .disconnected
                activeModem = nil
                clearControlState()
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

    private func runControl(
        _ operation: NetworkControlOperation,
        command: ModemControlCommand?,
        context: ControlActionContext
    ) async {
        guard queuedControlToken == context.token,
              controlOperation == operation
        else { return }
        defer {
            if queuedControlToken == context.token {
                queuedControlToken = nil
                controlOperation = nil
                refreshNow()
            }
        }
        guard !demoMode, supportsControlSession else { return }
        // Validate the click-time context before doing anything observable.
        // A refresh or Settings save may have completed while the Task was
        // merely waiting to be scheduled.
        guard settingsGeneration == context.settingsGeneration else { return }
        guard activeModem?.id == context.modemID,
              activeModem?.endpoint == context.endpoint
        else {
            controlError = localizedError(ModemControlError.deviceChanged)
            return
        }
        if let command,
           activeModem?.capabilities.contains(command.requiredCapability) != true {
            controlError = localizedError(
                ModemBackendError.unsupportedCapability(command.requiredCapability)
            )
            return
        }
        // Bind the user's action to the currently displayed modem before the
        // first suspension point. A refresh already in flight may replace the
        // active endpoint while this operation waits for it to finish; that
        // must cancel the action, never retarget it to the replacement modem.
        let expectedModemID = context.modemID
        let expectedEndpoint = context.endpoint
        let expectedSettingsGeneration = context.settingsGeneration
        let operationCredentials = context.credentials
        while isRefreshing {
            do {
                try await Task.sleep(nanoseconds: 50_000_000)
            } catch {
                return
            }
        }

        // A Settings save owns the newer UI generation and must not receive an
        // error from the retired operation. A same-generation modem change is
        // still reported to the user as a fail-closed device replacement.
        guard settingsGeneration == expectedSettingsGeneration else { return }
        guard activeModem?.id == expectedModemID,
              activeModem?.endpoint == expectedEndpoint
        else {
            controlError = localizedError(ModemControlError.deviceChanged)
            return
        }

        controlError = nil
        controlNotice = nil
        var openedSession: (any ModemControlSession)?
        do {
            guard let coordinator else { throw ModemCoordinatorError.noMatchingModem }
            let session = try await coordinator.controlSession(credentials: operationCredentials)
            openedSession = session
            let result: ModemControlResult
            if let command {
                result = try await session.perform(command)
            } else {
                result = ModemControlResult(state: try await session.refresh())
            }
            // A returned control result is already authoritative. The session
            // observed no cancellation at any suspension point and may have
            // completed a persistent write, so commit that result rather than
            // discarding it for a cancellation that arrived afterward.
            guard activeModem?.id == expectedModemID,
                  activeModem?.endpoint == expectedEndpoint,
                  settingsGeneration == expectedSettingsGeneration
            else {
                throw ModemControlError.deviceChanged
            }
            applyControlResult(result)
            controlNotice = controlNotice(for: operation, result: result)
        } catch {
            let operationError = error
            // The backend session owns cancellation-safe rollback for any
            // ambiguous persistent write. Once it returns CancellationError,
            // do not turn an intentional interruption into visible failure.
            // Its cleanup may intentionally settle on a different verified
            // state (for example automatic operator selection), so reconcile
            // the panel without starting a second recovery sequence.
            if ModemOperationInterruption.isCancellation(operationError) {
                if let openedSession {
                    await reconcileControlStateAfterCancellation(
                        session: openedSession,
                        expectedModemID: expectedModemID,
                        expectedEndpoint: expectedEndpoint,
                        expectedSettingsGeneration: expectedSettingsGeneration
                    )
                }
                return
            }
            // A settings save owns the new UI/coordinator generation. The old
            // session has already performed its private recovery; do not let
            // its completion clear or annotate the newly selected modem.
            guard settingsGeneration == expectedSettingsGeneration else { return }
            if operationError as? ModemControlError == .deviceChanged {
                clearControlState()
                activeModem = nil
                if let coordinator {
                    await coordinator.invalidateActiveModem()
                }
                guard settingsGeneration == expectedSettingsGeneration else { return }
            } else if let openedSession,
                      activeModem?.id == expectedModemID,
                      activeModem?.endpoint == expectedEndpoint,
                      settingsGeneration == expectedSettingsGeneration {
                // A command can fail after the modem has already completed a
                // verified rollback or a partial restore. Preserve the
                // original error, but refresh the authoritative control state
                // so the panel never remains on a stale pre-error value.
                do {
                    let recovered = try await openedSession.refresh()
                    guard activeModem?.id == expectedModemID,
                          activeModem?.endpoint == expectedEndpoint,
                          settingsGeneration == expectedSettingsGeneration
                    else { throw ModemControlError.deviceChanged }
                    applyControlResult(ModemControlResult(state: recovered))
                } catch {
                    if error as? ModemControlError == .deviceChanged {
                        clearControlState()
                        activeModem = nil
                        if let coordinator {
                            await coordinator.invalidateActiveModem()
                        }
                        guard settingsGeneration == expectedSettingsGeneration else { return }
                    }
                }
            }
            guard settingsGeneration == expectedSettingsGeneration else { return }
            controlError = localizedError(operationError)
        }
    }

    private func reconcileControlStateAfterCancellation(
        session: any ModemControlSession,
        expectedModemID: String,
        expectedEndpoint: ScopedEndpoint,
        expectedSettingsGeneration: UInt64
    ) async {
        guard settingsGeneration == expectedSettingsGeneration,
              activeModem?.id == expectedModemID,
              activeModem?.endpoint == expectedEndpoint
        else { return }

        // The calling operation is cancelled. Run only an authoritative read
        // in a fresh task; backend sessions have already completed any needed
        // write recovery before exposing CancellationError.
        let reconciliation = Task { try await session.refresh() }
        do {
            let reconciled = try await reconciliation.value
            guard settingsGeneration == expectedSettingsGeneration,
                  activeModem?.id == expectedModemID,
                  activeModem?.endpoint == expectedEndpoint
            else { return }
            applyControlResult(ModemControlResult(state: reconciled))
        } catch {
            guard settingsGeneration == expectedSettingsGeneration else { return }
            if error as? ModemControlError == .deviceChanged {
                clearControlState()
                activeModem = nil
                if let coordinator {
                    await coordinator.invalidateActiveModem()
                }
            } else if activeModem?.id == expectedModemID,
                      activeModem?.endpoint == expectedEndpoint {
                // A failed quiet reconciliation must not leave values that no
                // longer describe the modem. The user can reload the controls
                // without being shown the intentional cancellation as an error.
                clearControlState()
            }
        }
    }

    func applyControlResult(_ result: ModemControlResult) {
        controlState = result.state
        // The state is authoritative. A nil selection means the backend has
        // verified that no operator selection is currently available; keeping
        // the previous non-nil value would present stale UI state.
        operatorSelection = result.state.operatorSelection
        if let scannedNetworks = result.scannedNetworks {
            self.scannedNetworks = scannedNetworks
        }
    }

    private func controlNotice(
        for operation: NetworkControlOperation,
        result: ModemControlResult
    ) -> String? {
        switch operation {
        case .loading:
            return nil
        case .scanning:
            return L10n.text("Network scan completed.", language: language)
        case .selecting:
            let selection = result.state.operatorSelection
            let name = selection?.operatorName ?? selection?.formattedPLMN ?? "—"
            return L10n.format(
                "Manual selection verified for %@.",
                language: language,
                name
            )
        case .automaticSelection:
            return L10n.text("Automatic network selection was verified.", language: language)
        case let .changingArchitecture(mode):
            return L10n.format(
                "%@ was applied and verified. %@",
                language: language,
                L10n.text(mode.label, language: language),
                persistenceNotice(result.state.preferenceLifetime)
            )
        case .lockingNRBands:
            let bands = displayedNRBands(in: result.state)
            return L10n.format(
                "NR bands %@ were applied and verified. %@",
                language: language,
                bands.sorted().map(String.init).joined(separator: ", "),
                persistenceNotice(result.state.preferenceLifetime)
            )
        case .lockingLTEBands:
            return L10n.format(
                "LTE bands %@ were applied and verified. %@",
                language: language,
                result.state.lteBands.sorted().map(String.init).joined(separator: ", "),
                persistenceNotice(result.state.preferenceLifetime)
            )
        case .restoring:
            if activeModem?.identity.kind == .zteMC7530CA {
                return L10n.text(
                    "Automatic selection and the MC7530CA band/cell defaults were restored and verified.",
                    language: language
                )
            }
            return L10n.text(
                "Automatic operator selection and the original LTE/NR masks were restored and verified.",
                language: language
            )
        }
    }

    private func persistenceNotice(_ lifetime: ModemPreferenceLifetime) -> String {
        switch lifetime {
        case .untilPowerLoss:
            return L10n.text("This setting lasts until the modem loses power.", language: language)
        case .persistent:
            return L10n.text("This setting persists until it is changed or restored.", language: language)
        case .unknown:
            return L10n.text("The modem did not report this setting's persistence.", language: language)
        }
    }

    private func displayedNRBands(in state: ModemControlState) -> Set<Int> {
        switch state.architecture {
        case .saOnly: return state.saBands
        case .nsaOnly: return state.nsaBands
        case .automatic: return state.saBands == state.nsaBands
            ? state.saBands
            : state.saBands.union(state.nsaBands)
        case .lteOnly, .unavailable: return []
        }
    }

    private func clearControlState() {
        operatorSelection = nil
        scannedNetworks = []
        controlState = nil
        controlError = nil
        controlNotice = nil
    }

    private func clearOperatorContext() {
        operatorSelection = nil
        scannedNetworks = []
        controlState = controlState?.clearingOperatorSelection()
        controlError = nil
        controlNotice = nil
    }

    private func updateMenuTitle(force: Bool) {
        let proposed: String
        if connectionState == .disconnected || connectionState == .authenticationFailed || connectionState == .qmiUnavailable {
            proposed = L10n.text("Cellular —", language: language)
        } else if !snapshot.hasRadioData {
            proposed = L10n.text("Cellular …", language: language)
        } else {
            switch menuBarStyle {
            case .detailed: proposed = snapshot.detailedMenuTitle
            case .compact: proposed = snapshot.compactMenuTitle
            case .iconOnly: proposed = ""
            }
        }

        if force || menuBarTitle.hasPrefix("Cellular") || menuBarTitle.hasPrefix("蜂窝网络") {
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

    private var currentConnectionPreferences: ModemConnectionPreferences {
        var endpoints: [ModemEndpointPreference] = []
        if !Self.isBuiltInDefault(kind: .vos5G, address: host),
           let endpoint = endpointPreference(kind: .vos5G, address: host) {
            endpoints.append(endpoint)
        }
        if !Self.isBuiltInDefault(kind: .zteMC7530CA, address: zteHost),
           let endpoint = endpointPreference(kind: .zteMC7530CA, address: zteHost) {
            endpoints.append(endpoint)
        }
        return ModemConnectionPreferences(
            selection: modemSelection,
            manualEndpoints: endpoints,
            lastSuccessfulScopeKey: lastSuccessfulScopeKey,
            lastSuccessfulEndpoint: lastSuccessfulEndpoint
        )
    }

    private var currentCredentials: ModemConnectionCredentials {
        var credentials = ModemConnectionCredentials()
        let vosUser = username.trimmingCharacters(in: .whitespacesAndNewlines)
        if !vosUser.isEmpty, !password.isEmpty {
            credentials[.vos5G] = .ssh(SSHCredentials(username: vosUser, password: password))
        }
        if !ztePassword.isEmpty {
            credentials[.zteMC7530CA] = .web(WebCredentials(password: ztePassword))
        }
        return credentials
    }

    private func endpointPreference(
        kind: ModemKind,
        address: String
    ) -> ModemEndpointPreference? {
        let configuration = DeviceConfiguration(
            host: address,
            username: "",
            password: "",
            refreshInterval: refreshInterval
        )
        guard let url = configuration.baseURL else { return nil }
        return ModemEndpointPreference(kind: kind, baseURL: url)
    }

    private func persistLastSuccessful(_ result: ModemReadResult) {
        lastSuccessfulScopeKey = result.lastSuccessfulScopeKey
        lastSuccessfulEndpoint = result.lastSuccessfulEndpoint
        defaults.set(result.lastSuccessfulScopeKey, forKey: Key.lastSuccessfulScopeKey)
        if let data = try? JSONEncoder().encode(result.lastSuccessfulEndpoint) {
            defaults.set(data, forKey: Key.lastSuccessfulEndpoint)
        }
    }

    private func clearLastSuccessfulEndpoint() {
        lastSuccessfulScopeKey = nil
        lastSuccessfulEndpoint = nil
        defaults.removeObject(forKey: Key.lastSuccessfulScopeKey)
        defaults.removeObject(forKey: Key.lastSuccessfulEndpoint)
    }

    private var unresolvedCredentialLoadError: String? {
        let messages = ModemKind.allCases.compactMap { kind -> String? in
            guard case let .unavailable(message) = credentialLoadStates[kind] else { return nil }
            return message
        }
        return messages.isEmpty ? nil : messages.joined(separator: "; ")
    }

    static func isBuiltInDefault(kind: ModemKind, address: String) -> Bool {
        let defaultAddress: String
        switch kind {
        case .vos5G: defaultAddress = defaultVOSHost
        case .zteMC7530CA: defaultAddress = defaultZTEHost
        }
        return normalizedManagementURL(address) == normalizedManagementURL(defaultAddress)
    }

    static func normalizedManagementURL(_ address: String) -> URL? {
        DeviceConfiguration(
            host: address,
            username: "",
            password: "",
            refreshInterval: 30
        ).baseURL
    }

    private static func loadLastSuccessfulEndpoint(
        defaults: UserDefaults
    ) -> ModemEndpointPreference? {
        guard let data = defaults.data(forKey: Key.lastSuccessfulEndpoint) else { return nil }
        return try? JSONDecoder().decode(ModemEndpointPreference.self, from: data)
    }

    static func loadVOSCredential(
        defaults: UserDefaults,
        credentialStore: any CredentialStoring
    ) throws -> CredentialLoadResult {
        if let stored = try credentialStore.password(for: vosCredentialAccount) {
            defaults.removeObject(forKey: Key.password)
            return CredentialLoadResult(password: stored, state: .loaded(stored))
        }

        guard let legacy = defaults.string(forKey: Key.password), !legacy.isEmpty else {
            defaults.removeObject(forKey: Key.password)
            let defaultPassword = "oelinux123"
            return CredentialLoadResult(
                password: defaultPassword,
                state: .loaded(defaultPassword)
            )
        }
        do {
            try credentialStore.setPassword(legacy, for: vosCredentialAccount)
            defaults.removeObject(forKey: Key.password)
        } catch {
            // Keep the legacy value as the only durable copy and mark it
            // unavailable so Save retries the local-file write before cleanup.
            return CredentialLoadResult(
                password: legacy,
                state: .unavailable(error.localizedDescription)
            )
        }
        return CredentialLoadResult(password: legacy, state: .loaded(legacy))
    }

    static func loadVOSPassword(
        defaults: UserDefaults,
        credentialStore: any CredentialStoring
    ) throws -> String {
        try loadVOSCredential(
            defaults: defaults,
            credentialStore: credentialStore
        ).password
    }

    private func isAuthenticationError(_ error: Error) -> Bool {
        ModemFailureClassifier.category(of: error) == .authentication
    }

    private func isQMIUnavailableError(_ error: Error) -> Bool {
        ModemFailureClassifier.category(of: error) == .qmiUnavailable
    }

    private func localizedError(_ error: Error) -> String {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        if let backendError = error as? ModemBackendError {
            switch backendError {
            case .credentialsRequired(.web), .incompatibleCredentials(expected: .web, actual: _):
                return L10n.text(
                    "Enter the ZTE Web administrator password in Settings.",
                    language: language
                )
            case .credentialsRequired(.ssh), .incompatibleCredentials(expected: .ssh, actual: _):
                return L10n.text(
                    "Enter the VOS SSH username and password in Settings.",
                    language: language
                )
            default:
                break
            }
        }
        if error as? ZTEUBusError == .authenticationFailed {
            return L10n.text("The ZTE administrator password was rejected.", language: language)
        }
        if error as? VOSClientError == .authenticationFailed {
            return L10n.text("The modem SSH username or password was rejected.", language: language)
        }
        if let coordinatorError = error as? ModemCoordinatorError,
           case let .authenticationFailed(kind, _) = coordinatorError {
            switch kind {
            case .zteMC7530CA:
                if ztePassword.isEmpty {
                    return L10n.text(
                        "Enter the ZTE Web administrator password in Settings.",
                        language: language
                    )
                }
                return L10n.text("The ZTE administrator password was rejected.", language: language)
            case .vos5G:
                if username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    password.isEmpty {
                    return L10n.text(
                        "Enter the VOS SSH username and password in Settings.",
                        language: language
                    )
                }
                return L10n.text("The modem SSH username or password was rejected.", language: language)
            case nil:
                return L10n.text("Authentication failed", language: language)
            }
        }
        return L10n.text(message, language: language)
    }
}
