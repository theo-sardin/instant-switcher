import AppKit
import os

protocol SpaceLocating {
    func currentSpaceIndex() -> Int?
    func spaceIndex(forBundleID bundleID: String) -> Int?
    /// Returns a short breadcrumb describing what happened during the lookup,
    /// used for UI diagnostics. Non-protocol-required-by-tests, default no-op.
    func diagnose(forBundleID bundleID: String) -> String
}

extension SpaceLocating {
    func diagnose(forBundleID bundleID: String) -> String { "" }
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

@_silgen_name("CGSCopyWindowsWithOptionsAndTags")
private func CGSCopyWindowsWithOptionsAndTags(
    _ cid: Int32,
    _ owner: UInt32,
    _ spaces: CFArray,
    _ options: Int32,
    _ setTags: UnsafeMutablePointer<UInt64>,
    _ clearTags: UnsafeMutablePointer<UInt64>
) -> CFArray?

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
        return spaceIndex(forPID: app.processIdentifier)
    }

    /// Looks up the space of every layer-0 window owned by `pid`. For each
    /// window, `CGSCopySpacesForWindows` is called individually so we can
    /// distinguish single-space windows from sticky (all-spaces) windows.
    ///
    /// Preference order:
    /// 1. A window whose single space is NOT the currently active space.
    /// 2. A window whose single space IS the currently active space.
    /// 3. Any space we can resolve from any window.
    ///
    /// Sticky windows (multiple spaces returned) are ignored unless nothing
    /// else resolves.
    private func spaceIndex(forPID pid: pid_t) -> Int? {
        let options: CGWindowListOption = []  // .optionAll
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        let ownedWIDs: [UInt32] = list.compactMap { info in
            guard let owner = info[kCGWindowOwnerPID as String] as? pid_t, owner == pid,
                  let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let wid = info[kCGWindowNumber as String] as? UInt32
            else { return nil }
            return wid
        }
        guard !ownedWIDs.isEmpty else { return nil }

        let conn = CGSMainConnectionID()
        let active = CGSGetActiveSpace(conn)
        let activeIdx = spaceIndex(for: active)

        var singleOnCurrent: Int? = nil
        var fallback: Int? = nil

        for wid in ownedWIDs {
            guard let ids = CGSCopySpacesForWindows(conn, 0x7, [wid] as CFArray) as? [UInt64],
                  !ids.isEmpty else { continue }
            if ids.count == 1, let idx = spaceIndex(for: ids[0]) {
                if idx != activeIdx { return idx }  // exactly what we want
                singleOnCurrent = idx
            } else if fallback == nil {
                // sticky / multi-space window — keep as last resort
                for id in ids where id != active {
                    if let idx = spaceIndex(for: id) { fallback = idx; break }
                }
            }
        }
        return singleOnCurrent ?? fallback ?? activeIdx
    }

    func diagnose(forBundleID bundleID: String) -> String {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            return "not-running"
        }
        if let idx = spaceIndex(forPID: app.processIdentifier) { return "space \(idx)" }
        return "no space found"
    }

    // MARK: - Private

    private func frontWindowID(for pid: pid_t) -> UInt32? {
        // NOTE: must NOT use .optionOnScreenOnly — windows on *other* spaces
        // aren't "on screen" and would be filtered out, defeating the whole
        // point of this lookup.
        let options: CGWindowListOption = [.excludeDesktopElements]
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
