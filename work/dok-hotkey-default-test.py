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
        ("var keyCode: UInt16 = 50 // key left of 1", "default grave key code"),
        ("var modifiers: NSEvent.ModifierFlags = [.command]", "command-only default modifier"),
        ("50: \"·\"", "user-facing key label for the key left of 1"),
        ("init(keyCode: UInt16 = 50, modifiers: NSEvent.ModifierFlags = [.command])", "default initializer uses command + grave key"),
        ("decoded.hotkey.keyCode == 2 && decoded.hotkey.modifiers == [.command, .shift]", "old default hotkey migration"),
        ("重置为默认 ⌘·", "migration comment reflects new default"),
    ]

    for needle, reason in requirements:
        require(source, needle, reason)

    print("Hotkey default contract passed.")


if __name__ == "__main__":
    main()
