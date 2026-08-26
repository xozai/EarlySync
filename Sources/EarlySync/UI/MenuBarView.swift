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

// MARK: - PreferencesView (Phase 1 stub)

/// Preferences window — Phase 1 shows credential entry only.
/// Mapping table and Luxafor config added in Phase 5.
struct PreferencesView: View {
    @EnvironmentObject var appState: AppState
    @State private var apiKey: String = ""
    @State private var apiSecret: String = ""
    @State private var isSaving = false
    @State private var saveMessage: String?

    var body: some View {
        Form {
            Section("Early API Credentials") {
                TextField("API Key", text: $apiKey)
                    .textContentType(.username)

                SecureField("API Secret", text: $apiSecret)
                    .textContentType(.password)

                HStack {
                    Button(isSaving ? "Connecting…" : "Save & Connect") {
                        Task { await saveCredentials() }
                    }
                    .disabled(apiKey.isEmpty || apiSecret.isEmpty || isSaving)

                    if let msg = saveMessage {
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(msg.contains("✓") ? .green : .red)
                    }
                }

                Link("Get API Key at product.early.app →",
                     destination: URL(string: "https://product.early.app")!)
                    .font(.caption)
            }

            Section("Status") {
                LabeledContent("Auth state") {
                    Text(authStateText)
                        .foregroundStyle(authStateColor)
                }
                LabeledContent("Polling") {
                    Text(appState.poller.isPolling ? "Active (every 30s)" : "Stopped")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 300)
        .padding()
        .onAppear {
            // Pre-fill if credentials already saved
            apiKey = KeychainService.shared.earlyAPIKey ?? ""
        }
        .navigationTitle("EarlySync Preferences")
    }

    private var authStateText: String {
        switch appState.authService.authState {
        case .unauthenticated: return "Not connected"
        case .authenticating:  return "Connecting…"
        case .authenticated:   return "Connected ✓"
        case .failed(let err): return err.localizedDescription
        }
    }

    private var authStateColor: Color {
        switch appState.authService.authState {
        case .authenticated: return .green
        case .failed:        return .red
        default:             return .secondary
        }
    }

    private func saveCredentials() async {
        isSaving = true
        saveMessage = nil
        await appState.authService.signIn(apiKey: apiKey, apiSecret: apiSecret)
        isSaving = false
        switch appState.authService.authState {
        case .authenticated:
            saveMessage = "Connected ✓"
            appState.startPolling()
        case .failed(let err):
            saveMessage = err.localizedDescription
        default:
            break
        }
    }
}
