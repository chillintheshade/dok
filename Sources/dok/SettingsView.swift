import SwiftUI
import AppKit
import ApplicationServices
import ServiceManagement
import UniformTypeIdentifiers

private enum SettingsDesign {
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
private struct SettingsContentHeightKey: PreferenceKey {
    static var defaultValue: [SettingsTab: CGFloat] = [:]
    static func reduce(value: inout [SettingsTab: CGFloat], nextValue: () -> [SettingsTab: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}

private extension View {
    func reportsContentHeight(for tab: SettingsTab) -> some View {
        background(GeometryReader { proxy in
            Color.clear.preference(key: SettingsContentHeightKey.self, value: [tab: proxy.size.height])
        })
    }
}

// One shared selection layer moves between segments instead of replacing fills.
private struct SmoothSegmentedControl<Value: Hashable>: View {
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

private struct SmoothSettingsSwitch: ToggleStyle {
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

private struct SmoothSettingsSlider: View {
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

private extension View {
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

private struct SettingsRootGlassLayer: NSViewRepresentable {
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

private final class SettingsWindowDragHandleView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

private struct SettingsWindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        SettingsWindowDragHandleView()
    }

    func updateNSView(_ view: NSView, context: Context) {}
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case apps
    case general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apps: return Loc.string("settings.tab.wheel")
        case .general: return Loc.string("settings.tab.general")
        }
    }

    var symbol: String {
        switch self {
        case .apps: return "square.grid.3x3"
        case .general: return "gearshape"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedTab: SettingsTab
    @State private var hoveredTab: SettingsTab?
    @State private var contentHeights: [SettingsTab: CGFloat] = [:]
    @FocusState private var focusedTab: SettingsTab?
    @Namespace private var sidebarSelection
    let onSelectTab: (SettingsTab) -> Void
    let onContentHeight: (SettingsTab, CGFloat) -> Void

    init(
        selectedTab: SettingsTab,
        onSelectTab: @escaping (SettingsTab) -> Void = { _ in },
        onContentHeight: @escaping (SettingsTab, CGFloat) -> Void = { _, _ in }
    ) {
        _selectedTab = State(initialValue: selectedTab)
        self.onSelectTab = onSelectTab
        self.onContentHeight = onContentHeight
    }

    var body: some View {
        ZStack {
            SettingsRootGlassLayer()
                .ignoresSafeArea()
                .allowsHitTesting(false)

            HStack(spacing: 0) {
                settingsSidebar
                Rectangle()
                    .fill(SettingsDesign.hairline)
                    .frame(width: SettingsDesign.dividerWidth)
                    .accessibilityHidden(true)
                // 内容按自然高度顶对齐；测得的高度交给窗口，窗口随之伸缩。
                VStack(spacing: 0) {
                    ZStack(alignment: .top) {
                        settingsContent
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .onPreferenceChange(SettingsContentHeightKey.self) { heights in
                    contentHeights.merge(heights) { $1 }
                    if let height = heights[selectedTab] { onContentHeight(selectedTab, height) }
                }
            }

            // A narrow, explicit window-drag strip. It occupies only the empty
            // header band and cannot compete with wheel item reordering below.
            SettingsWindowDragHandle()
                .frame(height: 22)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .accessibilityHidden(true)
        }
        .tint(.primary)
        .frame(width: SettingsDesign.windowWidth)
        .frame(maxHeight: .infinity)
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsTab.allCases) { tab in
                Button {
                    selectTab(tab)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 14, weight: .regular))
                            .frame(width: 20)
                        Text(tab.title)
                            .font(.system(size: 13, weight: .medium))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: SettingsDesign.navigationRowHeight)
                    .contentShape(Rectangle())
                    .background {
                        ZStack {
                            RoundedRectangle(
                                cornerRadius: SettingsDesign.navigationRadius,
                                style: .continuous
                            )
                            .fill(SettingsDesign.hoverSurface)
                            .opacity(selectedTab != tab && (hoveredTab == tab || focusedTab == tab) ? 1 : 0)

                            if selectedTab == tab {
                                RoundedRectangle(
                                    cornerRadius: SettingsDesign.navigationRadius,
                                    style: .continuous
                                )
                                .fill(SettingsDesign.selectedSurface)
                                .matchedGeometryEffect(id: "sidebarSelection", in: sidebarSelection)
                            }
                        }
                        .allowsHitTesting(false)
                    }
                }
                .buttonStyle(.plain)
                .focusable(true)
                .focused($focusedTab, equals: tab)
                .settingsNavigationFocusEffect()
                .onHover { inside in
                    if inside { hoveredTab = tab }
                    else if hoveredTab == tab { hoveredTab = nil }
                }
                .animation(reduceMotion ? nil : SettingsDesign.quickMotion, value: hoveredTab == tab)
                .animation(reduceMotion ? nil : SettingsDesign.quickMotion, value: focusedTab == tab)
                .onMoveCommand { direction in
                    guard focusedTab == tab,
                          let index = SettingsTab.allCases.firstIndex(of: tab) else { return }
                    let offset: Int
                    switch direction {
                    case .up: offset = -1
                    case .down: offset = 1
                    default: return
                    }
                    let next = index + offset
                    guard SettingsTab.allCases.indices.contains(next) else { return }
                    let destination = SettingsTab.allCases[next]
                    focusedTab = destination
                    selectTab(destination)
                }
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
            Spacer(minLength: 0)
            Text("Dok \(SettingsDesign.versionText)")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
                .padding(.horizontal, 10)
        }
        .padding(.horizontal, 12)
        .padding(.top, 24)
        .padding(.bottom, 16)
        .frame(width: SettingsDesign.sidebarWidth)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private func selectTab(_ tab: SettingsTab) {
        guard selectedTab != tab else { return }
        NotificationCenter.default.post(name: .hotkeyRecordingCancelled, object: nil)
        // 已知新页面高度时，窗口与内容淡入淡出同时开始。
        if let height = contentHeights[tab] { onContentHeight(tab, height) }
        if reduceMotion {
            selectedTab = tab
        } else {
            withAnimation(SettingsDesign.pageMotion) { selectedTab = tab }
        }
        onSelectTab(tab)
    }

    @ViewBuilder
    private var settingsContent: some View {
        switch selectedTab {
        case .apps:
            AppsSettingsView()
                .environmentObject(appState)
                .reportsContentHeight(for: .apps)
                .transition(.opacity)
        case .general:
            GeneralSettingsView()
                .environmentObject(appState)
                .reportsContentHeight(for: .general)
                .transition(.opacity)
        }
    }
}

// MARK: - 应用设置

struct AppsSettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var panel: ItemPanelMode?
    @State private var addKind: AddKind = .app
    /// 添加成功后换新 id，表单回到空白，可以接着添加下一个。
    @State private var formID = UUID()
    @State private var selectedIndex: Int? = nil
    @State private var draggingIndex: Int? = nil
    @State private var dragTranslation: CGSize = .zero
    @State private var dragTargetIndex: Int? = nil
    @State private var isInDeleteZone: Bool = false
    @State private var removedItems: [RemovedWheelItem] = []
    @State private var confirmingRestore = false
    @State private var restoreHovered = false
    @State private var restoreCollapseToken = UUID()
    @Namespace private var wheelItemAnimation

    /// 原地确认无操作这么久后自动收起，等于取消。
    private static let restoreConfirmTimeout: TimeInterval = 4

    private struct RemovedWheelItem {
        let item: AppItem
        let index: Int
    }

    private var editAnimation: Animation? {
        reduceMotion ? nil : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.32)
    }

    private let pieSize: CGFloat = 436
    private var previewMenuRadius: CGFloat { appState.settings.menuRadius }
    private var previewOuterDiameter: CGFloat { (previewMenuRadius + 50) * 2 }
    /// 预览（轮盘 + 下方卫星）整体高度正好填满 pieSize，不在四周留死角。
    private var previewAvailableHeight: CGFloat { pieSize - 8 }
    private var baseScale: CGFloat {
        min(previewAvailableHeight / previewOuterDiameter, 1.12)
    }
    private var previewRecentApps: [AppItem] {
        appState.recentContentForSettingsPreview()
    }
    private var satelliteFitScale: CGFloat {
        let fixedSatelliteSpacing = RecentAppSatelliteGeometry.edgeGap
            + RecentAppSatelliteGeometry.glassPadding * 2
        let scalableExtent = previewOuterDiameter
            + appState.settings.iconSize * RecentAppSatelliteGeometry.iconScale
        return (previewAvailableHeight - fixedSatelliteSpacing) / scalableExtent
    }
    private var scale: CGFloat {
        previewRecentApps.isEmpty ? baseScale : min(baseScale, satelliteFitScale)
    }
    private var iconOrbitRadius: CGFloat { previewMenuRadius * scale }
    private var ringThickness: CGFloat { 100 * scale }
    private var outerRadius: CGFloat { iconOrbitRadius + ringThickness / 2 }
    private var innerRadius: CGFloat { iconOrbitRadius - ringThickness / 2 }
    private var center: CGFloat { pieSize / 2 }
    private var wheelDiameter: CGFloat { outerRadius * 2 }
    private var iconSize: CGFloat { appState.settings.iconSize * scale }
    private var recentPreviewYOffset: CGFloat {
        guard !previewRecentApps.isEmpty else { return 0 }
        let satelliteDiameter = RecentAppSatelliteGeometry.baseDiameter(for: iconSize)
        return -(RecentAppSatelliteGeometry.edgeGap + satelliteDiameter) / 2
    }
    private var glassMaterialIntensity: Double {
        DokGlassMaterial.intensity(for: appState.settings.menuOpacity)
    }

    var body: some View {
        HStack(alignment: .top, spacing: SettingsDesign.contentInset) {
            appsPreviewPane
            appsControlPane
        }
        .padding(SettingsDesign.contentInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - 右侧面板：添加与编辑共用

    private var isFull: Bool { appState.settings.apps.count >= maxSlots }

    private func openPanel(_ mode: ItemPanelMode) {
        formID = UUID()
        withAnimation(reduceMotion ? nil : SettingsDesign.standardMotion) { panel = mode }
    }

    private func closePanel() {
        withAnimation(reduceMotion ? nil : SettingsDesign.standardMotion) { panel = nil }
    }

    /// 只有网址和按键动作有可编辑的内容；其他类型右键里是替换。
    private func openEditor(for item: AppItem) {
        guard item.itemType == .webLink || item.itemType == .keyAction else { return }
        openPanel(.edit(item.id))
    }

    private func append(_ item: AppItem) {
        guard !isFull else { return }
        withAnimation(reduceMotion ? nil : SettingsDesign.standardMotion) {
            removedItems.removeAll()
            appState.settings.apps.append(item)
        }
    }

    private func itemPanel(_ mode: ItemPanelMode) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(panelTitle(mode))
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 0)
                Button(Loc.string("panel.done"), action: closePanel)
                    .buttonStyle(SettingsPillButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
            .frame(height: 24)

            if mode == .add {
                SmoothSegmentedControl(
                    selection: $addKind,
                    options: AddKind.allCases.map { ($0, Loc.string("add.kind.\($0.rawValue)")) },
                    label: Loc.string("settings.add")
                )
                if isFull {
                    Text(Loc.string("panel.full"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            panelContent(mode)
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .onChange(of: addKind) { _ in formID = UUID() }
    }

    private func panelTitle(_ mode: ItemPanelMode) -> String {
        guard case .edit(let id) = mode,
              let item = appState.settings.apps.first(where: { $0.id == id }) else {
            return Loc.string("settings.add")
        }
        return Loc.string(item.itemType == .webLink ? "link.edit.title" : "keyAction.editTitle")
    }

    @ViewBuilder
    private func panelContent(_ mode: ItemPanelMode) -> some View {
        switch mode {
        case .add:
            switch addKind {
            case .app:
                AppListPanel(appState: appState, canAdd: !isFull) { append($0) }
            case .file:
                FileDropPanel(canAdd: !isFull, onAdd: addFiles, onChoose: chooseFiles)
            case .link:
                LinkForm(existing: nil, canAdd: !isFull) { address, name in
                    saveWebLink(address: address, name: name, existing: nil)
                }
                .id(formID)
            case .keyAction:
                KeyActionEditor(
                    appState: appState,
                    item: AppItem(name: "", bundleIdentifier: "", path: "", itemType: .keyAction),
                    canAdd: !isFull,
                    onSave: saveKeyAction
                )
                .id(formID)
            }
        case .edit(let id):
            if let item = appState.settings.apps.first(where: { $0.id == id }) {
                if item.itemType == .webLink {
                    LinkForm(existing: item) { address, name in
                        saveWebLink(address: address, name: name, existing: item)
                    }
                    .id(item.id)
                } else {
                    KeyActionEditor(appState: appState, item: item, onSave: saveKeyAction)
                        .id(item.id)
                }
            } else {
                // 正在编辑的项目被移除了，面板随之收起。
                Color.clear.onAppear(perform: closePanel)
            }
        }
    }

    /// 编辑后收起面板；新建后表单清空，留在面板里可继续添加。
    private func saveKeyAction(_ result: AppItem) {
        IconCache.shared.invalidate()
        if let index = appState.settings.apps.firstIndex(where: { $0.id == result.id }) {
            appState.settings.apps[index] = result
            closePanel()
        } else {
            append(result)
            formID = UUID()
        }
    }

    private func addFiles(_ urls: [URL]) {
        for url in urls { append(fileSystemItem(for: url)) }
        IconCache.shared.invalidate()
    }

    private func chooseFiles() {
        guard !isFull else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.resolvesAliases = true
        panel.prompt = Loc.string("openPanel.add")
        panel.message = Loc.string("openPanel.message")
        guard panel.runModal() == .OK else { return }
        addFiles(Array(panel.urls.prefix(maxSlots - appState.settings.apps.count)))
    }

    // MARK: - 底部按钮

    private let maxSlots = AppState.maxSlots

    private func fileSystemItem(for url: URL) -> AppItem {
        let bookmarkData = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        return AppItem(
            name: url.lastPathComponent,
            bundleIdentifier: "",
            path: url.path,
            itemType: .fileOrFolder,
            bookmarkData: bookmarkData,
            customIconData: AppItem.persistentCustomIconData(for: url)
        )
    }

    /// 网址无效时返回 false，面板保持并提示。编辑后收起面板；新建后表单清空可继续添加。
    private func saveWebLink(address: String, name: String, existing: AppItem?) -> Bool {
        guard let url = AppItem.normalizedWebURL(from: address) else { return false }

        let customName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var item = AppItem(
            name: customName.isEmpty ? (url.host ?? url.absoluteString) : customName,
            bundleIdentifier: "",
            path: url.absoluteString,
            itemType: .webLink
        )
        if let existing {
            item.id = existing.id
            if existing.path == item.path { item.customIconData = existing.customIconData }
        }
        IconCache.shared.invalidate()
        withAnimation(reduceMotion ? nil : SettingsDesign.standardMotion) {
            if let index = appState.settings.apps.firstIndex(where: { $0.id == item.id }) {
                appState.settings.apps[index] = item
            } else if existing == nil, !isFull {
                removedItems.removeAll()
                appState.settings.apps.append(item)
            }
        }
        if item.customIconData == nil { appState.refreshWebsiteIcon(for: item) }
        if existing == nil { formID = UUID() } else { closePanel() }
        return true
    }

    // MARK: - 恢复默认：原地两步确认

    private func beginRestoreConfirmation() {
        withAnimation(reduceMotion ? nil : SettingsDesign.standardMotion) {
            confirmingRestore = true
        }
        scheduleRestoreCollapse()
    }

    /// 4 秒无操作自动收起（不执行）。指针停在确认区时不收，移开后重新计时。
    private func scheduleRestoreCollapse() {
        let token = UUID()
        restoreCollapseToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.restoreConfirmTimeout) {
            guard restoreCollapseToken == token, confirmingRestore, !restoreHovered else { return }
            cancelRestoreConfirmation()
        }
    }

    private func cancelRestoreConfirmation() {
        restoreCollapseToken = UUID()
        withAnimation(reduceMotion ? nil : SettingsDesign.standardMotion) {
            confirmingRestore = false
        }
    }

    private func restoreDefaults() {
        restoreCollapseToken = UUID()
        withAnimation(reduceMotion ? nil : SettingsDesign.standardMotion) {
            confirmingRestore = false
            selectedIndex = nil
            removedItems.removeAll()
            appState.settings.apps = Array(AppState.defaultApps().prefix(maxSlots))
        }
    }

    // MARK: - 预览图标右键

    private func removeItem(at index: Int) {
        guard index < appState.settings.apps.count else { return }
        withAnimation(editAnimation) {
            selectedIndex = nil
            removedItems.append(RemovedWheelItem(item: appState.settings.apps[index], index: index))
            appState.settings.apps.remove(at: index)
        }
    }

    private func revealInFinder(_ item: AppItem) {
        let url = item.itemType == .app ? URL(fileURLWithPath: item.path) : item.resolvedFileURL()
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// 用新选的应用或文件替换原位置的项目，位置不变。
    private func replaceItem(at index: Int) {
        guard index < appState.settings.apps.count else { return }
        let old = appState.settings.apps[index]
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        panel.prompt = Loc.string("wheel.context.replace.prompt")
        if old.itemType == .app {
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowedContentTypes = [.application]
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
        } else {
            panel.canChooseFiles = true
            panel.canChooseDirectories = true
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let item: AppItem
        if old.itemType == .app {
            let name = FileManager.default.displayName(atPath: url.path)
            item = AppItem(
                name: name.hasSuffix(".app") ? String(name.dropLast(4)) : name,
                bundleIdentifier: Bundle(url: url)?.bundleIdentifier ?? "",
                path: url.path
            )
        } else {
            item = fileSystemItem(for: url)
        }
        IconCache.shared.invalidate()
        withAnimation(reduceMotion ? nil : SettingsDesign.standardMotion) {
            guard index < appState.settings.apps.count,
                  appState.settings.apps[index].id == old.id else { return }
            appState.settings.apps[index] = item
        }
    }

    private var appsPreviewPane: some View {
        wheelStage
            .frame(width: pieSize, height: pieSize)
            // 布局只占轮盘实际宽度，多余的方形边角不挤占右侧。
            .frame(width: wheelDiameter + 8, height: pieSize)
    }

    private var wheelStage: some View {
        ZStack {
            pieRing
            pieIcons
            recentPreviewSatellites
        }
        .frame(width: pieSize, height: pieSize)
        .offset(y: recentPreviewYOffset)
        .animation(.easeInOut(duration: 0.2), value: appState.settings.showRecentApps)
        .animation(.easeInOut(duration: 0.2), value: appState.settings.recentAppCount)
        .onTapGesture {
            withAnimation(reduceMotion ? nil : SettingsDesign.standardMotion) {
                selectedIndex = nil
            }
        }
    }

    /// 右侧是一张与预览等高的长卡片：平时是总览（添加、最近内容，恢复默认固定在底部），
    /// 添加或编辑时同一张卡片里换成面板。两栏顶边、底边对齐。
    private var appsControlPane: some View {
        ZStack(alignment: .top) {
            if let panel {
                itemPanel(panel)
                    .transition(.opacity)
            } else {
                overviewColumn
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: pieSize, alignment: .top)
        .settingsInsetSurface()
    }

    private var overviewColumn: some View {
        VStack(spacing: 0) {
            actionTile(
                Loc.string("settings.add"),
                subtitle: Loc.string(isFull ? "settings.add.full" : "settings.add.subtitle"),
                icon: "plus"
            ) {
                openPanel(.add)
            }
            .disabled(isFull)

            sectionDivider

            recentAppsControl

            Spacer(minLength: 0)

            sectionDivider

            if confirmingRestore {
                restoreConfirmation
                    .transition(.opacity)
            } else {
                actionTile(
                    Loc.string("settings.restoreDefaults"),
                    subtitle: Loc.string("settings.restoreDefaults.subtitle"),
                    icon: "arrow.counterclockwise",
                    isDestructive: true
                ) {
                    beginRestoreConfirmation()
                }
                .transition(.opacity)
            }
        }
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(SettingsDesign.quietDivider)
            .frame(height: SettingsDesign.dividerWidth)
            .padding(.horizontal, 8)
    }

    private var recentAppsControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(Loc.string("settings.recentApps"))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Toggle(Loc.string("settings.recentApps"), isOn: $appState.settings.showRecentApps)
                    .labelsHidden()
                    .toggleStyle(SmoothSettingsSwitch())
                    .controlSize(.small)
            }

            SmoothSegmentedControl(
                selection: $appState.settings.recentAppCount,
                options: (1...4).map { ($0, String($0)) },
                label: Loc.string("settings.recentApps")
            )
            .disabled(!appState.settings.showRecentApps)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
    }

    /// 恢复默认的原地确认：按钮展开成说明 + 取消/恢复，只有点“恢复”才执行。
    private var restoreConfirmation: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 14, weight: .regular))
                    .frame(width: 30, height: 30)
                    .background(SettingsDesign.emphasizedSurface,
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(Loc.string("settings.restoreDefaults.confirm.title"))
                        .font(.system(size: 13, weight: .medium))
                    Text(Loc.string("settings.restoreDefaults.inline"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                Button(Loc.string("settings.restoreDefaults.confirm.cancel"), action: cancelRestoreConfirmation)
                    .buttonStyle(SettingsPillButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button(Loc.string("settings.restoreDefaults.confirm.action"), action: restoreDefaults)
                    .buttonStyle(SettingsPillButtonStyle(prominent: true))
            }
        }
        .padding(8)
        .onHover { inside in
            restoreHovered = inside
            if !inside { scheduleRestoreCollapse() }
        }
    }

    private func actionTile(
        _ title: String,
        subtitle: String,
        icon: String,
        isDestructive: Bool = false,
        trailingIcon: String = "chevron.right",
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.primary)
                    .frame(width: 30, height: 30)
                    .background(
                        isDestructive ? SettingsDesign.emphasizedSurface : SettingsDesign.insetSurface,
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                    Text(subtitle)
                        .font(.system(size: 10.5, weight: .regular))
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 0)
                Image(systemName: trailingIcon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .frame(height: SettingsDesign.rowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 圆环

    private var pieRing: some View {
        ZStack {
            NativeGlassSamplingLayer(cornerRadius: outerRadius, intensity: glassMaterialIntensity)
                .frame(width: wheelDiameter, height: wheelDiameter)
                .allowsHitTesting(false)
            settingsGlassEdgeHighlightLayer
            centerLabel
        }
    }

    @ViewBuilder
    private var settingsGlassEdgeHighlightLayer: some View {
        ControlCenterGlassEdgeLayer(
            diameter: wheelDiameter,
            centerDiameter: innerRadius * 2,
            intensity: glassMaterialIntensity
        )
    }

    // MARK: - 中心标签

    @ViewBuilder
    private var centerLabel: some View {
        ZStack {
            // 1. 删除区激活（拖到中心）
            if isInDeleteZone {
                VStack(spacing: 4) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 26, weight: .semibold))
                    Text(Loc.string("wheel.releaseToDelete"))
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(.primary)
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
            // 2. 拖拽中（未进入删除区）
            else if draggingIndex != nil {
                VStack(spacing: 2) {
                    Text(Loc.string("wheel.dragToCenter"))
                        .font(.system(size: 10))
                    Text(Loc.string("wheel.delete"))
                        .font(.system(size: 10))
                }
                .foregroundStyle(.secondary)
                .transition(.opacity)
            }
            // 3. 选中状态（点击图标）
            else if let idx = selectedIndex, idx < appState.settings.apps.count {
                let item = appState.settings.apps[idx]
                VStack(spacing: 7) {
                    Text(item.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    if item.itemType == .keyAction {
                        Button(item.keyCombination?.displayString ?? Loc.string("keyAction.record")) { openEditor(for: item) }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, weight: .medium))
                    }
                    if item.itemType == .webLink {
                        Button(Loc.string("link.edit.title")) { openEditor(for: item) }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .settingsInsetSurface(emphasized: true)
                    }
                }
                .padding(.horizontal, 12)
                .transition(.opacity)
            }
            else if let removed = removedItems.last {
                Button(action: undoLastRemoval) {
                    VStack(spacing: 5) {
                        Image(nsImage: removed.item.icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 28, height: 28)
                            .matchedGeometryEffect(id: removed.item.id, in: wheelItemAnimation)
                        Label(Loc.string("wheel.undoRemoval"), systemImage: "arrow.uturn.backward")
                            .font(.system(size: 11, weight: .semibold))
                        Text(removed.item.displayName)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(10)
                    .frame(maxWidth: max(innerRadius * 2 - 10, 90))
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .disabled(appState.settings.apps.count >= maxSlots)
                .help(Loc.string(appState.settings.apps.count >= maxSlots ? "wheel.undoFull" : "wheel.undoRemoval"))
                .transition(.opacity)
            }
            // 4. 空状态
            else if appState.settings.apps.isEmpty {
                Text(Loc.string("wheel.addAppsHint"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            // 5. 默认提示
            else {
                VStack(spacing: 2) {
                    Text(Loc.string("wheel.dragToReorder"))
                        .font(.system(size: 10))
                    Text(Loc.string("wheel.dragToCenterDelete"))
                        .font(.system(size: 10))
                }
                .foregroundStyle(.tertiary)
            }
        }
        .animation(reduceMotion ? nil : SettingsDesign.standardMotion, value: selectedIndex)
        .animation(reduceMotion ? nil : SettingsDesign.standardMotion, value: isInDeleteZone)
        .animation(reduceMotion ? nil : SettingsDesign.standardMotion, value: draggingIndex)
        .animation(editAnimation, value: removedItems.last?.item.id)
    }

    // MARK: - 图标

    private var previewOrder: [Int] {
        let total = appState.settings.apps.count
        guard let from = draggingIndex, let to = dragTargetIndex,
              from != to, from < total, to < total else {
            return Array(0..<total)
        }
        var order = Array(0..<total)
        let item = order.remove(at: from)
        order.insert(item, at: to)
        return order
    }

    private var pieIcons: some View {
        let apps = appState.settings.apps
        let total = apps.count
        let preview = previewOrder
        return ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
            let displaySlot = preview.firstIndex(of: index) ?? index
            pieIcon(app: app, index: index, displaySlot: displaySlot, total: total)
        }
    }

    @ViewBuilder
    private var recentPreviewSatellites: some View {
        let apps = previewRecentApps
        let offsets = RecentAppSatelliteGeometry.offsets(
            count: apps.count,
            outerRadius: outerRadius,
            mainIconSize: iconSize
        )

        ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
            if index < offsets.count {
                recentPreviewSatellite(app)
                    .position(
                        x: center + offsets[index].x,
                        y: center + offsets[index].y
                    )
            }
        }
    }

    private func recentPreviewSatellite(_ app: AppItem) -> some View {
        let satelliteIconSize = RecentAppSatelliteGeometry.iconSize(for: iconSize)
        let baseDiameter = RecentAppSatelliteGeometry.baseDiameter(for: iconSize)

        return ZStack {
            NativeGlassSamplingLayer(
                cornerRadius: baseDiameter / 2,
                intensity: glassMaterialIntensity,
                circular: true
            )
            .frame(width: baseDiameter, height: baseDiameter)
            Circle()
                .stroke(Color.white.opacity(0.22 * glassMaterialIntensity), lineWidth: 0.55)

            Image(nsImage: app.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: satelliteIconSize, height: satelliteIconSize)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: app.itemType == .app ? satelliteIconSize * 0.22 : 0,
                        style: .continuous
                    )
                )

            if app.isRunning {
                Circle()
                    .fill(.primary)
                    .frame(width: 4, height: 4)
                    .opacity(0.85)
                    .offset(y: baseDiameter / 2 - 5)
            }
        }
        .frame(width: baseDiameter, height: baseDiameter)
        .allowsHitTesting(false)
    }

    private func slotPosition(slot: Int, total: Int) -> (x: CGFloat, y: CGFloat) {
        guard total > 0 else { return (center, center) }
        let angle = (2 * Double.pi / Double(total)) * Double(slot) - .pi / 2
        return (center + iconOrbitRadius * cos(angle), center - iconOrbitRadius * sin(angle))
    }

    private func pieIcon(app: AppItem, index: Int, displaySlot: Int, total: Int) -> some View {
        let originalPos = slotPosition(slot: index, total: total)
        let targetPos = slotPosition(slot: displaySlot, total: total)
        let isSelected = selectedIndex == index
        let isDragging = draggingIndex == index
        let angle = (2 * Double.pi / Double(max(total, 1))) * Double(index) - .pi / 2
        let pushDist: CGFloat = 6

        let posX = isDragging ? originalPos.x + dragTranslation.width : targetPos.x
        let posY = isDragging ? originalPos.y + dragTranslation.height : targetPos.y

        return ZStack {
            // 选中高亮圆 — 柔和的 tint 底色
            if isSelected && !isDragging {
                Circle()
                    .fill(SettingsDesign.selectedSurface)
                    .frame(width: iconSize + 12, height: iconSize + 12)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }

            Image(nsImage: app.icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: iconSize, height: iconSize)
                .matchedGeometryEffect(id: app.id, in: wheelItemAnimation)
                .overlay {
                    if isDragging && isInDeleteZone {
                        Circle()
                            .fill(.primary.opacity(0.32))
                            .overlay {
                                Image(systemName: "trash.fill")
                                    .font(.system(size: iconSize * 0.35, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            .transition(.opacity)
                    }
                }
        }
        .scaleEffect(isDragging ? (isInDeleteZone ? 0.85 : 1.2) : (isSelected ? 1.15 : 1.0))
        .offset(
            x: isSelected && !isDragging ? cos(angle) * pushDist : 0,
            y: isSelected && !isDragging ? -sin(angle) * pushDist : 0
        )
        .position(x: posX, y: posY)
        .zIndex(isDragging ? 10 : (isSelected ? 5 : 0))
        .gesture(dragGesture(index: index, total: total, originX: originalPos.x, originY: originalPos.y))
        .onTapGesture {
            withAnimation(SettingsDesign.standardMotion) {
                selectedIndex = selectedIndex == index ? nil : index
            }
        }
        .contextMenu {
            if app.itemType == .keyAction {
                Button(Loc.string("keyAction.title")) { openEditor(for: app) }
            }
            if app.itemType == .webLink {
                Button(Loc.string("link.edit.title")) { openEditor(for: app) }
            }
            if app.itemType == .app || app.itemType == .fileOrFolder {
                Button(Loc.string("wheel.context.replace")) { replaceItem(at: index) }
                Button(Loc.string("wheel.context.reveal")) { revealInFinder(app) }
            }
            Divider()
            Button(Loc.string("wheel.context.remove")) { removeItem(at: index) }
        }
    }

    // MARK: - 拖拽手势

    private func dragGesture(index: Int, total: Int, originX: CGFloat, originY: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                if draggingIndex == nil {
                    withAnimation(reduceMotion ? nil : SettingsDesign.standardMotion) {
                        selectedIndex = nil
                        draggingIndex = index
                    }
                } else {
                    draggingIndex = index
                }
                dragTranslation = value.translation

                let absX = originX + value.translation.width
                let absY = originY + value.translation.height
                let distFromCenter = hypot(absX - center, absY - center)
                let inDelete = distFromCenter < innerRadius

                if inDelete != isInDeleteZone {
                    withAnimation(reduceMotion ? nil : SettingsDesign.standardMotion) {
                        isInDeleteZone = inDelete
                    }
                }

                if inDelete {
                    // 进入删除区时取消排序预览
                    if dragTargetIndex != nil {
                        withAnimation(reduceMotion ? nil : SettingsDesign.standardMotion) {
                            dragTargetIndex = nil
                        }
                    }
                } else {
                    let target = slotIndex(at: CGPoint(x: absX, y: absY), total: total)
                    if target != dragTargetIndex {
                        withAnimation(
                            reduceMotion ? nil : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.52)
                        ) {
                            dragTargetIndex = target
                        }
                    }
                }
            }
            .onEnded { value in
                let absX = originX + value.translation.width
                let absY = originY + value.translation.height
                let distFromCenter = hypot(absX - center, absY - center)
                let inDelete = distFromCenter < innerRadius
                let target = slotIndex(at: CGPoint(x: absX, y: absY), total: total)

                withAnimation(inDelete ? editAnimation : (reduceMotion ? nil : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.52))) {
                    if inDelete {
                        // 拖到中心 → 删除
                        removedItems.append(RemovedWheelItem(item: appState.settings.apps[index], index: index))
                        appState.settings.apps.remove(at: index)
                    } else if target != index {
                        // 拖到其它槽位 → 重新排序
                        let item = appState.settings.apps.remove(at: index)
                        let insertAt = min(target, appState.settings.apps.count)
                        appState.settings.apps.insert(item, at: insertAt)
                    }
                    draggingIndex = nil
                    dragTranslation = .zero
                    dragTargetIndex = nil
                    isInDeleteZone = false
                }
            }
    }

    private func undoLastRemoval() {
        guard let removed = removedItems.last,
              appState.settings.apps.count < maxSlots,
              !appState.settings.apps.contains(where: { $0.id == removed.item.id }) else { return }
        withAnimation(editAnimation) {
            selectedIndex = nil
            _ = removedItems.popLast()
            appState.settings.apps.insert(removed.item, at: min(removed.index, appState.settings.apps.count))
        }
        if removed.item.itemType == .webLink && removed.item.customIconData == nil {
            appState.refreshWebsiteIcon(for: removed.item)
        }
    }

    private func slotIndex(at point: CGPoint, total: Int) -> Int {
        guard total > 0 else { return 0 }
        let dx = Double(point.x - center)
        let dy = Double(center - point.y)
        var angle = atan2(dy, dx)
        if angle < 0 { angle += 2 * .pi }
        let sliceAngle = (2 * .pi) / Double(total)
        let adjusted = fmod(angle + .pi / 2 + sliceAngle / 2, 2 * .pi)
        return Int(adjusted / sliceAngle) % total
    }
}

// MARK: - 应用选择器

/// Own the NSTextInputClient instead of borrowing a sheet's shared field editor.
private final class KeyActionNameTextView: NSTextView {
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

private struct KeyActionNameInput: NSViewRepresentable {
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
private struct KeyActionRecorderInput: NSViewRepresentable {
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

private struct KeyActionEditor: View {
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
private struct LargeKeyCap: View {
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

// MARK: - 通用设置

private struct SettingsGroup<Content: View>: View {
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
private struct AccessibilityPermissionRow: View {
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

private struct SettingRow<Accessory: View>: View {
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
private struct SettingsPillButtonStyle: ButtonStyle {
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
private enum AddKind: String, CaseIterable {
    case app, file, link, keyAction
}

/// 右侧一列在“添加”与“编辑某一项”时变成同一个面板，左侧预览始终可见。
private enum ItemPanelMode: Equatable {
    case add
    case edit(UUID)
}

/// 面板里的应用列表：搜索 + 点一下加入，可连续添加；已在轮盘里的打勾。
private struct AppListPanel: View {
    @ObservedObject var appState: AppState
    var canAdd: Bool
    var onAdd: (AppItem) -> Void
    @State private var search = ""
    @State private var apps: [AppItem] = []
    @State private var hovered: String?

    private var addedBundles: Set<String> {
        Set(appState.settings.apps.filter { $0.itemType == .app }.map(\.bundleIdentifier))
    }

    private var filtered: [AppItem] {
        guard !search.isEmpty else { return apps }
        return apps.filter {
            $0.name.localizedCaseInsensitiveContains(search)
                || $0.displayName.localizedCaseInsensitiveContains(search)
                || $0.bundleIdentifier.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tertiary)
                SearchField(text: $search, placeholder: Loc.string("appPicker.search"))
            }
            .padding(.horizontal, 9)
            .frame(height: 28)
            .settingsInsetSurface()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filtered) { app in
                        row(app, added: addedBundles.contains(app.bundleIdentifier))
                    }
                }
                .padding(.vertical, 4)
            }
            .settingsInsetSurface()
        }
        .onAppear {
            if apps.isEmpty { apps = AppState.installedApps() }
        }
    }

    private func row(_ app: AppItem, added: Bool) -> some View {
        Button { onAdd(app) } label: {
            HStack(spacing: 8) {
                Image(nsImage: app.icon)
                    .resizable()
                    .frame(width: 22, height: 22)
                Text(app.displayName)
                    .font(.system(size: 12.5))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: added ? "checkmark" : "plus")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(added ? .tertiary : .secondary)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hovered == app.bundleIdentifier && !added ? SettingsDesign.hoverSurface : .clear)
                    .padding(.horizontal, 4)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(added || !canAdd)
        .opacity(added ? 0.55 : 1)
        .onHover { inside in
            if inside { hovered = app.bundleIdentifier } else if hovered == app.bundleIdentifier { hovered = nil }
        }
    }
}

/// 面板里的文件区：拖入文件或文件夹即加入，也可以点“选择”。
private struct FileDropPanel: View {
    var canAdd: Bool
    var onAdd: ([URL]) -> Void
    var onChoose: () -> Void
    @State private var targeted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 8) {
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(.secondary)
                Text(Loc.string("panel.dropTitle"))
                    .font(.system(size: 13, weight: .medium))
                Text(Loc.string("panel.dropHint"))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 168)
            .settingsInsetSurface(emphasized: targeted)
            .overlay(
                RoundedRectangle(cornerRadius: SettingsDesign.surfaceRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(targeted ? 0.45 : 0.18),
                                  style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
            .animation(reduceMotion ? nil : SettingsDesign.quickMotion, value: targeted)
            .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
                guard canAdd else { return false }
                for provider in providers {
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        guard let url else { return }
                        DispatchQueue.main.async { onAdd([url]) }
                    }
                }
                return true
            }

            HStack {
                Spacer(minLength: 0)
                Button(Loc.string("panel.choose"), action: onChoose)
                    .buttonStyle(SettingsPillButtonStyle(prominent: true))
                    .disabled(!canAdd)
            }
        }
    }
}

/// 网址表单：添加与编辑共用。网址无效时原地提示；回车提交。
private struct LinkForm: View {
    let existing: AppItem?
    var canAdd: Bool = true
    let onSave: (String, String) -> Bool

    @State private var address: String
    @State private var name: String
    @State private var invalid = false
    @FocusState private var focus: Field?

    private enum Field { case address, name }

    init(existing: AppItem?, canAdd: Bool = true, onSave: @escaping (String, String) -> Bool) {
        self.existing = existing
        self.canAdd = canAdd
        self.onSave = onSave
        _address = State(initialValue: existing?.path ?? "")
        _name = State(initialValue: existing?.name ?? "")
    }

    private var canSubmit: Bool {
        canAdd && !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Loc.string(invalid ? "link.invalid.message" : "link.message"))
                .font(.system(size: 11))
                .foregroundStyle(invalid ? .primary : .secondary)
                .fixedSize(horizontal: false, vertical: true)

            field(Loc.string("link.address"), text: $address,
                  placeholder: Loc.string("link.placeholder"), id: .address)
            field(Loc.string("link.name"), text: $name,
                  placeholder: Loc.string("link.name.placeholder"), id: .name)

            HStack {
                Spacer(minLength: 0)
                Button(Loc.string(existing == nil ? "link.add" : "link.save"), action: submit)
                    .buttonStyle(SettingsPillButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSubmit)
            }
        }
        .onAppear { focus = .address }
        .onChange(of: address) { _ in invalid = false }
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String, id: Field) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($focus, equals: id)
                .onSubmit(submit)
                .padding(.horizontal, 9)
                .frame(height: 28)
                .settingsInsetSurface(emphasized: focus == id)
                .overlay(
                    RoundedRectangle(cornerRadius: SettingsDesign.surfaceRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(id == .address && invalid ? 0.5 : 0),
                                      lineWidth: 1)
                )
        }
    }

    private func submit() {
        guard canSubmit else { return }
        if !onSave(address, name) {
            invalid = true
            focus = .address
        }
    }
}

/// 记住某个视图对应的 NSView，用于在它正下方弹出原生菜单。
private final class MenuAnchorHolder {
    weak var view: NSView?

    func popUp(_ menu: NSMenu) {
        guard let view else { return }
        let y = view.isFlipped ? view.bounds.height + 4 : -4
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: y), in: view)
    }
}

private struct MenuAnchor: NSViewRepresentable {
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

private final class ClosureMenuItem: NSMenuItem {
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

private struct SettingDivider: View {
    var body: some View {
        Rectangle()
            .fill(SettingsDesign.quietDivider)
            .frame(height: SettingsDesign.dividerWidth)
            .padding(.leading, 12)
    }
}

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

private final class AppPickerSearchField: NSSearchField {
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

// MARK: - 交互模式

extension InteractionMode {
    var displayName: String {
        switch self {
        case .hold: return Loc.string("mode.holdDescription")
        case .click: return Loc.string("mode.clickDescription")
        }
    }
}
