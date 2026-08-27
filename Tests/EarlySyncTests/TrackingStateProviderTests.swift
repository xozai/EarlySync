import XCTest
import Combine
@testable import EarlySync

// MARK: - MockTrackingStateProvider

/// A non-`EarlyPoller` conformer, standing in for a future push-based provider
/// (see issue #6). Proves `StatusEngine` only ever depends on the
/// `TrackingStateProvider` protocol, not the concrete poller.
@MainActor
private final class MockTrackingStateProvider: TrackingStateProvider {
    private let subject = PassthroughSubject<TrackingState, Never>()

    var trackingStatePublisher: AnyPublisher<TrackingState, Never> {
        subject.eraseToAnyPublisher()
    }

    func emit(_ state: TrackingState) {
        subject.send(state)
    }
}

// MARK: - TrackingStateProviderTests

@MainActor
final class TrackingStateProviderTests: XCTestCase {

    private var luxaforSession: URLSession!
    private var luxaforClient: LuxaforWebhookClient!
    private var shortcutRunner: MockShortcutRunnerForProviderTests!
    private var focusManager: FocusManager!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        luxaforSession = URLSession(configuration: config)
        luxaforClient = LuxaforWebhookClient(session: luxaforSession)
        shortcutRunner = MockShortcutRunnerForProviderTests()
        focusManager = FocusManager(runner: shortcutRunner)
        KeychainService.shared.luxaforUserId = "test-user-id"
    }

    override func tearDown() {
        KeychainService.shared.luxaforUserId = nil
        MockURLProtocol.reset()
        super.tearDown()
    }

    func testStatusEngine_drivenByNonPollerProvider_dispatchesOnStateChange() async {
        MockURLProtocol.setStubQueue([.init(statusCode: 200, error: nil)])
        let provider = MockTrackingStateProvider()
        let mapping = ActivityMapping(
            activityNameContains: ["deep work"],
            luxaforColor: .red,
            focusProfileName: "Work",
            enableFocus: true,
            label: "Deep Work"
        )
        let config = ActivityMappingConfig(mappings: [mapping])
        let engine = StatusEngine(
            stateProvider: provider,
            luxaforClient: luxaforClient,
            focusManager: focusManager,
            mappingProvider: { config }
        )

        let entry = TrackingEntry(id: 1, activityId: 1, activityName: "Deep Work", startedAt: .distantPast, note: nil)
        provider.emit(.tracking(entry: entry))
        await engine.waitForPendingWork()

        XCTAssertEqual(shortcutRunner.runCalls, ["EarlySync: Work"])
        XCTAssertEqual(engine.lastAction?.activityName, "Deep Work")
        XCTAssertEqual(engine.lastAction?.luxaforColor, .red)
    }
}

// MARK: - MockShortcutRunnerForProviderTests

private final class MockShortcutRunnerForProviderTests: ShortcutRunning {
    private(set) var runCalls: [String] = []

    func run(_ shortcutName: String, timeout: TimeInterval) async throws {
        runCalls.append(shortcutName)
    }

    func list(timeout: TimeInterval) async throws -> [String] { [] }
}
