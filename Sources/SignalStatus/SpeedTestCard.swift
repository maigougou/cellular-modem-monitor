import SwiftUI

struct SpeedTestCard: View {
    @ObservedObject var speedTest: SpeedTestModel
    @Environment(\.appLanguage) private var language
    @State private var isExpanded: Bool

    init(speedTest: SpeedTestModel, initiallyExpanded: Bool = false) {
        self.speedTest = speedTest
        _isExpanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        CollapsibleCard(
            isExpanded: $isExpanded,
            accessibilityLabel: L10n.text("Speed test", language: language),
            accent: .blue
        ) {
            SpeedTestEngineSection(
                speedTest: speedTest,
                routeVerificationNote: routeVerificationNote
            )
            .padding(.top, 8)
        } label: {
            Label(
                L10n.text("Speed test", language: language),
                systemImage: "gauge.with.dots.needle.67percent"
            )
            .font(.subheadline.weight(.semibold))
        }
    }

    private var routeVerificationNote: String {
        if speedTest.boundConnectionPath == .routed {
            return L10n.text(
                "Traffic is pinned to the shown Mac interface and the final result must report that same interface. Live rates may include other traffic on it. Beyond the router, WAN, VPN and multi-WAN selection remain controlled by the router.",
                language: language
            )
        }
        return L10n.text(
            "Traffic is pinned to the shown modem interface and the final result must report that same interface. Live rates use interface counters and may include other traffic; final rates come from Ookla Speedtest CLI.",
            language: language
        )
    }
}

private struct SpeedTestInformationButton: View {
    @Environment(\.appLanguage) private var language
    @State private var isPresented = false
    let routeVerificationNote: String

    var body: some View {
        Button { isPresented.toggle() } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(PanelIconButtonStyle())
        .help(L10n.text("Test details", language: language))
        .accessibilityLabel(L10n.text("Test details", language: language))
        .popover(isPresented: $isPresented) {
            VStack(alignment: .leading, spacing: 12) {
                Label(L10n.text("Test details", language: language), systemImage: "speedometer")
                    .font(.headline)
                Text(routeVerificationNote)
                    .foregroundStyle(.secondary)
                Label(
                    L10n.text("Speed tests can use a substantial amount of cellular data.", language: language),
                    systemImage: "exclamationmark.circle"
                )
                .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Text(L10n.text("Uses the separately installed official Ookla CLI.", language: language))
                    Link(
                        L10n.text("Ookla terms", language: language),
                        destination: URL(string: "https://www.speedtest.net/about/eula")!
                    )
                }
                .foregroundStyle(.secondary)
            }
            .font(.callout)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .padding(18)
            .frame(width: 330, alignment: .leading)
        }
    }
}

private struct SpeedTestEngineSection: View {
    @ObservedObject var speedTest: SpeedTestModel
    @Environment(\.appLanguage) private var language
    let routeVerificationNote: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text(L10n.text("Ookla Speedtest CLI", language: language))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 6)
                if let interfaceName = speedTest.boundInterfaceName {
                    Label(interfaceName, systemImage: "point.3.connected.trianglepath.dotted")
                        .font(.caption2.monospaced().weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppPalette.inset, in: Capsule())
                        .help("\(L10n.text("Bound interface", language: language)) \(interfaceName)")
                }
                SpeedTestInformationButton(routeVerificationNote: routeVerificationNote)
            }

            HStack(spacing: 8) {
                SpeedTestRateTile(
                    title: L10n.text("Download", language: language),
                    systemImage: "arrow.down",
                    bitsPerSecond: displayedDownload,
                    accent: AppPalette.cyan
                )
                SpeedTestRateTile(
                    title: L10n.text("Upload", language: language),
                    systemImage: "arrow.up",
                    bitsPerSecond: displayedUpload,
                    accent: AppPalette.indigo
                )
            }

            stateDetails

            HStack {
                if case let .completed(result) = speedTest.state, let resultURL = result.resultURL {
                    Link(L10n.text("View result", language: language), destination: resultURL)
                        .font(.caption)
                }
                if showsInstallLink {
                    Link(
                        L10n.text("Install official CLI", language: language),
                        destination: URL(string: "https://www.speedtest.net/apps/cli")!
                    )
                    .font(.caption)
                }
                Spacer()
                if speedTest.isRunning {
                    Button(L10n.text("Cancel", language: language)) {
                        speedTest.cancel()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else if !showsInstallLink {
                    Button(action: speedTest.start) {
                        Label(
                            L10n.text(isCompleted ? "Test again" : "Run Ookla test", language: language),
                            systemImage: "gauge.with.dots.needle.67percent"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!speedTest.canStart)
                }
            }
        }
    }

    @ViewBuilder
    private var stateDetails: some View {
        switch speedTest.state {
        case let .running(progress):
            HStack(spacing: 7) {
                ProgressView().controlSize(.small)
                Text(L10n.format(
                    "Testing through %@ · %.0f s",
                    language: language,
                    speedTest.boundInterfaceName ?? "—",
                    progress.elapsed
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        case let .completed(result):
            VStack(spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    if let latency = result.idleLatencyMilliseconds {
                        SpeedTestCompactMetric(
                            label: L10n.text("Idle latency", language: language),
                            value: String(format: "%.0f ms", latency)
                        )
                    }
                    if let jitter = result.jitterMilliseconds {
                        SpeedTestCompactMetric(
                            label: L10n.text("Jitter", language: language),
                            value: String(format: "%.1f ms", jitter)
                        )
                    }
                    if let packetLoss = result.packetLossPercent {
                        SpeedTestCompactMetric(
                            label: L10n.text("Packet loss", language: language),
                            value: String(format: "%.1f%%", packetLoss)
                        )
                    }
                }
                if let server = result.serverName {
                    SpeedTestDetailRow(
                        label: L10n.text("Server", language: language),
                        value: server
                    )
                }
            }
            .padding(.vertical, 3)
        case let .unavailable(error), let .failed(error):
            Label(
                error.localizedMessage(language: language),
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.caption)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
        case .ready:
            EmptyView()
        }
    }

    private var showsInstallLink: Bool {
        switch speedTest.state {
        case .unavailable(.ooklaCLIUnavailable), .failed(.ooklaCLIUnavailable),
             .unavailable(.ooklaCLIIncompatible), .failed(.ooklaCLIIncompatible):
            return true
        default:
            return false
        }
    }

    private var isCompleted: Bool {
        if case .completed = speedTest.state { return true }
        return false
    }

    private var displayedDownload: Double? {
        switch speedTest.state {
        case let .running(progress):
            return progress.downloadBitsPerSecond
        case let .completed(result):
            return result.downloadBitsPerSecond
        default:
            return nil
        }
    }

    private var displayedUpload: Double? {
        switch speedTest.state {
        case let .running(progress):
            return progress.uploadBitsPerSecond
        case let .completed(result):
            return result.uploadBitsPerSecond
        default:
            return nil
        }
    }

}

private struct SpeedTestRateTile: View {
    let title: String
    let systemImage: String
    let bitsPerSecond: Double?
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: systemImage)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(accent)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(formattedRate.value)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                if let unit = formattedRate.unit {
                    Text(unit)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .insetSurface(accent: accent)
        .accessibilityElement(children: .combine)
    }

    private var formattedRate: (value: String, unit: String?) {
        guard let bitsPerSecond, bitsPerSecond.isFinite, bitsPerSecond >= 0 else { return ("—", nil) }
        if bitsPerSecond >= 1_000_000_000 {
            return (String(format: "%.2f", bitsPerSecond / 1_000_000_000), "Gbps")
        }
        if bitsPerSecond >= 1_000_000 {
            return (String(format: "%.1f", bitsPerSecond / 1_000_000), "Mbps")
        }
        return (String(format: "%.0f", bitsPerSecond / 1_000), "Kbps")
    }
}

private struct SpeedTestCompactMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.system(size: 13, weight: .medium)).monospacedDigit()
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct SpeedTestDetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .fontWeight(.medium)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
        .font(.caption)
    }
}
