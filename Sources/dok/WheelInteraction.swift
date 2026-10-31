import SwiftUI
import AppKit

/// 一扇轮盘窗口自己的交互状态。唤出轮盘和常驻轮盘可能同时存在，各用一份，互不串状态。
final class WheelInteractionState: ObservableObject {
    @Published var centerControlHover: AppState.CenterControlHover?
    @Published var selectedIndex: Int? = nil
    @Published var selectedRecentAppIndex: Int? = nil
    @Published var isMenuVisible: Bool = false
    /// 常驻轮盘正被拖动：内容轻微放大，不显示悬停高亮。
    @Published var isDragging: Bool = false
    /// 常驻轮盘被完全盖住：暂停逐帧的进度动画。
    @Published var isOccluded: Bool = false
}

enum WheelCenterAction {
    case openSettings
    case previousTrack
    case togglePlayPause
    case nextTrack
    case seek(to: TimeInterval)
}

/// 把鼠标位置换算成轮盘上的命中目标。坐标都是屏幕坐标（AppKit，y 轴向上）。
struct WheelHitTester {
    let appState: AppState

    private let centerControlHitRadius: CGFloat = 96
    private var centerLensRadius: CGFloat {
        let innerRadius = appState.settings.menuRadius - 50
        let maxRadiusBeforeIcons = appState.settings.menuRadius - appState.settings.iconSize / 2 - 10
        return min(max(innerRadius, 66), maxRadiusBeforeIcons)
    }
    private var centerMusicControlScale: CGFloat {
        let radiusScale = min(max(appState.settings.menuRadius / 130, 0.88), 1.42)
        let availableScale = (centerLensRadius * 2 - 18) / 142
        return min(radiusScale, max(0.68, availableScale))
    }
    private var musicProgressRingHitTolerance: CGFloat { 6 * centerMusicControlScale }

    func slotIndex(at point: NSPoint, center: NSPoint) -> Int? {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let distance = hypot(dx, dy)
        let appCount = appState.settings.apps.count
        guard appCount > 0 else { return nil }

        let innerRadius = appState.settings.menuRadius - 50
        let outerRadius = appState.settings.menuRadius + 50
        guard seekFraction(dx: dx, dy: dy) == nil,
              !isInsideCenterControls(dx: dx, dy: dy),
              distance >= innerRadius,
              distance <= outerRadius else {
            return nil
        }

        var angle = atan2(dy, dx)
        if angle < 0 { angle += 2 * .pi }
        let sliceAngle = (2 * Double.pi) / Double(appCount)
        let adjustedAngle = fmod(angle + .pi / 2 + sliceAngle / 2, 2 * .pi)
        return Int(adjustedAngle / sliceAngle) % appCount
    }

    func satelliteIndex(at point: NSPoint, center: NSPoint) -> Int? {
        let satellites = appState.recentAppSnapshot
        guard !satellites.isEmpty else { return nil }

        let outerRadius = appState.settings.menuRadius + 50
        let baseDiameter = RecentAppSatelliteGeometry.baseDiameter(
            for: appState.settings.iconSize
        )
        let offsets = RecentAppSatelliteGeometry.offsets(
            count: satellites.count,
            outerRadius: outerRadius,
            mainIconSize: appState.settings.iconSize
        )
        let hitRadius = baseDiameter / 2 + 4

        for (index, offset) in offsets.enumerated() {
            let satelliteCenter = NSPoint(
                x: center.x + offset.x,
                y: center.y - offset.y
            )
            if hypot(point.x - satelliteCenter.x, point.y - satelliteCenter.y) <= hitRadius {
                return index
            }
        }
        return nil
    }

    /// 圆盘或任一卫星之内。常驻窗口靠它决定点击是否穿透。
    func isInsideWheel(at point: NSPoint, center: NSPoint) -> Bool {
        if hypot(point.x - center.x, point.y - center.y) <= appState.settings.menuRadius + 50 {
            return true
        }
        return satelliteIndex(at: point, center: center) != nil
    }

    func isInsideCenterControls(dx: CGFloat, dy: CGFloat) -> Bool {
        let distance = hypot(dx, dy)
        if appState.nowPlaying.hasNowPlaying && appState.settings.showMusicControl {
            let scale = centerMusicControlScale
            return distance <= centerControlHitRadius * scale
                && abs(dx) <= 90 * scale
                && dy >= -96 * scale
                && dy <= 72 * scale
        }

        return distance <= 64 * centerMusicControlScale
    }

    func centerAction(dx: CGFloat, dy: CGFloat) -> WheelCenterAction? {
        if appState.nowPlaying.hasNowPlaying && appState.settings.showMusicControl {
            if let fraction = seekFraction(dx: dx, dy: dy),
               let duration = appState.nowPlaying.duration {
                return .seek(to: duration * fraction)
            }

            guard isInsideCenterControls(dx: dx, dy: dy) else { return nil }
            let scale = centerMusicControlScale
            if abs(dx) <= 34 * scale && dy >= -96 * scale && dy <= -50 * scale {
                return .openSettings
            }

            if dy >= -58 * scale && dy <= -16 * scale {
                if dx < -24 * scale { return .previousTrack }
                if dx > 24 * scale { return .nextTrack }
                return .togglePlayPause
            }

            return nil
        }

        guard isInsideCenterControls(dx: dx, dy: dy) else { return nil }
        return .openSettings
    }

    private func seekFraction(dx: CGFloat, dy: CGFloat) -> Double? {
        let nowPlaying = appState.nowPlaying
        guard nowPlaying.hasNowPlaying,
              appState.settings.showMusicControl,
              nowPlaying.canSeek,
              nowPlaying.duration != nil else { return nil }

        return MusicProgressRingGeometry.fraction(
            dx: dx,
            dy: dy,
            centerYOffset: 0,
            radius: centerLensRadius,
            tolerance: musicProgressRingHitTolerance
        )
    }
}

extension AppState {
    /// 把拖到轮盘上的文件交给目标项目打开。按键动作不接收文件。
    func openDroppedFiles(from sender: NSDraggingInfo, with app: AppItem) -> Bool {
        guard app.itemType != .keyAction,
              let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [
                  .urlReadingFileURLsOnly: true
              ]) as? [URL], !urls.isEmpty else {
            return false
        }

        if settings.soundEffects {
            NSSound(named: "Tink")?.play()
        }

        // 用目标 app 打开文件
        if app.itemType == .app,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleIdentifier) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: config) { _, error in
                if let error = error {
                    NSLog("❌ 拖放打开失败: %@", error.localizedDescription)
                } else {
                    NSLog("✅ 已用 %@ 打开 %d 个文件", app.name, urls.count)
                }
            }
        } else {
            // 文件夹类型：直接打开文件
            for url in urls {
                NSWorkspace.shared.open(url)
            }
        }
        return true
    }

    /// 打开轮盘上的文件、网址或应用。按键动作依赖窗口是否已收起，由窗口自己处理。
    func openItem(_ app: AppItem) {
        if app.itemType == .fileOrFolder {
            NSLog("📂 Opening: %@", app.path)
            recordOpenedFolder(app)
            app.openFileOrFolder()
            return
        }

        if app.itemType == .webLink {
            NSLog("🔗 Opening: %@", app.path)
            app.openWebLink()
            return
        }

        NSLog("🚀 Launching: %@ (%@)", app.name, app.bundleIdentifier)
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleIdentifier) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
                if let error = error {
                    NSLog("  ❌ 启动失败: %@", error.localizedDescription)
                } else {
                    NSLog("  ✅ 已切换到: %@", app.name)
                }
            }
        } else {
            NSLog("  ❌ 找不到应用: %@", app.bundleIdentifier)
        }
    }
}
