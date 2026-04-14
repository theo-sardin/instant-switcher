import KeyboardShortcuts
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        if !state.coreInitialized {
            Button("Grant Accessibility…") { state.requestAccessibility() }
            Divider()
        } else if let info = state.core.currentSpaceInfo() {
            Button("Space \(info.currentIndex) of \(info.spaceCount)") {}.disabled(true)
            Divider()
        }

        if state.config.bindings.isEmpty {
            Button("No shortcuts configured") {}.disabled(true)
        } else {
            ForEach(state.config.bindings, id: \.id) { binding in
                Button(label(for: binding)) { state.engine.fire(binding) }
                    .globalKeyboardShortcut(.binding(binding.id))
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
        Toggle("Option + Tab Switcher", isOn: SwiftUI.Binding(
            get: { state.config.systemOverrides.altTab },
            set: { state.setOverride(altTab: $0) }
        ))

        Divider()

        Button("Settings…") {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
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
