#!/usr/bin/env python3
"""Dock 通知角标的数据、快照、显示和设置契约。"""
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
READER = (ROOT / "Sources" / "Arcly" / "DockNotificationBadgeReader.swift").read_text()
STATE = (ROOT / "Sources" / "Arcly" / "AppState.swift").read_text()
WINDOW = (ROOT / "Sources" / "Arcly" / "ArclyWheelWindow.swift").read_text()
VIEW = (ROOT / "Sources" / "Arcly" / "ArclyWheelView.swift").read_text()
SETTINGS = (ROOT / "Sources" / "Arcly" / "SettingsView.swift").read_text()
EN = (ROOT / "Resources" / "en.lproj" / "Localizable.strings").read_text()
ZH = (ROOT / "Resources" / "zh-Hans.lproj" / "Localizable.strings").read_text()


def main() -> None:
    for needle, description in [
        ("AXIsProcessTrusted()", "silent Accessibility permission check"),
        ('withBundleIdentifier: "com.apple.dock"', "Dock process lookup"),
        ('stringAttribute("AXStatusLabel"', "Dock status-label source"),
        ("kAXURLAttribute", "Dock URL source"),
        ("static let timeout: TimeInterval = 0.1", "bounded 100ms query"),
        ("completion.wait(timeout: .now() + timeout)", "timeout fail-open behavior"),
        ("guard app.itemType == .app, app.isRunning", "running-app-only badges"),
        ("byPath[Self.normalizedPath(app.path)]", "path-first matching"),
        ("byBundleIdentifier[app.bundleIdentifier]", "bundle fallback matching"),
        ("byTitle[Self.normalizedTitle(app.displayName)]", "display-name fallback matching"),
    ]:
        assert needle in READER, f"missing {description}"
    assert "AXIsProcessTrustedWithOptions" not in READER, "badge lookup must never prompt"

    for needle, description in [
        ("var showNotificationBadges: Bool = true", "default-on badge setting"),
        ("forKey: .showNotificationBadges", "legacy settings fallback"),
        ("notificationBadgeSnapshot", "presentation badge snapshot"),
        ("func snapshotNotificationBadges()", "show-time badge snapshot function"),
        ("settings.showNotificationBadges", "setting-gated query"),
        ("func notificationBadge(for app: AppItem)", "shared main/satellite lookup"),
    ]:
        assert needle in STATE, f"missing {description}"

    assert "self.appState.snapshotNotificationBadges()" in WINDOW
    assert WINDOW.find("self.appState.snapshotNotificationBadges()") < WINDOW.find(
        "self.appState.isMenuVisible = false"
    ), "badge snapshot must finish before presentation starts"

    assert VIEW.count("SlotNotificationBadge(text: badge") == 2, (
        "main slots and satellites must both render notification badges"
    )
    assert 'return "99+"' in VIEW, "large numeric badges must clamp to 99+"
    assert "y: -iconSize * 0.36" in VIEW, "main badge must sit at top-right"
    assert "y: -baseDiameter * 0.31" in VIEW, "satellite badge must sit at top-right"
    assert 'Image(systemName: "clock.fill")' in VIEW, "recent clock badge must remain"

    assert '$appState.settings.showNotificationBadges' in SETTINGS
    assert 'Loc.string("settings.notificationBadges")' in SETTINGS
    assert '"settings.notificationBadges" = "Notification Badges";' in EN
    assert '"settings.notificationBadges" = "通知角标";' in ZH
    assert ".frame(width: 920, height: 520)" in SETTINGS

    print("Notification badge contract passed.")


if __name__ == "__main__":
    main()
