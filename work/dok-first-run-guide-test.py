#!/usr/bin/env python3
"""首次引导合约：亲手按一次快捷键、用一次轮盘；不要权限；老用户不打扰。"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
S = ROOT / "Sources" / "dok"


def main() -> None:
    guide = (S / "FirstRunGuide.swift").read_text()
    app = (S / "DokApp.swift").read_text()
    state = (S / "AppState.swift").read_text()
    window = (S / "DokWheelWindow.swift").read_text()
    settings = (S / "SettingsView.swift").read_text()

    assert "forKey: .hasCompletedOnboarding)) ?? true" in state, "an existing config isn't a new user"
    assert "NSAlert" not in app.split("func showOnboarding", 1)[-1][:400] if "func showOnboarding" in app else True
    assert "func showOnboarding" not in app and "onboarding.openAccessibility" not in app
    assert "firstRunGuide?.hotkeyDidFire()" in app.split("func handleHotKeyDown()", 1)[1][:600]
    assert ".nonactivatingPanel" in guide
    assert guide.count("hasCompletedOnboarding = true") == 1, "only finishing or skipping completes it"
    assert "AXIsProcessTrustedWithOptions" not in guide and "CGRequestListenEventAccess" not in guide
    assert "CGPreflightListenEventAccess()" in guide, "never triggers a permission prompt"
    assert "static let fallbackDelay: TimeInterval = 8" in guide
    assert "HotkeyRecorderRow(appState:" in guide
    assert "onDidHide?()" in window.split("private func finishHiding()", 1)[1].split("override func order", 1)[0]
    assert "guide.useWheel.hold" in guide and "guide.openSettings" in guide and "guide.start" in guide
    assert "settings.replayGuide" in settings and "replayGuideRequested" in settings
    for lang in ("en", "zh-Hans"):
        strings = (ROOT / "Resources" / f"{lang}.lproj" / "Localizable.strings").read_text()
        assert "onboarding.body" not in strings
        for key in ("guide.press", "guide.useWheel", "guide.useWheel.hold", "guide.done", "guide.openSettings",
                    "guide.start", "guide.skip", "guide.openWheel", "guide.changeHotkey", "settings.replayGuide",
                    "settings.replayGuide.action"):
            assert f'"{key}"' in strings, (lang, key)
    # 审查修复：换快捷键能退出；退出时停止录入；键帽按下变亮；已展开的置顶轮盘不推进引导
    assert "func cancelChangingHotkey()" in guide and "link.cancel" in guide
    assert guide.count("hotkeyRecordingCancelled") >= 2
    assert ".opacity(isHeld(symbol) || guide.heldModifiers.isEmpty ? 1 : 0.5)" in guide
    down = app.split("func handleHotKeyDown()", 1)[1]
    assert down.index("pinnedController?.collapse()") < down.index("firstRunGuide?.hotkeyDidFire()")
    print("First run guide contract passed.")


if __name__ == "__main__":
    main()
