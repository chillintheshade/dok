#!/usr/bin/env python3
"""轮盘常驻合约：三种模式、点击穿透、拖动不误触、小圆点、与快捷键共存。"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
S = ROOT / "Sources" / "dok"


def main() -> None:
    state = (S / "AppState.swift").read_text()
    settings = (S / "SettingsView.swift").read_text()
    app = (S / "DokApp.swift").read_text()
    view = (S / "DokWheelView.swift").read_text()
    window = (S / "PinnedWheelWindow.swift").read_text()
    drag = (S / "PinnedDragTracker.swift").read_text()
    orb = (S / "PinnedOrbWindow.swift").read_text()
    ctrl = (S / "PinnedWheelController.swift").read_text()
    agents = (ROOT / "AGENTS.md").read_text()

    # 设置：默认关闭，旧配置兼容
    assert "enum PinnedMode: String, Codable, CaseIterable" in state
    assert "var pinnedMode: PinnedMode = .off" in state
    assert "forKey: .pinnedMode)) ?? .off" in state
    assert "selection: $appState.settings.pinnedMode" in settings
    assert "pinnedMenuItems" in app
    for lang in ("en", "zh-Hans"):
        strings = (ROOT / "Resources" / f"{lang}.lproj" / "Localizable.strings").read_text()
        for key in ("pinned.title", "pinned.off", "pinned.desktop", "pinned.floating", "pinned.lock", "pinned.unlock"):
            assert f'"{key}"' in strings, (lang, key)

    # 窗口：不抢焦点，不因外部点击收起，透明处穿透
    assert ".nonactivatingPanel" in window and ".nonactivatingPanel" in orb
    assert "dismiss()" not in window
    assert "if inside == ignoresMouseEvents { ignoresMouseEvents = !inside }" in window
    assert "isInsideWheel(at:" in window
    assert "didChangeOcclusionStateNotification" in window
    assert "NSWorkspace.didWakeNotification" in window
    assert "activeSpaceDidChangeNotification" in window
    assert "appState.$settings" in window, "radius and icon changes update hit testing at once"
    assert "beginConsuming(.pinnedWheel)" in window and "endConsuming(.pinnedWheel)" in window
    assert "!interaction.isMenuVisible || interaction.isOccluded" in view, "no per-frame ring while covered"

    # 拖动：4pt 阈值；按下不触发动作；可锁定；Esc 取消；回到屏幕内
    assert "static let threshold: CGFloat = 4" in drag
    assert "static func clampedCenter(" in drag
    down = window.split("case .leftMouseDown:", 1)[1].split("case .leftMouseDragged:", 1)[0]
    assert "tracker.press" in down and "performClick" not in down
    assert "case .click:" in window and "performClick(at:" in window
    assert "isDraggable" in window and "pinnedLocked" in ctrl
    assert "CGEventSource.keyState(.combinedSessionState, key: 53)" in window
    assert "interaction.isDragging" in view and "1.02" in view
    assert "didChangeScreenParametersNotification" in ctrl and "clampedCenter" in ctrl
    assert "NSHapticFeedbackManager" in window and "hapticFeedback" in window

    # 小圆点
    assert "static let diameter: CGFloat = 44" in orb
    assert "static let hoverExpandDelay: TimeInterval = 0.15" in ctrl
    assert "static let collapseDelay: TimeInterval = 0.25" in ctrl
    assert "pressedMouseButtons" in ctrl, "no hover expand while a button is down"
    assert "TimelineView(.animation" not in orb, "the orb never runs per-frame"
    assert "snappedToEdge" in orb or "snappedToEdge" in ctrl
    assert "beginConsuming(.pinnedOrb)" in ctrl and "endConsuming(.pinnedOrb)" in ctrl
    assert ".fullScreenAuxiliary" in ctrl or ".fullScreenAuxiliary" in orb
    assert "reevaluateStream()" in ctrl

    # 共存
    down = app.split("func handleHotKeyDown()", 1)[1].split("func handleHotKeyUp()", 1)[0]
    assert "pinnedController?.isWheelExpanded == true" in down
    assert "Exception" in agents and "PinnedWheelWindow" in agents
    # 审查修复：右键菜单位置；丢失松手事件；按住时不展开；两种模式都复查音乐推送
    assert "contentView?.convert(event.locationInWindow, from: nil)" in window
    assert "tracker.isPressed, NSEvent.pressedMouseButtons == 0" in window, "a lost mouse-up can't leave a stuck drag"
    assert "guard NSEvent.pressedMouseButtons == 0 else { return }" in ctrl
    assert "window.contentView?.convert(event.locationInWindow, from: nil)" in ctrl
    assert ctrl.index("reevaluateStream()") < ctrl.index("// MARK: - 桌面模式"), "the stream re-check covers both modes"
    # 展开时小圆点仍可见、在轮盘旁边，随时能直接拖；一拖轮盘就收回。
    assert "wheel.isDraggable = false" in ctrl and "wheel.onDragEnded" not in ctrl
    assert "orb.orderOut(nil)" not in ctrl
    assert "func expandedCenter(for orbCenter: NSPoint) -> NSPoint" in ctrl
    began = ctrl.split("window.onDragBegan", 1)[1].split("window.onDragEnded", 1)[0]
    assert "collapse()" in began
    # Esc：应用不在前台收不到按键，轮盘显示期间临时注册 Esc。
    assert "EventHotKeyID(signature: OSType(0x50494531), id: 2)" in app
    assert "kEventParamDirectObject" in app and "typeEventHotKeyID" in app
    assert "UnregisterEventHotKey(ref)" in app.split("func updateEscapeHotKey()", 1)[1][:700]
    assert "updateEscapeHotKey()" in app.split("func showDok()", 1)[1].split("func closeDok()", 1)[0]
    assert "updateEscapeHotKey()" in app.split("created.onDidHide", 1)[1][:200]
    assert "onExpansionChanged" in ctrl and "var wantsEscape: Bool" in ctrl
    print("Pinned wheel contract passed.")


if __name__ == "__main__":
    main()
