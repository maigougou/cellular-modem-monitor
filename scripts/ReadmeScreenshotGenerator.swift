import AppKit
import SwiftUI

@main
enum ReadmeScreenshotGenerator {
    @MainActor
    static func main() {
        let arguments = CommandLine.arguments
        guard arguments.count >= 2 else {
            fputs("usage: ReadmeScreenshotGenerator OUTPUT.png --scene NAME [--light|--dark] [--chinese] [--compact|--wide]\n", stderr)
            exit(64)
        }
        let sceneName = arguments.firstIndex(of: "--scene").flatMap { index in
            arguments.indices.contains(index + 1) ? arguments[index + 1] : nil
        } ?? "overview"
        guard let scene = ReadmeScene(rawValue: sceneName) else {
            fputs("Unknown scene: \(sceneName)\n", stderr)
            exit(64)
        }
        let outputURL = URL(fileURLWithPath: arguments[1])
        let dark = arguments.contains("--dark")
        let language: AppLanguage = arguments.contains("--chinese") ? .simplifiedChinese : .english
        let width: PanelWidth = arguments.contains("--compact") ? .compact : arguments.contains("--wide") ? .wide : .standard
        let initialSize = NSSize(width: width.points, height: scene == .overview ? 1_180 : 1_600)
        let fixture = ReadmeFixture(scene: scene)
        fixture.validate()

        let defaults = UserDefaults(suiteName: "CellularModemMonitorReadmeFixture")!
        defaults.removePersistentDomain(forName: "CellularModemMonitorReadmeFixture")
        defaults.set(language.rawValue, forKey: "appLanguage")
        defaults.set(width.rawValue, forKey: "panelWidth")
        setenv("SIGNAL_STATUS_DEMO", "1", 1)
        let model = StatusModel(
            defaults: defaults,
            credentialStore: ScreenshotCredentials(),
            speedTestRunner: ScreenshotSpeedTestRunner(),
            demoSnapshot: fixture.snapshot
        )
        model.configureReadmeModem(fixture.modem, controls: fixture.controls)
        model.language = language
        if scene == .overview || scene == .speedtest { model.speedTestModel.start() }

        var panel = StatusPanel(
            initiallyShowNetworkControls: scene == .controls,
            initiallyShowSettings: scene == .settings,
            initiallyShowCarrierAggregation: [.ca, .nrCA, .lteCA].contains(scene),
            initiallyShowSpeedTest: scene == .overview,
            panelHeightLimit: initialSize.height
        )
        panel.readmeScene = scene
        let content = panel
            .background(AppPalette.canvas.ignoresSafeArea())
            .environmentObject(model)
            .environmentObject(SoftwareUpdater())
            .environment(\.appLanguage, language)
            .environment(\.locale, language.locale)
            .preferredColorScheme(dark ? .dark : .light)
        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = NSRect(origin: .zero, size: initialSize)
        let window = ScreenshotWindow(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: .borderless, backing: .buffered, defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = hostingView
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        window.makeKeyAndOrderFront(nil)
        application.activate(ignoringOtherApps: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            // Fit the actual SwiftUI card rather than exporting a tall, empty canvas.
            hostingView.layoutSubtreeIfNeeded()
            let fittingHeight = ceil(hostingView.fittingSize.height)
            precondition(fittingHeight > 40 && fittingHeight < 2_400)
            let size = NSSize(width: width.points, height: fittingHeight)
            window.setContentSize(size)
            hostingView.frame = NSRect(origin: .zero, size: size)
            hostingView.layoutSubtreeIfNeeded()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                hostingView.layoutSubtreeIfNeeded()
                window.displayIfNeeded()
                do {
                    try render(hostingView, size: size, to: outputURL)
                    print("\(scene.rawValue) \(language.rawValue) \(dark ? "dark" : "light"): \(Int(size.width))×\(Int(size.height))")
                    application.terminate(nil)
                } catch {
                    fputs("screenshot failed: \(error.localizedDescription)\n", stderr)
                    exit(1)
                }
            }
        }
        application.run()
    }

    @MainActor
    private static func render(_ view: NSView, size: NSSize, to outputURL: URL) throws {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bitmapFormat: [], bytesPerRow: 0, bitsPerPixel: 0
        ) else { throw NSError(domain: "ReadmeScreenshotGenerator", code: 1) }
        bitmap.size = size
        view.cacheDisplay(in: view.bounds, to: bitmap)

        // SwiftUI's fitting bounds can include transparent shadow margins.
        // Export an opaque canvas so GitHub's theme never shows through them.
        guard let opaque = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: bitmap.pixelsWide, pixelsHigh: bitmap.pixelsHigh,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bitmapFormat: [], bytesPerRow: 0, bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: opaque), let captured = bitmap.cgImage
        else { throw NSError(domain: "ReadmeScreenshotGenerator", code: 3) }
        opaque.size = size
        let pixelBounds = CGRect(x: 0, y: 0, width: opaque.pixelsWide, height: opaque.pixelsHigh)
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            context.cgContext.setFillColor(NSColor(AppPalette.canvas).cgColor)
        }
        context.cgContext.fill(pixelBounds)
        context.cgContext.draw(captured, in: pixelBounds)
        guard let png = opaque.representation(using: .png, properties: [:])
        else { throw NSError(domain: "ReadmeScreenshotGenerator", code: 2) }
        try png.write(to: outputURL, options: .atomic)
    }
}

/// One coherent, synthetic modem supplies every field shown in a scene.
/// SA has no LTE anchor; NSA has one. CA adds distinct component carriers.
private struct ReadmeFixture {
    let snapshot: DeviceSnapshot
    let modem: ActiveModem
    let controls: ModemControlState

    init(scene: ReadmeScene) {
        let isSA = scene == .sa
        let hasCA = ![ReadmeScene.sa, .nsa, .connection, .radio].contains(scene)
        var value = DeviceSnapshot.empty
        value.host = "192.168.254.1"
        value.interfaceName = "en12"
        value.operatorName = "TELUS"
        value.mcc = "302"
        value.mnc = "220"
        value.nrSystemMode = isSA ? .sa : .nsa
        value.nrBand = "n77"
        value.nrChannel = "640608"
        value.nrBandwidthMHz = 50
        value.nrGlobalCellID = 0x1234_56780
        value.nrPhysicalCellID = 821
        value.nrSignal = RadioSignal(rsrpDBm: -88, rsrqDB: -11, rssiDBm: -65, snrDB: 22)
        value.nrPrimaryCell = NRCarrier(
            role: .primary, band: "n77", nrarfcn: 640608, bandwidthMHz: 50,
            physicalCellID: 821, state: .active, globalCellID: value.nrGlobalCellID, signal: value.nrSignal
        )
        if hasCA {
            value.nrSecondaryCells = [
                NRCarrier(
                    role: .secondary(index: 1), band: "n77", nrarfcn: 634000, bandwidthMHz: 30,
                    physicalCellID: 822, state: .active,
                    signal: RadioSignal(rsrpDBm: -91, rsrqDB: -12, rssiDBm: -68, snrDB: 19)
                ),
                NRCarrier(
                    role: .secondary(index: 2), band: "n71", nrarfcn: 126500, bandwidthMHz: 10,
                    physicalCellID: 203, state: .configured, signal: .empty
                )
            ]
        }
        if !isSA {
            value.lteBand = "B2"
            value.lteChannel = "900"
            value.lteBandwidthMHz = 20
            value.lteGlobalCellID = 0x0123_4567
            value.ltePhysicalCellID = 203
            value.lteSignal = RadioSignal(rsrpDBm: -91, rsrqDB: -10, rssiDBm: -64, snrDB: 16)
            value.ltePrimaryCell = LTECarrier(
                role: .primary, band: "B2", earfcn: 900, bandwidthMHz: 20, physicalCellID: 203,
                state: .active, globalCellID: value.lteGlobalCellID, signal: value.lteSignal
            )
            if hasCA {
                value.lteSecondaryCells = [
                    LTECarrier(
                        role: .secondary(index: 1), band: "B66", earfcn: 66786, bandwidthMHz: 20,
                        physicalCellID: 203, state: .active,
                        signal: RadioSignal(rsrpDBm: -94, rsrqDB: -12, rssiDBm: -67, snrDB: 14)
                    ),
                    LTECarrier(
                        role: .secondary(index: 2), band: "B7", earfcn: 2850, bandwidthMHz: 20,
                        physicalCellID: 203, state: .configured, signal: .empty
                    )
                ]
            }
        }
        value.updatedAt = Date()
        snapshot = value
        modem = ActiveModem(
            identity: ModemIdentity(
                kind: .zteMC7530CA, manufacturer: "ZTE", model: "MC7530CA",
                displayName: "ZTE MC7530CA / G5 MAX", stableIdentifier: "readme-fixture-zte"
            ),
            endpoint: ScopedEndpoint(
                baseURL: URL(string: "http://192.168.254.1")!, interfaceName: "en12", interfaceIndex: 12,
                sourceAddress: "192.168.254.20", connectionPath: .directUSB
            ),
            capabilities: [.statusRead, .identityRead, .webUI, .operatorSelection, .networkScan, .radioAccessPreference, .nrBandLock, .lteBandLock]
        )
        controls = ModemControlState(
            operatorSelection: OperatorSelection(
                mode: .automatic, operatorName: "TELUS", plmn: "302220",
                accessTechnology: isSA ? .nr5GC : .lteNRDualConnectivity
            ),
            architecture: isSA ? .saOnly : .automatic,
            saBands: [71, 77, 78], nsaBands: [71, 77, 78], lteBands: [2, 4, 7, 12, 66],
            availableNRBands: [2, 5, 7, 12, 25, 38, 41, 66, 71, 77, 78],
            availableLTEBands: [2, 4, 5, 7, 12, 13, 17, 25, 26, 29, 30, 38, 41, 48, 66, 71],
            canRestoreDefaults: true, preferenceLifetime: .persistent
        )
    }

    func validate() {
        precondition(snapshot.host == modem.endpoint.baseURL.host)
        precondition(snapshot.interfaceName == modem.endpoint.interfaceName)
        guard let nr = snapshot.nrPrimaryCell else { preconditionFailure("Missing NR PCell") }
        precondition(nr.state == .active && nr.band == snapshot.nrBand)
        precondition(String(nr.nrarfcn) == snapshot.nrChannel && nr.bandwidthMHz == snapshot.nrBandwidthMHz)
        precondition(nr.signal == snapshot.nrSignal && nr.globalCellID == snapshot.nrGlobalCellID)
        if snapshot.nrSystemMode == .sa {
            precondition(snapshot.lteBand == nil && snapshot.ltePrimaryCell == nil && snapshot.lteSecondaryCells.isEmpty)
        } else {
            guard let lte = snapshot.ltePrimaryCell else { preconditionFailure("NSA requires an LTE anchor") }
            precondition(lte.state == .active && lte.band == snapshot.lteBand)
            precondition(String(lte.earfcn) == snapshot.lteChannel && lte.bandwidthMHz == snapshot.lteBandwidthMHz)
            precondition(lte.signal == snapshot.lteSignal && lte.globalCellID == snapshot.lteGlobalCellID)
        }
        let lteCarriers = [snapshot.ltePrimaryCell].compactMap { $0 } + snapshot.lteSecondaryCells
        precondition(lteCarriers.allSatisfy { [1.4, 3, 5, 10, 15, 20].contains($0.bandwidthMHz ?? -1) })
        if !snapshot.lteSecondaryCells.isEmpty {
            let active = lteCarriers.filter { $0.state == .active }
            precondition(active.compactMap(\.band) == ["B2", "B66"])
            precondition(active.compactMap(\.bandwidthMHz).reduce(0, +) == 40)
            let activeNR = ([nr] + snapshot.nrSecondaryCells).filter { $0.state == .active }
            precondition(activeNR.compactMap(\.bandwidthMHz).reduce(0, +) == 80)
        }
    }
}

private final class ScreenshotWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

// Offline fixtures never open a socket, run Ookla, or read the user's credentials.
private struct ScreenshotCredentials: CredentialStoring {
    func password(for account: String) throws -> String? { nil }
    func setPassword(_ password: String, for account: String) throws {}
    func removePassword(for account: String) throws {}
}

private struct ScreenshotSpeedTestRunner: SpeedTestRunning {
    func run(
        binding: SpeedTestBinding,
        progress: @escaping @Sendable (SpeedTestProgress) async -> Void
    ) async throws -> SpeedTestResult {
        SpeedTestResult(
            binding: binding, downloadBitsPerSecond: 486_200_000, uploadBitsPerSecond: 42_800_000,
            idleLatencyMilliseconds: 28, jitterMilliseconds: 3.6, packetLossPercent: 0,
            serverName: "Example server · Toronto, ON", resultURL: URL(string: "https://www.speedtest.net/"),
            completedAt: Date()
        )
    }
}
