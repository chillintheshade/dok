#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WHEEL = (ROOT / "Sources/dok/DokWheelView.swift").read_text()
SETTINGS = (ROOT / "Sources/dok/SettingsView.swift").read_text()

assert ".fill(Color.primary.opacity(0.055))" in WHEEL, (
    "the live wheel selection wedge must use the monochrome semantic cursor"
)
assert ".fill(Color.accentColor.opacity(0.12))" not in WHEEL
assert ".fill(SettingsDesign.selectedSurface)" in SETTINGS, (
    "the settings wheel preview selection must match the monochrome language"
)

print("monochrome selection contract passed")
