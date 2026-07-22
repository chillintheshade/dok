# Arcly Project Guide

## Product

Arcly is a free macOS 26 radial launcher for apps, files, folders, and system Now Playing controls. The user-facing name is Arcly; keep `com.qingshan.orbis` for update compatibility.

## Run And Verify

```bash
swift build -c release
for test in work/*-test.py; do python3 "$test" || exit 1; done
xcodebuild -project Arcly.xcodeproj -scheme Arcly -configuration Release build CODE_SIGNING_ALLOWED=NO
```

The installed development copy is `/Applications/Arcly.app`. Build successfully before replacing it, then ad-hoc sign and verify the local copy.

## Stack And Structure

- SwiftUI + AppKit, Swift 5 language mode, macOS 26 deployment target.
- `Sources/Arcly/ArclyApp.swift`: lifecycle, hotkey, mouse trigger, status item, settings window.
- `Sources/Arcly/ArclyWheelView.swift`: wheel layout, glass layers, center music UI.
- `Sources/Arcly/ArclyWheelWindow.swift`: window placement, hit testing, launch and dismiss behavior.
- `Sources/Arcly/NowPlayingService.swift`: now-playing state; resident helper backends and media-key controls.
- `Sources/Arcly/SettingsView.swift`: fixed-size two-tab settings UI.
- `Vendor/MediaRemoteAdapter/`: vendored BSD-3 framework sources + perl script (see its README). Built by the `MediaRemoteAdapter` target, embedded in the app, loaded at runtime by `/usr/bin/perl` — never linked.
- `Resources/*lproj`: English and Simplified Chinese strings; UI follows macOS language.
- `work/*-test.py`: source-contract regression suite.

## Now Playing Backends (priority order)

1. In-process direct MediaRemote read — instant, works only where macOS still allows it.
2. `perlAdapter` — bundled `MediaRemoteAdapter.framework` run via the Apple-signed system perl. Works for every user, streams JSON lines (`stream --no-diff`).
3. `swiftToolchain` — legacy script on a real CLT/Xcode Swift binary. Fallback only.

A backend that exits within 5 seconds of launch is dropped from the queue; the next one is tried. When the perl adapter is active, playback controls use its one-shot MediaRemote `send` command; system media keys are fallback only. Placeholder play records a 12-second, bundle-targeted intent and brings the preferred running player to the foreground; the perl helper consumes the intent once that player exposes a controllable session. This preserves explicit player selection while preventing an ownerless media key from launching Apple Music.

## Project Rules

- Do not rename the bundle identifier without an explicit migration plan.
- Keep every product feature free; do not add feature gates, purchase flows, or account requirements.
- `Orbis` and `PieMenu` may appear only in compatibility identifiers, legacy-data migration code, or documents explicitly marked as historical.
- Preserve the native `NSGlassEffectView` sampling base; tune custom tone and edge layers separately.
- Keep one persistent wheel window to avoid presentation flashing and desktop re-open failures.
- Keep settings at `920 x 520` with only Wheel and General tabs unless the product scope changes.
- Music metadata uses the private MediaRemote framework. Keep it in self-distributed builds only; an App Store target must compile it out rather than hide it at runtime.
- Build, run all contract tests, install, sign, and visually inspect both settings tabs after UI changes.
- Do not commit or push unless the user explicitly asks.

## Current State (2026-07-21)

- App version is 1.0.1; the local source and `/Applications/Arcly.app` include newer wheel and settings fixes.
- All features are free. The source contains no Pro tier, StoreKit manager, purchase flow, or paywall.
- Licensed GPL-3.0; `Vendor/MediaRemoteAdapter` is BSD-3 and its notices must be retained.
- The `/usr/bin/swift` shim is forbidden. The swift-toolchain helper may run only with a real CLT/Xcode Swift binary and is a fallback behind the perl adapter.
- `dist/Arcly-1.0.1.dmg` is an older valid signed package and does not contain the current uncommitted fixes.

## Next Release

Build a new DMG, notarize it once a developer account is available, verify the perl adapter on a Mac without developer tools, then publish a release.
