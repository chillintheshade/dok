#!/usr/bin/env python3
"""设置页打磨契约：滑块按档位实时吸附；按键动作页以组合键为主角、名称选填、目标应用用菜单选。"""
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SETTINGS = (ROOT / "Sources" / "dok" / "SettingsView.swift").read_text()
SERVICE = (ROOT / "Sources" / "dok" / "KeyActionService.swift").read_text()
STATE = (ROOT / "Sources" / "dok" / "AppState.swift").read_text()


def main() -> None:
    # 滑块：拖动中就落在档位上，看到的值就是松手后的值；每档轻震，默认档换震感。
    slider = SETTINGS.split("private struct SmoothSettingsSlider: View {", 1)[1].split("private extension View {", 1)[0]
    assert "move(to: target)" in slider and "magnetized" not in slider
    assert ".onEnded { _ in\n                    dragging = false\n                })" in slider, "release never jumps"
    assert "next == defaultValue ? .alignment : .levelChange" in slider
    assert "TapGesture(count: 2)" in slider, "double-click resets to default"
    assert "range: 100...180,\n                step: 5," in SETTINGS
    assert "range: 32...64,\n                step: 2," in SETTINGS
    assert "static let defaultMenuRadius: Double = 110" in STATE
    assert "static let defaultIconSize: Double = 48" in STATE

    # 按键动作页
    editor = SETTINGS.split("private struct KeyActionEditor: View {", 1)[1].split("// MARK: - 通用设置", 1)[0]
    assert ".frame(maxWidth: .infinity, alignment: .topLeading)" in editor, "fills the right-hand panel"
    assert "Button(Loc.string(\"link.cancel\")" not in editor, "the panel's Done closes it; no separate cancel"
    assert "LargeKeyCap(text: symbol)" in editor, "the combination is the hero"
    assert "KeyActionRecorderInput(value: $combo, recording: $recording, status: $recorderStatus)" in editor
    assert "control.drawsChrome = false" in SETTINGS and "if drawsChrome { super.draw(dirtyRect) }" in SERVICE
    assert "private var canSave: Bool { canAdd && !recording && combo != nil && !conflict }" in editor, "name is optional"
    assert 'combo.displayString : "\\(targetName) \\(combo.displayString)"' in editor, "empty name is generated"
    assert "NSWorkspace.shared.runningApplications" in editor and "targetMenuAnchor.popUp(menu)" in editor
    assert "SettingsPillButtonStyle(prominent: true)" in editor and ".keyboardShortcut(.defaultAction)" in editor
    assert "KeyActionNameInput(text: $name, onSubmit: save)" in editor
    assert "parent.onSubmit?(); return true" in SETTINGS, "Return in the name field saves"

    print("Settings polish contract passed.")


if __name__ == "__main__":
    main()
