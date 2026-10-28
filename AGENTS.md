# Dok Project Guide

## Product

Dok is a free macOS 13+ radial launcher for apps, files, folders, websites, and system Now Playing controls. The user-facing name is `Dok`; keep `com.qingshan.orbis` for update compatibility. macOS 26 uses native Liquid Glass; macOS 13–15 use the compatibility material.

## Run And Verify

```bash
swift build -c release
for test in work/*-test.py; do python3 "$test" || exit 1; done
xcodebuild -project dok.xcodeproj -scheme dok -configuration Release build CODE_SIGNING_ALLOWED=NO
```

The installed development copy is `/Applications/Dok.app`. Build successfully before replacing it, then ad-hoc sign and verify the local copy.

## Stack And Structure

- SwiftUI + AppKit, Swift 5 language mode, macOS 13 deployment target, Universal 2 (`arm64` + `x86_64`) release binary.
- `Sources/dok/DokApp.swift`: lifecycle, hotkey, mouse trigger, status item, settings window.
- `Sources/dok/DokWheelView.swift`: wheel layout, glass layers, center music UI.
- `Sources/dok/DokWheelWindow.swift`: window placement, hit testing, launch and dismiss behavior.
- `Sources/dok/NowPlayingService.swift`: now-playing state; on-demand adapter reads, resident Swift fallback, and media-key controls.
- `Sources/dok/SettingsView.swift`: fixed-size two-tab settings UI.
- `Sources/dok/DockNotificationBadgeReader.swift`: one-shot Dock Accessibility badge snapshot (silent, 100ms bound).
- `Sources/dok/QQMusicTitleReader.swift`: reads QQ Music's play-bar accessibility description (`歌曲名：… - 歌手名：…`), which changes ~0.3s after a skip versus MediaRemote's ~0.7s. Used only to confirm a skip was accepted (cancelling the resend); it never drives the display. Returns nil without Accessibility permission or if QQ changes its UI.
- `Vendor/MediaRemoteAdapter/`: vendored BSD-3 framework sources + perl script (see its README). Built by the `MediaRemoteAdapter` target, embedded in the app, loaded at runtime by `/usr/bin/perl` — never linked.
- `Resources/*lproj`: English and Simplified Chinese strings; UI follows macOS language.
- `work/*-test.py`: source-contract regression suite.

## Now Playing Backends (priority order)

1. In-process direct MediaRemote read — instant, works only where macOS still allows it.
2. perl adapter — bundled `MediaRemoteAdapter.framework` run via the Apple-signed system perl. Works for every user. **On demand only**: summoning the wheel shows the cached track and starts `stream --no-diff` (first full snapshot ~20ms), which pushes changes the moment the system announces them; the stream also runs while a play intent is pending, and is terminated when the wheel hides. One-shot `get` warms the cache at startup and after wake. No resident perl process.
   QQ Music publishes a new track to MediaRemote ~0.7s after a skip and has no scripting interface, so ~0.7s is the floor. The wheel renders `trackCard` (title, artist and artwork as one unit). A new track's card commits only once its cover is present (or after 0.6s without one); late or replaced covers on the same card crossfade in place, and identical artwork bytes keep the same image object. A committed card pushes in only when the user is watching — after the wheel's first snapshot of this summon, or after the user's own skip; a track that changed while the wheel was hidden appears directly on summon, without a push. A pushed card: old and new cards stay edge to edge and move together by the card width (left for next and player-side changes, right for previous) on a 0.46s curve, with 14pt gradient-masked edges (no blur; Reduce Motion uses a fade). QQ Music silently drops skip commands while switching (dropped 0.24s after it reports the new track, accepted at 0.54s) and sometimes at random. `isSkipLocked` runs from a press until the card commits (2s cap): previous/next show at 0.3 opacity without hover, a locked press sends nothing and shakes the button, presses are never queued, and buttons unlock on the push curve. `skipCommandReadyAt` (0.6s after the reported change) defers a press made right after unlock. If no change is confirmed within 0.8s (QQ play bar readable) or 1.4s (MediaRemote only), the command is resent exactly once. A title wider than the card plays a one-time reveal while the wheel is visible: after 0.6s it eases left (30pt/s) until the artist's end is visible, pauses 0.3s, eases back to the start at the 14pt fade inset, and stops — never a looping marquee. It replays for each new card and each summon; titles that fit stay centered and Reduce Motion keeps tail truncation. The title's width is computed synchronously (NSFont, same size and weight) so a new card's first frame already has its final layout; measuring after layout made long titles snap from centered to leading mid-push. Play state from a new-track snapshot bypasses the 1.5s post-command freeze, and state received during a freeze is re-applied when it ends (the stream does not resend).
3. Swift toolchain — legacy resident script on a real CLT/Xcode Swift binary. Runs only when perl is missing or 3 consecutive `get`s fail, and stops once a `get` succeeds again. Self-heals: quick exits retry with 30s→5min doubling backoff, system wake restarts it, and a summon with a running player but no track restarts it.

There is no in-app diagnostics row (removed at the user's request); Dok's NSLog output does not reach the unified log on macOS 27, so debug with temporary instrumentation. When the perl adapter is active, playback controls use its one-shot MediaRemote `send` command; system media keys are fallback only. Placeholder play records a 12-second, bundle-targeted intent and brings the preferred running player to the foreground; the perl helper consumes the intent once that player exposes a controllable session. This preserves explicit player selection while preventing an ownerless media key from launching Apple Music.

## Project Rules

- `dok.xcodeproj` is hand-adjusted after XcodeGen (e.g. product `Dok.app`); `xcodegen generate` would rename the product to `dok.app`. Add new source files to the pbxproj by hand instead of regenerating.

- Do not rename the bundle identifier without an explicit migration plan.
- Keep every product feature free; do not add feature gates, purchase flows, or account requirements.
- `Arcly`, `Orbis`, and `PieMenu` may appear only in compatibility identifiers, legacy-data migration code, or documents explicitly marked as historical.
- Preserve the native `NSGlassEffectView` sampling base unchanged on macOS 26. On macOS 13–15, use the isolated `NSVisualEffectView` compatibility path; compatibility work must not alter the macOS 26 rendering branch.
- Keep one persistent wheel window to avoid presentation flashing and desktop re-open failures.
- Settings are `920pt` wide with only Wheel and General tabs. Height follows the current page: each tab reports its natural height (`SettingsContentHeightKey`, per tab), and on a tab switch the window starts resizing immediately to the known height of the new tab, keeping the top edge, in step with the content crossfade (0.32s, curve 0.32/0.72/0/1 on both sides). Each tab's window height is remembered (`dok.settings.windowHeight.<tab>`) and the window opens at it; the first measurement after opening only corrects the size without animating, so reopening never plays a resize. Spacing uses an 8pt grid (8/12/16/24): every page starts top-left at the 24pt content inset, aligned with the first sidebar row; nothing is vertically centered. The sidebar footer shows `Dok <version> (<build>)`. Menu items and button titles carry no trailing ellipsis.
- Settings use a fixed `216pt` in-window sidebar and one continuous root surface. Keep navigation rows at `34pt`, setting rows at `44pt`, trailing controls at `130pt`, dividers at `0.5pt`, and all selection/action states monochrome through semantic primary/secondary fills. Do not restore the old preference toolbar, nested white cards, colored accents, decorative shadows, or springy settings animations.
- Music metadata uses the private MediaRemote framework. Keep it in self-distributed builds only; an App Store target must compile it out rather than hide it at runtime.
- Build, run all contract tests, install, sign, and visually inspect both settings tabs after UI changes.
- Do not commit or push unless the user explicitly asks.

## Current State (2026-09-21)

- Source version is 1.5.1 (build 13), Developer ID-signed release without Apple notarization; one Universal 2 build supports macOS 13+, Apple Silicon, and Intel. macOS 26 retains the approved native Liquid Glass branch; macOS 13–15 use the isolated compatibility material.
- All features are free. The source contains no Pro tier, StoreKit manager, purchase flow, or paywall.
- Licensed GPL-3.0; `Vendor/MediaRemoteAdapter` is BSD-3 and its notices must be retained.
- The `/usr/bin/swift` shim is forbidden. The swift-toolchain helper may run only with a real CLT/Xcode Swift binary and is a fallback behind the perl adapter.
- On macOS 27+, wheel and satellites use user-selected untinted native `.regular` glass at full alpha with no local opacity override (system preference response confirmed in an offscreen comparison; live slider verification remains pending); settings hide the opacity row entirely (nothing to adjust). macOS 26 retains untinted `.clear` with local opacity adjustment; macOS 13–15 retain compatibility material. Preserve native edges without a second bounds mask, plus the existing `0.55pt` white supplement.
- App icon: the ripple — one clear droplet and one luminous ring (8 faint glints for the 8 slots) on a deep ink tile. `work/generate-dok-app-icon.py` rebuilds everything from `work/dok-icon-source.webp`: full-bleed `AppIcon.icon` art for macOS 26+ (system shape and rim), a pre-shaped squircle icon set with a faint top rim for macOS 13–15, simplified 16/32px marks, and `AppIcon.icns`. Do not hand-edit the generated PNGs.
- Center names: apps and recent-app satellites never show a name (they are familiar by icon); hovering one keeps the music controller or gear in place. Files/folders, web links and key actions show a two-line capsule — name, plus what tells similar items apart: the parent folder, the domain without `www.`, or the key combination as outlined caps. It appears only after a 0.15s dwell so sweeping across does not flash; once shown, moving to another such item switches immediately; leaving restores the center at once.
- Music progress: the junction between the inner lens and the outer ring is itself the track — nothing else is drawn there (gray tracks, dark grooves, double lines, stacked glass and full-circle lighting were all tried and rejected). The played part is rendered by the system itself: on macOS 26+ a `.glassEffect(.clear, in: ProgressArcBand(...))` band shaped like a stream of liquid water (body 2.5pt; 4pt read as too thick): the tail tapers from 60% over the first 12pt, and the leading end swells into a 1.45× droplet over the last 10pt, as one closed outline. The glass carries a barely-cool, near-colorless tint (`Color(0.86, 0.94, 1.0)` at 16%; 18% white read as white frost, `Color(0.70, 0.90, 1.0)` read as cyan) so the native dark rim (which reads as a black outline on so thin a shape) washes out. A 0.6pt `.plusLighter` glint is nudged toward the light and appears only top-left; opposite it, a softer, wider (1.1pt), faintly cyan caustic is nudged away from the light and appears only bottom-right — light gathered on the far side is what makes it read as water rather than glass or plastic. Hover is a jelly touch, not a thickening: width springs 2.5→3.1pt (response 0.38, damping 0.42) and back; width is animatable and the centerline stays fixed on the junction straddling the junction, so its rim highlight, refraction and lighting are native. Every hand-drawn highlight (uniform white, angular white, white + dark groove, blended gray) read as paint and was rejected; `.regular` glass on the wheel's glass is invisible. Below macOS 26 it falls back to a 1pt white `.plusLighter` arc. No blur, no head dot, no ticks. It advances every frame while playing (TimelineView `.animation`, paused when not playing or hidden). Tap-to-seek uses the perl adapter's one-shot `seek`; helper drift under 1.5s converges at 8% per tick. The settings gear is quiet at rest and deepens to secondary on hover.
- Wheel extras: right-clicking a running app slot shows a single localized Quit item; up to 4 recent-content satellites (default 2) sit outside the wheel at 6 o'clock and include apps plus folders opened through dok, while files and websites stay fixed-slot only; satellites carry no clock badge; Dock notification badges render on app slots and satellites, snapshotted once per summon, silently absent without Accessibility permission.
- GitHub v1.5.1 distributes `Dok-1.5.1.dmg`, Developer ID-signed but not Apple-notarized by user decision. `dist/dok-1.3.0.dmg` is the historical notarized package.

## Wheel Visibility (2026-10-28)

- `DokWheelWindow.Presentation` (`hidden/revealing/shown/dismissing`) is the single visibility state; `AppDelegate.isMenuOpen` derives from it. All hiding goes through `finishHiding()`.
- A hidden wheel stays at `windowWarmupAlpha`: the native glass ignores SwiftUI content opacity, so a hidden window at alpha 1 shows as an empty glass disc if anything orders it in. An `order(_:relativeTo:)` override and a 0.1s guard (content invisible > 0.2s ⇒ order out) back this up.
- Window level is `.popUpMenu` with `.fullScreenAuxiliary` (was `CGShieldingWindowLevel`); verify on full-screen apps.

## Next Release

Verify the perl adapter on a Mac without developer tools and monitor GitHub release feedback.

## Settings Motion (1.4.1)

- Settings → Wheel: the right column is one card exactly as tall as the preview (top and bottom edges aligned): Add and Recent content at the top, Restore Defaults pinned to the bottom. Adding and editing swap this same card's content for a panel while the preview stays live. “Add” opens it with a segmented Apps / Files / Website / Keys control: apps are a searchable inline list (click to add, keep adding; added ones show a check), files and folders are one kind (drop zone, or Choose → one open panel allowing both), websites and keyboard actions are inline forms whose Add clears the form for the next one. Editing a website or keyboard action (center button or context menu) opens the same panel; Save closes it, Done (Esc) closes it. No sheets, menus, overlays or full-page swaps for adding. Restore Defaults expands in place into Cancel/Restore and collapses after 4s without acting (never while hovered); preview icons have a context menu (edit, replace, show in Finder, remove with undo). No `NSAlert` in settings.
- Size sliders snap to their steps live while dragging (radius step 5, icon step 2), so the shown value is the released value; each step plays a level-change haptic and the default step (radius 110, icon 48, opacity 100%, marked with a tick) plays an alignment haptic. Double-click resets to the default.
- Keyboard action form (inside the panel): The combination is the hero (large monochrome keycaps; dashed prompt when empty; breathing border while recording); a transparent native `KeyActionRecorderControl` (`drawsChrome = false`) handles capture. Name is optional (empty → “target app + combo” or the combo); “Switch to” is a native menu of none / running apps / choose another; pill Cancel/Save, Return saves, Esc cancels (Esc while recording only cancels recording). All General-tab switches use the same custom switch; General → System shows the version.
- Segmented controls, recent-content switch, and setting sliders use custom SwiftUI visuals with explicit movement; native glass is unchanged. Respect Reduce Motion. Builds and regression checks passed; live animation verification remains pending.
