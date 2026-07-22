import AppKit
import SwiftUI
import Carbon
import ServiceManagement

@main
enum ArclyEntry {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var statusItem: NSStatusItem!
    var appState = AppState()
    var wheelWindow: ArclyWheelWindow?
    var settingsWindow: NSWindow?
    var hotKeyRef: EventHotKeyRef?
    var isMenuOpen = false
    private var settingsKeyMonitor: Any?
    private var mouseDownMonitor: Any?
    private var mouseUpMonitor: Any?
    private var mouseEventTap: CFMachPort?
    private var mouseEventRunLoopSource: CFRunLoopSource?

    private var showMenuTitle: String {
        Loc.string("menu.show")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        setupStatusBar()
        registerHotKey()

        // 监听快捷键修改
        NotificationCenter.default.addObserver(
            self, selector: #selector(hotkeyDidChange),
            name: .hotkeyChanged, object: nil
        )

        // 监听外观修改
        NotificationCenter.default.addObserver(
            self, selector: #selector(appearanceDidChange),
            name: .appearanceChanged, object: nil
        )

        // 监听菜单栏图标开关
        NotificationCenter.default.addObserver(
            self, selector: #selector(menuBarIconDidChange),
            name: .menuBarIconChanged, object: nil
        )

        // 监听鼠标按键触发修改
        NotificationCenter.default.addObserver(
            self, selector: #selector(mouseTriggerDidChange),
            name: .mouseTriggerChanged, object: nil
        )

        // 启动 Now Playing 监听
        appState.nowPlaying.startObserving()

        // 注册鼠标按键触发
        setupMouseTrigger()

        NSLog("✅ 轮盘已启动！按 %@ 打开菜单", appState.settings.hotkey.displayString)

        // 首次启动引导
        if !appState.settings.hasCompletedOnboarding {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.showOnboarding()
            }
        }
    }

    func showOnboarding() {
        let alert = NSAlert()
        alert.messageText = Loc.string("onboarding.title")
        alert.informativeText = Loc.string("onboarding.body", appState.settings.hotkey.displayString)
        alert.alertStyle = .informational
        alert.addButton(withTitle: Loc.string("onboarding.start"))
        alert.addButton(withTitle: Loc.string("onboarding.openAccessibility"))

        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            NSWorkspace.shared.open(url)
        }

        appState.settings.hasCompletedOnboarding = true

        // 首次启动弹出轮盘，让用户直观看到效果
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.showArcly()
        }
    }

    @objc func mouseTriggerDidChange() {
        setupMouseTrigger()
    }

    func setupMouseTrigger() {
        // 清除旧监听
        removeMouseEventTap()
        if let m = mouseDownMonitor { NSEvent.removeMonitor(m); mouseDownMonitor = nil }
        if let m = mouseUpMonitor { NSEvent.removeMonitor(m); mouseUpMonitor = nil }

        guard appState.settings.mouseTrigger.buttonNumber != nil else { return }

        if installMouseEventTap() {
            return
        }

        // 系统事件 tap 装不上时的兜底监听
        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.otherMouseDown]) { [weak self] event in
            self?.handleMouseTriggerDown(buttonNumber: event.buttonNumber)
        }

        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.otherMouseUp]) { [weak self] event in
            self?.handleMouseTriggerUp(buttonNumber: event.buttonNumber)
        }
    }

    private func installMouseEventTap() -> Bool {
        let downMask = CGEventMask(1 << CGEventType.otherMouseDown.rawValue)
        let upMask = CGEventMask(1 << CGEventType.otherMouseUp.rawValue)
        let eventMask = downMask | upMask
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: AppDelegate.mouseEventTapCallback,
            userInfo: refcon
        ) else {
            NSLog("⚠️ mouse trigger event tap unavailable; falling back to NSEvent monitor")
            return false
        }

        mouseEventTap = tap
        mouseEventRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source = mouseEventRunLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func removeMouseEventTap() {
        if let source = mouseEventRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap = mouseEventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        mouseEventRunLoopSource = nil
        mouseEventTap = nil
    }

    private static let mouseEventTapCallback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
        let delegate = Unmanaged<AppDelegate>.fromOpaque(refcon).takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = delegate.mouseEventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let buttonNumber = Int(event.getIntegerValueField(.mouseEventButtonNumber))
        DispatchQueue.main.async {
            switch type {
            case .otherMouseDown:
                delegate.handleMouseTriggerDown(buttonNumber: buttonNumber)
            case .otherMouseUp:
                delegate.handleMouseTriggerUp(buttonNumber: buttonNumber)
            default:
                break
            }
        }

        return Unmanaged.passUnretained(event)
    }

    private func handleMouseTriggerDown(buttonNumber: Int) {
        guard buttonNumber == appState.settings.mouseTrigger.buttonNumber else { return }

        if appState.settings.interactionMode == .hold {
            if !isMenuOpen { showArcly() }
        } else {
            toggleArcly()
        }
    }

    private func handleMouseTriggerUp(buttonNumber: Int) {
        guard wheelWindow?.isContextMenuOpen != true else { return }
        guard buttonNumber == appState.settings.mouseTrigger.buttonNumber,
              appState.settings.interactionMode == .hold,
              isMenuOpen else {
            return
        }

        if let app = wheelWindow?.selectedAppForActivation() {
            closeArcly()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.wheelWindow?.launchApp(app) ?? {
                    if app.itemType == .fileOrFolder {
                        app.openFileOrFolder()
                    } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleIdentifier) {
                        let config = NSWorkspace.OpenConfiguration()
                        config.activates = true
                        NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: nil)
                    }
                }()
            }
        } else {
            closeArcly()
        }
    }

    @objc func menuBarIconDidChange() {
        if appState.settings.showMenuBarIcon {
            if statusItem == nil {
                setupStatusBar()
            }
            statusItem.isVisible = true
        } else {
            statusItem.isVisible = false
        }
    }

    @objc func appearanceDidChange() {
        wheelWindow?.applyAppearance()
        applySettingsAppearance()
    }

    @objc func hotkeyDidChange() {
        registerHotKey()
        // 更新菜单栏显示
        if let menu = statusItem?.menu,
           let showItem = menu.items.first {
            configureShowMenuItem(showItem)
        }
    }

    // 点 Dock 图标时弹轮盘
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showArcly()
        }
        return false
    }

    // MARK: - Dock 菜单（右键 Dock 图标）

    // Dock 右键菜单
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let dockMenu = NSMenu()

        let showItem = NSMenuItem(title: showMenuTitle, action: #selector(manualShowArcly), keyEquivalent: "")
        configureShowMenuItem(showItem)
        showItem.target = self
        dockMenu.addItem(showItem)

        dockMenu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: Loc.string("menu.settings"), action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        dockMenu.addItem(settingsItem)

        return dockMenu
    }

    // MARK: - 主菜单（Cmd+W / 输入法 / 剪切板依赖）

    func setupMainMenu() {
        let mainMenu = NSMenu()

        // App 菜单
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: Loc.string("menu.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // File 菜单 — Cmd+W 关闭窗口
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: Loc.string("menu.file"))
        fileMenu.addItem(NSMenuItem(title: Loc.string("menu.closeWindow"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // Edit 菜单 — IME 输入法 + 剪切板
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: Loc.string("menu.edit"))
        editMenu.addItem(NSMenuItem(title: Loc.string("menu.undo"), action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: Loc.string("menu.redo"), action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: Loc.string("menu.cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: Loc.string("menu.copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: Loc.string("menu.paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: Loc.string("menu.selectAll"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    // MARK: - 菜单栏图标

    func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            if let img = NSImage(systemSymbolName: "circle.grid.cross", accessibilityDescription: "Arcly") {
                img.size = NSSize(width: 17, height: 17)
                img.isTemplate = true
                button.image = img
            }
            button.imagePosition = .imageOnly
            button.toolTip = "Arcly"
            NSLog("✅ 状态栏图标已创建")
        } else {
            NSLog("❌ 状态栏按钮创建失败")
        }

        let menu = NSMenu()

        let showItem = NSMenuItem(title: showMenuTitle, action: #selector(manualShowArcly), keyEquivalent: "")
        configureShowMenuItem(showItem)
        showItem.target = self
        menu.addItem(showItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: Loc.string("menu.settings"), action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: Loc.string("menu.quit"), action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func configureShowMenuItem(_ item: NSMenuItem) {
        let hotkey = appState.settings.hotkey
        item.title = showMenuTitle
        item.keyEquivalent = hotkey.menuKeyEquivalent
        item.keyEquivalentModifierMask = hotkey.menuModifierMask
    }

    // MARK: - 全局快捷键

    private var eventHandlerInstalled = false

    func registerHotKey() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }

        let hotkey = appState.settings.hotkey
        let hotkeyKeyCode: UInt32 = UInt32(hotkey.keyCode)
        let carbonModifiers: UInt32 = hotkey.carbonModifiers

        let hotKeyID = EventHotKeyID(signature: OSType(0x50494531), id: 1)

        if !eventHandlerInstalled {
            var eventTypes = [
                EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                              eventKind: UInt32(kEventHotKeyPressed)),
                EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                              eventKind: UInt32(kEventHotKeyReleased)),
            ]

            let selfPtr = Unmanaged.passUnretained(self).toOpaque()

            InstallEventHandler(
                GetApplicationEventTarget(),
                { (_, event, userData) -> OSStatus in
                    guard let userData = userData else { return OSStatus(eventNotHandledErr) }
                    let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                    let eventKind = GetEventKind(event)
                    DispatchQueue.main.async {
                        if eventKind == UInt32(kEventHotKeyPressed) {
                            delegate.handleHotKeyDown()
                        } else if eventKind == UInt32(kEventHotKeyReleased) {
                            delegate.handleHotKeyUp()
                        }
                    }
                    return noErr
                },
                2,
                &eventTypes,
                selfPtr,
                nil
            )
            eventHandlerInstalled = true
        }

        let status = RegisterEventHotKey(
            hotkeyKeyCode, carbonModifiers, hotKeyID,
            GetApplicationEventTarget(), 0, &hotKeyRef
        )

        if status == noErr {
            NSLog("✅ 快捷键注册成功: %@", hotkey.displayString)
        } else {
            NSLog("❌ 快捷键注册失败: %d", status)
        }
    }

    // MARK: - 快捷键事件

    func handleHotKeyDown() {
        NSLog("🔑 handleHotKeyDown: mode=%@, isMenuOpen=%d", appState.settings.interactionMode.rawValue, isMenuOpen)
        if appState.settings.interactionMode == .hold {
            // 按住模式：按下 → 显示菜单
            if !isMenuOpen {
                showArcly()
            }
        } else {
            // 点击模式：按下 → 切换菜单
            toggleArcly()
        }
    }

    func handleHotKeyUp() {
        guard wheelWindow?.isContextMenuOpen != true else { return }
        if appState.settings.interactionMode == .hold && isMenuOpen {
            // 按住模式：松开 → 执行选中并关闭
            if let app = wheelWindow?.selectedAppForActivation() {
                closeArcly()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.wheelWindow?.launchApp(app) ?? {
                        // wheelWindow 已关闭，直接启动
                        if app.itemType == .fileOrFolder {
                            app.openFileOrFolder()
                        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleIdentifier) {
                            let config = NSWorkspace.OpenConfiguration()
                            config.activates = true
                            NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: nil)
                        }
                    }()
                }
            } else {
                closeArcly()
            }
        }
    }

    // MARK: - 轮盘操作

    func toggleArcly() {
        if isMenuOpen {
            closeArcly()
        } else {
            showArcly()
        }
    }

    func showArcly() {
        let window: ArclyWheelWindow
        if let existing = wheelWindow {
            window = existing
        } else {
            let created = ArclyWheelWindow(appState: appState)
            created.onDismiss = { [weak self] in
                self?.isMenuOpen = false
            }
            created.onOpenSettings = { [weak self] in
                self?.openSettings()
            }
            wheelWindow = created
            window = created
        }

        let mouseLocation = NSEvent.mouseLocation
        appState.nowPlaying.refreshForMenuPresentation()
        window.showAt(point: mouseLocation)
        isMenuOpen = true
        NSLog("✅ showArcly: window shown at (%.0f, %.0f)", mouseLocation.x, mouseLocation.y)
    }

    func closeArcly() {
        guard let window = wheelWindow else { return }
        isMenuOpen = false
        window.dismiss()
    }

    @objc func manualShowArcly() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.showArcly()
        }
    }

    @objc func openSettings() {
        NSApp.setActivationPolicy(.regular)
        setupMainMenu()

        if settingsWindow == nil {
            let settingsView = SettingsView()
                .environmentObject(appState)
            let hostingController = NSHostingController(rootView: settingsView)
            let window = NSWindow(contentViewController: hostingController)
            window.title = Loc.string("settings.windowTitle")
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.setContentSize(NSSize(width: 920, height: 520))
            window.center()
            window.delegate = self
            self.settingsWindow = window
        }
        applySettingsAppearance()

        // Cmd+W 直接用事件监听，不依赖菜单栏
        if settingsKeyMonitor == nil {
            settingsKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.modifierFlags.contains(.command),
                   event.charactersIgnoringModifiers == "w" {
                    self?.settingsWindow?.performClose(nil)
                    return nil
                }
                return event
            }
        }

        guard let w = settingsWindow else { return }
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)

        // 补救：如果首次激活太早（setActivationPolicy 异步），100ms 后再试一次
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if !NSApp.isActive || !w.isKeyWindow {
                NSApp.activate(ignoringOtherApps: true)
                w.makeKeyAndOrderFront(nil)
            }
        }
    }

    func applySettingsAppearance() {
        switch appState.settings.appearanceMode {
        case .light: settingsWindow?.appearance = NSAppearance(named: .aqua)
        case .dark: settingsWindow?.appearance = NSAppearance(named: .darkAqua)
        case .system: settingsWindow?.appearance = nil
        }
    }

    // 设置窗口关闭时隐藏 Dock + 清理监听
    func windowWillClose(_ notification: Notification) {
        if let m = settingsKeyMonitor {
            NSEvent.removeMonitor(m)
            settingsKeyMonitor = nil
        }
        settingsWindow = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }
}
