import Foundation
import os

struct ISSSpaceStatus: Equatable {
    let currentIndex: Int   // 1-based
    let spaceCount: Int
}

protocol ISSInvoking {
    /// True once `iss_init()` has returned success.
    var isInitialized: Bool { get }
    /// Tries to (re)initialize the C core. Returns true on success.
    @discardableResult
    func ensureInitialized() -> Bool
    func left()
    func right()
    func index(_ oneBased: Int)
    /// Best-effort current space info; nil if the C core is not initialized
    /// or the query failed.
    func currentSpaceInfo() -> ISSSpaceStatus?
    /// Toggles ISS's dock-swipe override. When enabled, ISS intercepts all
    /// native horizontal dock-swipe gestures (trackpad AND macOS's internal
    /// synthetic swipes used when Cmd+Tab crosses spaces) and replaces them
    /// with instant switches.
    func setSwipeOverride(_ on: Bool)
    /// Tell ISS that macOS changed space by means other than ISS itself —
    /// resets its optimistic space index so bounds checks fall back to live
    /// CGS data. Must be called whenever `NSWorkspace.activeSpaceDidChange`
    /// fires.
    func noteExternalSpaceChange()
}

final class ISSCore: ISSInvoking {
    static let shared = ISSCore()

    private let log = Logger(subsystem: "com.theosardin.instantswitcher", category: "iss")
    private var initialized = false
    private let lock = NSLock()

    init() {
        _ = ensureInitialized()
    }

    deinit {
        if initialized { iss_destroy() }
    }

    var isInitialized: Bool {
        lock.lock(); defer { lock.unlock() }
        return initialized
    }

    @discardableResult
    func ensureInitialized() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if initialized { return true }
        if iss_init() {
            initialized = true
            log.info("iss_init succeeded")
            return true
        }
        log.error("iss_init failed — Accessibility likely not granted")
        return false
    }

    func left() {
        guard ensureInitialized() else { return }
        iss_on_space_changed() // drop optimistic index — bounds check against live CGS
        if !iss_switch(ISSDirectionLeft) { log.debug("iss_switch(left) returned false") }
    }

    func right() {
        guard ensureInitialized() else { return }
        iss_on_space_changed()
        if !iss_switch(ISSDirectionRight) { log.debug("iss_switch(right) returned false") }
    }

    func index(_ oneBased: Int) {
        guard ensureInitialized(), oneBased >= 1 else { return }
        iss_on_space_changed()
        let zeroBased = UInt32(oneBased - 1)
        if !iss_switch_to_index(zeroBased) {
            log.debug("iss_switch_to_index(\(zeroBased)) returned false")
        }
    }

    func setSwipeOverride(_ on: Bool) {
        guard ensureInitialized() else { return }
        iss_set_swipe_override(on)
        log.info("swipe override: \(on ? "on" : "off")")
    }

    func noteExternalSpaceChange() {
        guard isInitialized else { return }
        iss_on_space_changed()
    }

    func currentSpaceInfo() -> ISSSpaceStatus? {
        guard ensureInitialized() else { return nil }
        var info = ISSSpaceInfo(currentIndex: 0, spaceCount: 0)
        let ok = withUnsafeMutablePointer(to: &info) { iss_get_space_info($0) }
        guard ok else { return nil }
        return ISSSpaceStatus(currentIndex: Int(info.currentIndex) + 1,
                              spaceCount: Int(info.spaceCount))
    }
}
