import XCTest
@testable import EarlySync

// MARK: - MockShortcutRunner

private final class MockShortcutRunner: ShortcutRunning {
    var runHandler: ((String) throws -> Void)?
    /// Per-shortcut-name artificial delay, to simulate one call resolving slower than another.
    var delays: [String: TimeInterval] = [:]
    private(set) var runCalls: [String] = []

    func run(_ shortcutName: String, timeout: TimeInterval) async throws {
        runCalls.append(shortcutName)
        if let delay = delays[shortcutName] {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        try runHandler?(shortcutName)
    }

    func list(timeout: TimeInterval) async throws -> [String] { [] }
}

// MARK: - StatusEngineTests

@MainActor
final class StatusEngineTests: XCTestCase {

    private var luxaforSession: URLSession!
    private var luxaforClient: LuxaforWebhookClient!
    private var shortcutRunner: MockShortcutRunner!
    private var focusManager: FocusManager!
    private var poller: EarlyPoller!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        luxaforSession = URLSession(configuration: config)
        luxaforClient = LuxaforWebhookClient(session: luxaforSession)
        shortcutRunner = MockShortcutRunner()
        focusManager = FocusManager(runner: shortcutRunner)
        poller = EarlyPoller()
        KeychainService.shared.luxaforUserId = "test-user-id"
    }

    override func tearDown() {
        KeychainService.shared.luxaforUserId = nil
        MockURLProtocol.reset()
        super.tearDown()
    }

    private func makeEngine(mappings: [ActivityMapping]) -> StatusEngine {
        let config = ActivityMappingConfig(mappings: mappings)
        return StatusEngine(
            poller: poller,
            luxaforClient: luxaforClient,
            focusManager: focusManager,
            mappingProvider: { config }
        )
    }

    private func makeEntry(activityName: String) -> TrackingEntry {
        TrackingEntry(id: 1, activityId: 1, activityName: activityName, startedAt: Date.distantPast, note: nil)
    }

    // MARK: - Idle

    func testHandle_idle_turnsLuxaforOffAndDisablesFocus() async throws {
        MockURLProtocol.setStubQueue([.init(statusCode: 200, error: nil)])
        let engine = makeEngine(mappings: [])

        await engine.handle(.idle)

        XCTAssertEqual(shortcutRunner.runCalls, ["EarlySync: Focus Off"])
        let request = try XCTUnwrap(MockURLProtocol.allRecordedRequests().first)
        XCTAssertEqual(request.url?.absoluteString, "https://api.luxafor.co.uk/webhook/v1/actions/solid_color")
        XCTAssertNil(engine.lastAction?.activityName)
        XCTAssertEqual(engine.lastAction?.luxaforColor, .off)
        XCTAssertNil(engine.lastAction?.focusProfile)
        XCTAssertEqual(engine.lastAction?.success, true)
    }

    // MARK: - Tracking with a match, Focus enabled

    func testHandle_trackingWithMatch_focusEnabled_setsColorAndEnablesFocus() async {
        MockURLProtocol.setStubQueue([.init(statusCode: 200, error: nil)])
        let mapping = ActivityMapping(
            activityNameContains: ["deep work"],
            luxaforColor: .red,
            focusProfileName: "Work",
            enableFocus: true,
            label: "Deep Work"
        )
        let engine = makeEngine(mappings: [mapping])
        let entry = makeEntry(activityName: "Deep Work")

        await engine.handle(.tracking(entry: entry))

        XCTAssertEqual(shortcutRunner.runCalls, ["EarlySync: Work"])
        XCTAssertEqual(engine.lastAction?.activityName, "Deep Work")
        XCTAssertEqual(engine.lastAction?.luxaforColor, .red)
        XCTAssertEqual(engine.lastAction?.focusProfile, "Work")
        XCTAssertEqual(engine.lastAction?.success, true)
    }

    // MARK: - Tracking with a match, Focus disabled

    func testHandle_trackingWithMatch_focusDisabled_setsColorAndDisablesFocus() async {
        MockURLProtocol.setStubQueue([.init(statusCode: 200, error: nil)])
        let mapping = ActivityMapping(
            activityNameContains: ["break"],
            luxaforColor: .green,
            focusProfileName: nil,
            enableFocus: false,
            label: "Break"
        )
        let engine = makeEngine(mappings: [mapping])
        let entry = makeEntry(activityName: "Coffee break")

        await engine.handle(.tracking(entry: entry))

        XCTAssertEqual(shortcutRunner.runCalls, ["EarlySync: Focus Off"])
        XCTAssertEqual(engine.lastAction?.luxaforColor, .green)
        XCTAssertNil(engine.lastAction?.focusProfile)
        XCTAssertEqual(engine.lastAction?.success, true)
    }

    // MARK: - Tracking with no matching mapping

    func testHandle_trackingNoMatch_turnsOffAndDisablesFocus() async {
        MockURLProtocol.setStubQueue([.init(statusCode: 200, error: nil)])
        let engine = makeEngine(mappings: [])
        let entry = makeEntry(activityName: "Unmapped activity")

        await engine.handle(.tracking(entry: entry))

        XCTAssertEqual(shortcutRunner.runCalls, ["EarlySync: Focus Off"])
        XCTAssertEqual(engine.lastAction?.activityName, "Unmapped activity")
        XCTAssertEqual(engine.lastAction?.luxaforColor, .off)
        XCTAssertEqual(engine.lastAction?.success, true)
    }

    // MARK: - Partial failure

    func testHandle_luxaforFails_focusSucceeds_successIsFalse() async {
        // Both the initial attempt and the one retry fail.
        MockURLProtocol.setStubQueue([
            .init(statusCode: 500, error: nil),
            .init(statusCode: 500, error: nil),
        ])
        let mapping = ActivityMapping(
            activityNameContains: ["deep work"],
            luxaforColor: .red,
            focusProfileName: nil,
            enableFocus: false,
            label: "Deep Work"
        )
        let engine = makeEngine(mappings: [mapping])
        let entry = makeEntry(activityName: "Deep Work")

        await engine.handle(.tracking(entry: entry))

        XCTAssertEqual(engine.lastAction?.success, false)
    }

    func testHandle_focusFails_luxaforSucceeds_successIsFalse() async {
        MockURLProtocol.setStubQueue([.init(statusCode: 200, error: nil)])
        shortcutRunner.runHandler = { _ in throw FocusManagerError.shortcutFailed(1) }
        let mapping = ActivityMapping(
            activityNameContains: ["deep work"],
            luxaforColor: .red,
            focusProfileName: "Work",
            enableFocus: true,
            label: "Deep Work"
        )
        let engine = makeEngine(mappings: [mapping])
        let entry = makeEntry(activityName: "Deep Work")

        await engine.handle(.tracking(entry: entry))

        XCTAssertEqual(engine.lastAction?.success, false)
    }

    // MARK: - Ordering under rapid state changes

    /// Regression test for the race HoneyX found in PR #11: dispatching each state
    /// change as an independent, unlinked Task meant a slower call for an OLDER
    /// state could finish after a faster call for a NEWER one and clobber
    /// `lastAction` with stale data. `enqueue` now chains dispatches so they
    /// always complete in the order they arrived, regardless of relative speed.
    func testEnqueue_rapidStateChanges_lastActionReflectsMostRecentState() async {
        MockURLProtocol.setStubQueue([
            .init(statusCode: 200, error: nil),
            .init(statusCode: 200, error: nil),
        ])
        // The OLDER state's Focus call resolves slower than the newer one's.
        shortcutRunner.delays["EarlySync: A"] = 0.5

        let mappingA = ActivityMapping(
            activityNameContains: ["a work"],
            luxaforColor: .red,
            focusProfileName: "A",
            enableFocus: true,
            label: "A"
        )
        let mappingB = ActivityMapping(
            activityNameContains: ["b work"],
            luxaforColor: .blue,
            focusProfileName: "B",
            enableFocus: true,
            label: "B"
        )
        let engine = makeEngine(mappings: [mappingA, mappingB])

        engine.enqueue(.tracking(entry: makeEntry(activityName: "A work")))
        engine.enqueue(.tracking(entry: makeEntry(activityName: "B work")))

        await engine.waitForPendingWork()

        XCTAssertEqual(engine.lastAction?.activityName, "B work")
        XCTAssertEqual(engine.lastAction?.luxaforColor, .blue)
        XCTAssertEqual(engine.lastAction?.focusProfile, "B")
    }

    // MARK: - History

    func testHistory_capsAtHistoryLimit_newestFirst() async {
        let callCount = StatusEngine.historyLimit + 3
        MockURLProtocol.setStubQueue(Array(repeating: .init(statusCode: 200, error: nil), count: callCount))
        // Empty keyword list matches any activity name.
        let mapping = ActivityMapping(
            activityNameContains: [],
            luxaforColor: .red,
            focusProfileName: nil,
            enableFocus: false,
            label: "Any"
        )
        let engine = makeEngine(mappings: [mapping])

        for i in 0..<callCount {
            await engine.handle(.tracking(entry: makeEntry(activityName: "Activity \(i)")))
        }

        XCTAssertEqual(engine.history.count, StatusEngine.historyLimit)
        // Newest first, oldest entries evicted.
        XCTAssertEqual(engine.history.first?.activityName, "Activity \(callCount - 1)")
        XCTAssertEqual(engine.history.last?.activityName, "Activity 3")
    }
}
