# instant-switcher

macOS menu bar app for instant space switching. No sliding animation, ever. This is REALLY hacky, it basically simulates super fast gestures.

- **App hotkeys** — bind a key combo to an app, press it, instantly jump to that app's space and focus it.
- **Space hotkeys** — bind a key combo to a space number, press it, go there.
- **Override Ctrl+Arrows / Ctrl+1..9** — replace macOS's animated space switch with instant ones.
- **Swipe override** — make trackpad swipes between spaces instant too.
- **Import from Apptivate** — one-click import of your existing Apptivate shortcuts.

Built on [InstantSpaceSwitcher](https://github.com/jurplel/InstantSpaceSwitcher) (MIT, vendored).

## Install

Grab the `.dmg` from the [latest release](https://github.com/theo-sardin/instant-switcher/releases), drag to Applications, open, grant Accessibility when prompted.

If after granting the permissions it doesn't immediately work, try restarting and on/off toggling the settings you need.

## Build from source

    brew install xcodegen
    xcodegen generate
    xcodebuild -scheme InstantSwitcher -configuration Release -derivedDataPath build build
    open build/Build/Products/Release/InstantSwitcher.app

## Package a DMG

    ./scripts/build-dmg.sh

## Permissions

Accessibility only. No Screen Recording, no Input Monitoring.

## Tests

    xcodebuild -scheme InstantSwitcher test -derivedDataPath build

## Credits

Powered by [jurplel/InstantSpaceSwitcher](https://github.com/jurplel/InstantSpaceSwitcher) (MIT).
