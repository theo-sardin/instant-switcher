import SwiftUI

@main
struct InstantSwitcherApp: App {
    var body: some Scene {
        MenuBarExtra("InstantSwitcher", systemImage: "square.grid.3x3.square") {
            Text("InstantSwitcher running")
            Divider()
            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
