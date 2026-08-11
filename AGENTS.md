# dok Project Guide

## Product

dok is a free macOS 26 radial launcher for apps, files, folders, websites, and system Now Playing controls. The user-facing name is always lowercase `dok`; keep `com.qingshan.orbis` for update compatibility.

## Run And Verify

```bash
swift build -c release
for test in work/*-test.py; do python3 "$test" || exit 1; done
xcodebuild -project dok.xcodeproj -scheme dok -configuration Release build CODE_SIGNING_ALLOWED=NO
```

The installed development copy is `/Applications/dok.app`. Build successfully before replacing it, then ad-hoc sign and verify the local copy.

## Stack And Structure

- SwiftUI + AppKit, Swift 5 language mode, macOS 26 deployment target.
- `Sources/dok/DokApp.swift`: lifecycle, hotkey, mouse trigger, status item, settings window.
- `Sources/dok/DokWheelView.swift`: wheel layout, glass layers, center music UI.
- `Sources/dok/DokWheelWindow.swift`: window placement, hit testing, launch and dismiss behavior.
- `Sources/dok/NowPlayingService.swift`: now-playing state; resident helper backends and media-key controls.
- `Sources/dok/SettingsView.swift`: fixed-size two-tab settings UI.
- `Sources/dok/DockNotificationBadgeReader.swift`: one-shot Dock Accessibility badge snapshot (silent, 100ms bound).
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
- `Arcly`, `Orbis`, and `PieMenu` may appear only in compatibility identifiers, legacy-data migration code, or documents explicitly marked as historical.
- Preserve the native `NSGlassEffectView` sampling base; tune custom tone and edge layers separately.
- Keep one persistent wheel window to avoid presentation flashing and desktop re-open failures.
- Keep settings at `920 x 520` with only Wheel and General tabs unless the product scope changes.
- Music metadata uses the private MediaRemote framework. Keep it in self-distributed builds only; an App Store target must compile it out rather than hide it at runtime.
- Build, run all contract tests, install, sign, and visually inspect both settings tabs after UI changes.
- Do not commit or push unless the user explicitly asks.

## Current State (2026-08-11)

- App version is 1.2.0; the local source and `/Applications/dok.app` include files, websites, recent-content preview, and the native settings toolbar.
- All features are free. The source contains no Pro tier, StoreKit manager, purchase flow, or paywall.
- Licensed GPL-3.0; `Vendor/MediaRemoteAdapter` is BSD-3 and its notices must be retained.
- The `/usr/bin/swift` shim is forbidden. The swift-toolchain helper may run only with a real CLT/Xcode Swift binary and is a fallback behind the perl adapter.
- Glass look is final: native `.clear` sampling with a `0.03` black tint base, no extra tone layer, native edge plus a single `0.55pt` white supplement. `menuOpacity` maps linearly to material intensity; 100% is the approved look.
- Music progress is a minimal played-arc ring at the center boundary (no track, no boundary circle, no head dot) with tap-to-seek via the perl adapter's one-shot `seek` command; helper drift under 1.5s converges at 8% per tick.
- Wheel extras: right-clicking a running app slot shows a single localized Quit item; up to 4 recent-content satellites (default 2) sit outside the wheel at 6 o'clock and include apps plus folders opened through dok, while files and websites stay fixed-slot only; Dock notification badges render on app slots and satellites, snapshotted once per summon, silently absent without Accessibility permission.
- `dist/dok-1.2.0.dmg` is the current ad-hoc-signed self-distribution package.

## Next Release

Build a new DMG, notarize it once a developer account is available, verify the perl adapter on a Mac without developer tools, then publish a release.
