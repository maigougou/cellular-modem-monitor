import AppKit
import Foundation

@main
enum IconGenerator {
    static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            throw NSError(domain: "IconGenerator", code: 1, userInfo: [NSLocalizedDescriptionKey: "Output PNG and ICNS paths are required"])
        }

        let size = NSSize(width: 1024, height: 1024)
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 1024,
            pixelsHigh: 1024,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw NSError(domain: "IconGenerator", code: 2)
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()

        let iconRect = NSRect(x: 48, y: 48, width: 928, height: 928)
        let iconPath = NSBezierPath(roundedRect: iconRect, xRadius: 214, yRadius: 214)
        let appBlue = NSColor(calibratedRed: 10 / 255, green: 132 / 255, blue: 1, alpha: 1)
        let appCyan = NSColor(calibratedRed: 100 / 255, green: 210 / 255, blue: 1, alpha: 1)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(calibratedRed: 0.02, green: 0.07, blue: 0.16, alpha: 0.42)
        shadow.shadowBlurRadius = 42
        shadow.shadowOffset = NSSize(width: 0, height: -20)
        shadow.set()
        NSGradient(colors: [
            NSColor(calibratedRed: 0.03, green: 0.12, blue: 0.25, alpha: 1),
            appBlue,
            NSColor(calibratedRed: 0.20, green: 0.58, blue: 0.96, alpha: 1)
        ])?.draw(in: iconPath, angle: -48)

        let label = NSMutableAttributedString(
            string: "5G",
            attributes: [
                .font: NSFont.systemFont(ofSize: 330, weight: .heavy),
                .foregroundColor: NSColor.white.withAlphaComponent(0.97),
                .kern: -20
            ]
        )
        label.append(NSAttributedString(
            string: "+",
            attributes: [
                .font: NSFont.systemFont(ofSize: 250, weight: .bold),
                .foregroundColor: appCyan,
                .kern: -10
            ]
        ))
        let labelSize = label.size()
        label.draw(at: NSPoint(
            x: (size.width - labelSize.width) / 2,
            y: 395
        ))

        let barWidths: [CGFloat] = [120, 120, 120, 120]
        let barHeights: [CGFloat] = [64, 104, 144, 184]
        let barGap: CGFloat = 26
        let totalBarWidth = barWidths.reduce(0, +) + barGap * CGFloat(barWidths.count - 1)
        var barX = (size.width - totalBarWidth) / 2
        NSColor.white.withAlphaComponent(0.92).setFill()
        for index in barWidths.indices {
            let rect = NSRect(x: barX, y: 190, width: barWidths[index], height: barHeights[index])
            NSBezierPath(roundedRect: rect, xRadius: 24, yRadius: 24).fill()
            barX += barWidths[index] + barGap
        }

        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "IconGenerator", code: 3)
        }
        try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
        try makeICNS(from: bitmap).write(to: URL(fileURLWithPath: CommandLine.arguments[2]), options: .atomic)
    }

    private static func makeICNS(from source: NSBitmapImageRep) throws -> Data {
        let sourceImage = NSImage(size: NSSize(width: 1024, height: 1024))
        sourceImage.addRepresentation(source)
        let entries: [(String, Int)] = [
            ("icp4", 16),
            ("icp5", 32),
            ("icp6", 64),
            ("ic07", 128),
            ("ic08", 256),
            ("ic09", 512),
            ("ic10", 1024)
        ]

        var body = Data()
        for (type, pixels) in entries {
            guard let png = resizedPNG(sourceImage, pixels: pixels) else {
                throw NSError(domain: "IconGenerator", code: 4)
            }
            body.append(Data(type.utf8))
            body.append(bigEndianUInt32(UInt32(8 + png.count)))
            body.append(png)
        }

        var result = Data("icns".utf8)
        result.append(bigEndianUInt32(UInt32(8 + body.count)))
        result.append(body)
        return result
    }

    private static func resizedPNG(_ source: NSImage, pixels: Int) -> Data? {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixels,
            pixelsHigh: pixels,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        source.draw(
            in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
            from: NSRect(x: 0, y: 0, width: 1024, height: 1024),
            operation: .copy,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])
    }

    private static func bigEndianUInt32(_ value: UInt32) -> Data {
        var bigEndian = value.bigEndian
        return Data(bytes: &bigEndian, count: MemoryLayout<UInt32>.size)
    }
}
