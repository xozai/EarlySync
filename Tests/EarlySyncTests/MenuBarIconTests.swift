import XCTest
@testable import EarlySync

// MARK: - menuBarDotColor Tests

final class MenuBarDotColorTests: XCTestCase {

    func testIdle_isGray() {
        XCTAssertEqual(menuBarDotColor(for: .idle, mappingConfig: .defaults), .gray)
    }

    func testTrackingWithMatch_usesMappingColor() {
        let entry = makeEntry(activityName: "Deep Work")
        XCTAssertEqual(
            menuBarDotColor(for: .tracking(entry: entry), mappingConfig: .defaults),
            .color(.red)
        )
    }

    func testTrackingWithNoMatch_isGray() {
        let entry = makeEntry(activityName: "Some uncategorized thing")
        XCTAssertEqual(
            menuBarDotColor(for: .tracking(entry: entry), mappingConfig: .defaults),
            .gray
        )
    }
}

// MARK: - MenuBarIconRenderer Tests

/// Only a smoke test — this environment has no display to visually confirm
/// the rendered glyph looks right. This does confirm the drawing code runs
/// without crashing and produces a real, non-empty image, which is the one
/// thing an automated test here can meaningfully check.
final class MenuBarIconRendererTests: XCTestCase {

    func testImage_grayDot_producesNonEmptyImage() {
        let image = MenuBarIconRenderer.image(dotColor: .gray)
        XCTAssertEqual(image.size, MenuBarIconRenderer.size)
        XCTAssertFalse(image.representations.isEmpty)
    }

    func testImage_coloredDot_producesNonEmptyImage() {
        let image = MenuBarIconRenderer.image(dotColor: .color(.red))
        XCTAssertEqual(image.size, MenuBarIconRenderer.size)
        XCTAssertFalse(image.representations.isEmpty)
    }

    func testNSColor_mapsEveryLuxaforColor() {
        for color in LuxaforColor.allCases {
            _ = MenuBarIconRenderer.nsColor(for: .color(color))
        }
        // No crash / exhaustive switch is the assertion — every case must be handled.
    }
}
