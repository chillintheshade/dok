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

enum ArclyGlassMaterial {
    static let tintBase: Double = 0.03
    static let tintRange: Double = 0.14
    static let minimumMenuOpacity: Double = 0.15

    static func intensity(for menuOpacity: Double) -> Double {
        let clamped = min(max(menuOpacity, minimumMenuOpacity), 1)
        return (clamped - minimumMenuOpacity) / (1 - minimumMenuOpacity)
    }
}

struct NativeGlassSamplingLayer: NSViewRepresentable {
    let cornerRadius: CGFloat
    let intensity: Double

    func makeNSView(context: Context) -> NSGlassEffectView {
        let glass = NSGlassEffectView()
        applyMaterial(to: glass)
        return glass
    }

    func updateNSView(_ glass: NSGlassEffectView, context: Context) {
        applyMaterial(to: glass)
    }

    private func applyMaterial(to glass: NSGlassEffectView) {
        let clampedIntensity = min(max(intensity, 0), 1)
        glass.style = .clear
        glass.cornerRadius = cornerRadius
        // Keep the native compositor fully active. Density changes through tint,
        // matching Control Center instead of fading the entire glass surface.
        glass.alphaValue = 1
        glass.tintColor = NSColor.black.withAlphaComponent(
            CGFloat(ArclyGlassMaterial.tintBase + clampedIntensity * ArclyGlassMaterial.tintRange)
        )
        glass.clipsToBounds = true
        glass.layer?.cornerRadius = cornerRadius
        glass.layer?.cornerCurve = .continuous
        glass.layer?.masksToBounds = true
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

// MARK: - ArclyWheelView

struct ArclyWheelView: View {
    @ObservedObject var appState: AppState
    var onAppSelected: ((AppItem) -> Void)?
    var onSettingsTapped: (() -> Void)?

    static let windowSize: CGFloat = 480

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
        ArclyGlassMaterial.intensity(for: appState.settings.menuOpacity)
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
                innerRadius: innerRadius + 3,
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
        return ""
    }

    private var centerContentIdentity: String {
        if let index = appState.selectedIndex, index < appState.settings.apps.count {
            return "app-\(appState.settings.apps[index].id)"
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
        let noSelection = appState.selectedIndex == nil
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
                    .glassEffect(.regular, in: .capsule)
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
