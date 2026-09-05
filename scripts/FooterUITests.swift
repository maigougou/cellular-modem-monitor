import AppKit
import SwiftUI

private struct FooterPreview: View {
    let language: AppLanguage
    let dark: Bool
    let target = ModemRestartTarget(
        modemID: "offline", endpoint: ScopedEndpoint(baseURL: URL(string: "http://192.168.254.1")!),
        settingsGeneration: 0, displayName: "ZTE MC7530CA / G5 MAX"
    )

    var body: some View {
        column
        .padding(16)
        .background(AppPalette.canvas)
        .environment(\.appLanguage, language)
        .preferredColorScheme(dark ? .dark : .light)
    }

    private var column: some View {
        VStack(spacing: 16) {
            footer(pending: nil, enabled: true)
            footer(pending: target, enabled: true)
            footer(pending: nil, enabled: false)
        }
        .frame(width: 360)
    }

    private func footer(pending: ModemRestartTarget?, enabled: Bool) -> some View {
        PanelFooter(
            pendingRestart: .constant(pending), target: target,
            canRestart: enabled, isRestarting: false, notice: nil, error: nil,
            willConfirmRestart: {}, restart: { _ in fatalError("Preview must never restart") },
            dismissMessage: {}, action: { _ in }
        )
        .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Offline visual fixtures use the production footer, never real device I/O.
@main
enum FooterUITests {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 392, height: 460),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Offline footer layout — no device actions"
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        Task { @MainActor in
            for language in AppLanguage.allCases {
              for dark in [false, true] {
                let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
                window.appearance = appearance
                let host = NSHostingView(rootView: FooterPreview(language: language, dark: dark))
                host.appearance = appearance
                window.contentView = host
                window.makeKeyAndOrderFront(nil)
                try? await Task.sleep(nanoseconds: 300_000_000)
                host.layoutSubtreeIfNeeded()
                let height = host.fittingSize.height
                precondition(height < 460, "Narrow footer confirmation must fit")
                guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("No bitmap") }
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let theme = dark ? "dark" : "light"
                try! bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("footer-\(language.rawValue)-\(theme).png"))
                print("Footer layout rendered: \(language.rawValue), \(theme), 360 pt, height \(height)")
              }
            }
            app.terminate(nil)
        }
        app.run()
    }
}
