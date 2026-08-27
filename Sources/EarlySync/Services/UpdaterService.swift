import Foundation
import Sparkle

// MARK: - UpdaterService

/// Thin wrapper around Sparkle's `SPUStandardUpdaterController` so the rest
/// of the app depends on this instead of Sparkle types directly.
///
/// Sparkle 2 requires a valid `SUPublicEDKey` in Info.plist to safely check
/// for updates — without one, the app has no real update infrastructure yet
/// (see issue #8: needs a real EdDSA keypair generated via Sparkle's
/// `generate_keys` tool, which hasn't happened). Rather than let Sparkle
/// assert/crash on a missing key, this skips initializing the updater
/// entirely and disables the "Check for Updates" menu item — the same
/// graceful-degradation pattern used elsewhere in the app (e.g.
/// `LuxaforWebhookClient` with no userId configured).
@MainActor
public final class UpdaterService: NSObject {

    private var controller: SPUStandardUpdaterController?

    public override init() {
        super.init()
        guard
            let key = Bundle.main.infoDictionary?["SUPublicEDKey"] as? String,
            !key.isEmpty
        else {
            log("SUPublicEDKey not configured — auto-update disabled until a real Sparkle keypair is set up")
            return
        }
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    /// Whether a real updater is configured and able to check right now.
    public var canCheckForUpdates: Bool {
        controller?.updater.canCheckForUpdates ?? false
    }

    public func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    private func log(_ message: String) {
        FileHandle.standardError.write(Data("[UpdaterService] \(message)\n".utf8))
    }
}
