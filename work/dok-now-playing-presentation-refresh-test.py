#!/usr/bin/env python3
"""轮盘弹出时的刷新契约，以及过期状态的清理。"""
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
APP_SOURCE = ROOT / "Sources" / "dok" / "DokApp.swift"
NOW_PLAYING_SOURCE = ROOT / "Sources" / "dok" / "NowPlayingService.swift"


def require(source: str, needle: str, reason: str) -> None:
    if needle not in source:
        raise AssertionError(f"Missing {reason}: {needle}")


def require_order(source: str, first: str, second: str, reason: str) -> None:
    first_index = source.find(first)
    second_index = source.find(second)
    if first_index == -1 or second_index == -1 or first_index > second_index:
        raise AssertionError(f"Expected order for {reason}: {first} before {second}")


def main() -> None:
    app_source = APP_SOURCE.read_text()
    now_playing_source = NOW_PLAYING_SOURCE.read_text()

    requirements = [
        ("func refreshForMenuPresentation()", "public refresh entrypoint for menu presentation"),
        ("directRead()", "immediate now-playing read when presenting the menu"),
        ("private func clearNowPlaying", "stale now-playing state is actively cleared"),
        ("bundleID != expected", "bundle mismatch branch still guards app identity"),
        ("scheduleClear()", "bundle mismatch drops the stale displayed track"),
    ]

    for needle, reason in requirements:
        require(now_playing_source, needle, reason)

    require(app_source, "appState.nowPlaying.refreshForMenuPresentation()", "menu presentation refresh call")
    require_order(
        app_source,
        "appState.nowPlaying.refreshForMenuPresentation()",
        "window.showAt(point: mouseLocation)",
        "refresh starts before the wheel appears",
    )

    print("Now-playing presentation refresh contract passed.")


if __name__ == "__main__":
    main()
