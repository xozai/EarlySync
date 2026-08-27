import XCTest
@testable import EarlySync

// MARK: - MockShortcutRunner

private final class MockShortcutRunner: ShortcutRunning {
    var runHandler: ((String) throws -> Void)?
    private(set) var runCalls: [String] = []

    func run(_ shortcutName: String, timeout: TimeInterval) async throws {
        runCalls.append(shortcutName)
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
}
