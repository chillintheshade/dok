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
- `Sources/Arcly/NowPlayingService.swift`: MediaRemote metadata and control refresh.
- `Sources/Arcly/SettingsView.swift`: fixed-size two-tab settings UI.
- `Resources/*lproj`: English and Simplified Chinese strings; UI follows macOS language.
- `work/*-test.py`: source-contract regression suite.

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
- The `/usr/bin/swift` shim is forbidden. The optional music helper may run only with a real CLT/Xcode Swift binary; direct MediaRemote reading remains the primary path.
- `dist/Arcly-1.0.1.dmg` is an older valid signed package and does not contain the current uncommitted fixes.
- App Store copy under `docs/appstore/` must describe one free feature set with no in-app purchases.

## Next Release

Refresh GitHub screenshots, choose an open-source license, build a new DMG, notarize it, verify on a clean Mac account, then publish a release.
