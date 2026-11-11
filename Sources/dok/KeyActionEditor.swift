import SwiftUI
import AppKit
import ApplicationServices
import ServiceManagement
import UniformTypeIdentifiers

// 设置 → 轮盘 → 按键动作：名称输入、组合键录制和编辑表单。

// MARK: - 按键动作编辑

/// Own the NSTextInputClient instead of borrowing a sheet's shared field editor.
final class KeyActionNameTextView: NSTextView {
    var attached: ((KeyActionNameTextView) -> Void)?
    var placeholder = Loc.string("keyAction.name")
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// A sheet can own firstResponder while its app has no key window. In that
    /// state AppKit accepts text events but cannot display the caret or run IME.
    @discardableResult
    func activateForEditing() -> Bool {
        guard let window, window.isVisible else { return false }
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        guard NSApp.isActive, window.isKeyWindow, window.makeFirstResponder(self) else { return false }
        inputContext?.activate()
        needsDisplay = true
        return true
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { attached?(self) }
    }
    override func mouseDown(with event: NSEvent) {
        if let window, !NSApp.isActive {
            NotificationCenter.default.post(name: .settingsInputFocusRequested, object: window)
        }
        activateForEditing()
        super.mouseDown(with: event)
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty && !hasMarkedText() {
            (placeholder as NSString).draw(at: NSPoint(x: textContainerInset.width, y: textContainerInset.height),
                withAttributes: [.font: font ?? NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.placeholderTextColor])
        }
    }
}

struct KeyActionNameInput: NSViewRepresentable {
    @Binding var text: String
    var onSubmit: (() -> Void)? = nil

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.drawsBackground = false
        let view = KeyActionNameTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 24))
        view.isEditable = true
        view.isSelectable = true
        view.isRichText = false
        view.importsGraphics = false
        view.allowsUndo = true
        view.isFieldEditor = true
        view.font = .systemFont(ofSize: 13)
        view.textColor = .textColor
        view.insertionPointColor = .labelColor
        view.drawsBackground = false
        view.textContainerInset = NSSize(width: 8, height: 5)
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.maximumNumberOfLines = 1
        view.textContainer?.widthTracksTextView = false
        view.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: 28)
        view.isHorizontallyResizable = true
        view.isVerticallyResizable = false
        view.autoresizingMask = [.width]
        view.setAccessibilityLabel(Loc.string("keyAction.name"))
        view.delegate = context.coordinator
        view.attached = { [weak coordinator = context.coordinator] view in coordinator?.focusWhenReady(view) }
        scroll.documentView = view
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? KeyActionNameTextView, !view.hasMarkedText() else { return }
        if view.string != text {
            let selection = view.selectedRange()
            view.string = text
            let count = (text as NSString).length
            let location = min(selection.location, count)
            view.setSelectedRange(NSRange(location: location, length: min(selection.length, count - location)))
        }
        view.needsDisplay = true
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: KeyActionNameInput
        private var didRequestWindowActivation = false
        init(_ parent: KeyActionNameInput) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? KeyActionNameTextView else { return }
            view.needsDisplay = true
            // Do not publish an IME's provisional text back through SwiftUI.
            guard !view.hasMarkedText() else { return }
            parent.text = view.string
        }
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) { parent.onSubmit?(); return true }
            if commandSelector == #selector(NSResponder.insertTab(_:)) {
                textView.window?.selectNextKeyView(textView); return true
            }
            if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
                textView.window?.selectPreviousKeyView(textView); return true
            }
            return false
        }
        func focusWhenReady(_ view: KeyActionNameTextView, attempt: Int = 0) {
            DispatchQueue.main.asyncAfter(deadline: .now() + (attempt == 0 ? 0 : 0.1)) { [weak self, weak view] in
                guard let self, let view, let window = view.window, attempt < 20,
                      !KeyActionService.isRecording else { return }
                if window.isVisible {
                    if !self.didRequestWindowActivation {
                        self.didRequestWindowActivation = true
                        NotificationCenter.default.post(name: .settingsInputFocusRequested, object: window)
                    }
                    window.initialFirstResponder = view
                    if view.activateForEditing() { return }
                }
                self.focusWhenReady(view, attempt: attempt + 1)
            }
        }
    }
}

/// 透明的原生录入控件铺在键帽区上：它负责焦点、事件拦截与生命周期，外观全由 SwiftUI 绘制。
struct KeyActionRecorderInput: NSViewRepresentable {
    @Binding var value: HotkeyConfig?
    @Binding var recording: Bool
    @Binding var status: String?
    func makeNSView(context: Context) -> KeyActionRecorderControl {
        let control = KeyActionRecorderControl(frame: .zero)
        control.drawsChrome = false
        return control
    }
    func updateNSView(_ control: KeyActionRecorderControl, context: Context) {
        control.value = value
        control.onChange = { value = $0 }
        control.onRecordingChanged = { recording = $0 }
        control.onStatusChanged = { status = $0 }
    }
    static func dismantleNSView(_ control: KeyActionRecorderControl, coordinator: ()) {
        control.onRecordingChanged = nil
        control.onStatusChanged = nil
        control.onChange = nil
        control.stop(reason: "editor-dismissed")
    }
}

struct KeyActionEditor: View {
    @ObservedObject var appState: AppState
    var item: AppItem
    var canAdd: Bool = true
    var onSave: (AppItem) -> Void
    @State private var name = ""
    @State private var combo: HotkeyConfig?
    @State private var recording = false
    @State private var recorderStatus: String?
    @State private var targetBundle = ""
    @State private var targetName = ""
    @State private var targetMenuAnchor = MenuAnchorHolder()
    @State private var breathing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var conflict: Bool { combo == appState.settings.hotkey }
    private var canSave: Bool { canAdd && !recording && combo != nil && !conflict }
    private var isEditing: Bool { item.keyCombination != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            comboStage

            VStack(spacing: 0) {
                SettingRow(title: Loc.string("keyAction.nameLabel"), accessoryWidth: 150) {
                    KeyActionNameInput(text: $name, onSubmit: save)
                        .frame(height: 26)
                        .settingsInsetSurface()
                }

                SettingDivider()

                SettingRow(title: Loc.string("keyAction.target"), accessoryWidth: 150) {
                    targetButton
                }

                if !AXIsProcessTrusted() {
                    SettingDivider()
                    HStack(spacing: 8) {
                        Text(Loc.string("keyAction.permission"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Button(Loc.string("keyAction.openAccessibilityShort")) {
                            KeyActionService.openAccessibility()
                        }
                        .buttonStyle(SettingsPillButtonStyle())
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: SettingsDesign.rowHeight)
                }
            }
            .settingsInsetSurface()

            Text(Loc.string("keyAction.footnote"))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)

            HStack {
                Spacer(minLength: 0)
                Button(Loc.string(isEditing ? "link.save" : "link.add"), action: save)
                    .buttonStyle(SettingsPillButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onAppear {
            name = item.name
            combo = item.keyCombination
            targetBundle = item.bundleIdentifier
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: targetBundle) {
                targetName = Self.displayName(of: url)
            } else { targetName = targetBundle }
        }
        .onChange(of: recording) { isRecording in
            if !isRecording { recorderStatus = nil }
            breathing = false
            if isRecording && !reduceMotion {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { breathing = true }
            }
        }
    }

    // MARK: 组合键

    /// 页面的主角：组合键以大号键帽显示；整块可点，点击开始录入，再点或按 Esc 取消。
    private var comboStage: some View {
        VStack(spacing: 10) {
            ZStack {
                if recording {
                    Text(recorderStatus ?? Loc.string("keyAction.recording"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                } else if let combo {
                    HStack(spacing: 6) {
                        ForEach(Array(Self.symbols(of: combo).enumerated()), id: \.offset) { _, symbol in
                            LargeKeyCap(text: symbol)
                        }
                    }
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
                } else {
                    Label(Loc.string("keyAction.recordPrompt"), systemImage: "keyboard")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 76)
            .settingsInsetSurface(emphasized: recording)
            .overlay(
                RoundedRectangle(cornerRadius: SettingsDesign.surfaceRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(stageBorderOpacity),
                                  style: StrokeStyle(lineWidth: 1, dash: combo == nil && !recording ? [4, 3] : []))
            )
            .overlay(
                KeyActionRecorderInput(value: $combo, recording: $recording, status: $recorderStatus)
            )
            .animation(reduceMotion ? nil : SettingsDesign.standardMotion, value: recording)
            .animation(reduceMotion ? nil : SettingsDesign.standardMotion, value: combo)

            Text(stageCaption)
                .font(.system(size: 11))
                .foregroundStyle(conflict ? .primary : .tertiary)
        }
    }

    private var stageBorderOpacity: Double {
        if recording { return breathing ? 0.45 : 0.15 }
        if conflict { return 0.5 }
        return combo == nil ? 0.18 : 0
    }

    private var stageCaption: String {
        if conflict { return Loc.string("keyAction.conflict") }
        if recording { return Loc.string("keyAction.recordingCaption") }
        return Loc.string(combo == nil ? "keyAction.recordCaption" : "keyAction.rerecordCaption")
    }

    static func symbols(of combo: HotkeyConfig) -> [String] { combo.keySymbols }

    // MARK: 目标应用

    private var targetButton: some View {
        Button(action: showTargetMenu) {
            HStack(spacing: 6) {
                if let icon = targetIcon {
                    Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                }
                Text(targetBundle.isEmpty ? Loc.string("keyAction.noSwitch") : targetName)
                    .font(.system(size: 12.5))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 9)
            .frame(height: 26)
            .settingsInsetSurface()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(MenuAnchor(holder: targetMenuAnchor))
    }

    private var targetIcon: NSImage? {
        guard !targetBundle.isEmpty,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: targetBundle) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    /// 不切换 / 正在运行的应用 / 选择其他应用…，用原生菜单，不再弹出访达。
    private func showTargetMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let none = ClosureMenuItem(title: Loc.string("keyAction.noSwitch"), symbol: "arrow.uturn.right", enabled: true) {
            targetBundle = ""
            targetName = ""
        }
        none.state = targetBundle.isEmpty ? .on : .off
        menu.addItem(none)

        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil
                && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .sorted { ($0.localizedName ?? "").localizedStandardCompare($1.localizedName ?? "") == .orderedAscending }
        if !running.isEmpty {
            menu.addItem(.separator())
            let header = NSMenuItem(title: Loc.string("keyAction.runningApps"), action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for app in running {
                guard let bundle = app.bundleIdentifier else { continue }
                let name = app.localizedName ?? bundle
                let entry = ClosureMenuItem(title: name, symbol: "app", enabled: true) {
                    targetBundle = bundle
                    targetName = name
                }
                if let icon = app.icon?.copy() as? NSImage {
                    icon.size = NSSize(width: 16, height: 16)
                    entry.image = icon
                }
                entry.state = bundle == targetBundle ? .on : .off
                menu.addItem(entry)
            }
        }

        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem(title: Loc.string("keyAction.chooseOther"), symbol: "folder", enabled: true) {
            DispatchQueue.main.async(execute: chooseTarget)
        })
        targetMenuAnchor.popUp(menu)
    }

    private func chooseTarget() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url,
           let bundle = Bundle(url: url)?.bundleIdentifier,
           bundle != Bundle.main.bundleIdentifier {
            targetBundle = bundle
            targetName = Self.displayName(of: url)
        }
    }

    private static func displayName(of url: URL) -> String {
        let name = FileManager.default.displayName(atPath: url.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    // MARK: 保存

    /// 名称选填：留空时用“目标应用 + 组合键”命名，没有目标应用就只用组合键。
    private func save() {
        guard canSave, let combo else { return }
        var result = item
        let typed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        result.name = typed.isEmpty
            ? (targetBundle.isEmpty ? combo.displayString : "\(targetName) \(combo.displayString)")
            : typed
        result.keyCombination = combo
        result.bundleIdentifier = targetBundle
        result.path = ""
        onSave(result)
    }
}

/// 组合键展示用的大号键帽：单色浅底、细描边，底边略深模拟键帽厚度。
struct LargeKeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 17, weight: .medium, design: .rounded))
            .frame(minWidth: 36, minHeight: 36)
            .padding(.horizontal, 6)
            .background(SettingsDesign.emphasizedSurface,
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
            )
            .overlay(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 3)
                    .padding(.horizontal, 2)
            }
    }
}
