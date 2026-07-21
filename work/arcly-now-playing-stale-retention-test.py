#!/usr/bin/env python3
"""空读容忍契约。

切歌瞬间 MediaRemote 常有短暂空窗，立刻清空会让轮盘中心闪一下。
旧实现靠计数若干次空读再清；常驻 helper 是事件驱动的，
改为延迟清理 —— 期间任何有效数据都会取消这次清理。
"""
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Sources" / "Arcly" / "NowPlayingService.swift"


def main() -> None:
    source = SOURCE.read_text()

    assert "private var pendingClearWorkItem: DispatchWorkItem?" in source, (
        "NowPlayingService should defer clearing instead of wiping on the first empty read"
    )
    assert "private let staleClearDelay" in source, "the tolerated empty window should be an explicit duration"
    assert "private func scheduleClear()" in source, (
        "empty reads should be handled separately from hard clearing"
    )

    schedule = re.search(r"private func scheduleClear\(\) \{(?P<body>.*?)\n    \}\n", source, re.S)
    assert schedule, "scheduleClear body not found"
    schedule_body = schedule.group("body")
    assert "runningMusicApp == nil" in schedule_body, (
        "empty reads should retain the placeholder while a music app is still running"
    )
    assert "trackName.isEmpty" in schedule_body, (
        "retention should only keep meaningful previous music metadata"
    )
    assert "staleClearDelay" in schedule_body, "clearing must be delayed, not immediate"
    assert "guard pendingClearWorkItem == nil else { return }" in schedule_body, (
        "a pending clear should not be restarted by repeated empty reads"
    )

    apply_body = re.search(r"private func apply\(_ snapshot: NowPlayingSnapshot\) \{(?P<body>.*?)\n    \}\n", source, re.S)
    assert apply_body, "apply body not found"
    assert "cancelPendingClear()" in apply_body.group("body"), (
        "a successful read should cancel any pending clear"
    )

    # 发送播放命令后的乐观更新不得被随后的旧状态回弹覆盖。
    assert "playingFrozenUntil" in source, "optimistic play state should be protected after a command"
    assert "if Date() > playingFrozenUntil" in source, "frozen window should guard isPlaying writes"

    print("Now-playing stale retention contract passed.")


if __name__ == "__main__":
    main()
