import SwiftUI
import AppKit
import ApplicationServices
import ServiceManagement
import UniformTypeIdentifiers

// 设置窗口共用的控件和样式：设计常量、分段控件、开关、滑块、分组与行、按键帽、搜索框。

enum SettingsDesign {
    static let windowWidth: CGFloat = 920
    /// 窗口高度随当前页面内容变化；这是首次打开、尚未测得内容时的高度。
    static let initialWindowHeight: CGFloat = 520
    static let sidebarWidth: CGFloat = 216
    static let navigationRowHeight: CGFloat = 34
    static let rowHeight: CGFloat = 44
    static let controlWidth: CGFloat = 130
    static let generalContentWidth: CGFloat = 656
    static let dividerWidth: CGFloat = 0.5
    static let navigationRadius: CGFloat = 7
    static let surfaceRadius: CGFloat = 8
    static let contentInset: CGFloat = 24
    static let sectionSpacing: CGFloat = 16
    static let insetSurface = Color.primary.opacity(0.045)
    static let emphasizedSurface = Color.primary.opacity(0.065)
    static let hoverSurface = Color.primary.opacity(0.035)
    static let selectedSurface = Color.primary.opacity(0.055)
    static let hairline = Color(nsColor: .separatorColor).opacity(0.72)
    static let quietDivider = Color(nsColor: .separatorColor).opacity(0.44)
    static let quickMotion = Animation.easeOut(duration: 0.14)
    static let standardMotion = Animation.easeInOut(duration: 0.16)
    /// 页面切换与窗口伸缩共用的时长与曲线（与 DokApp.fitSettingsWindow 一致）。
    static let pageDuration: Double = 0.32
    static let pageMotion = Animation.timingCurve(0.32, 0.72, 0, 1, duration: pageDuration)

    static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(version) (\($0))" } ?? version
    }
}

/// 各页面内容的自然高度，窗口据此调整，页面底部不留空。按页面分开记录：
/// 切换时立即用新页面的高度伸缩窗口，不必等旧页面淡出。
struct SettingsContentHeightKey: PreferenceKey {
    static var defaultValue: [SettingsTab: CGFloat] = [:]
    static func reduce(value: inout [SettingsTab: CGFloat], nextValue: () -> [SettingsTab: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    func reportsContentHeight(for tab: SettingsTab) -> some View {
        background(GeometryReader { proxy in
            Color.clear.preference(key: SettingsContentHeightKey.self, value: [tab: proxy.size.height])
        })
    }
}

// One shared selection layer moves between segments instead of replacing fills.
struct SmoothSegmentedControl<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(Value, String)]
    let label: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.0) { value, title in
                Button {
                    selection = value
                } label: {
                    Text(title)
                        .font(.system(size: 12, weight: selection == value ? .semibold : .regular))
                        .foregroundStyle(selection == value
                            ? (colorScheme == .dark ? Color.black : Color.white)
                            : Color.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 20)
                        .contentShape(Rectangle())

                }
                .buttonStyle(.plain)
                .accessibilityLabel(title)
                .accessibilityAddTraits(selection == value ? .isSelected : [])
            }
        }
        .background {
            GeometryReader { geometry in
                let width = geometry.size.width / CGFloat(max(1, options.count))
                let index = options.firstIndex { $0.0 == selection } ?? 0
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.primary)
                    .frame(width: width)
                    .offset(x: CGFloat(index) * width)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: index)
            }
            .allowsHitTesting(false)
        }
        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

struct SmoothSettingsSwitch: ToggleStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            Capsule()
                .fill(configuration.isOn ? Color.primary : Color.primary.opacity(0.18))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(.white)
                        .padding(2)
                        .frame(width: 28)
                        .offset(x: configuration.isOn ? 16 : 0)
                }
                .frame(width: 44, height: 22)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: configuration.isOn)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .toggleStyle(.switch)
        }
    }
}

struct SmoothSettingsSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let label: String
    var defaultValue: Double? = nil
    @State private var dragging = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fraction: CGFloat { fraction(of: value) }

    private func fraction(of v: Double) -> CGFloat {
        CGFloat(min(1, max(0, (v - range.lowerBound) / (range.upperBound - range.lowerBound))))
    }

    private func snapped(_ raw: Double) -> Double {
        let stepped = range.lowerBound + ((raw - range.lowerBound) / step).rounded() * step
        return min(range.upperBound, max(range.lowerBound, stepped))
    }

    /// 拖动时就按档位跳，看到的值就是松手后的值；每跳一档轻震，落在默认值上换一种震感。
    private func move(to raw: Double) {
        let next = snapped(raw)
        guard next != value else { return }
        let pattern: NSHapticFeedbackManager.FeedbackPattern = next == defaultValue ? .alignment : .levelChange
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
        withAnimation(reduceMotion ? nil : .easeOut(duration: dragging ? 0.08 : 0.2)) { value = next }
    }

    var body: some View {
        GeometryReader { geometry in
            let travel = max(1, geometry.size.width - 10)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12)).frame(height: 4)
                Capsule().fill(Color.primary).frame(width: 5 + travel * fraction, height: 4)
                if let defaultValue {
                    // 默认位置的小刻度，压在滑轨下方，不和填充色抢。
                    Capsule()
                        .fill(Color.primary.opacity(0.32))
                        .frame(width: 1.5, height: 4)
                        .offset(x: 5 + travel * fraction(of: defaultValue) - 0.75, y: 7)
                }
                Capsule()
                    .fill(.white)
                    .frame(width: 10, height: 18)
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                    .offset(x: travel * fraction)
            }
            .frame(height: 20)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { gesture in
                    let target = range.lowerBound + Double(min(1, max(0, (gesture.location.x - 5) / travel))) * (range.upperBound - range.lowerBound)
                    move(to: target)
                    dragging = true
                }
                .onEnded { _ in
                    dragging = false
                })
            .simultaneousGesture(TapGesture(count: 2).onEnded {
                guard let defaultValue else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { value = defaultValue }
            })
        }
        .frame(height: 20)
        .focusable(true)
        .onMoveCommand { direction in
            let delta: Double
            switch direction {
            case .left, .down: delta = -step
            case .right, .up: delta = step
            default: return
            }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                value = min(range.upperBound, max(range.lowerBound, value + delta))
            }
        }
        .accessibilityRepresentation {
            Slider(value: $value, in: range, step: step) { Text(label) }
        }
    }
}

extension View {
    @ViewBuilder
    func settingsNavigationFocusEffect() -> some View {
        if #available(macOS 14.0, *) {
            self.focusEffectDisabled()
        } else {
            self
        }
    }

    func settingsInsetSurface(emphasized: Bool = false) -> some View {
        background(
            emphasized ? SettingsDesign.emphasizedSurface : SettingsDesign.insetSurface,
            in: RoundedRectangle(cornerRadius: SettingsDesign.surfaceRadius, style: .continuous)
        )
    }
}

struct SettingsRootGlassLayer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = 18
            glass.alphaValue = 1
            // The native glass owns its edge; avoid a second view-bounds crop.
            glass.clipsToBounds = false
            glass.layer?.masksToBounds = false
            return glass
        }

        let effect = NSVisualEffectView()
        effect.blendingMode = .behindWindow
        effect.material = .sidebar
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 18
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true
        return effect
    }

    func updateNSView(_ view: NSView, context: Context) {}
}

final class SettingsWindowDragHandleView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

struct SettingsWindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        SettingsWindowDragHandleView()
    }

    func updateNSView(_ view: NSView, context: Context) {}
}
// MARK: - 通用设置

struct SettingsGroup<Content: View>: View {
    @Environment(\.colorSchemeContrast) private var contrast
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .background(
                Color.primary.opacity(contrast == .increased ? 0.065 : 0.025),
                in: RoundedRectangle(cornerRadius: SettingsDesign.surfaceRadius, style: .continuous)
            )
        }
    }
}

// MARK: - 辅助功能权限提示

/// 鼠标按键触发依赖 CGEvent tap，需要辅助功能权限。
/// 未授权时不会报错，只是静默不工作，因此在设置里显式提示并提供跳转。
struct AccessibilityPermissionRow: View {
    @State private var isTrusted = AXIsProcessTrusted()

    private let pollTimer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if !isTrusted {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    Text(Loc.string("permission.accessibility.needed"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 8)

                    Button(Loc.string("permission.accessibility.open")) {
                        openAccessibilitySettings()
                    }
                    .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .frame(minHeight: SettingsDesign.rowHeight)
                .transition(.opacity)
            }
        }
        .onReceive(pollTimer) { _ in
            // 用户可能在 App 运行期间去系统设置授权，这里轮询让提示自动消失。
            let current = AXIsProcessTrusted()
            if current != isTrusted {
                withAnimation(.easeOut(duration: 0.2)) {
                    isTrusted = current
                }
            }
        }
    }

    private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}

struct SettingRow<Accessory: View>: View {
    let title: String
    var accessoryWidth: CGFloat = SettingsDesign.controlWidth
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)

            Spacer(minLength: 8)
            accessory
                .controlSize(.small)
                .frame(width: accessoryWidth, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(height: SettingsDesign.rowHeight)
    }
}

/// 设置页内的胶囊按钮：次要为浅底，主要为实心反色，与分段控件的选中态一致。
struct SettingsPillButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        PillLabel(configuration: configuration, prominent: prominent)
    }

    private struct PillLabel: View {
        let configuration: ButtonStyle.Configuration
        let prominent: Bool
        @Environment(\.colorScheme) private var colorScheme
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: 12, weight: prominent ? .semibold : .medium))
                .foregroundStyle(prominent ? (colorScheme == .dark ? Color.black : Color.white) : Color.primary)
                .padding(.horizontal, 12)
                .frame(height: 24)
                .background(prominent ? Color.primary : Color.primary.opacity(0.08), in: Capsule())
                .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
                .contentShape(Capsule())
        }
    }
}

/// 右侧面板的添加类型。文件与文件夹同一种添加方式，合为一类。
final class MenuAnchorHolder {
    weak var view: NSView?

    func popUp(_ menu: NSMenu) {
        guard let view else { return }
        let y = view.isFlipped ? view.bounds.height + 4 : -4
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: y), in: view)
    }
}

struct MenuAnchor: NSViewRepresentable {
    let holder: MenuAnchorHolder

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        holder.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        holder.view = view
    }
}

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, symbol: String, enabled: Bool, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        isEnabled = enabled
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func fire() { handler() }
}

struct SettingDivider: View {
    var body: some View {
        Rectangle()
            .fill(SettingsDesign.quietDivider)
            .frame(height: SettingsDesign.dividerWidth)
            .padding(.leading, 12)
    }
}
// MARK: - 按键帽组件

struct KeyCap: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .frame(minWidth: 24, minHeight: 22)
            .padding(.horizontal, 4)
            .dokKeyCapGlass()
    }
}

// MARK: - NSSearchField 包装

final class AppPickerSearchField: NSSearchField {
    var onAttachedToWindow: ((AppPickerSearchField) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        onAttachedToWindow?(self)
    }
}

struct SearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String

    func makeNSView(context: Context) -> NSSearchField {
        let field = AppPickerSearchField()
        field.isBezeled = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13)
        // 放大镜由 SwiftUI 画在框外侧；无边框时系统自带的放大镜会压在文字上。
        (field.cell as? NSSearchFieldCell)?.searchButtonCell = nil
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.isEditable = true
        field.isSelectable = true
        field.isEnabled = true
        field.sendsSearchStringImmediately = true
        field.onAttachedToWindow = { [weak coordinator = context.coordinator] field in
            coordinator?.focusWhenAttached(field)
        }
        return field
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if let editor = nsView.currentEditor() as? NSTextView, editor.hasMarkedText() {
            return
        }
        if nsView.stringValue != text { nsView.stringValue = text }
    }

    static func dismantleNSView(_ nsView: NSSearchField, coordinator: Coordinator) {
        coordinator.finishInitialFocus()
        (nsView as? AppPickerSearchField)?.onAttachedToWindow = nil
        nsView.delegate = nil
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: SearchField
        private var didApplyInitialFocus = false
        private var observers: [NSObjectProtocol] = []
        private weak var attachedField: AppPickerSearchField?

        init(_ parent: SearchField) { self.parent = parent }
        deinit { observers.forEach(NotificationCenter.default.removeObserver) }

        fileprivate func focusWhenAttached(_ field: AppPickerSearchField) {
            guard !didApplyInitialFocus, attachedField !== field,
                  let window = field.window else { return }
            attachedField = field
            window.initialFirstResponder = field
            // Wait for AppKit's sheet and app activation to finish. Never make
            // the window key or reactivate the app from an input control.
            for (name, object) in [
                (NSWindow.didBecomeKeyNotification, window as AnyObject),
                (NSApplication.didBecomeActiveNotification, NSApp as AnyObject)
            ] {
                observers.append(NotificationCenter.default.addObserver(
                    forName: name, object: object, queue: .main
                ) { [weak self] _ in self?.scheduleInitialFocus() })
            }
            scheduleInitialFocus()
        }

        private func scheduleInitialFocus() {
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.didApplyInitialFocus,
                      let field = self.attachedField, let window = field.window,
                      window.isVisible, window.isKeyWindow, NSApp.isActive else { return }
                if field.currentEditor() != nil {
                    self.finishInitialFocus()
                    return
                }
                if window.makeFirstResponder(field) { self.finishInitialFocus() }
            }
        }

        fileprivate func finishInitialFocus() {
            didApplyInitialFocus = true
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            // A user click or AppKit's initial responder already owns input.
            // Cancel pending work before the first IME composition begins.
            finishInitialFocus()
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSSearchField else { return }
            if let editor = field.currentEditor() as? NSTextView, editor.hasMarkedText() {
                return
            }
            parent.text = field.stringValue
        }
    }
}
