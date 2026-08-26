import SwiftUI
import Combine

// MARK: - AppState

/// Root observable state for the entire EarlySync app.
///
/// Owns the poller and auth service. All UI subscribes through this object.
/// Phase 1: wires Early polling only. Luxafor + Focus actions are stubs.
@MainActor
public final class AppState: ObservableObject {

    // MARK: - Services

    public let poller: EarlyPoller
    public let authService: EarlyAuthService
    public let mappingStore: ActivityMappingStore

    // MARK: - Published State

    @Published public var mappingConfig: ActivityMappingConfig

    // MARK: - Computed

    /// The menu bar SF Symbol name based on current tracking state
    public var menuBarIcon: String {
        switch poller.trackingState {
        case .idle:
            return "clock"
        case .tracking(let entry):
            let mapping = mappingConfig.match(for: entry)
            switch mapping?.luxaforColor {
            case .red:    return "clock.fill"  // active / focused
            case .blue:   return "phone.fill"  // meeting
            case .green:  return "leaf.fill"   // break
            case .yellow: return "envelope.fill" // admin
            default:      return "clock.badge.checkmark"
            }
        }
    }

    /// Short status string for menu bar popover
    public var statusSummary: String {
        switch poller.trackingState {
        case .idle:
            return "Not tracking"
        case .tracking(let entry):
            return "\(entry.activityName) · \(entry.durationString)"
        }
    }

    // MARK: - Init

    public init() {
        let apiClient = EarlyAPIClient()
        self.poller = EarlyPoller(apiClient: apiClient)
        self.authService = EarlyAuthService(apiClient: apiClient)
        self.mappingStore = .shared
        self.mappingConfig = mappingStore.load()

        // Start polling if we already have credentials
        if KeychainService.shared.hasEarlyCredentials() {
            poller.start()
        }
    }

    // MARK: - Actions

    public func startPolling() {
        poller.start()
    }

    public func stopPolling() {
        poller.stop()
    }

    public func saveMapping() {
        mappingStore.save(mappingConfig)
    }
}
