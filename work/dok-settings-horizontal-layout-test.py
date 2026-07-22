#!/usr/bin/env python3
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
settings = root / "Sources/dok/SettingsView.swift"
app = root / "Sources/dok/DokApp.swift"
state = root / "Sources/dok/AppState.swift"

settings_text = settings.read_text()
app_text = app.read_text()
state_text = state.read_text()

checks = [
    ("enum SettingsTab", "settings tabs are modeled explicitly for sidebar navigation"),
    ("struct SettingsSidebar", "settings window has a left sidebar component"),
    ("struct SettingsSidebarButton", "sidebar rows have a dedicated reusable row view"),
    ("SettingsSidebar(selectedTab: $selectedTab)", "settings root uses the sidebar"),
    (".frame(width: 920, height: 520)", "both settings tabs use the same fixed window height"),
    ('case .apps: return Loc.string("settings.tab.wheel")', "apps tab is renamed to wheel"),
    ("private let pieSize: CGFloat = 476", "app wheel preview is enlarged to eat the usable vertical space"),
    ("private var previewMenuRadius: CGFloat", "settings preview uses the runtime wheel radius"),
    ("private var previewOuterDiameter: CGFloat", "settings preview measures the rendered wheel before scaling"),
    ("min((pieSize - 28) / previewOuterDiameter", "wheel preview scales large radii to stay inside the stage"),
    ("private var wheelStage", "apps tab keeps the wheel in a dedicated centered stage"),
    ("private var controlList", "apps tab uses a compact settings-style action list"),
    ("private var appsPreviewPane", "apps tab keeps the wheel as the primary preview pane"),
    ("private var appsControlPane", "apps tab has a right-side control pane"),
    ("private func actionTile", "apps tab uses compact horizontal-setting action tiles"),
    ("private struct SettingsGroup", "general tab uses compact grouped settings instead of a long form"),
    ("private struct SettingRow", "general controls use reusable full-width setting rows"),
    ("private func inlineSetting", "general tab uses a shared alignment primitive for inline controls"),
    ("private func toggleCell", "general tab uses aligned toggle cells"),
    ("private func compactSlider", "general tab uses aligned compact sliders"),
    ("private var triggerGroup", "general tab keeps launch controls grouped"),
    ("private var playbackGroup", "general tab keeps playback controls grouped"),
    ("private var feedbackGroup", "general tab keeps haptics and sound in a separate feedback group"),
    ("private var wheelGroup", "general tab keeps wheel controls grouped"),
    ("private var systemGroup", "general tab keeps system controls grouped"),
]

for needle, description in checks:
    assert needle in settings_text, f"Missing {description}: {needle}"

assert ".frame(width: 520, height: 620)" not in settings_text, "old narrow settings frame is still present"
assert "window.setContentSize(NSSize(width: 920, height: 520))" in app_text, "settings NSWindow size was not updated"
assert "window.setContentSize(NSSize(width: 840, height: 420))" not in app_text, "previous loose NSWindow content size is still present"
assert "window.setContentSize(NSSize(width: 520, height: 620))" not in app_text, "old NSWindow content size is still present"
assert "window.setContentSize(NSSize(width: 820, height: 420))" not in app_text, "previous cramped NSWindow content size is still present"
assert "window.setContentSize(NSSize(width: 860, height: 440))" not in app_text, "previous loose NSWindow content size is still present"
assert "window.setContentSize(NSSize(width: 860, height: 560))" not in app_text, "previous oversized NSWindow content size is still present"
assert "window.setContentSize(NSSize(width: 860, height: 470))" not in app_text, "previous loose NSWindow content size is still present"

root_layout = re.search(r"struct SettingsView: View \{.*?var body: some View \{(?P<body>.*?)\n    \}", settings_text, re.S)
assert root_layout, "SettingsView body not found"
assert "HStack(spacing: 0)" in root_layout.group("body"), "SettingsView root is not horizontal"
assert ".frame(width: 920, height: 520)" in root_layout.group("body"), "Settings root should keep one fixed height for both tabs"
assert "windowHeight" not in settings_text, "Settings window height should not adapt per tab"
assert "SettingsWindowSizer" not in settings_text, "Settings window should not resize when switching tabs"

settings_tab_enum = re.search(r"private enum SettingsTab: String, CaseIterable, Identifiable \{(?P<body>.*?)\n\}", settings_text, re.S)
assert settings_tab_enum, "SettingsTab enum not found"
tab_body = settings_tab_enum.group("body")
assert "case apps" in tab_body and "case general" in tab_body, "Settings should keep Wheel and General tabs"
assert "case pro" not in tab_body, "Pro tab should be removed from settings navigation"
assert "case about" not in tab_body, "About tab should be removed from settings navigation"
assert "case .pro" not in settings_text, "Settings content should no longer route to Pro tab"
assert "case .about" not in settings_text, "Settings content should no longer route to About tab"
assert "ProSettingsView" not in settings_text, "Unused Pro tab view should be removed"
assert "AboutView" not in settings_text, "Unused About tab view should be removed"

assert "SettingsPageScaffold" not in settings_text, "generic title scaffold should be removed with repeated page headers"
assert "SettingsPageHeader" not in settings_text, "right content should not repeat tab title/subtitle headers"

apps_layout = re.search(r"struct AppsSettingsView: View \{.*?var body: some View \{(?P<body>.*?)\n    \}", settings_text, re.S)
assert apps_layout, "AppsSettingsView body not found"
apps_body = apps_layout.group("body")
assert "HStack(alignment: .center, spacing: 12)" in apps_body, "Apps tab should use a balanced content row"
assert "appsHeader" not in settings_text, "Apps tab should not repeat its tab title in the content area"
assert ".padding(.horizontal, 12)" in apps_body, "Apps tab should use a compact horizontal gutter"
assert ".padding(.vertical, 0)" in apps_body, "Apps tab should not reserve top or bottom dead space"
assert ".frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)" in apps_body, "Apps content should stay centered while filling the fixed-height window"
assert "wheelStage\n            .frame(width: 500, height: 500, alignment: .center)" in settings_text, "wheel preview should use the full fixed-height stage"

control_pane = re.search(r"private var appsControlPane: some View \{(?P<body>.*?)\n    \}", settings_text, re.S)
assert control_pane, "appsControlPane not found"
control_body = control_pane.group("body")
assert "capacitySummary" not in settings_text, "Slot usage card should be removed from the wheel tab"
assert "selectedAppSummary" not in settings_text, "The low-value selected icon placeholder should be removed"
assert "controlList" in control_body, "Apps tab should keep only the direct wheel actions in the side pane"

sidebar_layout = re.search(r"private struct SettingsSidebar: View \{.*?var body: some View \{(?P<body>.*?)\n    \}", settings_text, re.S)
assert sidebar_layout, "SettingsSidebar body not found"
sidebar_body = sidebar_layout.group("body")
assert 'Text("dok")' not in sidebar_body, "sidebar should not duplicate the window title brand block"
assert "液态玻璃" not in sidebar_body, "sidebar should not include the bottom slogan card"
assert ".padding(.top, 12)" in sidebar_body, "sidebar top padding should be deliberate"
assert ".padding(.horizontal, 12)" in sidebar_body, "sidebar should keep a small horizontal inset"
assert ".padding(.bottom, 12)" in sidebar_body, "sidebar bottom padding should match the top"
assert ".padding(.top, 18)" not in sidebar_body, "sidebar should not keep the old large top gap"
assert 'Text("应用轮盘")' not in settings_text, "apps page title should share the same tab vocabulary instead of using a different custom title"

assert "一点提示" not in settings_text, "right inspector should not duplicate the center drag/delete hint"
assert 'Text("拖动图标排序，拖到中心删除。")' not in settings_text, "apps page header should not duplicate the wheel center hint"
assert "点击图标查看名称；拖动时中心会变成删除区。" not in settings_text, "duplicated drag/delete hint should be removed"
assert "排序会立即保存到下次唤出的轮盘。" not in settings_text, "bottom preview hint should be removed to keep the wheel balanced"
assert ".contentShape(Rectangle())" in settings_text, "sidebar and action rows need full-row click targets"
assert ".frame(maxWidth: .infinity, alignment: .leading)" in settings_text, "sidebar rows should fill the available row width"
assert "VStack(spacing: 0)" in settings_text, "action rows should be grouped as a native settings-style list"
assert ".frame(width: 172)" in settings_text, "sidebar should be compact but comfortably clickable"
assert ".frame(width: 208)" in settings_text, "right-side controls should remain legible beside the larger wheel"
assert ".formStyle(.grouped)" not in settings_text, "general tab should not use the old long grouped Form layout"
assert ".frame(width: 700)" in settings_text, "general settings should share one precise content grid"
general_layout = re.search(r"struct GeneralSettingsView: View \{.*?var body: some View \{(?P<body>.*?)\n    \}", settings_text, re.S)
assert general_layout, "GeneralSettingsView body not found"
general_body = general_layout.group("body")
assert "triggerGroup" in general_body and "wheelGroup" in general_body, "general tab should lead with the two primary control surfaces"
assert "HStack(alignment: .top, spacing: 12)" in general_body, "secondary groups should share the same top edge"
assert ".padding(.horizontal, 20)" in general_body, "general tab should use balanced horizontal padding"
assert ".padding(.vertical, 16)" in general_body, "general tab should use one measured vertical rhythm"
assert ".frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)" in general_body, "general controls should sit in the usable center instead of leaving a bottom void"
assert ".padding(.top, 10)" not in general_body, "general tab should not pin controls too high"
assert ".padding(.bottom, 10)" not in general_body, "general tab should not reserve a bottom gutter"
assert ".padding(.vertical, 18)" not in general_body, "general tab should not keep the old equal vertical padding"
assert 'SettingsGroup(title: Loc.string("settings.group.trigger"))' in settings_text, "general trigger group is missing or poorly named"
assert 'SettingsGroup(title: Loc.string("settings.group.playback"))' in settings_text, "general playback group is missing"
assert 'SettingsGroup(title: Loc.string("settings.group.feedback"))' in settings_text, "general feedback group is missing"
assert 'SettingsGroup(title: Loc.string("settings.group.wheel"))' in settings_text, "general wheel group is missing"
assert 'SettingsGroup(title: Loc.string("settings.group.system"))' in settings_text, "general system group is missing"
assert 'SettingsGroup(title: "偏好")' not in settings_text, "generic preference card should be split into clearer groups"
assert ".frame(width: pieSize + 34, height: pieSize + 34)" not in settings_text, "preview glow must not expand the wheel coordinate space"
assert ".scaleEffect((pieSize + 34) / pieSize)" in settings_text, "preview glow should scale visually without shifting icon coordinates"
assert "Pro 已激活" not in settings_text, "Old Pro activation view should be removed"
assert 'Text(Loc.string("settings.changeHotkey"))' in settings_text, "shortcut recorder needs an explicit change action"
assert ".contentShape(Rectangle())" in settings_text, "shortcut and navigation rows need full-row click targets"
assert "private var licensePanel" not in settings_text, "Pro settings panel should be removed with the Pro tab"
assert "private var aboutIdentityPanel" not in settings_text, "About settings panel should be removed with the About tab"

mode_enum = re.search(r"enum InteractionMode: String, Codable, CaseIterable \{(?P<body>.*?)\n\}", state_text, re.S)
assert mode_enum, "InteractionMode enum not found"
assert mode_enum.group("body").find("case click") < mode_enum.group("body").find("case hold"), "click mode should appear before hold mode"
assert "var interactionMode: InteractionMode = .click" in state_text, "click mode should remain the default interaction mode"

print("settings horizontal layout contract passed")
