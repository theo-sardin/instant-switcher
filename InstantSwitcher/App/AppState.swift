import AppKit
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
    private var spaceChangeObserver: NSObjectProtocol?

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
        observeSpaceChanges()
    }

    deinit {
        if let spaceChangeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceChangeObserver)
        }
    }

    /// Piggyback on macOS app activations (Cmd+Tab, Dock click, etc.): when the
    /// activated app's frontmost window lives on a different space, pre-fire
    /// an instant ISS jump so the native animated swipe never starts (or at
    /// worst is cut short).
    ///
    /// Only active while the swipe override is enabled — we treat that toggle
    /// as "make everything instant".
    /// Keep ISS's optimistic space index honest when macOS changes space by
    /// any means ISS didn't fire itself (trackpad gestures we didn't
    /// intercept, Mission Control, returning to leftmost desktop, etc.).
    /// Without this, ISS's bounds check can refuse to move after the active
    /// space drifts out from under it.
    private func observeSpaceChanges() {
        spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.core.noteExternalSpaceChange() }
        }
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

    // MARK: - Import from Apptivate

    /// Bulk-add bindings from Apptivate, skipping any whose bundle ID already
    /// exists in the current config. Returns the number of bindings added.
    @discardableResult
    func importFromApptivate(_ items: [ApptivateImportedItem]) -> Int {
        let existingIDs = Set(config.bindings.compactMap { b -> String? in
            if case .app(let a) = b { return a.bundleIdentifier }
            return nil
        })
        var added = 0
        for item in items where !existingIDs.contains(item.bundleID) {
            let binding = AppBinding(
                id: UUID(),
                bundleIdentifier: item.bundleID,
                displayName: item.displayName,
                iconPath: item.iconPath
            )
            config.bindings.append(.app(binding))
            registerBinding(.app(binding))
            let shortcut = KeyboardShortcuts.Shortcut(
                carbonKeyCode: item.carbonKeyCode,
                carbonModifiers: item.carbonModifiers
            )
            KeyboardShortcuts.setShortcut(shortcut, for: .binding(binding.id))
            added += 1
        }
        if added > 0 { persist() }
        return added
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

    func setOverride(swipe: Bool) {
        config.systemOverrides.swipe = swipe
        persist()
        applyOverrideState()
    }

    private func applyOverrideState() {
        systemOverride.arrowsEnabled = config.systemOverrides.arrows
        systemOverride.digitsEnabled = config.systemOverrides.digits
        core.setSwipeOverride(config.systemOverrides.swipe)
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
