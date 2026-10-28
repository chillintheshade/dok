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
        # 添加与编辑统一在右侧面板：应用 / 文件 / 网址 / 按键 四类，同一种操作方式。
        ("private enum AddKind: String, CaseIterable {\n    case app, file, link, keyAction", "four add kinds"),
        ("private func itemPanel(_ mode: ItemPanelMode) -> some View", "one shared add/edit panel"),
        ("openPanel(.add)", "Add opens the panel"),
        ("openPanel(.edit(item.id))", "editing uses the same panel"),
        ("private struct AppListPanel: View", "inline app list"),
        (".onDrop(of: [.fileURL], isTargeted: $targeted)", "files and folders by drag and drop"),
        ("panel.canChooseFiles = true\n        panel.canChooseDirectories = true", "one picker for files and folders"),
        ("private struct LinkForm: View", "inline website form"),
        ("AppItem.normalizedWebURL(from: address)", "validated website input"),
    ]:
        assert needle in SETTINGS, f"missing {description}"

    assert "appState.recordOpenedFolder(app)" in WINDOW
    assert "app.openWebLink()" in WINDOW
    assert APP.count("appState.recordOpenedFolder(app)") == 2
    assert APP.count("app.openWebLink()") == 2

    for text, language in [(EN, "English"), (ZH, "Chinese")]:
        for key in [
            "add.kind.file",
            "add.kind.link",
            "panel.dropTitle",
            "openPanel.message",
            "link.invalid.message",
        ]:
            assert f'"{key}"' in text, f"{language} missing {key}"

    print("Wheel content items contract passed.")


if __name__ == "__main__":
    main()
