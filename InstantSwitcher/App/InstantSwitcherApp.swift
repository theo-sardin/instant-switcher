import SwiftUI

@main
struct InstantSwitcherApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra("InstantSwitcher", systemImage: "rectangle.righthalf.filled") {
            MenuBarView()
                .environmentObject(state)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsWindow()
                .environmentObject(state)
        }
    }
}
