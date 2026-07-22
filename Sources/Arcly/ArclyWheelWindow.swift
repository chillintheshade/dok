import SwiftUI
import AppKit
import QuartzCore
import AVFoundation

struct MusicProgressRingGeometry {
    /// 把 AppKit 的 y 轴向上坐标映射到 SwiftUI 从顶部顺时针绘制的进度比例。
    static func fraction(
        dx: CGFloat,
        dy: CGFloat,
        centerYOffset: CGFloat,
        radius: CGFloat,
        tolerance: CGFloat
    ) -> Double? {
        let relativeY = dy - centerYOffset
        let distance = hypot(dx, relativeY)
        guard abs(distance - radius) <= tolerance else { return nil }

        var angle = atan2(dx, relativeY)
        if angle < 0 { angle += 2 * .pi }
        return Double(angle / (2 * .pi))
    }
}

// MARK: - 拖放目标视图

class DropTargetHostingView<Content: View>: NSHostingView<Content> {
    weak var wheelWindow: ArclyWheelWindow?

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        wheelWindow?.handleDragUpdate(sender)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        wheelWindow?.handleDragUpdate(sender)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        wheelWindow?.appState.selectedIndex = nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        return wheelWindow?.handleDrop(sender) ?? false
    }
}

// MARK: - ArclyWheelWindow

class ArclyWheelWindow: NSWindow {
    let appState: AppState
    private var mouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var clickMonitor: Any?
    private var localClickMonitor: Any?
    private var rightClickMonitor: Any?
    private var localRightClickMonitor: Any?
    private var escMonitor: Any?
    private var revealWorkItem: DispatchWorkItem?
    private var dismissWorkItem: DispatchWorkItem?
    private var contextMenuApplication: NSRunningApplication?
    private(set) var isContextMenuOpen = false
    var onDismiss: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    private let windowSize: CGFloat = ArclyWheelView.windowSize
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

    private enum CenterClickAction {
        case openSettings
        case previousTrack
        case togglePlayPause
        case nextTrack
        case seek(to: TimeInterval)
    }

    // AVAudioPlayer 预缓冲，play() 近乎零延迟
    private static let tickPlayers: [AVAudioPlayer] = {
        let url = URL(fileURLWithPath: "/System/Library/Sounds/Tink.aiff")
        return (0..<3).compactMap { _ in
            guard let p = try? AVAudioPlayer(contentsOf: url) else { return nil }
            p.volume = 0.5
            p.prepareToPlay()  // 预填充音频缓冲区
            return p
        }
    }()
    private var tickIndex = 0

    init(appState: AppState) {
        self.appState = appState
        let size = ArclyWheelView.windowSize
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: size, height: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        // screenSaver 级别确保在全屏 app 上也能显示
        self.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = false
        self.isReleasedWhenClosed = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        self.acceptsMouseMovedEvents = true

        let menuView = ArclyWheelView(appState: appState, onAppSelected: { [weak self] app in
            self?.launchApp(app)
            self?.dismiss()
        }, onSettingsTapped: { [weak self] in
            self?.dismissForSettings()
        })
        let hosting = DropTargetHostingView(rootView: menuView)
        hosting.wheelWindow = self
        hosting.frame = NSRect(x: 0, y: 0, width: size, height: size)
        hosting.registerForDraggedTypes([.fileURL])
        self.contentView = hosting
        applyAppearance()
    }

    func showAt(point: NSPoint) {
        revealWorkItem?.cancel()
        revealWorkItem = nil
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        let wasAlreadyPresented = isVisible && appState.isMenuVisible && alphaValue > 0.99

        let anchor: NSPoint
        if appState.settings.menuPosition == .screenCenter,
           let screen = NSScreen.main {
            anchor = NSPoint(x: screen.frame.midX, y: screen.frame.midY)
        } else {
            anchor = point
        }

        var x = anchor.x - windowSize / 2
        var y = anchor.y - windowSize / 2

        // 限制在屏幕可见区域内
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(anchor) }) ?? NSScreen.main {
            let frame = screen.frame
            x = min(max(x, frame.minX), frame.maxX - windowSize)
            y = min(max(y, frame.minY), frame.maxY - windowSize)
        }

        self.setFrameOrigin(NSPoint(x: x, y: y))
        self.appState.selectedIndex = nil
        self.appState.selectedRecentAppIndex = nil

        guard !wasAlreadyPresented else {
            self.alphaValue = 1
            self.ignoresMouseEvents = false
            installEventMonitors()
            return
        }

        self.appState.snapshotRecentApps()

        self.appState.isMenuVisible = false
        self.ignoresMouseEvents = true
        // Keep the native sampler alive while hiding its cached first frame.
        // A true zero alpha can stop desktop sampling on some compositor paths.
        self.alphaValue = MenuMotion.windowWarmupAlpha
        // Do not depend on app activation. This keeps presentation working after
        // clicking the wallpaper or entering the desktop-only Space.
        self.orderFrontRegardless()

        self.contentView?.layoutSubtreeIfNeeded()
        self.displayIfNeeded()
        let reveal = DispatchWorkItem { [weak self] in
            guard let self else { return }
            withAnimation(MenuMotion.menuAnimation(isVisible: true)) {
                self.appState.isMenuVisible = true
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = MenuMotion.windowRevealDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.animator().alphaValue = 1
            }
            self.ignoresMouseEvents = false
            self.revealWorkItem = nil
        }
        revealWorkItem = reveal
        DispatchQueue.main.asyncAfter(
            deadline: .now() + MenuMotion.glassSamplerWarmupDelay,
            execute: reveal
        )

        installEventMonitors()
    }

    private func installEventMonitors() {
        removeMonitors()
        installGlobalInteractionMonitors()

        // Mouse movement - local (when mouse is over our window)
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .otherMouseDragged]) { [weak self] event in
            self?.updateSelection()
            return event
        }

        // Click - local (clicking inside window)
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            guard let self = self else { return nil }

            let mouseLocation = NSEvent.mouseLocation
            let center = NSPoint(x: self.frame.midX, y: self.frame.midY)
            let dx = mouseLocation.x - center.x
            let dy = mouseLocation.y - center.y
            let distance = sqrt(dx * dx + dy * dy)
            NSLog("🖱️ Click: mouse=(%.0f,%.0f) center=(%.0f,%.0f) dist=%.1f",
                  mouseLocation.x, mouseLocation.y, center.x, center.y, distance)

            if let action = self.centerClickAction(dx: dx, dy: dy, distance: distance) {
                let np = self.appState.nowPlaying
                switch action {
                case .openSettings:
                    self.dismissForSettings()
                case .previousTrack:
                    np.previousTrack()
                case .togglePlayPause:
                    np.togglePlayPause()
                case .nextTrack:
                    np.nextTrack()
                case .seek(let seconds):
                    np.seek(to: seconds)
                }
                return nil
            }

            if self.isInsideCenterControls(dx: dx, dy: dy, distance: distance) {
                return nil
            }

            // 点击应用图标 → 启动应用
            let appToLaunch = self.selectedAppForActivation()
            if appToLaunch != nil {
                if self.appState.settings.soundEffects {
                    NSSound(named: "Tink")?.play()
                }
            }
            self.dismiss()
            if let app = appToLaunch {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    self.launchApp(app)
                }
            }
            return nil
        }

        // 运行中的 App 槽位显示退出菜单，其余位置维持关闭轮盘。
        localRightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown]) { [weak self] event in
            self?.handleRightClick(event)
            return nil
        }

        // Escape to close
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 { // Escape
                self?.dismiss()
                return nil
            }
            return event
        }
    }

    private func installGlobalInteractionMonitors() {
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .otherMouseDragged]
        ) { [weak self] _ in
            self?.updateSelection()
        }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            self?.dismiss()
        }
        rightClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.rightMouseDown]) { [weak self] _ in
            self?.dismiss()
        }
    }

    private func suspendGlobalInteractionMonitors() {
        if let monitor = mouseMonitor { NSEvent.removeMonitor(monitor); mouseMonitor = nil }
        if let monitor = clickMonitor { NSEvent.removeMonitor(monitor); clickMonitor = nil }
        if let monitor = rightClickMonitor { NSEvent.removeMonitor(monitor); rightClickMonitor = nil }
    }

    private func handleRightClick(_ event: NSEvent) {
        let screenPoint = NSEvent.mouseLocation
        let recentIndex = satelliteIndex(at: screenPoint)
        let fixedIndex = recentIndex == nil ? slotIndex(at: screenPoint) : nil

        let app: AppItem
        if let recentIndex, recentIndex < appState.recentAppSnapshot.count {
            app = appState.recentAppSnapshot[recentIndex]
            appState.selectedRecentAppIndex = recentIndex
            appState.selectedIndex = nil
        } else if let fixedIndex, fixedIndex < appState.settings.apps.count {
            app = appState.settings.apps[fixedIndex]
            appState.selectedIndex = fixedIndex
            appState.selectedRecentAppIndex = nil
        } else {
            dismiss()
            return
        }

        guard app.itemType == .app,
              app.isRunning,
              let runningApplication = NSWorkspace.shared.runningApplications.first(where: {
                  $0.bundleIdentifier == app.bundleIdentifier && !$0.isTerminated
              }) else {
            dismiss()
            return
        }

        contextMenuApplication = runningApplication
        isContextMenuOpen = true
        suspendGlobalInteractionMonitors()

        let menu = NSMenu()
        let quitItem = NSMenuItem(
            title: Loc.string("wheel.quitRunningApp"),
            action: #selector(quitContextMenuApplication),
            keyEquivalent: ""
        )
        quitItem.target = self
        menu.addItem(quitItem)
        let menuPoint = contentView?.convert(event.locationInWindow, from: nil)
            ?? event.locationInWindow
        menu.popUp(positioning: nil, at: menuPoint, in: contentView)

        isContextMenuOpen = false
        contextMenuApplication = nil
        if isVisible && appState.isMenuVisible {
            installGlobalInteractionMonitors()
        }
    }

    @objc private func quitContextMenuApplication() {
        contextMenuApplication?.terminate()
        dismiss()
    }

    func updateSelection() {
        let mouseLocation = NSEvent.mouseLocation
        let newRecentIndex = satelliteIndex(at: mouseLocation)
        let newIndex = newRecentIndex == nil ? slotIndex(at: mouseLocation) : nil

        // 仅在值变化时更新，禁用 Core Animation 隐式动画防止闪烁
        if appState.selectedIndex != newIndex
            || appState.selectedRecentAppIndex != newRecentIndex {
            NSAnimationContext.beginGrouping()
            NSAnimationContext.current.duration = 0
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            appState.selectedIndex = newIndex
            appState.selectedRecentAppIndex = newRecentIndex
            CATransaction.commit()
            NSAnimationContext.endGrouping()

            if newIndex != nil || newRecentIndex != nil {
                // 触觉 + 音效同步触发
                if appState.settings.hapticFeedback {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                }
                if appState.settings.soundEffects && !Self.tickPlayers.isEmpty {
                    let p = Self.tickPlayers[tickIndex % Self.tickPlayers.count]
                    p.currentTime = 0
                    p.play()
                    tickIndex += 1
                }
            }
        }
    }

    private func slotIndex(at screenPoint: NSPoint) -> Int? {
        let center = NSPoint(x: frame.midX, y: frame.midY)
        let dx = screenPoint.x - center.x
        let dy = screenPoint.y - center.y
        let distance = hypot(dx, dy)
        let appCount = appState.settings.apps.count
        guard appCount > 0 else { return nil }

        let innerRadius = appState.settings.menuRadius - 50
        let outerRadius = appState.settings.menuRadius + 50
        guard seekFraction(dx: dx, dy: dy) == nil,
              !isInsideCenterControls(dx: dx, dy: dy, distance: distance),
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

    private func satelliteIndex(at screenPoint: NSPoint) -> Int? {
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
                x: frame.midX + offset.x,
                y: frame.midY - offset.y
            )
            if hypot(screenPoint.x - satelliteCenter.x, screenPoint.y - satelliteCenter.y) <= hitRadius {
                return index
            }
        }
        return nil
    }

    // MARK: - 拖放处理

    func handleDragUpdate(_ sender: NSDraggingInfo) {
        // 将拖拽位置转换为屏幕坐标，复用 selection 逻辑
        let windowPoint = sender.draggingLocation
        let screenPoint = self.convertPoint(toScreen: windowPoint)
        let center = NSPoint(x: self.frame.midX, y: self.frame.midY)

        let dx = screenPoint.x - center.x
        let dy = screenPoint.y - center.y
        let distance = sqrt(dx * dx + dy * dy)

        let appCount = appState.settings.apps.count
        guard appCount > 0 else { return }

        let innerRadius = appState.settings.menuRadius - 50
        let outerRadius = appState.settings.menuRadius + 50

        let newIndex: Int?
        if isInsideCenterControls(dx: dx, dy: dy, distance: distance)
            || distance < innerRadius || distance > outerRadius {
            newIndex = nil
        } else {
            var angle = atan2(dy, dx)
            if angle < 0 { angle += 2 * .pi }
            let sliceAngle = (2 * Double.pi) / Double(appCount)
            let adjustedAngle = fmod(angle + .pi / 2 + sliceAngle / 2, 2 * .pi)
            newIndex = Int(adjustedAngle / sliceAngle) % appCount
        }

        if appState.selectedIndex != newIndex {
            appState.selectedIndex = newIndex
            if newIndex != nil && appState.settings.hapticFeedback {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
        }
    }

    func handleDrop(_ sender: NSDraggingInfo) -> Bool {
        guard let index = appState.selectedIndex,
              index < appState.settings.apps.count else {
            dismiss()
            return false
        }

        let app = appState.settings.apps[index]

        // 读取拖入的文件 URL
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL], !urls.isEmpty else {
            dismiss()
            return false
        }

        if appState.settings.soundEffects {
            NSSound(named: "Tink")?.play()
        }

        dismiss()

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

    func applyAppearance() {
        switch appState.settings.appearanceMode {
        case .light: self.appearance = NSAppearance(named: .aqua)
        case .dark: self.appearance = NSAppearance(named: .darkAqua)
        case .system: self.appearance = nil
        }
    }

    private func isInsideCenterControls(dx: CGFloat, dy: CGFloat, distance: CGFloat) -> Bool {
        if appState.nowPlaying.hasNowPlaying && appState.settings.showMusicControl {
            let scale = centerMusicControlScale
            return distance <= centerControlHitRadius * scale
                && abs(dx) <= 90 * scale
                && dy >= -96 * scale
                && dy <= 72 * scale
        }

        return distance <= 64 * centerMusicControlScale
    }

    private func centerClickAction(dx: CGFloat, dy: CGFloat, distance: CGFloat) -> CenterClickAction? {
        if appState.nowPlaying.hasNowPlaying && appState.settings.showMusicControl {
            if let fraction = seekFraction(dx: dx, dy: dy),
               let duration = appState.nowPlaying.duration {
                return .seek(to: duration * fraction)
            }

            guard isInsideCenterControls(dx: dx, dy: dy, distance: distance) else { return nil }
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

        guard isInsideCenterControls(dx: dx, dy: dy, distance: distance) else { return nil }
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

    func activateSelected() {
        guard let app = selectedAppForActivation() else { return }
        launchApp(app)
    }

    func selectedAppForActivation() -> AppItem? {
        if let index = appState.selectedRecentAppIndex,
           index < appState.recentAppSnapshot.count {
            return appState.recentAppSnapshot[index]
        }
        if let index = appState.selectedIndex,
           index < appState.settings.apps.count {
            return appState.settings.apps[index]
        }
        return nil
    }

    func launchApp(_ app: AppItem) {
        if app.itemType == .fileOrFolder {
            NSLog("📂 Opening: %@", app.path)
            app.openFileOrFolder()
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

    func dismiss() {
        revealWorkItem?.cancel()
        revealWorkItem = nil
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        appState.selectedIndex = nil
        appState.selectedRecentAppIndex = nil
        removeMonitors()
        ignoresMouseEvents = true

        withAnimation(MenuMotion.menuAnimation(isVisible: false)) {
            appState.isMenuVisible = false
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = MenuMotion.contentDismissDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = MenuMotion.windowWarmupAlpha
        }

        let finishDismiss = DispatchWorkItem { [weak self] in
            guard let self, !self.appState.isMenuVisible else { return }
            self.orderOut(nil)
            self.alphaValue = 1
            self.onDismiss?()
            self.dismissWorkItem = nil
        }
        dismissWorkItem = finishDismiss
        DispatchQueue.main.asyncAfter(
            deadline: .now() + MenuMotion.dismissOrderOutDelay,
            execute: finishDismiss
        )
    }

    /// 立即关闭（无动画），然后打开设置 — 确保设置窗口能拿到焦点
    func dismissForSettings() {
        revealWorkItem?.cancel()
        revealWorkItem = nil
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        let openSettings = onOpenSettings // 先捕获，防止 onDismiss 释放 self 后丢失
        appState.selectedIndex = nil
        appState.selectedRecentAppIndex = nil
        appState.isMenuVisible = false
        removeMonitors()
        ignoresMouseEvents = true
        orderOut(nil)
        alphaValue = 1
        onDismiss?()
        DispatchQueue.main.async {
            openSettings?()
        }
    }

    private func removeMonitors() {
        suspendGlobalInteractionMonitors()
        if let m = localMouseMonitor { NSEvent.removeMonitor(m); localMouseMonitor = nil }
        if let m = localClickMonitor { NSEvent.removeMonitor(m); localClickMonitor = nil }
        if let m = localRightClickMonitor { NSEvent.removeMonitor(m); localRightClickMonitor = nil }
        if let m = escMonitor { NSEvent.removeMonitor(m); escMonitor = nil }
    }

    override func close() {
        dismiss()
    }

    deinit {
        removeMonitors()
    }
}
