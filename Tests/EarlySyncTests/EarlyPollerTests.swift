import XCTest
import Combine
@testable import EarlySync

// MARK: - EarlyPollerTests

@MainActor
final class EarlyPollerTests: XCTestCase {

    func testPollIntervalSeconds_defaultsToConfigValue() {
        let poller = EarlyPoller(config: .init(pollInterval: 45, debounceInterval: 5))
        XCTAssertEqual(poller.pollIntervalSeconds, 45)
    }

    func testPollIntervalSeconds_isMutable() {
        let poller = EarlyPoller()
        poller.pollIntervalSeconds = 60
        XCTAssertEqual(poller.pollIntervalSeconds, 60)
    }

    // MARK: - TrackingStateProvider conformance

    /// `$trackingState` replays its current value (`.idle`) to every new subscriber —
    /// `trackingStatePublisher` must drop that replay so it only emits real changes,
    /// per the `TrackingStateProvider` contract.
    func testTrackingStatePublisher_doesNotReplayCurrentValueToNewSubscriber() {
        let poller = EarlyPoller()
        let provider: any TrackingStateProvider = poller
        var received: [TrackingState] = []
        let cancellable = provider.trackingStatePublisher.sink { received.append($0) }

        XCTAssertTrue(received.isEmpty)
        cancellable.cancel()
    }
}
