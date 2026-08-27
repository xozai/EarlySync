import Foundation
import Combine

// MARK: - StatusEngine

/// Subscribes to `EarlyPoller.trackingState` and dispatches the matching
/// `ActivityMapping`'s action to `LuxaforWebhookClient` and `FocusManager`.
///
/// Idle state or an entry with no matching mapping turns the Luxafor light
/// off and deactivates Focus.
@MainActor
public final class StatusEngine: ObservableObject {

    // MARK: - Published State

    @Published public private(set) var lastAction: StatusAction?

    // MARK: - Dependencies

    private let luxaforClient: LuxaforWebhookClient
    private let focusManager: FocusManager
    private let mappingProvider: () -> ActivityMappingConfig
    private var cancellable: AnyCancellable?
    /// Chains dispatched state handling so a slower older call can't overwrite
    /// `lastAction` after a faster newer one already ran — see `enqueue(_:)`.
    private var pendingWork: Task<Void, Never>?

    // MARK: - Init

    init(
        poller: EarlyPoller,
        luxaforClient: LuxaforWebhookClient = LuxaforWebhookClient(),
        focusManager: FocusManager = FocusManager(),
        mappingProvider: @escaping () -> ActivityMappingConfig
    ) {
        self.luxaforClient = luxaforClient
        self.focusManager = focusManager
        self.mappingProvider = mappingProvider

        // dropFirst() skips the replay of the poller's current value on subscription —
        // StatusEngine should react to state *changes*, not fire an action at construction
        // time using whatever value the poller happened to hold before polling even starts.
        cancellable = poller.$trackingState
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] state in
                self?.enqueue(state)
            }
    }

    // MARK: - Dispatch ordering

    /// Each poller state change used to spawn an independent, unlinked `Task`,
    /// so a slower call for an older state could finish after — and overwrite
    /// `lastAction` for — a faster call for a newer state. Chaining onto
    /// `pendingWork` forces strictly in-order processing: a new state's
    /// `handle(_:)` never starts until every previously enqueued one has
    /// finished, so `lastAction` always ends up reflecting the most recent state.
    func enqueue(_ state: TrackingState) {
        let previous = pendingWork
        pendingWork = Task { [weak self] in
            _ = await previous?.value
            await self?.handle(state)
        }
    }

    /// Awaits the current dispatch chain — test-only hook to observe `lastAction`
    /// only after all enqueued state handling has completed.
    func waitForPendingWork() async {
        await pendingWork?.value
    }

    // MARK: - Handling

    func handle(_ state: TrackingState) async {
        switch state {
        case .idle:
            lastAction = await turnOff(activityName: nil)

        case .tracking(let entry):
            guard let mapping = mappingProvider().match(for: entry) else {
                lastAction = await turnOff(activityName: entry.activityName)
                return
            }

            let luxaforSuccess = await luxaforClient.setColor(mapping.luxaforColor)
            let focusProfile = mapping.enableFocus ? mapping.focusProfileName : nil
            let focusSuccess = mapping.enableFocus
                ? await focusManager.enableFocus(profile: mapping.focusProfileName)
                : await focusManager.disableFocus()

            lastAction = StatusAction(
                timestamp: Date(),
                activityName: entry.activityName,
                luxaforColor: mapping.luxaforColor,
                focusProfile: focusProfile,
                success: luxaforSuccess && focusSuccess
            )
        }
    }

    // MARK: - Private

    private func turnOff(activityName: String?) async -> StatusAction {
        let luxaforSuccess = await luxaforClient.off()
        let focusSuccess = await focusManager.disableFocus()
        return StatusAction(
            timestamp: Date(),
            activityName: activityName,
            luxaforColor: .off,
            focusProfile: nil,
            success: luxaforSuccess && focusSuccess
        )
    }
}
