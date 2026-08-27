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
/// itself is drawn in `NSColor.labelColor`, which resolves to the correct
/// black/white for light/dark menu bars at draw time; only the dot carries a
/// fixed, non-adaptive color.
///
/// Caveat: rendering correctness (this actually looks right) has not been
/// visually verified — this environment has no display. The one thing that
/// *is* verified by an automated test is that this doesn't crash and produces
/// a non-empty image; a manual look on a real Mac is still worthwhile.
enum MenuBarIconRenderer {
    static let size = NSSize(width: 18, height: 18)

    static func image(dotColor: MenuBarDotColor) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        if let clock = NSImage(systemSymbolName: "clock", accessibilityDescription: nil) {
            let tinted = clock.copy() as! NSImage
            tinted.isTemplate = true
            NSColor.labelColor.set()
            let rect = NSRect(origin: .zero, size: size)
            tinted.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
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
