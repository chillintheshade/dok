#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
APP_STATE = (ROOT / "Sources/dok/AppState.swift").read_text()
SETTINGS = (ROOT / "Sources/dok/SettingsView.swift").read_text()
DOK_APP = (ROOT / "Sources/dok/DokApp.swift").read_text()

assert "hotkeyRecordingCancelled" in APP_STATE

toolbar_post = "NotificationCenter.default.post(name: .hotkeyRecordingCancelled, object: nil)"
selection = "selectedSettingsTab = tab"
assert toolbar_post in DOK_APP, "toolbar pane changes must cancel hotkey recording"
assert DOK_APP.index(toolbar_post) < DOK_APP.index(selection), "cancel recording before changing panes"

assert ".onReceive(NotificationCenter.default.publisher(for: .hotkeyRecordingCancelled))" in SETTINGS
assert ".onDisappear" in SETTINGS

recorder_start = SETTINGS.index("struct HotkeyRecorderRow")
recorder_end = SETTINGS.index("// MARK: - 按键帽组件", recorder_start)
recorder = SETTINGS[recorder_start:recorder_end]
assert recorder.count("stopRecording()") >= 4
assert "NSEvent.removeMonitor(m)" in recorder
assert "localMonitor = nil" in recorder
assert "globalMonitor = nil" in recorder
assert "event.keyCode == 53 && mods.isEmpty" in recorder, "only bare Escape should cancel recording"
assert recorder.index("event.keyCode == 53 && mods.isEmpty") < recorder.index("appState.settings.hotkey = HotkeyConfig"), (
    "Command-Escape must reach hotkey assignment instead of being cancelled"
)

print("Hotkey recording cancellation contract passed.")
