#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "Sources" / "Arcly"


assert not (SOURCES / "ProManager.swift").exists(), "paid-tier manager must stay removed"

source_text = "\n".join(path.read_text() for path in SOURCES.glob("*.swift"))
for forbidden in (
    "import StoreKit",
    "ProManager",
    "appState.pro",
    "UpgradeView",
    "showUpgrade",
    "localProUnlocked",
    "canAddFolder",
    "canCustomizeSize",
    "canControlMusic",
):
    assert forbidden not in source_text, f"paid-tier code returned: {forbidden}"

app_state = (SOURCES / "AppState.swift").read_text()
assert "static let maxSlots = 12" in app_state, "all users should receive 12 wheel slots"

settings = (SOURCES / "SettingsView.swift").read_text()
assert "appState.settings.apps.count >= AppState.maxSlots" in settings
assert "guard appState.settings.apps.count < AppState.maxSlots" in settings

pbxproj = (ROOT / "Arcly.xcodeproj" / "project.pbxproj").read_text()
assert "ProManager.swift" not in pbxproj

for relative in (
    "Resources/en.lproj/Localizable.strings",
    "Resources/zh-Hans.lproj/Localizable.strings",
):
    localization = (ROOT / relative).read_text()
    for forbidden in ('"upgrade.', '"pro.', '"settings.proUnlock"'):
        assert forbidden not in localization, f"stale paid copy in {relative}: {forbidden}"

public_docs = "\n".join(
    (ROOT / relative).read_text()
    for relative in (
        "README.md",
        "AGENTS.md",
        "docs/appstore/store-copy.md",
        "docs/appstore/privacy-policy.html",
        "docs/appstore/marketing/screen-3.html",
    )
)
for forbidden in ("localProUnlocked", "Upgrade to Pro", "升级 Pro", "Buy Pro", "购买 Pro"):
    assert forbidden not in public_docs, f"stale paid-tier claim in active docs: {forbidden}"

print("Arcly free feature contract passed.")
