#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PROJECT = (ROOT / "project.yml").read_text()
PACKAGE = (ROOT / "Package.swift").read_text()
WHEEL = (ROOT / "Sources" / "dok" / "DokWheelView.swift").read_text()
SETTINGS = (ROOT / "Sources" / "dok" / "SettingsView.swift").read_text()


def require(source: str, needle: str, reason: str) -> None:
    if needle not in source:
        raise AssertionError(f"Missing {reason}: {needle}")


def main() -> None:
    project_requirements = [
        ('macOS: "13.0"', "macOS 13 deployment target"),
        ('MACOSX_DEPLOYMENT_TARGET: "13.0"', "explicit macOS 13 build setting"),
        ("- arm64", "Apple Silicon release slice"),
        ("- x86_64", "Intel release slice"),
        ("ONLY_ACTIVE_ARCH: false", "Universal 2 release output"),
    ]
    for needle, reason in project_requirements:
        require(PROJECT, needle, reason)

    require(PACKAGE, ".macOS(.v13)", "Swift package macOS 13 baseline")

    wheel_requirements = [
        ("if #available(macOS 26.0, *)", "runtime native/compatibility split"),
        ("NSGlassEffectView", "unchanged native macOS 26 material"),
        ("CompatibilityGlassEffectView", "macOS 15 compatibility material"),
        ("NSVisualEffectView", "public AppKit compatibility sampler"),
        ("dokCapsuleGlass", "availability-safe center capsule"),
    ]
    for needle, reason in wheel_requirements:
        require(WHEEL, needle, reason)

    require(SETTINGS, "if #available(macOS 26.0, *)", "availability-safe settings controls")
    require(SETTINGS, "NSVisualEffectView", "macOS 13-15 settings root material")
    require(SETTINGS, ".buttonStyle(.plain)", "availability-safe monochrome settings buttons")
    require(SETTINGS, ".dokKeyCapGlass()", "macOS 15 key-cap fallback")

    print("dok platform compatibility contract passed.")


if __name__ == "__main__":
    main()
