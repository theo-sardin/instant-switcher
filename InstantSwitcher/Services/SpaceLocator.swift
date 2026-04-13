import AppKit
import os

protocol SpaceLocating {
    func currentSpaceIndex() -> Int?
    func spaceIndex(forBundleID bundleID: String) -> Int?
}

// Private CGS symbols. Undocumented; may change across macOS versions.
// Mirrors the shape used by Yabai/AeroSpace/Hammerspoon.
@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> Int32

@_silgen_name("CGSCopyManagedDisplaySpaces")
private func CGSCopyManagedDisplaySpaces(_ connection: Int32) -> CFArray?

@_silgen_name("CGSCopySpacesForWindows")
private func CGSCopySpacesForWindows(_ connection: Int32, _ mask: Int32, _ windowIDs: CFArray) -> CFArray?

@_silgen_name("CGSGetActiveSpace")
private func CGSGetActiveSpace(_ connection: Int32) -> UInt64

final class SpaceLocator: SpaceLocating {
    private let log = Logger(subsystem: "com.theosardin.instantswitcher", category: "cgs")

    func currentSpaceIndex() -> Int? {
        let conn = CGSMainConnectionID()
        let activeID = CGSGetActiveSpace(conn)
        return spaceIndex(for: activeID)
    }

    func spaceIndex(forBundleID bundleID: String) -> Int? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            return nil
        }
        guard let windowID = frontWindowID(for: app.processIdentifier) else {
            return nil
        }
        let conn = CGSMainConnectionID()
        let mask: Int32 = 0x7
        guard let spaces = CGSCopySpacesForWindows(conn, mask, [windowID] as CFArray) as? [UInt64],
              let first = spaces.first else {
            return nil
        }
        return spaceIndex(for: first)
    }

    // MARK: - Private

    private func frontWindowID(for pid: pid_t) -> UInt32? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        for info in list {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID == pid,
                  let id = info[kCGWindowNumber as String] as? UInt32,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0
            else { continue }
            return id
        }
        return nil
    }

    private func spaceIndex(for spaceID: UInt64) -> Int? {
        let conn = CGSMainConnectionID()
        guard let displays = CGSCopyManagedDisplaySpaces(conn) as? [[String: Any]] else {
            log.error("CGSCopyManagedDisplaySpaces returned nil")
            return nil
        }
        var index = 0
        for display in displays {
            guard let spaces = display["Spaces"] as? [[String: Any]] else { continue }
            for space in spaces {
                index += 1
                if let id = space["id64"] as? UInt64, id == spaceID {
                    return index
                }
            }
        }
        return nil
    }
}
