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

        let iconRect = NSRect(x: 58, y: 58, width: 908, height: 908)
        let iconPath = NSBezierPath(roundedRect: iconRect, xRadius: 218, yRadius: 218)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(calibratedRed: 0.02, green: 0.08, blue: 0.20, alpha: 0.34)
        shadow.shadowBlurRadius = 38
        shadow.shadowOffset = NSSize(width: 0, height: -18)
        NSGraphicsContext.current?.saveGraphicsState()
        shadow.set()
        NSGradient(colors: [
            NSColor(calibratedRed: 0.08, green: 0.34, blue: 0.88, alpha: 1),
            NSColor(calibratedRed: 0.03, green: 0.56, blue: 0.98, alpha: 1),
            NSColor(calibratedRed: 0.23, green: 0.76, blue: 1.00, alpha: 1)
        ])?.draw(in: iconPath, angle: 58)
        NSGraphicsContext.current?.restoreGraphicsState()

        // A single high-contrast radio mark survives Finder's 16 pt size and
        // mirrors the menu-bar/panel symbol without relying on tiny lettering.
        NSGraphicsContext.current?.saveGraphicsState()
        iconPath.addClip()
        let topHighlight = NSBezierPath(roundedRect: iconRect, xRadius: 218, yRadius: 218)
        NSGradient(colors: [
            NSColor.white.withAlphaComponent(0.20),
            NSColor.white.withAlphaComponent(0.00)
        ])?.draw(in: topHighlight, angle: -90)
        NSGraphicsContext.current?.restoreGraphicsState()

        NSColor.white.withAlphaComponent(0.17).setStroke()
        let rim = NSBezierPath(roundedRect: iconRect.insetBy(dx: 7, dy: 7), xRadius: 211, yRadius: 211)
        rim.lineWidth = 14
        rim.stroke()

        let radioCenter = NSPoint(x: 512, y: 526)
        drawRadioArc(center: radioCenter, radius: 258, side: .left, alpha: 0.72)
        drawRadioArc(center: radioCenter, radius: 258, side: .right, alpha: 0.72)
        drawRadioArc(center: radioCenter, radius: 158, side: .left, alpha: 0.96)
        drawRadioArc(center: radioCenter, radius: 158, side: .right, alpha: 0.96)

        NSColor.white.setStroke()
        let mast = NSBezierPath()
        mast.lineWidth = 54
        mast.lineCapStyle = .round
        mast.move(to: NSPoint(x: 512, y: 238))
        mast.line(to: NSPoint(x: 512, y: 461))
        mast.stroke()

        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: 451, y: 465, width: 122, height: 122)).fill()

        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "IconGenerator", code: 3)
        }
        try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
        try makeICNS(from: bitmap).write(to: URL(fileURLWithPath: CommandLine.arguments[2]), options: .atomic)
    }

    private enum RadioSide {
        case left
        case right
    }

    private static func drawRadioArc(
        center: NSPoint,
        radius: CGFloat,
        side: RadioSide,
        alpha: CGFloat
    ) {
        let path = NSBezierPath()
        path.lineWidth = 54
        path.lineCapStyle = .round
        switch side {
        case .left:
            path.appendArc(
                withCenter: center,
                radius: radius,
                startAngle: 132,
                endAngle: 228
            )
        case .right:
            path.appendArc(
                withCenter: center,
                radius: radius,
                startAngle: -48,
                endAngle: 48
            )
        }
        NSColor.white.withAlphaComponent(alpha).setStroke()
        path.stroke()
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
