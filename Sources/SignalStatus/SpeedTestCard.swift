import SwiftUI

struct SpeedTestCard: View {
    @ObservedObject var speedTest: SpeedTestModel
    @Environment(\.appLanguage) private var language
    @State private var isExpanded = false

    var body: some View {
        CollapsibleCard(
            isExpanded: $isExpanded,
            accessibilityLabel: L10n.text("Speed test", language: language),
            accent: .blue
        ) {
            VStack(alignment: .leading, spacing: 10) {
                if let interfaceName = speedTest.boundInterfaceName {
                    HStack(spacing: 5) {
                        Text(L10n.text("Bound interface", language: language))
                            .foregroundStyle(.secondary)
                        Text(interfaceName)
                            .fontWeight(.semibold)
                            .monospaced()
                    }
                    .font(.caption)
                }

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
                        if let responsiveness = result.responsivenessRPM {
                            SpeedTestDetailRow(
                                label: L10n.text("Responsiveness", language: language),
                                value: String(format: "%.0f RPM", responsiveness)
                            )
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

                Text(routeVerificationNote)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Label(
                    L10n.text(
                        "Speed tests can use a substantial amount of cellular data.",
                        language: language
                    ),
                    systemImage: "exclamationmark.circle"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)

                HStack {
                    Spacer()
                    if speedTest.isRunning {
                        Button(L10n.text("Cancel", language: language)) {
                            speedTest.cancel()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else {
                        Button(action: speedTest.start) {
                            Label(
                                L10n.text(
                                    isCompleted ? "Test again" : "Start speed test",
                                    language: language
                                ),
                                systemImage: "gauge.with.dots.needle.67percent"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(!speedTest.canStart)
                    }
                }
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

    private var routeVerificationNote: String {
        if speedTest.boundConnectionPath == .routed {
            return L10n.text(
                "Traffic is pinned to the shown Mac interface and the final result must report that same interface. Live rates may include other traffic on it. Beyond the router, WAN, VPN and multi-WAN selection remain controlled by the router.",
                language: language
            )
        }
        return L10n.text(
            "Traffic is pinned to the shown modem interface and the final result must report that same interface. Live rates use interface counters and may include other traffic; final rates come from macOS networkQuality.",
            language: language
        )
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
            Text(value).fontWeight(.medium).monospacedDigit()
        }
        .font(.caption)
    }
}
