import AppKit

/// Offline visual QA of the production image inside a real NSStatusBarButton.
/// Does not construct StatusModel, read saved credentials, or contact a modem.
@main
@MainActor
enum MenuBarScreenshotGenerator {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            print("usage: MenuBarScreenshotGenerator OUTPUT_DIRECTORY")
            exit(64)
        }
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        let samples: [(String, MenuBarText)] = [
            ("NSA · NR + LTE", MenuBarText(primary: "NSA n77 · 3CC", secondary: "LTE B7 · 2CC")),
            ("SA · NR only", MenuBarText(primary: "SA n77 · 3CC")),
            ("LTE only", MenuBarText(primary: "LTE B7 · 2CC")),
            ("Compact", MenuBarText(primary: "n77 · 3CC", secondary: "B7 · 2CC")),
            ("No CA", MenuBarText(primary: "NSA n77 · 1CC", secondary: "LTE B7 · 1CC")),
            ("Stale / unknown", MenuBarText(primary: "NSA n77 · —", secondary: "LTE B7 · —")),
            ("Unequal band / CC widths", MenuBarText(primary: "NSA n261 · 16CC", secondary: "LTE B7 · 2CC")),
            ("Icon only", MenuBarText(primary: ""))
        ]
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { NSStatusBar.system.removeStatusItem(item) }
        guard let button = item.button else { fatalError("Missing native status button") }
        let canvasSize = NSSize(width: 670, height: 80 + samples.count * 52)
        let sheet = NSImage(size: canvasSize)
        sheet.lockFocus()
        NSColor(calibratedWhite: 0.94, alpha: 1).setFill()
        NSRect(origin: .zero, size: canvasSize).fill()
        draw("Native macOS menu bar · actual button captures", x: 20, y: canvasSize.height - 32,
             size: 16, color: .black)
        draw("Light", x: 250, y: canvasSize.height - 59, size: 12, color: .darkGray)
        draw("Dark", x: 455, y: canvasSize.height - 59, size: 12, color: .darkGray)
        sheet.unlockFocus()
        for (index, sample) in samples.enumerated() {
            let y = canvasSize.height - 96 - CGFloat(index) * 52
            sheet.lockFocus()
            draw(sample.0, x: 20, y: y + 5, size: 12, color: .black)
            sheet.unlockFocus()
            for (appearanceIndex, appearanceName) in [NSAppearance.Name.aqua, .darkAqua].enumerated() {
                button.appearance = NSAppearance(named: appearanceName)
                button.image = MenuBarImageRenderer.image(symbol: "antenna.radiowaves.left.and.right", text: sample.1)
                button.imagePosition = .imageOnly
                button.toolTip = sample.1.accessibilityValue
                button.sizeToFit()
                button.window?.layoutIfNeeded()
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.08))
                guard button.bounds.height >= 22,
                      button.bounds.width >= button.image!.size.width,
                      let pixels = button.bitmapImageRepForCachingDisplay(in: button.bounds) else {
                    fatalError("Native menu bar clips image for \(sample.0): \(button.bounds)")
                }
                button.cacheDisplay(in: button.bounds, to: pixels)
                if !sample.1.secondary.isEmpty {
                    let upper = rightmostInk(in: pixels, rows: 0..<(pixels.pixelsHigh / 2))
                    let lower = rightmostInk(in: pixels, rows: (pixels.pixelsHigh / 2)..<pixels.pixelsHigh)
                    guard upper >= 0, upper == lower else {
                        fatalError("CA columns not pixel-aligned for \(sample.0): \(upper), \(lower)")
                    }
                    print("\(sample.0): upper/lower count right edge aligned at pixel \(upper)")
                }
                guard let png = pixels.representation(using: .png, properties: [:]) else { fatalError("No PNG") }
                let name = "menu-bar-\(index)-\(appearanceIndex == 0 ? "light" : "dark").png"
                try png.write(to: directory.appendingPathComponent(name))
                let captured = NSImage(size: button.bounds.size)
                captured.addRepresentation(pixels)
                sheet.lockFocus()
                let x = CGFloat(240 + appearanceIndex * 205)
                (appearanceIndex == 0 ? NSColor.white : NSColor(calibratedWhite: 0.13, alpha: 1)).setFill()
                NSRect(x: x, y: y - 4, width: 195, height: 34).fill()
                captured.draw(in: NSRect(origin: NSPoint(x: x + 8, y: y), size: button.bounds.size))
                sheet.unlockFocus()
                print("\(name): button \(button.bounds.size), image \(button.image!.size), \(pixels.pixelsWide)×\(pixels.pixelsHigh) pixels")
            }
        }
        guard let tiff = sheet.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("No sheet PNG") }
        try png.write(to: directory.appendingPathComponent("menu-bar-ca-preview.png"))
    }

    static func draw(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat, color: NSColor) {
        (text as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [
            .font: NSFont.systemFont(ofSize: size, weight: .medium), .foregroundColor: color
        ])
    }

    static func rightmostInk(in pixels: NSBitmapImageRep, rows: Range<Int>) -> Int {
        guard let background = pixels.colorAt(x: pixels.pixelsWide - 1, y: 0)?.usingColorSpace(.deviceRGB)
        else { return -1 }
        for x in stride(from: pixels.pixelsWide - 1, through: pixels.pixelsWide / 2, by: -1) {
            for y in rows {
                guard let color = pixels.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let contrast = background.alphaComponent < 0.1 ? color.alphaComponent : max(
                    abs(color.redComponent - background.redComponent),
                    abs(color.greenComponent - background.greenComponent),
                    abs(color.blueComponent - background.blueComponent)
                )
                if contrast > 0.25 { return x }
            }
        }
        return -1
    }
}
