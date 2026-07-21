#!/usr/bin/env python3
"""Now-playing 基础契约。

播放控制必须与「能否显示曲目」解耦：即便读不到元数据，
上一首/播放暂停/下一首也要能用。
"""
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Sources" / "Arcly" / "NowPlayingService.swift"


def require(source: str, needle: str, reason: str) -> None:
    if needle not in source:
        raise AssertionError(f"Missing {reason}: {needle}")


def forbid(source: str, needle: str, reason: str) -> None:
    if needle in source:
        raise AssertionError(f"Forbidden {reason}: {needle}")


def main() -> None:
    source = SOURCE.read_text()

    requirements = [
        ("private static let helperScript", "external MediaRemote helper script"),
        ("private var helperProcess: Process?", "tracked persistent helper process"),
        ("Process()", "helper process launch"),
        ("helperSwiftURL", "helper only uses an installed developer-tool Swift binary"),
        ("private func directRead", "in-process MediaRemote read path"),
        ("postSystemMediaKey", "media controls use hardware media key events"),
        ("NX_KEYTYPE_PLAY", "play pause uses system media key"),
        ("NX_KEYTYPE_NEXT", "next track uses system media key"),
        ("NX_KEYTYPE_PREVIOUS", "previous track uses system media key"),
        ("postSystemMediaKey(NX_KEYTYPE_PLAY)", "play pause sends command even when no title is displayed"),
        ("postSystemMediaKey(NX_KEYTYPE_NEXT)", "next track sends command even when no title is displayed"),
        ("postSystemMediaKey(NX_KEYTYPE_PREVIOUS)", "previous track sends command even when no title is displayed"),
        ("private func clearNowPlaying", "explicit clearing path"),
    ]

    for needle, reason in requirements:
        require(source, needle, reason)

    forbidden = [
        ("if trackName.isEmpty { return }", "media controls blocked by missing displayed title"),
        ('URL(fileURLWithPath: "/usr/bin/swift")', "system Swift shim can prompt users to install developer tools"),
        ("🎵", "temporary diagnostic music logs should not ship"),
    ]

    for needle, reason in forbidden:
        forbid(source, needle, reason)

    print("Direct now-playing contract passed.")


if __name__ == "__main__":
    main()
