import SwiftUI

// MARK: - StatusHistoryView

/// Shows the last `StatusEngine.historyLimit` actions StatusEngine has taken,
/// newest first — a mini audit log for "why did my light just change?".
struct StatusHistoryView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Activity")
                .font(.headline)

            if appState.statusEngine.history.isEmpty {
                Text("No actions yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                List(appState.statusEngine.history.indices, id: \.self) { index in
                    HistoryRow(action: appState.statusEngine.history[index])
                }
                .frame(minHeight: 200)
            }
        }
        .padding()
    }
}

// MARK: - HistoryRow

private struct HistoryRow: View {
    let action: StatusAction

    var body: some View {
        HStack(spacing: 8) {
            Text(action.luxaforColor.emoji)
            VStack(alignment: .leading, spacing: 2) {
                Text(action.activityName ?? "Idle")
                    .font(.subheadline)
                if let profile = action.focusProfile {
                    Text("Focus: \(profile)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !action.success {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("One or more actions failed")
            }
            Text(action.timestamp.formatted(.relative(presentation: .named)))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}
