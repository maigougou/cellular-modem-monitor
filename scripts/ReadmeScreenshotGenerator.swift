import AppKit
import SwiftUI

@main
enum ReadmeScreenshotGenerator {
    @MainActor
    static func main() {
        guard CommandLine.arguments.count >= 2 else {
            fputs("usage: ReadmeScreenshotGenerator OUTPUT.png [--demo-sa|--demo-controls] [--ca] [--overview] [--settings] [--compact|--wide] [--chinese] [--light]\n", stderr)
            exit(64)
        }

        let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let arguments = CommandLine.arguments
        let showsControls = arguments.contains("--demo-controls")
        let showsCA = arguments.contains("--ca")
        let showsSettings = arguments.contains("--settings")
        let width = arguments.contains("--compact") ? PanelWidth.compact
            : arguments.contains("--wide") ? .wide : .standard
        let language: AppLanguage = arguments.contains("--chinese") ? .simplifiedChinese : .english
        let height: CGFloat = arguments.contains("--overview") ? 875
            : showsCA || showsSettings ? 1_900
            : showsControls ? 1_250 : 720
        let pointSize = NSSize(width: width.points, height: height)
        let defaults = UserDefaults(suiteName: "CellularModemMonitorReadmeFixture")!
        defaults.removePersistentDomain(forName: "CellularModemMonitorReadmeFixture")
        defaults.set(language.rawValue, forKey: "appLanguage")
        defaults.set(width.rawValue, forKey: "panelWidth")

        setenv("SIGNAL_STATUS_DEMO", "1", 1)
        let model = StatusModel(defaults: defaults, demoSnapshot: showsCA ? caFixture() : nil)
        model.language = language
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
            initiallyShowSettings: showsSettings,
            initiallyShowCarrierAggregation: showsCA,
            panelHeightLimit: pointSize.height
        )
        .environmentObject(model)
        .environmentObject(updater)
        .environment(\.appLanguage, language)
        .environment(\.locale, language.locale)
        .preferredColorScheme(arguments.contains("--light") || !showsControls ? .light : .dark)

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

    private static func caFixture() -> DeviceSnapshot {
        // Synthetic component carriers cover active/inactive rows, PCI
        // fallback, missing signals and a two-card NSA layout.
        var fixture = DeviceSnapshot.empty
        fixture.host = "192.168.254.1"
        fixture.operatorName = "TELUS"
        fixture.mcc = "302"
        fixture.mnc = "220"
        fixture.nrSystemMode = .nsa
        fixture.nrBand = "n77"
        fixture.nrChannel = "640608"
        fixture.nrBandwidthMHz = 50
        fixture.nrSignal = RadioSignal(rsrpDBm: -63, rsrqDB: -11, rssiDBm: -55, snrDB: 31)
        fixture.nrPrimaryCell = NRCarrier(role: .primary, band: "n77", nrarfcn: 640608, bandwidthMHz: 50, physicalCellID: 821, state: .active, signal: fixture.nrSignal)
        fixture.nrSecondaryCells = [
            NRCarrier(role: .secondary(index: 1), band: "n77", nrarfcn: 634000, bandwidthMHz: 30, physicalCellID: 822, state: .active, signal: RadioSignal(rsrpDBm: -74, rsrqDB: -12, rssiDBm: -60, snrDB: 24)),
            NRCarrier(role: .secondary(index: 2), band: "n71", nrarfcn: 126500, bandwidthMHz: 10, physicalCellID: 203, state: .configured)
        ]
        fixture.lteBand = "B7"
        fixture.lteChannel = "2850"
        fixture.lteBandwidthMHz = 20
        fixture.lteGlobalCellID = 12345678
        fixture.lteSignal = RadioSignal(rsrpDBm: -72, rsrqDB: -17, rssiDBm: -35, snrDB: 12)
        fixture.ltePrimaryCell = LTECarrier(role: .primary, band: "B7", earfcn: 2850, bandwidthMHz: 20, physicalCellID: 203, state: .active, globalCellID: fixture.lteGlobalCellID, signal: fixture.lteSignal)
        fixture.lteSecondaryCells = [LTECarrier(role: .secondary(index: 1), band: "B2", earfcn: 900, bandwidthMHz: 20, physicalCellID: 203, state: .configured, signal: RadioSignal(rsrpDBm: -76, rsrqDB: -17, rssiDBm: -52, snrDB: 15.6))]
        fixture.updatedAt = Date()
        return fixture
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
