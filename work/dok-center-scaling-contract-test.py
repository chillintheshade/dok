#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PIE_VIEW = ROOT / "Sources" / "dok" / "DokWheelView.swift"
PIE_WINDOW = ROOT / "Sources" / "dok" / "DokWheelWindow.swift"
SETTINGS = ROOT / "Sources" / "dok" / "SettingsView.swift"


def main() -> None:
    pie = PIE_VIEW.read_text()
    window = PIE_WINDOW.read_text()
    settings = SETTINGS.read_text()

    assert "private var centerControlScale" in pie, "center controls should have their own radius-based scale"
    assert "iconOrbitRadius / 130" in pie, "center control scale should respond to wheel radius"
    assert "iconSize / 48" not in pie[pie.find("private var centerControlScale"):pie.find("private var sliceAngleDeg")], (
        "center controls should not depend on app icon size"
    )
    assert "private var musicArtworkBaseSize: CGFloat { 58 }" in pie, (
        "album artwork should keep a tuned base size"
    )
    assert "private var musicArtworkSize: CGFloat { musicArtworkBaseSize * centerMusicControlScale }" in pie, (
        "album artwork should scale with the wheel radius while following the center safety scale"
    )
    assert "centerSettingsIconSize" in pie, "settings gear should scale with the wheel center controls"

    assert "private var centerMusicControlScale" in window, "hit testing should mirror visual center scale"
    assert "appState.settings.menuRadius / 130" in window, "center hit areas should follow wheel radius"
    assert "private var centerLensRadius" in window, "center hit areas should use the same fitted inner circle as visuals"
    assert "appState.settings.iconSize / 48" not in window[window.find("private var centerMusicControlScale"):window.find("private enum CenterClickAction")], (
        "center hit areas should not depend on app icon size"
    )

    assert "previewOuterDiameter" in settings, "settings preview should calculate a fitted wheel diameter"
    assert "min((pieSize - 28) / previewOuterDiameter" in settings, (
        "settings preview should shrink large wheel radii to stay inside the preview stage"
    )

    print("Center scaling contract passed.")


if __name__ == "__main__":
    main()
