import AppKit
import os
import SwiftUI

struct SwitcherApp {
    let bundleID: String
    let name: String
    let icon: NSImage
}

@MainActor
final class WindowSwitcher {
    private let engine: ShortcutEngine
    private let log = Logger(subsystem: "com.theosardin.instantswitcher", category: "switcher")

    private(set) var isShowing = false
    private var mruBundleIDs: [String] = []
    private var activationObserver: NSObjectProtocol?
    private var terminationObserver: NSObjectProtocol?
    private var panel: NSPanel?
    private var hostingView: NSHostingView<SwitcherHUDView>?
    private var selectedIndex = 0
    private var currentApps: [SwitcherApp] = []

    init(engine: ShortcutEngine) {
        self.engine = engine
        seedMRU()
        observeActivations()
        observeTerminations()
    }

    deinit {
        let nc = NSWorkspace.shared.notificationCenter
        if let activationObserver { nc.removeObserver(activationObserver) }
        if let terminationObserver { nc.removeObserver(terminationObserver) }
    }

    // MARK: - MRU tracking

    private func seedMRU() {
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
        if let front = NSWorkspace.shared.frontmostApplication,
           let bid = front.bundleIdentifier {
            mruBundleIDs = [bid]
            for app in running where app.bundleIdentifier != bid {
                if let id = app.bundleIdentifier { mruBundleIDs.append(id) }
            }
        } else {
            mruBundleIDs = running.compactMap(\.bundleIdentifier)
        }
    }

    private func observeActivations() {
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self, !self.isShowing else { return }
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      let bundleID = app.bundleIdentifier,
                      bundleID != Bundle.main.bundleIdentifier else { return }
                self.mruBundleIDs.removeAll { $0 == bundleID }
                self.mruBundleIDs.insert(bundleID, at: 0)
            }
        }
    }

    private func observeTerminations() {
        terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      let bundleID = app.bundleIdentifier else { return }
                self.mruBundleIDs.removeAll { $0 == bundleID }
            }
        }
    }

    // MARK: - Show / cycle / commit

    func showOrAdvance() {
        if isShowing {
            guard !currentApps.isEmpty else { return }
            selectedIndex = (selectedIndex + 1) % currentApps.count
            updateHUD()
        } else {
            show()
        }
    }

    func retreat() {
        guard isShowing, !currentApps.isEmpty else { return }
        selectedIndex = (selectedIndex - 1 + currentApps.count) % currentApps.count
        updateHUD()
    }

    func select(index: Int) {
        guard isShowing, index >= 0, index < currentApps.count else { return }
        selectedIndex = index
        commit()
    }

    func commit() {
        guard isShowing, selectedIndex < currentApps.count else {
            dismiss()
            return
        }
        let app = currentApps[selectedIndex]
        dismiss()
        unminimizeWindows(bundleID: app.bundleID)
        engine.fireApp(bundleID: app.bundleID)
    }

    func dismiss() {
        isShowing = false
        selectedIndex = 0
        currentApps = []
        panel?.orderOut(nil)
        hostingView = nil
    }

    // MARK: - Unminimize

    private func unminimizeWindows(bundleID: String) {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else { return }
        for window in windows {
            var minimizedRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedRef) == .success,
               let minimized = minimizedRef as? Bool, minimized {
                AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, false as CFTypeRef)
            }
        }
    }

    // MARK: - Panel

    private func show() {
        currentApps = buildAppList()
        guard currentApps.count > 1 else { return }
        selectedIndex = 1
        isShowing = true
        showPanel()
    }

    private func buildAppList() -> [SwitcherApp] {
        // Find PIDs that own at least one real layer-0 window:
        // - On-screen windows always count (visible right now).
        // - Off-screen windows (minimized, other spaces) count only if large
        //   enough (>= 400×300) to exclude hidden popups and menu bar frames.
        let pidsWithWindows: Set<pid_t> = {
            guard let list = CGWindowListCopyWindowInfo([], kCGNullWindowID) as? [[String: Any]] else { return [] }
            var pids = Set<pid_t>()
            for info in list {
                guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                      let pid = info[kCGWindowOwnerPID as String] as? pid_t
                else { continue }
                if info[kCGWindowIsOnscreen as String] as? Bool == true {
                    pids.insert(pid)
                } else if let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                          let bounds = CGRect(dictionaryRepresentation: boundsDict),
                          bounds.width >= 400, bounds.height >= 300 {
                    pids.insert(pid)
                }
            }
            return pids
        }()

        return mruBundleIDs.compactMap { bid in
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bid).first,
                  app.activationPolicy == .regular,
                  pidsWithWindows.contains(app.processIdentifier) else { return nil }
            return SwitcherApp(
                bundleID: bid,
                name: app.localizedName ?? bid,
                icon: app.icon ?? NSImage(named: NSImage.applicationIconName)!
            )
        }
    }

    private func makeHUDView() -> SwitcherHUDView {
        SwitcherHUDView(apps: currentApps, selectedIndex: selectedIndex) { [weak self] index in
            self?.select(index: index)
        }
    }

    private func showPanel() {
        if panel == nil {
            let p = NSPanel(
                contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            p.isFloatingPanel = true
            p.level = .screenSaver
            p.backgroundColor = .clear
            p.isOpaque = false
            p.hasShadow = true
            p.acceptsMouseMovedEvents = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel = p
        }
        if hostingView == nil {
            let hv = NSHostingView(rootView: makeHUDView())
            hostingView = hv
            panel?.contentView = hv
        } else {
            hostingView?.rootView = makeHUDView()
        }
        let size = hostingView?.fittingSize ?? .zero
        panel?.setContentSize(size)
        centerPanel()
        panel?.orderFrontRegardless()
    }

    private func updateHUD() {
        hostingView?.rootView = makeHUDView()
    }

    private func centerPanel() {
        guard let panel, let screen = NSScreen.main else { return }
        let origin = NSPoint(
            x: screen.frame.midX - panel.frame.width / 2,
            y: screen.frame.midY - panel.frame.height / 2
        )
        panel.setFrameOrigin(origin)
    }
}

// MARK: - SwiftUI HUD

struct SwitcherHUDView: View {
    let apps: [SwitcherApp]
    let selectedIndex: Int
    var onSelect: ((Int) -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(apps.enumerated()), id: \.offset) { index, app in
                VStack(spacing: 4) {
                    Image(nsImage: app.icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 56, height: 56)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(index == selectedIndex ? Color.white.opacity(0.2) : Color.clear)
                        )
                    Text(app.name)
                        .font(.system(size: 11))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .frame(width: 72)
                }
                .onTapGesture { onSelect?(index) }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
    }
}
