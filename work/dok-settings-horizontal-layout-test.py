#!/usr/bin/env python3
"""Settings layout contract for the quiet, monochrome in-window navigation design."""
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SETTINGS = (ROOT / "Sources/dok/SettingsView.swift").read_text()
APP = (ROOT / "Sources/dok/DokApp.swift").read_text()


def require(needle: str, description: str) -> None:
    assert needle in SETTINGS, f"missing {description}: {needle}"


for needle, description in [
    ("static let windowWidth: CGFloat = 920", "fixed settings width token"),
    ("static let windowHeight: CGFloat = 520", "fixed settings height token"),
    ("static let sidebarWidth: CGFloat = 216", "fixed sidebar width"),
    ("static let navigationRowHeight: CGFloat = 34", "navigation row height"),
    ("static let rowHeight: CGFloat = 44", "settings row height"),
    ("static let controlWidth: CGFloat = 130", "stable trailing control column"),
    ("static let dividerWidth: CGFloat = 0.5", "hairline divider"),
    ("static let selectedSurface = Color.primary.opacity(0.055)", "monochrome selection fill"),
    ("private struct SettingsRootGlassLayer", "single root glass implementation"),
    ("private struct SettingsWindowDragHandle", "dedicated settings window drag strip"),
    ("window?.performDrag(with: event)", "native window dragging from the explicit strip"),
    ("glass.style = .regular", "native regular root glass"),
    ("effect.material = .sidebar", "macOS 13-15 compatibility root material"),
    ("@State private var selectedTab: SettingsTab", "stable in-window selection state"),
    (".tint(.primary)", "monochrome native control accent"),
    ("private var settingsSidebar", "in-window sidebar"),
    ("ForEach(SettingsTab.allCases)", "shared navigation rows"),
    (".frame(width: SettingsDesign.sidebarWidth)", "sidebar token usage"),
    ("private let pieSize: CGFloat = 452", "fitted wheel preview"),
    (".frame(width: 475, height: 500", "fixed wheel preview canvas"),
    (".frame(width: SettingsDesign.actionPaneWidth)", "stable wheel action rail"),
    ("private var controlList", "direct wheel actions"),
    ("private var recentAppsControl", "recent content controls"),
    ("private struct SettingsGroup", "shared low-contrast settings group"),
    (".settingsInsetSurface()", "semantic inset fill"),
    ("private struct SettingRow", "stable settings row primitive"),
    (".frame(width: SettingsDesign.controlWidth, alignment: .trailing)", "trailing control alignment"),
    ("HStack(alignment: .top, spacing: SettingsDesign.sectionSpacing)", "balanced general columns"),
    (".frame(width: SettingsDesign.generalContentWidth)", "fixed general settings grid"),
    ("SettingsGroup(title: Loc.string(\"settings.group.trigger\"))", "trigger section"),
    ("SettingsGroup(title: Loc.string(\"settings.group.wheel\"))", "wheel section"),
    ("SettingsGroup(title: Loc.string(\"settings.group.system\"))", "system section"),
]:
    require(needle, description)

assert "Color.accentColor" not in SETTINGS, "settings must not use the system accent hue"
assert ".foregroundColor(.green)" not in SETTINGS, "settings must not use green action states"
assert ".foregroundStyle(.orange)" not in SETTINGS, "settings warnings stay monochrome"
assert ".shadow(" not in SETTINGS, "settings must stay flat"
assert ".buttonStyle(.glass)" not in SETTINGS, "inner controls must not nest glass"
assert ".scaleEffect((pieSize + 34) / pieSize)" not in SETTINGS, (
    "wheel preview must not draw an oversized decorative halo outside the wheel"
)
assert "SettingsPageHeader" not in SETTINGS, "content must not repeat sidebar titles"
assert "NSToolbarDelegate" not in APP, "the old preference toolbar must stay removed"
assert "configureSettingsToolbar" not in APP, "the old preference toolbar must stay removed"
assert 'window.title = Loc.string("settings.windowTitle")' in APP
assert "window.setContentSize(NSSize(width: 920, height: 520))" in APP
assert "window.titlebarAppearsTransparent = true" in APP
assert "window.isOpaque = false" in APP
assert "window.backgroundColor = .clear" in APP
assert "window.isMovableByWindowBackground = false" in APP, (
    "only the native title bar may move the settings window so wheel item drags remain interactive"
)
assert "window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]" in APP, (
    "settings root surface must extend behind the native title bar"
)
assert "window.standardWindowButton(.miniaturizeButton)?.isHidden = false" in APP
assert "window.standardWindowButton(.zoomButton)?.isHidden = false" in APP
assert "w.makeKeyAndOrderFront(nil)" in APP
assert "activateSettingsWindow(w, generation: settingsActivationGeneration)" in APP
assert "NSRunningApplication.current.activate" in APP
assert "window.makeKeyAndOrderFront(nil)" not in APP, (
    "settings may be ordered front only once; activation retries must not redisplay the window"
)
assert "SettingsRootGlassLayer()\n                .ignoresSafeArea()" in SETTINGS, (
    "the single root glass must visually unite the title bar and settings content"
)
assert "override func viewDidMoveToWindow()" in SETTINGS
assert "coordinator?.focusWhenAttached(field)" in SETTINGS, (
    "the app picker search field must request focus after it is attached to its sheet window"
)
assert "editor.hasMarkedText()" in SETTINGS, (
    "SwiftUI updates must not overwrite active CJK input-method composition"
)
assert "NSApplication.didBecomeActiveNotification" in SETTINGS
assert "NSWindow.didBecomeKeyNotification" in SETTINGS
search = SETTINGS.split("struct SearchField: NSViewRepresentable", 1)[1]
assert "window.isVisible, window.isKeyWindow, NSApp.isActive" in search
assert "window.makeFirstResponder(field)" in search
assert "keyboardSelectionDidChangeNotification" not in search
assert "window.makeKey()" not in search and "NSApp.activate" not in search
assert "controlTextDidBeginEditing" in search and "finishInitialFocus()" in search
assert ".frame(height: 22)" in SETTINGS, (
    "the explicit drag strip must stay narrow and clear of wheel item drag targets"
)

print("settings quiet layout contract passed")
