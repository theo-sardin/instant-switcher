import SwiftUI

struct SettingsWindow: View {
    var body: some View {
        TabView {
            ShortcutsTab().tabItem { Label("Shortcuts", systemImage: "keyboard") }
            SystemTab().tabItem { Label("System", systemImage: "gearshape") }
            Text("About").tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 620, height: 460)
        .padding(20)
    }
}
