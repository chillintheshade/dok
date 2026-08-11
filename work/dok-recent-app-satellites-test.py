#!/usr/bin/env python3
"""最近内容卫星的持久化、筛选、快照、布局、状态与交互契约。"""
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
STATE = (ROOT / "Sources" / "dok" / "AppState.swift").read_text()
VIEW = (ROOT / "Sources" / "dok" / "DokWheelView.swift").read_text()
WINDOW = (ROOT / "Sources" / "dok" / "DokWheelWindow.swift").read_text()
APP = (ROOT / "Sources" / "dok" / "DokApp.swift").read_text()
SETTINGS = (ROOT / "Sources" / "dok" / "SettingsView.swift").read_text()
EN = (ROOT / "Resources" / "en.lproj" / "Localizable.strings").read_text()
ZH = (ROOT / "Resources" / "zh-Hans.lproj" / "Localizable.strings").read_text()


def main() -> None:
    state_requirements = [
        ("var recentApps: [AppItem] = []", "persisted MRU list"),
        ("var recentAppCount: Int = 2", "default satellite count"),
        ("var showRecentApps: Bool = true", "independent visibility setting"),
        ("forKey: .recentApps", "tolerant MRU decoding"),
        ("forKey: .recentAppCount", "tolerant count decoding"),
        ("forKey: .showRecentApps", "tolerant visibility decoding"),
        ("decodedRecentAppCount != 0", "legacy zero-count migration"),
        ("prefix(10)", "ten-entry MRU cap"),
        ("NSWorkspace.didActivateApplicationNotification", "workspace activation tracking"),
        ("$0.bundleIdentifier != bundleIdentifier", "MRU de-duplication"),
        ("item.bundleIdentifier != ownBundleIdentifier", "dok exclusion"),
        ("!fixedBundleIdentifiers.contains(item.bundleIdentifier)", "fixed-slot exclusion"),
        ("func recordOpenedFolder(_ item: AppItem)", "folder MRU recording"),
        ("guard item.itemType == .fileOrFolder, item.isFolder", "folder-only recent file-system content"),
        ("private func eligibleRecentContent", "shared app/folder eligibility filter"),
        ("case .webLink:", "website exclusion from recent content"),
        ("return false", "ineligible file and website rejection"),
        ("func snapshotRecentApps()", "presentation snapshot"),
        ("func recentContentForSettingsPreview()", "settings preview snapshot"),
        ("settings.showRecentApps", "visibility-gated snapshot"),
        ("Array(eligible.prefix(settings.recentAppCount))", "count-limited snapshot"),
        ("recentActivatedBundleIdentifiers", "shared activation MRU for player routing"),
    ]
    for needle, description in state_requirements:
        assert needle in STATE, f"missing {description}"

    view_requirements = [
        ("enum RecentAppSatelliteGeometry", "shared satellite geometry"),
        ("static let iconScale: CGFloat = 0.75", "three-quarter icon scale"),
        ("switch min(max(count, 0), 4)", "four-satellite cap"),
        ("case 1: angles = [90]", "single centered satellite"),
        ("case 2: angles = [78, 102]", "symmetric two-satellite arc"),
        ("case 3: angles = [70, 90, 110]", "wider symmetric three-satellite arc"),
        ("case 4: angles = [63, 81, 99, 117]", "wider symmetric four-satellite arc"),
        ("let orbit = outerRadius + edgeGap", "single circular orbit"),
        ("recentAppSatellitesLayer", "satellite view layer"),
        ("NativeGlassSamplingLayer(", "native glass satellite base"),
        ('Image(systemName: "clock.fill")', "recent-app clock badge"),
        ("if app.isRunning", "running-state indicator gate"),
        (".fill(.primary)", "running black/primary dot"),
        ("appState.selectedRecentAppIndex == index", "satellite selection feedback"),
        ("static let windowSize: CGFloat = 640", "unclipped max-radius satellite window"),
    ]
    for needle, description in view_requirements:
        assert needle in VIEW, f"missing {description}"

    assert WINDOW.find("let newRecentIndex = satelliteIndex") < WINDOW.find(
        "newRecentIndex == nil ? slotIndex"
    ), "satellite hit testing must precede fixed-slot/outside rejection"
    for needle, description in [
        ("self.appState.snapshotRecentApps()", "show-time snapshot"),
        ("private func satelliteIndex", "independent circular satellite hit test"),
        ("let hitRadius = baseDiameter / 2 + 4", "circular hit radius"),
        ("func selectedAppForActivation() -> AppItem?", "shared selected-app resolver"),
        ("appState.recentAppSnapshot[index]", "satellite activation target"),
    ]:
        assert needle in WINDOW, f"missing {description}"

    assert APP.count("wheelWindow?.selectedAppForActivation()") == 2, (
        "mouse and keyboard hold release must both activate satellites"
    )
    assert '$appState.settings.showRecentApps' in SETTINGS
    assert '$appState.settings.recentAppCount' in SETTINGS
    assert 'appState.recentContentForSettingsPreview()' in SETTINGS
    assert 'private var recentPreviewSatellites' in SETTINGS
    assert 'RecentAppSatelliteGeometry.offsets(' in SETTINGS
    assert 'private func recentPreviewSatellite' in SETTINGS
    assert '.allowsHitTesting(false)' in SETTINGS
    assert 'ForEach(1...4, id: \.self)' in SETTINGS
    assert '.disabled(!appState.settings.showRecentApps)' in SETTINGS
    assert 'Loc.string("settings.recentApps")' in SETTINGS
    assert '"settings.recentApps" = "Recent Content";' in EN
    assert '"settings.recentApps" = "最近内容";' in ZH

    print("Recent-content satellites contract passed.")


if __name__ == "__main__":
    main()
