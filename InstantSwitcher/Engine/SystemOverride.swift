import CoreGraphics
import Foundation
import os

// NOTE on deinit + @MainActor isolation:
// This class is @MainActor. Swift does not allow calling actor-isolated methods
// from a `deinit` (which is nonisolated by default). We solve this by making
// `teardown()` nonisolated and using `MainActor.assumeIsolated { }` inside it,
// which is safe because deinit of a @MainActor object is only ever reached when
// the main actor is already the executor at that point in the object's lifetime.
@MainActor
final class SystemOverride {
    private let engine: ShortcutEngine
    private let log = Logger(subsystem: "com.theosardin.instantswitcher", category: "override")

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var arrowsEnabled: Bool = false { didSet { reconfigure() } }
    var digitsEnabled: Bool = false { didSet { reconfigure() } }


    init(engine: ShortcutEngine) {
        self.engine = engine
    }

    nonisolated deinit { teardown() }

    private func reconfigure() {
        if arrowsEnabled || digitsEnabled {
            ensureTap()
        } else {
            teardown()
        }
    }

    private func ensureTap() {
        if tap != nil { return }
        let mask = (1 << CGEventType.keyDown.rawValue)
        let opaqueSelf = Unmanaged.passUnretained(self).toOpaque()
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: Self.callback,
            userInfo: opaqueSelf
        ) else {
            log.error("Failed to create event tap (Accessibility not granted?)")
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        self.tap = eventTap
        self.runLoopSource = source
    }

    nonisolated private func teardown() {
        MainActor.assumeIsolated {
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
            if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
            tap = nil
            runLoopSource = nil
        }
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }

        let flags = event.flags
        let isControl = flags.contains(.maskControl)
        let others = flags.subtracting([.maskControl])
        let noOtherMods = !others.contains(.maskCommand)
            && !others.contains(.maskAlternate)
            && !others.contains(.maskShift)

        guard isControl, noOtherMods else { return Unmanaged.passUnretained(event) }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if arrowsEnabled {
            if keyCode == 123 { engine.systemOverride(.left);  return nil }
            if keyCode == 124 { engine.systemOverride(.right); return nil }
        }
        if digitsEnabled {
            if let n = digitIndex(for: keyCode) {
                engine.systemOverride(.index(n))
                return nil
            }
        }
        return Unmanaged.passUnretained(event)
    }

    private func digitIndex(for keyCode: Int64) -> Int? {
        switch keyCode {
        case 18: return 1
        case 19: return 2
        case 20: return 3
        case 21: return 4
        case 23: return 5
        case 22: return 6
        case 26: return 7
        case 28: return 8
        case 25: return 9
        default: return nil
        }
    }

    private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let me = Unmanaged<SystemOverride>.fromOpaque(userInfo).takeUnretainedValue()
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = me.tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        return MainActor.assumeIsolated {
            me.handle(type: type, event: event)
        }
    }
}
