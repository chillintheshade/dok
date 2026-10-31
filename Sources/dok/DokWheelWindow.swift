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

protocol WheelDropTarget: AnyObject {
    func handleDragUpdate(_ sender: NSDraggingInfo)
    func handleDragExit()
    func handleDrop(_ sender: NSDraggingInfo) -> Bool
}

class DropTargetHostingView<Content: View>: NSHostingView<Content> {
    weak var dropTarget: WheelDropTarget?

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        dropTarget?.handleDragUpdate(sender)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        dropTarget?.handleDragUpdate(sender)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        dropTarget?.handleDragExit()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        return dropTarget?.handleDrop(sender) ?? false
    }
}

// MARK: - DokWheelWindow

class DokWheelWindow: NSWindow, WheelDropTarget {
    /// The only source of truth for wheel visibility. Every show and close path
    /// changes it through `setPresentation(_:)`.
    enum Presentation: String {
        case hidden, revealing, shown, dismissing
    }

    let appState: AppState
    let interaction = WheelInteractionState()
    private var hitTester: WheelHitTester { WheelHitTester(appState: appState) }
    private var wheelCenter: NSPoint { NSPoint(x: frame.midX, y: frame.midY) }
    private(set) var presentation: Presentation = .hidden
    /// True from summon until dismissal begins; used by triggers to toggle and hold.
    var isPresented: Bool { presentation == .revealing || presentation == .shown }
    private var visibilityGuardTimer: Timer?
    private var contentHiddenSince: Date?
    /// Window on screen with invisible content for longer than this is ordered out.
    private static let hiddenContentTolerance: TimeInterval = 0.2
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
    var onOpenSettings: (() -> Void)?
    var onDidHide: (() -> Void)?

    private let windowSize: CGFloat = DokWheelView.windowSize

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
        let size = DokWheelView.windowSize
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: size, height: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        // popUpMenu 级别配合 .fullScreenAuxiliary 即可显示在全屏 app 上，
        // 同时让系统截图等覆盖层保持在轮盘之上。
        self.level = .popUpMenu
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = false
        self.isReleasedWhenClosed = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        self.acceptsMouseMovedEvents = true

        let menuView = DokWheelView(appState: appState, interaction: interaction, onAppSelected: { [weak self] app in
            self?.launchApp(app)
            self?.dismiss()
        }, onSettingsTapped: { [weak self] in
            self?.dismissForSettings()
        })
        let hosting = DropTargetHostingView(rootView: menuView)
        hosting.dropTarget = self
        hosting.frame = NSRect(x: 0, y: 0, width: size, height: size)
        hosting.registerForDraggedTypes([.fileURL])
        self.contentView = hosting
        applyAppearance()
    }

    func showAt(point: NSPoint) {
        interaction.centerControlHover = nil
        revealWorkItem?.cancel()
        revealWorkItem = nil
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        let wasAlreadyPresented = presentation == .shown && isVisible

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
        self.interaction.selectedIndex = nil
        self.interaction.selectedRecentAppIndex = nil

        guard !wasAlreadyPresented else {
            self.alphaValue = 1
            self.ignoresMouseEvents = false
            installEventMonitors()
            return
        }

        self.appState.snapshotRecentApps()
        self.appState.snapshotNotificationBadges()

        setPresentation(.revealing)
        self.interaction.isMenuVisible = false
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
            guard let self, self.presentation == .revealing else { return }
            self.setPresentation(.shown)
            // DokWheelView owns the content transition. Setting the state inside a
            // second explicit animation transaction can make the same content
            // transition resolve twice while the native window is fading in.
            self.interaction.isMenuVisible = true
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

            if let action = self.hitTester.centerAction(dx: dx, dy: dy) {
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

            if self.hitTester.isInsideCenterControls(dx: dx, dy: dy) {
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
                DispatchQueue.main.asyncAfter(deadline: .now() + (app.itemType == .keyAction ? 0 : 0.15)) {
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
        let recentIndex = hitTester.satelliteIndex(at: screenPoint, center: wheelCenter)
        let fixedIndex = recentIndex == nil ? hitTester.slotIndex(at: screenPoint, center: wheelCenter) : nil

        let app: AppItem
        if let recentIndex, recentIndex < appState.recentAppSnapshot.count {
            app = appState.recentAppSnapshot[recentIndex]
            interaction.selectedRecentAppIndex = recentIndex
            interaction.selectedIndex = nil
        } else if let fixedIndex, fixedIndex < appState.settings.apps.count {
            app = appState.settings.apps[fixedIndex]
            interaction.selectedIndex = fixedIndex
            interaction.selectedRecentAppIndex = nil
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
        if isVisible && interaction.isMenuVisible {
            installGlobalInteractionMonitors()
        }
    }

    @objc private func quitContextMenuApplication() {
        contextMenuApplication?.terminate()
        dismiss()
    }

    func updateSelection() {
        let mouseLocation = NSEvent.mouseLocation
        let newRecentIndex = hitTester.satelliteIndex(at: mouseLocation, center: wheelCenter)
        let newIndex = newRecentIndex == nil ? hitTester.slotIndex(at: mouseLocation, center: wheelCenter) : nil
        let dx = mouseLocation.x - frame.midX
        let dy = mouseLocation.y - frame.midY
        let hoveredControl: AppState.CenterControlHover?
        switch hitTester.centerAction(dx: dx, dy: dy) {
        case .openSettings: hoveredControl = .settings
        case .previousTrack: hoveredControl = .previous
        case .togglePlayPause: hoveredControl = .playback
        case .nextTrack: hoveredControl = .next
        case .seek: hoveredControl = .progress
        case nil: hoveredControl = nil
        }
        if interaction.centerControlHover != hoveredControl {
            interaction.centerControlHover = hoveredControl
        }

        // 仅在值变化时更新，禁用 Core Animation 隐式动画防止闪烁
        if interaction.selectedIndex != newIndex
            || interaction.selectedRecentAppIndex != newRecentIndex {
            NSAnimationContext.beginGrouping()
            NSAnimationContext.current.duration = 0
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            interaction.selectedIndex = newIndex
            interaction.selectedRecentAppIndex = newRecentIndex
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
        if hitTester.isInsideCenterControls(dx: dx, dy: dy)
            || distance < innerRadius || distance > outerRadius {
            newIndex = nil
        } else {
            var angle = atan2(dy, dx)
            if angle < 0 { angle += 2 * .pi }
            let sliceAngle = (2 * Double.pi) / Double(appCount)
            let adjustedAngle = fmod(angle + .pi / 2 + sliceAngle / 2, 2 * .pi)
            newIndex = Int(adjustedAngle / sliceAngle) % appCount
        }

        if interaction.selectedIndex != newIndex {
            interaction.selectedIndex = newIndex
            if newIndex != nil && appState.settings.hapticFeedback {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
        }
    }

    func handleDragExit() {
        interaction.selectedIndex = nil
    }

    func handleDrop(_ sender: NSDraggingInfo) -> Bool {
        guard let index = interaction.selectedIndex,
              index < appState.settings.apps.count else {
            dismiss()
            return false
        }

        let opened = appState.openDroppedFiles(from: sender, with: appState.settings.apps[index])
        dismiss()
        return opened
    }

    func applyAppearance() {
        switch appState.settings.appearanceMode {
        case .light: self.appearance = NSAppearance(named: .aqua)
        case .dark: self.appearance = NSAppearance(named: .darkAqua)
        case .system: self.appearance = nil
        }
    }

    func activateSelected() {
        guard let app = selectedAppForActivation() else { return }
        launchApp(app)
    }

    func selectedAppForActivation() -> AppItem? {
        if let index = interaction.selectedRecentAppIndex,
           index < appState.recentAppSnapshot.count {
            return appState.recentAppSnapshot[index]
        }
        if let index = interaction.selectedIndex,
           index < appState.settings.apps.count {
            return appState.settings.apps[index]
        }
        return nil
    }

    func launchApp(_ app: AppItem) {
        if app.itemType == .keyAction {
            guard app.keyCombination != appState.settings.hotkey else {
                dismiss()
                KeyActionService.showError("keyAction.conflict")
                return
            }
            if interaction.isMenuVisible { dismiss() }
            app.runKeyAction(ready: { [weak self] in
                self?.isVisible != true
            })
            return
        }
        appState.openItem(app)
    }

    func dismiss() {
        interaction.centerControlHover = nil
        revealWorkItem?.cancel()
        revealWorkItem = nil
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        interaction.selectedIndex = nil
        interaction.selectedRecentAppIndex = nil
        removeMonitors()
        ignoresMouseEvents = true

        setPresentation(.dismissing)
        interaction.isMenuVisible = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = MenuMotion.contentDismissDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = MenuMotion.windowWarmupAlpha
        }

        let finishDismiss = DispatchWorkItem { [weak self] in
            guard let self, self.presentation == .dismissing else { return }
            self.dismissWorkItem = nil
            self.finishHiding()
        }
        dismissWorkItem = finishDismiss
        DispatchQueue.main.asyncAfter(
            deadline: .now() + MenuMotion.dismissOrderOutDelay,
            execute: finishDismiss
        )
    }

    /// 立即关闭（无动画），然后打开设置 — 确保设置窗口能拿到焦点
    func dismissForSettings() {
        interaction.centerControlHover = nil
        revealWorkItem?.cancel()
        revealWorkItem = nil
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        let openSettings = onOpenSettings
        interaction.selectedIndex = nil
        interaction.selectedRecentAppIndex = nil
        removeMonitors()
        ignoresMouseEvents = true
        finishHiding()
        DispatchQueue.main.async {
            openSettings?()
        }
    }

    // MARK: - 可见性状态机

    private func setPresentation(_ next: Presentation) {
        guard presentation != next else { return }
        NSLog("dok.wheel: %@ -> %@", presentation.rawValue, next.rawValue)
        presentation = next
        if next == .hidden {
            stopVisibilityGuard()
        } else {
            startVisibilityGuard()
        }
    }

    /// Hidden is ordered out *and* transparent: the native glass sampler does not
    /// follow the SwiftUI content opacity, so a hidden window at full alpha would
    /// appear as an empty glass disc if anything ordered it back in.
    private func finishHiding() {
        revealWorkItem?.cancel()
        revealWorkItem = nil
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        removeMonitors()
        interaction.isMenuVisible = false
        interaction.centerControlHover = nil
        ignoresMouseEvents = true
        setPresentation(.hidden)
        orderOut(nil)
        alphaValue = MenuMotion.windowWarmupAlpha
        appState.nowPlaying.menuDidDismiss()
        onDidHide?()
    }

    override func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
        super.order(place, relativeTo: otherWin)
        // Only showAt may bring the wheel on screen.
        if place != .out, presentation == .hidden {
            NSLog("dok.wheel: unexpected order-in while hidden; ordering out")
            super.order(.out, relativeTo: 0)
        }
    }

    private func startVisibilityGuard() {
        guard visibilityGuardTimer == nil else { return }
        contentHiddenSince = nil
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.checkVisibilityInvariant()
        }
        RunLoop.main.add(timer, forMode: .common)
        visibilityGuardTimer = timer
    }

    private func stopVisibilityGuard() {
        visibilityGuardTimer?.invalidate()
        visibilityGuardTimer = nil
        contentHiddenSince = nil
    }

    /// Invariant: the window is never on screen with invisible content for
    /// longer than `hiddenContentTolerance`, whatever path led there.
    private func checkVisibilityInvariant() {
        guard isVisible, !interaction.isMenuVisible else {
            contentHiddenSince = nil
            return
        }
        let since = contentHiddenSince ?? Date()
        contentHiddenSince = since
        guard Date().timeIntervalSince(since) > Self.hiddenContentTolerance else { return }
        NSLog("dok.wheel: content hidden for >%.1fs in state %@; forcing order-out",
              Self.hiddenContentTolerance, presentation.rawValue)
        finishHiding()
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
        visibilityGuardTimer?.invalidate()
    }
}
