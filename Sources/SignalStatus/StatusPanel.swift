import AppKit
import SwiftUI

private enum AppPalette {
    static let blue = Color(nsColor: .systemBlue)
    static let cyan = Color(nsColor: .systemCyan)
}

struct StatusPanel: View {
    @EnvironmentObject private var model: StatusModel
    @Environment(\.appLanguage) private var language
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showSettings = false
    @State private var showDeviceDetails = false
    @State private var showNetworkControls = false
    @State private var pendingControl: ControlConfirmation?
    @State private var launchAtLogin = false
    @State private var launchError: String?
    @State private var nrBandLockText = ""
    @State private var lteBandLockText = ""
    @State private var measuredContentHeight: CGFloat = 320
    @State private var measuredChromeHeight: CGFloat = 96
    private let panelHeightLimit: CGFloat?

    init(
        initiallyShowNetworkControls: Bool = false,
        initiallyShowSettings: Bool = false,
        panelHeightLimit: CGFloat? = nil
    ) {
        _showNetworkControls = State(initialValue: initiallyShowNetworkControls)
        _showSettings = State(initialValue: initiallyShowSettings)
        self.panelHeightLimit = panelHeightLimit
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            panelSeparator
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 10) {
                        if let error = model.lastError, model.connectionState != .online {
                            errorCard(error)
                        }
                        heroCard
                        radioCards
                        if !model.snapshot.lteSecondaryCells.isEmpty {
                            carrierAggregationCard
                        }
                        if model.supportsDeviceControls {
                            networkControlsCard
                                .id("network-controls")
                        }
                        SpeedTestCard(
                            networkQuality: model.networkQualitySpeedTestModel,
                            ookla: model.ooklaSpeedTestModel
                        )
                            .id("speed-test")
                        if showSettings {
                            settingsCard
                                .id("settings")
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                        deviceDetailsCard
                            .id("device-details")
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(12)
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: ContentHeightPreferenceKey.self,
                                value: geometry.size.height
                            )
                        }
                    }
                }
                .frame(height: scrollViewportHeight)
                .accessibilityLabel(L10n.text("Modem status", language: language))
                .onChange(of: showSettings) { isVisible in
                    guard isVisible else { return }
                    DispatchQueue.main.async {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("settings", anchor: .bottom)
                        }
                    }
                }
                .onChange(of: showDeviceDetails) { isVisible in
                    guard isVisible else { return }
                    DispatchQueue.main.async {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("device-details", anchor: .bottom)
                        }
                    }
                }
                .onChange(of: showNetworkControls) { isVisible in
                    guard isVisible else {
                        pendingControl = nil
                        return
                    }
                    if model.supportsControlSession {
                        model.loadNetworkControls()
                    }
                    DispatchQueue.main.async {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("network-controls", anchor: .bottom)
                        }
                    }
                }
                .onChange(of: model.snapshot.plmn) { plmn in
                    // A replacement SIM can register on a different PLMN
                    // without changing the USB device. Refresh the expanded
                    // read-only control summary once the new registration is
                    // available; do not probe while the modem has no PLMN.
                    guard showNetworkControls,
                          plmn != nil,
                          model.supportsControlSession
                    else { return }
                    model.loadNetworkControls()
                }
                .onChange(of: model.supportsDeviceControls) { isSupported in
                    guard !isSupported else { return }
                    showNetworkControls = false
                    pendingControl = nil
                }
                .onChange(of: model.activeModem) { _ in
                    // Confirmations, restore state and scan rows belong to the
                    // exact modem + endpoint binding that produced them. Never
                    // carry them to another device or connection path.
                    pendingControl = nil
                    guard showNetworkControls, model.supportsControlSession else { return }
                    model.loadNetworkControls()
                }
            }
            panelSeparator
            footer
        }
        .frame(width: 360)
        .tint(AppPalette.blue)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Color(nsColor: .windowBackgroundColor)
                    .opacity(colorScheme == .dark ? 0.18 : 0.10)
            }
        }
        .onAppear { launchAtLogin = model.launchAtLogin }
        .onPreferenceChange(ContentHeightPreferenceKey.self) { height in
            guard height > 0, abs(height - measuredContentHeight) > 0.5 else { return }
            measuredContentHeight = ceil(height)
        }
        .onPreferenceChange(ChromeHeightPreferenceKey.self) { height in
            guard height > 0, abs(height - measuredChromeHeight) > 0.5 else { return }
            measuredChromeHeight = ceil(height)
        }
        .animation(.easeInOut(duration: 0.2), value: showSettings)
        .animation(.easeInOut(duration: 0.2), value: showNetworkControls)
        .animation(.easeInOut(duration: 0.16), value: pendingControl?.id)
        .animation(.easeInOut(duration: 0.2), value: scrollViewportHeight)
    }

    private var panelSeparator: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.07))
            .frame(height: 0.5)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(secondaryAccent)
                    .frame(width: 30, height: 30)
                    .background(AppPalette.blue.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Text("Cellular Modem Monitor")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .layoutPriority(1)

                Spacer(minLength: 4)

                StatusBadge(state: model.connectionState)

                Button(action: model.refreshNow) {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(model.isRefreshing && !reduceMotion ? .degrees(360) : .zero)
                        .animation(
                            model.isRefreshing && !reduceMotion
                                ? .linear(duration: 0.8).repeatForever(autoreverses: false)
                                : .default,
                            value: model.isRefreshing
                        )
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help(L10n.text("Refresh now", language: language))
                .accessibilityLabel(L10n.text("Refresh now", language: language))
                .disabled(model.isRefreshing || model.isControlBusy)
            }

            Text(headerSubtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .allowsTightening(true)
                .padding(.leading, 40)
                .help(headerSubtitle)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color.primary.opacity(0.018))
        .background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: ChromeHeightPreferenceKey.self,
                    value: geometry.size.height
                )
            }
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(L10n.text("CURRENT CONNECTION", language: language))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .tracking(0.6)
                Spacer()
                if let updated = updatedText {
                    Text(updated)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(model.snapshot.detailedMenuTitle)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.72)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }

            if !model.snapshot.hasRadioData {
                Text(L10n.text("Waiting for current radio information", language: language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .cardStyle(prominent: true, accent: AppPalette.blue)
    }

    @ViewBuilder
    private var radioCards: some View {
        if model.snapshot.nrBand != nil || model.snapshot.lteBand != nil {
            LazyVGrid(columns: radioColumns, alignment: .leading, spacing: 10) {
                if let band = model.snapshot.nrBand {
                    RadioCard(
                        title: "NR",
                        radio: .nr,
                        accent: secondaryAccent,
                        surfaceAccent: AppPalette.cyan,
                        band: band,
                        frequency: model.snapshot.nrFrequencyMHz,
                        channelLabel: "NR-ARFCN",
                        channel: model.snapshot.nrChannel,
                        bandwidth: model.snapshot.nrBandwidthMHz,
                        signal: model.snapshot.nrSignal,
                        globalCellID: model.snapshot.nrGlobalCellID,
                        mcc: model.snapshot.mcc,
                        mnc: model.snapshot.mnc,
                        raw: model.snapshot.nrRaw
                    )
                }
                if let band = model.snapshot.lteBand {
                    RadioCard(
                        title: "LTE",
                        radio: .lte,
                        accent: AppPalette.blue,
                        surfaceAccent: AppPalette.blue,
                        band: band,
                        frequency: model.snapshot.lteFrequencyMHz,
                        channelLabel: "EARFCN",
                        channel: model.snapshot.lteChannel,
                        bandwidth: model.snapshot.lteBandwidthMHz,
                        signal: model.snapshot.lteSignal,
                        globalCellID: model.snapshot.lteGlobalCellID,
                        mcc: model.snapshot.mcc,
                        mnc: model.snapshot.mnc,
                        raw: model.snapshot.lteRaw
                    )
                }
            }
        }
    }

    private var radioColumns: [GridItem] {
        let count = [model.snapshot.nrBand, model.snapshot.lteBand].compactMap { $0 }.count
        return Array(
            repeating: GridItem(.flexible(minimum: 140), spacing: 10, alignment: .top),
            count: max(1, min(2, count))
        )
    }

    private var carrierAggregationCard: some View {
        LTECarrierAggregationCard(
            primaryCell: model.snapshot.ltePrimaryCell,
            secondaryCells: model.snapshot.lteSecondaryCells,
            mcc: model.snapshot.mcc,
            mnc: model.snapshot.mnc
        )
    }

    private var deviceDetailsCard: some View {
        CollapsibleCard(
            isExpanded: $showDeviceDetails,
            accessibilityLabel: L10n.text("Device details", language: language)
        ) {
            VStack(spacing: 9) {
                DetailRow(label: L10n.text("Device", language: language), value: model.activeModemName)
                DetailRow(label: L10n.text("Management", language: language), value: model.activeManagementEndpoint)
                DetailRow(label: L10n.text("Interface", language: language), value: model.activeInterfaceName)
                DetailRow(label: L10n.text("Connection path", language: language), value: model.activeConnectionPath)
                DetailRow(label: L10n.text("Source", language: language), value: model.activeDataSource)
                if let version = model.snapshot.moduleVersion {
                    DetailRow(label: L10n.text("Modem firmware", language: language), value: version)
                }
                if let firmware = model.snapshot.deviceFirmware {
                    DetailRow(label: L10n.text("Device firmware", language: language), value: firmware)
                }
            }
            .padding(.top, 9)
        } label: {
            Label(L10n.text("Device details", language: language), systemImage: "info.circle")
                .font(.subheadline.weight(.semibold))
        }
    }

    private var networkControlsCard: some View {
        CollapsibleCard(
            isExpanded: $showNetworkControls,
            accessibilityLabel: L10n.text("Network & radio controls", language: language),
            accent: AppPalette.blue
        ) {
            VStack(alignment: .leading, spacing: 12) {
                currentNetworkControlSummary

                if let confirmation = pendingControl {
                    InlineControlConfirmation(
                        confirmation: confirmation,
                        modemKind: model.activeModem?.identity.kind,
                        preferenceLifetime: model.controlState?.preferenceLifetime ?? .unknown,
                        cancel: { pendingControl = nil },
                        confirm: { perform(confirmation) }
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if let operation = model.controlOperation {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(operation.localizedLabel(language: language))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let error = model.controlError {
                    controlMessage(error, color: .red, icon: "exclamationmark.triangle.fill")
                } else if let notice = model.controlNotice {
                    controlMessage(notice, color: .green, icon: "checkmark.circle.fill")
                }

                operatorControlButtons

                if model.supportsControl(.networkScan), !model.scannedNetworks.isEmpty {
                    Divider()
                    Text(L10n.text("Scanned networks", language: language))
                        .font(.caption.weight(.semibold))
                    Text(L10n.text("Reported access is the modem's scan result, not a complete list of every band offered by the operator.", language: language))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    VStack(spacing: 7) {
                        ForEach(model.scannedNetworks) { network in
                            ScannedNetworkRow(
                                network: network,
                                isDisabled: controlsDisabled || !model.supportsControl(.operatorSelection)
                            ) {
                                pendingControl = .manualNetwork(network)
                            }
                        }
                    }
                }

                if model.supportsControl(.radioAccessPreference) {
                    Divider()
                    architectureControls
                }

                if hasBandLockControls {
                    Divider()
                    bandLockControls
                }

                if model.supportsControl(.neighborMeasurements) {
                    Divider()
                    neighborMeasurements
                }
            }
            .padding(.top, 10)
        } label: {
            Label(L10n.text("Network & radio controls", language: language), systemImage: "antenna.radiowaves.left.and.right.circle")
                .font(.subheadline.weight(.semibold))
        }
    }

    private var currentNetworkControlSummary: some View {
        VStack(spacing: 7) {
            if hasOperatorControls {
                DetailRow(
                    label: L10n.text("Operator selection", language: language),
                    value: model.operatorSelection.map { L10n.text($0.mode.label, language: language) } ?? L10n.text("Reading…", language: language),
                    compact: true
                )
                DetailRow(
                    label: L10n.text("Selected operator", language: language),
                    value: selectedOperatorText,
                    compact: true
                )
            }
            if model.supportsControl(.radioAccessPreference) {
                DetailRow(
                    label: L10n.text("Radio preference", language: language),
                    value: model.controlState.map { L10n.text($0.architecture.label, language: language) } ?? L10n.text("Reading…", language: language),
                    compact: true
                )
            }
        }
    }

    @ViewBuilder
    private var operatorControlButtons: some View {
        if hasOperatorControls {
            HStack(spacing: 8) {
                if model.supportsControl(.networkScan) {
                    Button(L10n.text("Scan Networks", language: language)) {
                        pendingControl = .scan
                    }
                    .buttonStyle(.borderedProminent)
                }

                if model.supportsControl(.operatorSelection) {
                    Button(L10n.text("Automatic Selection", language: language)) {
                        pendingControl = .automaticNetwork
                    }
                    .buttonStyle(.bordered)
                }
            }
            .disabled(controlsDisabled)
        }
    }

    private var architectureControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text("Radio access preference", language: language))
                .font(.caption.weight(.semibold))
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible())],
                spacing: 6
            ) {
                architectureButton(.automatic)
                architectureButton(.saOnly)
                architectureButton(.nsaOnly)
                architectureButton(.lteOnly)
            }
            Text(architecturePersistenceDescription)
                .font(.caption2)
                .foregroundStyle(.secondary)
            if model.controlState != nil, !model.canRestoreControlDefaults {
                Label(
                    L10n.text("Automatic defaults were not available to capture. Reconnect or power-cycle the modem, then close and reopen this panel before changing radio access mode.", language: language),
                    systemImage: "info.circle"
                )
                .font(.caption2)
                .foregroundStyle(.orange)
            }

            if supportsRestoreDefaults {
                Button(L10n.text("Restore automatic defaults", language: language)) {
                    pendingControl = .restoreDefaults
                }
                .buttonStyle(.bordered)
                .disabled(controlsDisabled || !model.canRestoreControlDefaults)
            }
        }
    }

    private var selectedOperatorText: String {
        guard model.operatorSelection != nil else { return L10n.text("Reading…", language: language) }
        return operatorIdentity.formatted ?? L10n.text("Not registered", language: language)
    }

    private func architectureButton(_ mode: NRArchitectureMode) -> some View {
        let isSelected = model.controlState?.architecture == mode
        return Button {
            pendingControl = .architecture(mode)
        } label: {
            Text(L10n.text(mode.label, language: language))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(isSelected ? AppPalette.blue : Color.gray)
        .disabled(controlsDisabled || !model.canRestoreControlDefaults)
    }

    private var controlsDisabled: Bool {
        model.isRefreshing || model.isControlBusy || pendingControl != nil
    }

    private var bandLockControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text("Band locking", language: language))
                .font(.caption.weight(.semibold))
            Text(bandLockPersistenceDescription)
                .font(.caption2)
                .foregroundStyle(.secondary)

            if model.supportsControl(.nrBandLock) {
                HStack(spacing: 7) {
                    TextField("NR: 77,78", text: $nrBandLockText)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        pendingControl = .nrBandLock(Self.parseBands(nrBandLockText, prefix: "n") ?? [])
                    } label: {
                        Text(L10n.text("Lock NR", language: language))
                            .frame(width: 62)
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.controlState?.architecture == .lteOnly)
                }
            }
            if model.supportsControl(.lteBandLock) {
                HStack(spacing: 7) {
                    TextField("LTE: 2,4,25,66", text: $lteBandLockText)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        pendingControl = .lteBandLock(Self.parseBands(lteBandLockText, prefix: "b") ?? [])
                    } label: {
                        Text(L10n.text("Lock LTE", language: language))
                            .frame(width: 62)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .disabled(controlsDisabled || !model.canRestoreControlDefaults)
    }

    private var hasOperatorControls: Bool {
        model.supportsControl(.networkScan) || model.supportsControl(.operatorSelection)
    }

    private var hasBandLockControls: Bool {
        model.supportsControl(.nrBandLock) || model.supportsControl(.lteBandLock)
    }

    private var supportsRestoreDefaults: Bool {
        model.supportsControl(.operatorSelection)
            && model.supportsControl(.radioAccessPreference)
            && model.supportsControl(.nrBandLock)
            && model.supportsControl(.lteBandLock)
    }

    private var architecturePersistenceDescription: String {
        switch model.controlState?.preferenceLifetime ?? .unknown {
        case .untilPowerLoss:
            return L10n.text("These radio preferences last until the modem loses power. Automatic restores the captured SA/NSA masks; LTE only disables NR while preserving the current LTE band mask.", language: language)
        case .persistent:
            return L10n.text("These radio preferences persist across restarts until they are changed or restored. Each change is read back and a failed change is rolled back.", language: language)
        case .unknown:
            return L10n.text("Each radio preference change is read back and a failed change is rolled back. The modem did not report whether the setting persists across restarts.", language: language)
        }
    }

    private var bandLockPersistenceDescription: String {
        switch model.controlState?.preferenceLifetime ?? .unknown {
        case .untilPowerLoss:
            return L10n.text("Enter comma-separated band numbers. Locks last until the modem loses power; Restore automatic defaults restores the captured masks.", language: language)
        case .persistent:
            return L10n.text("Enter comma-separated band numbers. Locks persist across restarts until changed or restored; Restore automatic defaults restores the modem's vendor defaults.", language: language)
        case .unknown:
            return L10n.text("Enter comma-separated band numbers. Locks are read back after each change; the modem did not report whether they persist across restarts.", language: language)
        }
    }

    private var neighborMeasurements: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.text("Neighbor measurements", language: language))
                    .font(.caption.weight(.semibold))
                Spacer()
                Button(L10n.text("Refresh", language: language)) { model.refreshNow() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(model.isRefreshing || model.isControlBusy)
            }
            if model.snapshot.lteNeighborCells.isEmpty {
                Text(L10n.text("No LTE neighbors were reported.", language: language))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.snapshot.lteNeighborCells) { cell in
                    LTENeighborRow(cell: cell)
                }
            }
        }
    }

    private static func parseBands(_ input: String, prefix: Character) -> Set<Int>? {
        let tokens = input.lowercased().split { $0 == "," || $0 == "+" || $0.isWhitespace }
        guard !tokens.isEmpty else { return nil }
        var bands = Set<Int>()
        for rawToken in tokens {
            var token = String(rawToken)
            if token.first == prefix { token.removeFirst() }
            guard let band = Int(token), band > 0 else { return nil }
            bands.insert(band)
        }
        return bands
    }

    private func controlMessage(_ text: String, color: Color, icon: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(text)
                .font(.caption2)
                .textSelection(.enabled)
        }
    }

    private func perform(_ confirmation: ControlConfirmation) {
        pendingControl = nil
        switch confirmation {
        case .scan:
            model.scanNetworks()
        case let .manualNetwork(network):
            model.selectNetwork(network)
        case .automaticNetwork:
            model.selectAutomaticNetwork()
        case let .architecture(mode):
            model.setNRArchitecture(mode)
        case let .nrBandLock(bands):
            model.lockNRBands(bands)
        case let .lteBandLock(bands):
            model.lockLTEBands(bands)
        case .restoreDefaults:
            model.restoreAutomaticDefaults()
        }
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(L10n.text("Connection", language: language))
                .font(.subheadline.weight(.semibold))

            LabeledContent(L10n.text("Modem", language: language)) {
                Picker("", selection: $model.modemSelection) {
                    Text(L10n.text("Automatic", language: language)).tag(ModemSelection.automatic)
                    Text("VOS 5G").tag(ModemSelection.vos5G)
                    Text("ZTE MC7530CA / G5 MAX").tag(ModemSelection.zteMC7530CA)
                }
                .labelsHidden()
                .frame(width: 190)
            }

            if model.modemSelection != .zteMC7530CA {
                modemSettingsHeading("VOS 5G")
                LabeledContent(L10n.text("Address", language: language)) {
                    TextField("192.168.225.1", text: $model.host)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 190)
                }
                LabeledContent(L10n.text("SSH user", language: language)) {
                    TextField("root", text: $model.username)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 190)
                }
                LabeledContent(L10n.text("SSH password", language: language)) {
                    SecureField("oelinux123", text: $model.password)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 190)
                }
            }

            if model.modemSelection != .vos5G {
                modemSettingsHeading("ZTE MC7530CA / G5 MAX")
                LabeledContent(L10n.text("Address", language: language)) {
                    TextField("192.168.254.1", text: $model.zteHost)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 190)
                }
                LabeledContent(L10n.text("Web admin password", language: language)) {
                    SecureField(L10n.text("Required for status", language: language), text: $model.ztePassword)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 190)
                }
            }

            Text(L10n.text("Passwords are stored unencrypted in a private local file readable only by your macOS account. They are never stored in diagnostics or management URLs.", language: language))
                .font(.caption2)
                .foregroundStyle(.secondary)

            LabeledContent(L10n.text("Refresh", language: language)) {
                Picker("", selection: $model.refreshInterval) {
                    Text(L10n.text("1 second", language: language)).tag(1.0)
                    Text(L10n.text("5 seconds", language: language)).tag(5.0)
                    Text(L10n.text("10 seconds", language: language)).tag(10.0)
                    Text(L10n.text("15 seconds", language: language)).tag(15.0)
                    Text(L10n.text("30 seconds", language: language)).tag(30.0)
                    Text(L10n.text("1 minute", language: language)).tag(60.0)
                }
                .labelsHidden()
                .frame(width: 190)
            }
            LabeledContent(L10n.text("Menu bar", language: language)) {
                Picker("", selection: $model.menuBarStyle) {
                    ForEach(MenuBarStyle.allCases) { style in
                        Text(L10n.text(style.label, language: language)).tag(style)
                    }
                }
                .labelsHidden()
                .frame(width: 190)
            }

            LabeledContent(L10n.text("Language", language: language)) {
                Picker("", selection: $model.language) {
                    ForEach(AppLanguage.allCases) { choice in
                        Text(choice.displayName).tag(choice)
                    }
                }
                .labelsHidden()
                .frame(width: 190)
            }

            Toggle(L10n.text("Open at Login", language: language), isOn: Binding(
                get: { launchAtLogin },
                set: { newValue in
                    do {
                        try model.setLaunchAtLogin(newValue)
                        launchAtLogin = model.launchAtLogin
                        launchError = nil
                    } catch {
                        launchAtLogin = model.launchAtLogin
                        launchError = error.localizedDescription
                    }
                }
            ))

            if let launchError {
                Text(launchError)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }

            if let settingsError = model.settingsError {
                Text(settingsError)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            HStack {
                if model.modemSelection != .zteMC7530CA {
                    Text(L10n.text("Factory VOS SSH: root / oelinux123", language: language))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(L10n.text("Save", language: language)) {
                    if model.saveSettings() {
                        showSettings = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isControlBusy)
            }
        }
        .cardStyle()
    }

    private func modemSettingsHeading(_ title: String) -> some View {
        HStack(spacing: 8) {
            Divider()
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Divider()
        }
        .padding(.vertical, 2)
    }

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .cardStyle(tint: model.connectionState == .disconnected || model.connectionState == .authenticationFailed ? .red : .orange)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Button(action: model.copyDiagnostics) {
                Label(L10n.text("Copy", language: language), systemImage: "doc.on.doc")
            }
            .buttonStyle(.borderless)

            Spacer()

            Menu {
                Button(L10n.text(showSettings ? "Hide Settings" : "Settings…", language: language)) {
                    showSettings.toggle()
                }
                Button(L10n.text("Open Device Web UI", language: language), action: model.openWebUI)
                Button(L10n.text("About Cellular Modem Monitor", language: language), action: model.showAbout)
                Divider()
                Button(L10n.text("Quit Cellular Modem Monitor", language: language), role: .destructive, action: model.quit)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help(L10n.text("Application menu", language: language))
            .accessibilityLabel(L10n.text("Application menu", language: language))
        }
        .font(.caption)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.018))
        .background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: ChromeHeightPreferenceKey.self,
                    value: geometry.size.height
                )
            }
        }
    }

    private var updatedText: String? {
        guard model.snapshot.updatedAt != .distantPast else { return nil }
        if abs(model.snapshot.updatedAt.timeIntervalSinceNow) < 2 {
            return L10n.text("now", language: language)
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = language.locale
        formatter.unitsStyle = .full
        return formatter.localizedString(for: model.snapshot.updatedAt, relativeTo: Date())
    }

    private var headerSubtitle: String {
        operatorIdentity.headerSubtitle(
            modemName: model.activeModem?.identity.compactDisplayName,
            fallback: L10n.text("Local modem", language: language)
        )
    }

    private var operatorIdentity: OperatorDisplayIdentity {
        OperatorDisplayIdentity.resolve(
            snapshotName: model.snapshot.operatorName,
            snapshotPLMN: model.snapshot.plmn,
            selection: model.operatorSelection,
            scannedNetworks: model.scannedNetworks
        )
    }

    private var secondaryAccent: Color {
        colorScheme == .dark ? AppPalette.cyan : AppPalette.blue
    }

    private var maximumPanelHeight: CGFloat {
        if let panelHeightLimit { return panelHeightLimit }
        return max(300, (NSScreen.main?.visibleFrame.height ?? 760) - 24)
    }

    private var scrollViewportHeight: CGFloat {
        let separators: CGFloat = 1
        let available = max(140, maximumPanelHeight - measuredChromeHeight - separators)
        return min(measuredContentHeight, available)
    }
}

private struct InlineControlConfirmation: View {
    @Environment(\.appLanguage) private var language

    let confirmation: ControlConfirmation
    let modemKind: ModemKind?
    let preferenceLifetime: ModemPreferenceLifetime
    let cancel: () -> Void
    let confirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(confirmation.title(language: language))
                    .font(.caption.weight(.semibold))
            }

            Text(confirmation.message(
                language: language,
                modemKind: modemKind,
                preferenceLifetime: preferenceLifetime
            ))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button(L10n.text("Cancel", language: language), action: cancel)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button(confirmation.buttonTitle(language: language), action: confirm)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!confirmation.canConfirm)
            }
        }
        .padding(9)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(.orange.opacity(0.22), lineWidth: 0.5)
        }
    }
}

private enum ControlConfirmation: Identifiable {
    case scan
    case manualNetwork(CellularNetwork)
    case automaticNetwork
    case architecture(NRArchitectureMode)
    case nrBandLock(Set<Int>)
    case lteBandLock(Set<Int>)
    case restoreDefaults

    var id: String {
        switch self {
        case .scan: return "scan"
        case let .manualNetwork(network): return "manual-\(network.id)"
        case .automaticNetwork: return "automatic-network"
        case let .architecture(mode): return "architecture-\(mode.rawValue)"
        case let .nrBandLock(bands): return "nr-bands-\(bands.sorted())"
        case let .lteBandLock(bands): return "lte-bands-\(bands.sorted())"
        case .restoreDefaults: return "restore-defaults"
        }
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .scan: return L10n.text("Scan cellular networks?", language: language)
        case .manualNetwork: return L10n.text("Select this network manually?", language: language)
        case .automaticNetwork: return L10n.text("Use automatic network selection?", language: language)
        case let .architecture(mode):
            return L10n.format(
                "Apply %@?",
                language: language,
                L10n.text(mode.label, language: language)
            )
        case .nrBandLock: return L10n.text("Lock NR bands?", language: language)
        case .lteBandLock: return L10n.text("Lock LTE bands?", language: language)
        case .restoreDefaults: return L10n.text("Restore automatic defaults?", language: language)
        }
    }

    func message(
        language: AppLanguage,
        modemKind: ModemKind?,
        preferenceLifetime: ModemPreferenceLifetime
    ) -> String {
        switch self {
        case .scan:
            if modemKind == .vos5G {
                return L10n.text(
                    "On VOS 5G, the app first switches to verified LTE-only mode, performs the scan, and then restores the exact previous LTE/SA/NSA preference. Data will be interrupted during this process.",
                    language: language
                )
            }
            return L10n.text("A full operator scan can take several minutes and may temporarily interrupt cellular data.", language: language)
        case let .manualNetwork(network):
            return L10n.format(
                "The modem will try %@ (%@) using this exact scan result. Registration and data may be interrupted.",
                language: language,
                network.displayName,
                network.formattedPLMN
            )
        case .automaticNetwork:
            return L10n.text("The modem will return to automatic operator selection. The resulting selection mode will be read back and verified.", language: language)
        case .architecture:
            return L10n.format(
                "This changes the modem's radio access mode. Exact values are read back; a failed change triggers an automatic rollback. Selected operator settings are not changed. %@",
                language: language,
                persistenceSentence(preferenceLifetime, language: language)
            )
        case let .nrBandLock(bands):
            return bands.isEmpty
                ? L10n.text("The NR band list is invalid.", language: language)
                : L10n.format(
                    "Allow only NR bands %@. The exact values will be read back and a failed change will be rolled back. %@",
                    language: language,
                    bands.sorted().map(String.init).joined(separator: ", "),
                    persistenceSentence(preferenceLifetime, language: language)
                )
        case let .lteBandLock(bands):
            return bands.isEmpty
                ? L10n.text("The LTE band list is invalid.", language: language)
                : L10n.format(
                    "Allow only LTE bands %@. The exact values will be read back and a failed change will be rolled back. %@",
                    language: language,
                    bands.sorted().map(String.init).joined(separator: ", "),
                    persistenceSentence(preferenceLifetime, language: language)
                )
        case .restoreDefaults:
            if modemKind == .zteMC7530CA {
                return L10n.text("This clears configured LTE, SA and NSA band locks and LTE/NR cell locks, restores the modem's vendor band defaults, and returns operator selection to automatic. The result will be read back and verified.", language: language)
            }
            return L10n.text("This restores the original LTE, SA and NSA masks captured in this app session and returns operator selection to automatic. Both results will be read back and verified.", language: language)
        }
    }

    private func persistenceSentence(
        _ lifetime: ModemPreferenceLifetime,
        language: AppLanguage
    ) -> String {
        switch lifetime {
        case .untilPowerLoss:
            return L10n.text("The setting lasts until the modem loses power.", language: language)
        case .persistent:
            return L10n.text("The setting persists across restarts until it is changed or restored.", language: language)
        case .unknown:
            return L10n.text("The modem did not report whether the setting persists across restarts.", language: language)
        }
    }

    func buttonTitle(language: AppLanguage) -> String {
        switch self {
        case .scan: return L10n.text("Scan", language: language)
        case .manualNetwork: return L10n.text("Select", language: language)
        case .automaticNetwork: return L10n.text("Use Automatic", language: language)
        case .architecture, .nrBandLock, .lteBandLock: return L10n.text("Apply", language: language)
        case .restoreDefaults: return L10n.text("Restore", language: language)
        }
    }

    var canConfirm: Bool {
        switch self {
        case let .nrBandLock(bands), let .lteBandLock(bands): return !bands.isEmpty
        default: return true
        }
    }
}

private struct ScannedNetworkRow: View {
    @Environment(\.appLanguage) private var language

    let network: CellularNetwork
    let isDisabled: Bool
    let select: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 9) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(network.displayName)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text(network.formattedPLMN)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 5) {
                    NetworkStatusBadge(availability: network.availability)
                    if network.supportsLTE {
                        AccessBadge(title: "LTE")
                    }
                    if network.supportsNR {
                        AccessBadge(title: "NR")
                    }
                    if !network.accessTechnologyLabel.isEmpty {
                        Text(network.accessTechnologyLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 4)
            Button(L10n.text("Select", language: language), action: select)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isDisabled || network.availability == .current || network.availability == .forbidden)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct NetworkStatusBadge: View {
    @Environment(\.appLanguage) private var language

    let availability: NetworkAvailability

    var body: some View {
        Text(L10n.text(availability.label, language: language))
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var color: Color {
        switch availability {
        case .current: return AppPalette.blue
        case .available: return .green
        case .forbidden: return .red
        case .unknown: return .secondary
        }
    }
}

private struct AccessBadge: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(AppPalette.blue)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(AppPalette.blue.opacity(0.10), in: Capsule())
    }
}

private struct StatusBadge: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appLanguage) private var language

    let state: ConnectionState

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(L10n.text(state.label, language: language))
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(color.opacity(0.12), in: Capsule())
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch state {
        case .online: return .green
        case .connecting: return AppPalette.blue
        case .stale: return .orange
        case .disconnected, .authenticationFailed: return .red
        case .qmiUnavailable: return .orange
        }
    }
}

private struct RadioCard: View {
    @Environment(\.appLanguage) private var language

    let title: String
    let radio: RadioKind
    let accent: Color
    let surfaceAccent: Color
    let band: String
    let frequency: Double?
    let channelLabel: String
    let channel: String?
    let bandwidth: Double?
    let signal: RadioSignal
    let globalCellID: UInt64?
    let mcc: String?
    let mnc: String?
    let raw: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent)
                Spacer()
                SignalBars(signal: signal.rsrpDBm, accent: accent)
            }
            Text(band)
                .font(.system(size: 24, weight: .bold, design: .rounded))

            HStack(spacing: 4) {
                if let frequency {
                    Text(DeviceSnapshot.frequencyText(frequency))
                }
                if frequency != nil, bandwidth != nil {
                    Text("·")
                }
                if let bandwidth {
                    Text(DeviceSnapshot.bandwidthText(bandwidth))
                }
                if frequency == nil, bandwidth == nil {
                    Text(L10n.text("Carrier details unavailable", language: language))
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .help(channelDetail)

            if let globalCellID {
                HStack(spacing: 8) {
                    CellIDLink(
                        cellID: globalCellID,
                        radio: radio,
                        mcc: mcc,
                        mnc: mnc
                    )
                }
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 2),
                alignment: .leading,
                spacing: 7
            ) {
                SignalMetric(label: "RSRP", value: signal.rsrpDBm.map { "\($0) dBm" })
                SignalMetric(label: "RSRQ", value: signal.rsrqDB.map { Self.metricText($0, unit: "dB") })
                SignalMetric(label: "SNR", value: signal.snrDB.map { Self.metricText($0, unit: "dB") })
                SignalMetric(label: "RSSI", value: signal.rssiDBm.map { "\($0) dBm" })
            }
        }
        .frame(maxWidth: .infinity, minHeight: 156, alignment: .topLeading)
        .cardStyle(accent: surfaceAccent)
    }

    private var channelDetail: String {
        if let channel { return "\(channelLabel) \(channel)" }
        return raw ?? L10n.text("Channel unavailable", language: language)
    }

    private static func metricText(_ value: Double, unit: String) -> String {
        let number = value.rounded() == value ? "\(Int(value))" : String(format: "%.1f", value)
        return "\(number) \(unit)"
    }

    fileprivate static func cellIDText(_ value: UInt64) -> String {
        String(value)
    }
}

private struct SignalMetric: View {
    let label: String
    let value: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value ?? "—")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct LTECarrierAggregationCard: View {
    @State private var isExpanded = false
    @Environment(\.appLanguage) private var language

    let primaryCell: LTECarrier?
    let secondaryCells: [LTECarrier]
    let mcc: String?
    let mnc: String?

    var body: some View {
        CollapsibleCard(
            isExpanded: $isExpanded,
            accessibilityLabel: "LTE CA",
            accent: AppPalette.blue
        ) {
            VStack(spacing: 8) {
                if let primaryCell {
                    LTECarrierRow(carrier: primaryCell, mcc: mcc, mnc: mnc)
                }
                ForEach(Array(secondaryCells.enumerated()), id: \.offset) { _, carrier in
                    LTECarrierRow(carrier: carrier, mcc: mcc, mnc: mnc)
                }
            }
            .padding(.top, 9)
        } label: {
            HStack(spacing: 8) {
                Label("LTE CA", systemImage: "square.stack.3d.up")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 6)
                Text(combination)
                    .font(.caption.monospaced().weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var combination: String {
        let active = secondaryCells.filter { $0.state == .active }
        var bands = [primaryCell?.band].compactMap { $0 }
        bands.append(contentsOf: active.compactMap(\.band))
        if active.isEmpty {
            return bands.first.map {
                L10n.format("%@ only", language: language, $0)
            } ?? L10n.text("No active SCell", language: language)
        }
        return bands.joined(separator: "+")
    }
}

private struct LTECarrierRow: View {
    @Environment(\.appLanguage) private var language

    let carrier: LTECarrier
    let mcc: String?
    let mnc: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                Text(carrier.role.localizedLabel(language: language))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(carrier.band ?? L10n.text("Unknown", language: language))
                    .font(.caption.monospaced().weight(.semibold))
                Spacer(minLength: 4)
                if let state = carrier.state {
                    Text(state.localizedLabel(language: language))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(state == .active ? AppPalette.blue : .secondary)
                }
            }

            HStack(spacing: 5) {
                if let frequency = carrier.downlinkFrequencyMHz {
                    Text(DeviceSnapshot.frequencyText(frequency))
                }
                if let bandwidth = carrier.bandwidthMHz {
                    Text(DeviceSnapshot.bandwidthText(bandwidth))
                }
                if let cellID = carrier.globalCellID {
                    CellIDLink(cellID: cellID, radio: .lte, mcc: mcc, mnc: mnc)
                } else {
                    Text("Cell ID —")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)

            HStack(spacing: 10) {
                CompactSignalMetric(label: "RSRP", value: carrier.signal.rsrpDBm.map { "\($0)" })
                CompactSignalMetric(label: "RSRQ", value: carrier.signal.rsrqDB.map(Self.metricText))
                CompactSignalMetric(label: "RSSI", value: carrier.signal.rssiDBm.map { "\($0)" })
                CompactSignalMetric(label: "SNR", value: carrier.signal.snrDB.map(Self.metricText))
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .help("EARFCN \(carrier.earfcn)")
    }

    private static func metricText(_ value: Double) -> String {
        value.rounded() == value ? "\(Int(value))" : String(format: "%.1f", value)
    }
}

private struct CellIDLink: View {
    @Environment(\.appLanguage) private var language

    let cellID: UInt64
    let radio: RadioKind
    let mcc: String?
    let mnc: String?

    var body: some View {
        if let destination = CellMapperLink.destination(
            for: cellID,
            radio: radio,
            mcc: mcc,
            mnc: mnc
        ) {
            Button(action: { open(destination) }) {
                Text("Cell ID \(RadioCard.cellIDText(cellID))")
                    .underline()
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppPalette.blue)
            .help(helpText)
            .accessibilityAddTraits(.isLink)
        } else {
            Text("Cell ID \(RadioCard.cellIDText(cellID))")
        }
    }

    private var helpText: String {
        switch radio {
        case .lte:
            return L10n.text("Open this Cell ID in CellMapper's LTE calculator", language: language)
        case .nr:
            return L10n.text("Copy this Cell ID and open the matching operator's NR map in CellMapper", language: language)
        }
    }

    private func open(_ destination: URL) {
        if CellMapperLink.copiesCellIDBeforeOpening(radio: radio) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(String(cellID), forType: .string)
        }
        NSWorkspace.shared.open(destination)
    }
}

private struct LTENeighborRow: View {
    let cell: LTECellNeighbor

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(cell.band ?? "LTE")
                    .font(.caption.monospaced().weight(.semibold))
                Spacer()
                Text("EARFCN \(cell.earfcn)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                CompactSignalMetric(label: "RSRP", value: cell.signal.rsrpDBm.map { "\($0)" })
                CompactSignalMetric(label: "RSRQ", value: cell.signal.rsrqDB.map(Self.metricText))
                CompactSignalMetric(label: "RSSI", value: cell.signal.rssiDBm.map { "\($0)" })
                CompactSignalMetric(label: "SNR", value: cell.signal.snrDB.map(Self.metricText))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private static func metricText(_ value: Double) -> String {
        value.rounded() == value ? "\(Int(value))" : String(format: "%.1f", value)
    }
}

private struct CompactSignalMetric: View {
    let label: String
    let value: String?

    var body: some View {
        HStack(spacing: 2) {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value ?? "—")
                .foregroundStyle(.primary)
        }
        .font(.system(size: 9, weight: .medium, design: .rounded))
        .monospacedDigit()
        .lineLimit(1)
    }
}

private struct SignalBars: View {
    @Environment(\.appLanguage) private var language

    let signal: Int?
    let accent: Color

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(index < level ? accent : Color.secondary.opacity(0.2))
                    .frame(width: 3.5, height: CGFloat(5 + index * 3))
            }
        }
        .frame(height: 14)
        .accessibilityLabel(
            signal.map {
                L10n.format("Signal %@ dBm", language: language, String($0))
            } ?? L10n.text("Signal unavailable", language: language)
        )
    }

    private var level: Int {
        guard let signal else { return 0 }
        if signal > -85 { return 4 }
        if signal > -100 { return 3 }
        if signal > -115 { return 2 }
        if signal > -125 { return 1 }
        return 0
    }
}

private struct DetailRow: View {
    let label: String
    let value: String
    var compact = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .fontWeight(.medium)
                .lineLimit(compact ? 1 : 2)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
                .monospacedDigit()
                .textSelection(.enabled)
        }
        .font(compact ? .caption2 : .caption)
    }
}

/// A disclosure card whose complete header row is the control. The native
/// macOS `DisclosureGroup` gives most of its hit target to the small chevron;
/// this keeps the familiar appearance while making the icon, title and empty
/// trailing space behave as one accessible button.
struct CollapsibleCard<Content: View, Header: View>: View {
    @Binding private var isExpanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appLanguage) private var language
    @State private var isHeaderHovered = false

    private let accessibilityLabel: String
    private let accent: Color?
    private let content: Content
    private let header: Header

    init(
        isExpanded: Binding<Bool>,
        accessibilityLabel: String,
        accent: Color? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder label: () -> Header
    ) {
        _isExpanded = isExpanded
        self.accessibilityLabel = accessibilityLabel
        self.accent = accent
        self.content = content()
        header = label()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(isExpanded ? .degrees(90) : .zero)
                        .frame(width: 10)
                        .accessibilityHidden(true)
                    header
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
                .background(
                    Color.primary.opacity(isHeaderHovered ? 0.055 : 0),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .onHover { isHeaderHovered = $0 }
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(
                L10n.text(isExpanded ? "Expanded" : "Collapsed", language: language)
            )
            .accessibilityHint(
                L10n.text(isExpanded ? "Collapse section" : "Expand section", language: language)
            )

            if isExpanded {
                content
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(accent: accent)
    }

    private func toggle() {
        if reduceMotion {
            isExpanded.toggle()
        } else {
            withAnimation(.easeInOut(duration: 0.16)) {
                isExpanded.toggle()
            }
        }
    }
}

private struct CardStyle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    var prominent = false
    var tint: Color?
    var accent: Color?

    func body(content: Content) -> some View {
        content
            .padding(prominent ? 13 : 11)
            .background {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(background)
                    }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(border, lineWidth: 0.5)
            )
    }

    private var background: Color {
        if let tint { return tint.opacity(0.09) }
        if prominent {
            return Color(nsColor: .controlBackgroundColor)
                .opacity(colorScheme == .dark ? 0.38 : 0.52)
        }
        return Color(nsColor: .controlBackgroundColor)
            .opacity(colorScheme == .dark ? 0.28 : 0.42)
    }

    private var border: Color {
        if let tint { return tint.opacity(0.18) }
        if let accent { return accent.opacity(0.14) }
        return Color.primary.opacity(0.075)
    }
}

extension View {
    func cardStyle(prominent: Bool = false, tint: Color? = nil, accent: Color? = nil) -> some View {
        modifier(CardStyle(prominent: prominent, tint: tint, accent: accent))
    }
}

private struct ContentHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ChromeHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value += nextValue()
    }
}
