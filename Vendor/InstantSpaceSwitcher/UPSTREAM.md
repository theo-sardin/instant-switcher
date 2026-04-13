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
