#!/usr/bin/env python3
"""中心名字契约：应用不显示名字；文件、网址、按键动作停留后显示名字 + 区分信息。"""
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
VIEW = (ROOT / "Sources" / "dok" / "DokWheelView.swift").read_text()
STATE = (ROOT / "Sources" / "dok" / "AppState.swift").read_text()


def main() -> None:
    assert "selectedAppName" not in VIEW, "apps are recognised by icon; no name in the center"
    candidate = VIEW.split("private var centerLabelCandidateID: UUID? {", 1)[1].split("}", 2)
    assert "item.itemType == .app ? nil : item.id" in VIEW
    assert "selectedRecentAppIndex" not in candidate[0], "recent apps never get a name"
    # 音乐控制只在显示名字时让位
    assert "centerLabelItem == nil\n            && nowPlaying.hasNowPlaying" in VIEW
    # 停留后出现；已显示时立刻切换；离开立刻复原
    assert "static let centerLabelDwell: Double = 0.15" in VIEW
    assert "if centerLabelItemID != nil {\n            centerLabelItemID = id" in VIEW
    assert "asyncAfter(deadline: .now() + MenuMotion.centerLabelDwell" in VIEW
    # 第二行区分信息
    assert "deletingLastPathComponent()" in VIEW and "FileManager.default.displayName(atPath: folder)" in VIEW
    assert 'host.hasPrefix("www.")' in VIEW
    assert "combo.keySymbols" in VIEW and "var keySymbols: [String]" in STATE
    print("Center label contract passed.")


if __name__ == "__main__":
    main()
