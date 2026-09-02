import Foundation

#if canImport(Sparkle)
import Sparkle
#endif

/// Owns the updater for the whole application lifetime. Release builds import
/// Sparkle; dependency-free direct compiler checks use the inert fallback.
@MainActor
final class SoftwareUpdater: ObservableObject {
#if canImport(Sparkle)
    private let controller: SPUStandardUpdaterController

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
#else
    init() {}

    func checkForUpdates() {}
#endif

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
}
