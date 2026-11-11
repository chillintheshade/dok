import SwiftUI
import AppKit
import ApplicationServices
import ServiceManagement
import UniformTypeIdentifiers

// 设置窗口外壳：侧栏、两个页面的切换和窗口高度。

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
// MARK: - 交互模式

extension InteractionMode {
    var displayName: String {
        switch self {
        case .hold: return Loc.string("mode.holdDescription")
        case .click: return Loc.string("mode.clickDescription")
        }
    }
}
