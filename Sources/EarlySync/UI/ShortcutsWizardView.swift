import SwiftUI

// MARK: - ShortcutsWizardView

/// Detects whether the two Apple Shortcuts EarlySync needs ("EarlySync: Focus On"
/// and "EarlySync: Focus Off") are configured, and walks the user through
/// creating them if not.
struct ShortcutsWizardView: View {
    @EnvironmentObject var appState: AppState

    @State private var focusOnConfigured: Bool?
    @State private var focusOffConfigured: Bool?
    @State private var isChecking = false

    private var bothConfigured: Bool {
        focusOnConfigured == true && focusOffConfigured == true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Shortcuts Setup")
                    .font(.headline)
                Spacer()
                if bothConfigured {
                    Label("Configured", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
            }

            statusRow(name: FocusManager.focusOnShortcutName, configured: focusOnConfigured)
            statusRow(name: FocusManager.focusOffShortcutName, configured: focusOffConfigured)

            if !bothConfigured {
                Text("""
                EarlySync activates macOS Focus by running Shortcuts named above. \
                Create both in Shortcuts.app (they can just toggle Focus modes), \
                then check again.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)

                Button("Open Shortcuts.app") {
                    appState.focusManager.openShortcutsSetupGuide()
                }
            }

            Button(isChecking ? "Checking…" : "Check Again") {
                Task { await checkShortcuts() }
            }
            .disabled(isChecking)
        }
        .padding()
        .task {
            await checkShortcuts()
        }
    }

    @ViewBuilder
    private func statusRow(name: String, configured: Bool?) -> some View {
        HStack(spacing: 6) {
            switch configured {
            case .some(true):
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .some(false):
                Image(systemName: "xmark.circle.fill").foregroundStyle(.orange)
            case .none:
                ProgressView().controlSize(.small)
            }
            Text(name).font(.caption)
        }
    }

    private func checkShortcuts() async {
        isChecking = true
        async let focusOn = appState.focusManager.isShortcutConfigured(FocusManager.focusOnShortcutName)
        async let focusOff = appState.focusManager.isShortcutConfigured(FocusManager.focusOffShortcutName)
        focusOnConfigured = await focusOn
        focusOffConfigured = await focusOff
        isChecking = false
    }
}
