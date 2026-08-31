import AppKit
import SwiftUI

private enum AppPalette {
    static let blue = Color(nsColor: .systemBlue)
    static let cyan = Color(nsColor: .systemCyan)
}

struct StatusPanel: View {
    @EnvironmentObject private var model: StatusModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showSettings = false
    @State private var showDeviceDetails = false
    @State private var launchAtLogin = false
    @State private var launchError: String?
    @State private var measuredContentHeight: CGFloat = 320
    @State private var measuredChromeHeight: CGFloat = 96

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
                        deviceDetailsCard
                            .id("device-details")
                        if showSettings {
                            settingsCard
                                .id("settings")
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
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
                .accessibilityLabel("Modem status")
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
        .animation(.easeInOut(duration: 0.2), value: scrollViewportHeight)
    }

    private var panelSeparator: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.07))
            .frame(height: 0.5)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(secondaryAccent)
                .frame(width: 30, height: 30)
                .background(AppPalette.blue.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("Cellular Modem Monitor")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Text(headerSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(headerSubtitle)
            }
            .layoutPriority(1)

            Spacer()

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
            .help("Refresh now")
            .accessibilityLabel("Refresh now")
            .disabled(model.isRefreshing)
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
                Text("CURRENT CONNECTION")
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

            if model.snapshot.nrBand != nil, model.snapshot.nrSystemMode != nil {
                Label("Confirmed by Qualcomm DSD", systemImage: "checkmark.seal")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if model.snapshot.nrBand != nil {
                Label("SA/NSA unavailable — not inferred", systemImage: "info.circle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if !model.snapshot.hasRadioData {
                Text("Waiting for current radio information")
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
                        title: "5G NR",
                        icon: "antenna.radiowaves.left.and.right",
                        accent: secondaryAccent,
                        surfaceAccent: AppPalette.cyan,
                        band: band,
                        channelLabel: "NR-ARFCN",
                        channel: model.snapshot.nrChannel,
                        bandwidth: model.snapshot.nrBandwidthMHz,
                        signal: model.snapshot.nrSignalDBm,
                        raw: model.snapshot.nrRaw
                    )
                }
                if let band = model.snapshot.lteBand {
                    RadioCard(
                        title: "LTE",
                        icon: "cellularbars",
                        accent: AppPalette.blue,
                        surfaceAccent: AppPalette.blue,
                        band: band,
                        channelLabel: "EARFCN",
                        channel: model.snapshot.lteChannel,
                        bandwidth: model.snapshot.lteBandwidthMHz,
                        signal: model.snapshot.lteSignalDBm,
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
        HStack(spacing: 10) {
            Label("LTE CA", systemImage: "square.stack.3d.up")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            FlowLayout(spacing: 6) {
                ForEach(model.snapshot.lteSecondaryCells, id: \.self) { cell in
                    Text(cell)
                        .font(.caption.monospaced())
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(AppPalette.blue.opacity(0.16), in: Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(accent: AppPalette.blue)
    }

    private var deviceDetailsCard: some View {
        DisclosureGroup(isExpanded: $showDeviceDetails) {
            VStack(spacing: 9) {
                DetailRow(label: "USB network", value: model.snapshot.interfaceName ?? "Not detected")
                DetailRow(label: "Device", value: "VOS 5G")
                DetailRow(label: "Management", value: model.snapshot.host)
                DetailRow(label: "Source", value: "SSH → QRTR/QMI")
                if let version = model.snapshot.moduleVersion {
                    DetailRow(label: "Modem firmware", value: version)
                }
                if let firmware = model.snapshot.deviceFirmware {
                    DetailRow(label: "VOS firmware", value: firmware)
                }
            }
            .padding(.top, 9)
        } label: {
            Label("Device details", systemImage: "info.circle")
                .font(.subheadline.weight(.semibold))
        }
        .cardStyle()
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("Connection")
                .font(.subheadline.weight(.semibold))

            LabeledContent("Address") {
                TextField("192.168.225.1", text: $model.host)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 190)
            }
            LabeledContent("SSH user") {
                TextField("root", text: $model.username)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 190)
            }
            LabeledContent("SSH password") {
                SecureField("oelinux123", text: $model.password)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 190)
            }
            LabeledContent("Refresh") {
                Picker("", selection: $model.refreshInterval) {
                    Text("1 second").tag(1.0)
                    Text("5 seconds").tag(5.0)
                    Text("10 seconds").tag(10.0)
                    Text("15 seconds").tag(15.0)
                    Text("30 seconds").tag(30.0)
                    Text("1 minute").tag(60.0)
                }
                .labelsHidden()
                .frame(width: 190)
            }
            LabeledContent("Menu bar") {
                Picker("", selection: $model.menuBarStyle) {
                    ForEach(MenuBarStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .labelsHidden()
                .frame(width: 190)
            }

            Toggle("Open at Login", isOn: Binding(
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

            HStack {
                Text("Factory VOS SSH: root / oelinux123")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Save") {
                    model.saveSettings()
                    showSettings = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .cardStyle()
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
                Label("Copy", systemImage: "doc.on.doc")
            }
            .buttonStyle(.borderless)

            Spacer()

            Menu {
                Button(showSettings ? "Hide Settings" : "Settings…") {
                    showSettings.toggle()
                }
                Button("Open Device Web UI", action: model.openWebUI)
                Button("About Cellular Modem Monitor", action: model.showAbout)
                Divider()
                Button("Quit Cellular Modem Monitor", role: .destructive, action: model.quit)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("Application menu")
            .accessibilityLabel("Application menu")
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
        return model.snapshot.updatedAt.formatted(.relative(presentation: .named))
    }

    private var headerSubtitle: String {
        let operatorName = model.snapshot.operatorName ?? "Local modem"
        guard let plmn = model.snapshot.plmn else { return operatorName }
        return "\(operatorName) · \(plmn)"
    }

    private var secondaryAccent: Color {
        colorScheme == .dark ? AppPalette.cyan : AppPalette.blue
    }

    private var maximumPanelHeight: CGFloat {
        max(300, (NSScreen.main?.visibleFrame.height ?? 760) - 24)
    }

    private var scrollViewportHeight: CGFloat {
        let separators: CGFloat = 1
        let available = max(140, maximumPanelHeight - measuredChromeHeight - separators)
        return min(measuredContentHeight, available)
    }
}

private struct StatusBadge: View {
    @Environment(\.colorScheme) private var colorScheme

    let state: ConnectionState

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(state.label)
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
    let title: String
    let icon: String
    let accent: Color
    let surfaceAccent: Color
    let band: String
    let channelLabel: String
    let channel: String?
    let bandwidth: Double?
    let signal: Int?
    let raw: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: icon)
                        .foregroundStyle(accent)
                    Text(title)
                        .foregroundStyle(.secondary)
                }
                    .font(.caption.weight(.semibold))
                Spacer()
                SignalBars(signal: signal, accent: accent)
            }
            Text(band)
                .font(.system(size: 24, weight: .bold, design: .rounded))
            if let channel {
                DetailRow(label: channelLabel, value: channel, compact: true)
            }
            if let bandwidth {
                DetailRow(label: "Bandwidth", value: DeviceSnapshot.bandwidthText(bandwidth), compact: true)
            }
            DetailRow(label: "RSRP", value: signal.map { "\($0) dBm" } ?? "—", compact: true)
            if channel == nil, let raw, raw.localizedCaseInsensitiveContains("ARFCN") {
                Text(raw)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 126, alignment: .topLeading)
        .cardStyle(accent: surfaceAccent)
    }
}

private struct SignalBars: View {
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
        .accessibilityLabel(signal.map { "Signal \($0) dBm" } ?? "Signal unavailable")
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

private extension View {
    func cardStyle(prominent: Bool = false, tint: Color? = nil, accent: Color? = nil) -> some View {
        modifier(CardStyle(prominent: prominent, tint: tint, accent: accent))
    }
}

private struct ContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ChromeHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value += nextValue()
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: ProposedViewSize(width: bounds.width, height: proposal.height), subviews: subviews)
        for (index, point) in result.points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        var points: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var contentWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                contentWidth = max(contentWidth, max(0, x - spacing))
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        contentWidth = max(contentWidth, max(0, x - spacing))
        return (CGSize(width: min(maxWidth, contentWidth), height: y + lineHeight), points)
    }
}
