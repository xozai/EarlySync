import Combine

// MARK: - TrackingStateProvider

/// Supplies `TrackingState` changes to `StatusEngine`, decoupling it from a
/// specific transport.
///
/// `EarlyPoller` (REST, 30s interval) is the only conformer today — Early API v4
/// has no webhook/push mechanism (see issue #6). If Early ever ships one, a push-based
/// conformer can replace or supplement the poller here without any change to
/// `StatusEngine`, since it only ever depends on this protocol.
@MainActor
public protocol TrackingStateProvider: AnyObject {
    /// Emits only real state changes — never a replay of a value that predates
    /// the subscriber. `@Published` properties replay their current value to
    /// every new subscriber by default, so a conformer backed by one (like
    /// `EarlyPoller`) must drop that replay itself; a push-based conformer,
    /// where every emission is inherently a real event, needs no extra work
    /// to satisfy this.
    var trackingStatePublisher: AnyPublisher<TrackingState, Never> { get }
}

extension EarlyPoller: TrackingStateProvider {
    public var trackingStatePublisher: AnyPublisher<TrackingState, Never> {
        // dropFirst() discards the @Published replay of whatever state this
        // poller happened to hold before this subscriber attached (e.g. the
        // `.idle` default, pre-polling) — not a real change.
        $trackingState.dropFirst().eraseToAnyPublisher()
    }
}
