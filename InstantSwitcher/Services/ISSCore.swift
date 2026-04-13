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
        if !iss_switch(ISSDirectionLeft) { log.debug("iss_switch(left) returned false") }
    }

    func right() {
        guard ensureInitialized() else { return }
        if !iss_switch(ISSDirectionRight) { log.debug("iss_switch(right) returned false") }
    }

    func index(_ oneBased: Int) {
        guard ensureInitialized(), oneBased >= 1 else { return }
        let zeroBased = UInt32(oneBased - 1)
        if !iss_switch_to_index(zeroBased) {
            log.debug("iss_switch_to_index(\(zeroBased)) returned false")
        }
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
