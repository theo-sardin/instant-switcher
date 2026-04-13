import SwiftUI

struct SystemTab: View {
    @EnvironmentObject var state: AppState
    @State private var accessibilityTrusted: Bool = Permissions.isAccessibilityTrusted()

    var body: some View {
        Form {
            Section("Override macOS shortcuts") {
                Toggle("Override Ctrl + ← / Ctrl + →", isOn: SwiftUI.Binding(
                    get: { state.config.systemOverrides.arrows },
                    set: { enable($0, kind: .arrows) }
                ))
                Toggle("Override Ctrl + 1 … 9", isOn: SwiftUI.Binding(
                    get: { state.config.systemOverrides.digits },
                    set: { enable($0, kind: .digits) }
                ))

                if (state.config.systemOverrides.arrows || state.config.systemOverrides.digits) && !accessibilityTrusted {
                    banner(
                        title: "Accessibility permission required",
                        message: "Grant InstantSwitcher access in System Settings › Privacy & Security › Accessibility.",
                        buttonLabel: "Open Accessibility Settings",
                        action: { Permissions.openAccessibilitySettings() }
                    )
                }

                if state.config.systemOverrides.arrows || state.config.systemOverrides.digits {
                    banner(
                        title: "Disable the native shortcut",
                        message: "Otherwise macOS still processes it in parallel. Open Keyboard Shortcuts and turn off Mission Control's space shortcuts.",
                        buttonLabel: "Open Keyboard Shortcuts",
                        action: { Permissions.openKeyboardShortcutsSettings() }
                    )
                }
            }
            Section("General") {
                Toggle("Launch at login", isOn: SwiftUI.Binding(
                    get: { state.config.launchAtLogin },
                    set: { state.setLaunchAtLogin($0) }
                ))
            }
        }
        .formStyle(.grouped)
        .onAppear { accessibilityTrusted = Permissions.isAccessibilityTrusted() }
    }

    private enum Kind { case arrows, digits }

    private func enable(_ on: Bool, kind: Kind) {
        if on {
            _ = Permissions.isAccessibilityTrusted(prompt: true)
        }
        accessibilityTrusted = Permissions.isAccessibilityTrusted()
        switch kind {
        case .arrows: state.setOverride(arrows: on)
        case .digits: state.setOverride(digits: on)
        }
    }

    private func banner(title: String, message: String, buttonLabel: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline).bold()
            Text(message).font(.caption).foregroundStyle(.secondary)
            Button(buttonLabel, action: action).controlSize(.small)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.yellow.opacity(0.15)))
    }
}
