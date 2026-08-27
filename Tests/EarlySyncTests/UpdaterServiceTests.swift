import XCTest
@testable import EarlySync

// MARK: - UpdaterServiceTests

/// The test bundle's Info.plist has no SUPublicEDKey (it isn't the app's
/// bundle), so this exercises exactly the "not configured yet" path that
/// matters until a real Sparkle keypair exists — the one thing worth
/// guaranteeing here is that missing/invalid config degrades safely instead
/// of crashing.
@MainActor
final class UpdaterServiceTests: XCTestCase {

    func testCanCheckForUpdates_falseWithoutConfiguredKey() {
        let service = UpdaterService()
        XCTAssertFalse(service.canCheckForUpdates)
    }

    func testCheckForUpdates_withoutConfiguredKey_doesNotCrash() {
        let service = UpdaterService()
        service.checkForUpdates() // must be a safe no-op, not a crash
    }
}
