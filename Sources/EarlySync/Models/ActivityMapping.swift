import Foundation

// MARK: - ActivityMappingConfig

/// Maps Early activity names (and optional tags) to Luxafor colors and macOS Focus profiles.
/// Stored as JSON in ~/Library/Application Support/EarlySync/activity-mappings.json
/// so users can hand-edit if needed.
public struct ActivityMappingConfig: Codable {

    public var mappings: [ActivityMapping]
    /// How to talk to the Luxafor light. Defaults to `.webhook` for configs saved
    /// before this field existed — see the custom `init(from:)` below.
    public var transport: LuxaforTransport

    /// Default mappings used on first launch
    public static let defaults = ActivityMappingConfig(mappings: [
        ActivityMapping(
            id: UUID(),
            activityNameContains: ["deep work", "focus", "coding", "writing"],
            tagKeys: [],
            luxaforColor: .red,
            focusProfileName: "Work",
            enableFocus: true,
            label: "Deep Work"
        ),
        ActivityMapping(
            id: UUID(),
            activityNameContains: ["meeting", "call", "standup", "1:1"],
            tagKeys: [],
            luxaforColor: .blue,
            focusProfileName: "Do Not Disturb",
            enableFocus: true,
            label: "Meeting / Call"
        ),
        ActivityMapping(
            id: UUID(),
            activityNameContains: ["break", "lunch", "walk", "exercise"],
            tagKeys: [],
            luxaforColor: .green,
            focusProfileName: nil,
            enableFocus: false,
            label: "Break"
        ),
        ActivityMapping(
            id: UUID(),
            activityNameContains: ["admin", "email", "slack", "planning"],
            tagKeys: [],
            luxaforColor: .yellow,
            focusProfileName: nil,
            enableFocus: false,
            label: "Admin / Email"
        ),
    ])

    public init(mappings: [ActivityMapping], transport: LuxaforTransport = .webhook) {
        self.mappings = mappings
        self.transport = transport
    }

    private enum CodingKeys: String, CodingKey {
        case mappings
        case transport
    }

    // Custom decode so configs saved before `transport` existed still load —
    // the auto-synthesized Decodable would otherwise require the key and fall
    // back to `.defaults`, silently discarding the user's saved mappings.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.mappings = try container.decode([ActivityMapping].self, forKey: .mappings)
        self.transport = try container.decodeIfPresent(LuxaforTransport.self, forKey: .transport) ?? .webhook
    }

    /// Returns the first matching mapping for the given entry, or nil (= idle state)
    public func match(for entry: TrackingEntry) -> ActivityMapping? {
        let nameLower = entry.activityName.lowercased()
        let entryTagKeys = entry.note?.tags.map(\.key) ?? []

        return mappings.first { mapping in
            let nameMatch = mapping.activityNameContains.isEmpty ||
                mapping.activityNameContains.contains { nameLower.contains($0.lowercased()) }

            let tagMatch = mapping.tagKeys.isEmpty ||
                mapping.tagKeys.contains { entryTagKeys.contains($0) }

            return nameMatch && tagMatch
        }
    }
}

// MARK: - ActivityMapping

public struct ActivityMapping: Codable, Identifiable {
    public var id: UUID
    /// Activity name substrings to match (case-insensitive). Empty = match any name.
    public var activityNameContains: [String]
    /// Tag keys to match. Empty = ignore tags.
    public var tagKeys: [String]
    /// Luxafor color to set
    public var luxaforColor: LuxaforColor
    /// macOS Focus profile name (e.g. "Work", "Do Not Disturb"). nil = don't change Focus.
    public var focusProfileName: String?
    /// Whether to activate Focus when this mapping fires
    public var enableFocus: Bool
    /// Human-readable label for the UI
    public var label: String

    public init(
        id: UUID = UUID(),
        activityNameContains: [String],
        tagKeys: [String] = [],
        luxaforColor: LuxaforColor,
        focusProfileName: String?,
        enableFocus: Bool,
        label: String
    ) {
        self.id = id
        self.activityNameContains = activityNameContains
        self.tagKeys = tagKeys
        self.luxaforColor = luxaforColor
        self.focusProfileName = focusProfileName
        self.enableFocus = enableFocus
        self.label = label
    }
}

// MARK: - LuxaforColor

/// Colors supported by the Luxafor Webhook API
public enum LuxaforColor: String, Codable, CaseIterable {
    case red
    case green
    case yellow
    case blue
    case white
    case cyan
    case magenta
    case off  // special: sends #000000 to turn off

    public var displayName: String {
        switch self {
        case .off: return "Off"
        default: return rawValue.capitalized
        }
    }

    public var hexColor: String {
        switch self {
        case .red:     return "FF0000"
        case .green:   return "00FF00"
        case .yellow:  return "FFFF00"
        case .blue:    return "0000FF"
        case .white:   return "FFFFFF"
        case .cyan:    return "00FFFF"
        case .magenta: return "FF00FF"
        case .off:     return "000000"
        }
    }

    // MARK: - Emoji representation for menu bar / UI
    public var emoji: String {
        switch self {
        case .red:     return "🔴"
        case .green:   return "🟢"
        case .yellow:  return "🟡"
        case .blue:    return "🔵"
        case .white:   return "⚪"
        case .cyan:    return "🩵"
        case .magenta: return "🟣"
        case .off:     return "⚫"
        }
    }
}

// MARK: - LuxaforTransport

/// How EarlySync talks to the Luxafor light.
public enum LuxaforTransport: String, Codable, CaseIterable {
    /// Luxafor's cloud webhook API — needs internet + Luxafor software running.
    case webhook
    /// Direct USB/HID control — works offline, falls back to `.webhook` if no device is found.
    case usb

    public var displayName: String {
        switch self {
        case .webhook: return "Webhook (cloud)"
        case .usb: return "USB / Local"
        }
    }
}

// MARK: - ActivityMappingStore

/// Loads and persists `ActivityMappingConfig` from the app support directory.
public final class ActivityMappingStore {

    public static let shared = ActivityMappingStore()

    private let fileURL: URL

    private convenience init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("EarlySync", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.init(fileURL: dir.appendingPathComponent("activity-mappings.json"))
    }

    /// Test-only hook so tests can point at a throwaway file instead of the
    /// real one in Application Support.
    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() -> ActivityMappingConfig {
        guard let data = try? Data(contentsOf: fileURL),
              let config = try? JSONDecoder().decode(ActivityMappingConfig.self, from: data)
        else {
            return .defaults
        }
        return config
    }

    /// Updates only `transport` in the persisted config, leaving any other
    /// fields on disk untouched — so a transport change made from one tab
    /// never clobbers unsaved, in-progress edits held elsewhere (e.g. the
    /// Activity Mapping tab's draft rows). See issue #17.
    public func updateTransport(_ transport: LuxaforTransport) {
        var onDisk = load()
        onDisk.transport = transport
        save(onDisk)
    }

    public func save(_ config: ActivityMappingConfig) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(config) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
