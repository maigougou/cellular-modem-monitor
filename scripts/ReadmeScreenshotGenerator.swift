import AppKit
import SwiftUI

@main
enum ReadmeScreenshotGenerator {
    @MainActor
    static func main() {
        guard CommandLine.arguments.count >= 2 else {
            fputs("usage: ReadmeScreenshotGenerator OUTPUT.png [--demo-sa|--demo-controls]\n", stderr)
            exit(64)
        }

        let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let showsControls = CommandLine.arguments.contains("--demo-controls")
        let pointSize = NSSize(width: 360, height: showsControls ? 1_300 : 620)
        let defaults = UserDefaults(suiteName: "CellularModemMonitorReadmeFixture")!
        defaults.removePersistentDomain(forName: "CellularModemMonitorReadmeFixture")
        defaults.set(AppLanguage.english.rawValue, forKey: "appLanguage")

        let model = StatusModel(defaults: defaults)
        model.language = .english
        if showsControls, let controlState = model.controlState {
            // Keep the long-form screenshot focused on the controls themselves.
            // Network scan results have their own dynamic height and made the
            // README preview needlessly tall without demonstrating another
            // control capability.
            model.applyControlResult(
                ModemControlResult(state: controlState, scannedNetworks: [])
            )
        }
        let updater = SoftwareUpdater()
        let content = StatusPanel(
            initiallyShowNetworkControls: showsControls,
            panelHeightLimit: pointSize.height
        )
        .environmentObject(model)
        .environmentObject(updater)
        .environment(\.appLanguage, AppLanguage.english)
        .environment(\.locale, AppLanguage.english.locale)
        .preferredColorScheme(showsControls ? .dark : .light)

        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = NSRect(origin: .zero, size: pointSize)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: pointSize),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = hostingView
        window.orderFrontRegardless()

        let application = NSApplication.shared
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            hostingView.layoutSubtreeIfNeeded()
            do {
                try render(hostingView, pointSize: pointSize, to: outputURL)
                application.terminate(nil)
            } catch {
                fputs("screenshot failed: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
        }
        application.run()
    }

    @MainActor
    private static func render(
        _ view: NSView,
        pointSize: NSSize,
        to outputURL: URL
    ) throws {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(pointSize.width * 2),
            pixelsHigh: Int(pointSize.height * 2),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw NSError(domain: "ReadmeScreenshotGenerator", code: 1)
        }
        bitmap.size = pointSize
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "ReadmeScreenshotGenerator", code: 2)
        }
        try png.write(to: outputURL, options: .atomic)
    }
}
