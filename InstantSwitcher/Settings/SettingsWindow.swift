import SwiftUI

struct SettingsWindow: View {
    var body: some View {
        TabView {
            Text("Shortcuts").tabItem { Label("Shortcuts", systemImage: "keyboard") }
            Text("System").tabItem { Label("System", systemImage: "gearshape") }
            Text("About").tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 620, height: 460)
        .padding(20)
    }
}
