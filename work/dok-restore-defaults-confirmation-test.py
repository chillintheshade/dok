#!/usr/bin/env python3
"""恢复默认：按钮原地展开确认，只有点“恢复”才执行；4 秒无操作自动收起，等于取消。"""
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SETTINGS = ROOT / "Sources" / "dok" / "SettingsView.swift"
ZH = ROOT / "Resources" / "zh-Hans.lproj" / "Localizable.strings"
EN = ROOT / "Resources" / "en.lproj" / "Localizable.strings"


def require(source: str, needle: str, reason: str) -> None:
    if needle not in source:
        raise AssertionError(f"Missing {reason}: {needle}")


def main() -> None:
    settings = SETTINGS.read_text()
    zh = ZH.read_text()
    en = EN.read_text()

    assert "NSAlert" not in settings, "settings no longer use system alerts"
    requirements = [
        ("beginRestoreConfirmation()", "restore tile opens the inline confirmation"),
        ("if confirmingRestore {\n                restoreConfirmation", "confirmation replaces the tile in place"),
        ("Button(Loc.string(\"settings.restoreDefaults.confirm.action\"), action: restoreDefaults)",
         "only the explicit restore button restores"),
        ("private static let restoreConfirmTimeout: TimeInterval = 4", "auto-collapse delay"),
        ("guard restoreCollapseToken == token, confirmingRestore, !restoreHovered else { return }\n"
         "            cancelRestoreConfirmation()", "timeout cancels, never restores, and waits while hovered"),
        ("appState.settings.apps = Array(AppState.defaultApps().prefix(maxSlots))", "confirmed default restoration"),
    ]
    for needle, reason in requirements:
        require(settings, needle, reason)
    collapse = settings.split("private func scheduleRestoreCollapse()", 1)[1].split("private func cancelRestoreConfirmation()", 1)[0]
    assert "restoreDefaults()" not in collapse, "the timeout must never restore"

    for localization in (zh, en):
        for key in (
            "settings.restoreDefaults.confirm.title",
            "settings.restoreDefaults.inline",
            "settings.restoreDefaults.confirm.action",
            "settings.restoreDefaults.confirm.cancel",
        ):
            require(localization, f'"{key}"', f"localized {key}")

    print("Restore defaults confirmation contract passed.")


if __name__ == "__main__":
    main()
