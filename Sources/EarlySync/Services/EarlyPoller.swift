import Foundation
import Combine

// MARK: - EarlyPoller

/// Periodically polls the Early API and publishes `TrackingState` changes.
///
/// - Polls on a configurable interval (default: 30s)
/// - Debounces state changes by 5 seconds to avoid flicker on accidental stop/restart
/// - Publishes via Combine `@Published` — subscribe on main actor for UI binding
/// - Only emits when state actually changes (deduplicates identical consecutive states)
@MainActor
public final class EarlyPoller: ObservableObject {

    // MARK: - Published State

    @Published public private(set) var trackingState: TrackingState = .idle
    @Published public private(set) var lastError: EarlyAPIError?
    @Published public private(set) var isPolling: Bool = false
    @Published public private(set) var lastPollDate: Date?

    // MARK: - Configuration

    public struct Configuration {
        /// How often to poll Early (seconds)
        public var pollInterval: TimeInterval
        /// How long to wait before propagating a state change (debounce)
        public var debounceInterval: TimeInterval

        public static let `default` = Configuration(
            pollInterval: 30,
            debounceInterval: 5
        )

        public init(pollInterval: TimeInterval = 30, debounceInterval: TimeInterval = 5) {
            self.pollInterval = pollInterval
            self.debounceInterval = debounceInterval
        }
    }

    // MARK: - Private

    private let apiClient: EarlyAPIClient
    private let config: Configuration
    private var pollTask: Task<Void, Never>?
    private var pendingState: TrackingState?
    private var debounceTask: Task<Void, Never>?

    // MARK: - Init

    public init(
        apiClient: EarlyAPIClient = EarlyAPIClient(),
        config: Configuration = .default
    ) {
        self.apiClient = apiClient
        self.config = config
    }

    // MARK: - Lifecycle

    /// Start polling. Safe to call multiple times (idempotent).
    public func start() {
        guard pollTask == nil else { return }
        isPolling = true
        pollTask = Task { [weak self] in
            guard let self else { return }
            // Poll immediately, then on interval
            await self.poll()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(self.config.pollInterval * 1_000_000_000))
                if !Task.isCancelled {
                    await self.poll()
                }
            }
        }
    }

    /// Stop polling. Safe to call when not started.
    public func stop() {
        pollTask?.cancel()
        pollTask = nil
        debounceTask?.cancel()
        debounceTask = nil
        isPolling = false
    }

    // MARK: - Poll

    private func poll() async {
        do {
            let newState = try await apiClient.fetchTrackingState()
            lastPollDate = Date()
            lastError = nil
            await applyStateChange(newState)
        } catch let error as EarlyAPIError {
            lastError = error
        } catch {
            lastError = .networkError(error.localizedDescription)
        }
    }

    // MARK: - Debounce

    /// Applies a state change with debounce — holds the new state for `debounceInterval`
    /// seconds before committing. If another change arrives in that window, the timer resets.
    /// This prevents flicker when the user accidentally stops and immediately restarts tracking.
    private func applyStateChange(_ newState: TrackingState) async {
        // Skip if state didn't change
        if newState == trackingState && pendingState == nil { return }

        // Idle → tracking: apply immediately (no need to debounce starting)
        if case .tracking = newState, case .idle = trackingState {
            pendingState = nil
            debounceTask?.cancel()
            trackingState = newState
            return
        }

        // tracking → idle or activity change: debounce
        pendingState = newState
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(self.config.debounceInterval * 1_000_000_000))
            if !Task.isCancelled, let pending = self.pendingState {
                self.trackingState = pending
                self.pendingState = nil
            }
        }
    }
}

// MARK: - TrackingEntry + Display Helpers

public extension TrackingEntry {
    /// Duration since the entry started
    var duration: TimeInterval {
        Date().timeIntervalSince(startedAt)
    }

    /// Human-readable duration string, e.g. "1h 23m"
    var durationString: String {
        let total = Int(duration)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    /// Tag labels as a comma-separated string
    var tagLabels: String {
        note?.tags.map(\.label).joined(separator: ", ") ?? ""
    }
}
