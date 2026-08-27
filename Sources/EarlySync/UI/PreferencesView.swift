import SwiftUI
import ServiceManagement

// MARK: - PreferencesView

/// Preferences window: account credentials, activity mapping table, Luxafor +
/// Focus setup, and recent action history.
struct PreferencesView: View {
    var body: some View {
        TabView {
            AccountTab()
                .tabItem { Label("Account", systemImage: "person.crop.circle") }

            MappingTableView()
                .tabItem { Label("Activity Mapping", systemImage: "list.bullet.rectangle") }

            LuxaforFocusTab()
                .tabItem { Label("Luxafor & Focus", systemImage: "lightbulb") }

            StatusHistoryView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
        }
        .frame(width: 480, height: 420)
        .navigationTitle("EarlySync Preferences")
    }
}

// MARK: - AccountTab

private struct AccountTab: View {
    @EnvironmentObject var appState: AppState
    @State private var apiKey: String = ""
    @State private var apiSecret: String = ""
    @State private var isSaving = false
    @State private var saveMessage: String?
    @State private var launchAtLoginEnabled = SMAppService.mainApp.status == .enabled

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

            Section("Polling") {
                LabeledContent("Auth state") {
                    Text(authStateText)
                        .foregroundStyle(authStateColor)
                }
                Picker("Poll interval", selection: pollIntervalBinding) {
                    Text("15s").tag(TimeInterval(15))
                    Text("30s").tag(TimeInterval(30))
                    Text("60s").tag(TimeInterval(60))
                }
                LabeledContent("Status") {
                    Text(appState.poller.isPolling ? "Active" : "Stopped")
                }
            }

            Section("General") {
                Toggle("Launch EarlySync at login", isOn: launchAtLoginBinding)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            apiKey = KeychainService.shared.earlyAPIKey ?? ""
        }
    }

    private var pollIntervalBinding: Binding<TimeInterval> {
        Binding(
            get: { appState.poller.pollIntervalSeconds },
            set: { appState.setPollInterval($0) }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLoginEnabled },
            set: { newValue in
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                    launchAtLoginEnabled = newValue
                } catch {
                    // Revert the toggle — SMAppService can fail if e.g. the app
                    // isn't in /Applications or the user denies the login-item prompt.
                    launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
                }
            }
        )
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

// MARK: - LuxaforFocusTab

private struct LuxaforFocusTab: View {
    @EnvironmentObject var appState: AppState
    @State private var luxaforUserId: String = KeychainService.shared.luxaforUserId ?? ""
    @State private var isTestingLight = false

    var body: some View {
        Form {
            Section("Luxafor") {
                Picker("Transport", selection: transportBinding) {
                    ForEach(LuxaforTransport.allCases, id: \.self) { transport in
                        Text(transport.displayName).tag(transport)
                    }
                }

                TextField("Luxafor User ID", text: $luxaforUserId)
                    .onChange(of: luxaforUserId) { newValue in
                        KeychainService.shared.luxaforUserId = newValue.isEmpty ? nil : newValue
                    }

                if appState.mappingConfig.transport == .usb {
                    Text("""
                    USB mode talks directly to a plugged-in Luxafor device — no \
                    User ID needed. Falls back to the webhook automatically if \
                    no device is found.
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Link("Find your User ID at luxafor.co.uk →",
                     destination: URL(string: "https://luxafor.co.uk/webhook-api/")!)
                    .font(.caption)

                Button(isTestingLight ? "Testing…" : "Test Light") {
                    Task { await testLight() }
                }
                .disabled(isTestingLight || (appState.mappingConfig.transport == .webhook && luxaforUserId.isEmpty))
            }

            Section {
                ShortcutsWizardView()
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var transportBinding: Binding<LuxaforTransport> {
        Binding(
            get: { appState.mappingConfig.transport },
            set: { newValue in appState.setTransport(newValue) }
        )
    }

    private func testLight() async {
        isTestingLight = true
        await appState.luxaforClient.setColor(.red)
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        await appState.luxaforClient.off()
        isTestingLight = false
    }
}
