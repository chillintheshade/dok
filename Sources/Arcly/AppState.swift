import SwiftUI
import AppKit
import Carbon

extension Notification.Name {
    static let hotkeyChanged = Notification.Name("Arcly.hotkeyChanged")
    static let appearanceChanged = Notification.Name("Arcly.appearanceChanged")
    static let menuBarIconChanged = Notification.Name("Arcly.menuBarIconChanged")
    static let mouseTriggerChanged = Notification.Name("Arcly.mouseTriggerChanged")
    static let hotkeyRecordingCancelled = Notification.Name("Arcly.hotkeyRecordingCancelled")
}

// MARK: - Data Models

enum WheelItemType: String, Codable {
    case app = "app"
    case fileOrFolder = "fileOrFolder"
}

struct AppItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var bundleIdentifier: String
    var path: String
    var itemType: WheelItemType = .app
    var bookmarkData: Data?
    var customIconData: Data?

    /// 缓存版本 — 视图中使用这两个
    var displayName: String { IconCache.shared.displayName(for: self) }
    var icon: NSImage { IconCache.shared.icon(for: self) }

    func resolvedFileURL() -> URL {
        Self.resolvingAliasIfNeeded(securityScopedFileURL())
    }

    private func securityScopedFileURL() -> URL {
        guard itemType == .fileOrFolder, let bookmarkData else {
            return URL(fileURLWithPath: path)
        }

        var isStale = false
        if let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) {
            return url
        }

        return URL(fileURLWithPath: path)
    }

    /// 实际加载逻辑（仅由 IconCache 调用一次）
    func resolveDisplayName() -> String {
        if itemType == .fileOrFolder {
            let url = resolvedFileURL()
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess { url.stopAccessingSecurityScopedResource() }
            }

            if let values = try? url.resourceValues(forKeys: [.localizedNameKey]),
               let localized = values.localizedName,
               !localized.isEmpty {
                return localized
            }
            return url.lastPathComponent
        }
        if Loc.prefersChinese, let cn = AppItem.chineseNames[bundleIdentifier] { return cn }
        let url = URL(fileURLWithPath: path)
        if let values = try? url.resourceValues(forKeys: [.localizedNameKey]),
           let localized = values.localizedName {
            let cleaned = localized.replacingOccurrences(of: ".app", with: "")
            if cleaned != name && !cleaned.isEmpty { return cleaned }
        }
        if let bundle = Bundle(url: url) {
            if let dn = bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String { return dn }
            if let bn = bundle.localizedInfoDictionary?["CFBundleName"] as? String { return bn }
        }
        return name
    }

    func loadIcon() -> NSImage {
        if itemType == .fileOrFolder {
            if let customIconData, let image = NSImage(data: customIconData) {
                return image
            }

            let url = resolvedFileURL()
            _ = url.startAccessingSecurityScopedResource()

            if let customIcon = customIcon(for: url) {
                return customIcon
            }

            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                return NSWorkspace.shared.icon(forFile: url.path)
            }

            let isAliasFile = (try? url.resourceValues(forKeys: [.isAliasFileKey]).isAliasFile) ?? false
            if let aliasTarget = try? URL(resolvingAliasFileAt: url),
               aliasTarget.path != url.path {
                return NSWorkspace.shared.icon(forFile: aliasTarget.path)
            }

            if isAliasFile && url.pathExtension.isEmpty {
                return NSWorkspace.shared.icon(for: .folder)
            }

            return NSWorkspace.shared.icon(forFile: url.path)
        }
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return NSWorkspace.shared.icon(forFile: app.path)
        }
        return NSWorkspace.shared.icon(forFile: path)
    }

    static func persistentCustomIconData(for url: URL) -> Data? {
        if let data = iconDataFromResourceFork(for: url) {
            return data
        }

        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            let iconFile = url.appendingPathComponent("Icon\r")
            return iconDataFromResourceFork(for: iconFile)
        }

        return nil
    }

    private func customIcon(for url: URL) -> NSImage? {
        guard let data = Self.persistentCustomIconData(for: url) else { return nil }
        return NSImage(data: data)
    }

    private static func resolvingAliasIfNeeded(_ url: URL) -> URL {
        guard ((try? url.resourceValues(forKeys: [.isAliasFileKey]).isAliasFile) ?? false),
              let resolvedURL = try? URL(resolvingAliasFileAt: url, options: []) else {
            return url
        }
        return resolvedURL
    }

    private static func iconDataFromResourceFork(for url: URL) -> Data? {
        let resourceForkURL = URL(fileURLWithPath: url.path + "/..namedfork/rsrc")
        guard let data = try? Data(contentsOf: resourceForkURL),
              data.count >= 8 else { return nil }

        let bytes = [UInt8](data)
        var offset = 0
        while offset <= bytes.count - 8 {
            if bytes[offset] == 0x69, bytes[offset + 1] == 0x63,
               bytes[offset + 2] == 0x6E, bytes[offset + 3] == 0x73 {
                let length = Int(bytes[offset + 4]) << 24
                    | Int(bytes[offset + 5]) << 16
                    | Int(bytes[offset + 6]) << 8
                    | Int(bytes[offset + 7])
                if length >= 8, offset + length <= data.count {
                    let iconData = data.subdata(in: offset..<(offset + length))
                    return NSImage(data: iconData) == nil ? nil : iconData
                }
            }
            offset += 1
        }

        return nil
    }

    func openFileOrFolder() {
        let scopedURL = securityScopedFileURL()
        let didAccessScopedURL = scopedURL.startAccessingSecurityScopedResource()
        let url = Self.resolvingAliasIfNeeded(scopedURL)
        let didAccessResolvedURL = url.path == scopedURL.path ? false : url.startAccessingSecurityScopedResource()
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open(url, configuration: config) { _, error in
            if let error {
                NSLog("❌ 打开文件或文件夹失败: %@", error.localizedDescription)
            }
            if didAccessResolvedURL {
                url.stopAccessingSecurityScopedResource()
            }
            if didAccessScopedURL {
                scopedURL.stopAccessingSecurityScopedResource()
            }
        }
    }

    var isRunning: Bool {
        guard itemType == .app else { return false }
        return !NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == bundleIdentifier }.isEmpty
    }

    /// 常用 app 中文名映射（系统 API 可能拿不到中文名时的兜底）
    static let chineseNames: [String: String] = [
        // Apple 系统应用
        "com.apple.finder": "访达",
        "com.apple.Safari": "Safari 浏览器",
        "com.apple.MobileSMS": "信息",
        "com.apple.mail": "邮件",
        "com.apple.iCal": "日历",
        "com.apple.Notes": "备忘录",
        "com.apple.Music": "音乐",
        "com.apple.systempreferences": "系统设置",
        "com.apple.Photos": "照片",
        "com.apple.reminders": "提醒事项",
        "com.apple.Maps": "地图",
        "com.apple.weather": "天气",
        "com.apple.news": "新闻",
        "com.apple.stocks": "股市",
        "com.apple.Home": "家庭",
        "com.apple.freeform": "无边记",
        "com.apple.dt.Xcode": "Xcode",
        "com.apple.Terminal": "终端",
        "com.apple.ActivityMonitor": "活动监视器",
        "com.apple.Preview": "预览",
        "com.apple.TextEdit": "文本编辑",
        "com.apple.AppStore": "App Store",
        "com.apple.FaceTime": "FaceTime 通话",
        "com.apple.calculator": "计算器",
        "com.apple.AddressBook": "通讯录",
        "com.apple.TV": "Apple TV",
        "com.apple.podcasts": "播客",
        "com.apple.Books": "图书",
        "com.apple.Passwords": "密码",
        "com.apple.ScreenSharing": "屏幕共享",
        "com.apple.Dictionary": "词典",
        "com.apple.shortcuts": "快捷指令",
        "com.apple.Automator": "自动操作",
        "com.apple.ColorSyncUtility": "ColorSync 实用工具",
        "com.apple.Console": "控制台",
        "com.apple.DiskUtility": "磁盘工具",
        "com.apple.FontBook": "字体册",
        "com.apple.GarageBand": "库乐队",
        "com.apple.iMovie": "iMovie 剪辑",
        "com.apple.iWork.Keynote": "Keynote 讲演",
        "com.apple.iWork.Numbers": "Numbers 表格",
        "com.apple.iWork.Pages": "Pages 文稿",
        "com.apple.keychainaccess": "钥匙串访问",
        "com.apple.ScriptEditor2": "脚本编辑器",
        "com.apple.ScreenCaptureUI": "截屏",
        "com.apple.VoiceMemos": "语音备忘录",
        "com.apple.Chess": "国际象棋",
        "com.apple.PhotoBooth": "Photo Booth",
        "com.apple.QuickTimePlayerX": "QuickTime Player",
        "com.apple.Stickies": "便签",
        "com.apple.siri.launcher": "Siri",
        "com.apple.MigrateAssistant": "迁移助理",
        "com.apple.BluetoothFileExchange": "蓝牙文件交换",
        "com.apple.audio.AudioMIDISetup": "音频 MIDI 设置",
        "com.apple.SystemProfiler": "系统信息",
        "com.apple.grapher": "Grapher",
        "com.apple.DigitalColorMeter": "数码测色计",
        "com.apple.airport.airportutility": "AirPort 实用工具",
        "com.apple.Accessibility.AccessibilityVisualsPreferences": "辅助功能",
        // 常用第三方应用
        "com.tencent.xinWeChat": "微信",
        "com.tencent.qq": "QQ",
        "com.tencent.QQMusicMac": "QQ音乐",
        "com.tencent.meeting": "腾讯会议",
        "com.tencent.LemonMonitor": "腾讯柠檬清理",
        "com.tencent.WeWorkMac": "企业微信",
        "com.alibaba.DingTalkMac": "钉钉",
        "com.netease.163music": "网易云音乐",
        "com.baidu.BaiduNetdisk-mac": "百度网盘",
        "com.feishu.Lark": "飞书",
        "com.bytedance.macos.feishu": "飞书",
        "com.electron.lark": "飞书",
        "com.wps.officemac": "WPS Office",
        "com.kingsoft.wpsoffice.mac": "WPS Office",
        "com.readdle.PDFExpert-Mac": "PDF Expert",
        "com.microsoft.Word": "Word",
        "com.microsoft.Excel": "Excel",
        "com.microsoft.Powerpoint": "PowerPoint",
        "com.microsoft.Outlook": "Outlook",
        "com.microsoft.onenote.mac": "OneNote",
        "com.microsoft.teams2": "Teams",
        "com.microsoft.VSCode": "VS Code",
        "com.microsoft.edgemac": "Edge",
        "com.google.Chrome": "Chrome",
        "org.mozilla.firefox": "Firefox",
        "com.brave.Browser": "Brave",
        "com.operasoftware.Opera": "Opera",
        "com.vivaldi.Vivaldi": "Vivaldi",
        "com.spotify.client": "Spotify",
        "com.notion.id": "Notion",
        "us.zoom.xos": "Zoom",
        "com.figma.Desktop": "Figma",
        "com.obsproject.obs-studio": "OBS",
        "com.postmanlabs.mac": "Postman",
        "com.docker.docker": "Docker Desktop",
        "com.sublimetext.4": "Sublime Text",
        "com.jetbrains.intellij": "IntelliJ IDEA",
        "com.jetbrains.WebStorm": "WebStorm",
        "com.jetbrains.pycharm": "PyCharm",
        "com.jetbrains.goland": "GoLand",
        "com.jetbrains.CLion": "CLion",
        "com.jetbrains.datagrip": "DataGrip",
        "com.apple.iBooksAuthor": "iBooks Author",
        "com.raycast.macos": "Raycast",
        "com.alfredapp.Alfred": "Alfred",
        "com.crowdcafe.windowmagnet": "Magnet",
        "com.hegenberg.BetterTouchTool": "BetterTouchTool",
        "com.1password.1password": "1Password",
        "com.bitwarden.desktop": "Bitwarden",
        "com.nssurge.surge-mac": "Surge",
        "com.lemonjarLLC.clashX": "ClashX",
        "com.west2online.ClashXPro": "ClashX Pro",
        "com.v2rayu.V2rayU": "V2rayU",
        "net.shadowsocks.ShadowsocksX-NG": "ShadowsocksX-NG",
        "com.sequelpro.SequelPro": "Sequel Pro",
        "com.tinyapp.TablePlus": "TablePlus",
        "com.ToothFairy.macOS": "ToothFairy",
        "me.sketch.Sketch": "Sketch",
        "com.pixelmatorteam.pixelmator.x": "Pixelmator Pro",
        "com.colliderli.iStatMenus": "iStat Menus",
        "com.agilebits.onepassword7": "1Password 7",
        "com.toggl.daneel": "Toggl Track",
        "com.tencent.wechatdevtools": "微信开发者工具",
    ]
}

enum InteractionMode: String, Codable, CaseIterable {
    case click = "click"
    case hold = "hold"
}

enum MenuPosition: String, Codable, CaseIterable {
    case followMouse = "followMouse"
    case screenCenter = "screenCenter"
}

enum MouseTrigger: String, Codable, CaseIterable {
    case none = "none"
    case middleButton = "middleButton"   // 中键
    case sideButton1 = "sideButton1"     // 侧键1 (Mouse4)
    case sideButton2 = "sideButton2"     // 侧键2 (Mouse5)

    var displayName: String {
        switch self {
        case .none: return Loc.string("trigger.none")
        case .middleButton: return Loc.string("trigger.middleButton")
        case .sideButton1: return Loc.string("trigger.sideButton1")
        case .sideButton2: return Loc.string("trigger.sideButton2")
        }
    }

    /// 对应的 NSEvent.buttonNumber
    var buttonNumber: Int? {
        switch self {
        case .none: return nil
        case .middleButton: return 2
        case .sideButton1: return 3
        case .sideButton2: return 4
        }
    }
}

enum AppearanceMode: String, Codable, CaseIterable {
    case system = "system"
    case light = "light"
    case dark = "dark"
}

struct HotkeyConfig: Codable {
    var keyCode: UInt16 = 50 // key left of 1
    var modifiers: NSEvent.ModifierFlags = [.command]

    var displayString: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }
        parts.append(Self.keyCodeToString(keyCode))
        return parts.joined()
    }

    /// 转换为 Carbon API 的修饰键
    var carbonModifiers: UInt32 {
        var result: UInt32 = 0
        if modifiers.contains(.command) { result |= UInt32(cmdKey) }
        if modifiers.contains(.shift) { result |= UInt32(shiftKey) }
        if modifiers.contains(.option) { result |= UInt32(optionKey) }
        if modifiers.contains(.control) { result |= UInt32(controlKey) }
        return result
    }

    static func keyCodeToString(_ keyCode: UInt16) -> String {
        let keyMap: [UInt16: String] = [
            49: "Space", 36: "Return", 48: "Tab", 51: "Delete",
            53: "Esc", 0: "A", 1: "S", 2: "D", 3: "F",
            4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
            11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 31: "O", 32: "U", 34: "I",
            35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
            18: "1", 19: "2", 20: "3", 21: "4", 23: "5",
            22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
            24: "=", 27: "-", 30: "]", 33: "[", 39: "'",
            41: ";", 42: "\\", 43: ",", 44: "/", 47: ".",
            50: "·", 76: "Enter",
            122: "F1", 120: "F2", 99: "F3", 118: "F4",
            96: "F5", 97: "F6", 98: "F7", 100: "F8",
            101: "F9", 109: "F10", 103: "F11", 111: "F12",
        ]
        return keyMap[keyCode] ?? "Key\(keyCode)"
    }

    var menuKeyEquivalent: String {
        switch keyCode {
        case 49: return " "
        case 36, 76: return "\r"
        case 48: return "\t"
        case 51: return "\u{8}"
        case 53: return "\u{1b}"
        default:
            let label = Self.keyCodeToString(keyCode)
            return label.count == 1 ? label.lowercased() : ""
        }
    }

    var menuModifierMask: NSEvent.ModifierFlags {
        modifiers.intersection([.command, .shift, .option, .control])
    }

    // Codable conformance for NSEvent.ModifierFlags
    enum CodingKeys: String, CodingKey {
        case keyCode, rawModifiers
    }

    init(keyCode: UInt16 = 50, modifiers: NSEvent.ModifierFlags = [.command]) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = try container.decode(UInt16.self, forKey: .keyCode)
        let rawModifiers = try container.decode(UInt.self, forKey: .rawModifiers)
        modifiers = NSEvent.ModifierFlags(rawValue: rawModifiers)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(keyCode, forKey: .keyCode)
        try container.encode(modifiers.rawValue, forKey: .rawModifiers)
    }
}

struct AppSettings: Codable {
    var apps: [AppItem] = []
    var recentApps: [AppItem] = []
    var recentAppCount: Int = 2
    var interactionMode: InteractionMode = .click
    var hotkey: HotkeyConfig = HotkeyConfig()
    var menuRadius: Double = 140
    var iconSize: Double = 48
    var menuOpacity: Double = 1.0
    var menuPosition: MenuPosition = .followMouse
    var appearanceMode: AppearanceMode = .system
    var hapticFeedback: Bool = true
    var soundEffects: Bool = true
    var showMenuBarIcon: Bool = true
    var showMusicControl: Bool = true
    var mouseTrigger: MouseTrigger = .none
    var hasCompletedOnboarding: Bool = false

    // 自定义 decoder：新增字段缺失时用默认值，兼容旧版 settings.json
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        apps = (try? c.decode([AppItem].self, forKey: .apps)) ?? []
        recentApps = Array(((try? c.decode([AppItem].self, forKey: .recentApps)) ?? []).prefix(10))
        recentAppCount = min(max((try? c.decode(Int.self, forKey: .recentAppCount)) ?? 2, 0), 3)
        interactionMode = (try? c.decode(InteractionMode.self, forKey: .interactionMode)) ?? .click
        hotkey = (try? c.decode(HotkeyConfig.self, forKey: .hotkey)) ?? HotkeyConfig()
        menuRadius = (try? c.decode(Double.self, forKey: .menuRadius)) ?? 140
        iconSize = (try? c.decode(Double.self, forKey: .iconSize)) ?? 48
        menuOpacity = (try? c.decode(Double.self, forKey: .menuOpacity)) ?? 1.0
        menuPosition = (try? c.decode(MenuPosition.self, forKey: .menuPosition)) ?? .followMouse
        appearanceMode = (try? c.decode(AppearanceMode.self, forKey: .appearanceMode)) ?? .system
        hapticFeedback = (try? c.decode(Bool.self, forKey: .hapticFeedback)) ?? true
        soundEffects = (try? c.decode(Bool.self, forKey: .soundEffects)) ?? true
        showMenuBarIcon = (try? c.decode(Bool.self, forKey: .showMenuBarIcon)) ?? true
        showMusicControl = (try? c.decode(Bool.self, forKey: .showMusicControl)) ?? true
        mouseTrigger = (try? c.decode(MouseTrigger.self, forKey: .mouseTrigger)) ?? .none
        hasCompletedOnboarding = (try? c.decode(Bool.self, forKey: .hasCompletedOnboarding)) ?? false
    }

    init() {}
}

// MARK: - Icon Cache

final class IconCache {
    static let shared = IconCache()
    private var cache: [String: NSImage] = [:]
    private var nameCache: [String: String] = [:]

    private func cacheKey(for app: AppItem) -> String {
        app.itemType == .fileOrFolder ? app.path : app.bundleIdentifier
    }

    func icon(for app: AppItem) -> NSImage {
        let key = cacheKey(for: app)
        if let img = cache[key] { return img }
        let img = app.loadIcon()
        cache[key] = img
        return img
    }

    func displayName(for app: AppItem) -> String {
        let key = cacheKey(for: app)
        if let name = nameCache[key] { return name }
        let name = app.resolveDisplayName()
        nameCache[key] = name
        return name
    }

    func invalidate() {
        cache.removeAll()
        nameCache.removeAll()
    }
}

// MARK: - App State

class AppState: ObservableObject {
    static let maxSlots = 12

    @Published var settings: AppSettings {
        didSet { saveSettings() }
    }
    @Published var selectedIndex: Int? = nil
    @Published var selectedRecentAppIndex: Int? = nil
    @Published private(set) var recentAppSnapshot: [AppItem] = []
    @Published var isMenuVisible: Bool = false
    let nowPlaying = NowPlayingService()
    private var workspaceActivationObserver: NSObjectProtocol?

    private let settingsURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Arcly")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("settings.json")
        let legacyDir = appSupport.appendingPathComponent("Pie" + "Menu")
        let legacyURL = legacyDir.appendingPathComponent("settings.json")
        if !FileManager.default.fileExists(atPath: url.path),
           FileManager.default.fileExists(atPath: legacyURL.path) {
            try? FileManager.default.copyItem(at: legacyURL, to: url)
        }
        return url
    }()

    init() {
        if let data = try? Data(contentsOf: settingsURL),
           var decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            // 迁移：修复旧版保存的无效快捷键（⌥Space）
            if decoded.hotkey.keyCode == 49 && decoded.hotkey.modifiers == .option {
                decoded.hotkey = HotkeyConfig() // 重置为默认 ⌘·
            }
            // 迁移：如果用户仍使用旧默认 ⌘⇧D，切换到新的默认 ⌘·。
            if decoded.hotkey.keyCode == 2 && decoded.hotkey.modifiers == [.command, .shift] {
                decoded.hotkey = HotkeyConfig() // 重置为默认 ⌘·
            }
            self.settings = decoded
        } else {
            self.settings = AppSettings()
            // Add some default apps
            self.settings.apps = Self.defaultApps()
        }

        workspaceActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.recordActivatedApplication(from: notification)
        }
    }

    deinit {
        if let workspaceActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceActivationObserver)
        }
    }

    func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            try? data.write(to: settingsURL)
        }
    }

    func snapshotRecentApps() {
        let eligible = eligibleRecentApps(settings.recentApps)
        if eligible != settings.recentApps {
            settings.recentApps = eligible
        }
        recentAppSnapshot = Array(eligible.prefix(settings.recentAppCount))
        selectedRecentAppIndex = nil
    }

    private func recordActivatedApplication(from notification: Notification) {
        guard let runningApplication = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication,
              let bundleIdentifier = runningApplication.bundleIdentifier,
              let bundleURL = runningApplication.bundleURL,
              shouldTrackRecentApplication(bundleIdentifier: bundleIdentifier) else {
            return
        }

        let name = runningApplication.localizedName
            ?? FileManager.default.displayName(atPath: bundleURL.path)
                .replacingOccurrences(of: ".app", with: "")
        let recent = AppItem(
            name: name,
            bundleIdentifier: bundleIdentifier,
            path: bundleURL.path
        )
        var updated = settings.recentApps.filter { $0.bundleIdentifier != bundleIdentifier }
        updated.insert(recent, at: 0)
        settings.recentApps = Array(eligibleRecentApps(updated).prefix(10))
    }

    private func shouldTrackRecentApplication(bundleIdentifier: String) -> Bool {
        let ownBundleIdentifier = Bundle.main.bundleIdentifier ?? "com.qingshan.orbis"
        guard bundleIdentifier != ownBundleIdentifier else { return false }
        return !settings.apps.contains {
            $0.itemType == .app && $0.bundleIdentifier == bundleIdentifier
        }
    }

    private func eligibleRecentApps(_ apps: [AppItem]) -> [AppItem] {
        let ownBundleIdentifier = Bundle.main.bundleIdentifier ?? "com.qingshan.orbis"
        let fixedBundleIdentifiers = Set(settings.apps.compactMap { item in
            item.itemType == .app && !item.bundleIdentifier.isEmpty ? item.bundleIdentifier : nil
        })
        var seen = Set<String>()
        return apps.filter { item in
            guard item.itemType == .app,
                  !item.bundleIdentifier.isEmpty,
                  item.bundleIdentifier != ownBundleIdentifier,
                  !fixedBundleIdentifiers.contains(item.bundleIdentifier),
                  !seen.contains(item.bundleIdentifier) else {
                return false
            }
            seen.insert(item.bundleIdentifier)
            return true
        }
    }

    static func defaultApps() -> [AppItem] {
        let defaultBundleIDs = [
            "com.apple.finder",
            "com.apple.Safari",
            "com.apple.MobileSMS",
            "com.apple.mail",
            "com.apple.iCal",
            "com.apple.Notes",
            "com.apple.Music",
            "com.apple.systempreferences",
        ]

        return defaultBundleIDs.compactMap { bundleID in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
            let localizedName = FileManager.default.displayName(atPath: url.path)
                .replacingOccurrences(of: ".app", with: "")
            return AppItem(name: localizedName, bundleIdentifier: bundleID, path: url.path)
        }
    }

    // 获取已安装的用户可见应用
    static func installedApps() -> [AppItem] {
        var apps: [AppItem] = []
        let searchPaths = [
            "/Applications",
            "/System/Applications",
            "/System/Library/CoreServices",
        ]

        // 过滤掉后台服务和系统工具（关键字匹配）
        let hiddenKeywords = [
            "Agent", "Stub", "Diagnostics", "Utility",
            "Helper", "Daemon", "Installer", "Migration",
            "Setup", "Updater", "Reporter", "PrefPane",
            "UIAgent", "Service", "ScreenSaver",
            "WidgetKit", "Widget", "WindowManager",
            "Education", "ShowDesktop",
            "VoiceOver", "Wallpaper",
            "CoreLocationAgent", "CoreServicesUIAgent",
            "PrintCenter", "HelpViewer", "FileMerge",
            "CrashReporter", "Problem", "Feedback",
            "AXVisualSupportAgent", "LocationMenu",
            "UniversalControl", "WiFiAgent",
            "Bluetooth", "CoreServices",
            "SpeakableItems", "AssistiveControl",
        ]

        // 精确匹配要隐藏的 bundle ID
        let hiddenBundleIDs: Set<String> = [
            "com.apple.VoiceOverUtility",
            "com.apple.SystemProfiler",
            "com.apple.ScreenSharing",
            "com.apple.DirectoryUtility",
            "com.apple.NetworkUtility",
            "com.apple.AVB-Audio-Configuration",
            "com.apple.MIDI-Configuration",
            "com.apple.wifi.diagnostics",
            "com.apple.BluetoothFileExchange",
            "com.apple.PacketLogger",
            "com.apple.FileSyncAgent",
            "com.apple.Ticket-Viewer",
            "com.apple.SystemUIServer",
            "com.apple.loginwindow",
            "com.apple.notificationcenterui",
            "com.apple.controlcenter",
            "com.apple.dock",
            "com.apple.inputmethod.ChinaHandwriting",
            "com.apple.WatchFaceAlbums",
        ]

        // 精确匹配要隐藏的 app 名称
        let hiddenNames: Set<String> = [
            "VoiceOver",
            "Wallpaper",
            "Watch Face Help",
            "WindowManager",
            "WindowManagerShowDesktopEducation",
            "WidgetKit Simulator",
            "CoreLocationAgent",
            "HelpViewer",
            "CoreServicesUIAgent",
            "FileMerge",
            "Print Center",
        ]

        for searchPath in searchPaths {
            let url = URL(fileURLWithPath: searchPath)
            if let contents = try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) {
                for fileURL in contents where fileURL.pathExtension == "app" {
                    if let bundle = Bundle(url: fileURL),
                       let bundleID = bundle.bundleIdentifier {
                        let rawName = FileManager.default.displayName(atPath: fileURL.path)
                            .replacingOccurrences(of: ".app", with: "")

                        // 精确名称匹配跳过
                        if hiddenNames.contains(rawName) { continue }

                        // bundle ID 匹配跳过
                        if hiddenBundleIDs.contains(bundleID) { continue }

                        // 关键字匹配跳过后台服务
                        let shouldHide = hiddenKeywords.contains { rawName.contains($0) }
                        if shouldHide { continue }

                        apps.append(AppItem(
                            name: rawName,
                            bundleIdentifier: bundleID,
                            path: fileURL.path
                        ))
                    }
                }
            }
        }

        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
