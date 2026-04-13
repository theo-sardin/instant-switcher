# InstantSwitcher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS menu-bar app (`InstantSwitcher.app`) that wraps `ISSCli` to provide global hotkeys for (1) focusing a specific app on its current space with no animation, (2) jumping to a specific space, and (3) overriding macOS's native Ctrl+Arrows / Ctrl+1..9 space shortcuts.

**Architecture:** SwiftUI menu-bar app with `MenuBarExtra` + `Settings` scenes. Business logic split into `ShortcutEngine` (dispatches hotkey actions), `SpaceLocator` (private CGS APIs for per-app space lookup), `ISSRunner` (shells out to `ISSCli`), and `SystemOverride` (`CGEventTap` for native-shortcut interception). Config persisted as JSON.

**Tech Stack:** Swift 5.9+, SwiftUI, macOS 13+, [`KeyboardShortcuts`](https://github.com/sindresorhus/KeyboardShortcuts) SPM package, private CoreGraphics/SkyLight symbols, `SMAppService`, XCTest, [`xcodegen`](https://github.com/yonaskolb/XcodeGen) for project generation.

---

## File structure

```
instant-switcher/
├── project.yml                               # xcodegen manifest
├── .gitignore
├── README.md
├── InstantSwitcher/
│   ├── App/
│   │   ├── InstantSwitcherApp.swift          # @main; Settings + MenuBarExtra scenes
│   │   └── MenuBarView.swift                 # dropdown UI
│   ├── Settings/
│   │   ├── SettingsWindow.swift              # tab container
│   │   ├── ShortcutsTab.swift                # bindings list, add/remove
│   │   ├── SystemTab.swift                   # override toggles, launch-at-login
│   │   └── AboutTab.swift                    # version, ISS status
│   ├── Engine/
│   │   ├── ShortcutEngine.swift              # orchestrates hotkey → locate → jump → activate
│   │   └── SystemOverride.swift              # CGEventTap wrapper
│   ├── Services/
│   │   ├── ISSRunner.swift                   # Process wrapper (protocol + live impl)
│   │   ├── SpaceLocator.swift                # CGS wrapper (protocol + live impl)
│   │   ├── ConfigStore.swift                 # JSON atomic load/save + migration
│   │   ├── LaunchAtLogin.swift               # SMAppService helper
│   │   └── ShortcutNames.swift               # KeyboardShortcuts.Name registry
│   ├── Models/
│   │   ├── Config.swift                      # Config, SystemOverrides
│   │   └── Binding.swift                     # Binding enum, AppBinding, SpaceBinding
│   └── Resources/
│       ├── Assets.xcassets
│       └── Info.plist
└── InstantSwitcherTests/
    ├── Fakes/
    │   ├── FakeSpaceLocator.swift
    │   └── FakeISSRunner.swift
    ├── BindingCodableTests.swift
    ├── ConfigStoreTests.swift
    └── ShortcutEngineTests.swift
```

---

## Task 1: Project scaffold with xcodegen

**Files:**
- Create: `project.yml`
- Create: `InstantSwitcher/Resources/Info.plist`
- Create: `InstantSwitcher/App/InstantSwitcherApp.swift`
- Modify: `.gitignore`

- [ ] **Step 1: Install xcodegen locally if missing**

Run: `which xcodegen || brew install xcodegen`
Expected: path printed, or homebrew install completes.

- [ ] **Step 2: Write `.gitignore` additions**

Append to `.gitignore`:
```
InstantSwitcher.xcodeproj
*.xcworkspace
.swiftpm/
```

- [ ] **Step 3: Write `project.yml`**

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
    resources:
      - path: InstantSwitcher/Resources/Assets.xcassets
    info:
      path: InstantSwitcher/Resources/Info.plist
      properties:
        LSUIElement: true
        CFBundleDisplayName: InstantSwitcher
        NSHumanReadableCopyright: "Copyright © 2026"
    entitlements:
      path: InstantSwitcher/Resources/InstantSwitcher.entitlements
      properties:
        com.apple.security.app-sandbox: false
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

- [ ] **Step 4: Create empty `Info.plist` and entitlements**

Create `InstantSwitcher/Resources/Info.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict/></plist>
```

Create `InstantSwitcher/Resources/InstantSwitcher.entitlements`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict/></plist>
```

Create an empty `InstantSwitcher/Resources/Assets.xcassets/Contents.json`:
```json
{ "info": { "author": "xcode", "version": 1 } }
```

- [ ] **Step 5: Create minimal app entry point**

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

- [ ] **Step 6: Generate the Xcode project and build**

Run:
```bash
xcodegen generate
xcodebuild -scheme InstantSwitcher -configuration Debug -derivedDataPath build build | tail -20
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add .gitignore project.yml InstantSwitcher
git commit -m "Scaffold InstantSwitcher Xcode project and menu-bar stub"
```

---

## Task 2: Data models (`Config`, `Binding`, codable)

**Files:**
- Create: `InstantSwitcher/Models/Binding.swift`
- Create: `InstantSwitcher/Models/Config.swift`
- Test: `InstantSwitcherTests/BindingCodableTests.swift`

- [ ] **Step 1: Write failing test for `AppBinding` round-trip**

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

- [ ] **Step 2: Run the test, expect failure**

Run: `xcodebuild -scheme InstantSwitcher test -derivedDataPath build 2>&1 | tail -30`
Expected: compile failure — `Binding`, `AppBinding`, `Config` unresolved.

- [ ] **Step 3: Implement `Binding.swift`**

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

- [ ] **Step 4: Implement `Config.swift`**

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

- [ ] **Step 5: Run tests, expect pass**

Run: `xcodebuild -scheme InstantSwitcher test -derivedDataPath build 2>&1 | tail -20`
Expected: tests pass, `TEST SUCCEEDED`.

- [ ] **Step 6: Commit**

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

- [ ] **Step 2: Run tests, expect compile failure**

Run: `xcodebuild -scheme InstantSwitcher test -derivedDataPath build 2>&1 | tail -15`
Expected: `ConfigStore` unresolved.

- [ ] **Step 3: Implement `ConfigStore.swift`**

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

- [ ] **Step 4: Run tests, expect pass**

Run: `xcodebuild -scheme InstantSwitcher test -derivedDataPath build 2>&1 | tail -10`
Expected: tests pass.

- [ ] **Step 5: Commit**

```bash
git add InstantSwitcher/Services/ConfigStore.swift InstantSwitcherTests/ConfigStoreTests.swift
git commit -m "Add ConfigStore with atomic writes and backup-on-corruption"
```

---

## Task 4: `ISSRunner` protocol + live impl + fake + test

**Files:**
- Create: `InstantSwitcher/Services/ISSRunner.swift`
- Create: `InstantSwitcherTests/Fakes/FakeISSRunner.swift`

- [ ] **Step 1: Implement the protocol and a fake**

`InstantSwitcher/Services/ISSRunner.swift`:
```swift
import Foundation
import os

enum ISSCommand: Equatable {
    case left
    case right
    case index(Int)

    var args: [String] {
        switch self {
        case .left: return ["left"]
        case .right: return ["right"]
        case .index(let n): return ["index", String(n)]
        }
    }
}

protocol ISSInvoking {
    var isAvailable: Bool { get }
    func run(_ command: ISSCommand)
}

final class ISSRunner: ISSInvoking {
    static let defaultCLIPath = "/Applications/InstantSpaceSwitcher.app/Contents/MacOS/ISSCli"

    private let cliPath: String
    private let queue = DispatchQueue(label: "com.theosardin.instantswitcher.iss", qos: .userInitiated)
    private let log = Logger(subsystem: "com.theosardin.instantswitcher", category: "iss")

    init(cliPath: String = ISSRunner.defaultCLIPath) {
        self.cliPath = cliPath
    }

    var isAvailable: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: cliPath, isDirectory: &isDir) && !isDir.boolValue
    }

    func run(_ command: ISSCommand) {
        let args = command.args
        let path = cliPath
        queue.async { [log] in
            guard FileManager.default.fileExists(atPath: path) else {
                log.error("ISSCli missing at \(path, privacy: .public)")
                return
            }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = args
            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus != 0 {
                    log.error("ISSCli exited \(process.terminationStatus) for args \(args, privacy: .public)")
                }
            } catch {
                log.error("ISSCli launch failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
```

- [ ] **Step 2: Add fake for tests**

`InstantSwitcherTests/Fakes/FakeISSRunner.swift`:
```swift
import Foundation
@testable import InstantSwitcher

final class FakeISSRunner: ISSInvoking {
    var isAvailable: Bool = true
    private(set) var calls: [ISSCommand] = []

    func run(_ command: ISSCommand) {
        calls.append(command)
    }
}
```

- [ ] **Step 3: Write integration test for live runner using `/bin/echo` as a stand-in**

Append to `InstantSwitcherTests/ConfigStoreTests.swift` — actually create a new file `InstantSwitcherTests/ISSRunnerLiveTests.swift`:
```swift
import XCTest
@testable import InstantSwitcher

final class ISSRunnerLiveTests: XCTestCase {
    func testReportsUnavailableWhenPathMissing() {
        let runner = ISSRunner(cliPath: "/definitely/not/here/ISSCli")
        XCTAssertFalse(runner.isAvailable)
    }

    func testReportsAvailableForEcho() {
        let runner = ISSRunner(cliPath: "/bin/echo")
        XCTAssertTrue(runner.isAvailable)
    }

    func testRunDoesNotThrowWithEcho() {
        let runner = ISSRunner(cliPath: "/bin/echo")
        runner.run(.index(3))
        // async; just assert no crash. Give the queue a moment.
        let exp = expectation(description: "returns")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)
    }
}
```

- [ ] **Step 4: Run tests, expect pass**

Run: `xcodebuild -scheme InstantSwitcher test -derivedDataPath build 2>&1 | tail -10`
Expected: tests pass.

- [ ] **Step 5: Commit**

```bash
git add InstantSwitcher/Services/ISSRunner.swift InstantSwitcherTests/Fakes/FakeISSRunner.swift InstantSwitcherTests/ISSRunnerLiveTests.swift
git commit -m "Add ISSRunner with protocol, live impl, and fake"
```

---

## Task 5: `SpaceLocator` protocol + CGS implementation + fake

**Files:**
- Create: `InstantSwitcher/Services/SpaceLocator.swift`
- Create: `InstantSwitcherTests/Fakes/FakeSpaceLocator.swift`

- [ ] **Step 1: Implement protocol + CGS-backed impl**

`InstantSwitcher/Services/SpaceLocator.swift`:
```swift
import AppKit
import os

protocol SpaceLocating {
    func currentSpaceIndex() -> Int?
    func spaceIndex(forBundleID bundleID: String) -> Int?
}

// Private CGS symbols. These are undocumented and may change across macOS versions.
// Mirrors what Yabai/AeroSpace/Hammerspoon use.
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
        let mask: Int32 = 0x7  // include all space types
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

- [ ] **Step 3: Build and run tests**

Run: `xcodebuild -scheme InstantSwitcher test -derivedDataPath build 2>&1 | tail -10`
Expected: compile succeeds; existing tests still pass. SpaceLocator has no unit tests by design (CGS can't be stubbed in isolation).

- [ ] **Step 4: Commit**

```bash
git add InstantSwitcher/Services/SpaceLocator.swift InstantSwitcherTests/Fakes/FakeSpaceLocator.swift
git commit -m "Add SpaceLocator with CGS-backed implementation and fake"
```

---

## Task 6: `ShortcutEngine` orchestration + tests

**Files:**
- Create: `InstantSwitcher/Engine/ShortcutEngine.swift`
- Test: `InstantSwitcherTests/ShortcutEngineTests.swift`

- [ ] **Step 1: Write failing tests**

`InstantSwitcherTests/ShortcutEngineTests.swift`:
```swift
import XCTest
@testable import InstantSwitcher

final class ShortcutEngineTests: XCTestCase {
    var locator: FakeSpaceLocator!
    var runner: FakeISSRunner!
    var activator: FakeAppActivator!
    var engine: ShortcutEngine!

    override func setUp() {
        locator = FakeSpaceLocator()
        runner = FakeISSRunner()
        activator = FakeAppActivator()
        engine = ShortcutEngine(locator: locator, runner: runner, activator: activator)
    }

    func testSpaceBindingRunsIndexCommand() {
        engine.fire(.space(SpaceBinding(id: UUID(), spaceIndex: 4, label: "Four")))
        XCTAssertEqual(runner.calls, [.index(4)])
        XCTAssertTrue(activator.activateCalls.isEmpty)
    }

    func testAppBindingJumpsToSpaceThenActivates() {
        locator.byBundleID["com.slack"] = 3
        activator.isRunning["com.slack"] = true
        engine.fire(.app(AppBinding(id: UUID(), bundleIdentifier: "com.slack", displayName: "Slack", iconPath: nil)))
        XCTAssertEqual(runner.calls, [.index(3)])
        XCTAssertEqual(activator.activateCalls, ["com.slack"])
    }

    func testAppBindingWithUnknownSpaceSkipsISSButStillActivates() {
        activator.isRunning["com.slack"] = true
        engine.fire(.app(AppBinding(id: UUID(), bundleIdentifier: "com.slack", displayName: "Slack", iconPath: nil)))
        XCTAssertTrue(runner.calls.isEmpty)
        XCTAssertEqual(activator.activateCalls, ["com.slack"])
    }

    func testAppBindingLaunchesWhenNotRunning() {
        activator.isRunning["com.slack"] = false
        engine.fire(.app(AppBinding(id: UUID(), bundleIdentifier: "com.slack", displayName: "Slack", iconPath: nil)))
        XCTAssertEqual(activator.launchCalls, ["com.slack"])
    }

    func testSystemOverrideLeftRoutesToRunner() {
        engine.systemOverride(.left)
        XCTAssertEqual(runner.calls, [.left])
    }

    func testSystemOverrideIndexRoutesToRunner() {
        engine.systemOverride(.index(7))
        XCTAssertEqual(runner.calls, [.index(7)])
    }
}

final class FakeAppActivator: AppActivating {
    var isRunning: [String: Bool] = [:]
    var launchCalls: [String] = []
    var activateCalls: [String] = []

    func isRunning(bundleID: String) -> Bool { isRunning[bundleID] ?? false }
    func activate(bundleID: String) { activateCalls.append(bundleID) }
    func launch(bundleID: String) { launchCalls.append(bundleID) }
}
```

- [ ] **Step 2: Run tests, expect failure**

Run: `xcodebuild -scheme InstantSwitcher test -derivedDataPath build 2>&1 | tail -15`
Expected: `ShortcutEngine`, `AppActivating`, `.systemOverride` unresolved.

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

enum SystemOverrideAction {
    case left, right
    case index(Int)
}

final class ShortcutEngine {
    private let locator: SpaceLocating
    private let runner: ISSInvoking
    private let activator: AppActivating
    private let log = Logger(subsystem: "com.theosardin.instantswitcher", category: "hotkey")

    init(locator: SpaceLocating, runner: ISSInvoking, activator: AppActivating) {
        self.locator = locator
        self.runner = runner
        self.activator = activator
    }

    func fire(_ binding: Binding) {
        switch binding {
        case .space(let s):
            runner.run(.index(s.spaceIndex))
        case .app(let a):
            fireApp(a)
        }
    }

    func systemOverride(_ action: SystemOverrideAction) {
        switch action {
        case .left:  runner.run(.left)
        case .right: runner.run(.right)
        case .index(let n): runner.run(.index(n))
        }
    }

    private func fireApp(_ binding: AppBinding) {
        if activator.isRunning(bundleID: binding.bundleIdentifier) {
            if let idx = locator.spaceIndex(forBundleID: binding.bundleIdentifier) {
                runner.run(.index(idx))
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

- [ ] **Step 4: Run tests, expect pass**

Run: `xcodebuild -scheme InstantSwitcher test -derivedDataPath build 2>&1 | tail -10`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add InstantSwitcher/Engine InstantSwitcherTests/ShortcutEngineTests.swift
git commit -m "Add ShortcutEngine orchestrating locator, runner, and app activation"
```

---

## Task 7: Hotkey name registry + integration with `KeyboardShortcuts`

**Files:**
- Create: `InstantSwitcher/Services/ShortcutNames.swift`

- [ ] **Step 1: Implement name registry**

`InstantSwitcher/Services/ShortcutNames.swift`:
```swift
import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Stable per-binding name derived from the binding UUID.
    static func binding(_ id: UUID) -> KeyboardShortcuts.Name {
        .init("binding.\(id.uuidString)")
    }

    // System override names — fixed.
    static let systemLeft  = Self("system.left")
    static let systemRight = Self("system.right")
    static func systemIndex(_ n: Int) -> Self { Self("system.index.\(n)") }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild -scheme InstantSwitcher build -derivedDataPath build 2>&1 | tail -10`
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add InstantSwitcher/Services/ShortcutNames.swift
git commit -m "Add KeyboardShortcuts.Name registry for bindings and overrides"
```

---

## Task 8: App-wide state container and hotkey registration

**Files:**
- Create: `InstantSwitcher/App/AppState.swift`
- Modify: `InstantSwitcher/App/InstantSwitcherApp.swift`

- [ ] **Step 1: Create `AppState.swift`**

```swift
import Foundation
import KeyboardShortcuts
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var config: Config
    let engine: ShortcutEngine
    let runner: ISSInvoking
    let locator: SpaceLocating
    private let store: ConfigStore

    init(store: ConfigStore = ConfigStore(),
         runner: ISSInvoking = ISSRunner(),
         locator: SpaceLocating = SpaceLocator(),
         activator: AppActivating = NSWorkspaceAppActivator()) {
        self.store = store
        self.runner = runner
        self.locator = locator
        self.engine = ShortcutEngine(locator: locator, runner: runner, activator: activator)
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

    // MARK: - System override toggles

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

- [ ] **Step 2: Wire `AppState` into `InstantSwitcherApp`**

Replace the whole of `InstantSwitcher/App/InstantSwitcherApp.swift`:
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

- [ ] **Step 3: Create stub views so the app builds**

`InstantSwitcher/App/MenuBarView.swift`:
```swift
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Button("Settings…") {
            NSApp.activate(ignoringOtherApps: true)
            if #available(macOS 14, *) {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } else {
                NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
            }
        }
        .keyboardShortcut(",")
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
        .frame(width: 560, height: 420)
        .padding(20)
    }
}
```

- [ ] **Step 4: Build**

Run: `xcodebuild -scheme InstantSwitcher build -derivedDataPath build 2>&1 | tail -10`
Expected: build succeeds.

- [ ] **Step 5: Commit**

```bash
git add InstantSwitcher/App InstantSwitcher/Settings
git commit -m "Add AppState, menu bar dropdown stub, and settings tab shell"
```

---

## Task 9: Shortcuts tab — list, add, delete, hotkey recorder

**Files:**
- Create: `InstantSwitcher/Settings/ShortcutsTab.swift`
- Create: `InstantSwitcher/Settings/AppPickerView.swift`
- Modify: `InstantSwitcher/Settings/SettingsWindow.swift`

- [ ] **Step 1: Implement `AppPickerView`**

```swift
import AppKit
import SwiftUI

enum AppPickerResult {
    struct Info {
        let bundleID: String
        let displayName: String
        let iconPath: String
    }
}

enum AppPicker {
    static func pick() -> AppPickerResult.Info? {
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
        return AppPickerResult.Info(bundleID: bundleID, displayName: name, iconPath: url.path)
    }
}
```

- [ ] **Step 2: Implement `ShortcutsTab`**

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

Replace `SettingsWindow.swift` body:
```swift
import SwiftUI

struct SettingsWindow: View {
    var body: some View {
        TabView {
            ShortcutsTab()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            Text("System")
                .tabItem { Label("System", systemImage: "gearshape") }
            Text("About")
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 620, height: 460)
        .padding(20)
    }
}
```

- [ ] **Step 4: Build and smoke-run**

```bash
xcodebuild -scheme InstantSwitcher build -derivedDataPath build 2>&1 | tail -10
open build/Build/Products/Debug/InstantSwitcher.app
```
Expected: build succeeds; app runs, Settings window opens, you can pick an app and record a hotkey. Hitting the hotkey should focus the app (space jump may not yet work if the app is on another space, but activation should).

- [ ] **Step 5: Commit**

```bash
git add InstantSwitcher/Settings
git commit -m "Add Shortcuts tab with app picker, space sheet, and recorder"
```

---

## Task 10: `SystemOverride` — `CGEventTap` for Ctrl+Arrows and Ctrl+Digits

**Files:**
- Create: `InstantSwitcher/Engine/SystemOverride.swift`

- [ ] **Step 1: Implement the tap**

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

    deinit {
        teardown()
    }

    // MARK: - Tap lifecycle

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

    // MARK: - Handling

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }

        let flags = event.flags
        let isControl = flags.contains(.maskControl)
        let withoutUnmodified = flags.subtracting([.maskControl])
        let noOtherMods = !withoutUnmodified.contains(.maskCommand)
            && !withoutUnmodified.contains(.maskAlternate)
            && !withoutUnmodified.contains(.maskShift)

        guard isControl, noOtherMods else { return Unmanaged.passUnretained(event) }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        // kVK_LeftArrow  = 123, kVK_RightArrow = 124
        if arrowsEnabled {
            if keyCode == 123 {
                engine.systemOverride(.left)
                return nil
            }
            if keyCode == 124 {
                engine.systemOverride(.right)
                return nil
            }
        }
        if digitsEnabled {
            if let n = digitIndex(for: keyCode) {
                engine.systemOverride(.index(n))
                return nil
            }
        }
        return Unmanaged.passUnretained(event)
    }

    // Top-row digit virtual keycodes: 18=1, 19=2, 20=3, 21=4, 23=5, 22=6, 26=7, 28=8, 25=9
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

    // MARK: - C callback

    private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let me = Unmanaged<SystemOverride>.fromOpaque(userInfo).takeUnretainedValue()
        // Tap may be disabled by the system (e.g. timeout); re-enable.
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

Modify `AppState.swift`:
- Add stored property: `let systemOverride: SystemOverride`
- Initialize after `engine`: `self.systemOverride = SystemOverride(engine: engine)`
- At end of `init` (after `registerAllBindings`), call `applyOverrideState()`
- Add:
```swift
private func applyOverrideState() {
    systemOverride.arrowsEnabled = config.systemOverrides.arrows
    systemOverride.digitsEnabled = config.systemOverrides.digits
}
```
- In `setOverride(arrows:)` and `setOverride(digits:)`, call `applyOverrideState()` after `persist()`.

- [ ] **Step 3: Add Accessibility usage description to Info.plist**

Modify `project.yml` target `InstantSwitcher` `info.properties`, adding:
```yaml
        NSAppleEventsUsageDescription: "InstantSwitcher launches and activates the apps you've bound to shortcuts."
```
(Accessibility itself doesn't require a plist string, but AX prompt appears automatically the first time `CGEvent.tapCreate` runs.)

Regenerate project:
```bash
xcodegen generate
```

- [ ] **Step 4: Build**

Run: `xcodebuild -scheme InstantSwitcher build -derivedDataPath build 2>&1 | tail -10`
Expected: build succeeds.

- [ ] **Step 5: Commit**

```bash
git add InstantSwitcher/Engine/SystemOverride.swift InstantSwitcher/App/AppState.swift project.yml
git commit -m "Add SystemOverride CGEventTap for Ctrl+Arrows and Ctrl+Digits"
```

---

## Task 11: System tab — override toggles + Accessibility banner

**Files:**
- Create: `InstantSwitcher/Settings/SystemTab.swift`
- Create: `InstantSwitcher/Services/Permissions.swift`
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
        if on && !Permissions.isAccessibilityTrusted(prompt: true) {
            accessibilityTrusted = false
            // Still flip the flag; tap will install once permission is granted.
        } else {
            accessibilityTrusted = Permissions.isAccessibilityTrusted()
        }
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

Replace the System text placeholder with `SystemTab()`.

- [ ] **Step 4: Build and test**

```bash
xcodebuild -scheme InstantSwitcher build -derivedDataPath build 2>&1 | tail -10
```
Expected: build succeeds.

- [ ] **Step 5: Commit**

```bash
git add InstantSwitcher/Settings/SystemTab.swift InstantSwitcher/Services/Permissions.swift InstantSwitcher/Settings/SettingsWindow.swift
git commit -m "Add System tab with override toggles and permission banners"
```

---

## Task 12: Launch at login (`SMAppService`)

**Files:**
- Create: `InstantSwitcher/Services/LaunchAtLogin.swift`
- Modify: `InstantSwitcher/Settings/SystemTab.swift`
- Modify: `InstantSwitcher/App/AppState.swift`

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

In `AppState.swift`, add:
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

- [ ] **Step 3: Add toggle to System tab**

In `SystemTab.swift`, add a new `Section` after the overrides section:
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

## Task 13: About tab — ISS detection badge + version

**Files:**
- Create: `InstantSwitcher/Settings/AboutTab.swift`
- Modify: `InstantSwitcher/Settings/SettingsWindow.swift`

- [ ] **Step 1: Implement `AboutTab.swift`**

```swift
import SwiftUI

struct AboutTab: View {
    @EnvironmentObject var state: AppState

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

            issStatusRow

            Link("InstantSpaceSwitcher (required)", destination: URL(string: "https://interversehq.com/instantspaceswitcher")!)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(4)
    }

    private var issStatusRow: some View {
        HStack(spacing: 8) {
            if state.runner.isAvailable {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("ISSCli detected at \(ISSRunner.defaultCLIPath)").font(.caption)
            } else {
                Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                Text("ISSCli not found — install InstantSpaceSwitcher").font(.caption)
            }
        }
    }

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }
}
```

- [ ] **Step 2: Wire into `SettingsWindow`**

Replace the About placeholder:
```swift
AboutTab().tabItem { Label("About", systemImage: "info.circle") }
```

- [ ] **Step 3: Build**

```bash
xcodebuild -scheme InstantSwitcher build -derivedDataPath build 2>&1 | tail -10
```
Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
git add InstantSwitcher/Settings/AboutTab.swift InstantSwitcher/Settings/SettingsWindow.swift
git commit -m "Add About tab with ISS detection badge"
```

---

## Task 14: Menu-bar dropdown — status, clickable bindings, overrides, settings

**Files:**
- Modify: `InstantSwitcher/App/MenuBarView.swift`

- [ ] **Step 1: Rewrite `MenuBarView.swift`**

```swift
import KeyboardShortcuts
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        if !state.runner.isAvailable {
            Text("⚠︎ ISSCli not found").foregroundStyle(.red)
            Link("Install InstantSpaceSwitcher", destination: URL(string: "https://interversehq.com/instantspaceswitcher")!)
            Divider()
        }

        if let idx = state.locator.currentSpaceIndex() {
            Text("Current space: \(idx)").foregroundStyle(.secondary)
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

Note: `SettingsLink` is macOS 14+. If deployment needs macOS 13, replace with:
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
git commit -m "Flesh out menu-bar dropdown with bindings, overrides, and ISS status"
```

---

## Task 15: End-to-end manual smoke test + README

**Files:**
- Create: `README.md`
- Create: `docs/testing.md`

- [ ] **Step 1: Write `docs/testing.md` smoke checklist**

```markdown
# Manual smoke test

Run after build. Requires `InstantSpaceSwitcher.app` installed at `/Applications`.

1. **Launch** — `open build/Build/Products/Debug/InstantSwitcher.app`. Menu-bar icon appears, no Dock icon.
2. **App shortcut** — Settings → Shortcuts → Add app shortcut → pick an app on a different space → assign a hotkey. Press the hotkey: space switches instantly, app comes to front.
3. **Space shortcut** — Add space shortcut → index 2, label "Two" → assign a hotkey. Press the hotkey: space 2 focused, no app focus.
4. **Override arrows** — Settings → System → enable "Override Ctrl + ← / →". Grant Accessibility when prompted. Disable native Mission Control arrow shortcuts in System Settings. Ctrl+← and Ctrl+→ now switch instantly.
5. **Override digits** — Enable "Override Ctrl + 1 … 9". Ctrl+1, Ctrl+2 jump without animation.
6. **Launch at login** — Toggle on, reboot, confirm app auto-launches.
7. **ISS missing** — Temporarily rename `/Applications/InstantSpaceSwitcher.app`. Menu-bar shows warning; bindings no-op. Rename back.
8. **Deleted bound app** — Delete an app you've bound. Its row should still be listed; hotkey no-ops.
9. **Persistence** — Quit and relaunch. Bindings, hotkeys, and toggles survive.
```

- [ ] **Step 2: Write `README.md`**

```markdown
# InstantSwitcher

A menu-bar wrapper around [InstantSpaceSwitcher](https://interversehq.com/instantspaceswitcher) that lets you:

- Bind a global hotkey to **focus a specific app** on the space it's currently on — no sliding animation.
- Bind a global hotkey to **jump to a specific space**.
- Optionally **override macOS's native** Ctrl+Arrows / Ctrl+1..9 space shortcuts so they become instant.

## Requirements

- macOS 13+
- [InstantSpaceSwitcher.app](https://interversehq.com/instantspaceswitcher) installed at `/Applications/InstantSpaceSwitcher.app`
- [xcodegen](https://github.com/yonaskolb/XcodeGen) for dev: `brew install xcodegen`

## Build

```bash
xcodegen generate
xcodebuild -scheme InstantSwitcher -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/InstantSwitcher.app
```

## Permissions

- **Accessibility** (for system overrides only) — prompted on first enable.
- No Screen Recording or Input Monitoring needed.

## Development

- Models: `InstantSwitcher/Models`
- Services: `InstantSwitcher/Services` (`SpaceLocator`, `ISSRunner`, `ConfigStore`, …)
- Engine: `InstantSwitcher/Engine` (`ShortcutEngine`, `SystemOverride`)
- UI: `InstantSwitcher/App` + `InstantSwitcher/Settings`
- Tests: `InstantSwitcherTests`

Run tests: `xcodebuild -scheme InstantSwitcher test -derivedDataPath build`

Manual smoke test: `docs/testing.md`.

## Design

See `docs/superpowers/specs/2026-04-13-instant-switcher-wrapper-design.md`.
```

- [ ] **Step 3: Run all tests one more time**

```bash
xcodebuild -scheme InstantSwitcher test -derivedDataPath build 2>&1 | tail -10
```
Expected: `TEST SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add README.md docs/testing.md
git commit -m "Add README and manual smoke-test checklist"
```

---

## Acceptance verification

After the final commit, confirm each acceptance criterion from the spec:

1. Menu-bar icon present, no Dock icon. (Task 1, 14)
2. App shortcut focuses app on its space without animation. (Task 5, 6, 9, 14)
3. Space shortcut jumps to index N. (Task 6, 9)
4. Ctrl+Arrow override. (Task 10, 11)
5. Ctrl+Digit override. (Task 10, 11)
6. ISS missing → red state + no-op. (Task 4, 13, 14)
7. Config persistence. (Task 3, 8)

If any criterion is unverified after the smoke test, file it as a follow-up task rather than retroactively editing this plan.
