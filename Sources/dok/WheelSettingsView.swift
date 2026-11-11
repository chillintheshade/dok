import SwiftUI
import AppKit
import ApplicationServices
import ServiceManagement
import UniformTypeIdentifiers

// 设置 → 轮盘：预览、右侧卡片，以及添加应用、文件、网址、按键动作的面板。

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
enum AddKind: String, CaseIterable {
    case app, file, link, keyAction
}

/// 右侧一列在“添加”与“编辑某一项”时变成同一个面板，左侧预览始终可见。
enum ItemPanelMode: Equatable {
    case add
    case edit(UUID)
}

/// 面板里的应用列表：搜索 + 点一下加入，可连续添加；已在轮盘里的打勾。
struct AppListPanel: View {
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
struct FileDropPanel: View {
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
struct LinkForm: View {
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
