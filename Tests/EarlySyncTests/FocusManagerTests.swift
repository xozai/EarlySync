import XCTest
@testable import EarlySync

// MARK: - MockShortcutRunner

private final class MockShortcutRunner: ShortcutRunning {
    var runHandler: ((String) throws -> Void)?
    var listHandler: (() throws -> [String])?
    private(set) var runCalls: [String] = []
    private(set) var listCallCount = 0

    func run(_ shortcutName: String, timeout: TimeInterval) async throws {
        runCalls.append(shortcutName)
        try runHandler?(shortcutName)
    }

    func list(timeout: TimeInterval) async throws -> [String] {
        listCallCount += 1
        return try listHandler?() ?? []
    }
}

// MARK: - FocusManagerTests

final class FocusManagerTests: XCTestCase {

    func testEnableFocus_defaultProfile_runsFocusOnShortcut() async {
        let runner = MockShortcutRunner()
        let manager = FocusManager(runner: runner)

        await manager.enableFocus()

        XCTAssertEqual(runner.runCalls, ["EarlySync: Focus On"])
    }

    func testEnableFocus_namedProfile_runsPerProfileShortcut() async {
        let runner = MockShortcutRunner()
        let manager = FocusManager(runner: runner)

        await manager.enableFocus(profile: "Work")

        XCTAssertEqual(runner.runCalls, ["EarlySync: Work"])
    }

    func testDisableFocus_runsFocusOffShortcut() async {
        let runner = MockShortcutRunner()
        let manager = FocusManager(runner: runner)

        await manager.disableFocus()

        XCTAssertEqual(runner.runCalls, ["EarlySync: Focus Off"])
    }

    func testEnableFocus_shortcutFailure_doesNotThrow() async {
        let runner = MockShortcutRunner()
        runner.runHandler = { _ in throw FocusManagerError.shortcutFailed(1) }
        let manager = FocusManager(runner: runner)

        await manager.enableFocus() // must not throw/crash

        XCTAssertEqual(runner.runCalls, ["EarlySync: Focus On"])
    }

    func testEnableFocus_timeout_doesNotThrow() async {
        let runner = MockShortcutRunner()
        runner.runHandler = { _ in throw FocusManagerError.timedOut }
        let manager = FocusManager(runner: runner)

        await manager.enableFocus()
    }

    func testIsShortcutConfigured_present() async {
        let runner = MockShortcutRunner()
        runner.listHandler = { ["EarlySync: Focus On", "EarlySync: Focus Off", "Some Other Shortcut"] }
        let manager = FocusManager(runner: runner)

        let configured = await manager.isShortcutConfigured()

        XCTAssertTrue(configured)
        XCTAssertEqual(runner.listCallCount, 1)
    }

    func testIsShortcutConfigured_absent() async {
        let runner = MockShortcutRunner()
        runner.listHandler = { ["Some Other Shortcut"] }
        let manager = FocusManager(runner: runner)

        let configured = await manager.isShortcutConfigured()

        XCTAssertFalse(configured)
    }

    func testIsShortcutConfigured_listFails_returnsFalse() async {
        let runner = MockShortcutRunner()
        runner.listHandler = { throw FocusManagerError.timedOut }
        let manager = FocusManager(runner: runner)

        let configured = await manager.isShortcutConfigured()

        XCTAssertFalse(configured)
    }

    func testIsShortcutConfigured_customName() async {
        let runner = MockShortcutRunner()
        runner.listHandler = { ["EarlySync: DND"] }
        let manager = FocusManager(runner: runner)

        let configured = await manager.isShortcutConfigured("EarlySync: DND")

        XCTAssertTrue(configured)
    }
}
