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
                guard let self else { return }
                Task { await self.handle(state) }
            }
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
