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

    /// Regression test for issue #20: HoneyX found that `NSColor.set()` before
    /// `NSImage.draw()` doesn't retint anything — it only affects subsequent
    /// *path* drawing, not compositing an existing image. Rendering under
    /// forced light/dark appearances and sampling actual pixel RGB (no
    /// display needed) previously showed the glyph rendering the same dark
    /// gray in both — this confirms the fixed version actually adapts.
    func testGlyphTint_adaptsToLightAndDarkAppearance() throws {
        let light = try Self.averageGlyphRGB(appearance: .aqua)
        let dark = try Self.averageGlyphRGB(appearance: .darkAqua)

        XCTAssertLessThan(light, 0.35, "light-mode glyph should render dark (near-black)")
        XCTAssertGreaterThan(dark, 0.65, "dark-mode glyph should render light (near-white)")
        XCTAssertGreaterThan(dark - light, 0.3, "glyph tint must actually differ between appearances")
    }

    /// Average red-channel value (0...1) of opaque pixels in the glyph area,
    /// excluding the bottom-right corner where the status dot sits — the dot
    /// is intentionally non-adaptive, so it would mask a regression here.
    private static func averageGlyphRGB(appearance name: NSAppearance.Name) throws -> CGFloat {
        guard let appearance = NSAppearance(named: name) else {
            throw XCTSkip("NSAppearance(named: \(name.rawValue)) unavailable in this environment")
        }

        var image: NSImage!
        appearance.performAsCurrentDrawingAppearance {
            image = MenuBarIconRenderer.image(dotColor: .gray)
        }

        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else {
            throw XCTSkip("Could not create a bitmap representation in this environment")
        }

        let dotExclusionFraction: CGFloat = 0.5 // exclude the right half where the dot lives
        var total: CGFloat = 0
        var count = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                if CGFloat(x) > CGFloat(bitmap.pixelsWide) * (1 - dotExclusionFraction) { continue }
                guard let color = bitmap.colorAt(x: x, y: y), color.alphaComponent > 0.5 else { continue }
                total += color.redComponent
                count += 1
            }
        }
        guard count > 0 else {
            throw XCTSkip("No opaque glyph pixels sampled — SF Symbol may not have rendered in this environment")
        }
        return total / CGFloat(count)
    }
}
