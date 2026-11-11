#!/usr/bin/env python3
"""纯逻辑的行为测试：把整个应用的源码和一个测试入口编译在一起，真正运行断言。

覆盖三块：
- 设置解码与迁移：旧版或损坏的 settings.json 读进来是什么样。
- 槽位几何：图标位置、鼠标命中、拖放和键盘选择用的是同一套角度。
- Dock 角标匹配：同名的两个应用（双开微信）不会串号。

不构造 AppState（它会读写真实的设置文件），不启动应用，不碰用户的任何文件；
临时文件都在 work/ 下的临时目录里，结束即删。
"""
import plistlib
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "Sources" / "dok"

# 追加到 DockNotificationBadgeReader.swift 的副本里，才能访问它的 private 成员。
BADGE_CHECKS = r'''

extension DockNotificationBadgeSnapshot {
    static func runDokLogicChecks(sameA: URL, sameB: URL, other: URL) {
        // 带路径的 Dock 项只按路径记，不记名字：两个都叫「微信」也不会互相借角标。
        var snapshot = DockNotificationBadgeSnapshot()
        snapshot.insert(badge: "3", url: sameA, title: "微信")
        dokCheck(snapshot.byTitle.isEmpty, "a Dock item with a URL is never matched by title")
        dokCheck(snapshot.byPath[normalizedPath(sameA.path)] == "3", "a Dock item is matched by its path")
        dokCheck(snapshot.byPath[normalizedPath(sameB.path)] == nil, "another copy's path has no badge")
        dokCheck(snapshot.byBundleIdentifier["com.example.dok.same"] == "3", "a lone copy is matched by bundle id")

        // 第二个副本标识相同：标识不再可信，只能靠路径。
        snapshot.insert(badge: "5", url: sameB, title: "微信")
        dokCheck(snapshot.byBundleIdentifier["com.example.dok.same"] == nil, "two copies drop the shared bundle id")
        dokCheck(snapshot.byPath[normalizedPath(sameA.path)] == "3"
                 && snapshot.byPath[normalizedPath(sameB.path)] == "5", "each copy keeps its own badge")
        snapshot.insert(badge: "7", url: sameA, title: "微信")
        dokCheck(snapshot.byBundleIdentifier["com.example.dok.same"] == nil, "an ambiguous bundle id stays ambiguous")

        snapshot.insert(badge: "2", url: other, title: "Other")
        dokCheck(snapshot.byBundleIdentifier["com.example.dok.other"] == "2", "distinct apps keep bundle-id matching")

        // 没有路径的 Dock 项（少数第三方条目）才退回按名字记，名字不区分大小写。
        snapshot.insert(badge: "1", url: nil, title: "Some App.app")
        dokCheck(snapshot.byTitle[normalizedTitle("some app")] == "1", "items without a URL fall back to title")
        snapshot.insert(badge: "", url: other, title: "Other")
        dokCheck(snapshot.byBundleIdentifier["com.example.dok.other"] == "2", "an empty badge is ignored")
    }
}
'''

HARNESS = r'''
import Foundation
import AppKit

func dokCheck(_ condition: Bool, _ message: String) {
    if !condition { print("FAILED: \(message)"); exit(1) }
}

@main
enum DokLogicTests {
    static func decode(_ json: String) -> AppSettings {
        try! JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
    }

    static func main() {
        settingsDecoding()
        settingsMigration()
        slotGeometry()
        let args = CommandLine.arguments
        DockNotificationBadgeSnapshot.runDokLogicChecks(
            sameA: URL(fileURLWithPath: args[1]), sameB: URL(fileURLWithPath: args[2]),
            other: URL(fileURLWithPath: args[3]))
        print("ok")
    }

    static func settingsDecoding() {
        // 一个空文件：全部回到默认值；缺少引导标记的旧文件视为已完成引导。
        let empty = decode("{}")
        dokCheck(empty.apps.isEmpty && empty.recentApps.isEmpty, "empty settings have no items")
        dokCheck(empty.menuRadius == 110 && empty.iconSize == 48 && empty.menuOpacity == 1, "default sizes")
        dokCheck(empty.interactionMode == .click && empty.menuPosition == .followMouse, "default interaction")
        dokCheck(empty.recentAppCount == 2 && empty.showRecentApps, "recent content defaults to two, shown")
        dokCheck(empty.hotkey == HotkeyConfig(), "default hotkey is ⌘Esc")
        dokCheck(empty.pinnedMode == .off && !empty.pinnedLocked, "pinned wheel is off by default")
        dokCheck(empty.hasCompletedOnboarding, "an old file without the flag never replays the guide")
        dokCheck(!decode(#"{"hasCompletedOnboarding":false}"#).hasCompletedOnboarding, "explicit false is kept")

        // 最近内容数量：旧版用 0 表示关闭；其余夹在 1…4。
        let off = decode(#"{"recentAppCount":0}"#)
        dokCheck(!off.showRecentApps && off.recentAppCount == 2, "legacy 0 means hidden, count back to 2")
        dokCheck(decode(#"{"recentAppCount":9}"#).recentAppCount == 4, "count is capped at 4")
        dokCheck(decode(#"{"recentAppCount":-3}"#).recentAppCount == 1, "count is at least 1")
        let hidden = decode(#"{"recentAppCount":3,"showRecentApps":false}"#)
        dokCheck(!hidden.showRecentApps && hidden.recentAppCount == 3, "an explicit switch wins over the count")

        // 损坏或未知的字段：该字段回到默认，其余照常读出，整份设置不丢。
        let damaged = decode(#"{"menuRadius":"big","interactionMode":"spin","hotkey":{"keyCode":"x"},"iconSize":56}"#)
        dokCheck(damaged.menuRadius == 110, "a mistyped radius falls back to the default")
        dokCheck(damaged.interactionMode == .click, "an unknown mode falls back to click")
        dokCheck(damaged.hotkey == HotkeyConfig(), "a broken hotkey falls back to ⌘Esc")
        dokCheck(damaged.iconSize == 56, "valid fields next to broken ones survive")

        // 最近内容最多保留 10 个。
        var many = AppSettings()
        many.recentApps = (0..<15).map { AppItem(name: "App \($0)", bundleIdentifier: "com.example.\($0)", path: "/A\($0).app") }
        let trimmed = try! JSONDecoder().decode(AppSettings.self, from: try! JSONEncoder().encode(many))
        dokCheck(trimmed.recentApps.count == 10 && trimmed.recentApps.first?.name == "App 0", "recent list keeps the newest 10")

        // 写出再读回：所有改过的值都原样保留。
        var custom = AppSettings()
        custom.apps = [AppItem(name: "Finder", bundleIdentifier: "com.apple.finder", path: "/System/Library/CoreServices/Finder.app")]
        custom.menuRadius = 135; custom.iconSize = 52; custom.menuOpacity = 0.8
        custom.interactionMode = .hold; custom.menuPosition = .screenCenter; custom.appearanceMode = .dark
        custom.hapticFeedback = false; custom.soundEffects = false; custom.showMenuBarIcon = false
        custom.showNotificationBadges = false; custom.showMusicControl = false; custom.mouseTrigger = .middleButton
        custom.pinnedMode = .desktop; custom.pinnedDesktopCenter = CGPoint(x: 300, y: 200); custom.pinnedLocked = true
        custom.hotkey = HotkeyConfig(keyCode: 49, modifiers: [.control, .option])
        custom.recentAppCount = 3; custom.showRecentApps = false; custom.hasCompletedOnboarding = false
        let back = try! JSONDecoder().decode(AppSettings.self, from: try! JSONEncoder().encode(custom))
        dokCheck(back.apps == custom.apps, "slots round-trip")
        dokCheck(back.menuRadius == 135 && back.iconSize == 52 && back.menuOpacity == 0.8, "sizes round-trip")
        dokCheck(back.interactionMode == .hold && back.menuPosition == .screenCenter && back.appearanceMode == .dark,
                 "modes round-trip")
        dokCheck(!back.hapticFeedback && !back.soundEffects && !back.showMenuBarIcon
                 && !back.showNotificationBadges && !back.showMusicControl, "switches round-trip")
        dokCheck(back.mouseTrigger == .middleButton && back.pinnedMode == .desktop && back.pinnedLocked
                 && back.pinnedDesktopCenter == CGPoint(x: 300, y: 200), "triggers and pinning round-trip")
        dokCheck(back.hotkey == custom.hotkey, "hotkey round-trips")
        dokCheck(back.recentAppCount == 3 && !back.showRecentApps && !back.hasCompletedOnboarding, "flags round-trip")
    }

    static func settingsMigration() {
        for retired in [HotkeyConfig(keyCode: 49, modifiers: .option),
                        HotkeyConfig(keyCode: 2, modifiers: [.command, .shift]),
                        HotkeyConfig(keyCode: 50, modifiers: [.command])] {
            var old = AppSettings()
            old.hotkey = retired
            old.menuRadius = 140
            let migrated = old.migrated()
            dokCheck(migrated.hotkey == HotkeyConfig(), "retired hotkey \(retired.displayString) becomes ⌘Esc")
            dokCheck(migrated.menuRadius == 140, "migration leaves other settings alone")
        }
        for kept in [HotkeyConfig(keyCode: 49, modifiers: [.option, .shift]),
                     HotkeyConfig(keyCode: 2, modifiers: [.command]),
                     HotkeyConfig(keyCode: 50, modifiers: [.control])] {
            var chosen = AppSettings()
            chosen.hotkey = kept
            dokCheck(chosen.migrated().hotkey == kept, "a user's own hotkey \(kept.displayString) is kept")
        }
    }

    static func slotGeometry() {
        dokCheck(WheelSlotGeometry.slotIndex(dx: 1, dy: 0, count: 0) == nil, "an empty wheel has no slots")
        for count in 1...12 {
            let slice = 360 / Double(count)
            for index in 0..<count {
                let degrees = WheelSlotGeometry.slotDegrees(index, count: count)
                // DokWheelView 画图标的公式（SwiftUI 坐标 y 轴向下，换成屏幕坐标即 dy = +sin）。
                let viewAngle = (2 * Double.pi / Double(count)) * Double(index) - .pi / 2
                dokCheck(abs(viewAngle * 180 / .pi - degrees) < 1e-9, "icons sit where the geometry says")
                for offset in [0, slice / 2 - 0.5, -(slice / 2 - 0.5)] {
                    let radians = (degrees + offset) * .pi / 180
                    let hit = WheelSlotGeometry.slotIndex(dx: 100 * cos(radians), dy: 100 * sin(radians), count: count)
                    dokCheck(hit == index, "pointing at slot \(index) of \(count) (offset \(offset)°) hits it, got \(String(describing: hit))")
                }
                dokCheck(WheelKeyboardNavigation.slotDegrees(index, count: count) == degrees,
                         "the keyboard uses the same layout")
            }
        }
        // 第 0 个在正下方，逆时针（屏幕上向右）排开。
        dokCheck(WheelSlotGeometry.slotIndex(dx: 0, dy: -100, count: 8) == 0, "slot 0 is at 6 o'clock")
        dokCheck(WheelSlotGeometry.slotIndex(dx: 100, dy: 0, count: 8) == 2, "slot 2 of 8 is at 3 o'clock")
        dokCheck(WheelSlotGeometry.slotIndex(dx: 0, dy: 100, count: 8) == 4, "slot 4 of 8 is at 12 o'clock")
    }
}
'''


def make_bundle(directory: Path, name: str, bundle_id: str) -> Path:
    app = directory / f"{name}.app"
    (app / "Contents").mkdir(parents=True)
    with open(app / "Contents" / "Info.plist", "wb") as handle:
        plistlib.dump({"CFBundleIdentifier": bundle_id, "CFBundleName": name, "CFBundlePackageType": "APPL"}, handle)
    return app


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="logic-unit-", dir=ROOT / "work") as tmp:
        directory = Path(tmp)
        src = directory / "src"
        src.mkdir()
        for path in SOURCES.glob("*.swift"):
            text = path.read_text()
            if path.name == "DokApp.swift":
                assert text.count("\n@main\n") == 1, "the app entry point moved; update this test"
                text = text.replace("\n@main\n", "\n", 1)
            if path.name == "DockNotificationBadgeReader.swift":
                text += BADGE_CHECKS
            (src / path.name).write_text(text)
        (src / "zz_dok_logic_tests.swift").write_text(HARNESS)

        bundles = directory / "bundles"
        same_a = make_bundle(bundles / "a", "WeChat", "com.example.dok.same")
        same_b = make_bundle(bundles / "b", "WeChat2", "com.example.dok.same")
        other = make_bundle(bundles / "c", "Other", "com.example.dok.other")

        binary = directory / "logic-tests"
        build = subprocess.run(
            ["xcrun", "swiftc", "-swift-version", "5", "-parse-as-library", "-Onone",
             *map(str, sorted(src.glob("*.swift"))), "-o", str(binary)],
            capture_output=True, text=True,
        )
        assert build.returncode == 0, build.stderr[-3000:]
        result = subprocess.run([str(binary), str(same_a), str(same_b), str(other)],
                                capture_output=True, text=True, timeout=30)
        assert result.returncode == 0 and result.stdout.strip().endswith("ok"), result.stdout + result.stderr

    # 这些路径都只算一次：图标、命中、拖放、键盘不再各写一份公式。
    interaction = (SOURCES / "WheelInteraction.swift").read_text()
    window = (SOURCES / "DokWheelWindow.swift").read_text()
    assert "WheelSlotGeometry.slotIndex(dx: Double(dx), dy: Double(dy), count: appCount)" in interaction
    assert "WheelSlotGeometry.slotIndex(dx: Double(dx), dy: Double(dy), count: appCount)" in window
    assert "sliceAngle / 2, 2 * .pi)" not in window, "drag-and-drop no longer carries its own copy of the formula"
    assert "decoded.migrated()" in (SOURCES / "AppState.swift").read_text()

    print("dok logic unit tests passed.")


if __name__ == "__main__":
    main()
