#!/usr/bin/env python3
"""播放进度环契约：perl 数据进入服务层，视图本地外推并按需隐藏。"""
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SERVICE = (ROOT / "Sources" / "dok" / "NowPlayingService.swift").read_text()
VIEW = (ROOT / "Sources" / "dok" / "DokWheelView.swift").read_text()


def main() -> None:
    for field in ["duration", "elapsedTime", "progressTimestamp", "playbackRate"]:
        assert f"@Published private(set) var {field}" in SERVICE, f"missing published {field}"

    for key in ['payload["duration"]', 'payload["elapsedTime"]',
                'payload["timestamp"]', 'payload["playbackRate"]']:
        assert key in SERVICE, f"perl adapter field is not parsed: {key}"

    assert "func playbackProgress(at now: Date = Date()) -> Double?" in SERVICE
    assert "now.timeIntervalSince(progressTimestamp)" in SERVICE
    track_changed_block = SERVICE.split("let trackChanged = trackName != snapshot.title", 1)[1].split(
        "trackName = snapshot.title", 1
    )[0]
    assert "if trackChanged" in track_changed_block
    assert "clearProgress()" in track_changed_block
    assert "clearProgress()\n        applyArtwork" not in SERVICE, (
        "progress must be applied from the new snapshot before artwork handling"
    )

    assert "TimelineView(.periodic" in VIEW, "the view should extrapolate locally"
    assert ".trim(from: 0, to: progress)" in VIEW
    assert VIEW.count(".trim(from: 0, to: progress)") == 1, (
        "the center progress boundary must contain exactly one progress arc"
    )
    assert "StrokeStyle(lineWidth: musicProgressLineWidth, lineCap: .round)" in VIEW, (
        "the progress arc must use rounded end caps"
    )
    assert ".rotationEffect(.degrees(-90))" in VIEW
    assert "musicProgressLineWidth" in VIEW
    assert "musicProgressBoundaryLayer" in VIEW
    assert "musicProgressDiameter: CGFloat { centerLensRadius * 2 }" in VIEW
    assert "if showsMusicController, nowPlaying.duration != nil" in VIEW, (
        "missing progress must hide the ring"
    )
    assert "showsCenterBoundary" not in VIEW, "the center boundary must be removed in every state"
    assert "colorScheme == .dark ? 0.12 : 0.06" not in VIEW, (
        "the idle gear state must not restore the center boundary"
    )
    assert "Color.primary.opacity(0.28)" in VIEW, "played segment should only be one level stronger than the boundary"
    assert "min(max(0.9 * centerMusicControlScale, 0.9), 1.0)" in VIEW, (
        "progress and center boundary must share a restrained line width"
    )
    assert "musicProgressDotSize" not in VIEW, "the progress head dot must be removed"
    assert "Color.primary.opacity(0.40)" not in VIEW, "the progress head dot must not be drawn"
    assert "musicProgressTrackLineWidth" not in VIEW, "the progress layer must not draw a second track"
    assert "Color.primary.opacity(0.70)" not in VIEW, "the old heavy progress arc must be removed"
    assert "Color.primary.opacity(0.88)" not in VIEW, "the old heavy progress head must be removed"
    assert "musicArtworkWithProgress" not in VIEW, "the artwork must no longer own the progress ring"
    assert "musicProgressTick" not in VIEW, "the ring must not add tick marks"
    assert "musicProgressEndLine" not in VIEW, "the ring must not add endpoint lines"

    print("Now-playing progress ring contract passed.")


if __name__ == "__main__":
    main()
