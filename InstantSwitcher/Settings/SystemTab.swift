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
                Toggle("Instant trackpad swipes between spaces", isOn: SwiftUI.Binding(
                    get: { state.config.systemOverrides.swipe },
                    set: { enable($0, kind: .swipe) }
                ))
                Toggle("Option + Tab instant app switcher", isOn: SwiftUI.Binding(
                    get: { state.config.systemOverrides.altTab },
                    set: { enable($0, kind: .altTab) }
                ))

                if !accessibilityTrusted {
                    banner(
                        title: "Accessibility permission required",
                        message: "Grant InstantSwitcher access in System Settings › Privacy & Security › Accessibility.",
                        buttonLabel: "Open Accessibility Settings",
                        action: { Permissions.openAccessibilitySettings() }
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

    private enum Kind { case arrows, digits, swipe, altTab }

    private func enable(_ on: Bool, kind: Kind) {
        if on {
            _ = Permissions.isAccessibilityTrusted(prompt: true)
        }
        accessibilityTrusted = Permissions.isAccessibilityTrusted()
        switch kind {
        case .arrows: state.setOverride(arrows: on)
        case .digits: state.setOverride(digits: on)
        case .swipe:  state.setOverride(swipe: on)
        case .altTab: state.setOverride(altTab: on)
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
