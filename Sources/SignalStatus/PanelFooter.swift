import SwiftUI

/// Direct, equal-width actions remain legible at the narrow panel width.
/// Confirmation stays inside the menu-bar window (no transient alert/sheet).
struct PanelFooter: View {
    @Environment(\.appLanguage) private var language
    @Binding var pendingRestart: ModemRestartTarget?
    let target: ModemRestartTarget?
    let canRestart: Bool
    let isRestarting: Bool
    let notice: String?
    let error: String?
    let willConfirmRestart: () -> Void
    let restart: (ModemRestartTarget) -> Void
    let dismissMessage: () -> Void
    let action: (PanelFooterAction) -> Void

    var body: some View {
        VStack(spacing: 8) {
            if let pending = pendingRestart {
                VStack(alignment: .leading, spacing: 8) {
                    Label(L10n.text("Restart device?", language: language), systemImage: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                    Text(pending.displayName)
                        .font(.caption.weight(.medium))
                    Text(pending.endpoint.baseURL.absoluteString)
                        .font(.caption2.monospaced()).foregroundStyle(.secondary)
                    Text(L10n.text("The modem will disconnect briefly. Monitoring resumes automatically.", language: language))
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Spacer()
                        Button(L10n.text("Cancel", language: language)) { pendingRestart = nil }
                            .keyboardShortcut(.cancelAction)
                            .accessibilityIdentifier("restart-cancel")
                        Button(L10n.text("Restart device", language: language)) {
                            pendingRestart = nil
                            restart(pending)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canRestart || pending != target)
                        .accessibilityIdentifier("restart-confirm")
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }

            if isRestarting || error != nil || notice != nil {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: error == nil ? "info.circle" : "exclamationmark.triangle")
                    Text(isRestarting ? L10n.text("Requesting restart…", language: language) : error ?? notice ?? "")
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if !isRestarting {
                        Button(action: dismissMessage) { Image(systemName: "xmark") }
                            .buttonStyle(.plain)
                            .help(L10n.text("Dismiss", language: language))
                            .accessibilityLabel(L10n.text("Dismiss", language: language))
                    }
                }
                .font(.caption2)
                .foregroundStyle(error == nil ? Color.secondary : Color.orange)
                .padding(.horizontal, 4)
            }

            HStack(spacing: 2) {
                ForEach(PanelFooterAction.allCases, id: \.self) { item in
                    Button {
                        if item == .restart, let target {
                            willConfirmRestart()
                            pendingRestart = target
                            dismissMessage()
                        } else {
                            action(item)
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: item.symbol).font(.system(size: 14, weight: .medium))
                                .frame(height: 16)
                            Text(L10n.text(item.title, language: language))
                                .font(.system(size: 10, weight: .medium))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(FooterActionStyle())
                    .disabled(item == .restart && !canRestart)
                    .help(L10n.text(item.help, language: language))
                    .accessibilityLabel(L10n.text(item.help, language: language))
                    .accessibilityIdentifier("footer-\(item.rawValue)")
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .onChange(of: target) { _ in pendingRestart = nil }
    }
}

private struct FooterActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? Color.primary.opacity(0.8) : Color.secondary.opacity(0.45))
            .background(
                Color.primary.opacity(isEnabled && configuration.isPressed ? 0.12 : isEnabled && isHovered ? 0.06 : 0),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .onHover { isHovered = $0 }
    }
}
