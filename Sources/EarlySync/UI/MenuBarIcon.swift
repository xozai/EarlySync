import AppKit

// MARK: - MenuBarDotColor

/// What color the menu bar status dot should be — separated from `LuxaforColor`
/// so idle state (no mapping in play at all) is representable without
/// overloading `LuxaforColor.off`, which already means something else
/// (Luxafor commanded to black, still under an active mapping).
enum MenuBarDotColor: Equatable {
    case gray
    case color(LuxaforColor)
}

/// Pure mapping from tracking state to the dot color that should show in the
/// menu bar — no AppKit involved, so this is fully unit-testable.
func menuBarDotColor(for state: TrackingState, mappingConfig: ActivityMappingConfig) -> MenuBarDotColor {
    switch state {
    case .idle:
        return .gray
    case .tracking(let entry):
        guard let mapping = mappingConfig.match(for: entry) else { return .gray }
        return .color(mapping.luxaforColor)
    }
}

// MARK: - MenuBarIconRenderer

/// Draws the menu bar glyph: a clock outline with a colored status dot overlay.
///
/// Not a template image — a template image is masked to a single system color,
/// which would erase the whole point of a colored dot. Instead the clock glyph
/// is manually retinted to `NSColor.labelColor` (see `tintedClockGlyph(_:)`),
/// which resolves to the correct black/white for light/dark menu bars at draw
/// time; only the dot carries a fixed, non-adaptive color.
///
/// Caveat: no display in this environment, so the result has never been
/// eyeballed. What *is* verified: an automated test renders under forced
/// `.aqua`/`.darkAqua` appearances and samples actual pixel RGB via
/// `NSBitmapImageRep` to confirm the glyph tint really does differ between
/// light and dark — not just that drawing doesn't crash. A manual look on a
/// real Mac is still worthwhile.
enum MenuBarIconRenderer {
    static let size = NSSize(width: 18, height: 18)

    static func image(dotColor: MenuBarDotColor) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        if let clock = NSImage(systemSymbolName: "clock", accessibilityDescription: nil) {
            tintedClockGlyph(clock).draw(in: NSRect(origin: .zero, size: size))
        }

        let dotDiameter: CGFloat = 7
        let dotRect = NSRect(
            x: size.width - dotDiameter - 1,
            y: 0,
            width: dotDiameter,
            height: dotDiameter
        )
        nsColor(for: dotColor).setFill()
        NSBezierPath(ovalIn: dotRect).fill()

        return image
    }

    /// Manually retints a template image to `NSColor.labelColor`.
    ///
    /// `NSColor.set()` followed by `NSImage.draw()` does NOT retint an image —
    /// `.set()` only affects subsequent *path* drawing (`NSBezierPath.fill()`,
    /// etc.), and `isTemplate` only auto-tints when an AppKit control renders
    /// the image, not a manual `lockFocus()`/`draw()` call. (Caught by HoneyX
    /// in issue #20, verified by pixel-sampling under forced light/dark
    /// appearances — the untinted version rendered the same dark gray in both.)
    ///
    /// The correct technique: draw the template image into a fresh context,
    /// then fill that context with the target color using `.sourceAtop`,
    /// which paints only where the glyph already has non-zero alpha.
    private static func tintedClockGlyph(_ image: NSImage) -> NSImage {
        let tinted = NSImage(size: image.size)
        tinted.lockFocus()
        image.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1.0)
        NSColor.labelColor.set()
        NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop)
        tinted.unlockFocus()
        return tinted
    }

    static func nsColor(for dotColor: MenuBarDotColor) -> NSColor {
        switch dotColor {
        case .gray:
            return .systemGray
        case .color(let color):
            switch color {
            case .red:     return .systemRed
            case .green:   return .systemGreen
            case .yellow:  return .systemYellow
            case .blue:    return .systemBlue
            case .white:   return .white
            case .cyan:    return .systemCyan
            case .magenta: return .systemPurple
            case .off:     return .systemGray
            }
        }
    }
}
