#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
VIEW_SOURCE = ROOT / "Sources" / "Arcly" / "ArclyWheelView.swift"
WINDOW_SOURCE = ROOT / "Sources" / "Arcly" / "ArclyWheelWindow.swift"


def require(source: str, needle: str, reason: str) -> None:
    if needle not in source:
        raise AssertionError(f"Missing {reason}: {needle}")


def forbid(source: str, needle: str, reason: str) -> None:
    if needle in source:
        raise AssertionError(f"Forbidden {reason}: {needle}")


def main() -> None:
    source = VIEW_SOURCE.read_text()
    window_source = WINDOW_SOURCE.read_text()

    requirements = [
        ("enum MenuMotion", "named motion constants shared by view and window"),
        ("static let contentAppearDuration: Double = 0.11", "crisp content-only appear timing"),
        ("static let contentDismissDuration: Double = 0.08", "crisp content-only dismiss timing"),
        ("static let dismissOrderOutDelay: Double = 0.09", "short window occupancy after dismissal"),
        ("static let iconFocusResponse: Double = 0.18", "icon focus timing"),
        ("static let centerSwapResponse: Double = 0.16", "center content swap timing"),
        ("static var wedgeSelectionAnimation: Animation", "fast plain selected wedge movement"),
        ("static let iconSelectedScale: CGFloat = 1.07", "restrained selected icon scale"),
        ("static let iconSelectedPushRatio: CGFloat = 0.018", "radial icon float ratio"),
        ("static let selectedDotScale: CGFloat = 1.62", "selected running dot breath"),
        ("private var materialOverlayLayers", "material overlays remain a stable surface"),
        (".scaleEffect(appState.isMenuVisible ? 1 : 0.975)", "restrained content-only entry scale"),
        (".opacity(appState.isMenuVisible ? 1 : 0)", "content-only opacity transition"),
        ("let pushDist = iconOrbitRadius * MenuMotion.iconSelectedPushRatio", "radius-aware selected icon push"),
        (".scaleEffect(isSelected ? MenuMotion.iconSelectedScale : 1.0)", "selected icon focus scale"),
        (".scaleEffect(isSelected ? MenuMotion.selectedDotScale : 1.0)", "selected dot breathing"),
        ("selectedIconHalo(angle: angle, isSelected: isSelected)", "subtle selected icon halo"),
        ("struct WedgeShape: Shape", "plain selected wedge shape"),
        ("var animatableData: Double", "plain wedge only animates angle if SwiftUI interpolates it"),
        ("@State private var wedgeAngle: Double = 90", "selected wedge angle state"),
        ("@State private var showWedge: Bool = false", "selected wedge visibility state"),
        ("private var selectedWedgeLayer", "selected wedge is isolated as a dedicated animated layer"),
        ("WedgeShape(", "selected wedge uses the plain shape"),
        ("sliceAngle: sliceAngleDeg", "selected wedge uses fixed sector width"),
        ("innerRadius: centerLensRadius + 3", "selected wedge stays outside the scaled center lens"),
        ("private func normalizedAngleDelta(from current: Double, to target: Double) -> Double", "selected wedge uses shortest path between sectors"),
        ("let delta = normalizedAngleDelta(from: wedgeAngle, to: target)", "selected wedge computes smooth sector travel"),
        ("withAnimation(MenuMotion.wedgeSelectionAnimation)", "selected wedge moves with a named fast animation"),
        ("wedgeAngle += delta", "selected wedge animates from the previous sector instead of jumping"),
        ("private var centerContentIdentity: String", "center content identity"),
        ("MenuMotion.centerContentTransition", "center content cross-fade transition"),
        ("private var centerControlScale: CGFloat", "center controls scale with menu size"),
        ("iconOrbitRadius / 130", "center controls follow ring radius"),
        ("private var musicArtworkBaseSize: CGFloat { 58 }", "album artwork keeps a tuned base size"),
        ("private var musicArtworkSize: CGFloat { musicArtworkBaseSize * centerMusicControlScale }", "album artwork scales with the center controls"),
        ("private var centerSettingsIconSize: CGFloat", "settings gear scales with center controls"),
        ("private var musicSecondaryControlSize: CGFloat", "secondary music button size"),
        ("private var musicPrimaryControlSize: CGFloat", "primary music button size"),
        ("private var musicControlSpacing: CGFloat", "music control spacing"),
        ("HStack(spacing: musicControlSpacing)", "scaled music control spacing applied"),
        (".font(.system(size: musicSecondaryControlSize))", "scaled previous and next music buttons"),
        (".font(.system(size: musicPrimaryControlSize))", "scaled play pause music button"),
    ]

    for needle, reason in requirements:
        require(source, needle, reason)

    window_requirements = [
        ("self.appState.isMenuVisible = false", "hidden initial visible state before showing window"),
        ("self.orderFrontRegardless()", "desktop-Space-safe window presentation"),
        ("DispatchQueue.main.async", "deferred appear animation trigger"),
        ("withAnimation(MenuMotion.menuAnimation(isVisible: true))", "animated visible-state flip"),
        ("self.appState.isMenuVisible = true", "visible state set after presentation"),
        ("MenuMotion.dismissOrderOutDelay", "order-out delayed until dismiss animation is visible"),
        ("private var centerMusicControlScale: CGFloat", "center music hit zones scale with controls"),
        ("appState.settings.menuRadius / 130", "hit zones follow ring radius"),
        ("let scale = centerMusicControlScale", "scaled music hit zone calculations"),
    ]

    for needle, reason in window_requirements:
        require(window_source, needle, reason)

    forbid(source, ".id(centerContentIdentity)", "center content forced rebuild")
    forbid(source, "revealMask", "synthetic expanding glass animation")
    forbid(source, ".delay(min(Double(index)", "staggered icon entry that makes the wheel feel assembled")
    forbid(source, ".blur(radius: appState.isMenuVisible ? 0 : MenuMotion.menuHiddenBlur)", "whole-wheel blur that changes material brightness")
    forbid(source, "LiquidSelectionShape", "rejected liquid selection animation")
    forbid(source, "LiquidMeniscusShape", "rejected target-side liquid meniscus")
    forbid(source, "wedgeLeadingPull", "rejected leading-pull liquid state")
    forbid(source, "wedgeInnerLag", "rejected inner-lag liquid state")
    forbid(source, "wedgeRadialBulge", "rejected radial-bulge liquid state")
    forbid(source, "wedgeMeniscus", "rejected meniscus liquid state")
    forbid(source, "wedgeSliceScale", "rejected wedge compression animation")
    forbid(source, "wedgeBloom", "rejected wedge bloom animation")
    forbid(source, "wedgePulseToken", "rejected delayed liquid animation token")
    forbid(source, "displayedSelectedIndex", "rejected delayed center selection state")
    forbid(source, "centerSelectionToken", "rejected delayed center swap token")
    forbid(source, "reboundWedge", "slow selected wedge tail rebound")
    forbid(source, "wedgeTrailOpacity", "old-position tail animation that lingers after travel")
    forbid(source, "WedgeBridgeShape", "phantom bridge selection animation")
    forbid(source, "LiquidDropShape", "separate liquid layer that can drift out of sync")
    forbid(source, "liquidDropOpacity", "separate liquid layer opacity state")
    forbid(source, "let direction = delta >= 0 ? 1.0 : -1.0", "angle-space direction that reads opposite to pointer travel")

    print("Liquid motion contract passed.")


if __name__ == "__main__":
    main()
