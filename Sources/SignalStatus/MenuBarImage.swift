import AppKit

/// A template image preserves both rows in the native menu bar. MenuBarExtra
/// does not reliably preserve arbitrary multi-line SwiftUI label hierarchies.
@MainActor
enum MenuBarImageRenderer {
    private static let images: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 32
        return cache
    }()

    static func image(symbol: String, text: MenuBarText) -> NSImage {
        let key = "\(symbol)|\(text.primary)|\(text.secondary)" as NSString
        if let cached = images.object(forKey: key) { return cached }
        let hasSecondLine = !text.secondary.isEmpty
        let font = NSFont.monospacedDigitSystemFont(ofSize: hasSecondLine ? 9 : 12, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let first = NSAttributedString(string: text.primary, attributes: attributes)
        let second = NSAttributedString(string: text.secondary, attributes: attributes)
        let hasText = !text.primary.isEmpty || hasSecondLine
        let textX: CGFloat = hasText ? 20 : 16
        // Lay out both RATs in shared columns. Right-align the count column so
        // the CC suffix stays aligned even for different band/digit lengths.
        let rows = hasSecondLine ? [text.primary, text.secondary].compactMap { line
            -> (identity: NSAttributedString, count: NSAttributedString)? in
            guard let divider = line.range(of: " · ", options: .backwards) else { return nil }
            return (
                NSAttributedString(string: String(line[..<divider.lowerBound]), attributes: attributes),
                NSAttributedString(string: String(line[divider.upperBound...]), attributes: attributes)
            )
        } : []
        let separator = NSAttributedString(string: " · ", attributes: attributes)
        let identityWidth = ceil(rows.map { $0.identity.size().width }.max() ?? 0)
        let countWidth = ceil(rows.map { $0.count.size().width }.max() ?? 0)
        let countRight = textX + identityWidth + ceil(separator.size().width) + countWidth
        let width = rows.count == 2 ? countRight + 1
            : hasText ? textX + ceil(max(first.size().width, second.size().width)) + 1 : 16
        let size = NSSize(width: width, height: 22)
        let icon = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .regular))
        let image = NSImage(size: size, flipped: false) { _ in
            icon?.draw(in: NSRect(x: 0, y: 4, width: 16, height: 14),
                       from: .zero, operation: .sourceOver, fraction: 1)
            if rows.count == 2 {
                for (index, row) in rows.enumerated() {
                    let y: CGFloat = index == 0 ? 11 : 0
                    row.identity.draw(at: NSPoint(x: textX, y: y))
                    separator.draw(at: NSPoint(x: textX + identityWidth, y: y))
                    row.count.draw(at: NSPoint(x: countRight - row.count.size().width, y: y))
                }
            } else if hasSecondLine {
                first.draw(at: NSPoint(x: textX, y: 11))
                second.draw(at: NSPoint(x: textX, y: 0))
            } else if hasText {
                first.draw(at: NSPoint(x: textX, y: (size.height - first.size().height) / 2))
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = text.accessibilityValue
        images.setObject(image, forKey: key)
        return image
    }
}
