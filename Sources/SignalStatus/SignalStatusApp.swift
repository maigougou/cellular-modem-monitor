import SwiftUI

@main
struct CellularModemMonitorApp: App {
    @StateObject private var model = StatusModel()
    @StateObject private var softwareUpdater = SoftwareUpdater()

    var body: some Scene {
        MenuBarExtra {
            StatusPanel()
                .environmentObject(model)
                .environmentObject(softwareUpdater)
                .environment(\.appLanguage, model.language)
                .environment(\.locale, model.language.locale)
        } label: {
            Image(nsImage: MenuBarImageRenderer.image(symbol: model.statusSymbol, text: model.menuBarText))
            .accessibilityLabel(
                "Cellular Modem Monitor, \(model.menuBarText.accessibilityValue), \(L10n.text(model.connectionState.label, language: model.language))"
            )
            .help("\(model.menuBarText.accessibilityValue) · \(L10n.text(model.connectionState.label, language: model.language))")
        }
        .menuBarExtraStyle(.window)
    }
}
