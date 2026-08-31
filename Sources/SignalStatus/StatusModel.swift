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
    @Published private(set) var operatorSelection: OperatorSelection?
    @Published private(set) var scannedNetworks: [CellularNetwork] = []
    @Published private(set) var nrSelectionPreferences: NRSystemSelectionPreferences?
    @Published private(set) var controlOperation: NetworkControlOperation?
    @Published private(set) var controlError: String?
    @Published private(set) var controlNotice: String?

    @Published var host: String
    @Published var username: String
    @Published var password: String
    @Published var refreshInterval: Double
    @Published var menuBarStyle: MenuBarStyle
    @Published var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: Key.language)
            updateMenuTitle(force: true)
        }
    }

    private let client = VOSClient()
    private let defaults: UserDefaults
    private var pollingTask: Task<Void, Never>?
    private var pollingGeneration: UInt64 = 0
    private var refreshCoalescer = RefreshCoalescer()
    private var consecutiveFailures = 0
    private var candidateTitle: String?
    private var candidateTitleCount = 0
    private let demoMode: Bool
    private var controlDeviceFingerprint: String?
    private var originalNRPreferences: NRSystemSelectionPreferences?
    private var activeNRBandLock: Set<Int>?

    private enum Key {
        static let host = "deviceHost"
        static let username = "sshUsername"
        static let password = "sshPassword"
        static let interval = "refreshInterval"
        static let intervalSchema = "refreshIntervalSchema"
        static let menuStyle = "menuBarStyle"
        static let language = "appLanguage"
    }

    private static let refreshIntervals = [1.0, 5.0, 10.0, 15.0, 30.0, 60.0]
    private static let currentIntervalSchema = 1

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let arguments = ProcessInfo.processInfo.arguments
        let isSADemo = arguments.contains("--demo-sa")
        let showsDemoControls = arguments.contains("--demo-controls")
        demoMode = ProcessInfo.processInfo.environment["SIGNAL_STATUS_DEMO"] == "1" ||
            arguments.contains("--demo") || arguments.contains("--demo-nsa") || isSADemo || showsDemoControls
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
        language = AppLanguage.resolved(
            storedValue: defaults.string(forKey: Key.language),
            preferredLanguages: Locale.preferredLanguages
        )

        if demoMode {
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
                if let saBands = NRBandMask(bands: [77, 78]),
                   let nsaBands = NRBandMask(bands: [77, 78]),
                   let lteBands = LTEBandMask(bands: [2, 4, 25, 66]) {
                    let preferences = NRSystemSelectionPreferences(
                        modePreference: 0x0050,
                        saBands: saBands,
                        nsaBands: nsaBands,
                        lteBands: lteBands
                    )
                    nrSelectionPreferences = preferences
                    originalNRPreferences = preferences
                }
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
    var canRestoreNRDefaults: Bool { originalNRPreferences != nil }

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
        Task { [weak self] in
            await self?.runControl(.loading) { model, configuration, operationGuard in
                model.operatorSelection = try await model.client.fetchOperatorSelection(configuration: configuration)
                try await model.verifyControlDevice(
                    configuration: configuration,
                    operationGuard: operationGuard
                )
                let latestPreferences = try await model.client.fetchNRSystemSelectionPreferences(
                    configuration: configuration
                )
                try await model.verifyControlDevice(
                    configuration: configuration,
                    operationGuard: operationGuard
                )
                model.rememberOriginalPreferencesIfAutomatic(latestPreferences)
                model.nrSelectionPreferences = latestPreferences
            }
        }
    }

    func scanNetworks() {
        Task { [weak self] in
            await self?.runControl(.scanning) { model, configuration, operationGuard in
                model.scannedNetworks = try await model.preservingCurrentNRPreferences(
                    configuration: configuration,
                    operationGuard: operationGuard
                ) {
                    try await model.verifyControlDevice(
                        configuration: configuration,
                        operationGuard: operationGuard
                    )
                    return try await model.client.scanNetworks(configuration: configuration)
                }
                model.operatorSelection = try await model.client.fetchOperatorSelection(configuration: configuration)
                model.controlNotice = L10n.text("Network scan completed.", language: model.language)
            }
        }
    }

    func selectNetwork(_ network: CellularNetwork) {
        Task { [weak self] in
            await self?.runControl(.selecting(network.formattedPLMN)) { model, configuration, operationGuard in
                do {
                    _ = try await model.preservingCurrentNRPreferences(
                        configuration: configuration,
                        operationGuard: operationGuard
                    ) {
                        try await model.verifyControlDevice(
                            configuration: configuration,
                            operationGuard: operationGuard
                        )
                        return try await model.client.selectNetwork(
                            plmn: network.plmn,
                            configuration: configuration
                        )
                    }
                } catch {
                    guard operationGuard.isValid else { throw error }
                    let manualFailure = error
                    let finalSelection = try? await model.client.fetchOperatorSelection(
                        configuration: configuration
                    )
                    if finalSelection?.mode == .automatic { throw manualFailure }

                    var recoveryFailure: Error?
                    do {
                        _ = try await model.preservingCurrentNRPreferences(
                            configuration: configuration,
                            operationGuard: operationGuard
                        ) {
                            try await model.verifyControlDevice(
                                configuration: configuration,
                                operationGuard: operationGuard
                            )
                            return try await model.client.selectAutomaticNetwork(configuration: configuration)
                        }
                    } catch {
                        guard operationGuard.isValid else { throw error }
                        recoveryFailure = error
                    }
                    let recoveredSelection = try? await model.client.fetchOperatorSelection(
                        configuration: configuration
                    )
                    if recoveryFailure == nil, recoveredSelection?.mode == .automatic {
                        model.operatorSelection = recoveredSelection
                        throw VOSClientError.verificationFailed(
                            "\(manualFailure.localizedDescription) Automatic operator selection was restored and verified."
                        )
                    }
                    throw VOSClientError.verificationFailed(
                        "\(manualFailure.localizedDescription) Automatic operator recovery could not be verified; state is unknown."
                    )
                }

                let finalSelection = try await model.client.fetchOperatorSelection(configuration: configuration)
                if finalSelection.mode == .manual, finalSelection.plmn == network.plmn {
                    model.operatorSelection = finalSelection
                    model.controlNotice = L10n.format(
                        "Manual selection verified for %@ (%@).",
                        language: model.language,
                        network.displayName,
                        network.formattedPLMN
                    )
                    return
                }

                var recoveryFailure: Error?
                do {
                    _ = try await model.preservingCurrentNRPreferences(
                        configuration: configuration,
                        operationGuard: operationGuard
                    ) {
                        try await model.verifyControlDevice(
                            configuration: configuration,
                            operationGuard: operationGuard
                        )
                        return try await model.client.selectAutomaticNetwork(configuration: configuration)
                    }
                } catch {
                    guard operationGuard.isValid else { throw error }
                    recoveryFailure = error
                }
                let recoveredSelection = try? await model.client.fetchOperatorSelection(configuration: configuration)
                if recoveryFailure == nil, recoveredSelection?.mode == .automatic {
                    model.operatorSelection = recoveredSelection
                    throw VOSClientError.verificationFailed(
                        "Manual selection did not remain active after restoring the radio preference; automatic operator selection was restored and verified."
                    )
                }
                throw VOSClientError.verificationFailed(
                    "Manual selection did not remain active, and automatic recovery could not be verified after restoring the radio preference; state is unknown."
                )
            }
        }
    }

    func selectAutomaticNetwork() {
        Task { [weak self] in
            await self?.runControl(.automaticSelection) { model, configuration, operationGuard in
                _ = try await model.preservingCurrentNRPreferences(
                    configuration: configuration,
                    operationGuard: operationGuard
                ) {
                    try await model.verifyControlDevice(
                        configuration: configuration,
                        operationGuard: operationGuard
                    )
                    return try await model.client.selectAutomaticNetwork(configuration: configuration)
                }
                let finalSelection = try await model.client.fetchOperatorSelection(configuration: configuration)
                guard finalSelection.mode == .automatic else {
                    throw VOSClientError.verificationFailed(
                        "Automatic operator selection did not remain active after restoring the radio preference; state is unknown."
                    )
                }
                model.operatorSelection = finalSelection
                model.controlNotice = L10n.text(
                    "Automatic network selection was verified.",
                    language: model.language
                )
            }
        }
    }

    func setNRArchitecture(_ mode: NRArchitectureMode) {
        guard mode != .unavailable else { return }
        Task { [weak self] in
            await self?.runControl(.changingArchitecture(mode)) { model, configuration, operationGuard in
                let previous = try await model.client.fetchNRSystemSelectionPreferences(configuration: configuration)
                let preferencePlan = try model.targetPreferences(for: mode, current: previous)
                let target = preferencePlan.target
                guard let targetMode = target.modePreference else {
                    throw VOSClientError.verificationFailed("Qualcomm NAS did not report a mode preference to preserve.")
                }
                do {
                    try await model.verifyControlDevice(
                        configuration: configuration,
                        operationGuard: operationGuard
                    )
                    model.nrSelectionPreferences = try await model.client.setNRSystemSelectionPreferences(
                        modePreference: targetMode,
                        saBands: target.saBands,
                        nsaBands: target.nsaBands,
                        lteBands: preferencePlan.lteBandsToWrite,
                        configuration: configuration
                    )
                } catch {
                    guard operationGuard.isValid else { throw error }
                    if let rollbackFailure = try await model.rollbackNRPreferences(
                        previous,
                        configuration: configuration,
                        operationGuard: operationGuard
                    ) {
                        let originalFailure = (error as? LocalizedError)?.errorDescription
                            ?? error.localizedDescription
                        throw VOSClientError.verificationFailed(
                            "\(originalFailure) Automatic rollback also failed: \(rollbackFailure). Power-cycle VOS to restore its temporary radio preferences."
                        )
                    }
                    throw error
                }
                model.controlNotice = L10n.format(
                    "%@ was applied and verified. The preference resets when VOS loses power.",
                    language: model.language,
                    L10n.text(mode.label, language: model.language)
                )
            }
        }
    }

    func lockNRBands(_ bands: Set<Int>) {
        Task { [weak self] in
            await self?.runControl(.lockingNRBands) { model, configuration, operationGuard in
                guard !bands.isEmpty, let requested = NRBandMask(bands: bands) else {
                    throw VOSClientError.verificationFailed("Enter one or more valid NR bands, for example 77,78.")
                }
                let previous = try await model.client.fetchNRSystemSelectionPreferences(configuration: configuration)
                model.rememberOriginalPreferencesIfAutomatic(previous)
                guard let baseline = model.originalNRPreferences,
                      let modePreference = previous.modePreference
                else {
                    throw VOSClientError.verificationFailed(
                        "The original band masks were not captured. Power-cycle VOS, then reopen Network & radio controls."
                    )
                }

                let plan = try NRBandLockPlan.make(
                    requested: requested,
                    baseline: baseline,
                    architecture: previous.architectureMode
                )

                do {
                    try await model.verifyControlDevice(
                        configuration: configuration,
                        operationGuard: operationGuard
                    )
                    model.nrSelectionPreferences = try await model.client.setNRSystemSelectionPreferences(
                        modePreference: modePreference,
                        saBands: plan.saBands,
                        nsaBands: plan.nsaBands,
                        configuration: configuration
                    )
                } catch {
                    guard operationGuard.isValid else { throw error }
                    if let rollbackFailure = try await model.rollbackNRPreferences(
                        previous,
                        configuration: configuration,
                        operationGuard: operationGuard
                    ) {
                        throw VOSClientError.verificationFailed(
                            "\(error.localizedDescription) Rollback also failed: \(rollbackFailure). Power-cycle VOS."
                        )
                    }
                    throw error
                }
                model.activeNRBandLock = bands
                model.controlNotice = L10n.format(
                    "NR bands %@ were applied and verified until VOS loses power.",
                    language: model.language,
                    bands.sorted().map(String.init).joined(separator: ", ")
                )
            }
        }
    }

    func lockLTEBands(_ bands: Set<Int>) {
        Task { [weak self] in
            await self?.runControl(.lockingLTEBands) { model, configuration, operationGuard in
                guard !bands.isEmpty, let requested = LTEBandMask(bands: bands) else {
                    throw VOSClientError.verificationFailed("Enter one or more valid LTE bands, for example 2,4,25,66.")
                }
                let previous = try await model.client.fetchNRSystemSelectionPreferences(configuration: configuration)
                model.rememberOriginalPreferencesIfAutomatic(previous)
                guard let baseline = model.originalNRPreferences?.lteBands,
                      let previousLTE = previous.lteBands,
                      let modePreference = previous.modePreference
                else {
                    throw VOSClientError.verificationFailed("Qualcomm NAS did not report an extended LTE band mask to preserve.")
                }
                let target = baseline.intersecting(requested)
                let unavailable = bands.subtracting(Set(target.enabledBands)).sorted()
                guard unavailable.isEmpty else {
                    throw VOSClientError.verificationFailed(
                        "These LTE bands are not enabled by the captured modem defaults: \(unavailable.map(String.init).joined(separator: ", "))."
                    )
                }

                do {
                    try await model.verifyControlDevice(
                        configuration: configuration,
                        operationGuard: operationGuard
                    )
                    model.nrSelectionPreferences = try await model.client.setNRSystemSelectionPreferences(
                        modePreference: modePreference,
                        saBands: previous.saBands,
                        nsaBands: previous.nsaBands,
                        lteBands: target,
                        configuration: configuration
                    )
                } catch {
                    guard operationGuard.isValid else { throw error }
                    var rollback = previous
                    rollback.lteBands = previousLTE
                    if let rollbackFailure = try await model.rollbackNRPreferences(
                        rollback,
                        configuration: configuration,
                        operationGuard: operationGuard
                    ) {
                        throw VOSClientError.verificationFailed(
                            "\(error.localizedDescription) Rollback also failed: \(rollbackFailure). Power-cycle VOS."
                        )
                    }
                    throw error
                }
                model.controlNotice = L10n.format(
                    "LTE bands %@ were applied and verified until VOS loses power.",
                    language: model.language,
                    bands.sorted().map(String.init).joined(separator: ", ")
                )
            }
        }
    }

    func restoreAutomaticDefaults() {
        Task { [weak self] in
            await self?.runControl(.restoring) { model, configuration, operationGuard in
                guard let original = model.originalNRPreferences,
                      let modePreference = original.modePreference
                else {
                    throw VOSClientError.verificationFailed(
                        "No automatic radio baseline is available for this physical VOS. Power-cycle it, then reopen this panel to capture its defaults."
                    )
                }
                var failures: [String] = []
                // COPS=0 can alter the NAS mode-preference bitmask on 0R05.
                // Apply it first, then restore the captured QMI tuple last.
                do {
                    try await model.verifyControlDevice(
                        configuration: configuration,
                        operationGuard: operationGuard
                    )
                    model.operatorSelection = try await model.client.selectAutomaticNetwork(configuration: configuration)
                } catch {
                    guard operationGuard.isValid else { throw error }
                    failures.append("operator selection: \(error.localizedDescription)")
                }

                do {
                    try await model.verifyControlDevice(
                        configuration: configuration,
                        operationGuard: operationGuard
                    )
                    model.nrSelectionPreferences = try await model.client.setNRSystemSelectionPreferences(
                        modePreference: modePreference,
                        saBands: original.saBands,
                        nsaBands: original.nsaBands,
                        lteBands: original.lteBands,
                        configuration: configuration
                    )
                } catch {
                    guard operationGuard.isValid else { throw error }
                    failures.append("radio preference: \(error.localizedDescription)")
                }

                guard failures.isEmpty else {
                    throw VOSClientError.verificationFailed(failures.joined(separator: "; "))
                }
                let finalSelection = try await model.client.fetchOperatorSelection(configuration: configuration)
                guard finalSelection.mode == .automatic else {
                    throw VOSClientError.verificationFailed(
                        "The original radio tuple was restored, but final automatic operator selection could not be verified."
                    )
                }
                model.operatorSelection = finalSelection
                model.activeNRBandLock = nil
                model.controlNotice = L10n.text(
                    "Original LTE/NR masks and automatic operator selection were restored and verified.",
                    language: model.language
                )
            }
        }
    }

    func saveSettings() {
        defaults.set(host.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Key.host)
        defaults.set(username, forKey: Key.username)
        defaults.set(password, forKey: Key.password)
        defaults.set(refreshInterval, forKey: Key.interval)
        defaults.set(menuBarStyle.rawValue, forKey: Key.menuStyle)
        updateMenuTitle(force: true)
        consecutiveFailures = 0
        connectionState = .connecting
        lastError = nil
        clearControlState()
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
        ) as? String ?? "1.2.0"
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
        let seconds = StatusPollingPolicy.interval(
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
        guard refreshCoalescer.request(
            isRefreshing: isRefreshing,
            isControlBusy: isControlBusy
        ) else { return }

        repeat {
            refreshCoalescer.beginRefresh()
            await performRefresh()
        } while refreshCoalescer.shouldDrain(
            isRefreshing: isRefreshing,
            isControlBusy: isControlBusy
        )
    }

    private func performRefresh() async {
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
            let radioAvailabilityChanged = snapshot.hasRadioData != latest.hasRadioData
            if snapshot.plmn != latest.plmn {
                // A powered SIM replacement can leave the USB device and SSH
                // identity unchanged while registration moves to a different
                // PLMN (or temporarily disappears). Do not keep presenting a
                // selection or scan result captured for the previous card.
                operatorSelection = nil
                scannedNetworks = []
                controlError = nil
                controlNotice = nil
            }
            snapshot = latest
            consecutiveFailures = 0
            // During a physical SIM swap QMI remains reachable but may report
            // no serving band while the new card initializes. Treat that as a
            // reconnecting state so polling accelerates to the five-second
            // recovery cadence instead of waiting the full user interval.
            connectionState = latest.hasRadioData ? .online : .connecting
            lastError = nil
            updateMenuTitle(force: snapshot.updatedAt == .distantPast || radioAvailabilityChanged)
        } catch {
            consecutiveFailures += 1
            lastError = localizedError(error)
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

    private func runControl(
        _ operation: NetworkControlOperation,
        action: @escaping @MainActor (
            StatusModel,
            DeviceConfiguration,
            ControlOperationDeviceGuard
        ) async throws -> Void
    ) async {
        guard !demoMode, controlOperation == nil else { return }
        controlOperation = operation
        defer {
            controlOperation = nil
            refreshNow()
        }
        while isRefreshing {
            do {
                try await Task.sleep(nanoseconds: 50_000_000)
            } catch {
                return
            }
        }

        controlError = nil
        controlNotice = nil
        let configuration = currentConfiguration
        do {
            let fingerprint = try await client.fetchDeviceFingerprint(configuration: configuration)
            bindControlState(to: fingerprint)
            let operationGuard = ControlOperationDeviceGuard(expectedFingerprint: fingerprint)
            try await action(self, configuration, operationGuard)
        } catch {
            controlError = localizedError(error)
        }
    }

    private var currentConfiguration: DeviceConfiguration {
        DeviceConfiguration(
            host: host,
            username: username,
            password: password,
            refreshInterval: refreshInterval
        )
    }

    private func rememberOriginalPreferencesIfAutomatic(_ preferences: NRSystemSelectionPreferences) {
        guard originalNRPreferences == nil,
              preferences.architectureMode == .automatic,
              preferences.modePreference != nil
        else { return }
        originalNRPreferences = preferences
    }

    private func targetPreferences(
        for mode: NRArchitectureMode,
        current: NRSystemSelectionPreferences
    ) throws -> RadioAccessPreferencePlan {
        rememberOriginalPreferencesIfAutomatic(current)
        nrSelectionPreferences = current
        guard let original = originalNRPreferences,
              original.modePreference != nil
        else {
            throw VOSClientError.verificationFailed(
                "The original automatic radio masks were not captured. Power-cycle VOS, then open Network & radio controls before changing the mode."
            )
        }

        return try RadioAccessPreferencePlan.make(
            mode: mode,
            baseline: original,
            current: current,
            activeNRBandLock: activeNRBandLock
        )
    }

    private func rollbackNRPreferences(
        _ previous: NRSystemSelectionPreferences,
        configuration: DeviceConfiguration,
        operationGuard: ControlOperationDeviceGuard
    ) async throws -> String? {
        guard let modePreference = previous.modePreference
        else { return "the pre-operation preference tuple is incomplete" }
        do {
            try await verifyControlDevice(
                configuration: configuration,
                operationGuard: operationGuard
            )
            nrSelectionPreferences = try await client.setNRSystemSelectionPreferences(
                modePreference: modePreference,
                saBands: previous.saBands,
                nsaBands: previous.nsaBands,
                lteBands: previous.lteBands,
                configuration: configuration
            )
            return nil
        } catch {
            guard operationGuard.isValid else { throw error }
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func preservingCurrentNRPreferences<T>(
        configuration: DeviceConfiguration,
        operationGuard: ControlOperationDeviceGuard,
        operation: @escaping @MainActor () async throws -> T
    ) async throws -> T {
        let previous = try await client.fetchNRSystemSelectionPreferences(configuration: configuration)
        nrSelectionPreferences = previous

        let result: T
        do {
            result = try await operation()
        } catch {
            guard operationGuard.isValid else { throw error }
            if let rollbackFailure = try await rollbackNRPreferences(
                previous,
                configuration: configuration,
                operationGuard: operationGuard
            ) {
                throw VOSClientError.verificationFailed(
                    "\(error.localizedDescription) Restoring the pre-operation radio preference also failed: \(rollbackFailure). Power-cycle VOS before another control operation."
                )
            }
            throw error
        }

        if let rollbackFailure = try await rollbackNRPreferences(
            previous,
            configuration: configuration,
            operationGuard: operationGuard
        ) {
            throw VOSClientError.verificationFailed(
                "The operator operation was verified, but restoring its pre-operation radio preference failed: \(rollbackFailure). Power-cycle VOS before another control operation."
            )
        }
        return result
    }

    private func bindControlState(to fingerprint: String) {
        guard controlDeviceFingerprint != fingerprint else { return }
        controlDeviceFingerprint = fingerprint
        originalNRPreferences = nil
        activeNRBandLock = nil
        operatorSelection = nil
        scannedNetworks = []
        nrSelectionPreferences = nil
    }

    private func verifyControlDevice(
        configuration: DeviceConfiguration,
        operationGuard: ControlOperationDeviceGuard
    ) async throws {
        let current = try await client.fetchDeviceFingerprint(configuration: configuration)
        do {
            try operationGuard.validate(currentFingerprint: current)
        } catch {
            bindControlState(to: current)
            throw error
        }
    }

    private func clearControlState() {
        controlDeviceFingerprint = nil
        originalNRPreferences = nil
        activeNRBandLock = nil
        operatorSelection = nil
        scannedNetworks = []
        nrSelectionPreferences = nil
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

    private func localizedError(_ error: Error) -> String {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        return L10n.text(message, language: language)
    }
}
