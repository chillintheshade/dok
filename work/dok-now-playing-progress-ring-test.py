#!/usr/bin/env python3
"""播放进度环契约：perl 数据进入服务层，视图本地外推并按需隐藏。"""
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SERVICE = (ROOT / "Sources" / "dok" / "NowPlayingService.swift").read_text()
VIEW = (ROOT / "Sources" / "dok" / "DokWheelView.swift").read_text()


def main() -> None:
    for field in ["duration", "elapsedTime", "progressTimestamp", "playbackRate"]:
        assert f"@Published private(set) var {field}" in SERVICE, f"missing published {field}"

    for key in ['payload["duration"]', 'payload["elapsedTime"]',
                'payload["timestamp"]', 'payload["playbackRate"]']:
        assert key in SERVICE, f"perl adapter field is not parsed: {key}"

    assert "func playbackProgress(at now: Date = Date()) -> Double?" in SERVICE
    assert "now.timeIntervalSince(progressTimestamp)" in SERVICE
    track_changed_block = SERVICE.split("let trackChanged = trackName != snapshot.title", 1)[1].split(
        "trackName = snapshot.title", 1
    )[0]
    assert "if trackChanged" in track_changed_block
    assert "clearProgress()" in track_changed_block
    assert "clearProgress()\n        applyArtwork" not in SERVICE, (
        "progress must be applied from the new snapshot before artwork handling"
    )

    # 播放中逐帧外推；暂停或收起时停帧。
    assert "TimelineView(.animation(minimumInterval: nil," in VIEW, "the view should extrapolate every frame"
    assert "paused: !nowPlaying.isPlaying || !interaction.isMenuVisible" in VIEW
    assert "musicProgressBoundaryLayer" in VIEW
    # 内圆与外圈的交接处就是底轨，不另画线；已播放段由系统透明液态玻璃渲染（原生边缘高光）。
    ring = VIEW.split("private func musicProgressBoundary(progress: Double) -> some View {", 1)[1].split("private var centerLabelCandidateID", 1)[0]
    assert ".glassEffect(.clear.tint(MenuMotion.progressWaterTint)," in ring, "a faint cool wash lifts the dark rim"
    assert "static let progressWaterTint = Color(red: 0.86, green: 0.94, blue: 1.0).opacity(0.16)" in VIEW, "water, not white frost"
    assert "in: ProgressArcBand(progress: progress, width: width, maxWidth: maxWidth)" in ring
    # 悬停像水被碰了一下：宽度可动画，弹簧回弹；中线位置不随宽度移动。
    assert "AnimatablePair(progress, width)" in VIEW
    assert ".spring(response: 0.38, dampingFraction: 0.42), value: hovered" in ring
    assert "maxWidth * 1.45 / 2" in VIEW
    assert "static let progressGlassHoverWidth: CGFloat = 3.1" in VIEW
    # 受光一侧断续的水面反光
    assert "private func waterGlint(" in VIEW and ".offset(x: -0.6, y: -0.6)" in VIEW
    # 背光一侧的焦散：光穿过水聚在背面
    assert "waterCaustic(progress: progress, maxWidth: maxWidth)" in ring
    assert "private func waterCaustic(" in VIEW and ".offset(x: 0.6, y: 0.6)" in VIEW
    # 像一股水：尾部细、主体匀、前端鼓成水珠；单条闭合轮廓，不用路径并集。
    assert "struct ProgressArcBand: Shape" in VIEW
    assert "let headWidth = width * 1.45" in VIEW and "if toHead < 10 {" in VIEW
    assert "0.6 + 0.4 * tail * tail * (3 - 2 * tail)" in VIEW, "the tail tapers in"
    assert "static let progressInset: CGFloat = 0" in VIEW, "the band straddles the lens boundary"
    assert "static let progressGlassWidth: CGFloat = 2.5" in VIEW
    assert ".blur(" not in ring
    assert "DEBUG-PIN" not in VIEW
    assert "if showsMusicController, nowPlaying.duration != nil" in VIEW, (
        "missing progress must hide the ring"
    )
    assert "showsCenterBoundary" not in VIEW, "the center boundary must be removed in every state"
    assert "colorScheme == .dark ? 0.12 : 0.06" not in VIEW, (
        "the idle gear state must not restore the center boundary"
    )
    assert "musicProgressDotSize" not in VIEW, "the progress head dot must be removed"
    assert "Color.primary.opacity(0.40)" not in VIEW, "the progress head dot must not be drawn"
    assert "Color.primary.opacity(0.70)" not in VIEW, "the old heavy progress arc must be removed"
    assert "Color.primary.opacity(0.88)" not in VIEW, "the old heavy progress head must be removed"
    assert "musicArtworkWithProgress" not in VIEW, "the artwork must no longer own the progress ring"
    assert "musicProgressTick" not in VIEW, "the ring must not add tick marks"
    assert "musicProgressEndLine" not in VIEW, "the ring must not add endpoint lines"

    print("Now-playing progress ring contract passed.")


if __name__ == "__main__":
    main()
