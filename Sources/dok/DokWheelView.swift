import SwiftUI
import AppKit

// MARK: - Selection Wedge Shape

struct WedgeShape: Shape {
    var midAngle: Double
    var sliceAngle: Double
    var innerRadius: CGFloat
    var outerRadius: CGFloat

    var animatableData: Double {
        get { midAngle }
        set { midAngle = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var p = Path()
        p.addArc(center: c, radius: outerRadius,
                 startAngle: .degrees(midAngle - sliceAngle / 2),
                 endAngle: .degrees(midAngle + sliceAngle / 2),
                 clockwise: false)
        p.addArc(center: c, radius: innerRadius,
                 startAngle: .degrees(midAngle + sliceAngle / 2),
                 endAngle: .degrees(midAngle - sliceAngle / 2),
                 clockwise: true)
        p.closeSubpath()
        return p
    }
}

// MARK: - Donut Shape

struct DonutShape: Shape {
    var innerRadius: CGFloat
    var outerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var p = Path()
        p.addArc(center: c, radius: outerRadius,
                 startAngle: .zero, endAngle: .degrees(360), clockwise: false)
        p.addArc(center: c, radius: innerRadius,
                 startAngle: .zero, endAngle: .degrees(360), clockwise: true)
        return p
    }
}

// MARK: - Native Glass Sampling

enum DokGlassMaterial {
    static let tintBase: Double = 0.03
    static let tintRange: Double = 0.14
    static let minimumMenuOpacity: Double = 0.15

    static func intensity(for menuOpacity: Double) -> Double {
        let clamped = min(max(menuOpacity, minimumMenuOpacity), 1)
        return (clamped - minimumMenuOpacity) / (1 - minimumMenuOpacity)
    }
}

final class CompatibilityGlassEffectView: NSView {
    private let effectView = NSVisualEffectView()
    private let tintView = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        clipsToBounds = true

        effectView.blendingMode = .behindWindow
        effectView.material = .popover
        effectView.state = .active
        effectView.wantsLayer = true
        addSubview(effectView)

        tintView.wantsLayer = true
        addSubview(tintView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        effectView.frame = bounds
        tintView.frame = bounds
    }

    func apply(cornerRadius: CGFloat, intensity: Double) {
        let clampedIntensity = min(max(intensity, 0), 1)
        let tintAlpha = DokGlassMaterial.tintBase + clampedIntensity * DokGlassMaterial.tintRange

        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        effectView.layer?.cornerRadius = cornerRadius
        effectView.layer?.cornerCurve = .continuous
        effectView.layer?.masksToBounds = true
        tintView.layer?.backgroundColor = NSColor.black.withAlphaComponent(tintAlpha).cgColor
    }
}

struct NativeGlassSamplingLayer: NSViewRepresentable {
    let cornerRadius: CGFloat
    let intensity: Double

    func makeNSView(context: Context) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            applyMaterial(to: glass)
            return glass
        }

        let glass = CompatibilityGlassEffectView()
        glass.apply(cornerRadius: cornerRadius, intensity: intensity)
        return glass
    }

    func updateNSView(_ view: NSView, context: Context) {
        if #available(macOS 26.0, *), let glass = view as? NSGlassEffectView {
            applyMaterial(to: glass)
        } else if let glass = view as? CompatibilityGlassEffectView {
            glass.apply(cornerRadius: cornerRadius, intensity: intensity)
        }
    }

    @available(macOS 26.0, *)
    private func applyMaterial(to glass: NSGlassEffectView) {
        let clampedIntensity = min(max(intensity, 0), 1)
        glass.style = .clear
        glass.cornerRadius = cornerRadius
        // Keep the native compositor fully active. Density changes through tint,
        // matching Control Center instead of fading the entire glass surface.
        glass.alphaValue = 1
        glass.tintColor = NSColor.black.withAlphaComponent(
            CGFloat(DokGlassMaterial.tintBase + clampedIntensity * DokGlassMaterial.tintRange)
        )
        glass.clipsToBounds = true
        glass.layer?.cornerRadius = cornerRadius
        glass.layer?.cornerCurve = .continuous
        glass.layer?.masksToBounds = true
    }
}

extension View {
    @ViewBuilder
    func dokCapsuleGlass() -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular, in: .capsule)
        } else {
            background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.22), lineWidth: 0.55))
        }
    }

    @ViewBuilder
    func dokKeyCapGlass() -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular, in: .rect(cornerRadius: 5))
        } else {
            background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(Color.white.opacity(0.22), lineWidth: 0.55)
                )
        }
    }
}

struct ControlCenterGlassEdgeLayer: View {
    let diameter: CGFloat
    let centerDiameter: CGFloat
    let intensity: Double

    init(
        diameter: CGFloat,
        centerDiameter: CGFloat,
        intensity: Double
    ) {
        self.diameter = diameter
        self.centerDiameter = centerDiameter
        self.intensity = intensity
    }

    var body: some View {
        let strength = min(max(intensity, 0), 1)

        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.24 * strength), lineWidth: 0.55)
                .frame(width: diameter - 1, height: diameter - 1)

            Circle()
                .fill(Color.primary.opacity(0.018 * strength))
                .frame(width: centerDiameter, height: centerDiameter)
        }
        .frame(width: diameter, height: diameter)
        .allowsHitTesting(false)
    }
}

// MARK: - Motion

private struct LiquidContentTransitionModifier: ViewModifier {
    let opacity: Double
    let scale: CGFloat
    let blur: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .scaleEffect(scale)
            .blur(radius: blur)
    }
}

enum MenuMotion {
    static let contentAppearDuration: Double = 0.11
    static let contentDismissDuration: Double = 0.08
    static let dismissOrderOutDelay: Double = 0.09
    static let glassSamplerWarmupDelay: Double = 0.024
    static let windowRevealDuration: Double = 0.12
    static let windowWarmupAlpha: CGFloat = 0.01
    static let iconFocusResponse: Double = 0.18
    static let centerSwapResponse: Double = 0.16

    static let iconSelectedScale: CGFloat = 1.07
    static let iconSelectedPushRatio: CGFloat = 0.018
    static let selectedDotScale: CGFloat = 1.62

    static func menuAnimation(isVisible: Bool) -> Animation {
        isVisible
            ? .easeOut(duration: contentAppearDuration)
            : .easeIn(duration: contentDismissDuration)
    }

    static var iconFocusAnimation: Animation {
        .spring(response: iconFocusResponse, dampingFraction: 0.68)
    }

    static var centerAnimation: Animation {
        .spring(response: centerSwapResponse, dampingFraction: 0.78)
    }

    static var wedgeSelectionAnimation: Animation {
        .easeOut(duration: 0.14)
    }

    static var centerContentTransition: AnyTransition {
        .modifier(
            active: LiquidContentTransitionModifier(opacity: 0, scale: 0.965, blur: 3),
            identity: LiquidContentTransitionModifier(opacity: 1, scale: 1, blur: 0)
        )
    }
}

enum RecentAppSatelliteGeometry {
    static let iconScale: CGFloat = 0.75
    static let glassPadding: CGFloat = 8
    static let edgeGap: CGFloat = 12

    static func iconSize(for mainIconSize: CGFloat) -> CGFloat {
        mainIconSize * iconScale
    }

    static func baseDiameter(for mainIconSize: CGFloat) -> CGFloat {
        iconSize(for: mainIconSize) + glassPadding * 2
    }

    static func offsets(
        count: Int,
        outerRadius: CGFloat,
        mainIconSize: CGFloat
    ) -> [CGPoint] {
        let angles: [CGFloat]
        switch min(max(count, 0), 4) {
        case 1: angles = [90]
        case 2: angles = [78, 102]
        case 3: angles = [70, 90, 110]
        case 4: angles = [63, 81, 99, 117]
        default: return []
        }

        let orbit = outerRadius + edgeGap + baseDiameter(for: mainIconSize) / 2
        return angles.map { degrees in
            let radians = degrees * .pi / 180
            return CGPoint(x: orbit * cos(radians), y: orbit * sin(radians))
        }
    }
}

private struct SlotNotificationBadge: View {
    let text: String
    let iconSize: CGFloat

    private var displayText: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let number = Int(trimmed), number > 99 {
            return "99+"
        }
        return trimmed
    }

    private var diameter: CGFloat { max(13, iconSize * 0.4) }

    var body: some View {
        Text(displayText)
            .font(.system(size: max(8, iconSize * 0.2), weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.55)
            .padding(.horizontal, diameter * 0.24)
            .frame(minWidth: diameter, minHeight: diameter)
            .background(Color(red: 0.94, green: 0.18, blue: 0.16), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.72), lineWidth: 0.7))
            .shadow(color: .black.opacity(0.2), radius: 1.5, y: 0.75)
            .allowsHitTesting(false)
    }
}

// MARK: - DokWheelView

struct DokWheelView: View {
    @ObservedObject var appState: AppState
    var onAppSelected: ((AppItem) -> Void)?
    var onSettingsTapped: (() -> Void)?

    static let windowSize: CGFloat = 640

    @State private var wedgeAngle: Double = 90
    @State private var showWedge: Bool = false

    init(appState: AppState,
         onAppSelected: ((AppItem) -> Void)? = nil,
         onSettingsTapped: (() -> Void)? = nil) {
        self.appState = appState
        self.nowPlaying = appState.nowPlaying
        self.onAppSelected = onAppSelected
        self.onSettingsTapped = onSettingsTapped
    }

    private var iconOrbitRadius: CGFloat { appState.settings.menuRadius }
    private var ringThickness: CGFloat { 100 }
    private var outerRadius: CGFloat { iconOrbitRadius + ringThickness / 2 }
    private var innerRadius: CGFloat { iconOrbitRadius - ringThickness / 2 }
    private var center: CGFloat { Self.windowSize / 2 }
    private var wheelDiameter: CGFloat { outerRadius * 2 }
    private var iconSize: CGFloat { appState.settings.iconSize }
    private var glassMaterialIntensity: Double {
        DokGlassMaterial.intensity(for: appState.settings.menuOpacity)
    }
    private var centerLensRadius: CGFloat {
        let maxRadiusBeforeIcons = iconOrbitRadius - iconSize / 2 - 10
        return min(max(innerRadius, 66), maxRadiusBeforeIcons)
    }
    private var centerControlScale: CGFloat {
        min(max(iconOrbitRadius / 130, 0.88), 1.42)
    }
    private var centerMusicControlScale: CGFloat {
        let radiusScale = centerControlScale
        let availableScale = (centerLensRadius * 2 - 18) / 142
        return min(radiusScale, max(0.68, availableScale))
    }
    private var centerSettingsIconSize: CGFloat { 24 * centerControlScale }
    private var musicArtworkBaseSize: CGFloat { 58 }
    private var musicArtworkSize: CGFloat { musicArtworkBaseSize * centerMusicControlScale }
    private var musicArtworkCornerRadius: CGFloat { 12 }
    private var musicProgressDiameter: CGFloat { centerLensRadius * 2 }
    private var musicProgressLineWidth: CGFloat {
        min(max(0.9 * centerMusicControlScale, 0.9), 1.0)
    }
    private var musicTitleFontSize: CGFloat { 11.5 * centerMusicControlScale }
    private var musicSecondaryControlSize: CGFloat { 15 * centerMusicControlScale }
    private var musicPrimaryControlSize: CGFloat { 22 * centerMusicControlScale }
    private var musicControlSpacing: CGFloat { 18 * centerMusicControlScale }
    private var musicVerticalGap: CGFloat { 8 * centerMusicControlScale }
    private var musicControllerWidth: CGFloat {
        min(min(max(iconOrbitRadius * 1.28, 142), 230), max(centerLensRadius * 2 - 18, 96))
    }
    private var showsMusicController: Bool {
        appState.selectedIndex == nil
            && appState.selectedRecentAppIndex == nil
            && nowPlaying.hasNowPlaying
            && appState.settings.showMusicControl
    }

    private var sliceAngleDeg: Double {
        let count = appState.settings.apps.count
        return count > 0 ? 360.0 / Double(count) : 360.0
    }

    private func angleForIndex(_ index: Int) -> Double {
        90.0 - sliceAngleDeg * Double(index)
    }

    private func normalizedAngleDelta(from current: Double, to target: Double) -> Double {
        var delta = (target - current).truncatingRemainder(dividingBy: 360)
        if delta > 180 {
            delta -= 360
        } else if delta < -180 {
            delta += 360
        }
        return delta
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // The sampled glass is presented at its final geometry. Scaling a live
            // desktop sampler looks synthetic and can force a cached/live frame swap.
            nativeGlassSamplingLayer
            materialOverlayLayers

            animatedWheelLayers
        }
        .frame(width: Self.windowSize, height: Self.windowSize)
        .onChange(of: appState.selectedIndex) { newIndex in
            handleSelectionChange(newIndex)
        }
        .onChange(of: appState.isMenuVisible) { visible in
            if !visible {
                withAnimation(.easeOut(duration: 0.08)) {
                    showWedge = false
                }
            }
        }
    }

    private var animatedWheelLayers: some View {
        ZStack {
            selectedWedgeLayer
            musicProgressBoundaryLayer
            centerContent
            iconsLayer
            recentAppSatellitesLayer
        }
        .scaleEffect(appState.isMenuVisible ? 1 : 0.975)
        .opacity(appState.isMenuVisible ? 1 : 0)
        .animation(MenuMotion.menuAnimation(isVisible: appState.isMenuVisible),
                   value: appState.isMenuVisible)
    }

    private var materialOverlayLayers: some View {
        glassEdgeHighlightLayer
        .compositingGroup()
        .allowsHitTesting(false)
    }

    // MARK: - Selection Wedge

    @ViewBuilder
    private var nativeGlassSamplingLayer: some View {
        NativeGlassSamplingLayer(
            cornerRadius: outerRadius,
            intensity: glassMaterialIntensity
        )
            .frame(width: wheelDiameter, height: wheelDiameter)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var glassEdgeHighlightLayer: some View {
        ControlCenterGlassEdgeLayer(
            diameter: wheelDiameter,
            centerDiameter: centerLensRadius * 2,
            intensity: glassMaterialIntensity
        )
    }

    @ViewBuilder
    private var selectedWedgeLayer: some View {
        if showWedge {
            WedgeShape(
                midAngle: wedgeAngle,
                sliceAngle: sliceAngleDeg,
                innerRadius: centerLensRadius + 3,
                outerRadius: outerRadius - 3
            )
            .fill(Color.accentColor.opacity(0.12))
            .frame(width: outerRadius * 2, height: outerRadius * 2)
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }

    // MARK: - Icons

    @ViewBuilder
    private var iconsLayer: some View {
        ForEach(Array(appState.settings.apps.enumerated()), id: \.element.id) { index, app in
            let total = appState.settings.apps.count
            let angle = (2 * Double.pi / Double(total)) * Double(index) - .pi / 2
            let x = center + iconOrbitRadius * cos(angle)
            let y = center - iconOrbitRadius * sin(angle)
            let isSelected = appState.selectedIndex == index
            let pushDist = iconOrbitRadius * MenuMotion.iconSelectedPushRatio

            ZStack {
                selectedIconHalo(angle: angle, isSelected: isSelected)

                if app.itemType == .app {
                    Image(nsImage: app.icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: iconSize, height: iconSize)
                        // App 图标保留圆角裁剪，避免 macOS 预渲染阴影外溢。
                        .clipShape(RoundedRectangle(cornerRadius: iconSize * 0.22, style: .continuous))
                } else {
                    Image(nsImage: app.icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: iconSize, height: iconSize)
                }

                if let badge = appState.notificationBadge(for: app) {
                    SlotNotificationBadge(text: badge, iconSize: iconSize)
                        .offset(x: iconSize * 0.36, y: -iconSize * 0.36)
                }

                // 运行中指示点
                if app.isRunning {
                    Circle()
                        .fill(.primary)
                        .frame(width: 4, height: 4)
                        .scaleEffect(isSelected ? MenuMotion.selectedDotScale : 1.0)
                        .opacity(isSelected ? 1.0 : 0.85)
                        .offset(y: iconSize / 2 + 6)
                        .animation(MenuMotion.iconFocusAnimation, value: isSelected)
                }
            }
            // 选中：轻微放大 + 沿径向外浮，像焦点压过玻璃表面。
            .scaleEffect(isSelected ? MenuMotion.iconSelectedScale : 1.0)
            .offset(
                x: isSelected ? cos(angle) * pushDist : 0,
                y: isSelected ? -sin(angle) * pushDist : 0
            )
            .animation(MenuMotion.iconFocusAnimation, value: isSelected)
            .position(x: x, y: y)
        }
    }

    @ViewBuilder
    private var recentAppSatellitesLayer: some View {
        let apps = appState.recentAppSnapshot
        let offsets = RecentAppSatelliteGeometry.offsets(
            count: apps.count,
            outerRadius: outerRadius,
            mainIconSize: iconSize
        )

        ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
            if index < offsets.count {
                recentAppSatellite(
                    app: app,
                    isSelected: appState.selectedRecentAppIndex == index
                )
                .position(
                    x: center + offsets[index].x,
                    y: center + offsets[index].y
                )
            }
        }
    }

    private func recentAppSatellite(app: AppItem, isSelected: Bool) -> some View {
        let satelliteIconSize = RecentAppSatelliteGeometry.iconSize(for: iconSize)
        let baseDiameter = RecentAppSatelliteGeometry.baseDiameter(for: iconSize)

        return ZStack {
            NativeGlassSamplingLayer(
                cornerRadius: baseDiameter / 2,
                intensity: glassMaterialIntensity
            )
            Circle()
                .stroke(Color.white.opacity(0.22 * glassMaterialIntensity), lineWidth: 0.55)

            if app.itemType == .app {
                Image(nsImage: app.icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: satelliteIconSize, height: satelliteIconSize)
                    .clipShape(RoundedRectangle(
                        cornerRadius: satelliteIconSize * 0.22,
                        style: .continuous
                    ))
            } else {
                Image(nsImage: app.icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: satelliteIconSize, height: satelliteIconSize)
            }

            Image(systemName: "clock.fill")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.72))
                .frame(width: 15, height: 15)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.32), lineWidth: 0.5))
                .offset(x: baseDiameter * 0.31, y: baseDiameter * 0.31)

            if let badge = appState.notificationBadge(for: app) {
                SlotNotificationBadge(text: badge, iconSize: satelliteIconSize)
                    .offset(x: baseDiameter * 0.31, y: -baseDiameter * 0.31)
            }

            if app.isRunning {
                Circle()
                    .fill(.primary)
                    .frame(width: 4, height: 4)
                    .opacity(0.85)
                    .offset(y: baseDiameter / 2 + 5)
            }
        }
        .frame(width: baseDiameter, height: baseDiameter)
        .scaleEffect(isSelected ? 1.08 : 1)
        .animation(MenuMotion.iconFocusAnimation, value: isSelected)
    }

    @ViewBuilder
    private func selectedIconHalo(angle: Double, isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: iconSize * 0.42, style: .continuous)
            .fill(.white.opacity(0.32))
            .frame(width: iconSize + 26, height: iconSize + 26)
            .blur(radius: 9)
            .opacity(isSelected ? 0.42 : 0)
            .scaleEffect(isSelected ? 1.0 : 0.72)
            .offset(
                x: isSelected ? cos(angle) * iconOrbitRadius * MenuMotion.iconSelectedPushRatio * 0.45 : 0,
                y: isSelected ? -sin(angle) * iconOrbitRadius * MenuMotion.iconSelectedPushRatio * 0.45 : 0
            )
            .allowsHitTesting(false)
            .animation(MenuMotion.iconFocusAnimation, value: isSelected)
    }

    // MARK: - Center Content

    @ViewBuilder
    private var musicProgressBoundaryLayer: some View {
        if showsMusicController, nowPlaying.duration != nil {
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                if let progress = nowPlaying.playbackProgress(at: context.date) {
                    musicProgressBoundary(progress: progress)
                }
            }
        }
    }

    private func musicProgressBoundary(progress: Double) -> some View {
        Circle()
            .trim(from: 0, to: progress)
            .stroke(
                Color.primary.opacity(0.28),
                style: StrokeStyle(lineWidth: musicProgressLineWidth, lineCap: .round)
            )
            .rotationEffect(.degrees(-90))
            .frame(width: musicProgressDiameter, height: musicProgressDiameter)
            .allowsHitTesting(false)
    }

    private var selectedAppName: String {
        if let index = appState.selectedIndex, index < appState.settings.apps.count {
            return appState.settings.apps[index].displayName
        }
        if let index = appState.selectedRecentAppIndex, index < appState.recentAppSnapshot.count {
            return appState.recentAppSnapshot[index].displayName
        }
        return ""
    }

    private var centerContentIdentity: String {
        if let index = appState.selectedIndex, index < appState.settings.apps.count {
            return "app-\(appState.settings.apps[index].id)"
        }
        if let index = appState.selectedRecentAppIndex, index < appState.recentAppSnapshot.count {
            return "recent-app-\(appState.recentAppSnapshot[index].id)"
        }

        let np = nowPlaying
        if np.hasNowPlaying && appState.settings.showMusicControl {
            return "music-\(np.trackName)-\(np.artistName)-\(np.isPlaying)"
        }

        return "settings"
    }

    @ObservedObject private var nowPlaying: NowPlayingService

    @ViewBuilder
    var centerContent: some View {
        let np = nowPlaying
        let noSelection = appState.selectedIndex == nil && appState.selectedRecentAppIndex == nil
        let hasMusic = np.hasNowPlaying && appState.settings.showMusicControl

        ZStack {
            // 状态 1: 无音乐 + 未选中 → 齿轮
            if noSelection && !hasMusic {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: centerSettingsIconSize, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .transition(MenuMotion.centerContentTransition)
            }

            // 状态 2: 有音乐 + 未选中 → 音乐控制器
            if noSelection && hasMusic {
                musicController
                    .transition(MenuMotion.centerContentTransition)
            }

            // 状态 3: 选中应用 → 应用名
            if !noSelection {
                Text(selectedAppName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .dokCapsuleGlass()
                    .transition(MenuMotion.centerContentTransition)
            }
        }
        .animation(MenuMotion.centerAnimation, value: centerContentIdentity)
    }

    // MARK: - Music Controller

    @ViewBuilder
    private var musicController: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: musicVerticalGap)

            musicArtwork

            Spacer().frame(height: musicVerticalGap * 0.75)

            // 曲名 - 歌手
            Group {
                if nowPlaying.trackName.isEmpty {
                    Text(Loc.string("music.placeholder"))
                        .foregroundStyle(.tertiary)
                } else if nowPlaying.artistName.isEmpty {
                    Text(nowPlaying.trackName)
                        .foregroundColor(.primary)
                } else {
                    Text("\(nowPlaying.trackName) - \(nowPlaying.artistName)")
                        .foregroundColor(.primary)
                }
            }
            .font(.system(size: musicTitleFontSize, weight: .medium))
            .lineLimit(1)
            .frame(width: musicControllerWidth)

            Spacer().frame(height: musicVerticalGap)

            HStack(spacing: musicControlSpacing) {
                Image(systemName: "backward.fill")
                    .font(.system(size: musicSecondaryControlSize))
                    .foregroundStyle(.secondary)

                Image(systemName: nowPlaying.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: musicPrimaryControlSize))
                    .foregroundStyle(.primary)

                Image(systemName: "forward.fill")
                    .font(.system(size: musicSecondaryControlSize))
                    .foregroundStyle(.secondary)
            }

            Spacer().frame(height: musicVerticalGap)

            // 设置齿轮
            Image(systemName: "gearshape.fill")
                .font(.system(size: 12.5 * centerMusicControlScale, weight: .medium))
                .foregroundStyle(.quaternary)
        }
        .allowsHitTesting(false)
    }

    private var musicArtwork: some View {
        ZStack {
            if let art = nowPlaying.albumArt {
                Image(nsImage: art)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: musicArtworkSize, height: musicArtworkSize)
                    .clipShape(RoundedRectangle(cornerRadius: musicArtworkCornerRadius, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: musicArtworkCornerRadius, style: .continuous)
                    .fill(.quaternary)
                    .frame(width: musicArtworkSize, height: musicArtworkSize)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 24 * centerMusicControlScale, weight: .medium))
                            .foregroundStyle(.tertiary)
                    )
            }
        }
        .frame(width: musicArtworkSize, height: musicArtworkSize)
    }

    // MARK: - Selection

    private func handleSelectionChange(_ newIndex: Int?) {
        if let index = newIndex {
            let target = angleForIndex(index)
            if !showWedge {
                wedgeAngle = target
                withAnimation(.easeOut(duration: 0.08)) {
                    showWedge = true
                }
            } else {
                let delta = normalizedAngleDelta(from: wedgeAngle, to: target)
                withAnimation(MenuMotion.wedgeSelectionAnimation) {
                    wedgeAngle += delta
                }
            }
        } else {
            withAnimation(.easeOut(duration: 0.1)) {
                showWedge = false
            }
        }
    }
}
