import Foundation

// MARK: - StatusAction

/// Records the last action `StatusEngine` took in response to an Early state change,
/// for surfacing in the UI (menu bar popover, later Settings UI).
public struct StatusAction: Equatable {
    public let timestamp: Date
    /// The Early activity name, or `nil` when idle.
    public let activityName: String?
    public let luxaforColor: LuxaforColor
    /// The Focus profile that was activated, or `nil` if Focus wasn't engaged.
    public let focusProfile: String?
    /// Whether both the Luxafor and Focus calls succeeded.
    public let success: Bool

    public init(
        timestamp: Date,
        activityName: String?,
        luxaforColor: LuxaforColor,
        focusProfile: String?,
        success: Bool
    ) {
        self.timestamp = timestamp
        self.activityName = activityName
        self.luxaforColor = luxaforColor
        self.focusProfile = focusProfile
        self.success = success
    }
}
