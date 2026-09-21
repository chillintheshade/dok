#!/usr/bin/env python3
"""Main-wheel file, folder and website content contract."""
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
STATE = (ROOT / "Sources" / "dok" / "AppState.swift").read_text()
SETTINGS = (ROOT / "Sources" / "dok" / "SettingsView.swift").read_text()
WINDOW = (ROOT / "Sources" / "dok" / "DokWheelWindow.swift").read_text()
APP = (ROOT / "Sources" / "dok" / "DokApp.swift").read_text()
EN = (ROOT / "Resources" / "en.lproj" / "Localizable.strings").read_text()
ZH = (ROOT / "Resources" / "zh-Hans.lproj" / "Localizable.strings").read_text()


def main() -> None:
    for needle, description in [
        ('case webLink = "webLink"', "persisted website item type"),
        ("static func normalizedWebURL", "central website normalization"),
        ('scheme == "http" || scheme == "https"', "safe website scheme allowlist"),
        ("func openWebLink()", "default-browser website launch"),
        ("var isFolder: Bool", "folder classification"),
        ('return "url:\\(app.id):\\(app.path)"', "per-shortcut website icon cache identity"),
    ]:
        assert needle in STATE, f"missing {description}"

    for needle, description in [
        ("private func addFileSystemItem(chooseFolder: Bool)", "separate file/folder picker"),
        ("panel.canChooseFiles = !chooseFolder", "file-only picker mode"),
        ("panel.canChooseDirectories = chooseFolder", "folder-only picker mode"),
        ("private func addWebLink()", "website entry action"),
        ("AppItem.normalizedWebURL(from: field.stringValue)", "validated website input"),
        ('Loc.string("settings.addFile")', "file action row"),
        ('Loc.string("settings.addLink")', "website action row"),
    ]:
        assert needle in SETTINGS, f"missing {description}"

    assert "appState.recordOpenedFolder(app)" in WINDOW
    assert "app.openWebLink()" in WINDOW
    assert APP.count("appState.recordOpenedFolder(app)") == 2
    assert APP.count("app.openWebLink()") == 2

    for text, language in [(EN, "English"), (ZH, "Chinese")]:
        for key in [
            "settings.addFile",
            "settings.addLink",
            "openPanel.folder.message",
            "openPanel.file.message",
            "link.invalid.message",
        ]:
            assert f'"{key}"' in text, f"{language} missing {key}"

    print("Wheel content items contract passed.")


if __name__ == "__main__":
    main()
