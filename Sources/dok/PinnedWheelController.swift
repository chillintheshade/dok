import AppKit

/// 管理常驻模式：建窗口、记位置、小圆点的展开和收回。
final class PinnedWheelController: NSObject {
    static let hoverExpandDelay: TimeInterval = 0.15
    static let collapseDelay: TimeInterval = 0.25

    private let appState: AppState
    private var mode: PinnedMode = .off
    private var wheel: PinnedWheelWindow?
    private var orb: PinnedOrbWindow?
    private var hoverWork: DispatchWorkItem?
    private var collapseWork: DispatchWorkItem?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var streamTimer: Timer?
    private var screenObserver: NSObjectProtocol?

    var onOpenSettings: (() -> Void)?
    var onExpansionChanged: (() -> Void)?
    /// 轮盘展开期间 Esc 要能收起它。
    private(set) var wantsEscape: Bool = false {
        didSet { if wantsEscape != oldValue { onExpansionChanged?() } }
    }

    /// 置顶模式下完整轮盘正展开。
    var isWheelExpanded: Bool { mode == .floating && wheel?.interaction.isMenuVisible == true }

    init(appState: AppState) {
        self.appState = appState
        super.init()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.keepOnScreen()
        }
    }

    deinit {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

    private var screens: [NSRect] { NSScreen.screens.map(\.visibleFrame) }

    private var wheelRadius: CGFloat { appState.settings.menuRadius + 50 + 8 }

    private var wheelBottomExtra: CGFloat {
        appState.settings.showRecentApps
            ? RecentAppSatelliteGeometry.baseDiameter(for: appState.settings.iconSize) + 16
            : 0
    }

    private func clampedWheelCenter(_ center: NSPoint) -> NSPoint {
        PinnedDragTracker.clampedCenter(center, radius: wheelRadius, bottomExtra: wheelBottomExtra, screens: screens)
    }

    // MARK: - 模式

    func apply(mode newMode: PinnedMode) {
        guard newMode != mode else { return }
        tearDown()
        mode = newMode
        switch newMode {
        case .off: return
        case .desktop: showDesktopWheel()
        case .floating: showOrb()
        }
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            self?.appState.nowPlaying.reevaluateStream()
        }
        RunLoop.main.add(timer, forMode: .common)
        streamTimer = timer
    }

    func applyAppearance() {
        wheel?.applyAppearance()
        orb?.applyAppearance()
    }

    private func tearDown() {
        wantsEscape = false
        cancelTimers()
        stopMonitors()
        streamTimer?.invalidate()
        streamTimer = nil
        if orb != nil { appState.nowPlaying.endConsuming(.pinnedOrb) }
        orb?.orderOut(nil)
        orb = nil
        if let old = wheel {
            wheel = nil
            old.hide { _ = old }  // 留到淡出结束
        }
    }

    private func makeWheel(level: NSWindow.Level, behavior: NSWindow.CollectionBehavior, tracksOcclusion: Bool) -> PinnedWheelWindow {
        let window = PinnedWheelWindow(appState: appState, level: level, collectionBehavior: behavior, tracksOcclusion: tracksOcclusion)
        window.onOpenSettings = { [weak self] in
            self?.collapse()
            self?.onOpenSettings?()
        }
        window.isLocked = { [weak self] in self?.appState.settings.pinnedLocked ?? false }
        window.onToggleLock = { [weak self] in self?.toggleLock() }
        return window
    }

    private func toggleLock() {
        appState.settings.pinnedLocked.toggle()
    }

    // MARK: - 桌面模式

    private func showDesktopWheel() {
        let window = makeWheel(level: PinnedWheelWindow.desktopLevel,
                               behavior: [.canJoinAllSpaces, .stationary, .ignoresCycle],
                               tracksOcclusion: true)
        window.onDragEnded = { [weak self, weak window] center in
            guard let self else { return }
            let clamped = self.clampedWheelCenter(center)
            window?.moveCenter(to: clamped)
            self.appState.settings.pinnedDesktopCenter = clamped
        }
        let fallback = NSScreen.main.map { NSPoint(x: $0.visibleFrame.midX, y: $0.visibleFrame.midY) } ?? .zero
        window.moveCenter(to: clampedWheelCenter(appState.settings.pinnedDesktopCenter ?? fallback))
        wheel = window
        window.present()
    }

    // MARK: - 置顶模式

    private func showOrb() {
        let window = PinnedOrbWindow(appState: appState)
        window.isDraggable = { [weak self] in !(self?.appState.settings.pinnedLocked ?? false) }
        window.onClick = { [weak self] in self?.expand() }
        window.onDragBegan = { [weak self] in
            self?.cancelTimers()
            self?.collapse()
        }
        window.onDragEnded = { [weak self, weak window] center in
            guard let self, let window else { return }
            let snapped = PinnedOrbWindow.snappedToEdge(center, screens: self.screens)
            self.moveOrb(window, to: snapped)
            self.appState.settings.pinnedOrbCenter = snapped
        }
        window.onRightClick = { [weak self, weak window] event in
            guard let self, let window else { return }
            let menu = NSMenu()
            let item = NSMenuItem(title: Loc.string(self.appState.settings.pinnedLocked ? "pinned.unlock" : "pinned.lock"),
                                  action: #selector(self.toggleLockFromMenu), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
            menu.popUp(positioning: nil, at: window.contentView?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow, in: window.contentView)
        }
        let fallback = NSScreen.main.map {
            NSPoint(x: $0.visibleFrame.maxX - PinnedOrbWindow.diameter, y: $0.visibleFrame.midY)
        } ?? .zero
        window.moveCenter(to: PinnedOrbWindow.snappedToEdge(appState.settings.pinnedOrbCenter ?? fallback, screens: screens))
        orb = window
        window.orderFrontRegardless()

        let wheel = makeWheel(level: .popUpMenu,
                              behavior: [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle],
                              tracksOcclusion: false)
        // 展开的轮盘不能拖：要换位置就拖旁边的小圆点。
        wheel.isDraggable = false
        wheel.onActivate = { [weak self] in self?.collapse() }
        self.wheel = wheel

        appState.nowPlaying.beginConsuming(.pinnedOrb)
        startMonitors()
    }

    @objc private func toggleLockFromMenu() {
        toggleLock()
    }

    private func moveOrb(_ window: PinnedOrbWindow, to center: NSPoint) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            window.moveCenter(to: center)
            return
        }
        let target = NSRect(x: center.x - window.frame.width / 2, y: center.y - window.frame.height / 2,
                            width: window.frame.width, height: window.frame.height)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.32, 0.72, 0, 1)
            window.animator().setFrame(target, display: true)
        }
    }

    private func startMonitors() {
        let kinds: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: kinds) { [weak self] _ in
            self?.updateFloatingHover()
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: kinds) { [weak self] event in
            self?.updateFloatingHover()
            return event
        }
    }

    private func stopMonitors() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    private func cancelTimers() {
        hoverWork?.cancel()
        hoverWork = nil
        collapseWork?.cancel()
        collapseWork = nil
    }

    private func updateFloatingHover() {
        guard let orb, let wheel else { return }
        let point = NSEvent.mouseLocation
        if isWheelExpanded {
            // 小圆点贴在屏幕角落时可能在圆盘之外，鼠标还停在那里不能算离开。
            let inside = WheelHitTester(appState: appState).isInsideWheel(at: point, center: wheel.wheelCenter)
                || hypot(point.x - orb.center.x, point.y - orb.center.y) <= PinnedOrbWindow.diameter / 2
            if inside {
                collapseWork?.cancel()
                collapseWork = nil
            } else if collapseWork == nil {
                let work = DispatchWorkItem { [weak self] in self?.collapse() }
                collapseWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.collapseDelay, execute: work)
            }
            return
        }
        // 按住鼠标时不展开：可能正要拖动，或者只是拖东西路过。
        let onOrb = hypot(point.x - orb.center.x, point.y - orb.center.y) <= PinnedOrbWindow.diameter / 2
        guard onOrb, NSEvent.pressedMouseButtons == 0, orb.isVisible else {
            hoverWork?.cancel()
            hoverWork = nil
            return
        }
        guard hoverWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.hoverWork = nil
            guard NSEvent.pressedMouseButtons == 0 else { return }
            self?.expand()
        }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hoverExpandDelay, execute: work)
    }

    /// 轮盘开在小圆点朝屏幕中央的一侧，紧贴但不盖住它。
    private func expandedCenter(for orbCenter: NSPoint) -> NSPoint {
        let screen = screens.first { $0.insetBy(dx: -1, dy: -1).contains(orbCenter) } ?? screens.first ?? .zero
        let dx = screen.midX - orbCenter.x
        let dy = screen.midY - orbCenter.y
        let length = max(hypot(dx, dy), 1)
        let distance = appState.settings.menuRadius + 50 + PinnedOrbWindow.diameter / 2 + 4
        return NSPoint(x: orbCenter.x + dx / length * distance, y: orbCenter.y + dy / length * distance)
    }

    private func expand() {
        guard mode == .floating, let orb, let wheel, !isWheelExpanded else { return }
        cancelTimers()
        wheel.moveCenter(to: clampedWheelCenter(expandedCenter(for: orb.center)))
        wheel.present()
        // 小圆点留在轮盘旁边，随时能直接拖。
        orb.orderFrontRegardless()
        wantsEscape = true
    }

    /// 置顶模式收回成小圆点。桌面模式的轮盘不收起。
    func collapse() {
        guard mode == .floating, let wheel, isWheelExpanded else { return }
        cancelTimers()
        wantsEscape = false
        wheel.hide()
    }

    private func keepOnScreen() {
        switch mode {
        case .off:
            break
        case .desktop:
            wheel?.moveCenter(to: clampedWheelCenter(appState.settings.pinnedDesktopCenter ?? wheel?.wheelCenter ?? .zero))
        case .floating:
            guard let orb else { return }
            orb.moveCenter(to: PinnedOrbWindow.snappedToEdge(appState.settings.pinnedOrbCenter ?? orb.center, screens: screens))
            if isWheelExpanded { wheel?.moveCenter(to: clampedWheelCenter(expandedCenter(for: orb.center))) }
        }
    }
}
