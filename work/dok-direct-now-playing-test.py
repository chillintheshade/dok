#!/usr/bin/env python3
"""Now-playing 读取、命令路由与占位状态安全契约。"""
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Sources" / "dok" / "NowPlayingService.swift"


def require(source: str, needle: str, reason: str) -> None:
    if needle not in source:
        raise AssertionError(f"Missing {reason}: {needle}")


def method(source: str, start: str, end: str) -> str:
    return source.split(start, 1)[1].split(end, 1)[0]


def main() -> None:
    source = SOURCE.read_text()

    for needle, reason in [
        ("private static let helperScript", "external MediaRemote helper script"),
        ("private var helperProcess: Process?", "tracked persistent helper process"),
        ("helperSwiftURL", "real developer-tool Swift fallback"),
        ("private func directRead", "in-process MediaRemote read path"),
        ("private func sendAdapterPlaybackCommand", "perl playback command channel"),
        ('process.arguments = [script.path, framework.path, "send", String(command)]', "send command arguments"),
        ("process.standardOutput = FileHandle.nullDevice", "non-streaming playback command output"),
        ("private func postSystemMediaKey", "system media-key fallback"),
        ("private func clearNowPlaying", "explicit clearing path"),
    ]:
        require(source, needle, reason)

    toggle = method(source, "func togglePlayPause()", "func nextTrack()")
    next_track = method(source, "func nextTrack()", "func previousTrack()")
    previous = method(source, "func previousTrack()", "private func routePlaybackCommand")
    placeholder = re.search(
        r"guard !trackName\.isEmpty else \{(?P<body>.*?)\n\s*\}", toggle, re.S
    )
    assert placeholder, "play/pause must explicitly handle placeholder state"
    placeholder_body = placeholder.group("body")
    assert "armPendingPlaybackIntent()" in placeholder_body
    assert "activatePreferredRunningMusicApp()" in placeholder_body
    assert placeholder_body.find("armPendingPlaybackIntent()") < placeholder_body.find(
        "activatePreferredRunningMusicApp()"
    ), "intent must be armed before bringing the preferred player forward"
    assert "return" in placeholder_body
    for forbidden in [
        "routePlaybackCommand",
        "postSystemMediaKey",
        "Process()",
        '"send"',
    ]:
        assert forbidden not in placeholder_body, (
            f"placeholder play must not send a playback command directly: {forbidden}"
        )

    assert "guard !trackName.isEmpty else { return }" in next_track
    assert "guard !trackName.isEmpty else { return }" in previous
    assert "routePlaybackCommand(adapterCommand: 2, fallbackMediaKey: NX_KEYTYPE_PLAY)" in toggle
    assert "cancelPendingPlaybackIntent()" in toggle
    assert "routePlaybackCommand(adapterCommand: 4, fallbackMediaKey: NX_KEYTYPE_NEXT)" in next_track
    assert "routePlaybackCommand(adapterCommand: 5, fallbackMediaKey: NX_KEYTYPE_PREVIOUS)" in previous
    assert "isPlaying.toggle()" in toggle, "optimistic play state must remain"
    assert "playingFrozenUntil" in toggle and "playingFrozenUntil" in next_track
    assert "playingFrozenUntil" in previous
    assert source.count("activatePreferredRunningMusicApp()") == 2, (
        "placeholder play needs one activation call plus the helper declaration"
    )

    arm = method(
        source,
        "private func armPendingPlaybackIntent",
        "private func cancelPendingPlaybackIntent",
    )
    assert "cancelPendingPlaybackIntent()" in arm, "re-arming must invalidate the old intent"
    assert "preferredRunningMusicApp?.bundleIdentifier" in arm
    assert "playbackIntentLifetime: TimeInterval = 12" in source
    assert "pendingPlaybackIntent = intent" in arm
    for forbidden in ["activatePreferredRunningMusicApp", "sendAdapterPlaybackCommand", "Process()"]:
        assert forbidden not in arm, f"arming must stay silent: {forbidden}"

    fulfill = method(
        source,
        "private func fulfillPendingPlaybackIntent",
        "/// 使用 perl adapter",
    )
    assert "reportedBundleIdentifier == intent.targetBundleIdentifier" in fulfill
    assert "!snapshot.title.isEmpty || snapshot.pid > 0" in fulfill
    assert fulfill.count("sendAdapterPlaybackCommand(2)") == 1
    cancel_index = fulfill.rfind("cancelPendingPlaybackIntent()")
    playing_index = fulfill.find("guard !snapshot.playing else { return }")
    send_index = fulfill.find("sendAdapterPlaybackCommand(2)")
    assert -1 not in (cancel_index, playing_index, send_index)
    assert cancel_index < playing_index < send_index, (
        "intent must be consumed once, and an already-playing payload must not send"
    )

    helper = method(source, "private func handleHelperLine", "// MARK: - 进程内直读")
    assert "if backend == .perlAdapter" in helper
    assert "fulfillPendingPlaybackIntent" in helper

    assert "cancelPendingPlaybackIntent()" in next_track
    assert "cancelPendingPlaybackIntent()" in previous
    seek = method(source, "func seek(to seconds", "private func postSystemMediaKey")
    assert "cancelPendingPlaybackIntent()" in seek

    adapter = method(
        source,
        "private func sendAdapterPlaybackCommand",
        "private func activatePreferredRunningMusicApp",
    )
    assert "activeBackend == .perlAdapter" in adapter
    assert "try process.run()" in adapter
    assert "waitUntilExit" not in adapter

    route = method(
        source,
        "private func routePlaybackCommand",
        "private func sendAdapterPlaybackCommand",
    )
    assert "if !sendAdapterPlaybackCommand(adapterCommand)" in route
    assert "postSystemMediaKey(fallbackMediaKey)" in route

    preferred = method(
        source,
        "private var preferredRunningMusicApp",
        "// MARK: - MediaRemote",
    )
    owner = preferred.find("currentSessionBundleIdentifier")
    mru = preferred.find("recentMusicAppBundleIdentifiers")
    fallback = preferred.find("return runningMusicApp")
    assert -1 not in (owner, mru, fallback) and owner < mru < fallback, (
        "intent targeting must prefer session owner, then activation MRU, then fallback"
    )
    assert "currentSessionBundleIdentifier = reportedBundleID" in source
    clear = method(source, "private func clearNowPlaying()", "// MARK: - 行缓冲")
    assert "currentSessionBundleIdentifier = nil" in clear

    assert 'URL(fileURLWithPath: "/usr/bin/swift")' not in source
    assert "🎵" not in source
    print("Direct now-playing contract passed.")


if __name__ == "__main__":
    main()
