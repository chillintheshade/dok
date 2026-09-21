# dok Project Guide

## Product

dok is a free macOS 13+ radial launcher for apps, files, folders, websites, and system Now Playing controls. The user-facing name is always lowercase `dok`; keep `com.qingshan.orbis` for update compatibility. macOS 26 uses native Liquid Glass; macOS 13–15 use the compatibility material.

## Run And Verify

```bash
swift build -c release
for test in work/*-test.py; do python3 "$test" || exit 1; done
xcodebuild -project dok.xcodeproj -scheme dok -configuration Release build CODE_SIGNING_ALLOWED=NO
```

The installed development copy is `/Applications/dok.app`. Build successfully before replacing it, then ad-hoc sign and verify the local copy.

## Stack And Structure

- SwiftUI + AppKit, Swift 5 language mode, macOS 13 deployment target, Universal 2 (`arm64` + `x86_64`) release binary.
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
- Preserve the native `NSGlassEffectView` sampling base unchanged on macOS 26. On macOS 13–15, use the isolated `NSVisualEffectView` compatibility path; compatibility work must not alter the macOS 26 rendering branch.
- Keep one persistent wheel window to avoid presentation flashing and desktop re-open failures.
- Keep settings at `920 x 520` with only Wheel and General tabs unless the product scope changes.
- Settings use a fixed `216pt` in-window sidebar and one continuous root surface. Keep navigation rows at `34pt`, setting rows at `44pt`, trailing controls at `130pt`, dividers at `0.5pt`, and all selection/action states monochrome through semantic primary/secondary fills. Do not restore the old preference toolbar, nested white cards, colored accents, decorative shadows, or springy settings animations.
- Music metadata uses the private MediaRemote framework. Keep it in self-distributed builds only; an App Store target must compile it out rather than hide it at runtime.
- Build, run all contract tests, install, sign, and visually inspect both settings tabs after UI changes.
- Do not commit or push unless the user explicitly asks.

## Current State (2026-09-21)

- Source version is 1.4.1 (build 10), Developer ID-signed release without Apple notarization; one Universal 2 build supports macOS 13+, Apple Silicon, and Intel. macOS 26 retains the approved native Liquid Glass branch; macOS 13–15 use the isolated compatibility material.
- All features are free. The source contains no Pro tier, StoreKit manager, purchase flow, or paywall.
- Licensed GPL-3.0; `Vendor/MediaRemoteAdapter` is BSD-3 and its notices must be retained.
- The `/usr/bin/swift` shim is forbidden. The swift-toolchain helper may run only with a real CLT/Xcode Swift binary and is a fallback behind the perl adapter.
- On macOS 27+, wheel and satellites use user-selected untinted native `.regular` glass at full alpha with no local opacity override (system preference response confirmed in an offscreen comparison; live slider verification remains pending); settings display “Follows System” instead of a local opacity slider. macOS 26 retains untinted `.clear` with local opacity adjustment; macOS 13–15 retain compatibility material. Preserve native edges without a second bounds mask, plus the existing `0.55pt` white supplement.
- Music progress is a minimal played-arc ring at the center boundary (no track, no boundary circle, no head dot) with tap-to-seek via the perl adapter's one-shot `seek` command; helper drift under 1.5s converges at 8% per tick.
- Wheel extras: right-clicking a running app slot shows a single localized Quit item; up to 4 recent-content satellites (default 2) sit outside the wheel at 6 o'clock and include apps plus folders opened through dok, while files and websites stay fixed-slot only; Dock notification badges render on app slots and satellites, snapshotted once per summon, silently absent without Accessibility permission.
- GitHub v1.4.1 distributes `dok-1.4.1.dmg`, Developer ID-signed but not Apple-notarized by user decision. `dist/dok-1.3.0.dmg` is the historical notarized package.

## Next Release

Verify the perl adapter on a Mac without developer tools and monitor GitHub release feedback.

## Settings Motion (1.4.1)

- Segmented controls, recent-content switch, and setting sliders use custom SwiftUI visuals with explicit movement; native glass is unchanged. Respect Reduce Motion. Builds and regression checks passed; live animation verification remains pending.
