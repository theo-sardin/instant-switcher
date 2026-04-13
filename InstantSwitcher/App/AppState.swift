import Foundation
import KeyboardShortcuts
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var config: Config
    @Published var coreInitialized: Bool
    let engine: ShortcutEngine
    let core: ISSInvoking
    let locator: SpaceLocating
    let systemOverride: SystemOverride
    private let store: ConfigStore

    init(store: ConfigStore = ConfigStore(),
         core: ISSInvoking = ISSCore.shared,
         locator: SpaceLocating = SpaceLocator(),
         activator: AppActivating = NSWorkspaceAppActivator()) {
        self.store = store
        self.core = core
        self.locator = locator
        self.engine = ShortcutEngine(locator: locator, core: core, activator: activator)
        self.systemOverride = SystemOverride(engine: engine)
        self.config = store.load()
        self.coreInitialized = core.isInitialized
        registerAllBindings()
        applyOverrideState()
    }

    /// Ask macOS to prompt for Accessibility (identifying THIS binary to TCC),
    /// then retry `iss_init()` and reinstall the override event tap.
    func refreshPermissions() {
        // Triggers the native system prompt if the app isn't already trusted —
        // this is the only reliable way to register the running binary's
        // identity with TCC.
        _ = Permissions.isAccessibilityTrusted(prompt: true)
        coreInitialized = core.ensureInitialized()
        applyOverrideState()
    }

    // MARK: - Binding CRUD

    func addAppBinding(bundleID: String, displayName: String, iconPath: String?) {
        let b = AppBinding(id: UUID(), bundleIdentifier: bundleID, displayName: displayName, iconPath: iconPath)
        config.bindings.append(.app(b))
        registerBinding(.app(b))
        persist()
    }

    func addSpaceBinding(spaceIndex: Int, label: String) {
        let b = SpaceBinding(id: UUID(), spaceIndex: spaceIndex, label: label)
        config.bindings.append(.space(b))
        registerBinding(.space(b))
        persist()
    }

    func deleteBinding(id: UUID) {
        KeyboardShortcuts.reset(.binding(id))
        config.bindings.removeAll { $0.id == id }
        persist()
    }

    func moveBinding(fromOffsets src: IndexSet, toOffset dst: Int) {
        config.bindings.move(fromOffsets: src, toOffset: dst)
        persist()
    }

    func updateSpaceBinding(id: UUID, spaceIndex: Int, label: String) {
        guard let i = config.bindings.firstIndex(where: { $0.id == id }) else { return }
        if case .space = config.bindings[i] {
            config.bindings[i] = .space(SpaceBinding(id: id, spaceIndex: spaceIndex, label: label))
            persist()
        }
    }

    // MARK: - System overrides

    func setOverride(arrows: Bool) {
        config.systemOverrides.arrows = arrows
        persist()
        applyOverrideState()
    }

    func setOverride(digits: Bool) {
        config.systemOverrides.digits = digits
        persist()
        applyOverrideState()
    }

    private func applyOverrideState() {
        systemOverride.arrowsEnabled = config.systemOverrides.arrows
        systemOverride.digitsEnabled = config.systemOverrides.digits
    }

    // MARK: - Launch at login

    func setLaunchAtLogin(_ on: Bool) {
        do {
            try LaunchAtLogin.set(on)
            config.launchAtLogin = on
            persist()
        } catch {
            NSLog("LaunchAtLogin toggle failed: \(error)")
        }
    }

    // MARK: - Registration

    private func registerAllBindings() {
        for binding in config.bindings {
            registerBinding(binding)
        }
    }

    private func registerBinding(_ binding: Binding) {
        let engine = self.engine
        KeyboardShortcuts.onKeyDown(for: .binding(binding.id)) { [binding, engine] in
            engine.fire(binding)
        }
    }

    private func persist() {
        do { try store.save(config) }
        catch { NSLog("Persist failed: \(error)") }
    }
}
