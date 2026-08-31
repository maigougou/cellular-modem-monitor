import SwiftUI

@main
struct CellularModemMonitorApp: App {
    @StateObject private var model = StatusModel()

    var body: some Scene {
        MenuBarExtra {
            StatusPanel()
                .environmentObject(model)
                .environment(\.appLanguage, model.language)
                .environment(\.locale, model.language.locale)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: model.statusSymbol)
                if !model.menuBarTitle.isEmpty {
                    Text(model.menuBarTitle)
                }
            }
            .accessibilityLabel(
                "Cellular Modem Monitor, \(model.menuBarTitle), \(L10n.text(model.connectionState.label, language: model.language))"
            )
        }
        .menuBarExtraStyle(.window)
    }
}
