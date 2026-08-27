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
    public let statusEngine: StatusEngine
    /// Shared with `StatusEngine` so the Settings UI (test light, Shortcuts wizard)
    /// reflects the same underlying state rather than a second, independent instance.
    let luxaforClient: LuxaforController
    let focusManager: FocusManager

    // MARK: - Published State

    @Published public var mappingConfig: ActivityMappingConfig

    // MARK: - Computed

    /// Menu bar glyph: a clock with a status dot colored to match the current
    /// Luxafor color (gray when idle or unmapped). See `MenuBarIcon.swift`.
    public var menuBarImage: NSImage {
        MenuBarIconRenderer.image(dotColor: menuBarDotColor(for: poller.trackingState, mappingConfig: mappingConfig))
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
        let store = mappingStore
        self.luxaforClient = LuxaforController(transportProvider: { store.load().transport })
        self.focusManager = FocusManager()
        self.statusEngine = StatusEngine(
            poller: poller,
            luxaforClient: luxaforClient,
            focusManager: focusManager,
            mappingProvider: { store.load() }
        )

        let savedInterval = UserDefaults.standard.double(forKey: Self.pollIntervalDefaultsKey)
        if savedInterval > 0 {
            poller.pollIntervalSeconds = savedInterval
        }

        // Start polling if we already have credentials
        if KeychainService.shared.hasEarlyCredentials() {
            poller.start()
        }
    }

    // MARK: - Poll Interval

    static let pollIntervalDefaultsKey = "com.earlysync.pollIntervalSeconds"

    public func setPollInterval(_ seconds: TimeInterval) {
        poller.pollIntervalSeconds = seconds
        UserDefaults.standard.set(seconds, forKey: Self.pollIntervalDefaultsKey)
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

    /// Persists a transport change without touching (or clobbering) any
    /// unsaved draft edits to `mappingConfig.mappings` — see issue #17.
    public func setTransport(_ transport: LuxaforTransport) {
        mappingConfig.transport = transport
        mappingStore.updateTransport(transport)
    }
}
