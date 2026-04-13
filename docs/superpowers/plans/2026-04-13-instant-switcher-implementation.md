# InstantSwitcher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a self-contained macOS menu-bar app (`InstantSwitcher.app`) that vendors the MIT-licensed core of [InstantSpaceSwitcher](https://github.com/jurplel/InstantSpaceSwitcher) and ships as a single `.dmg`. Provides global hotkeys for (1) focusing a specific app on its current space with no animation, (2) jumping to a specific space, and (3) overriding macOS's native Ctrl+Arrows / Ctrl+1..9 space shortcuts.

**Architecture:** SwiftUI menu-bar app with `MenuBarExtra` + `Settings` scenes. Upstream ISS C core (`ISS.c`, `ISS.h`) vendored under `Vendor/InstantSpaceSwitcher/`, compiled into the app target via xcodegen, accessed from Swift through a bridging header. Business logic split into `ShortcutEngine` (dispatches hotkey actions), `SpaceLocator` (private CGS APIs for per-app space lookup), `ISSCore` (Swift wrapper over the vendored C library), and `SystemOverride` (`CGEventTap` for native-shortcut interception). Config persisted as JSON.

**Tech Stack:** Swift 5.9+, SwiftUI, macOS 13+, C (vendored upstream), [`KeyboardShortcuts`](https://github.com/sindresorhus/KeyboardShortcuts) SPM package, private CoreGraphics/SkyLight symbols, `SMAppService`, XCTest, [`xcodegen`](https://github.com/yonaskolb/XcodeGen) for project generation.

**Upstream pin:** `jurplel/InstantSpaceSwitcher@1d06568790050531935760be17b65e4d3727c00a` (2026-04-12). MIT License. Attribution preserved.

---

## File structure

```
instant-switcher/
├── project.yml
├── .gitignore
├── README.md
├── scripts/
│   └── build-dmg.sh
├── Vendor/
│   └── InstantSpaceSwitcher/
│       ├── LICENSE                                # upstream, verbatim
│       ├── UPSTREAM.md                            # origin URL + pinned commit + list of files taken
│       └── Sources/ISS/
│           ├── ISS.c                              # verbatim from upstream
│           └── include/ISS.h                      # verbatim from upstream
├── InstantSwitcher/
│   ├── App/
│   │   ├── InstantSwitcherApp.swift
│   │   ├── AppState.swift
│   │   └── MenuBarView.swift
│   ├── Settings/
│   │   ├── SettingsWindow.swift
│   │   ├── ShortcutsTab.swift
│   │   ├── SystemTab.swift
│   │   ├── AboutTab.swift
│   │   └── AppPickerView.swift
│   ├── Engine/
│   │   ├── ShortcutEngine.swift
│   │   └── SystemOverride.swift
│   ├── Services/
│   │   ├── ISSCore.swift
│   │   ├── SpaceLocator.swift
│   │   ├── ConfigStore.swift
│   │   ├── LaunchAtLogin.swift
│   │   ├── ShortcutNames.swift
│   │   └── Permissions.swift
│   ├── Models/
│   │   ├── Config.swift
│   │   └── Binding.swift
│   ├── Bridging/
│   │   └── InstantSwitcher-Bridging-Header.h
│   └── Resources/
│       ├── Assets.xcassets
│       ├── Info.plist
│       └── InstantSwitcher.entitlements
└── InstantSwitcherTests/
    ├── Fakes/
    │   ├── FakeSpaceLocator.swift
    │   ├── FakeISSCore.swift
    │   └── FakeAppActivator.swift
    ├── BindingCodableTests.swift
    ├── ConfigStoreTests.swift
    └── ShortcutEngineTests.swift
```

---

## Task 1: Project scaffold with xcodegen, vendor upstream C core

**Files:**
- Create: `project.yml`
- Create: `Vendor/InstantSpaceSwitcher/LICENSE`
- Create: `Vendor/InstantSpaceSwitcher/UPSTREAM.md`
- Create: `Vendor/InstantSpaceSwitcher/Sources/ISS/ISS.c`
- Create: `Vendor/InstantSpaceSwitcher/Sources/ISS/include/ISS.h`
- Create: `InstantSwitcher/Bridging/InstantSwitcher-Bridging-Header.h`
- Create: `InstantSwitcher/Resources/Info.plist`
- Create: `InstantSwitcher/Resources/InstantSwitcher.entitlements`
- Create: `InstantSwitcher/Resources/Assets.xcassets/Contents.json`
- Create: `InstantSwitcher/App/InstantSwitcherApp.swift`
- Modify: `.gitignore`

- [ ] **Step 1: Fetch upstream at the pinned commit**

```bash
git clone --depth 1 https://github.com/jurplel/InstantSpaceSwitcher.git /tmp/iss-upstream
( cd /tmp/iss-upstream && git fetch --depth 1 origin 1d06568790050531935760be17b65e4d3727c00a && git checkout 1d06568790050531935760be17b65e4d3727c00a )
```

If the `git fetch` by SHA fails (GitHub requires `uploadpack.allowReachableSHA1InWant`), fall back to cloning without `--depth`:
```bash
rm -rf /tmp/iss-upstream
git clone https://github.com/jurplel/InstantSpaceSwitcher.git /tmp/iss-upstream
( cd /tmp/iss-upstream && git checkout 1d06568790050531935760be17b65e4d3727c00a )
```

- [ ] **Step 2: Copy vendored files**

```bash
mkdir -p Vendor/InstantSpaceSwitcher/Sources/ISS/include
cp /tmp/iss-upstream/LICENSE Vendor/InstantSpaceSwitcher/LICENSE
cp /tmp/iss-upstream/Sources/ISS/ISS.c Vendor/InstantSpaceSwitcher/Sources/ISS/ISS.c
cp /tmp/iss-upstream/Sources/ISS/include/ISS.h Vendor/InstantSpaceSwitcher/Sources/ISS/include/ISS.h
```

- [ ] **Step 3: Write `Vendor/InstantSpaceSwitcher/UPSTREAM.md`**

```markdown
# Vendored: InstantSpaceSwitcher (core)

**Upstream:** https://github.com/jurplel/InstantSpaceSwitcher
**License:** MIT (see `LICENSE`)
**Pinned commit:** `1d06568790050531935760be17b65e4d3727c00a` (2026-04-12)

## Files taken (verbatim)

- `Sources/ISS/ISS.c`
- `Sources/ISS/include/ISS.h`
- `LICENSE`

Upstream's Swift/AppKit app code, tests, and build scripts are intentionally
not vendored — we provide our own SwiftUI UI.

## Updating

To refresh to a new upstream commit:

1. `git clone https://github.com/jurplel/InstantSpaceSwitcher.git /tmp/iss-upstream`
2. `cd /tmp/iss-upstream && git checkout <new-sha>`
3. `cp` the three files above back into place.
4. Update the pinned commit in this file and in `docs/superpowers/plans/2026-04-13-instant-switcher-implementation.md`.
5. Build and run the smoke test.
```

- [ ] **Step 4: Write `.gitignore` additions**

Append to `.gitignore`:
```
InstantSwitcher.xcodeproj
*.xcworkspace
.swiftpm/
build/
DerivedData/
*.xcuserstate
```

- [ ] **Step 5: Write `project.yml`**

```yaml
name: InstantSwitcher
options:
  deploymentTarget:
    macOS: "13.0"
  createIntermediateGroups: true
settings:
  base:
    SWIFT_VERSION: "5.9"
    MACOSX_DEPLOYMENT_TARGET: "13.0"
    PRODUCT_BUNDLE_IDENTIFIER: com.theosardin.instantswitcher
    MARKETING_VERSION: "0.1.0"
    CURRENT_PROJECT_VERSION: "1"
    CODE_SIGN_STYLE: Automatic
    CODE_SIGN_IDENTITY: "-"
    CLANG_ENABLE_MODULES: YES
packages:
  KeyboardShortcuts:
    url: https://github.com/sindresorhus/KeyboardShortcuts
    from: "2.2.0"
targets:
  InstantSwitcher:
    type: application
    platform: macOS
    sources:
      - path: InstantSwitcher
      - path: Vendor/InstantSpaceSwitcher/Sources/ISS
    resources:
      - path: InstantSwitcher/Resources/Assets.xcassets
      - path: Vendor/InstantSpaceSwitcher/LICENSE
    info:
      path: InstantSwitcher/Resources/Info.plist
      properties:
        LSUIElement: true
        CFBundleDisplayName: InstantSwitcher
        NSHumanReadableCopyright: "© 2026. Includes InstantSpaceSwitcher (MIT) by jurplel."
    entitlements:
      path: InstantSwitcher/Resources/InstantSwitcher.entitlements
      properties:
        com.apple.security.app-sandbox: false
    settings:
      base:
        SWIFT_OBJC_BRIDGING_HEADER: InstantSwitcher/Bridging/InstantSwitcher-Bridging-Header.h
        HEADER_SEARCH_PATHS:
          - $(SRCROOT)/Vendor/InstantSpaceSwitcher/Sources/ISS/include
        OTHER_LDFLAGS:
          - -framework
          - ApplicationServices
          - -framework
          - IOKit
    dependencies:
      - package: KeyboardShortcuts
  InstantSwitcherTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: InstantSwitcherTests
    dependencies:
      - target: InstantSwitcher
```

- [ ] **Step 6: Create bridging header**

`InstantSwitcher/Bridging/InstantSwitcher-Bridging-Header.h`:
```c
#ifndef InstantSwitcher_Bridging_Header_h
#define InstantSwitcher_Bridging_Header_h

#import "ISS.h"

#endif
```

- [ ] **Step 7: Create empty `Info.plist`, entitlements, and asset catalog**

`InstantSwitcher/Resources/Info.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict/></plist>
```

`InstantSwitcher/Resources/InstantSwitcher.entitlements`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict/></plist>
```

`InstantSwitcher/Resources/Assets.xcassets/Contents.json`:
```json
{ "info": { "author": "xcode", "version": 1 } }
```

- [ ] **Step 8: Create minimal app entry point**

`InstantSwitcher/App/InstantSwitcherApp.swift`:
```swift
import SwiftUI

@main
struct InstantSwitcherApp: App {
    var body: some Scene {
        MenuBarExtra("InstantSwitcher", systemImage: "square.grid.3x3.square") {
            Text("InstantSwitcher running")
            Divider()
            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
```

- [ ] **Step 9: Generate and build**

```bash
xcodegen generate
xcodebuild -scheme InstantSwitcher -configuration Debug -derivedDataPath build build 2>&1 | tail -30
```
Expected: `** BUILD SUCCEEDED **`. The vendored C sources must compile and link alongside the Swift code. If clang reports missing private CGS symbols at link time, they're declared weak in `ISS.c` — verify with `nm build/Build/Products/Debug/InstantSwitcher.app/Contents/MacOS/InstantSwitcher | grep CGS`.

- [ ] **Step 10: Commit the vendor + scaffold separately for a clean log**

```bash
git add Vendor
git commit -m "Vendor InstantSpaceSwitcher core (MIT, pin 1d06568)"

git add .gitignore project.yml InstantSwitcher
git commit -m "Scaffold SwiftUI menu-bar app target with C bridge"
```

---

## Task 2: Data models (`Config`, `Binding`, codable)

**Files:**
- Create: `InstantSwitcher/Models/Binding.swift`
- Create: `InstantSwitcher/Models/Config.swift`
- Test: `InstantSwitcherTests/BindingCodableTests.swift`

- [ ] **Step 1: Write failing tests**

`InstantSwitcherTests/BindingCodableTests.swift`:
```swift
import XCTest
@testable import InstantSwitcher

final class BindingCodableTests: XCTestCase {
    func testAppBindingRoundTrip() throws {
        let id = UUID()
        let original = Binding.app(AppBinding(
            id: id,
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            displayName: "Slack",
            iconPath: "/Applications/Slack.app"
        ))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Binding.self, from: data)
        XCTAssertEqual(decoded.id, id)
        if case let .app(b) = decoded {
            XCTAssertEqual(b.bundleIdentifier, "com.tinyspeck.slackmacgap")
            XCTAssertEqual(b.displayName, "Slack")
        } else {
            XCTFail("expected .app case")
        }
    }

    func testSpaceBindingRoundTrip() throws {
        let id = UUID()
        let original = Binding.space(SpaceBinding(id: id, spaceIndex: 3, label: "Comms"))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Binding.self, from: data)
        XCTAssertEqual(decoded.id, id)
        if case let .space(b) = decoded {
            XCTAssertEqual(b.spaceIndex, 3)
            XCTAssertEqual(b.label, "Comms")
        } else {
            XCTFail("expected .space case")
        }
    }

    func testConfigRoundTrip() throws {
        let cfg = Config(
            schemaVersion: 1,
            bindings: [
                .space(SpaceBinding(id: UUID(), spaceIndex: 1, label: "One"))
            ],
            systemOverrides: SystemOverrides(arrows: true, digits: false),
            launchAtLogin: true
        )
        let data = try JSONEncoder().encode(cfg)
        let decoded = try JSONDecoder().decode(Config.self, from: data)
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.bindings.count, 1)
        XCTAssertTrue(decoded.systemOverrides.arrows)
        XCTAssertFalse(decoded.systemOverrides.digits)
        XCTAssertTrue(decoded.launchAtLogin)
    }
}
```

- [ ] **Step 2: Implement `Binding.swift`**

```swift
import Foundation

struct AppBinding: Codable, Identifiable, Hashable {
    let id: UUID
    var bundleIdentifier: String
    var displayName: String
    var iconPath: String?
}

struct SpaceBinding: Codable, Identifiable, Hashable {
    let id: UUID
    var spaceIndex: Int
    var label: String
}

enum Binding: Codable, Identifiable, Hashable {
    case app(AppBinding)
    case space(SpaceBinding)

    var id: UUID {
        switch self {
        case .app(let b): return b.id
        case .space(let b): return b.id
        }
    }

    private enum CodingKeys: String, CodingKey { case kind, payload }
    private enum Kind: String, Codable { case app, space }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .app:   self = .app(try c.decode(AppBinding.self, forKey: .payload))
        case .space: self = .space(try c.decode(SpaceBinding.self, forKey: .payload))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .app(let b):
            try c.encode(Kind.app, forKey: .kind)
            try c.encode(b, forKey: .payload)
        case .space(let b):
            try c.encode(Kind.space, forKey: .kind)
            try c.encode(b, forKey: .payload)
        }
    }
}
```

- [ ] **Step 3: Implement `Config.swift`**

```swift
import Foundation

struct SystemOverrides: Codable, Hashable {
    var arrows: Bool
    var digits: Bool

    static let `default` = SystemOverrides(arrows: true, digits: false)
}

struct Config: Codable, Hashable {
    var schemaVersion: Int
    var bindings: [Binding]
    var systemOverrides: SystemOverrides
    var launchAtLogin: Bool

    static let currentSchemaVersion = 1

    static let `default` = Config(
        schemaVersion: currentSchemaVersion,
        bindings: [],
        systemOverrides: .default,
        launchAtLogin: false
    )
}
```

- [ ] **Step 4: Regenerate, build, test**

```bash
xcodegen generate
xcodebuild -scheme InstantSwitcher test -derivedDataPath build 2>&1 | tail -15
```
Expected: tests pass.

- [ ] **Step 5: Commit**

```bash
git add InstantSwitcher/Models InstantSwitcherTests/BindingCodableTests.swift
git commit -m "Add Config and Binding models with Codable round-trip tests"
```

---

## Task 3: `ConfigStore` with atomic write and migration fallback

**Files:**
- Create: `InstantSwitcher/Services/ConfigStore.swift`
- Test: `InstantSwitcherTests/ConfigStoreTests.swift`

- [ ] **Step 1: Write failing tests**

`InstantSwitcherTests/ConfigStoreTests.swift`:
```swift
import XCTest
@testable import InstantSwitcher

final class ConfigStoreTests: XCTestCase {
    var tmpDir: URL!

    override func setUp() {
        tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("instantswitcher-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    func testLoadReturnsDefaultWhenFileMissing() {
        let store = ConfigStore(directory: tmpDir)
        XCTAssertEqual(store.load(), Config.default)
    }

    func testSaveThenLoadRoundTrip() throws {
        let store = ConfigStore(directory: tmpDir)
        var cfg = Config.default
        cfg.bindings = [.space(SpaceBinding(id: UUID(), spaceIndex: 2, label: "Two"))]
        try store.save(cfg)
        XCTAssertEqual(store.load(), cfg)
    }

    func testUnknownSchemaIsBackedUpAndDefaultsReturned() throws {
        let path = tmpDir.appendingPathComponent("config.json")
        let bad = #"{"schemaVersion":999,"bindings":[],"systemOverrides":{"arrows":true,"digits":false},"launchAtLogin":false}"#
        try bad.write(to: path, atomically: true, encoding: .utf8)
        let store = ConfigStore(directory: tmpDir)
        let loaded = store.load()
        XCTAssertEqual(loaded, Config.default)
        let contents = try FileManager.default.contentsOfDirectory(atPath: tmpDir.path)
        XCTAssertTrue(contents.contains { $0.hasPrefix("config.json.backup-") })
    }

    func testCorruptFileIsBackedUpAndDefaultsReturned() throws {
        let path = tmpDir.appendingPathComponent("config.json")
        try "not json".write(to: path, atomically: true, encoding: .utf8)
        let store = ConfigStore(directory: tmpDir)
        XCTAssertEqual(store.load(), Config.default)
        let contents = try FileManager.default.contentsOfDirectory(atPath: tmpDir.path)
        XCTAssertTrue(contents.contains { $0.hasPrefix("config.json.backup-") })
    }
}
```

- [ ] **Step 2: Implement `ConfigStore.swift`**

```swift
import Foundation
import os

final class ConfigStore {
    static let defaultDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("InstantSwitcher", isDirectory: true)
    }()

    private let directory: URL
    private let fileURL: URL
    private let log = Logger(subsystem: "com.theosardin.instantswitcher", category: "config")

    init(directory: URL = ConfigStore.defaultDirectory) {
        self.directory = directory
        self.fileURL = directory.appendingPathComponent("config.json")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func load() -> Config {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .default }
        do {
            let data = try Data(contentsOf: fileURL)
            let cfg = try JSONDecoder().decode(Config.self, from: data)
            guard cfg.schemaVersion == Config.currentSchemaVersion else {
                log.error("Unknown schema version \(cfg.schemaVersion); backing up.")
                backup()
                return .default
            }
            return cfg
        } catch {
            log.error("Failed to decode config: \(error.localizedDescription); backing up.")
            backup()
            return .default
        }
    }

    func save(_ config: Config) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        let tmp = fileURL.appendingPathExtension("tmp")
        try data.write(to: tmp, options: .atomic)
        _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tmp)
    }

    private func backup() {
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backupURL = directory.appendingPathComponent("config.json.backup-\(stamp)")
        try? FileManager.default.moveItem(at: fileURL, to: backupURL)
    }
}
```

- [ ] **Step 3: Build, test**

```bash
xcodegen generate
xcodebuild -scheme InstantSwitcher test -derivedDataPath build 2>&1 | tail -10
```
Expected: tests pass.

- [ ] **Step 4: Commit**

```bash
git add InstantSwitcher/Services/ConfigStore.swift InstantSwitcherTests/ConfigStoreTests.swift
git commit -m "Add ConfigStore with atomic writes and backup-on-corruption"
```

---

## Task 4: `ISSCore` Swift wrapper over the vendored C library

**Files:**
- Create: `InstantSwitcher/Services/ISSCore.swift`
- Create: `InstantSwitcherTests/Fakes/FakeISSCore.swift`

- [ ] **Step 1: Implement protocol, live impl, and fake**

`InstantSwitcher/Services/ISSCore.swift`:
```swift
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
```

- [ ] **Step 2: Add fake**

`InstantSwitcherTests/Fakes/FakeISSCore.swift`:
```swift
import Foundation
@testable import InstantSwitcher

enum FakeISSCall: Equatable {
    case left
    case right
    case index(Int)
}

final class FakeISSCore: ISSInvoking {
    var isInitialized: Bool = true
    var ensureResult: Bool = true
    var info: ISSSpaceStatus?
    private(set) var calls: [FakeISSCall] = []

    @discardableResult
    func ensureInitialized() -> Bool { ensureResult }

    func left() { calls.append(.left) }
    func right() { calls.append(.right) }
    func index(_ oneBased: Int) { calls.append(.index(oneBased)) }
    func currentSpaceInfo() -> ISSSpaceStatus? { info }
}
```

- [ ] **Step 3: Build**

```bash
xcodegen generate
xcodebuild -scheme InstantSwitcher build -derivedDataPath build 2>&1 | tail -10
```
Expected: build succeeds. The C types `ISSDirectionLeft`, `ISSDirectionRight`, `ISSSpaceInfo`, and the functions `iss_init`, `iss_destroy`, `iss_switch`, `iss_switch_to_index`, `iss_get_space_info` must resolve via the bridging header.

- [ ] **Step 4: Commit**

```bash
git add InstantSwitcher/Services/ISSCore.swift InstantSwitcherTests/Fakes/FakeISSCore.swift
git commit -m "Add ISSCore Swift wrapper over vendored C library"
```

---

## Task 5: `SpaceLocator` protocol + CGS implementation + fake

**Files:**
- Create: `InstantSwitcher/Services/SpaceLocator.swift`
- Create: `InstantSwitcherTests/Fakes/FakeSpaceLocator.swift`

- [ ] **Step 1: Implement `SpaceLocator.swift`**

```swift
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
```

- [ ] **Step 2: Add fake**

`InstantSwitcherTests/Fakes/FakeSpaceLocator.swift`:
```swift
import Foundation
@testable import InstantSwitcher

final class FakeSpaceLocator: SpaceLocating {
    var currentIndex: Int? = 1
    var byBundleID: [String: Int] = [:]
    private(set) var lookups: [String] = []

    func currentSpaceIndex() -> Int? { currentIndex }

    func spaceIndex(forBundleID bundleID: String) -> Int? {
        lookups.append(bundleID)
        return byBundleID[bundleID]
    }
}
```

- [ ] **Step 3: Build and test**

```bash
xcodegen generate
xcodebuild -scheme InstantSwitcher test -derivedDataPath build 2>&1 | tail -10
```
Expected: build succeeds, existing tests pass. No unit tests for SpaceLocator itself — CGS can't be stubbed in isolation.

- [ ] **Step 4: Commit**

```bash
git add InstantSwitcher/Services/SpaceLocator.swift InstantSwitcherTests/Fakes/FakeSpaceLocator.swift
git commit -m "Add SpaceLocator with CGS-backed implementation and fake"
```

---

## Task 6: `ShortcutEngine` orchestration + tests

**Files:**
- Create: `InstantSwitcher/Engine/ShortcutEngine.swift`
- Create: `InstantSwitcherTests/Fakes/FakeAppActivator.swift`
- Test: `InstantSwitcherTests/ShortcutEngineTests.swift`

- [ ] **Step 1: Write failing tests**

`InstantSwitcherTests/ShortcutEngineTests.swift`:
```swift
import XCTest
@testable import InstantSwitcher

final class ShortcutEngineTests: XCTestCase {
    var locator: FakeSpaceLocator!
    var core: FakeISSCore!
    var activator: FakeAppActivator!
    var engine: ShortcutEngine!

    override func setUp() {
        locator = FakeSpaceLocator()
        core = FakeISSCore()
        activator = FakeAppActivator()
        engine = ShortcutEngine(locator: locator, core: core, activator: activator)
    }

    func testSpaceBindingCallsIndex() {
        engine.fire(.space(SpaceBinding(id: UUID(), spaceIndex: 4, label: "Four")))
        XCTAssertEqual(core.calls, [.index(4)])
        XCTAssertTrue(activator.activateCalls.isEmpty)
    }

    func testAppBindingJumpsToSpaceThenActivates() {
        locator.byBundleID["com.slack"] = 3
        activator.running["com.slack"] = true
        engine.fire(.app(AppBinding(id: UUID(), bundleIdentifier: "com.slack", displayName: "Slack", iconPath: nil)))
        XCTAssertEqual(core.calls, [.index(3)])
        XCTAssertEqual(activator.activateCalls, ["com.slack"])
    }

    func testAppBindingWithUnknownSpaceSkipsISSButStillActivates() {
        activator.running["com.slack"] = true
        engine.fire(.app(AppBinding(id: UUID(), bundleIdentifier: "com.slack", displayName: "Slack", iconPath: nil)))
        XCTAssertTrue(core.calls.isEmpty)
        XCTAssertEqual(activator.activateCalls, ["com.slack"])
    }

    func testAppBindingLaunchesWhenNotRunning() {
        activator.running["com.slack"] = false
        engine.fire(.app(AppBinding(id: UUID(), bundleIdentifier: "com.slack", displayName: "Slack", iconPath: nil)))
        XCTAssertEqual(activator.launchCalls, ["com.slack"])
    }

    func testSystemOverrideLeftCallsLeft() {
        engine.systemOverride(.left)
        XCTAssertEqual(core.calls, [.left])
    }

    func testSystemOverrideRightCallsRight() {
        engine.systemOverride(.right)
        XCTAssertEqual(core.calls, [.right])
    }

    func testSystemOverrideIndex() {
        engine.systemOverride(.index(7))
        XCTAssertEqual(core.calls, [.index(7)])
    }
}
```

- [ ] **Step 2: Create `FakeAppActivator`**

`InstantSwitcherTests/Fakes/FakeAppActivator.swift`:
```swift
import Foundation
@testable import InstantSwitcher

final class FakeAppActivator: AppActivating {
    var running: [String: Bool] = [:]
    private(set) var launchCalls: [String] = []
    private(set) var activateCalls: [String] = []

    func isRunning(bundleID: String) -> Bool { running[bundleID] ?? false }
    func activate(bundleID: String) { activateCalls.append(bundleID) }
    func launch(bundleID: String) { launchCalls.append(bundleID) }
}
```

- [ ] **Step 3: Implement `ShortcutEngine.swift`**

```swift
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

    private func fireApp(_ binding: AppBinding) {
        if activator.isRunning(bundleID: binding.bundleIdentifier) {
            if let idx = locator.spaceIndex(forBundleID: binding.bundleIdentifier) {
                core.index(idx)
            } else {
                log.notice("No space found for \(binding.bundleIdentifier, privacy: .public); activating directly")
            }
            activator.activate(bundleID: binding.bundleIdentifier)
        } else {
            activator.launch(bundleID: binding.bundleIdentifier)
        }
    }
}
```

- [ ] **Step 4: Build and test**

```bash
xcodegen generate
xcodebuild -scheme InstantSwitcher test -derivedDataPath build 2>&1 | tail -10
```
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add InstantSwitcher/Engine InstantSwitcherTests/ShortcutEngineTests.swift InstantSwitcherTests/Fakes/FakeAppActivator.swift
git commit -m "Add ShortcutEngine orchestrating locator, ISS core, and app activation"
```

---

## Task 7: Hotkey name registry

**Files:**
- Create: `InstantSwitcher/Services/ShortcutNames.swift`

- [ ] **Step 1: Implement**

```swift
import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static func binding(_ id: UUID) -> KeyboardShortcuts.Name {
        .init("binding.\(id.uuidString)")
    }
}
```

- [ ] **Step 2: Build**

```bash
xcodebuild -scheme InstantSwitcher build -derivedDataPath build 2>&1 | tail -10
```
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add InstantSwitcher/Services/ShortcutNames.swift
git commit -m "Add KeyboardShortcuts.Name registry for bindings"
```

---

## Task 8: `AppState` + app wiring + stub views

**Files:**
- Create: `InstantSwitcher/App/AppState.swift`
- Modify: `InstantSwitcher/App/InstantSwitcherApp.swift`
- Create: `InstantSwitcher/App/MenuBarView.swift`
- Create: `InstantSwitcher/Settings/SettingsWindow.swift`

- [ ] **Step 1: Implement `AppState.swift`**

```swift
import Foundation
import KeyboardShortcuts
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var config: Config
    let engine: ShortcutEngine
    let core: ISSInvoking
    let locator: SpaceLocating
    private let store: ConfigStore

    init(store: ConfigStore = ConfigStore(),
         core: ISSInvoking = ISSCore.shared,
         locator: SpaceLocating = SpaceLocator(),
         activator: AppActivating = NSWorkspaceAppActivator()) {
        self.store = store
        self.core = core
        self.locator = locator
        self.engine = ShortcutEngine(locator: locator, core: core, activator: activator)
        self.config = store.load()
        registerAllBindings()
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

    // MARK: - System overrides

    func setOverride(arrows: Bool) {
        config.systemOverrides.arrows = arrows
        persist()
    }

    func setOverride(digits: Bool) {
        config.systemOverrides.digits = digits
        persist()
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
```

- [ ] **Step 2: Rewrite `InstantSwitcherApp.swift`**

```swift
import SwiftUI

@main
struct InstantSwitcherApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra("InstantSwitcher", systemImage: "square.grid.3x3.square") {
            MenuBarView()
                .environmentObject(state)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsWindow()
                .environmentObject(state)
        }
    }
}
```

- [ ] **Step 3: Create stub views**

`InstantSwitcher/App/MenuBarView.swift`:
```swift
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        SettingsLink { Text("Settings…") }.keyboardShortcut(",")
        Divider()
        Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
```

`InstantSwitcher/Settings/SettingsWindow.swift`:
```swift
import SwiftUI

struct SettingsWindow: View {
    var body: some View {
        TabView {
            Text("Shortcuts").tabItem { Label("Shortcuts", systemImage: "keyboard") }
            Text("System").tabItem { Label("System", systemImage: "gearshape") }
            Text("About").tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 620, height: 460)
        .padding(20)
    }
}
```

- [ ] **Step 4: Build**

```bash
xcodegen generate
xcodebuild -scheme InstantSwitcher build -derivedDataPath build 2>&1 | tail -10
```
Expected: build succeeds.

- [ ] **Step 5: Commit**

```bash
git add InstantSwitcher/App InstantSwitcher/Settings/SettingsWindow.swift
git commit -m "Add AppState, app entry, menu bar and settings stubs"
```

---

## Task 9: Shortcuts tab — list, add, delete, hotkey recorder

**Files:**
- Create: `InstantSwitcher/Settings/ShortcutsTab.swift`
- Create: `InstantSwitcher/Settings/AppPickerView.swift`
- Modify: `InstantSwitcher/Settings/SettingsWindow.swift`

- [ ] **Step 1: Implement `AppPickerView.swift`**

```swift
import AppKit
import SwiftUI

struct PickedApp {
    let bundleID: String
    let displayName: String
    let iconPath: String
}

enum AppPicker {
    static func pick() -> PickedApp? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        guard let bundle = Bundle(url: url),
              let bundleID = bundle.bundleIdentifier
        else { return nil }
        let name = (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
            ?? (bundle.infoDictionary?["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return PickedApp(bundleID: bundleID, displayName: name, iconPath: url.path)
    }
}
```

- [ ] **Step 2: Implement `ShortcutsTab.swift`**

```swift
import KeyboardShortcuts
import SwiftUI

struct ShortcutsTab: View {
    @EnvironmentObject var state: AppState
    @State private var newSpaceIndex: Int = 1
    @State private var newSpaceLabel: String = ""
    @State private var showAddSpaceSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Shortcuts").font(.headline)
                Spacer()
                Menu {
                    Button("Add app shortcut…") { addApp() }
                    Button("Add space shortcut…") { showAddSpaceSheet = true }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .frame(width: 90)
            }

            if state.config.bindings.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .padding(.horizontal, 4)
        .sheet(isPresented: $showAddSpaceSheet) { addSpaceSheet }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "keyboard").font(.system(size: 40)).foregroundStyle(.secondary)
            Text("No shortcuts yet").font(.headline)
            Text("Add an app shortcut to instantly focus an app on its space, or a space shortcut to jump to a specific space.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        List {
            ForEach(state.config.bindings, id: \.id) { binding in
                row(for: binding)
            }
            .onMove { src, dst in state.moveBinding(fromOffsets: src, toOffset: dst) }
        }
        .listStyle(.inset)
    }

    @ViewBuilder
    private func row(for binding: Binding) -> some View {
        HStack(spacing: 12) {
            switch binding {
            case .app(let b):
                Image(nsImage: icon(for: b)).resizable().frame(width: 22, height: 22)
                VStack(alignment: .leading) {
                    Text(b.displayName).font(.body)
                    Text(b.bundleIdentifier).font(.caption).foregroundStyle(.secondary)
                }
            case .space(let b):
                Image(systemName: "square.grid.3x3").frame(width: 22, height: 22)
                VStack(alignment: .leading) {
                    Text(b.label.isEmpty ? "Space \(b.spaceIndex)" : b.label).font(.body)
                    Text("Space \(b.spaceIndex)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            KeyboardShortcuts.Recorder(for: .binding(binding.id))
            Button(role: .destructive) {
                state.deleteBinding(id: binding.id)
            } label: { Image(systemName: "trash") }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    private func icon(for binding: AppBinding) -> NSImage {
        if let path = binding.iconPath {
            return NSWorkspace.shared.icon(forFile: path)
        }
        return NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
    }

    private func addApp() {
        guard let info = AppPicker.pick() else { return }
        state.addAppBinding(bundleID: info.bundleID, displayName: info.displayName, iconPath: info.iconPath)
    }

    private var addSpaceSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add space shortcut").font(.headline)
            HStack {
                Text("Space index")
                Stepper(value: $newSpaceIndex, in: 1...20) { Text("\(newSpaceIndex)") }
            }
            HStack {
                Text("Label")
                TextField("optional", text: $newSpaceLabel)
            }
            HStack {
                Spacer()
                Button("Cancel") { showAddSpaceSheet = false; resetSheet() }
                Button("Add") {
                    state.addSpaceBinding(spaceIndex: newSpaceIndex, label: newSpaceLabel)
                    showAddSpaceSheet = false
                    resetSheet()
                }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 360)
    }

    private func resetSheet() { newSpaceIndex = 1; newSpaceLabel = "" }
}
```

- [ ] **Step 3: Wire into `SettingsWindow`**

Replace the Shortcuts tab text with `ShortcutsTab()`.

- [ ] **Step 4: Build and smoke-run**

```bash
xcodegen generate
xcodebuild -scheme InstantSwitcher build -derivedDataPath build 2>&1 | tail -10
open build/Build/Products/Debug/InstantSwitcher.app
```
Expected: build succeeds, Settings window opens, can pick an app, assign hotkey, firing it activates the app. (Space jump likely not yet working until Accessibility is granted, but no crash.)

- [ ] **Step 5: Commit**

```bash
git add InstantSwitcher/Settings
git commit -m "Add Shortcuts tab with app picker, space sheet, and recorder"
```

---

## Task 10: `SystemOverride` `CGEventTap`

**Files:**
- Create: `InstantSwitcher/Engine/SystemOverride.swift`
- Modify: `InstantSwitcher/App/AppState.swift`

- [ ] **Step 1: Implement `SystemOverride.swift`**

```swift
import CoreGraphics
import Foundation
import os

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

    deinit { teardown() }

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

    private func teardown() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        tap = nil
        runLoopSource = nil
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
```

- [ ] **Step 2: Wire into `AppState`**

Add stored property, initialize, and apply state. In `AppState.swift`:

Add after the other stored properties:
```swift
let systemOverride: SystemOverride
```

In `init`, after `self.engine = …`:
```swift
self.systemOverride = SystemOverride(engine: engine)
```

At the end of `init`, after `registerAllBindings()`:
```swift
applyOverrideState()
```

Add method:
```swift
private func applyOverrideState() {
    systemOverride.arrowsEnabled = config.systemOverrides.arrows
    systemOverride.digitsEnabled = config.systemOverrides.digits
}
```

Update `setOverride(arrows:)` and `setOverride(digits:)`:
```swift
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
```

- [ ] **Step 3: Build**

```bash
xcodegen generate
xcodebuild -scheme InstantSwitcher build -derivedDataPath build 2>&1 | tail -10
```
Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
git add InstantSwitcher/Engine/SystemOverride.swift InstantSwitcher/App/AppState.swift
git commit -m "Add SystemOverride CGEventTap for Ctrl+Arrows and Ctrl+Digits"
```

---

## Task 11: System tab — override toggles + Accessibility banner

**Files:**
- Create: `InstantSwitcher/Services/Permissions.swift`
- Create: `InstantSwitcher/Settings/SystemTab.swift`
- Modify: `InstantSwitcher/Settings/SettingsWindow.swift`

- [ ] **Step 1: Implement `Permissions.swift`**

```swift
import AppKit
import ApplicationServices

enum Permissions {
    static func isAccessibilityTrusted(prompt: Bool = false) -> Bool {
        let options: [String: Any] = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    static func openKeyboardShortcutsSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.keyboard?Shortcuts")!
        NSWorkspace.shared.open(url)
    }
}
```

- [ ] **Step 2: Implement `SystemTab.swift`**

```swift
import SwiftUI

struct SystemTab: View {
    @EnvironmentObject var state: AppState
    @State private var accessibilityTrusted: Bool = Permissions.isAccessibilityTrusted()

    var body: some View {
        Form {
            Section("Override macOS shortcuts") {
                Toggle("Override Ctrl + ← / Ctrl + →", isOn: Binding(
                    get: { state.config.systemOverrides.arrows },
                    set: { enable($0, kind: .arrows) }
                ))
                Toggle("Override Ctrl + 1 … 9", isOn: Binding(
                    get: { state.config.systemOverrides.digits },
                    set: { enable($0, kind: .digits) }
                ))

                if (state.config.systemOverrides.arrows || state.config.systemOverrides.digits) && !accessibilityTrusted {
                    banner(
                        title: "Accessibility permission required",
                        message: "Grant InstantSwitcher access in System Settings › Privacy & Security › Accessibility.",
                        buttonLabel: "Open Accessibility Settings",
                        action: { Permissions.openAccessibilitySettings() }
                    )
                }

                if state.config.systemOverrides.arrows || state.config.systemOverrides.digits {
                    banner(
                        title: "Disable the native shortcut",
                        message: "Otherwise macOS still processes it in parallel. Open Keyboard Shortcuts and turn off Mission Control's space shortcuts.",
                        buttonLabel: "Open Keyboard Shortcuts",
                        action: { Permissions.openKeyboardShortcutsSettings() }
                    )
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { accessibilityTrusted = Permissions.isAccessibilityTrusted() }
    }

    private enum Kind { case arrows, digits }

    private func enable(_ on: Bool, kind: Kind) {
        if on {
            _ = Permissions.isAccessibilityTrusted(prompt: true)
        }
        accessibilityTrusted = Permissions.isAccessibilityTrusted()
        switch kind {
        case .arrows: state.setOverride(arrows: on)
        case .digits: state.setOverride(digits: on)
        }
    }

    private func banner(title: String, message: String, buttonLabel: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline).bold()
            Text(message).font(.caption).foregroundStyle(.secondary)
            Button(buttonLabel, action: action).controlSize(.small)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.yellow.opacity(0.15)))
    }
}
```

- [ ] **Step 3: Wire into `SettingsWindow`**

Replace the "System" text placeholder with `SystemTab()`.

- [ ] **Step 4: Build**

```bash
xcodegen generate
xcodebuild -scheme InstantSwitcher build -derivedDataPath build 2>&1 | tail -10
```
Expected: build succeeds.

- [ ] **Step 5: Commit**

```bash
git add InstantSwitcher/Services/Permissions.swift InstantSwitcher/Settings/SystemTab.swift InstantSwitcher/Settings/SettingsWindow.swift
git commit -m "Add System tab with override toggles and permission banners"
```

---

## Task 12: Launch at login (`SMAppService`)

**Files:**
- Create: `InstantSwitcher/Services/LaunchAtLogin.swift`
- Modify: `InstantSwitcher/App/AppState.swift`
- Modify: `InstantSwitcher/Settings/SystemTab.swift`

- [ ] **Step 1: Implement `LaunchAtLogin.swift`**

```swift
import Foundation
import ServiceManagement

enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) throws {
        if enabled {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        }
    }
}
```

- [ ] **Step 2: Add `setLaunchAtLogin` to `AppState`**

```swift
func setLaunchAtLogin(_ on: Bool) {
    do {
        try LaunchAtLogin.set(on)
        config.launchAtLogin = on
        persist()
    } catch {
        NSLog("LaunchAtLogin toggle failed: \(error)")
    }
}
```

- [ ] **Step 3: Add toggle to `SystemTab`**

After the "Override macOS shortcuts" Section, add:
```swift
Section("General") {
    Toggle("Launch at login", isOn: Binding(
        get: { state.config.launchAtLogin },
        set: { state.setLaunchAtLogin($0) }
    ))
}
```

- [ ] **Step 4: Build**

```bash
xcodebuild -scheme InstantSwitcher build -derivedDataPath build 2>&1 | tail -10
```
Expected: build succeeds.

- [ ] **Step 5: Commit**

```bash
git add InstantSwitcher/Services/LaunchAtLogin.swift InstantSwitcher/App/AppState.swift InstantSwitcher/Settings/SystemTab.swift
git commit -m "Add launch-at-login toggle via SMAppService"
```

---

## Task 13: About tab — ISS status + credit + license

**Files:**
- Create: `InstantSwitcher/Settings/AboutTab.swift`
- Modify: `InstantSwitcher/Settings/SettingsWindow.swift`

- [ ] **Step 1: Implement `AboutTab.swift`**

```swift
import SwiftUI

struct AboutTab: View {
    @EnvironmentObject var state: AppState
    @State private var initialized: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                Image(systemName: "square.grid.3x3.square")
                    .font(.system(size: 48))
                VStack(alignment: .leading) {
                    Text("InstantSwitcher").font(.title2).bold()
                    Text("v\(version)").foregroundStyle(.secondary)
                }
            }

            coreStatusRow

            VStack(alignment: .leading, spacing: 4) {
                Text("Credits").font(.headline)
                Text("Powered by ") + Text("[InstantSpaceSwitcher](https://github.com/jurplel/InstantSpaceSwitcher)")
                    + Text(" (MIT) by jurplel.")
                Button("View upstream license") { openLicense() }
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(4)
        .onAppear { initialized = state.core.isInitialized }
    }

    private var coreStatusRow: some View {
        HStack(spacing: 8) {
            if initialized {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("ISS core initialized").font(.caption)
            } else {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                Text("ISS core not initialized — grant Accessibility").font(.caption)
                Button("Retry") {
                    initialized = state.core.ensureInitialized()
                }.controlSize(.small)
            }
        }
    }

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    private func openLicense() {
        guard let url = Bundle.main.url(forResource: "LICENSE", withExtension: nil) else { return }
        NSWorkspace.shared.open(url)
    }
}
```

- [ ] **Step 2: Wire into `SettingsWindow`**

Replace the About tab text with `AboutTab()`.

- [ ] **Step 3: Build**

```bash
xcodebuild -scheme InstantSwitcher build -derivedDataPath build 2>&1 | tail -10
```
Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
git add InstantSwitcher/Settings/AboutTab.swift InstantSwitcher/Settings/SettingsWindow.swift
git commit -m "Add About tab with ISS status, credit, and upstream license"
```

---

## Task 14: Menu-bar dropdown polish

**Files:**
- Modify: `InstantSwitcher/App/MenuBarView.swift`

- [ ] **Step 1: Rewrite**

```swift
import KeyboardShortcuts
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        if !state.core.isInitialized {
            Text("⚠︎ Grant Accessibility for instant switches").foregroundStyle(.yellow)
            Button("Open Accessibility Settings") { Permissions.openAccessibilitySettings() }
            Divider()
        }

        if let info = state.core.currentSpaceInfo() {
            Text("Space \(info.currentIndex) of \(info.spaceCount)").foregroundStyle(.secondary)
            Divider()
        }

        if state.config.bindings.isEmpty {
            Text("No shortcuts configured").foregroundStyle(.secondary)
        } else {
            ForEach(state.config.bindings, id: \.id) { binding in
                Button(label(for: binding)) { state.engine.fire(binding) }
            }
        }

        Divider()

        Toggle("Override Ctrl + Arrows", isOn: Binding(
            get: { state.config.systemOverrides.arrows },
            set: { state.setOverride(arrows: $0) }
        ))
        Toggle("Override Ctrl + 1…9", isOn: Binding(
            get: { state.config.systemOverrides.digits },
            set: { state.setOverride(digits: $0) }
        ))

        Divider()

        SettingsLink { Text("Settings…") }.keyboardShortcut(",")
        Button("Quit InstantSwitcher") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }

    private func label(for binding: Binding) -> String {
        switch binding {
        case .app(let b): return b.displayName
        case .space(let b): return b.label.isEmpty ? "Space \(b.spaceIndex)" : b.label
        }
    }
}
```

Note: `SettingsLink` requires macOS 14+. If deployment needs macOS 13, replace with:
```swift
Button("Settings…") {
    NSApp.activate(ignoringOtherApps: true)
    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
}.keyboardShortcut(",")
```

- [ ] **Step 2: Build**

```bash
xcodebuild -scheme InstantSwitcher build -derivedDataPath build 2>&1 | tail -10
```
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add InstantSwitcher/App/MenuBarView.swift
git commit -m "Flesh out menu-bar dropdown with bindings, space info, and overrides"
```

---

## Task 15: README + `docs/testing.md`

**Files:**
- Create: `README.md`
- Create: `docs/testing.md`

- [ ] **Step 1: Write `docs/testing.md`**

```markdown
# Manual smoke test

Run after build.

1. **Launch** — `open build/Build/Products/Debug/InstantSwitcher.app`. Menu-bar icon appears, no Dock icon.
2. **Grant Accessibility** — macOS prompts on first launch (or on first hotkey fire). Menu bar status line should flip from "Grant Accessibility" to "Space N of M".
3. **App shortcut** — Settings → Shortcuts → Add app shortcut → pick an app that lives on a different space → assign a hotkey. Press it: space jumps instantly, app focuses.
4. **Space shortcut** — Add space shortcut → index 2, label "Two" → assign a hotkey. Press it: jumps to space 2, no app focus.
5. **Override arrows** — System tab → "Override Ctrl + ← / →". Grant Accessibility if re-prompted. Disable the native Mission Control arrows in System Settings. Ctrl+← and Ctrl+→ switch without animation.
6. **Override digits** — "Override Ctrl + 1 … 9". Ctrl+1, Ctrl+2 jump instantly.
7. **Launch at login** — Toggle on, reboot, confirm auto-launch.
8. **Accessibility denied** — Remove InstantSwitcher from Accessibility. Hotkeys still don't crash; About tab says "not initialized"; "Retry" succeeds after re-granting.
9. **Deleted bound app** — Delete an app you bound. Row stays visible; hotkey no-ops.
10. **Persistence** — Quit and relaunch. Bindings, hotkeys, and toggles survive.
```

- [ ] **Step 2: Write `README.md`**

```markdown
# InstantSwitcher

A macOS menu-bar app for instant space switching and per-app space-focus hotkeys. Self-contained — no external dependencies.

- **Focus an app** on whatever space it's on, instantly, via a global hotkey.
- **Jump to a specific space** via a global hotkey.
- Optionally **override macOS's native** Ctrl+Arrows and Ctrl+1..9 so they become instant.

Built on the MIT-licensed [InstantSpaceSwitcher](https://github.com/jurplel/InstantSpaceSwitcher) core (vendored under `Vendor/`).

## Requirements

- macOS 13+
- Accessibility permission (prompted on first launch)
- [xcodegen](https://github.com/yonaskolb/XcodeGen) for dev: `brew install xcodegen`

## Build

```bash
xcodegen generate
xcodebuild -scheme InstantSwitcher -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/InstantSwitcher.app
```

## Package

```bash
./scripts/build-dmg.sh
```

Produces `build/InstantSwitcher.dmg`.

## Permissions

- **Accessibility** — required for gesture synthesis and for overriding native shortcuts.
- No Screen Recording or Input Monitoring needed.

## Development

- Vendored core: `Vendor/InstantSpaceSwitcher/`
- Models: `InstantSwitcher/Models/`
- Services: `InstantSwitcher/Services/` (`ISSCore`, `SpaceLocator`, `ConfigStore`, …)
- Engine: `InstantSwitcher/Engine/` (`ShortcutEngine`, `SystemOverride`)
- UI: `InstantSwitcher/App/` + `InstantSwitcher/Settings/`
- Tests: `InstantSwitcherTests/`

Run tests:
```bash
xcodebuild -scheme InstantSwitcher test -derivedDataPath build
```

Manual smoke test: `docs/testing.md`.

## Design

See `docs/superpowers/specs/2026-04-13-instant-switcher-wrapper-design.md`.

## License

- Our code: MIT (see `LICENSE`).
- Vendored ISS core: MIT by jurplel (see `Vendor/InstantSpaceSwitcher/LICENSE`). Bundled verbatim inside the `.app`.
```

- [ ] **Step 3: Write project root `LICENSE`**

Copy-paste an MIT LICENSE template with current year and your name.

- [ ] **Step 4: Final test pass**

```bash
xcodebuild -scheme InstantSwitcher test -derivedDataPath build 2>&1 | tail -10
```
Expected: `TEST SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add README.md docs/testing.md LICENSE
git commit -m "Add README, manual testing checklist, and project LICENSE"
```

---

## Task 16: `build-dmg.sh` packaging script

**Files:**
- Create: `scripts/build-dmg.sh`

- [ ] **Step 1: Write the script**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCHEME="InstantSwitcher"
CONFIG="Release"
DERIVED="build"
DMG_DIR="build/dmg"
DMG_PATH="build/InstantSwitcher.dmg"

rm -rf "$DERIVED" "$DMG_DIR" "$DMG_PATH"
mkdir -p "$DMG_DIR"

if ! command -v xcodegen >/dev/null; then
    echo "xcodegen not installed; run: brew install xcodegen" >&2
    exit 1
fi

xcodegen generate
xcodebuild -scheme "$SCHEME" -configuration "$CONFIG" -derivedDataPath "$DERIVED" build

APP_PATH="$DERIVED/Build/Products/$CONFIG/$SCHEME.app"
cp -R "$APP_PATH" "$DMG_DIR/"
ln -s /Applications "$DMG_DIR/Applications"

hdiutil create -volname "InstantSwitcher" -srcfolder "$DMG_DIR" -ov -format UDZO "$DMG_PATH"

echo "Built: $DMG_PATH"
```

- [ ] **Step 2: Make executable**

```bash
chmod +x scripts/build-dmg.sh
```

- [ ] **Step 3: Run it once to verify**

```bash
./scripts/build-dmg.sh
ls -la build/InstantSwitcher.dmg
```
Expected: `InstantSwitcher.dmg` exists (size > 0).

- [ ] **Step 4: Commit**

```bash
git add scripts/build-dmg.sh
git commit -m "Add build-dmg.sh packaging script"
```

---

## Acceptance verification

After Task 16, confirm each acceptance criterion from the spec:

1. Menu-bar icon present, no Dock icon. (Tasks 1, 8, 14)
2. App shortcut focuses app on its space without animation. (Tasks 4, 5, 6, 9, 14)
3. Space shortcut jumps to index N. (Tasks 4, 6, 9)
4. Ctrl+Arrow override. (Tasks 10, 11)
5. Ctrl+Digit override. (Tasks 10, 11)
6. Accessibility-denied degrades gracefully + Retry works. (Tasks 4, 13, 14)
7. Config persistence. (Tasks 3, 8)
8. `./scripts/build-dmg.sh` produces a single `.dmg` with ISS `LICENSE` embedded. (Tasks 1, 16)
