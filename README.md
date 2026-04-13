# instant-switcher

macOS menu bar app for fast space switching. Bind a hotkey to an app and it jumps to whatever space that app is on, focuses it, no sliding animation. Bind a hotkey to a space number and it just goes there.

Optionally hijacks `Ctrl+←/→` and `Ctrl+1..9` so those are instant too.

Built on top of [InstantSpaceSwitcher](https://github.com/jurplel/InstantSpaceSwitcher) (MIT). Their C core is vendored under `Vendor/` so this ships as a single `.app`.

## Build

Needs Xcode and xcodegen:

    brew install xcodegen
    xcodegen generate
    xcodebuild -scheme InstantSwitcher -configuration Debug -derivedDataPath build build
    open build/Build/Products/Debug/InstantSwitcher.app

## Package a DMG

    ./scripts/build-dmg.sh

Output lands at `build/InstantSwitcher.dmg`.

## Permissions

Grant Accessibility on first launch (System Settings → Privacy & Security → Accessibility). That's the only one.

## Tests

    xcodebuild -scheme InstantSwitcher test -derivedDataPath build

## Credits

Powered by jurplel/InstantSpaceSwitcher, MIT. See `Vendor/InstantSpaceSwitcher/LICENSE`.
