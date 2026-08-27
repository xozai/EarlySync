import XCTest
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
}
