import KeyboardShortcuts
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        if !state.core.isInitialized {
            Text("⚠︎ Grant Accessibility for instant switches").foregroundStyle(.yellow)
            Button("Open Accessibility Settings") { Permissions.openAccessibilitySettings() }
            Divider()
        }

        if let info = state.core.currentSpaceInfo() {
            Text("Space \(info.currentIndex) of \(info.spaceCount)").foregroundStyle(.secondary)
            Divider()
        }

        if state.config.bindings.isEmpty {
            Text("No shortcuts configured").foregroundStyle(.secondary)
        } else {
            ForEach(state.config.bindings, id: \.id) { binding in
                Button(label(for: binding)) { state.engine.fire(binding) }
            }
        }

        Divider()

        Toggle("Override Ctrl + Arrows", isOn: SwiftUI.Binding(
            get: { state.config.systemOverrides.arrows },
            set: { state.setOverride(arrows: $0) }
        ))
        Toggle("Override Ctrl + 1…9", isOn: SwiftUI.Binding(
            get: { state.config.systemOverrides.digits },
            set: { state.setOverride(digits: $0) }
        ))

        Divider()

        // DEVIATION from plan: Plan uses `SettingsLink` which requires macOS 14+.
        // Deployment target is macOS 13, so we use the NSApp.sendAction fallback
        // shown in the plan note instead.
        Button("Settings…") {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }.keyboardShortcut(",")
        Button("Quit InstantSwitcher") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }

    private func label(for binding: Binding) -> String {
        switch binding {
        case .app(let b): return b.displayName
        case .space(let b): return b.label.isEmpty ? "Space \(b.spaceIndex)" : b.label
        }
    }
}
