import AppKit
import Carbon.HIToolbox
import Foundation

// MARK: - Apptivate class stand-ins for NSKeyedUnarchiver

@objc(TAKeyCombo) private class TAKeyCombo: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool { true }
    let keyCode: Int
    let mods: Int
    init(keyCode: Int, mods: Int) { self.keyCode = keyCode; self.mods = mods }
    required init?(coder: NSCoder) {
        keyCode = coder.decodeInteger(forKey: "keyCode")
        mods = coder.decodeInteger(forKey: "mods")
    }
    func encode(with coder: NSCoder) {
        coder.encode(keyCode, forKey: "keyCode")
        coder.encode(mods, forKey: "mods")
    }
}

@objc(TAHotkey) private class TAHotkey: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool { true }
    let keyCombo: TAKeyCombo?
    init(keyCombo: TAKeyCombo?) { self.keyCombo = keyCombo }
    required init?(coder: NSCoder) {
        keyCombo = coder.decodeObject(of: TAKeyCombo.self, forKey: "keyCombo")
    }
    func encode(with coder: NSCoder) { coder.encode(keyCombo, forKey: "keyCombo") }
}

@objc(NDAlias) private class NDAlias: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool { true }
    let bookmarkData: Data?
    init(bookmarkData: Data?) { self.bookmarkData = bookmarkData }
    required init?(coder: NSCoder) {
        // NDAlias stores its blob under the synthetic key "$0".
        let raw = coder.decodeObject(of: NSData.self, forKey: "$0") as Data?
        bookmarkData = raw
    }
    func encode(with coder: NSCoder) {
        if let bookmarkData { coder.encode(bookmarkData as NSData, forKey: "$0") }
    }
}

@objc(TAApplicationItem) private class TAApplicationItem: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool { true }
    let fileAlias: NDAlias?
    let hotkeys: [TAHotkey]?
    init(fileAlias: NDAlias?, hotkeys: [TAHotkey]?) {
        self.fileAlias = fileAlias; self.hotkeys = hotkeys
    }
    required init?(coder: NSCoder) {
        fileAlias = coder.decodeObject(of: NDAlias.self, forKey: "fileAlias")
        let arr = coder.decodeObject(of: [NSArray.self, TAHotkey.self], forKey: "hotkeys") as? NSArray
        hotkeys = arr?.compactMap { $0 as? TAHotkey }
    }
    func encode(with coder: NSCoder) {
        coder.encode(fileAlias, forKey: "fileAlias")
        coder.encode(hotkeys as NSArray?, forKey: "hotkeys")
    }
}

// MARK: - Public API

struct ApptivateImportedItem: Equatable {
    let bundleID: String
    let displayName: String
    let iconPath: String
    let carbonKeyCode: Int
    let carbonModifiers: Int
}

enum ApptivateImportError: Error, LocalizedError {
    case missingFile
    case parseFailed(String)
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .missingFile: return "No Apptivate configuration found at ~/Library/Application Support/Apptivate/hotkeys."
        case .parseFailed(let s): return "Couldn't read Apptivate config: \(s)"
        case .emptyResult: return "Apptivate config contained no bindings."
        }
    }
}

enum ApptivateImporter {
    static var configURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Apptivate/hotkeys")
    }

    static var configExists: Bool {
        FileManager.default.fileExists(atPath: configURL.path)
    }

    /// Reads the Apptivate hotkeys file and returns one item per (app, hotkey) pair.
    ///
    /// Uses a hybrid parse: NSKeyedUnarchiver for TAApplicationItem/TAHotkey
    /// (standard keyed coding), plus a raw-bytes regex scan for the embedded
    /// `Applications/X.app` paths (NDAlias's bookmark blob is encoded under
    /// the non-standard "$0" key which the Swift coder APIs can't read
    /// reliably, so we sidestep it).
    static func importAll() throws -> [ApptivateImportedItem] {
        guard configExists else { throw ApptivateImportError.missingFile }
        let data: Data
        do { data = try Data(contentsOf: configURL) }
        catch { throw ApptivateImportError.parseFailed(error.localizedDescription) }

        let items = try decodeItems(data)
        let paths = scanAppPaths(data)

        guard items.count == paths.count else {
            throw ApptivateImportError.parseFailed(
                "decoded \(items.count) items but found \(paths.count) app paths — graph order mismatch"
            )
        }

        var results: [ApptivateImportedItem] = []
        for (item, path) in zip(items, paths) {
            let appURL = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: appURL.path),
                  let bundle = Bundle(url: appURL),
                  let bundleID = bundle.bundleIdentifier
            else { continue }
            let name = (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
                ?? (bundle.infoDictionary?["CFBundleName"] as? String)
                ?? appURL.deletingPathExtension().lastPathComponent
            for hk in item.hotkeys ?? [] {
                guard let combo = hk.keyCombo, combo.keyCode >= 0 else { continue }
                results.append(ApptivateImportedItem(
                    bundleID: bundleID,
                    displayName: name,
                    iconPath: appURL.path,
                    carbonKeyCode: combo.keyCode,
                    carbonModifiers: combo.mods
                ))
            }
        }
        if results.isEmpty { throw ApptivateImportError.emptyResult }
        return results
    }

    private static func decodeItems(_ data: Data) throws -> [TAApplicationItem] {
        let unarchiver: NSKeyedUnarchiver
        do { unarchiver = try NSKeyedUnarchiver(forReadingFrom: data) }
        catch { throw ApptivateImportError.parseFailed(error.localizedDescription) }
        unarchiver.requiresSecureCoding = false
        unarchiver.setClass(TAApplicationItem.self, forClassName: "TAApplicationItem")
        unarchiver.setClass(TAHotkey.self, forClassName: "TAHotkey")
        unarchiver.setClass(TAKeyCombo.self, forClassName: "TAKeyCombo")
        unarchiver.setClass(NDAlias.self, forClassName: "NDAlias")

        guard let root = unarchiver.decodeObject(forKey: "items") as? NSArray else {
            throw ApptivateImportError.parseFailed("top-level 'items' array missing or wrong type")
        }
        return root.compactMap { $0 as? TAApplicationItem }
    }

    /// Walk the raw NSKeyedArchiver `$objects` array, pulling the first `.app`
    /// basename out of every embedded alias blob. Blobs appear in the same
    /// order as the `TAApplicationItem` entries that reference them, which
    /// lets us pair the two lists by index.
    private static func scanAppPaths(_ data: Data) -> [String] {
        guard let top = try? PropertyListSerialization.propertyList(
            from: data, options: [], format: nil
        ) as? [String: Any],
              let objects = top["$objects"] as? [Any] else { return [] }

        let regex = try? NSRegularExpression(pattern: #"[A-Za-z0-9 _.\-]+\.app"#)
        guard let regex else { return [] }

        var paths: [String] = []
        for obj in objects {
            guard let blob = obj as? Data, blob.count > 64,
                  let text = String(data: blob, encoding: .isoLatin1) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            guard let match = regex.firstMatch(in: text, range: range),
                  let r = Range(match.range, in: text) else { continue }
            let name = String(text[r])
            paths.append(resolveAppPath(for: name) ?? "")
        }
        return paths.filter { !$0.isEmpty }
    }

    /// Resolve an app basename (e.g. "Terminal.app") to a full path using
    /// LaunchServices — finds apps in `/Applications`, `/System/Applications`,
    /// user `~/Applications`, Cryptex-signed paths, etc.
    private static func resolveAppPath(for basename: String) -> String? {
        let name = basename.hasSuffix(".app")
            ? String(basename.dropLast(".app".count)) : basename
        if let path = NSWorkspace.shared.fullPath(forApplication: name) {
            return path
        }
        let candidate = "/Applications/\(basename)"
        if FileManager.default.fileExists(atPath: candidate) { return candidate }
        return nil
    }

}
