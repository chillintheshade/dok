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
    @State private var dragging = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fraction: CGFloat {
        CGFloat(min(1, max(0, (value - range.lowerBound) / (range.upperBound - range.lowerBound))))
    }

    var body: some View {
        GeometryReader { geometry in
            let travel = max(1, geometry.size.width - 10)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12)).frame(height: 4)
                Capsule().fill(Color.primary).frame(width: 5 + travel * fraction, height: 4)
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
                    if !dragging {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { value = target }
                        dragging = true
                    } else {
                        value = target
                    }
                }
                .onEnded { _ in
                    dragging = false
                    let snapped = range.lowerBound + ((value - range.lowerBound) / step).rounded() * step
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
                        value = min(range.upperBound, max(range.lowerBound, snapped))
                    }
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
    @FocusState private var focusedTab: SettingsTab?
    @Namespace private var sidebarSelection
    let onSelectTab: (SettingsTab) -> Void

    init(selectedTab: SettingsTab, onSelectTab: @escaping (SettingsTab) -> Void = { _ in }) {
        _selectedTab = State(initialValue: selectedTab)
        self.onSelectTab = onSelectTab
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
        if reduceMotion {
            selectedTab = tab
        } else {
            withAnimation(SettingsDesign.standardMotion) { selectedTab = tab }
        }
        onSelectTab(tab)
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
    @State private var editingKeyAction: AppItem?
    @State private var selectedIndex: Int? = nil
    @State private var draggingIndex: Int? = nil
    @State private var dragTranslation: CGSize = .zero
    @State private var dragTargetIndex: Int? = nil
    @State private var isInDeleteZone: Bool = false
    @State private var removedItems: [RemovedWheelItem] = []
    @Namespace private var wheelItemAnimation

    private struct RemovedWheelItem {
        let item: AppItem
        let index: Int
    }

    private var editAnimation: Animation? {
        reduceMotion ? nil : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.32)
    }

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
        Group {
            if let item = editingKeyAction {
                KeyActionEditor(appState: appState, item: item, onCancel: {
                    editingKeyAction = nil
                }, onSave: saveKeyAction)
                .id(item.id)
            } else {
                HStack(alignment: .center, spacing: 8) {
                    appsPreviewPane
                    appsControlPane
                }
                .padding(.horizontal, 12)
            }
        }
        .padding(.vertical, 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .sheet(isPresented: $showingAppPicker) {
            AppPickerView(appState: appState, isPresented: $showingAppPicker) {
                removedItems.removeAll()
            }
        }
    }

    private func saveKeyAction(_ result: AppItem) {
        if let index = appState.settings.apps.firstIndex(where: { $0.id == result.id }) {
            appState.settings.apps[index] = result
        } else if appState.settings.apps.count < maxSlots {
            removedItems.removeAll()
            appState.settings.apps.append(result)
        }
        IconCache.shared.invalidate()
        editingKeyAction = nil
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
                removedItems.removeAll()
                appState.settings.apps.append(item)
            }
            IconCache.shared.invalidate()
        }
    }

    private func addWebLink() {
        guard appState.settings.apps.count < maxSlots else { return }
        editWebLink(nil)
    }

    private func editWebLink(_ existing: AppItem?) {
        guard existing != nil || appState.settings.apps.count < maxSlots else { return }

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = Loc.string("link.placeholder")
        field.stringValue = existing?.path ?? ""
        let nameField = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        nameField.placeholderString = Loc.string("link.name.placeholder")
        nameField.stringValue = existing?.name ?? ""
        let accessory = NSStackView(views: [
            NSTextField(labelWithString: Loc.string("link.address")), field,
            NSTextField(labelWithString: Loc.string("link.name")), nameField,
        ])
        accessory.orientation = .vertical
        accessory.alignment = .leading
        accessory.spacing = 6
        accessory.frame = NSRect(x: 0, y: 0, width: 320, height: 104)
        for input in [field, nameField] {
            input.widthAnchor.constraint(equalToConstant: 320).isActive = true
        }

        let alert = NSAlert()
        alert.messageText = Loc.string(existing == nil ? "link.title" : "link.edit.title")
        alert.informativeText = Loc.string("link.message")
        alert.alertStyle = .informational
        alert.accessoryView = accessory
        alert.addButton(withTitle: Loc.string(existing == nil ? "link.add" : "link.save"))
        alert.addButton(withTitle: Loc.string("link.cancel"))
        alert.window.initialFirstResponder = field

        var validatedURL: URL?
        while validatedURL == nil {
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            validatedURL = AppItem.normalizedWebURL(from: field.stringValue)
            if validatedURL == nil {
                alert.informativeText = Loc.string("link.invalid.message")
                alert.window.initialFirstResponder = field
            }
        }
        guard let url = validatedURL else { return }

        let customName = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
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
            } else if existing == nil {
                removedItems.removeAll()
                appState.settings.apps.append(item)
            }
        }
        if item.customIconData == nil { appState.refreshWebsiteIcon(for: item) }
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
            removedItems.removeAll()
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
                Loc.string("settings.addKeyAction"),
                subtitle: Loc.string("settings.addKeyAction.subtitle"),
                icon: "keyboard"
            ) {
                editingKeyAction = AppItem(name: "", bundleIdentifier: "", path: "", itemType: .keyAction)
            }
            .disabled(appState.settings.apps.count >= maxSlots)

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
                let item = appState.settings.apps[idx]
                VStack(spacing: 7) {
                    Text(item.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    if item.itemType == .keyAction {
                        Button(item.keyCombination?.displayString ?? Loc.string("keyAction.record")) { editingKeyAction = item }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, weight: .medium))
                    }
                    if item.itemType == .webLink {
                        Button(Loc.string("link.edit.title")) { editWebLink(item) }
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
                Button(Loc.string("keyAction.title")) { editingKeyAction = app }
            }
            if app.itemType == .webLink {
                Button(Loc.string("link.edit.title")) { editWebLink(app) }
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

struct AppPickerView: View {
    let appState: AppState
    @Binding var isPresented: Bool
    var onAdd: () -> Void = {}
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
            onAdd()
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

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.borderType = .bezelBorder
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor
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
        view.backgroundColor = .textBackgroundColor
        view.textContainerInset = NSSize(width: 5, height: 4)
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
            if commandSelector == #selector(NSResponder.insertNewline(_:)) { return true }
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

private struct KeyActionRecorderInput: NSViewRepresentable {
    @Binding var value: HotkeyConfig?
    @Binding var recording: Bool
    func makeNSView(context: Context) -> KeyActionRecorderControl { KeyActionRecorderControl(frame: .zero) }
    func updateNSView(_ control: KeyActionRecorderControl, context: Context) {
        control.value = value
        control.onChange = { value = $0 }
        control.onRecordingChanged = { recording = $0 }
    }
    static func dismantleNSView(_ control: KeyActionRecorderControl, coordinator: ()) {
        control.onRecordingChanged = nil
        control.onChange = nil
        control.stop(reason: "editor-dismissed")
    }
}

private struct KeyActionEditor: View {
    @ObservedObject var appState: AppState
    var item: AppItem
    var onCancel: () -> Void
    var onSave: (AppItem) -> Void
    @State private var name = ""
    @State private var combo: HotkeyConfig?
    @State private var recording = false
    @State private var targetBundle = ""
    @State private var targetName = ""

    private var conflict: Bool { combo == appState.settings.hotkey }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(Loc.string("keyAction.title")).font(.headline)
            KeyActionNameInput(text: $name)
                .frame(height: 30)
            HStack {
                Text(Loc.string("keyAction.combination"))
                Spacer()
                KeyActionRecorderInput(value: $combo, recording: $recording)
                    .frame(width: 190, height: 28)
            }
            Text(Loc.string(conflict ? "keyAction.conflict" : "keyAction.hint"))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Text(Loc.string("keyAction.target"))
                Spacer()
                Button(targetBundle.isEmpty ? Loc.string("keyAction.currentApp") : targetName) { chooseTarget() }
                if !targetBundle.isEmpty {
                    Button(Loc.string("keyAction.clearTarget")) { targetBundle = ""; targetName = "" }
                }
            }
            Text(Loc.string("keyAction.targetHint")).font(.caption).foregroundStyle(.secondary)
            if !AXIsProcessTrusted() {
                Text(Loc.string("keyAction.permission")).font(.caption).foregroundStyle(.secondary)
                Button(Loc.string("keyAction.openAccessibility")) {
                    KeyActionService.openAccessibility()
                }
            }
            HStack {
                Button(Loc.string("link.cancel"), action: onCancel)
                Spacer()
                Button(Loc.string("link.save")) {
                    var result = item
                    result.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    result.keyCombination = combo
                    result.bundleIdentifier = targetBundle
                    result.path = ""
                    onSave(result)
                }
                .disabled(recording || combo == nil || conflict || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .tint(.primary)
        .onAppear {
            name = item.name
            combo = item.keyCombination
            targetBundle = item.bundleIdentifier
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: targetBundle) {
                targetName = FileManager.default.displayName(atPath: url.path)
            } else { targetName = targetBundle }
        }
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
            targetName = FileManager.default.displayName(atPath: url.path)
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

            if #available(macOS 27.0, *) {
                SettingRow(title: "Liquid Glass") {
                    Text(Loc.string("settings.glass.followsSystem"))
                        .foregroundStyle(.secondary)
                }
            } else {
                compactSlider(
                    title: Loc.string("settings.opacity"),
                    value: $appState.settings.menuOpacity,
                    range: 0.15...1.0,
                    step: 0.05,
                    percentage: true
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
                SmoothSettingsSlider(value: value, range: range, step: step, label: title)
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
