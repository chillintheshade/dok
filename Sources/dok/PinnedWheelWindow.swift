import SwiftUI
import AppKit
import Combine

/// 常驻轮盘。和唤出轮盘是两扇窗口：有自己的交互状态，点外面不收起，透明处让点击穿透。
final class PinnedWheelWindow: NSPanel, WheelDropTarget {
    /// 桌面图标之上、所有普通窗口之下。
    static let desktopLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)

    private let appState: AppState
    let interaction = WheelInteractionState()
    /// 桌面模式会被窗口盖住，只在看得见时刷新；置顶模式展开时总是看得见。
    private let tracksOcclusion: Bool
    private var hitTester: WheelHitTester { WheelHitTester(appState: appState) }
    private var tracker = PinnedDragTracker()
    private var dragStartCenter: NSPoint = .zero
    private var isConsuming = false
    private var lastRefresh = Date.distantPast
    private var wasInside = false
    private var observers: [NSObjectProtocol] = []
    private var settingsObserver: AnyCancellable?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var contextMenuApplication: NSRunningApplication?

    var isDraggable = true
    var onActivate: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onDragEnded: ((NSPoint) -> Void)?
    var onToggleLock: (() -> Void)?
    var isLocked: () -> Bool = { false }

    var wheelCenter: NSPoint { NSPoint(x: frame.midX, y: frame.midY) }

    init(appState: AppState, level: NSWindow.Level, collectionBehavior: NSWindow.CollectionBehavior, tracksOcclusion: Bool) {
        self.appState = appState
        self.tracksOcclusion = tracksOcclusion
        let size = DokWheelView.windowSize
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: size, height: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.level = level
        self.collectionBehavior = collectionBehavior
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        acceptsMouseMovedEvents = true

        let hosting = DropTargetHostingView(rootView: DokWheelView(appState: appState, interaction: interaction))
        hosting.dropTarget = self
        hosting.frame = NSRect(x: 0, y: 0, width: size, height: size)
        hosting.registerForDraggedTypes([.fileURL])
        contentView = hosting
        applyAppearance()
    }

    func applyAppearance() {
        switch appState.settings.appearanceMode {
        case .light: appearance = NSAppearance(named: .aqua)
        case .dark: appearance = NSAppearance(named: .darkAqua)
        case .system: appearance = nil
        }
    }

    // MARK: - 显示

    func moveCenter(to center: NSPoint) {
        setFrameOrigin(NSPoint(x: center.x - frame.width / 2, y: center.y - frame.height / 2))
    }

    func present() {
        guard !interaction.isMenuVisible else { return }
        // 和唤出轮盘一样先让玻璃采样预热，避免第一帧是空盘。
        alphaValue = MenuMotion.windowWarmupAlpha
        orderFrontRegardless()
        contentView?.layoutSubtreeIfNeeded()
        displayIfNeeded()
        startObserving()
        refreshContent()
        updateConsumption()
        DispatchQueue.main.asyncAfter(deadline: .now() + MenuMotion.glassSamplerWarmupDelay) { [weak self] in
            guard let self, self.isVisible else { return }
            self.interaction.isMenuVisible = true
            NSAnimationContext.runAnimationGroup { context in
                context.duration = MenuMotion.windowRevealDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.animator().alphaValue = 1
            }
            self.updateHover()
        }
    }

    func hide(completion: (() -> Void)? = nil) {
        stopObserving()
        tracker.cancel()
        interaction.isDragging = false
        interaction.selectedIndex = nil
        interaction.selectedRecentAppIndex = nil
        interaction.centerControlHover = nil
        interaction.isMenuVisible = false
        ignoresMouseEvents = true
        wasInside = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = MenuMotion.contentDismissDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = MenuMotion.windowWarmupAlpha
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + MenuMotion.dismissOrderOutDelay) { [weak self] in
            guard let self, !self.interaction.isMenuVisible else { return }
            self.orderOut(nil)
            completion?()
        }
    }

    private func refreshContent() {
        lastRefresh = Date()
        appState.snapshotRecentApps()
        appState.snapshotNotificationBadges()
    }

    /// 被完全盖住时不读音乐数据，也不跑进度动画。
    private func updateConsumption() {
        let visible = isVisible && (!tracksOcclusion || occlusionState.contains(.visible))
        interaction.isOccluded = !visible
        guard visible != isConsuming else { return }
        isConsuming = visible
        if visible {
            appState.nowPlaying.beginConsuming(.pinnedWheel)
        } else {
            appState.nowPlaying.endConsuming(.pinnedWheel)
        }
    }

    private func startObserving() {
        guard globalMonitor == nil else { return }
        let kinds: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: kinds) { [weak self] _ in
            self?.updateHover()
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: kinds) { [weak self] event in
            self?.updateHover()
            return event
        }
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: self, queue: .main) { [weak self] _ in
                guard let self else { return }
                let wasVisible = self.isConsuming
                self.updateConsumption()
                if !wasVisible && self.isConsuming { self.refreshContent() }
            },
            NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.reappear()
            },
            NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.reappear()
            },
        ]
        // 改半径、图标、增删应用后，命中范围和穿透区域立刻跟上。
        settingsObserver = appState.$settings
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateHover() }
    }

    private func stopObserving() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        observers.forEach {
            NotificationCenter.default.removeObserver($0)
            NSWorkspace.shared.notificationCenter.removeObserver($0)
        }
        observers = []
        settingsObserver = nil
        if isConsuming {
            isConsuming = false
            appState.nowPlaying.endConsuming(.pinnedWheel)
        }
    }

    private func reappear() {
        orderFrontRegardless()
        updateConsumption()
        refreshContent()
    }

    // MARK: - 悬停和穿透

    private func updateHover() {
        guard interaction.isMenuVisible else { return }
        // 系统手势或锁屏可能吞掉松手事件，不能让拖动状态卡住。
        if tracker.isPressed, NSEvent.pressedMouseButtons == 0 {
            tracker.cancel()
            interaction.isDragging = false
        }
        let point = NSEvent.mouseLocation
        let inside = tracker.isDragging || hitTester.isInsideWheel(at: point, center: wheelCenter)
        if inside == ignoresMouseEvents { ignoresMouseEvents = !inside }

        // 鼠标进入时刷新最近内容和角标；进出频繁时限流。
        if inside && !wasInside && Date().timeIntervalSince(lastRefresh) > 5 {
            refreshContent()
        }
        wasInside = inside

        guard !tracker.isDragging else { return }
        let recent = inside ? hitTester.satelliteIndex(at: point, center: wheelCenter) : nil
        let slot = inside && recent == nil ? hitTester.slotIndex(at: point, center: wheelCenter) : nil
        if interaction.selectedRecentAppIndex != recent { interaction.selectedRecentAppIndex = recent }
        if interaction.selectedIndex != slot { interaction.selectedIndex = slot }

        let hover: AppState.CenterControlHover?
        switch inside ? hitTester.centerAction(dx: point.x - wheelCenter.x, dy: point.y - wheelCenter.y) : nil {
        case .openSettings: hover = .settings
        case .previousTrack: hover = .previous
        case .togglePlayPause: hover = .playback
        case .nextTrack: hover = .next
        case .seek: hover = .progress
        case nil: hover = nil
        }
        if interaction.centerControlHover != hover { interaction.centerControlHover = hover }
    }

    // MARK: - 点击和拖动

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            tracker.press(at: NSEvent.mouseLocation)
            dragStartCenter = wheelCenter
        case .leftMouseDragged:
            handleDrag()
        case .leftMouseUp:
            handleRelease()
        case .rightMouseDown:
            showContextMenu(for: event)
        default:
            super.sendEvent(event)
        }
    }

    private func handleDrag() {
        let canMove = isDraggable && !isLocked()
        if canMove, tracker.isDragging, CGEventSource.keyState(.combinedSessionState, key: 53) {
            tracker.cancel()
            moveCenter(to: dragStartCenter)
            setDragging(false)
            return
        }
        // 不能移动时也要跟踪：按住挪开后松手不算点击。
        let event = tracker.move(to: NSEvent.mouseLocation)
        guard canMove else { return }
        switch event {
        case .began:
            interaction.selectedIndex = nil
            interaction.selectedRecentAppIndex = nil
            interaction.centerControlHover = nil
            setDragging(true)
            playHaptic(.levelChange)
        case .moved(let dx, let dy):
            setFrameOrigin(NSPoint(x: frame.origin.x + dx, y: frame.origin.y + dy))
        case nil:
            break
        }
    }

    private func handleRelease() {
        guard tracker.isPressed else { return }  // 拖动中按 Esc 已取消
        switch tracker.release() {
        case .click:
            performClick(at: NSEvent.mouseLocation)
        case .dragged:
            guard interaction.isDragging else { return }
            setDragging(false)
            playHaptic(.alignment)
            onDragEnded?(wheelCenter)
            updateHover()
        }
    }

    private func setDragging(_ dragging: Bool) {
        interaction.isDragging = dragging
    }

    private func playHaptic(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        guard appState.settings.hapticFeedback else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }

    private func performClick(at point: NSPoint) {
        let dx = point.x - wheelCenter.x
        let dy = point.y - wheelCenter.y
        if let action = hitTester.centerAction(dx: dx, dy: dy) {
            let nowPlaying = appState.nowPlaying
            switch action {
            case .openSettings: onOpenSettings?()
            case .previousTrack: nowPlaying.previousTrack()
            case .togglePlayPause: nowPlaying.togglePlayPause()
            case .nextTrack: nowPlaying.nextTrack()
            case .seek(let seconds): nowPlaying.seek(to: seconds)
            }
            return
        }
        guard !hitTester.isInsideCenterControls(dx: dx, dy: dy), let item = item(at: point) else { return }
        if appState.settings.soundEffects { NSSound(named: "Tink")?.play() }
        if item.itemType == .keyAction {
            guard item.keyCombination != appState.settings.hotkey else {
                KeyActionService.showError("keyAction.conflict")
                return
            }
            item.runKeyAction()
        } else {
            appState.openItem(item)
        }
        onActivate?()
    }

    private func item(at point: NSPoint) -> AppItem? {
        if let index = hitTester.satelliteIndex(at: point, center: wheelCenter),
           index < appState.recentAppSnapshot.count {
            return appState.recentAppSnapshot[index]
        }
        if let index = hitTester.slotIndex(at: point, center: wheelCenter),
           index < appState.settings.apps.count {
            return appState.settings.apps[index]
        }
        return nil
    }

    private func showContextMenu(for event: NSEvent) {
        let menu = NSMenu()
        if let item = item(at: NSEvent.mouseLocation), item.itemType == .app, item.isRunning,
           let running = NSWorkspace.shared.runningApplications.first(where: {
               $0.bundleIdentifier == item.bundleIdentifier && !$0.isTerminated
           }) {
            contextMenuApplication = running
            let quit = NSMenuItem(title: Loc.string("wheel.quitRunningApp"), action: #selector(quitContextMenuApplication), keyEquivalent: "")
            quit.target = self
            menu.addItem(quit)
        } else {
            let title = Loc.string(isLocked() ? "pinned.unlock" : "pinned.lock")
            let lock = NSMenuItem(title: title, action: #selector(toggleLock), keyEquivalent: "")
            lock.target = self
            menu.addItem(lock)
        }
        menu.popUp(positioning: nil, at: contentView?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow, in: contentView)
        contextMenuApplication = nil
    }

    @objc private func quitContextMenuApplication() {
        contextMenuApplication?.terminate()
    }

    @objc private func toggleLock() {
        onToggleLock?()
    }

    // MARK: - 文件拖放

    func handleDragUpdate(_ sender: NSDraggingInfo) {
        let point = convertPoint(toScreen: sender.draggingLocation)
        let slot = hitTester.slotIndex(at: point, center: wheelCenter)
        if interaction.selectedIndex != slot { interaction.selectedIndex = slot }
    }

    func handleDragExit() {
        interaction.selectedIndex = nil
    }

    func handleDrop(_ sender: NSDraggingInfo) -> Bool {
        guard let index = interaction.selectedIndex, index < appState.settings.apps.count else { return false }
        return appState.openDroppedFiles(from: sender, with: appState.settings.apps[index])
    }

    deinit {
        stopObserving()
    }
}
