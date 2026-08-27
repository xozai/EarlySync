import XCTest
@testable import EarlySync

// MARK: - LuxaforHIDClientTests

/// Only the pure report-encoding logic is testable here — device discovery
/// and the actual `IOHIDDeviceSetReport` write require real hardware, which
/// this environment doesn't have. See the caveat in LuxaforHIDClient.swift.
final class LuxaforHIDClientTests: XCTestCase {

    func testReportBytes_red() {
        let bytes = LuxaforHIDClient.reportBytes(for: .red)
        XCTAssertEqual(bytes, [0x00, 0x01, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00])
    }

    func testReportBytes_off_isBlack() {
        let bytes = LuxaforHIDClient.reportBytes(for: .off)
        XCTAssertEqual(bytes, [0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
    }

    func testReportBytes_white() {
        let bytes = LuxaforHIDClient.reportBytes(for: .white)
        XCTAssertEqual(bytes, [0x00, 0x01, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00])
    }

    func testRgbComponents_parsesHex() {
        let (r, g, b) = LuxaforHIDClient.rgbComponents(fromHex: "00FF80")
        XCTAssertEqual(r, 0x00)
        XCTAssertEqual(g, 0xFF)
        XCTAssertEqual(b, 0x80)
    }
}
