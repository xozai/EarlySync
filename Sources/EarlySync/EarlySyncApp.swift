import SwiftUI

// MARK: - App Entry Point

@main
struct EarlySyncApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        // Menu bar app — no main window, no Dock icon (set LSUIElement=YES in Info.plist)
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            Image(nsImage: appState.menuBarImage)
        }
        .menuBarExtraStyle(.window)

        // Preferences window
        Settings {
            PreferencesView()
                .environmentObject(appState)
        }
    }
}
