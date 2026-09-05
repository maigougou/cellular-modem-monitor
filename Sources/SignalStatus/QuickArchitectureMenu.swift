import SwiftUI

struct QuickArchitectureMenu: View {
    @Environment(\.appLanguage) private var language
    let confirmedMode: NRArchitectureMode?
    let operation: NetworkControlOperation?
    let isEnabled: Bool
    let onSelect: (NRArchitectureMode) -> Void

    var body: some View {
        let state = QuickArchitectureMenuState(confirmedMode: confirmedMode, operation: operation)
        HStack(spacing: 5) {
            // Keep the native menu's textual label present in every state.
            // An indeterminate progress view is not a menu title and can leave
            // only the disclosure arrow visible while read-back is in flight.
            if state.isBusy {
                ProgressView()
                    .controlSize(.mini)
                    .accessibilityHidden(true)
            }
            Menu(state.title(language: language)) {
                ForEach(NRArchitectureMode.quickAccessModes) { mode in
                    Button {
                        onSelect(mode)
                    } label: {
                        if confirmedMode == mode {
                            Label(L10n.text(mode.label, language: language), systemImage: "checkmark")
                        } else {
                            Text(L10n.text(mode.label, language: language))
                        }
                    }
                    .disabled(confirmedMode == mode)
                }
            }
            .font(.caption2.weight(.semibold))
            .menuStyle(.borderlessButton)
            .menuIndicator(.visible)
            .menuOrder(.fixed)
            .fixedSize()
            .disabled(!isEnabled || state.isBusy)
            .help(L10n.text("Radio access preference", language: language))
            .accessibilityLabel(L10n.text("Radio access preference", language: language))
            .accessibilityValue(state.title(language: language))
        }
        .foregroundStyle(AppPalette.blue)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(AppPalette.blue.opacity(0.08), in: Capsule())
        .fixedSize()
    }
}
