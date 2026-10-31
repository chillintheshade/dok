import SwiftUI
import AppKit

enum FirstRunGuideStep {
    case pressHotkey, useWheel, finished
}

/// 首次引导：不讲解，让用户亲手按一次快捷键、用一次轮盘。由真实事件推进，没有"下一步"。
final class FirstRunGuideController: ObservableObject {
    static let fallbackDelay: TimeInterval = 8

    @Published private(set) var step: FirstRunGuideStep = .pressHotkey
    @Published private(set) var showsFallback = false
    @Published private(set) var isChangingHotkey = false
    @Published private(set) var heldModifiers: NSEvent.ModifierFlags = []

    let appState: AppState
    var onShowWheel: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    private var panel: FirstRunGuidePanel?
    private var fallbackWork: DispatchWorkItem?
    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var hotkeyObserver: NSObjectProtocol?

    var isRunning: Bool { panel != nil }

    init(appState: AppState) {
        self.appState = appState
    }

    func start() {
        step = .pressHotkey
        isChangingHotkey = false
        if panel == nil {
            let created = FirstRunGuidePanel(rootView: AnyView(FirstRunGuideCard(guide: self)))
            panel = created
            created.orderFrontRegardless()
        }
        placePanel()
        startFlagsMonitor()
        scheduleFallback()
        // 换了快捷键：键帽跟着变，回到第一步。
        if hotkeyObserver == nil {
            hotkeyObserver = NotificationCenter.default.addObserver(forName: .hotkeyChanged, object: nil, queue: .main) { [weak self] _ in
                self?.hotkeyDidChange()
            }
        }
    }

    func skip() {
        complete()
    }

    /// 走完最后一步。
    func finish(openSettings: Bool) {
        complete()
        if openSettings { onOpenSettings?() }
    }

    private func complete() {
        NotificationCenter.default.post(name: .hotkeyRecordingCancelled, object: nil)
        appState.settings.hasCompletedOnboarding = true
        fallbackWork?.cancel()
        stopFlagsMonitor()
        if let hotkeyObserver { NotificationCenter.default.removeObserver(hotkeyObserver) }
        hotkeyObserver = nil
        panel?.orderOut(nil)
        panel = nil
    }

    func hotkeyDidFire() {
        guard isRunning, step == .pressHotkey, !isChangingHotkey else { return }
        enterUseWheel()
    }

    func wheelDidClose() {
        guard isRunning, step == .useWheel else { return }
        step = .finished
        placePanel()
    }

    func openWheelFromFallback() {
        onShowWheel?()
        enterUseWheel()
    }

    func beginChangingHotkey() {
        fallbackWork?.cancel()
        isChangingHotkey = true
        panel?.makeKey()
        placePanel()
    }

    func cancelChangingHotkey() {
        NotificationCenter.default.post(name: .hotkeyRecordingCancelled, object: nil)
        isChangingHotkey = false
        placePanel()
    }

    private func hotkeyDidChange() {
        guard isRunning, isChangingHotkey else { return }
        isChangingHotkey = false
        showsFallback = false
        scheduleFallback()
    }

    private func enterUseWheel() {
        fallbackWork?.cancel()
        showsFallback = false
        stopFlagsMonitor()
        step = .useWheel
        placePanel()
    }

    private func scheduleFallback() {
        fallbackWork?.cancel()
        showsFallback = false
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.step == .pressHotkey else { return }
            self.showsFallback = true
            self.placePanel()
        }
        fallbackWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.fallbackDelay, execute: work)
    }

    /// 修饰键按下就亮起。没有输入监控权限时拿不到全局事件，也绝不弹权限框：键帽不提前亮，流程照常。
    private func startFlagsMonitor() {
        stopFlagsMonitor()
        if CGPreflightListenEventAccess() {
            globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                self?.heldModifiers = event.modifierFlags
            }
        }
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.heldModifiers = event.modifierFlags
            return event
        }
    }

    private func stopFlagsMonitor() {
        if let globalFlagsMonitor { NSEvent.removeMonitor(globalFlagsMonitor) }
        if let localFlagsMonitor { NSEvent.removeMonitor(localFlagsMonitor) }
        globalFlagsMonitor = nil
        localFlagsMonitor = nil
        heldModifiers = []
    }

    /// 第一、三步在屏幕中央；第二步让开轮盘，放到鼠标所在屏幕离鼠标较远的一端。
    private func placePanel() {
        guard let panel else { return }
        DispatchQueue.main.async { [weak panel, step = step] in
            guard let panel else { return }
            let mouse = NSEvent.mouseLocation
            guard let screen = (NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main)?.visibleFrame else { return }
            panel.fitToContent()
            let size = panel.frame.size
            var origin = NSPoint(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2)
            if step == .useWheel {
                origin.y = mouse.y > screen.midY ? screen.minY + 48 : screen.maxY - size.height - 48
            }
            panel.setFrameOrigin(origin)
        }
    }
}

private final class FirstRunGuidePanel: NSPanel {
    private let hosting: NSHostingView<AnyView>

    init(rootView: AnyView) {
        hosting = NSHostingView(rootView: rootView)
        super.init(contentRect: NSRect(x: 0, y: 0, width: 360, height: 200),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        contentView = hosting
    }

    /// 录入新快捷键时要收键盘事件。
    override var canBecomeKey: Bool { true }

    func fitToContent() {
        setContentSize(hosting.fittingSize)
    }
}

private struct FirstRunGuideCard: View {
    @ObservedObject var guide: FirstRunGuideController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 16) {
            switch guide.step {
            case .pressHotkey:
                pressHotkey
            case .useWheel:
                Text(Loc.string(guide.appState.settings.interactionMode == .hold ? "guide.useWheel.hold" : "guide.useWheel"))
                    .font(.system(size: 14, weight: .medium))
                skipButton
            case .finished:
                finished
            }
        }
        .padding(24)
        .frame(width: 360)
        .modifier(GuideCardSurface())
        .animation(reduceMotion ? nil : .timingCurve(0.32, 0.72, 0, 1, duration: 0.32), value: guide.showsFallback)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var pressHotkey: some View {
        VStack(spacing: 16) {
            Text(Loc.string("onboarding.title"))
                .font(.system(size: 15, weight: .semibold))
            HStack(spacing: 6) {
                ForEach(Array(guide.appState.settings.hotkey.keySymbols.enumerated()), id: \.offset) { _, symbol in
                    LargeKeyCap(text: symbol)
                        .opacity(isHeld(symbol) || guide.heldModifiers.isEmpty ? 1 : 0.5)
                }
            }
            Text(Loc.string("guide.press"))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            if guide.isChangingHotkey {
                HotkeyRecorderRow(appState: guide.appState)
                    .frame(height: 44)
                Button(Loc.string("link.cancel")) { guide.cancelChangingHotkey() }
                    .buttonStyle(SettingsPillButtonStyle())
            } else if guide.showsFallback {
                HStack(spacing: 8) {
                    Button(Loc.string("guide.changeHotkey")) { guide.beginChangingHotkey() }
                        .buttonStyle(SettingsPillButtonStyle())
                    Button(Loc.string("guide.openWheel")) { guide.openWheelFromFallback() }
                        .buttonStyle(SettingsPillButtonStyle(prominent: true))
                }
            }
            skipButton
        }
    }

    private var finished: some View {
        VStack(spacing: 16) {
            Text(Loc.string("guide.done"))
                .font(.system(size: 14, weight: .medium))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button(Loc.string("guide.openSettings")) { guide.finish(openSettings: true) }
                    .buttonStyle(SettingsPillButtonStyle())
                Button(Loc.string("guide.start")) { guide.finish(openSettings: false) }
                    .buttonStyle(SettingsPillButtonStyle(prominent: true))
            }
        }
    }

    private var skipButton: some View {
        Button(Loc.string("guide.skip")) { guide.skip() }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
    }

    private func isHeld(_ symbol: String) -> Bool {
        let flags = guide.heldModifiers
        switch symbol {
        case "⌃": return flags.contains(.control)
        case "⌥": return flags.contains(.option)
        case "⇧": return flags.contains(.shift)
        case "⌘": return flags.contains(.command)
        default: return false
        }
    }
}

private struct GuideCardSurface: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: 20))
        } else {
            content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}
