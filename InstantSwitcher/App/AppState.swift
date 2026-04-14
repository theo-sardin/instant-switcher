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
    let windowSwitcher: WindowSwitcher
    private let store: ConfigStore
    private var spaceChangeObserver: NSObjectProtocol?
    private var axWatchdog: Timer?

    init(store: ConfigStore = ConfigStore(),
         core: ISSInvoking = ISSCore.shared,
         locator: SpaceLocating = SpaceLocator(),
         activator: AppActivating = NSWorkspaceAppActivator()) {
        self.store = store
        self.core = core
        self.locator = locator
        self.engine = ShortcutEngine(locator: locator, core: core, activator: activator)
        self.systemOverride = SystemOverride(engine: engine)
        self.windowSwitcher = WindowSwitcher(engine: engine)
        self.systemOverride.setWindowSwitcher(windowSwitcher)
        self.config = store.load()
        self.coreInitialized = core.isInitialized
        registerAllBindings()
        applyOverrideState()
        observeSpaceChanges()
        startAccessibilityWatchdog()
    }

    deinit {
        axWatchdog?.invalidate()
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

    // MARK: - Accessibility watchdog

    /// Polls Accessibility status every 2s. If AX is revoked while event taps
    /// are live, tears down both the ISS C core tap and SystemOverride tap
    /// immediately — preventing the "frozen Mac" bug where active filter taps
    /// silently swallow all input after permission loss.
    private func startAccessibilityWatchdog() {
        axWatchdog = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.coreInitialized else { return }
                if !Permissions.isAccessibilityTrusted() {
                    self.core.destroy()
                    self.systemOverride.arrowsEnabled = false
                    self.systemOverride.digitsEnabled = false
                    self.systemOverride.altTabEnabled = false
                    self.coreInitialized = false
                }
            }
        }
    }

    /// Silent re-check: try to init ISS if not yet done, apply overrides.
    /// Called on every menu open — no system prompt.
    func refreshPermissions() {
        let wasInitialized = coreInitialized
        coreInitialized = core.ensureInitialized()
        if coreInitialized && !wasInitialized {
            // First successful init this session — tear down zombie tap
            // from startup (created before AX was granted) and recreate.
            // Same code path as user toggling off/on.
            systemOverride.arrowsEnabled = false
            systemOverride.digitsEnabled = false
        }
        applyOverrideState()
    }

    /// Explicit user action: trigger the macOS Accessibility prompt, then
    /// poll until the user actually grants it (they have to leave the app,
    /// toggle the switch in System Settings, and come back).
    func requestAccessibility() {
        _ = Permissions.isAccessibilityTrusted(prompt: true)
        refreshPermissions() // instant retry in case already granted
        guard !coreInitialized else { return }
        // Poll every 2s for up to 2 minutes
        Task { @MainActor in
            for _ in 0..<60 {
                try? await Task.sleep(for: .seconds(2))
                if Permissions.isAccessibilityTrusted() {
                    refreshPermissions()
                    if coreInitialized { return }
                }
            }
        }
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

    func setOverride(altTab: Bool) {
        config.systemOverrides.altTab = altTab
        persist()
        applyOverrideState()
    }

    private func applyOverrideState() {
        systemOverride.arrowsEnabled = config.systemOverrides.arrows
        systemOverride.digitsEnabled = config.systemOverrides.digits
        systemOverride.altTabEnabled = coreInitialized && config.systemOverrides.altTab
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
