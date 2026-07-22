#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
APP_STATE = (ROOT / "Sources/dok/AppState.swift").read_text()
SETTINGS = (ROOT / "Sources/dok/SettingsView.swift").read_text()

assert "hotkeyRecordingCancelled" in APP_STATE

sidebar_post = "NotificationCenter.default.post(name: .hotkeyRecordingCancelled, object: nil)"
selection = "selectedTab = tab"
assert sidebar_post in SETTINGS, "sidebar actions must cancel hotkey recording"
assert SETTINGS.index(sidebar_post) < SETTINGS.index(selection), "cancel recording before changing tabs"

assert ".onReceive(NotificationCenter.default.publisher(for: .hotkeyRecordingCancelled))" in SETTINGS
assert ".onDisappear" in SETTINGS

recorder_start = SETTINGS.index("struct HotkeyRecorderRow")
recorder_end = SETTINGS.index("// MARK: - 按键帽组件", recorder_start)
recorder = SETTINGS[recorder_start:recorder_end]
assert recorder.count("stopRecording()") >= 4
assert "NSEvent.removeMonitor(m)" in recorder
assert "localMonitor = nil" in recorder
assert "globalMonitor = nil" in recorder

print("Hotkey recording cancellation contract passed.")
