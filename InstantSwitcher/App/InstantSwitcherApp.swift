import SwiftUI

@main
struct InstantSwitcherApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra("InstantSwitcher", systemImage: "square.grid.3x3.square") {
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
