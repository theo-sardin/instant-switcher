import AppKit
import os

protocol AppActivating {
    func isRunning(bundleID: String) -> Bool
    func activate(bundleID: String)
    func launch(bundleID: String)
}

final class NSWorkspaceAppActivator: AppActivating {
    private let log = Logger(subsystem: "com.theosardin.instantswitcher", category: "activate")

    func isRunning(bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    func activate(bundleID: String) {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            launch(bundleID: bundleID)
            return
        }
        app.activate(options: [.activateIgnoringOtherApps])
    }

    func launch(bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            log.error("No URL for bundleID \(bundleID, privacy: .public)")
            return
        }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: cfg) { _, error in
            if let error { self.log.error("Launch failed: \(error.localizedDescription, privacy: .public)") }
        }
    }
}

enum SystemOverrideAction: Equatable {
    case left, right
    case index(Int)
}

final class ShortcutEngine {
    private let locator: SpaceLocating
    private let core: ISSInvoking
    private let activator: AppActivating
    private let log = Logger(subsystem: "com.theosardin.instantswitcher", category: "hotkey")

    init(locator: SpaceLocating, core: ISSInvoking, activator: AppActivating) {
        self.locator = locator
        self.core = core
        self.activator = activator
    }

    func fire(_ binding: Binding) {
        switch binding {
        case .space(let s):
            core.index(s.spaceIndex)
        case .app(let a):
            fireApp(a)
        }
    }

    func systemOverride(_ action: SystemOverrideAction) {
        switch action {
        case .left:  core.left()
        case .right: core.right()
        case .index(let n): core.index(n)
        }
    }

    /// Jump to the app's space (if found) and activate it, or launch if not running.
    func fireApp(bundleID: String) {
        if activator.isRunning(bundleID: bundleID) {
            if let idx = locator.spaceIndex(forBundleID: bundleID) {
                core.noteExternalSpaceChange()
                core.index(idx)
            } else {
                log.notice("No space found for \(bundleID, privacy: .public); activating directly")
            }
            activator.activate(bundleID: bundleID)
        } else {
            activator.launch(bundleID: bundleID)
        }
    }

    private func fireApp(_ binding: AppBinding) {
        fireApp(bundleID: binding.bundleIdentifier)
    }
}
