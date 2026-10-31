#!/usr/bin/env python3
"""音乐数据按使用方计数：关掉唤出轮盘不断常驻的数据；没有播放器时小圆点不留 perl 进程。"""
from pathlib import Path

S = (Path(__file__).resolve().parents[1] / "Sources" / "dok" / "NowPlayingService.swift").read_text()


def main() -> None:
    assert "enum NowPlayingConsumer: Hashable { case summonedWheel, pinnedWheel, pinnedOrb }" in S
    assert "private var consumers = Set<NowPlayingConsumer>()" in S
    assert "private var isMenuPresented: Bool { !consumers.subtracting([.pinnedOrb]).isEmpty }" in S, (
        "the orb isn't watching: songs changed while collapsed don't push"
    )
    assert "func beginConsuming(_ consumer: NowPlayingConsumer)" in S
    assert "func endConsuming(_ consumer: NowPlayingConsumer)" in S
    assert "beginConsuming(.summonedWheel)" in S and "endConsuming(.summonedWheel)" in S
    update = S.split("private func updateAdapterStream()", 1)[1].split("private func startAdapterStream", 1)[0]
    assert "consumers.contains(.summonedWheel) || pinnedNeedsStream || pendingPlaybackIntent != nil" in update
    assert "!consumers.isDisjoint(with: [.pinnedWheel, .pinnedOrb]) && runningMusicApp != nil && adapterUsable" in S
    assert "func reevaluateStream()" in S
    print("Now playing consumers contract passed.")


if __name__ == "__main__":
    main()
