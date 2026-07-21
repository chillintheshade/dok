# Center Music Controller Design

> **Status: historical design record (2026-07-20).** The implemented refresh, stale-retention, scaling, and settings behavior has evolved beyond this document. Use `NowPlayingService.swift`, `ArclyWheelView.swift`, and the Now Playing contract tests as the current source of truth.

## Overview

Add a mini music controller to the Arcly center area. When system media is playing, the center circle shows album art, track name, and playback controls instead of the gear icon. Does not occupy any app slot.

## Center Area State Machine

| State | Content |
|-------|---------|
| No music + no selection | Gear icon (current behavior) |
| Music playing + no selection | Music controller + small gear at bottom |
| App selected (any) | App name capsule (gear and music both hidden) |

## Music Controller Layout

Within the center circle (~120pt diameter):

```
    ┌─────────────┐
    │  [Album Art] │  ~40pt rounded square
    │   Song Name  │  single line, truncated, 10pt
    │  ⏮  ▶⏸  ⏭  │  playback controls
    │     ⚙︎       │  mini gear, 10pt
    └─────────────┘
```

## Technical Approach

### MRMediaRemote (Private Framework)

Load dynamically at runtime via `dlopen`/`dlsym`:

- `MRMediaRemoteGetNowPlayingInfo` — get track name, artist, album art, playback state
- `MRMediaRemoteSendCommand(.togglePlayPause)` — play/pause
- `MRMediaRemoteSendCommand(.nextTrack)` — next track
- `MRMediaRemoteSendCommand(.previousTrack)` — previous track
- `MRMediaRemoteRegisterForNowPlayingNotifications` — register for change notifications

### NowPlayingService

A new `ObservableObject` class that:

1. Exposes `@Published` properties: `isPlaying`, `trackName`, `artistName`, `albumArt` (NSImage?), `hasNowPlaying` (bool)
2. On `startObserving()`: registers for `kMRMediaRemoteNowPlayingInfoDidChangeNotification` and fetches initial state
3. On `stopObserving()`: removes notification observer
4. Provides methods: `togglePlayPause()`, `nextTrack()`, `previousTrack()`

### Integration Points

- `ArclyWheelView.centerContent`: check `nowPlayingService.hasNowPlaying` to decide which view to show
- `ArclyWheelWindow` or `ArclyApp`: call `startObserving()` when menu opens, `stopObserving()` when menu closes
- `AppState` holds the `NowPlayingService` instance

### Animations

- Gear <-> music controller transition: `.transition(.scale(scale: 0.75).combined(with: .opacity))` with `.spring(response: 0.25, dampingFraction: 0.7)`
- Consistent with existing center content transitions
- Album art appears with slight scale-up spring

## New Files

- `Sources/Arcly/NowPlayingService.swift` — MRMediaRemote wrapper + ObservableObject

## Modified Files

- `ArclyWheelView.swift` — update `centerContent` to include music controller view
- `ArclyApp.swift` — wire up start/stop observing on menu open/close
- `AppState.swift` — hold NowPlayingService instance

## Scope

- Controls all apps that register with macOS Now Playing (Apple Music, Spotify, QQ Music, NetEase Cloud Music, browser media, etc.)
- No settings UI for music control in v1 — always active when media is playing
- No volume control — only playback (play/pause, next, previous)
