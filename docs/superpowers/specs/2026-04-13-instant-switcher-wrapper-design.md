# Instant Switcher — Design Spec

**Date:** 2026-04-13
**Status:** Draft, awaiting implementation plan

## Summary

A small native macOS menu-bar app (`InstantSwitcher.app`) that wraps the existing `ISSCli` shipped inside `InstantSpaceSwitcher.app`. It lets the user:

1. Define global hotkeys that instantly jump to the space a specific app lives on and focus that app (replacing Apptivate + avoiding macOS's animated space switch).
2. Define global hotkeys that jump to a specific space index (no app focus).
3. Optionally override macOS's native space-switching shortcuts (Ctrl+Arrows, Ctrl+1..9) so they route through `ISSCli` and are instant.

`InstantSpaceSwitcher.app` remains a hard runtime dependency — this wrapper only orchestrates; it does not reimplement space switching.

## Non-goals

- Reimplementing ISS's instant-switch behavior. We shell out to `ISSCli` and trust it.
- Trackpad swipe gesture overrides (too invasive, low value).
- Syncing config across machines, Keychain, network, or telemetry.
- An in-app log viewer (use Console.app).
- Auto-updating / self-updater.

## Architecture

Single SwiftUI app, `LSUIElement = YES`, deployment target macOS 13 (matches ISS).

Internal modules:

- **ShortcutEngine** — registers global hotkeys via the `KeyboardShortcuts` Swift package (Sindre Sorhus). Dispatches actions to the binding handlers.
- **SpaceLocator** — wraps private CoreGraphics/SkyLight (CGS) APIs to answer *"which space index does app X's frontmost window live on?"*. Isolated to one file so a future macOS upgrade breaking CGS is contained.
- **ISSRunner** — thin wrapper around `Process` that invokes `/Applications/InstantSpaceSwitcher.app/Contents/MacOS/ISSCli`. Validates existence on launch and before each call.
- **SystemOverride** — optional `CGEventTap` that swallows Ctrl+Arrow and Ctrl+Digit key events and re-emits them as `ShortcutEngine` actions.

UI surface:

- `MenuBarExtra` for the menu-bar icon + dropdown.
- A separate `Settings` scene for editing bindings and toggles.

## Data flow

### Focus-app binding (`AppBinding`)

```
Hotkey fires
  → ShortcutEngine.handle(binding)
  → SpaceLocator.spaceIndex(forBundleID: …)   // e.g. 3
  → ISSRunner.run(["index", "3"])             // instant, no animation
  → NSRunningApplication.activate(bundleID: …) // or NSWorkspace.open if not running
```

Fallback: if `SpaceLocator` returns `nil` (CGS unavailable or no window found), skip the `ISSCli` call and just `activate` — macOS will do its animated switch. Degraded, not broken.

### Space-only binding (`SpaceBinding`)

```
Hotkey fires
  → ShortcutEngine.handle(binding)
  → ISSRunner.run(["index", "\(spaceIndex)"])
```

### System override

```
CGEventTap sees Ctrl+← / Ctrl+→ / Ctrl+1..9
  → swallow the event
  → ShortcutEngine.systemOverride(.left | .right | .index(n))
  → ISSRunner.run(["left" | "right" | "index", "\(n)"])
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
    var spaceIndex: Int             // 1-based, matches `ISSCli index N`
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

## UI

### Menu bar dropdown (left click)

- Header: "Current space: N" (best-effort from `SpaceLocator.currentSpaceIndex()`; hidden if unavailable).
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
   - Banner that appears after enabling an override if the corresponding native shortcut is still active in System Settings, with "Open System Settings → Keyboard Shortcuts" button.
   - "Launch at login" toggle (`SMAppService`).

3. **About**
   - Version, ISS path, ISS detection status (green ✓ / red ✗ with download link).
   - Credits, GitHub link.

### App picker

- Primary: native `NSOpenPanel` scoped to `.app` bundles under `/Applications`. We read `CFBundleIdentifier`, `CFBundleDisplayName`, and the icon from the chosen bundle's `Info.plist`.
- Secondary: "Pick from running apps" submenu populated from `NSWorkspace.shared.runningApplications` for quick selection of common cases.

## Permissions

Requested lazily:

- **Accessibility** — required only when the user first enables an override (Arrows or Digits). If the user declines, the toggle reverts and a banner with "Open Accessibility Settings" appears on the System tab.
- **Screen Recording** — **not** required. CGS window/space queries used by `SpaceLocator` do not trip the TCC screen-recording gate.
- **Input Monitoring** — not required. `CGEventTap` at the session level only needs Accessibility.

## Error handling & edge cases

- **ISSCli missing** — startup probe + per-call probe. On miss: menu-bar icon turns red, dropdown shows "InstantSpaceSwitcher.app not found [Download]", bindings fire a non-blocking toast and no-op.
- **CGS symbol resolution fails** — `SpaceLocator` returns `nil`; bindings fall back to plain `activate()` (native animated switch). Logged via `os.Logger` category `cgs`.
- **App not running** on focus hit — `NSWorkspace.open(url:)` to launch, poll up to ~1s for a window to appear, then locate → jump → activate. If still nothing, just leave it to macOS.
- **App has no windows on any space** (e.g. minimized-to-Dock only) — skip `ISSCli`, just `activate`.
- **Duplicate hotkey** — `KeyboardShortcuts` surfaces a conflict error; display inline on the row.
- **Bound app deleted** — row renders in a red "missing" state; still editable/removable; hotkey no-ops with a toast.
- **Rapid-fire hotkey** — `ISSRunner.run` is fire-and-forget on a dedicated serial `DispatchQueue` to avoid overlapping `Process` spawns.

## Logging

- `os.Logger` subsystem `com.theosardin.instantswitcher`.
- Categories: `hotkey`, `cgs`, `iss`, `override`.
- No in-app log viewer — visible in `Console.app`.

## Testing

- `SpaceLocator` and `ISSRunner` defined behind protocols (`SpaceLocating`, `ISSInvoking`) so they're stubbable.
- XCTest target covers:
  - `Config` codable round-trip and schema-migration fallback.
  - `ShortcutEngine` orchestration (locate → jump → activate) with stubbed locator/runner.
  - Duplicate-hotkey conflict handling.
  - JSON file atomic write (write → crash-sim → reload).
- Not automated: real global hotkeys, real CGS calls, real `CGEventTap`. A manual smoke checklist is kept in `docs/testing.md`:
  - App binding focuses the right app on the right space.
  - Space binding jumps without focusing any app.
  - Override Arrows routes Ctrl+←/→ through ISS.
  - Override Digits routes Ctrl+1..9 through ISS.
  - ISS missing → red state + toast.
  - Deleted bound app → missing state.
  - Toggle launch-at-login → reboot → app auto-launches.

## Project layout

```
instant-switcher/
├── InstantSwitcher.xcodeproj
├── InstantSwitcher/
│   ├── App/                 InstantSwitcherApp.swift, MenuBarView.swift
│   ├── Settings/            SettingsWindow.swift, ShortcutsTab.swift, SystemTab.swift, AboutTab.swift
│   ├── Engine/              ShortcutEngine.swift, SystemOverride.swift
│   ├── Services/            ISSRunner.swift, SpaceLocator.swift, ConfigStore.swift, LaunchAtLogin.swift
│   ├── Models/              Config.swift, Binding.swift
│   └── Resources/           Assets.xcassets, Info.plist
├── InstantSwitcherTests/
└── docs/
    └── superpowers/specs/2026-04-13-instant-switcher-wrapper-design.md
```

## Open questions (none blocking)

- Bundle ID: proposed `com.theosardin.instantswitcher`. Change at will.
- App icon: placeholder at first, swappable later.

## Acceptance criteria

1. Opening the app adds a menu-bar icon and no Dock icon.
2. I can add an app shortcut by picking an `.app`, assigning a hotkey, and pressing the hotkey focuses that app on its current space with no visible animated swipe.
3. I can add a space shortcut for index N and the hotkey instantly jumps to space N.
4. Toggling "Override Ctrl+Arrows" makes Ctrl+← / Ctrl+→ instant (after disabling the native shortcut in System Settings, per the in-app banner).
5. Toggling "Override Ctrl+1..9" makes those instant likewise.
6. Removing `InstantSpaceSwitcher.app` produces a red error state in the menu bar and bindings no-op instead of crashing.
7. Config survives restart; hotkey rebinds persist; `launchAtLogin` flag takes effect across reboots.
