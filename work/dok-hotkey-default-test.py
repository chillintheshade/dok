#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Sources" / "dok" / "AppState.swift"


def require(source: str, needle: str, reason: str) -> None:
    if needle not in source:
        raise AssertionError(f"Missing {reason}: {needle}")


def main() -> None:
    source = SOURCE.read_text()

    requirements = [
        ("var keyCode: UInt16 = 53 // Escape", "default Escape key code"),
        ("var modifiers: NSEvent.ModifierFlags = [.command]", "command-only default modifier"),
        ("53: \"Esc\"", "user-facing Escape key label"),
        ("init(keyCode: UInt16 = 53, modifiers: NSEvent.ModifierFlags = [.command])", "default initializer uses command + Escape"),
        # 迁移的行为由 dok-logic-unit-test.py 实际运行检查；这里只确认规则还在。
        ("HotkeyConfig(keyCode: 2, modifiers: [.command, .shift])", "old default hotkey migration"),
        ("HotkeyConfig(keyCode: 50, modifiers: [.command])", "command-grave default migration"),
        ("settings.hotkey = HotkeyConfig() // 默认 ⌘Esc", "migration resets to the new default"),
    ]

    for needle, reason in requirements:
        require(source, needle, reason)

    print("Hotkey default contract passed.")


if __name__ == "__main__":
    main()
