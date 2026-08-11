#!/usr/bin/env python3
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

    requirements = [
        ("private func restoreDefaultsWithConfirmation()", "dedicated confirmation gate"),
        ("alert.alertStyle = .warning", "destructive-action warning style"),
        ("guard alert.runModal() == .alertFirstButtonReturn else { return }", "cancel-safe restore gate"),
        ("restoreDefaultsWithConfirmation()", "restore tile invokes the confirmation gate"),
        ("appState.settings.apps = Array(AppState.defaultApps().prefix(maxSlots))", "confirmed default restoration"),
    ]
    for needle, reason in requirements:
        require(settings, needle, reason)

    for localization in (zh, en):
        for key in (
            "settings.restoreDefaults.confirm.title",
            "settings.restoreDefaults.confirm.message",
            "settings.restoreDefaults.confirm.action",
            "settings.restoreDefaults.confirm.cancel",
        ):
            require(localization, f'"{key}"', f"localized {key}")

    print("Restore defaults confirmation contract passed.")


if __name__ == "__main__":
    main()
