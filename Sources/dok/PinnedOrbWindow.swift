import SwiftUI
import AppKit

/// 置顶模式平时的样子：一颗玻璃小圆点，中间是水滴，放音乐时外圈显示进度。
struct PinnedOrbView: View {
    @ObservedObject var nowPlaying: NowPlayingService
    let showsProgress: Bool

    var body: some View {
        ZStack {
            Color.clear
                .frame(width: PinnedOrbWindow.diameter, height: PinnedOrbWindow.diameter)
                .dokCapsuleGlass()
            Circle()
                .fill(RadialGradient(colors: [.white, .white.opacity(0.55)],
                                     center: UnitPoint(x: 0.35, y: 0.3),
                                     startRadius: 0,
                                     endRadius: 9))
                .frame(width: 13, height: 13)
                .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
            // 每秒更新一次就够了：这里不值得逐帧刷新。
            if showsProgress && nowPlaying.duration != nil {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    if let progress = nowPlaying.playbackProgress(at: context.date) {
                        ProgressArcBand(progress: progress, width: 2, maxWidth: 2)
                            .fill(Color.primary.opacity(0.45))
                            .frame(width: PinnedOrbWindow.diameter - 2, height: PinnedOrbWindow.diameter - 2)
                    }
                }
            }
        }
        .frame(width: PinnedOrbWindow.windowSide, height: PinnedOrbWindow.windowSide)
    }
}

final class PinnedOrbWindow: NSPanel {
    static let diameter: CGFloat = 44
    static let windowSide: CGFloat = 64
    private static let edgeMargin: CGFloat = 8

    private var tracker = PinnedDragTracker()
    private let appState: AppState

    var isDraggable: () -> Bool = { true }
    var onClick: (() -> Void)?
    var onDragBegan: (() -> Void)?
    var onDragEnded: ((NSPoint) -> Void)?
    var onRightClick: ((NSEvent) -> Void)?

    var center: NSPoint { NSPoint(x: frame.midX, y: frame.midY) }

    init(appState: AppState) {
        self.appState = appState
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.windowSide, height: Self.windowSide),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        contentView = NSHostingView(rootView: PinnedOrbView(nowPlaying: appState.nowPlaying,
                                                            showsProgress: appState.settings.showMusicControl))
        applyAppearance()
    }

    func applyAppearance() {
        switch appState.settings.appearanceMode {
        case .light: appearance = NSAppearance(named: .aqua)
        case .dark: appearance = NSAppearance(named: .darkAqua)
        case .system: appearance = nil
        }
    }

    func moveCenter(to center: NSPoint) {
        setFrameOrigin(NSPoint(x: center.x - frame.width / 2, y: center.y - frame.height / 2))
    }

    /// 吸附到最近的屏幕边缘。
    static func snappedToEdge(_ center: NSPoint, screens: [NSRect]) -> NSPoint {
        let radius = diameter / 2 + edgeMargin
        let clamped = PinnedDragTracker.clampedCenter(center, radius: radius, screens: screens)
        guard let screen = screens.first(where: { $0.insetBy(dx: -1, dy: -1).contains(clamped) }) else { return clamped }
        let gaps: [(CGFloat, NSPoint)] = [
            (clamped.x - screen.minX, NSPoint(x: screen.minX + radius, y: clamped.y)),
            (screen.maxX - clamped.x, NSPoint(x: screen.maxX - radius, y: clamped.y)),
            (clamped.y - screen.minY, NSPoint(x: clamped.x, y: screen.minY + radius)),
            (screen.maxY - clamped.y, NSPoint(x: clamped.x, y: screen.maxY - radius)),
        ]
        return gaps.min(by: { $0.0 < $1.0 })?.1 ?? clamped
    }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            tracker.press(at: NSEvent.mouseLocation)
        case .leftMouseDragged:
            let event = tracker.move(to: NSEvent.mouseLocation)
            guard isDraggable() else { return }
            switch event {
            case .began:
                onDragBegan?()
                if appState.settings.hapticFeedback {
                    NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
                }
            case .moved(let dx, let dy):
                setFrameOrigin(NSPoint(x: frame.origin.x + dx, y: frame.origin.y + dy))
            case nil:
                break
            }
        case .leftMouseUp:
            switch tracker.release() {
            case .click:
                onClick?()
            case .dragged:
                guard isDraggable() else { return }
                if appState.settings.hapticFeedback {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                }
                onDragEnded?(center)
            }
        case .rightMouseDown:
            onRightClick?(event)
        default:
            super.sendEvent(event)
        }
    }
}
