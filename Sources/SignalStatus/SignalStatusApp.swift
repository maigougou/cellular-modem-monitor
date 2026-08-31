import SwiftUI

@main
struct CellularModemMonitorApp: App {
    @StateObject private var model = StatusModel()

    var body: some Scene {
        MenuBarExtra {
            StatusPanel()
                .environmentObject(model)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: model.statusSymbol)
                if !model.menuBarTitle.isEmpty {
                    Text(model.menuBarTitle)
                }
            }
            .accessibilityLabel("Cellular Modem Monitor, \(model.menuBarTitle), \(model.connectionState.label)")
        }
        .menuBarExtraStyle(.window)
    }
}
