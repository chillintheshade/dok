#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PIE_VIEW = ROOT / "Sources" / "dok" / "DokWheelView.swift"


def main() -> None:
    source = PIE_VIEW.read_text()

    assert "private var centerLensRadius" in source, (
        "center lens should have its own radius so the visible inner circle can contain center content"
    )
    assert "iconOrbitRadius - iconSize / 2 - 10" in source, (
        "center lens must stay inside the icon orbit instead of growing into app icons"
    )
    assert "private var centerMusicControlScale" in source, (
        "music controls need an inner-circle-aware scale separate from the general center scale"
    )
    assert "private var musicArtworkBaseSize: CGFloat { 58 }" in source, (
        "album artwork should keep a tuned base size before radius scaling"
    )
    assert "private var musicArtworkSize: CGFloat { musicArtworkBaseSize * centerMusicControlScale }" in source, (
        "album artwork should scale with the wheel radius while staying inside the center lens"
    )
    assert 'Image(systemName: "music.note")' in source and "24 * centerMusicControlScale" in source, (
        "the placeholder music note should scale with the album artwork"
    )
    assert "centerDiameter: centerLensRadius * 2" in source, (
        "the shared Control Center glass edge should use the fitted center lens radius"
    )
    assert "centerLensRadius * 2 - 18" in source, (
        "music title width should be constrained by the fitted inner circle"
    )
    assert "12.5 * centerMusicControlScale" in source, (
        "the music settings gear should use the same fitted music scale as the controls"
    )

    print("Music center inner-circle contract passed.")


if __name__ == "__main__":
    main()
