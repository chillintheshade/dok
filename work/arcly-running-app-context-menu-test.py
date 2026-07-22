#!/usr/bin/env python3
"""运行中 App 槽位右键退出菜单契约。"""
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WINDOW = (ROOT / "Sources" / "Arcly" / "ArclyWheelWindow.swift").read_text()
APP = (ROOT / "Sources" / "Arcly" / "ArclyApp.swift").read_text()
EN = (ROOT / "Resources" / "en.lproj" / "Localizable.strings").read_text()
ZH = (ROOT / "Resources" / "zh-Hans.lproj" / "Localizable.strings").read_text()


def main() -> None:
    requirements = [
        ("self?.handleRightClick(event)", "local right-click routing"),
        ("slotIndex(at: NSEvent.mouseLocation)", "shared slot hit testing"),
        ("app.itemType == .app", "file and folder exclusion"),
        ("app.isRunning", "running-app gate"),
        ("let menu = NSMenu()", "native context menu"),
        ('title: Loc.string("wheel.quitRunningApp")', "localized quit item"),
        ("menu.addItem(quitItem)", "single quit action"),
        ("contentView?.convert(event.locationInWindow, from: nil)", "flipped-view menu positioning"),
        ("contextMenuApplication?.terminate()", "running app termination"),
        ("suspendGlobalInteractionMonitors()", "global monitor suspension"),
        ("installGlobalInteractionMonitors()", "global monitor restoration"),
        ("private(set) var isContextMenuOpen = false", "menu tracking state"),
    ]
    for needle, description in requirements:
        assert needle in WINDOW, f"missing {description}"

    handler = WINDOW.split("private func handleRightClick", 1)[1].split(
        "@objc private func quitContextMenuApplication", 1
    )[0]
    assert handler.count("menu.addItem(") == 1, "context menu must contain only Quit"
    assert handler.count("dismiss()") >= 2, "all non-running-app right clicks must dismiss"

    assert APP.count("guard wheelWindow?.isContextMenuOpen != true else { return }") == 2, (
        "hotkey-up and mouse-up must not launch while the context menu is open"
    )
    assert '"wheel.quitRunningApp" = "Quit";' in EN
    assert '"wheel.quitRunningApp" = "退出";' in ZH

    print("Running-app context menu contract passed.")


if __name__ == "__main__":
    main()
