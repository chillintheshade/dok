import SwiftUI
import AppKit
import ApplicationServices
import ServiceManagement

private enum SettingsDesign {
    static let windowWidth: CGFloat = 920
    static let windowHeight: CGFloat = 520
    static let sidebarWidth: CGFloat = 216
    static let navigationRowHeight: CGFloat = 34
    static let rowHeight: CGFloat = 44
    static let controlWidth: CGFloat = 130
    static let actionPaneWidth: CGFloat = 196
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
}

private extension View {
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
            glass.clipsToBounds = true
            glass.layer?.cornerCurve = .continuous
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
    let onSelectTab: (SettingsTab) -> Void

    init(selectedTab: SettingsTab, onSelectTab: @escaping (SettingsTab) -> Void = { _ in }) {
        _selectedTab = State(initialValue: selectedTab)
        self.onSelectTab = onSelectTab
    }

    var body: some View {
        ZStack {
            SettingsRootGlassLayer()
                .allowsHitTesting(false)

            HStack(spacing: 0) {
                settingsSidebar
                Rectangle()
                    .fill(SettingsDesign.hairline)
                    .frame(width: SettingsDesign.dividerWidth)
                    .accessibilityHidden(true)
                settingsContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // A narrow, explicit window-drag strip. It occupies only the empty
            // header band and cannot compete with wheel item reordering below.
            SettingsWindowDragHandle()
                .frame(height: 22)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .accessibilityHidden(true)
        }
        .tint(.primary)
        .frame(width: SettingsDesign.windowWidth, height: SettingsDesign.windowHeight)
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsTab.allCases) { tab in
                Button {
                    guard selectedTab != tab else { return }
                    NotificationCenter.default.post(name: .hotkeyRecordingCancelled, object: nil)
                    if reduceMotion {
                        selectedTab = tab
                    } else {
                        withAnimation(SettingsDesign.standardMotion) {
                            selectedTab = tab
                        }
                    }
                    onSelectTab(tab)
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
                        if selectedTab == tab {
                            RoundedRectangle(
                                cornerRadius: SettingsDesign.navigationRadius,
                                style: .continuous
                            )
                            .fill(SettingsDesign.selectedSurface)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.top, 24)
        .padding(.bottom, 16)
        .frame(width: SettingsDesign.sidebarWidth)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var settingsContent: some View {
        switch selectedTab {
        case .apps:
            AppsSettingsView()
                .environmentObject(appState)
        case .general:
            GeneralSettingsView()
                .environmentObject(appState)
        }
    }
}

// MARK: - 应用设置

struct AppsSettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingAppPicker = false
    @State private var selectedIndex: Int? = nil
    @State private var draggingIndex: Int? = nil
    @State private var dragTranslation: CGSize = .zero
    @State private var dragTargetIndex: Int? = nil
    @State private var isInDeleteZone: Bool = false

    private let pieSize: CGFloat = 452
    private var previewMenuRadius: CGFloat { appState.settings.menuRadius }
    private var previewOuterDiameter: CGFloat { (previewMenuRadius + 50) * 2 }
    private var baseScale: CGFloat {
        min((pieSize - 28) / previewOuterDiameter, 1.12)
    }
    private var previewRecentApps: [AppItem] {
        appState.recentContentForSettingsPreview()
    }
    private var satelliteFitScale: CGFloat {
        let fixedSatelliteSpacing = RecentAppSatelliteGeometry.edgeGap
            + RecentAppSatelliteGeometry.glassPadding * 2
        let scalableExtent = previewMenuRadius + 50
            + appState.settings.iconSize * RecentAppSatelliteGeometry.iconScale
        return (pieSize / 2 - 4 - fixedSatelliteSpacing) / scalableExtent
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
        HStack(alignment: .center, spacing: 8) {
            appsPreviewPane
            appsControlPane
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .sheet(isPresented: $showingAppPicker) {
            AppPickerView(appState: appState, isPresented: $showingAppPicker)
        }
    }

    // MARK: - 底部按钮

    private let maxSlots = AppState.maxSlots

    private func addFileSystemItem(chooseFolder: Bool) {
        guard appState.settings.apps.count < maxSlots else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = !chooseFolder
        panel.canChooseDirectories = chooseFolder
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        panel.prompt = Loc.string("openPanel.add")
        panel.message = Loc.string(chooseFolder ? "openPanel.folder.message" : "openPanel.file.message")
        if panel.runModal() == .OK, let url = panel.url {
            let bookmarkData = try? url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            let item = AppItem(
                name: url.lastPathComponent,
                bundleIdentifier: "",
                path: url.path,
                itemType: .fileOrFolder,
                bookmarkData: bookmarkData,
                customIconData: AppItem.persistentCustomIconData(for: url)
            )
            withAnimation(reduceMotion ? nil : SettingsDesign.standardMotion) {
                appState.settings.apps.append(item)
            }
            IconCache.shared.invalidate()
        }
    }

    private func addWebLink() {
        guard appState.settings.apps.count < maxSlots else { return }

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = Loc.string("link.placeholder")

        let alert = NSAlert()
        alert.messageText = Loc.string("link.title")
        alert.informativeText = Loc.string("link.message")
        alert.alertStyle = .informational
        alert.accessoryView = field
        alert.addButton(withTitle: Loc.string("link.add"))
        alert.addButton(withTitle: Loc.string("link.cancel"))
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let url = AppItem.normalizedWebURL(from: field.stringValue) else {
            let invalidAlert = NSAlert()
            invalidAlert.messageText = Loc.string("link.invalid.title")
            invalidAlert.informativeText = Loc.string("link.invalid.message")
            invalidAlert.alertStyle = .warning
            invalidAlert.runModal()
            return
        }

        let item = AppItem(
            name: url.host ?? url.absoluteString,
            bundleIdentifier: "",
            path: url.absoluteString,
            itemType: .webLink
        )
        withAnimation(reduceMotion ? nil : SettingsDesign.standardMotion) {
            appState.settings.apps.append(item)
        }
        IconCache.shared.invalidate()
    }

    private func restoreDefaultsWithConfirmation() {
        let alert = NSAlert()
        alert.messageText = Loc.string("settings.restoreDefaults.confirm.title")
        alert.informativeText = Loc.string("settings.restoreDefaults.confirm.message")
        alert.alertStyle = .warning
        alert.addButton(withTitle: Loc.string("settings.restoreDefaults.confirm.action"))
        alert.addButton(withTitle: Loc.string("settings.restoreDefaults.confirm.cancel"))

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        withAnimation(reduceMotion ? nil : SettingsDesign.standardMotion) {
            selectedIndex = nil
            appState.settings.apps = Array(AppState.defaultApps().prefix(maxSlots))
        }
    }

    private var appsPreviewPane: some View {
        wheelStage
            .frame(width: 475, height: 500, alignment: .center)
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

    private var appsControlPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            controlList
            recentAppsControl
        }
        .frame(width: SettingsDesign.actionPaneWidth)
    }

    private var recentAppsControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(Loc.string("settings.recentApps"))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Toggle("", isOn: $appState.settings.showRecentApps)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            Picker("", selection: $appState.settings.recentAppCount) {
                ForEach(1...4, id: \.self) { count in
                    Text("\(count)").tag(count)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .disabled(!appState.settings.showRecentApps)
        }
        .padding(12)
        .settingsInsetSurface()
    }

    private var controlList: some View {
        VStack(spacing: 0) {
            actionTile(
                Loc.string("settings.addApp"),
                subtitle: Loc.string("settings.addApp.subtitle"),
                icon: "plus.app"
            ) {
                showingAppPicker = true
            }
            .disabled(appState.settings.apps.count >= maxSlots)

            quietActionDivider

            actionTile(
                Loc.string("settings.addFolder"),
                subtitle: Loc.string("settings.addFolder.subtitle"),
                icon: "folder.badge.plus"
            ) {
                addFileSystemItem(chooseFolder: true)
            }

            quietActionDivider

            actionTile(
                Loc.string("settings.addFile"),
                subtitle: Loc.string("settings.addFile.subtitle"),
                icon: "doc.badge.plus"
            ) {
                addFileSystemItem(chooseFolder: false)
            }

            quietActionDivider

            actionTile(
                Loc.string("settings.addLink"),
                subtitle: Loc.string("settings.addLink.subtitle"),
                icon: "link.badge.plus"
            ) {
                addWebLink()
            }

            quietActionDivider

            actionTile(
                Loc.string("settings.restoreDefaults"),
                subtitle: Loc.string("settings.restoreDefaults.subtitle"),
                icon: "arrow.counterclockwise",
                isDestructive: true
            ) {
                restoreDefaultsWithConfirmation()
            }
        }
        .settingsInsetSurface()
    }

    private var quietActionDivider: some View {
        Rectangle()
            .fill(SettingsDesign.quietDivider)
            .frame(height: SettingsDesign.dividerWidth)
            .padding(.leading, 42)
    }

    private func actionTile(
        _ title: String,
        subtitle: String,
        icon: String,
        isDestructive: Bool = false,
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
                Image(systemName: "chevron.right")
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
                Text(appState.settings.apps[idx].displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .transition(.scale(scale: 0.75).combined(with: .opacity))
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
        .animation(SettingsDesign.standardMotion, value: selectedIndex)
        .animation(SettingsDesign.standardMotion, value: isInDeleteZone)
        .animation(SettingsDesign.standardMotion, value: draggingIndex)
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
                intensity: glassMaterialIntensity
            )
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

            Image(systemName: "clock.fill")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.72))
                .frame(width: 15, height: 15)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.32), lineWidth: 0.5))
                .offset(x: baseDiameter * 0.31, y: baseDiameter * 0.31)

            if app.isRunning {
                Circle()
                    .fill(.primary)
                    .frame(width: 4, height: 4)
                    .opacity(0.85)
                    .offset(y: baseDiameter / 2 + 5)
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

                withAnimation(
                    reduceMotion ? nil : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.52)
                ) {
                    if inDelete {
                        // 拖到中心 → 删除
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

struct AppPickerView: View {
    let appState: AppState
    @Binding var isPresented: Bool
    @State private var searchText = ""
    @State private var installedApps: [AppItem] = []
    @State private var recentlyAdded: Set<String> = []

    var filteredApps: [AppItem] {
        let existing = Set(appState.settings.apps.map { $0.bundleIdentifier })
        let available = installedApps.filter { !existing.contains($0.bundleIdentifier) }

        if searchText.isEmpty {
            return available
        }
        return available.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.displayName.localizedCaseInsensitiveContains(searchText) ||
            $0.bundleIdentifier.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text(Loc.string("appPicker.title"))
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button(Loc.string("appPicker.done")) { isPresented = false }
                    .font(.system(size: 13, weight: .medium))
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .settingsInsetSurface(emphasized: true)
                    .keyboardShortcut(.defaultAction)
            }

            SearchField(text: $searchText, placeholder: Loc.string("appPicker.search"))

            List(filteredApps) { app in
                let justAdded = recentlyAdded.contains(app.bundleIdentifier)
                HStack(spacing: 12) {
                    Image(nsImage: app.icon)
                        .resizable()
                        .frame(width: 30, height: 30)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(app.displayName)
                            .font(.system(size: 13))
                        if app.displayName != app.name {
                            Text(app.name)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Spacer()

                    if justAdded {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.primary)
                            .transition(.opacity)
                    } else {
                        Button(action: { addApp(app) }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 16))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                        .disabled(appState.settings.apps.count >= AppState.maxSlots)
                    }
                }
                .frame(height: SettingsDesign.rowHeight)
            }
            .listStyle(.plain)
        }
        .padding(16)
        .frame(width: 420, height: 500)
        .onAppear {
            installedApps = AppState.installedApps()
        }
    }

    func addApp(_ app: AppItem) {
        guard appState.settings.apps.count < AppState.maxSlots else { return }
        withAnimation(SettingsDesign.standardMotion) {
            appState.settings.apps.append(app)
            recentlyAdded.insert(app.bundleIdentifier)
        }
        // 短暂显示勾后从列表移除
        let bid = app.bundleIdentifier
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.easeOut(duration: 0.25)) {
                _ = recentlyAdded.remove(bid)
            }
        }
    }
}

// MARK: - 通用设置

private struct SettingsGroup<Content: View>: View {
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
            .settingsInsetSurface()
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
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)

            Spacer(minLength: 8)
            accessory
                .controlSize(.small)
                .frame(width: SettingsDesign.controlWidth, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(height: SettingsDesign.rowHeight)
    }
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
    @State private var launchAtLogin = false

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
        .padding(SettingsDesign.contentInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            launchAtLogin = getLaunchAtLogin()
        }
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
                Picker("", selection: $appState.settings.interactionMode) {
                    Text(Loc.string("mode.click")).tag(InteractionMode.click)
                    Text(Loc.string("mode.hold")).tag(InteractionMode.hold)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
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
                Picker("", selection: $appState.settings.menuPosition) {
                    Text(Loc.string("position.mouse")).tag(MenuPosition.followMouse)
                    Text(Loc.string("position.center")).tag(MenuPosition.screenCenter)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            SettingDivider()

            SettingRow(title: Loc.string("settings.theme")) {
                Picker("", selection: $appState.settings.appearanceMode) {
                    Text(Loc.string("theme.system")).tag(AppearanceMode.system)
                    Text(Loc.string("theme.light")).tag(AppearanceMode.light)
                    Text(Loc.string("theme.dark")).tag(AppearanceMode.dark)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .onChange(of: appState.settings.appearanceMode) { _ in
                    NotificationCenter.default.post(name: .appearanceChanged, object: nil)
                }
            }

            SettingDivider()

            compactSlider(
                title: Loc.string("settings.radius"),
                value: $appState.settings.menuRadius,
                range: 100...180,
                step: 10
            )

            SettingDivider()

            compactSlider(
                title: Loc.string("settings.icon"),
                value: $appState.settings.iconSize,
                range: 32...64,
                step: 4
            )

            SettingDivider()

            compactSlider(
                title: Loc.string("settings.opacity"),
                value: $appState.settings.menuOpacity,
                range: 0.15...1.0,
                step: 0.05,
                percentage: true
            )
        }
    }

    private var systemGroup: some View {
        SettingsGroup(title: Loc.string("settings.group.system")) {
            SettingRow(title: Loc.string("settings.launchAtLogin")) {
                Toggle("", isOn: $launchAtLogin)
                    .labelsHidden()
                    .onChange(of: launchAtLogin) { newValue in
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
        percentage: Bool = false
    ) -> some View {
        SettingRow(title: title) {
            VStack(spacing: 2) {
                HStack {
                    Spacer(minLength: 0)
                    Text(percentage ? "\(Int(round(value.wrappedValue * 100)))%" : "\(Int(value.wrappedValue))")
                        .font(.system(size: 11.5, weight: .regular, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Slider(value: value, in: range, step: step)
            }
        }
    }

    func getLaunchAtLogin() -> Bool {
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

struct SearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.sendsSearchStringImmediately = true
        // sheet 窗口 IME 修复：激活 app + 让 sheet 成为 key window + 聚焦搜索框
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApp.activate(ignoringOtherApps: true)
            if let window = field.window {
                window.makeKey()
                window.makeFirstResponder(field)
            }
        }
        // 双重保障：延迟再试一次
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let window = field.window, window.firstResponder !== field.currentEditor() {
                NSApp.activate(ignoringOtherApps: true)
                window.makeKey()
                window.makeFirstResponder(field)
            }
        }
        return field
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSSearchFieldDelegate {
        let parent: SearchField
        init(_ parent: SearchField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSSearchField else { return }
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
