#!/usr/bin/env python3
"""常驻轮盘和唤出轮盘各有一份交互状态，命中判断共用。"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
S = ROOT / "Sources" / "dok"


def main() -> None:
    inter = (S / "WheelInteraction.swift").read_text()
    state = (S / "AppState.swift").read_text()
    window = (S / "DokWheelWindow.swift").read_text()
    view = (S / "DokWheelView.swift").read_text()
    for needle in ("final class WheelInteractionState: ObservableObject", "struct WheelHitTester",
                   "enum WheelCenterAction", "func isInsideWheel(at point: NSPoint, center: NSPoint) -> Bool"):
        assert needle in inter, needle
    for name in ("selectedIndex", "selectedRecentAppIndex", "isMenuVisible", "centerControlHover"):
        assert f"@Published var {name}" not in state, name
        assert f"appState.{name}" not in window and f"appState.{name}" not in view, name
    assert "let interaction = WheelInteractionState()" in window
    assert "private func slotIndex" not in window and "private func satelliteIndex" not in window
    assert "init(appState: AppState,\n         interaction: WheelInteractionState," in view
    assert "func openItem(_ app: AppItem)" in inter, "launching is shared by both wheels"
    print("Wheel interaction state contract passed.")


if __name__ == "__main__":
    main()
