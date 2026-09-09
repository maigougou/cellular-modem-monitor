import AppKit
import Foundation
import Vision

/// Pixel-level regression check of production SwiftUI screenshots, not a mock layout.
/// Run with CA screenshots produced by ReadmeScreenshotGenerator --alignment-stress.
@main
enum VerifyCarrierAlignment {
    static func main() throws {
        guard CommandLine.arguments.count > 1 else {
            print("usage: VerifyCarrierAlignment CA_SCREENSHOT.png ...")
            exit(64)
        }
        for path in CommandLine.arguments.dropFirst() {
            let url = URL(fileURLWithPath: path)
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.recognitionLanguages = path.contains("-zh-") ? ["zh-Hans", "en-US"] : ["en-US"]
            try VNImageRequestHandler(url: url).perform([request])
            let candidates = (request.results ?? []).compactMap { $0.topCandidates(1).first }
            guard let image = NSBitmapImageRep(data: try Data(contentsOf: url)) else { fail("Missing image") }
            let ulLabels = ["UL Enabled", "UL Disabled", "UL Unknown", "上行启用", "上行禁用", "上行未知"]
            let ul = try bounds(of: ulLabels, in: candidates)
            let metrics = try bounds(of: ["SINR", "SNR"], in: candidates)
            // Vision's substring boxes approximate character advances (several
            // pixels of noise). Locate the actual glyph ink inside each box.
            let xs = ul.map { inkLeft(in: $0, image: image) }
            if xs.isEmpty { print("Recognized text: \(candidates.map(\.string))") }
            guard xs.count >= 3, let low = xs.min(), let high = xs.max(), high - low <= 3 else {
                fail("UL column is not aligned in \(url.lastPathComponent): \(xs)")
            }
            guard metrics.count == ul.count,
                  metrics.allSatisfy({ abs(inkLeft(in: $0, image: image) - low) <= 3 }) else {
                fail("UL does not align with SINR/SNR in \(url.lastPathComponent)")
            }
            guard candidates.contains(where: { $0.string.contains("68719476735") }) else {
                fail("Longest NR Cell ID is missing or clipped in \(url.lastPathComponent)")
            }
            print("\(url.lastPathComponent): \(xs.count) UL rows aligned with SINR/SNR; spread \(String(format: "%.2f", high - low)) px; full 11-digit Cell ID visible")
        }
    }

    private static func inkLeft(in box: CGRect, image: NSBitmapImageRep) -> Double {
        let width = image.pixelsWide, height = image.pixelsHigh
        let left = max(0, Int(box.minX * Double(width)) - 12)
        let right = min(width - 1, Int(ceil(box.maxX * Double(width))) + 12)
        let top = max(0, Int((1 - box.maxY) * Double(height)) - 3)
        let bottom = min(height - 1, Int(ceil((1 - box.minY) * Double(height))) + 3)
        var samples: [(x: Int, rgb: Int)] = []
        var histogram: [Int: Int] = [:]
        for y in top...bottom {
            for x in left...right {
                guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let rgb = Int((color.redComponent * 255).rounded()) << 16
                    | Int((color.greenComponent * 255).rounded()) << 8
                    | Int((color.blueComponent * 255).rounded())
                samples.append((x, rgb))
                histogram[rgb, default: 0] += 1
            }
        }
        guard let background = histogram.max(by: { $0.value < $1.value })?.key else { fail("No pixels") }
        let ink = samples.filter { sample in
            [0, 8, 16].map { shift in
                abs(((sample.rgb >> shift) & 255) - ((background >> shift) & 255))
            }.max()! > 25
        }
        guard let x = ink.map(\.x).min() else { fail("No text ink") }
        return Double(x)
    }

    private static func fail(_ message: String) -> Never {
        print(message)
        exit(1)
    }

    private static func bounds(of labels: [String], in candidates: [VNRecognizedText]) throws -> [CGRect] {
        var results: [CGRect] = []
        for candidate in candidates {
            for label in labels {
                if let range = candidate.string.range(of: label),
                   let box = try candidate.boundingBox(for: range) {
                    results.append(box.boundingBox)
                }
            }
        }
        return results
    }
}
