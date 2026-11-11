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

/// 轮盘显示时可用的按键。
enum WheelKey: Equatable {
    /// 数字键：1–9 是按钟表顺序数的前九个槽位，0 是第十个。
    case digit(Int)
    case arrow(WheelArrow)
    case confirm
}

enum WheelArrow: Equatable {
    case up, down, left, right

    /// 方向对应的角度（数学坐标：0° 朝右，逆时针为正，y 轴向上）。
    var degrees: Double {
        switch self {
        case .right: return 0
        case .up: return 90
        case .left: return 180
        case .down: return 270
        }
    }
}

/// 槽位摆法的唯一定义：第 0 个在正下方，按屏幕上的逆时针方向依次排开，一圈平分。
/// 图标位置（`DokWheelView.iconsLayer`）、鼠标命中、拖放和键盘选择都以它为准。
enum WheelSlotGeometry {
    /// 第 index 个槽位中心的角度（数学坐标：0° 朝右，逆时针为正，y 轴向上），单位度。
    static func slotDegrees(_ index: Int, count: Int) -> Double {
        -90 + 360 / Double(count) * Double(index)
    }

    /// 屏幕坐标（y 轴向上）下相对圆心的偏移落在哪个槽位的扇区里。只看角度，不看距离。
    static func slotIndex(dx: Double, dy: Double, count: Int) -> Int? {
        guard count > 0 else { return nil }
        var angle = atan2(dy, dx)
        if angle < 0 { angle += 2 * .pi }
        let sliceAngle = (2 * Double.pi) / Double(count)
        let adjustedAngle = fmod(angle + .pi / 2 + sliceAngle / 2, 2 * .pi)
        return Int(adjustedAngle / sliceAngle) % count
    }
}

/// 键盘选择的纯计算：不碰窗口和状态，只回答「按这个键该选哪个槽位」。
///
/// 槽位的摆法见 `WheelSlotGeometry`。
enum WheelKeyboardNavigation {
    private static let epsilon = 1e-6

    static func slotDegrees(_ index: Int, count: Int) -> Double {
        WheelSlotGeometry.slotDegrees(index, count: count)
    }

    /// 从 12 点方向顺时针转到该槽位的角度，范围 [0, 360)。
    static func clockDegrees(_ index: Int, count: Int) -> Double {
        var clock = (90 - slotDegrees(index, count: count)).truncatingRemainder(dividingBy: 360)
        if clock < 0 { clock += 360 }
        return clock > 360 - epsilon ? 0 : clock
    }

    /// 像看钟表一样数：从 12 点开始顺时针，依次碰到的槽位。
    /// 正上方有槽位时它排第一；正上方是空的（槽位数为单数）时，右边紧挨着的那个排第一。
    static func clockOrder(count: Int) -> [Int] {
        guard count > 0 else { return [] }
        return (0..<count).sorted { clockDegrees($0, count: count) < clockDegrees($1, count: count) }
    }

    static func slot(forDigit digit: Int, count: Int) -> Int? {
        let position = digit == 0 ? 10 : digit
        let order = clockOrder(count: count)
        guard position >= 1, position <= order.count else { return nil }
        return order[position - 1]
    }

    /// 离某个方向最近的槽位。两个一样近时取顺时针一侧的，与数字键的数法一致。
    static func nearestSlot(toward arrow: WheelArrow, count: Int) -> Int? {
        guard count > 0 else { return nil }
        var best: (index: Int, distance: Double, signed: Double)?
        for index in 0..<count {
            let signed = signedDelta(from: arrow.degrees, to: slotDegrees(index, count: count))
            let distance = abs(signed)
            guard let current = best else {
                best = (index, distance, signed)
                continue
            }
            if distance < current.distance - epsilon
                || (abs(distance - current.distance) <= epsilon && signed < current.signed) {
                best = (index, distance, signed)
            }
        }
        return best?.index
    }

    /// 已有选中项时再按方向键：挪到相邻两个里更靠那个方向的一个。
    /// 两个相邻项一样（比如在正上方按下）就直接跳到那个方向最近的槽位；都不在那个方向就不动。
    static func step(from current: Int, arrow: WheelArrow, count: Int) -> Int {
        guard count > 1, current >= 0, current < count else { return current }
        let counterclockwise = (current + 1) % count
        let clockwise = (current - 1 + count) % count
        let gainCCW = gain(from: current, to: counterclockwise, arrow: arrow, count: count)
        let gainCW = gain(from: current, to: clockwise, arrow: arrow, count: count)

        if abs(gainCCW - gainCW) <= epsilon {
            return nearestSlot(toward: arrow, count: count) ?? current
        }
        let (target, best) = gainCW > gainCCW ? (clockwise, gainCW) : (counterclockwise, gainCCW)
        return best > epsilon ? target : current
    }

    /// 从 current 挪到 target，沿箭头方向前进了多少（单位圆上）。
    private static func gain(from current: Int, to target: Int, arrow: WheelArrow, count: Int) -> Double {
        let from = slotDegrees(current, count: count) * .pi / 180
        let to = slotDegrees(target, count: count) * .pi / 180
        let direction = arrow.degrees * .pi / 180
        return (cos(to) - cos(from)) * cos(direction) + (sin(to) - sin(from)) * sin(direction)
    }

    /// 从 a 到 b 的最短有符号夹角，范围 (-180, 180]；负值表示 b 在 a 的顺时针一侧。
    private static func signedDelta(from a: Double, to b: Double) -> Double {
        var delta = (b - a).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta <= -180 { delta += 360 }
        return delta
    }
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

        return WheelSlotGeometry.slotIndex(dx: Double(dx), dy: Double(dy), count: appCount)
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
