#!/usr/bin/env python3
"""播放进度 seek 契约：角度方向、perl 命令与乐观冻结保持一致。"""
from math import atan2, hypot, pi
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SERVICE = (ROOT / "Sources" / "Arcly" / "NowPlayingService.swift").read_text()
WINDOW = (ROOT / "Sources" / "Arcly" / "ArclyWheelWindow.swift").read_text()


def fraction(dx: float, dy: float, center_y: float, radius: float, tolerance: float):
    relative_y = dy - center_y
    if abs(hypot(dx, relative_y) - radius) > tolerance:
        return None
    angle = atan2(dx, relative_y)
    if angle < 0:
        angle += 2 * pi
    return angle / (2 * pi)


def main() -> None:
    center_y = 0
    radius = 66
    assert abs(fraction(0, center_y + radius, center_y, radius, 1) - 0.00) < 1e-9
    assert abs(fraction(radius, center_y, center_y, radius, 1) - 0.25) < 1e-9
    assert abs(fraction(0, center_y - radius, center_y, radius, 1) - 0.50) < 1e-9
    assert abs(fraction(-radius, center_y, center_y, radius, 1) - 0.75) < 1e-9
    assert fraction(0, center_y, center_y, radius, 1) is None

    assert "struct MusicProgressRingGeometry" in WINDOW
    assert "var angle = atan2(dx, relativeY)" in WINDOW
    assert "musicProgressRingHitTolerance: CGFloat { 6 * centerMusicControlScale }" in WINDOW
    assert "radius: centerLensRadius" in WINDOW
    assert "centerYOffset: 0" in WINDOW
    assert "case seek(to: TimeInterval)" in WINDOW
    assert "nowPlaying.canSeek" in WINDOW
    assert ".seek(to: duration * fraction)" in WINDOW
    assert "np.seek(to: seconds)" in WINDOW
    selection = WINDOW[WINDOW.index("func updateSelection()"):WINDOW.index("// MARK: - 拖放处理")]
    assert selection.index("seekFraction(dx: dx, dy: dy)") < selection.index("isInsideCenterControls"), (
        "seek ring must win before center controls and slot selection"
    )

    assert "@Published private(set) var canSeek" in SERVICE
    assert "activeBackend == .perlAdapter" in SERVICE
    assert "func seek(to seconds: TimeInterval)" in SERVICE
    assert '[script.path, framework.path, "seek", String(microseconds)]' in SERVICE
    assert "target * 1_000_000" in SERVICE
    assert "process.standardOutput = FileHandle.nullDevice" in SERVICE
    assert "try process.run()" in SERVICE
    assert "elapsedTime = target" in SERVICE
    assert "progressFrozenUntil = Date().addingTimeInterval" in SERVICE
    assert "guard trackChanged || Date() >= progressFrozenUntil" in SERVICE

    print("Now-playing seek contract passed.")


if __name__ == "__main__":
    main()
