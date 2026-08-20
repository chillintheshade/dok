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
        ("decoded.hotkey.keyCode == 2 && decoded.hotkey.modifiers == [.command, .shift]", "old default hotkey migration"),
        ("decoded.hotkey.keyCode == 50 && decoded.hotkey.modifiers == [.command]", "command-grave default migration"),
        ("重置为默认 ⌘Esc", "migration comment reflects new default"),
    ]

    for needle, reason in requirements:
        require(source, needle, reason)

    print("Hotkey default contract passed.")


if __name__ == "__main__":
    main()
