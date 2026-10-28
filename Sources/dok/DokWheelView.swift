import SwiftUI
import AppKit

/// Visual feedback only. The window retains ownership of all hit testing and clicks.
private struct CenterControlHoverFeedback: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let active: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(active && !reduceMotion ? 1.10 : 1)
            .offset(y: active && !reduceMotion ? -1 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: active)
    }
}

/// 设置齿轮平时很淡，悬停时加深到次要文字色，并带与其他中心控件一致的轻微放大。
private struct SettingsGearStyle: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let resting: HierarchicalShapeStyle
    let hovered: Bool

    func body(content: Content) -> some View {
        content
            .foregroundStyle(hovered ? .secondary : resting)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hovered)
            .modifier(CenterControlHoverFeedback(active: hovered))
    }
}

/// 上一首/下一首的状态反馈：播放器切歌期间显示为不可点（无悬停高亮），
/// 按下被接受时轻缩回弹，被拒绝时左右轻晃。命中判定仍由窗口负责。
private struct SkipButtonFeedback: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let direction: NowPlayingService.SkipDirection
    let locked: Bool
    let hovered: Bool
    let event: NowPlayingService.SkipEvent?

    @State private var pressScale: CGFloat = 1
    @State private var shakes: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .modifier(CenterControlHoverFeedback(active: hovered && !locked))
            .opacity(locked ? MenuMotion.skipLockedOpacity : 1)
            .scaleEffect(pressScale)
            .modifier(ShakeEffect(shakes: shakes))
            // 上锁要快；解锁与新曲目滑入同一刻、同一条曲线，二者一起落定。
            .animation(locked ? .easeOut(duration: 0.15) : MenuMotion.trackPushAnimation, value: locked)
            .onChange(of: event) { event in
                guard let event, event.direction == direction, !reduceMotion else { return }
                if event.accepted {
                    withAnimation(.easeOut(duration: 0.07)) { pressScale = 0.84 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) { pressScale = 1 }
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.24)) { shakes += 1 }
                }
            }
    }
}

/// 单行文字：放得下时居中静止；放不下时停顿后向左滑到末尾完整露出，停一下再滑回开头，
/// 然后停住，不循环。只在轮盘可见时播放，每张新卡片、每次唤出各播放一次。
/// 两侧渐隐由外层遮罩提供，静止时文字从 inset 处开始，开头不被淡掉。
/// 文字宽度在首帧之前同步算出：若等排版后再量，新卡片推入时会先按短曲名居中、下一帧才跳成长曲名排版。
private struct OverflowTitle: View {
    let text: String
    let fontSize: CGFloat
    let width: CGFloat
    let inset: CGFloat
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var offset: CGFloat = 0

    private var textWidth: CGFloat {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    private static let speed: CGFloat = 30
    private static let minimumTravel: Double = 0.6
    private static let startDelay: Double = 0.6
    private static let endPause: Double = 0.3

    private var overflow: CGFloat { textWidth - (width - inset * 2) }

    var body: some View {
        Group {
            if overflow > 0 && !reduceMotion {
                label
                    .fixedSize()
                    .offset(x: inset + offset)
                    .frame(width: width, alignment: .leading)
            } else {
                label
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: width)
            }
        }
        .task(id: "\(text)|\(isActive)|\(overflow > 0)|\(reduceMotion)") { await reveal() }
    }

    private var label: some View {
        Text(text)
            .font(.system(size: fontSize, weight: .medium))
            .foregroundColor(.primary)
    }

    @MainActor
    private func reveal() async {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { offset = 0 }
        guard isActive, overflow > 0, !reduceMotion else { return }

        let travel = max(Double(overflow / Self.speed), Self.minimumTravel)
        let stops: [(delay: Double, target: CGFloat)] = [
            (Self.startDelay, -overflow),       // 向左，直到末尾的歌手名完整露出
            (travel + Self.endPause, 0),        // 停一下，再推回开头
        ]
        for stop in stops {
            try? await Task.sleep(nanoseconds: UInt64(stop.delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: travel)) { offset = stop.target }
        }
    }
}

/// 每增加 1 晃动两个来回，整数值时回到原位，因此可重复触发。
private struct ShakeEffect: GeometryEffect {
    var shakes: CGFloat
    var amplitude: CGFloat = 2.5

    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let phase = shakes - shakes.rounded(.down)
        let x = sin(phase * .pi * 4) * amplitude * (1 - phase)
        return ProjectionTransform(CGAffineTransform(translationX: x, y: 0))
    }
}

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
        if #available(macOS 27.0, *) { return 1 }
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

    func apply(cornerRadius: CGFloat, intensity: Double, circular: Bool = false) {
        let clampedIntensity = min(max(intensity, 0), 1)
        let tintAlpha = DokGlassMaterial.tintBase + clampedIntensity * DokGlassMaterial.tintRange

        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        effectView.layer?.cornerRadius = cornerRadius
        effectView.layer?.cornerCurve = .continuous
        effectView.layer?.masksToBounds = true
        if circular {
            layer?.cornerCurve = .circular
            effectView.layer?.cornerCurve = .circular
        }
        tintView.layer?.backgroundColor = NSColor.black.withAlphaComponent(tintAlpha).cgColor
    }
}

struct NativeGlassSamplingLayer: NSViewRepresentable {
    let cornerRadius: CGFloat
    let intensity: Double
    var circular: Bool = false

    func makeNSView(context: Context) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            applyMaterial(to: glass)
            return glass
        }

        let glass = CompatibilityGlassEffectView()
        glass.apply(cornerRadius: cornerRadius, intensity: intensity, circular: circular)
        return glass
    }

    func updateNSView(_ view: NSView, context: Context) {
        if #available(macOS 26.0, *), let glass = view as? NSGlassEffectView {
            applyMaterial(to: glass)
        } else if let glass = view as? CompatibilityGlassEffectView {
            glass.apply(cornerRadius: cornerRadius, intensity: intensity, circular: circular)
        }
    }

    @available(macOS 26.0, *)
    private func applyMaterial(to glass: NSGlassEffectView) {
        glass.cornerRadius = cornerRadius
        if #available(macOS 27.0, *) {
            // Use native regular glass so macOS controls its material appearance.
            glass.style = .regular
            glass.alphaValue = 1
        } else {
            glass.style = .clear
            let clampedIntensity = min(max(intensity, 0), 1)
            glass.alphaValue = DokGlassMaterial.minimumMenuOpacity
                + (1 - DokGlassMaterial.minimumMenuOpacity) * clampedIntensity
        }
        glass.tintColor = nil
        // Let the native glass shape its own edge for both the wheel and satellites.
        // A second bounds mask clips the native edge at the cardinal points.
        glass.clipsToBounds = false
        glass.layer?.masksToBounds = false
        glass.layer?.cornerRadius = 0
    }
}

/// 已播放的一段“水流”：从 12 点顺时针到 progress，作为液态玻璃的形状。
/// 像一股流动的水：尾部细、身子匀、前端在表面张力下鼓成一颗圆润的水珠。
/// 轮廓是一条闭合路径（外沿 → 前端半圆 → 内沿 → 尾端半圆），每帧计算也很轻。
struct ProgressArcBand: Shape {
    var progress: Double
    /// 水流主体的宽度；尾部和水珠按比例计算。可动画，悬停时随弹簧鼓起再回弹。
    var width: CGFloat
    /// 外框里给最宽状态留的边距，保证宽度变化时水流中线不动，始终在内外圈交接处。
    var maxWidth: CGFloat

    var animatableData: AnimatablePair<Double, CGFloat> {
        get { AnimatablePair(progress, width) }
        set { progress = newValue.first; width = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let sweep = 2 * Double.pi * min(max(progress, 0), 1)
        guard sweep > 0 else { return Path() }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let headWidth = width * 1.45
        let radius = min(rect.width, rect.height) / 2 - maxWidth * 1.45 / 2
        let length = Double(radius) * sweep
        let start = -Double.pi / 2

        // 沿弧长的宽度：尾部 12pt 内从细到匀，前端 10pt 内鼓成水珠（余弦隆起）。
        func widthAt(_ distance: Double) -> CGFloat {
            let tail = min(distance / 12, 1)
            var w = Double(width) * (0.6 + 0.4 * tail * tail * (3 - 2 * tail))
            let toHead = length - distance
            if toHead < 10 {
                let bump = 0.5 - 0.5 * cos(.pi * (1 - toHead / 10))
                w += Double(headWidth - width) * bump
            }
            return CGFloat(w)
        }
        func point(_ angle: Double, _ r: CGFloat) -> CGPoint {
            CGPoint(x: center.x + r * CGFloat(cos(angle)), y: center.y + r * CGFloat(sin(angle)))
        }

        let steps = max(2, Int(sweep / (Double.pi / 90)))
        var outer: [CGPoint] = [], inner: [CGPoint] = []
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let angle = start + sweep * t
            let half = widthAt(length * t) / 2
            outer.append(point(angle, radius + half))
            inner.append(point(angle, radius - half))
        }
        let end = start + sweep
        var path = Path()
        path.move(to: outer[0])
        outer.dropFirst().forEach { path.addLine(to: $0) }
        // 前端水珠：外沿 → 前方 → 内沿
        path.addArc(center: point(end, radius), radius: widthAt(length) / 2,
                    startAngle: .radians(end), endAngle: .radians(end + .pi), clockwise: false)
        inner.reversed().forEach { path.addLine(to: $0) }
        // 尾端：内沿 → 后方 → 外沿
        path.addArc(center: point(start, radius), radius: widthAt(0) / 2,
                    startAngle: .radians(start + .pi), endAngle: .radians(start + 2 * .pi), clockwise: false)
        path.closeSubpath()
        return path
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
    /// 名字要停留这么久才出现：鼠标只是扫过时中心不闪；已经显示时换到相邻一项则立刻切换。
    static let centerLabelDwell: Double = 0.15
    /// 进度环与中心圆的边重合，只有一个圆。
    static let progressInset: CGFloat = 0
    /// 已播放弧带的玻璃宽度，正好跨在内圆与外圈的交接线上。
    static let progressGlassWidth: CGFloat = 2.5
    /// 悬停时只鼓起一点（配合弹簧回弹），不再大幅加粗。
    static let progressGlassHoverWidth: CGFloat = 3.1
    /// 玻璃上一层极淡、几乎无色的冷调（0.70/0.90 的青读起来偏青了）：冲淡细条上原生玻璃的暗边，又让它读起来是清凉的水，而不是白色磨砂。
    static let progressWaterTint = Color(red: 0.86, green: 0.94, blue: 1.0).opacity(0.16)
    static let skipLockedOpacity: Double = 0.3
    /// 卡片推入时两侧边缘的渐隐宽度，避免被中心区域硬切。
    static let trackPushEdgeFade: CGFloat = 14

    /// 旧卡片推出、新卡片推入共用的曲线：起步快、落定柔。
    static var trackPushAnimation: Animation {
        .timingCurve(0.25, 0.85, 0.25, 1, duration: 0.46)
    }

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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var appState: AppState
    var onAppSelected: ((AppItem) -> Void)?
    var onSettingsTapped: (() -> Void)?

    static let windowSize: CGFloat = 640

    @State private var wedgeAngle: Double = 90
    @State private var showWedge: Bool = false
    /// 中心正在显示名字的项目。只有文件、网址、按键动作会有，并且要停留一下才出现。
    @State private var centerLabelItemID: UUID?
    @State private var centerLabelTask: DispatchWorkItem?

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
    /// 进度环比玻璃边缘往里收一点，两条边不挤在一起。
    private var musicProgressDiameter: CGFloat { centerLensRadius * 2 - MenuMotion.progressInset * 2 }
    private var musicTitleFontSize: CGFloat { 11.5 * centerMusicControlScale }
    private var musicSecondaryControlSize: CGFloat { 15 * centerMusicControlScale }
    private var musicPrimaryControlSize: CGFloat { 22 * centerMusicControlScale }
    private var musicControlSpacing: CGFloat { 18 * centerMusicControlScale }
    private var musicVerticalGap: CGFloat { 8 * centerMusicControlScale }
    private var musicControllerWidth: CGFloat {
        min(min(max(iconOrbitRadius * 1.28, 142), 230), max(centerLensRadius * 2 - 18, 96))
    }
    private var showsMusicController: Bool {
        centerLabelItem == nil
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
        .onChange(of: centerLabelCandidateID) { id in
            updateCenterLabel(id)
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
            .fill(
                RadialGradient(
                    stops: [
                        .init(color: .primary.opacity(0), location: 0),
                        .init(color: .primary.opacity(0.032), location: 0.35),
                        .init(color: .primary.opacity(0.032), location: 0.65),
                        .init(color: .primary.opacity(0), location: 1)
                    ],
                    center: .center,
                    startRadius: centerLensRadius,
                    endRadius: outerRadius
                )
            )
            .frame(width: outerRadius * 2, height: outerRadius * 2)
            .blur(radius: 6)
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
                intensity: glassMaterialIntensity,
                circular: true
            )
            .frame(width: baseDiameter, height: baseDiameter)
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

            if let badge = appState.notificationBadge(for: app) {
                SlotNotificationBadge(text: badge, iconSize: satelliteIconSize)
                    .offset(x: baseDiameter * 0.31, y: -baseDiameter * 0.31)
            }

            if app.isRunning {
                Circle()
                    .fill(.primary)
                    .frame(width: 4, height: 4)
                    .opacity(0.85)
                    .offset(y: baseDiameter / 2 - 5)
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
            // 播放中逐帧推进；暂停或轮盘收起时停帧，不耗电。
            TimelineView(.animation(minimumInterval: nil,
                                    paused: !nowPlaying.isPlaying || !appState.isMenuVisible)) { context in
                if let progress = nowPlaying.playbackProgress(at: context.date) {
                    musicProgressBoundary(progress: progress)
                }
            }
        }
    }

    /// 内圆与外圈的交接处本身就是底轨，不另画线。进度是一股液态的水：形状是尾细、前端鼓成水珠的水流，
    /// 由系统自己的透明液态玻璃 `.clear` 来渲染。玻璃上一层极淡的冷青，冲淡原生玻璃在细条上显出的暗边，
    /// 让它通透而清凉；受光一侧（左上）有一道细的反光，背光一侧（右下）有一道柔的焦散——光穿过水后聚在背面，
    /// 这是水与玻璃、塑料最不一样的地方。
    /// 悬停不是生硬地加粗，而是像水被碰了一下：轻轻鼓起，弹簧稍冲过头再回稳。
    /// macOS 26 以下没有液态玻璃，退回一道细高光弧。
    @ViewBuilder
    private func musicProgressBoundary(progress: Double) -> some View {
        let hovered = appState.centerControlHover == .progress
        let width = hovered ? MenuMotion.progressGlassHoverWidth : MenuMotion.progressGlassWidth
        let maxWidth = MenuMotion.progressGlassHoverWidth
        let side = musicProgressDiameter + maxWidth * 1.45
        Group {
            if #available(macOS 26.0, *) {
                ZStack {
                    Color.clear
                        .glassEffect(.clear.tint(MenuMotion.progressWaterTint),
                                     in: ProgressArcBand(progress: progress, width: width, maxWidth: maxWidth))
                    waterCaustic(progress: progress, maxWidth: maxWidth)
                    waterGlint(progress: progress, side: side, maxWidth: maxWidth)
                }
            } else {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 1, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .blendMode(.plusLighter)
                    .padding(maxWidth * 1.45 / 2)
            }
        }
        .frame(width: side, height: side)
        .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.42), value: hovered)
        .allowsHitTesting(false)
    }

    /// 水面的反光：沿水流中线、整体向光源（左上）偏一点，于是左上段落在水流外沿、右下段落在内沿，
    /// 正好是朝光的那一侧。只在受光处出现，其余位置为零，所以是断续的几段，而不是一整圈白线。
    private func waterGlint(progress: Double, side: CGFloat, maxWidth: CGFloat) -> some View {
        Circle()
            .trim(from: 0, to: progress)
            .stroke(Self.waterGlintLighting, style: StrokeStyle(lineWidth: 0.6, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .padding(maxWidth * 1.45 / 2)
            .offset(x: -0.6, y: -0.6)
            .blendMode(.plusLighter)
    }

    /// 位置从 3 点钟方向顺时针（经 -90° 旋转补偿）。只有左上一段，其他地方没有。
    private static let waterGlintLighting = AngularGradient(
        stops: [
            (0.000, 0.0), (0.540, 0.0), (0.600, 0.85), (0.640, 0.9), (0.700, 0.0),
            (1.000, 0.0),
        ].map { Gradient.Stop(color: .white.opacity($0.1), location: $0.0) },
        center: .center,
        angle: .degrees(90)
    )

    /// 焦散：光从左上射进水里，在背光的一侧聚成一道柔亮。与反光相反地向右下偏，于是落在右下段的外沿；
    /// 比反光宽、淡、带一点青，渐入渐出很长，读起来是透出来的光，而不是画上去的线。
    private func waterCaustic(progress: Double, maxWidth: CGFloat) -> some View {
        Circle()
            .trim(from: 0, to: progress)
            .stroke(Self.waterCausticLighting, style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .padding(maxWidth * 1.45 / 2)
            .offset(x: 0.6, y: 0.6)
            .blendMode(.plusLighter)
    }

    /// 右下一段（约 4 点半方向）最亮，两侧很长地淡出。
    private static let waterCausticLighting = AngularGradient(
        stops: [
            (0.000, 0.0), (0.030, 0.0), (0.110, 0.34), (0.150, 0.34), (0.250, 0.0),
            (1.000, 0.0),
        ].map { Gradient.Stop(color: Color(red: 0.94, green: 0.98, blue: 1.0).opacity($0.1), location: $0.0) },
        center: .center,
        angle: .degrees(90)
    )

    /// 悬停项目里需要名字的那一个。应用和最近应用看图标就认得，不显示名字，中心保持音乐控制或齿轮。
    private var centerLabelCandidateID: UUID? {
        guard let index = appState.selectedIndex, index < appState.settings.apps.count else { return nil }
        let item = appState.settings.apps[index]
        return item.itemType == .app ? nil : item.id
    }

    private var centerLabelItem: AppItem? {
        guard let id = centerLabelItemID else { return nil }
        return appState.settings.apps.first { $0.id == id }
    }

    private func updateCenterLabel(_ id: UUID?) {
        centerLabelTask?.cancel()
        centerLabelTask = nil
        guard let id else {
            centerLabelItemID = nil
            return
        }
        if centerLabelItemID != nil {
            centerLabelItemID = id
            return
        }
        let task = DispatchWorkItem { centerLabelItemID = id }
        centerLabelTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + MenuMotion.centerLabelDwell, execute: task)
    }

    private var centerContentIdentity: String {
        if let item = centerLabelItem {
            return "label-\(item.id)"
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
        let labelItem = centerLabelItem
        let noSelection = labelItem == nil
        let hasMusic = np.hasNowPlaying && appState.settings.showMusicControl

        ZStack {
            // 状态 1: 无音乐 + 未选中 → 齿轮
            if noSelection && !hasMusic {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: centerSettingsIconSize, weight: .medium))
                    .modifier(SettingsGearStyle(resting: .tertiary,
                                                hovered: appState.centerControlHover == .settings))
                    .transition(MenuMotion.centerContentTransition)
            }

            // 状态 2: 有音乐 + 未选中 → 音乐控制器
            if noSelection && hasMusic {
                musicController
                    .transition(MenuMotion.centerContentTransition)
            }

            // 状态 3: 停在文件、网址、按键动作上 → 名字 + 一行区分信息
            if let labelItem {
                centerLabel(for: labelItem)
                    .transition(MenuMotion.centerContentTransition)
            }
        }
        .animation(MenuMotion.centerAnimation, value: centerContentIdentity)
    }

    /// 第二行让同类项目分得开：文件看所在文件夹，网址看域名，按键动作看组合键。
    private func centerLabel(for item: AppItem) -> some View {
        VStack(spacing: 5) {
            Text(item.displayName)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
            centerLabelDetail(for: item)
        }
        .frame(maxWidth: musicControllerWidth - 28)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .dokCapsuleGlass()
    }

    @ViewBuilder
    private func centerLabelDetail(for item: AppItem) -> some View {
        switch item.itemType {
        case .fileOrFolder:
            let folder = URL(fileURLWithPath: item.path).deletingLastPathComponent().path
            centerLabelCaption(FileManager.default.displayName(atPath: folder))
        case .webLink:
            if let host = item.webURL?.host {
                centerLabelCaption(host.hasPrefix("www.") ? String(host.dropFirst(4)) : host)
            }
        case .keyAction:
            if let combo = item.keyCombination {
                HStack(spacing: 3) {
                    ForEach(Array(combo.keySymbols.enumerated()), id: \.offset) { _, symbol in
                        Text(symbol)
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 17, minHeight: 17)
                            .padding(.horizontal, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.6)
                            )
                    }
                }
            }
        case .app:
            EmptyView()
        }
    }

    private func centerLabelCaption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    // MARK: - Music Controller

    @ViewBuilder
    private var musicController: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: musicVerticalGap)

            // 封面与曲名随曲目整体换出：切歌时沿切歌方向滑入，按钮保持不动。
            ZStack {
                trackInfo
                    .id(trackInfoIdentity)
                    .transition(trackInfoTransition)
            }
            .frame(width: musicControllerWidth)
            .mask(trackPushMask)
            .animation(nowPlaying.trackCard?.animated == false ? nil : trackInfoAnimation,
                       value: trackInfoIdentity)

            Spacer().frame(height: musicVerticalGap)

            HStack(spacing: musicControlSpacing) {
                Image(systemName: "backward.fill")
                    .font(.system(size: musicSecondaryControlSize))
                    .foregroundStyle(.secondary)
                    .modifier(SkipButtonFeedback(
                        direction: .backward,
                        locked: nowPlaying.isSkipLocked,
                        hovered: appState.centerControlHover == .previous,
                        event: nowPlaying.skipEvent
                    ))

                Image(systemName: nowPlaying.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: musicPrimaryControlSize))
                    .foregroundStyle(.primary)
                    .modifier(CenterControlHoverFeedback(active: appState.centerControlHover == .playback))

                Image(systemName: "forward.fill")
                    .font(.system(size: musicSecondaryControlSize))
                    .foregroundStyle(.secondary)
                    .modifier(SkipButtonFeedback(
                        direction: .forward,
                        locked: nowPlaying.isSkipLocked,
                        hovered: appState.centerControlHover == .next,
                        event: nowPlaying.skipEvent
                    ))
            }

            Spacer().frame(height: musicVerticalGap)

            // 设置齿轮
            Image(systemName: "gearshape.fill")
                .font(.system(size: 12.5 * centerMusicControlScale, weight: .medium))
                .modifier(SettingsGearStyle(resting: .quaternary,
                                            hovered: appState.centerControlHover == .settings))
        }
        .allowsHitTesting(false)
    }

    private var trackInfo: some View {
        let card = nowPlaying.trackCard
        return VStack(spacing: 0) {
            musicArtwork(card?.artwork)

            Spacer().frame(height: musicVerticalGap * 0.75)

            // 曲名 - 歌手：超出宽度时向左滑到末尾再滑回，播放一次。
            if let card {
                OverflowTitle(
                    text: card.artist.isEmpty ? card.title : "\(card.title) - \(card.artist)",
                    fontSize: musicTitleFontSize,
                    width: musicControllerWidth,
                    inset: MenuMotion.trackPushEdgeFade,
                    isActive: appState.isMenuVisible
                )
            } else {
                Text(Loc.string("music.placeholder"))
                    .foregroundStyle(.tertiary)
                    .font(.system(size: musicTitleFontSize, weight: .medium))
                    .lineLimit(1)
                    .frame(width: musicControllerWidth)
            }
        }
    }

    private var trackInfoIdentity: String {
        nowPlaying.trackCard?.id.uuidString ?? "empty"
    }

    /// 推入：旧卡片与新卡片左右紧挨着一起平移，前进向左推、后退向右推，位移等于卡片宽度。
    private var trackInfoTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let width = musicControllerWidth
        let sign: CGFloat = nowPlaying.skipDirection == .forward ? 1 : -1
        return .asymmetric(
            insertion: .offset(x: width * sign),
            removal: .offset(x: -width * sign)
        )
    }

    private var trackInfoAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.2) : MenuMotion.trackPushAnimation
    }

    /// 卡片宽度的窗口，两侧渐隐。用渐变遮罩而非模糊（模糊在透明窗口里会闪）。
    private var trackPushMask: some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: MenuMotion.trackPushEdgeFade)
            Rectangle()
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: MenuMotion.trackPushEdgeFade)
        }
    }

    /// 同一张卡片的封面晚到或更换时原地交叉淡化；换曲目由整张卡片推入完成。
    private func musicArtwork(_ artwork: NSImage?) -> some View {
        ZStack {
            if let artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: musicArtworkSize, height: musicArtworkSize)
                    .clipShape(RoundedRectangle(cornerRadius: musicArtworkCornerRadius, style: .continuous))
                    .id(ObjectIdentifier(artwork))
                    .transition(.opacity)
            } else {
                RoundedRectangle(cornerRadius: musicArtworkCornerRadius, style: .continuous)
                    .fill(.quaternary)
                    .frame(width: musicArtworkSize, height: musicArtworkSize)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 24 * centerMusicControlScale, weight: .medium))
                            .foregroundStyle(.tertiary)
                    )
                    .transition(.opacity)
            }
        }
        .frame(width: musicArtworkSize, height: musicArtworkSize)
        .animation(.easeInOut(duration: 0.35), value: artwork.map(ObjectIdentifier.init))
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
