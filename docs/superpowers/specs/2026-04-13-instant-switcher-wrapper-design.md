# Instant Switcher — Design Spec

**Date:** 2026-04-13
**Status:** Revised after pivot to vendor upstream ISS C core

## Summary

A native macOS menu-bar app (`InstantSwitcher.app`) that vendors the MIT-licensed core of [InstantSpaceSwitcher](https://github.com/jurplel/InstantSpaceSwitcher) (the C library that synthesizes a fast Dock-swipe gesture) into a single self-contained `.app`. It lets the user:

1. Define global hotkeys that instantly jump to the space a specific app lives on and focus that app (replacing Apptivate + avoiding macOS's animated space switch).
2. Define global hotkeys that jump to a specific space index (no app focus).
3. Optionally override macOS's native space-switching shortcuts (Ctrl+Arrows, Ctrl+1..9) so they are instant.

Distribution is a single `.dmg` containing `InstantSwitcher.app`. No external dependency. Upstream's C core (`Sources/ISS/ISS.c`, `Sources/ISS/include/ISS.h`) is vendored under `Vendor/InstantSpaceSwitcher/` with its `LICENSE` preserved and credit shown in the About tab. We do not vendor upstream's Swift/AppKit app code — our UI is all SwiftUI.

## Non-goals

- Reimplementing ISS's gesture-synthesis mechanism. We vendor it and call it directly via a C bridging header.
- Vendoring upstream's Swift/AppKit app code (their preferences window, hotkey manager, recorder). We provide our own SwiftUI equivalents.
- Trackpad swipe gesture overrides (upstream exposes `iss_set_swipe_override`; we leave it off by default — out of scope here).
- Syncing config across machines, Keychain, network, or telemetry.
- An in-app log viewer (use Console.app).
- Auto-updating / self-updater.

## Architecture

Single SwiftUI app, `LSUIElement = YES`, deployment target macOS 13 (matches upstream ISS).

Internal modules:

- **ShortcutEngine** — registers global hotkeys via the `KeyboardShortcuts` Swift package (Sindre Sorhus). Dispatches actions to the binding handlers.
- **SpaceLocator** — wraps private CoreGraphics/SkyLight (CGS) APIs to answer *"which space index does app X's frontmost window live on?"*. Isolated to one file so a future macOS upgrade breaking CGS is contained.
- **ISSCore** — Swift wrapper around the vendored C library. Calls `iss_init()` on construction; exposes `left()`, `right()`, `index(_:)`, `currentSpaceInfo()`. One instance, app-lifetime. Re-tries `iss_init()` on demand if Accessibility was granted after launch.
- **SystemOverride** — optional `CGEventTap` that swallows Ctrl+Arrow and Ctrl+Digit key events and re-emits them as `ShortcutEngine` actions.

UI surface:

- `MenuBarExtra` for the menu-bar icon + dropdown.
- A separate `Settings` scene for editing bindings and toggles.

## Data flow

### Focus-app binding (`AppBinding`)

```
Hotkey fires
  → ShortcutEngine.handle(binding)
  → SpaceLocator.spaceIndex(forBundleID: …)          // e.g. 3
  → ISSCore.index(3)                                  // in-process, instant
  → NSRunningApplication.activate(bundleID: …)        // or NSWorkspace.open if not running
```

Fallback: if `SpaceLocator` returns `nil` (CGS unavailable or no window found), skip the ISS call and just `activate` — macOS will do its animated switch. Degraded, not broken.

### Space-only binding (`SpaceBinding`)

```
Hotkey fires
  → ShortcutEngine.handle(binding)
  → ISSCore.index(spaceIndex)
```

### System override

```
CGEventTap sees Ctrl+← / Ctrl+→ / Ctrl+1..9
  → swallow the event
  → ShortcutEngine.systemOverride(.left | .right | .index(n))
  → ISSCore.left() / .right() / .index(n)
```

## Data model

Persisted at `~/Library/Application Support/InstantSwitcher/config.json`. Written atomically on change, loaded on launch.

```swift
struct Config: Codable {
    var schemaVersion: Int          // currently 1
    var bindings: [Binding]
    var systemOverrides: SystemOverrides
    var launchAtLogin: Bool
}

enum Binding: Codable, Identifiable {
    case app(AppBinding)
    case space(SpaceBinding)
    var id: UUID { … }
}

struct AppBinding: Codable, Identifiable {
    let id: UUID
    var bundleIdentifier: String    // "com.tinyspeck.slackmacgap"
    var displayName: String         // cached from the app's Info.plist
    var iconPath: String?           // cached resolved icon path
    // Hotkey combo stored by KeyboardShortcuts in UserDefaults, keyed by id.
}

struct SpaceBinding: Codable, Identifiable {
    let id: UUID
    var spaceIndex: Int             // 1-based (we subtract 1 when calling iss_switch_to_index)
    var label: String               // user-visible, e.g. "Comms"
}

struct SystemOverrides: Codable {
    var arrows: Bool   // default: true
    var digits: Bool   // default: false
}
```

Notes:

- App identity = bundle ID, never path — surviving app moves/renames.
- Hotkey combos live in `UserDefaults` (owned by `KeyboardShortcuts`), keyed by the binding's `UUID`. Our JSON is the source of truth for *which* bindings exist.
- Migration policy: unknown `schemaVersion` → rename file to `config.json.backup-<timestamp>` and start fresh.
- No Keychain, no network, no telemetry.
- Upstream `iss_switch_to_index` uses **0-based** indices. Our UI and storage are 1-based (matches how users count spaces). `ISSCore.index(_:)` translates.

## UI

### Menu bar dropdown (left click)

- Header: "Current space: N / M" (best-effort from `ISSCore.currentSpaceInfo()`; hidden if unavailable).
- Section: each binding as a clickable row (icon/label + hotkey). Clicking fires it — useful for testing without the hotkey.
- Toggles: `Override Ctrl+Arrows`, `Override Ctrl+1..9`.
- Footer: `Settings…`, `Quit`.

### Settings window (`Cmd+,`)

Three tabs:

1. **Shortcuts** (primary)
   - Single ordered list of bindings (drag to reorder).
   - `+` button → menu: *Add app shortcut* / *Add space shortcut*.
   - Each row: drag handle, type icon, type-specific fields (app picker or space-index stepper + label), `KeyboardShortcuts.Recorder`, delete.
   - Empty-state explainer + two "Add" buttons.

2. **System**
   - Override toggles (Arrows, Digits).
   - Banner that appears after enabling an override if Accessibility is not yet granted, with "Open Accessibility Settings" button.
   - Banner reminding the user to disable the native Mission Control shortcut, with "Open Keyboard Shortcuts" button.
   - "Launch at login" toggle (`SMAppService`).

3. **About**
   - App version.
   - ISS core status: "Initialized" (green ✓) or "Not initialized — Accessibility required" (yellow ⚠), with a "Retry" button.
   - Credit: "Powered by InstantSpaceSwitcher (MIT) by jurplel" with link to upstream.
   - Link to our GitHub repo + license view.

### App picker

- Primary: native `NSOpenPanel` scoped to `.app` bundles under `/Applications`. We read `CFBundleIdentifier`, `CFBundleDisplayName`, and the icon from the chosen bundle's `Info.plist`.
- Secondary: "Pick from running apps" submenu populated from `NSWorkspace.shared.runningApplications` for quick selection of common cases.

## Permissions

Requested lazily:

- **Accessibility** — required in two places: (a) `iss_init()` (upstream ISS creates its own event tap), (b) our `SystemOverride` event tap. Both are satisfied by a single Accessibility grant for `InstantSwitcher.app`.
  - Prompted on first launch if the user attempts any shortcut; retried when they enable the first override toggle.
  - If denied: `ISSCore.isInitialized == false`, bindings fall back to plain `activate()` for app shortcuts and are no-ops for space-only bindings. The About tab surfaces a "Retry" button.
- **Screen Recording** — **not** required.
- **Input Monitoring** — not required.

## Error handling & edge cases

- **ISS init fails** (Accessibility not granted) — bindings degrade as described above. About tab shows yellow status + Retry. We surface a one-shot "Grant Accessibility" prompt in the menu-bar dropdown on the first hotkey fire after failure.
- **CGS symbol resolution fails** — `SpaceLocator` returns `nil`; app-focus bindings fall back to plain `activate()`. Logged via `os.Logger` category `cgs`.
- **App not running** on focus hit — `NSWorkspace.openApplication(at:configuration:)` to launch; we defer space-jump/activation to the caller's standard path (macOS will handle focus). If discovering the target space proves unreliable for launches, a follow-up can add a one-time post-launch listener.
- **App has no windows on any space** (e.g. minimized-to-Dock only) — skip `ISSCore.index`, just `activate`.
- **Duplicate hotkey** — `KeyboardShortcuts` surfaces a conflict error; display inline on the row.
- **Bound app deleted** — row renders in a red "missing" state; still editable/removable; hotkey no-ops with a toast.
- **Rapid-fire hotkey** — `ISSCore` calls are cheap and synchronous; no additional throttling needed.

## Logging

- `os.Logger` subsystem `com.theosardin.instantswitcher`.
- Categories: `hotkey`, `cgs`, `iss`, `override`.
- No in-app log viewer — visible in `Console.app`.

## Testing

- `SpaceLocator` and `ISSCore` defined behind protocols (`SpaceLocating`, `ISSInvoking`) so they're stubbable.
- XCTest target covers:
  - `Config` codable round-trip and schema-migration fallback.
  - `ShortcutEngine` orchestration (locate → jump → activate) with stubbed locator/core/activator.
  - `ConfigStore` atomic-write + corrupt-file backup + schema-mismatch backup.
- Not automated: real global hotkeys, real CGS calls, real `CGEventTap`, real `iss_*` calls (they require Accessibility + a live session). A manual smoke checklist is kept in `docs/testing.md`:
  - App binding focuses the right app on the right space.
  - Space binding jumps without focusing any app.
  - Override Arrows routes Ctrl+←/→ through ISS.
  - Override Digits routes Ctrl+1..9 through ISS.
  - Accessibility denied → degraded state, Retry works after grant.
  - Deleted bound app → missing state.
  - Toggle launch-at-login → reboot → app auto-launches.

## Project layout

```
instant-switcher/
├── project.yml                                 # xcodegen manifest
├── .gitignore
├── README.md
├── Vendor/
│   └── InstantSpaceSwitcher/
│       ├── LICENSE                             # upstream MIT
│       ├── UPSTREAM.md                         # origin URL, commit SHA, what we took
│       └── Sources/ISS/
│           ├── ISS.c                           # verbatim from upstream
│           └── include/ISS.h                   # verbatim from upstream
├── InstantSwitcher/
│   ├── App/                  InstantSwitcherApp.swift, MenuBarView.swift, AppState.swift
│   ├── Settings/             SettingsWindow.swift, ShortcutsTab.swift, SystemTab.swift, AboutTab.swift, AppPickerView.swift
│   ├── Engine/               ShortcutEngine.swift, SystemOverride.swift
│   ├── Services/             ISSCore.swift, SpaceLocator.swift, ConfigStore.swift, LaunchAtLogin.swift, ShortcutNames.swift, Permissions.swift
│   ├── Models/               Config.swift, Binding.swift
│   ├── Bridging/             InstantSwitcher-Bridging-Header.h   # #import "ISS.h"
│   └── Resources/            Assets.xcassets, Info.plist, InstantSwitcher.entitlements
├── InstantSwitcherTests/
└── docs/
    ├── superpowers/specs/2026-04-13-instant-switcher-wrapper-design.md
    ├── superpowers/plans/2026-04-13-instant-switcher-implementation.md
    └── testing.md
```

## Distribution

- `./scripts/build-dmg.sh` — build Release, strip, sign with local identity, bundle into a DMG at `build/InstantSwitcher.dmg`. Documented in README.
- No notarization in v0 (local distribution). Can be added later.

## Open questions (none blocking)

- Bundle ID: `com.theosardin.instantswitcher`. Change at will.
- App icon: placeholder at first, swappable later.

## Acceptance criteria

1. Opening the app adds a menu-bar icon and no Dock icon.
2. I can add an app shortcut by picking an `.app`, assigning a hotkey, and pressing the hotkey focuses that app on its current space with no visible animated swipe.
3. I can add a space shortcut for index N and the hotkey instantly jumps to space N.
4. Toggling "Override Ctrl+Arrows" makes Ctrl+← / Ctrl+→ instant (after disabling the native shortcut in System Settings, per the in-app banner).
5. Toggling "Override Ctrl+1..9" makes those instant likewise.
6. If the user denies Accessibility, the app degrades gracefully (no crash) and the About tab shows a clear "Retry" path.
7. Config survives restart; hotkey rebinds persist; `launchAtLogin` flag takes effect across reboots.
8. `./scripts/build-dmg.sh` produces a single `.dmg` containing `InstantSwitcher.app` with the upstream MIT `LICENSE` visible in About and embedded in the bundle.
