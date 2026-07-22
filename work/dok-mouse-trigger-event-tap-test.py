#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Sources" / "dok" / "DokApp.swift"


def require(source: str, needle: str, reason: str) -> None:
    if needle not in source:
        raise AssertionError(f"Missing {reason}: {needle}")


def main() -> None:
    source = SOURCE.read_text()

    requirements = [
        ("private var mouseEventTap: CFMachPort?", "stored mouse event tap"),
        ("private var mouseEventRunLoopSource: CFRunLoopSource?", "stored event tap run loop source"),
        ("CGEvent.tapCreate", "low-level mouse event tap"),
        ("CGEventMask(1 << CGEventType.otherMouseDown.rawValue)", "middle and side mouse-down events observed"),
        ("CGEventMask(1 << CGEventType.otherMouseUp.rawValue)", "hold-mode mouse-up events observed"),
        ("mouseEventButtonNumber", "button number read from CGEvent"),
        ("tapDisabledByTimeout", "event tap timeout recovery"),
        ("CGEvent.tapEnable", "event tap re-enabled when disabled"),
        ("installMouseEventTap", "separate installer for mouse trigger"),
        ("removeMouseEventTap", "separate cleanup for mouse trigger"),
        ("handleMouseTriggerDown(buttonNumber:", "shared mouse down behavior"),
        ("handleMouseTriggerUp(buttonNumber:", "shared mouse up behavior"),
    ]

    for needle, reason in requirements:
        require(source, needle, reason)

    print("Mouse trigger event tap contract passed.")


if __name__ == "__main__":
    main()
