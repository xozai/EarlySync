import SwiftUI

// MARK: - MenuBarView

/// The popover that appears when the user clicks the EarlySync menu bar icon.
/// Phase 1: shows current tracking state, error, last poll time.
struct MenuBarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "clock.fill")
                    .foregroundStyle(.blue)
                Text("EarlySync")
                    .font(.headline)
                Spacer()
                if appState.poller.isPolling {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(.secondary)
                        .help("Polling every 30s")
                }
            }

            Divider()

            // Tracking status
            trackingStatusView

            // Error display
            if let error = appState.poller.lastError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Last poll
            if let lastPoll = appState.poller.lastPollDate {
                Text("Last checked \(lastPoll.formatted(.relative(presentation: .named)))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Last StatusEngine action
            if let action = appState.statusEngine.lastAction {
                Divider()
                HStack(spacing: 6) {
                    Text(action.luxaforColor.emoji)
                    Text(action.focusProfile.map { "Focus: \($0)" } ?? action.luxaforColor.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !action.success {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .help("One or more actions failed — see Preferences > History")
                    }
                }
            }

            Divider()

            // Actions
            HStack {
                Button("Preferences") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
                .buttonStyle(.plain)

                Spacer()

                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            }
            .font(.caption)
        }
        .padding(16)
        .frame(width: 280)
    }

    // MARK: - Tracking Status

    @ViewBuilder
    private var trackingStatusView: some View {
        switch appState.poller.trackingState {
        case .idle:
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.gray)
                    .frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Not tracking")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("Open Early to start tracking")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

        case .tracking(let entry):
            let mapping = appState.mappingConfig.match(for: entry)
            HStack(spacing: 8) {
                Circle()
                    .fill(luxaforSwiftUIColor(mapping?.luxaforColor ?? .green))
                    .frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.activityName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(entry.durationString)
                        if let label = mapping?.label {
                            Text("·")
                            Text(label)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    if !entry.tagLabels.isEmpty {
                        Text(entry.tagLabels)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private func luxaforSwiftUIColor(_ color: LuxaforColor) -> Color {
        switch color {
        case .red:     return .red
        case .green:   return .green
        case .yellow:  return .yellow
        case .blue:    return .blue
        case .white:   return .white
        case .cyan:    return .cyan
        case .magenta: return .purple
        case .off:     return .gray
        }
    }
}
