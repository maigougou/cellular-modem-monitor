import SwiftUI

struct SpeedTestCard: View {
    @ObservedObject var networkQuality: SpeedTestModel
    @ObservedObject var ookla: SpeedTestModel
    @Environment(\.appLanguage) private var language
    @State private var isExpanded = false

    var body: some View {
        CollapsibleCard(
            isExpanded: $isExpanded,
            accessibilityLabel: L10n.text("Speed test", language: language),
            accent: .blue
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if let interfaceName = boundInterfaceName {
                    HStack(spacing: 5) {
                        Text(L10n.text("Bound interface", language: language))
                            .foregroundStyle(.secondary)
                        Text(interfaceName)
                            .fontWeight(.semibold)
                            .monospaced()
                    }
                    .font(.caption)
                }

                SpeedTestEngineSection(
                    kind: .networkQuality,
                    speedTest: networkQuality,
                    anotherTestIsRunning: ookla.isRunning
                )

                Divider().opacity(0.55)

                SpeedTestEngineSection(
                    kind: .ookla,
                    speedTest: ookla,
                    anotherTestIsRunning: networkQuality.isRunning
                )

                Text(routeVerificationNote)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Label(
                    L10n.text(
                        "Running both tests can use a substantial amount of cellular data.",
                        language: language
                    ),
                    systemImage: "exclamationmark.circle"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .padding(.top, 10)
        } label: {
            Label(
                L10n.text("Speed test", language: language),
                systemImage: "gauge.with.dots.needle.67percent"
            )
            .font(.subheadline.weight(.semibold))
        }
    }

    private var boundInterfaceName: String? {
        networkQuality.boundInterfaceName ?? ookla.boundInterfaceName
    }

    private var routeVerificationNote: String {
        if networkQuality.boundConnectionPath == .routed || ookla.boundConnectionPath == .routed {
            return L10n.text(
                "Each test is pinned to the shown Mac interface and its final result must identify that same interface. Live rates may include other traffic on it. Beyond the router, WAN, VPN and multi-WAN selection remain controlled by the router.",
                language: language
            )
        }
        return L10n.text(
            "Each test is pinned to the shown modem interface and its final result must identify that same interface. Live rates use interface counters and may include other traffic; final rates come from the named test tool.",
            language: language
        )
    }
}

private enum SpeedTestEngineKind {
    case networkQuality
    case ookla

    var title: String {
        switch self {
        case .networkQuality: return "macOS networkQuality"
        case .ookla: return "Ookla Speedtest CLI"
        }
    }

    var icon: String {
        switch self {
        case .networkQuality: return "apple.logo"
        case .ookla: return "speedometer"
        }
    }

    var startLabel: String {
        switch self {
        case .networkQuality: return "Run macOS test"
        case .ookla: return "Run Ookla test"
        }
    }
}

private struct SpeedTestEngineSection: View {
    let kind: SpeedTestEngineKind
    @ObservedObject var speedTest: SpeedTestModel
    let anotherTestIsRunning: Bool
    @Environment(\.appLanguage) private var language

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(L10n.text(kind.title, language: language), systemImage: kind.icon)
                .font(.caption.weight(.semibold))

            HStack(spacing: 8) {
                SpeedTestRateTile(
                    title: L10n.text("Download", language: language),
                    systemImage: "arrow.down",
                    value: displayedDownload
                )
                SpeedTestRateTile(
                    title: L10n.text("Upload", language: language),
                    systemImage: "arrow.up",
                    value: displayedUpload
                )
            }

            stateDetails

            if kind == .ookla {
                HStack(spacing: 4) {
                    Text(L10n.text(
                        "Uses the separately installed official Ookla CLI.",
                        language: language
                    ))
                    Link(
                        L10n.text("Ookla terms", language: language),
                        destination: URL(string: "https://www.speedtest.net/about/eula")!
                    )
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            HStack {
                if kind == .ookla, showsInstallLink {
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
                            L10n.text(isCompleted ? "Test again" : kind.startLabel, language: language),
                            systemImage: "gauge.with.dots.needle.67percent"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!speedTest.canStart || anotherTestIsRunning)
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
            VStack(spacing: 6) {
                if let latency = result.idleLatencyMilliseconds {
                    SpeedTestDetailRow(
                        label: L10n.text("Idle latency", language: language),
                        value: String(format: "%.0f ms", latency)
                    )
                }
                if let jitter = result.jitterMilliseconds {
                    SpeedTestDetailRow(
                        label: L10n.text("Jitter", language: language),
                        value: String(format: "%.1f ms", jitter)
                    )
                }
                if let responsiveness = result.responsivenessRPM {
                    SpeedTestDetailRow(
                        label: L10n.text("Responsiveness", language: language),
                        value: String(format: "%.0f RPM", responsiveness)
                    )
                }
                if let packetLoss = result.packetLossPercent {
                    SpeedTestDetailRow(
                        label: L10n.text("Packet loss", language: language),
                        value: String(format: "%.1f%%", packetLoss)
                    )
                }
                if let server = result.serverName {
                    SpeedTestDetailRow(
                        label: L10n.text("Server", language: language),
                        value: server
                    )
                }
                if let resultURL = result.resultURL {
                    HStack {
                        Spacer()
                        Link(L10n.text("View result", language: language), destination: resultURL)
                            .font(.caption)
                    }
                }
            }
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
        guard kind == .ookla else { return false }
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

    private var displayedDownload: String {
        switch speedTest.state {
        case let .running(progress):
            return Self.rate(progress.downloadBitsPerSecond)
        case let .completed(result):
            return Self.rate(result.downloadBitsPerSecond)
        default:
            return "—"
        }
    }

    private var displayedUpload: String {
        switch speedTest.state {
        case let .running(progress):
            return Self.rate(progress.uploadBitsPerSecond)
        case let .completed(result):
            return Self.rate(result.uploadBitsPerSecond)
        default:
            return "—"
        }
    }

    private static func rate(_ bitsPerSecond: Double) -> String {
        guard bitsPerSecond.isFinite, bitsPerSecond >= 0 else { return "—" }
        if bitsPerSecond >= 1_000_000_000 {
            return String(format: "%.2f Gbps", bitsPerSecond / 1_000_000_000)
        }
        if bitsPerSecond >= 1_000_000 {
            return String(format: "%.1f Mbps", bitsPerSecond / 1_000_000)
        }
        return String(format: "%.0f Kbps", bitsPerSecond / 1_000)
    }
}

private struct SpeedTestRateTile: View {
    let title: String
    let systemImage: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: systemImage)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.body, design: .rounded).weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
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
