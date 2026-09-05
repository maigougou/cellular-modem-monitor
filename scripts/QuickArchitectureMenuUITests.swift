import AppKit
import SwiftUI

@MainActor
private final class QuickMenuProbeState: ObservableObject {
    @Published var mode: NRArchitectureMode? = .automatic
    @Published var operation: NetworkControlOperation?
}

private struct QuickMenuProbeView: View {
    @ObservedObject var state: QuickMenuProbeState

    var body: some View {
        QuickArchitectureMenu(
            confirmedMode: state.mode,
            operation: state.operation,
            isEnabled: state.mode != nil,
            onSelect: { _ in }
        )
        .padding(12)
        .frame(width: 360, height: 100)
        .background(AppPalette.canvas)
        .environment(\.appLanguage, .english)
        .preferredColorScheme(.dark)
    }
}

/// Offline AppKit regression: mutate one mounted SwiftUI menu, without
/// recreating the host or contacting a modem, and inspect its native title.
@main
enum QuickArchitectureMenuUITests {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let state = QuickMenuProbeState()
        let host = NSHostingView(rootView: QuickMenuProbeView(state: state))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 100),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.title = "Offline quick-mode UI test"
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        let phases: [(NRArchitectureMode?, NetworkControlOperation?, String)] = [
            (.automatic, nil, "Auto SA/NSA"),
            (.automatic, .changingArchitecture(.saOnly), "SA only…"),
            (.saOnly, .changingArchitecture(.saOnly), "SA only…"),
            (.saOnly, nil, "SA only"),
            (.saOnly, .loading, "SA only"),
            (.saOnly, .changingArchitecture(.automatic), "Auto SA/NSA…"),
            (.saOnly, nil, "SA only"),
            (.saOnly, .changingArchitecture(.nsaOnly), "NSA only…"),
            (.nsaOnly, nil, "NSA only"),
            (.nsaOnly, .changingArchitecture(.lteOnly), "LTE only…"),
            (.lteOnly, nil, "LTE only"),
            (nil, .loading, "—")
        ]
        Task { @MainActor in
            for (mode, operation, expected) in phases {
                state.mode = mode
                state.operation = operation
                try? await Task.sleep(nanoseconds: 300_000_000)
                host.layoutSubtreeIfNeeded()
                let buttons = descendants(of: host).compactMap { $0 as? NSButton }
                guard let menu = buttons.first(where: { $0.title == expected }) else {
                    let titles = buttons.map { "\(type(of: $0)): \($0.title)" }
                    fputs("Missing native title \(expected); buttons: \(titles)\n", stderr)
                    exit(1)
                }
                precondition(menu.isEnabled == (mode != nil && operation == nil))
                print("Native menu title: \(menu.title); enabled: \(menu.isEnabled)")
            }
            print("Quick architecture menu UI transitions passed.")
            application.terminate(nil)
        }
        application.run()
    }

    @MainActor
    private static func descendants(of view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants(of: $0) }
    }
}
