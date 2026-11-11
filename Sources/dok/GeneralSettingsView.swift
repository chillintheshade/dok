import SwiftUI
import AppKit
import ApplicationServices
import ServiceManagement
import UniformTypeIdentifiers

// 设置 → 通用：快捷键、唤出方式、外观、常驻、系统。

struct GeneralSettingsView: View {
    @EnvironmentObject var appState: AppState
    /// 创建视图时就读取真实状态：若出现后再赋值，开关会播一次切换动画，还会多触发一次注册。
    @State private var launchAtLogin = Self.isLaunchAtLoginEnabled()

    var body: some View {
        HStack(alignment: .top, spacing: SettingsDesign.sectionSpacing) {
            VStack(spacing: SettingsDesign.sectionSpacing) {
                triggerGroup
                playbackGroup
                feedbackGroup
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: SettingsDesign.sectionSpacing) {
                wheelGroup
                systemGroup
            }
            .frame(maxWidth: .infinity)
        }
        .frame(width: SettingsDesign.generalContentWidth)
        .toggleStyle(SmoothSettingsSwitch())
        .padding(SettingsDesign.contentInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var triggerGroup: some View {
        SettingsGroup(title: Loc.string("settings.group.trigger")) {
            HotkeyRecorderRow(appState: appState)
                .frame(height: SettingsDesign.rowHeight)

            SettingDivider()

            SettingRow(title: Loc.string("settings.mouse")) {
                Picker("", selection: $appState.settings.mouseTrigger) {
                    ForEach(MouseTrigger.allCases, id: \.self) { trigger in
                        Text(trigger.displayName).tag(trigger)
                    }
                }
                .labelsHidden()
                .onChange(of: appState.settings.mouseTrigger) { _ in
                    NotificationCenter.default.post(name: .mouseTriggerChanged, object: nil)
                }
            }

            // 鼠标触发依赖辅助功能权限，未授权时静默失效，这里显式提示。
            if appState.settings.mouseTrigger != .none {
                SettingDivider()
                AccessibilityPermissionRow()
            }

            SettingDivider()

            SettingRow(title: Loc.string("settings.mode")) {
                SmoothSegmentedControl(
                    selection: $appState.settings.interactionMode,
                    options: [(InteractionMode.click, Loc.string("mode.click")), (.hold, Loc.string("mode.hold"))],
                    label: Loc.string("settings.mode")
                )
            }
        }
    }

    private var playbackGroup: some View {
        SettingsGroup(title: Loc.string("settings.group.playback")) {
            toggleCell(title: Loc.string("settings.nowPlaying"), isOn: $appState.settings.showMusicControl)
        }
        .frame(maxWidth: .infinity)
    }

    private var feedbackGroup: some View {
        SettingsGroup(title: Loc.string("settings.group.feedback")) {
            toggleCell(title: Loc.string("settings.haptics"), isOn: $appState.settings.hapticFeedback)

            SettingDivider()

            toggleCell(title: Loc.string("settings.sound"), isOn: $appState.settings.soundEffects)
        }
        .frame(maxWidth: .infinity)
    }

    private var wheelGroup: some View {
        SettingsGroup(title: Loc.string("settings.group.wheel")) {
            SettingRow(title: Loc.string("pinned.title")) {
                SmoothSegmentedControl(
                    selection: $appState.settings.pinnedMode,
                    options: [(PinnedMode.off, Loc.string("pinned.off")), (.desktop, Loc.string("pinned.desktop")), (.floating, Loc.string("pinned.floating"))],
                    label: Loc.string("pinned.title")
                )
                .onChange(of: appState.settings.pinnedMode) { _ in
                    NotificationCenter.default.post(name: .pinnedModeChanged, object: nil)
                }
            }

            SettingDivider()

            SettingRow(title: Loc.string("settings.position")) {
                SmoothSegmentedControl(
                    selection: $appState.settings.menuPosition,
                    options: [(MenuPosition.followMouse, Loc.string("position.mouse")), (.screenCenter, Loc.string("position.center"))],
                    label: Loc.string("settings.position")
                )
            }

            SettingDivider()

            SettingRow(title: Loc.string("settings.theme")) {
                SmoothSegmentedControl(
                    selection: $appState.settings.appearanceMode,
                    options: [(AppearanceMode.system, Loc.string("theme.system")), (.light, Loc.string("theme.light")), (.dark, Loc.string("theme.dark"))],
                    label: Loc.string("settings.theme")
                )
                .onChange(of: appState.settings.appearanceMode) { _ in
                    NotificationCenter.default.post(name: .appearanceChanged, object: nil)
                }
            }

            SettingDivider()

            compactSlider(
                title: Loc.string("settings.radius"),
                value: $appState.settings.menuRadius,
                range: 100...180,
                step: 5,
                defaultValue: AppSettings.defaultMenuRadius
            )

            SettingDivider()

            compactSlider(
                title: Loc.string("settings.icon"),
                value: $appState.settings.iconSize,
                range: 32...64,
                step: 2,
                defaultValue: AppSettings.defaultIconSize
            )

            // macOS 27 起玻璃由系统 Liquid Glass 决定，没有可调项，整行不显示。
            if #unavailable(macOS 27.0) {
                SettingDivider()

                compactSlider(
                    title: Loc.string("settings.opacity"),
                    value: $appState.settings.menuOpacity,
                    range: 0.15...1.0,
                    step: 0.05,
                    percentage: true,
                    defaultValue: AppSettings.defaultMenuOpacity
                )
            }
        }
    }

    private var systemGroup: some View {
        SettingsGroup(title: Loc.string("settings.group.system")) {
            SettingRow(title: Loc.string("settings.launchAtLogin")) {
                Toggle("", isOn: $launchAtLogin)
                    .labelsHidden()
                    .onChange(of: launchAtLogin) { newValue in
                        guard newValue != Self.isLaunchAtLoginEnabled() else { return }
                        setLaunchAtLogin(newValue)
                    }
            }

            SettingDivider()

            SettingRow(title: Loc.string("settings.menuBar")) {
                Toggle("", isOn: $appState.settings.showMenuBarIcon)
                    .labelsHidden()
                    .onChange(of: appState.settings.showMenuBarIcon) { _ in
                        NotificationCenter.default.post(name: .menuBarIconChanged, object: nil)
                    }
            }

            SettingDivider()

            SettingRow(title: Loc.string("settings.notificationBadges")) {
                Toggle("", isOn: $appState.settings.showNotificationBadges)
                    .labelsHidden()
            }

            SettingDivider()

            SettingRow(title: Loc.string("settings.replayGuide")) {
                Button(Loc.string("settings.replayGuide.action")) {
                    NotificationCenter.default.post(name: .replayGuideRequested, object: nil)
                }
                .buttonStyle(SettingsPillButtonStyle())
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func toggleCell(
        title: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 6)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .controlSize(.small)
                .frame(width: SettingsDesign.controlWidth, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(height: SettingsDesign.rowHeight)
        .frame(maxWidth: .infinity)
    }

    private func compactSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        percentage: Bool = false,
        defaultValue: Double? = nil
    ) -> some View {
        SettingRow(title: title) {
            VStack(spacing: 2) {
                HStack {
                    Spacer(minLength: 0)
                    Text(percentage ? "\(Int(round(value.wrappedValue * 100)))%" : "\(Int(value.wrappedValue))")
                        .font(.system(size: 11.5, weight: .regular).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }
                SmoothSettingsSlider(value: value, range: range, step: step, label: title,
                                     defaultValue: defaultValue)
            }
        }
        .help(defaultValue == nil ? "" : Loc.string("settings.slider.resetHint"))
    }

    static func isLaunchAtLoginEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("❌ 设置开机自启动失败: %@", error.localizedDescription)
                SMAppService.openSystemSettingsLoginItems()
            }
        }
    }
}

// MARK: - 快捷键录制

struct HotkeyRecorderRow: View {
    @ObservedObject var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isRecording = false
    @State private var localMonitor: Any?
    @State private var globalMonitor: Any?

    var body: some View {
        Button {
            guard !isRecording else { return }
            withAnimation(reduceMotion ? nil : SettingsDesign.quickMotion) {
                startRecording()
            }
        } label: {
            HStack(spacing: 10) {
                Text(Loc.string("settings.hotkey"))
                    .font(.system(size: 13, weight: .medium))

                Spacer(minLength: 10)

                if isRecording {
                    Text(Loc.string("hotkey.recording"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                } else {
                    HStack(spacing: 8) {
                        Text(Loc.string("settings.changeHotkey"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)

                        HStack(spacing: 2) {
                            ForEach(modifierSymbols, id: \.self) { sym in
                                KeyCap(sym)
                            }
                            KeyCap(HotkeyConfig.keyCodeToString(appState.settings.hotkey.keyCode))
                        }
                    }
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRecording ? Loc.string("hotkey.recording") : Loc.string("settings.changeHotkey"))
        .animation(reduceMotion ? nil : SettingsDesign.standardMotion, value: isRecording)
        .onReceive(NotificationCenter.default.publisher(for: .hotkeyRecordingCancelled)) { _ in
            stopRecording()
        }
        .onDisappear {
            stopRecording()
        }
    }

    private var modifierSymbols: [String] {
        var result: [String] = []
        let mods = appState.settings.hotkey.modifiers
        if mods.contains(.control) { result.append("⌃") }
        if mods.contains(.option) { result.append("⌥") }
        if mods.contains(.shift) { result.append("⇧") }
        if mods.contains(.command) { result.append("⌘") }
        return result
    }

    private func startRecording() {
        stopRecording()
        NSApp.activate(ignoringOtherApps: true)
        isRecording = true

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            handleKeyEvent(event)
            return nil
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { event in
            handleKeyEvent(event)
        }
    }

    private func handleKeyEvent(_ event: NSEvent) {
        let mods = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .intersection([.command, .control, .option, .shift])

        if event.keyCode == 53 && mods.isEmpty {
            withAnimation(reduceMotion ? nil : SettingsDesign.quickMotion) {
                stopRecording()
            }
            return
        }

        guard mods.contains(.command) || mods.contains(.control) || mods.contains(.option) else {
            return
        }

        appState.settings.hotkey = HotkeyConfig(keyCode: event.keyCode, modifiers: mods)
        NotificationCenter.default.post(name: .hotkeyChanged, object: nil)

        withAnimation(reduceMotion ? nil : SettingsDesign.quickMotion) {
            stopRecording()
        }
    }

    private func stopRecording() {
        isRecording = false
        if let m = localMonitor {
            NSEvent.removeMonitor(m)
            localMonitor = nil
        }
        if let m = globalMonitor {
            NSEvent.removeMonitor(m)
            globalMonitor = nil
        }
    }
}
