#!/usr/bin/env python3
"""运行中播放器只能作为可选提示，不能作为硬门槛。

沙箱构建可能枚举不到正在播放的 App。若据此清空状态，
会在音乐正常播放时误清有效信息。
"""
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Sources" / "Arcly" / "NowPlayingService.swift"


def main() -> None:
    source = SOURCE.read_text()

    # 身份校验分支必须先确认拿得到期望值，拿不到就跳过校验而不是清空。
    assert "let expected = runningMusicApp?.bundleIdentifier" in source, (
        "running player identity should remain an optional validation hint, not a hard gate"
    )

    upkeep = re.search(r"private func upkeep\(\) \{(?P<body>.*?)\n    \}\n", source, re.S)
    assert upkeep, "upkeep body not found"
    upkeep_body = upkeep.group("body")

    assert "guard trackName.isEmpty else { return }" in upkeep_body, (
        "upkeep must not evaluate running-app state while a track is displayed"
    )
    assert "clearNowPlaying()" not in upkeep_body, (
        "upkeep must never clear a live track based on app enumeration alone"
    )

    # 有播放器在跑时保留占位控制器，让用户仍能操作播放。
    clear = re.search(r"private func clearNowPlaying\(\) \{(?P<body>.*?)\n    \}\n", source, re.S)
    assert clear, "clearNowPlaying body not found"
    assert "hasNowPlaying = runningMusicApp != nil" in clear.group("body"), (
        "clearing should keep the placeholder controller while a player is still running"
    )

    print("Now-playing no running-app gate contract passed.")


if __name__ == "__main__":
    main()
