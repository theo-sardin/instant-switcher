import SwiftUI

// DEVIATION from plan: Plan uses `SettingsLink` which is macOS 14+.
// Deployment target is macOS 13, so we use NSApp.sendAction with the
// private "showSettingsWindow:" selector instead, which works on macOS 13+.
struct MenuBarView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Button("Settings…") {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(",")
        Divider()
        Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
