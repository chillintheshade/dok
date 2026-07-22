#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
APP_STATE = ROOT / "Sources" / "Arcly" / "AppState.swift"
APP_SOURCE = ROOT / "Sources" / "Arcly" / "ArclyApp.swift"
PIE_VIEW = ROOT / "Sources" / "Arcly" / "ArclyWheelView.swift"
SETTINGS_VIEW = ROOT / "Sources" / "Arcly" / "SettingsView.swift"
WHEEL_WINDOW = ROOT / "Sources" / "Arcly" / "ArclyWheelWindow.swift"


def require(source: str, needle: str, reason: str) -> None:
    if needle not in source:
        raise AssertionError(f"Missing {reason}: {needle}")


def forbid(source: str, needle: str, reason: str) -> None:
    if needle in source:
        raise AssertionError(f"Forbidden {reason}: {needle}")


def main() -> None:
    app_state = APP_STATE.read_text()
    app_source = APP_SOURCE.read_text()
    pie_view = PIE_VIEW.read_text()
    settings_view = SETTINGS_VIEW.read_text()
    wheel_window = WHEEL_WINDOW.read_text()

    app_state_requirements = [
        ("var menuOpacity: Double = 1.0", "default menu glass opacity"),
        ("menuOpacity = (try? c.decode(Double.self, forKey: .menuOpacity)) ?? 1.0", "opacity decoder fallback"),
    ]
    for needle, reason in app_state_requirements:
        require(app_state, needle, reason)

    pie_requirements = [
        ("enum ArclyGlassMaterial", "single finalized glass parameter set"),
        ("static let tintBase: Double = 0.03", "final native tint baseline"),
        ("static let tintRange: Double = 0.14", "final opacity-controlled tint range"),
        ("static let minimumMenuOpacity: Double = 0.15", "slider lower bound used by material mapping"),
        ("static func intensity(for menuOpacity: Double) -> Double", "shared opacity-to-material mapping"),
        ("return (clamped - minimumMenuOpacity) / (1 - minimumMenuOpacity)", "linear mapping makes 100 percent the selected final appearance"),
        ("ArclyGlassMaterial.tintBase + clampedIntensity * ArclyGlassMaterial.tintRange", "final tint keeps the selected appearance at full opacity"),
        ("struct NativeGlassSamplingLayer", "native desktop-sampling glass base"),
        ("NSGlassEffectView", "macOS 26 native Liquid Glass sampling view"),
        ("glass.style = .clear", "selected native clear style"),
        ("glass.alphaValue = 1", "native glass remains fully composited instead of fading into a flat overlay"),
        ("glass.tintColor =", "native glass density is adjusted through tint rather than whole-view alpha"),
        ("NSColor.black.withAlphaComponent", "neutral dark tint keeps wallpaper color without the milky light-mode fill"),
        ("glass.layer?.masksToBounds = true", "native glass base clips its own rounded/circular edge"),
        ("appState.settings.menuOpacity", "radial menu reads saved opacity"),
        ("nativeGlassSamplingLayer", "runtime wheel renders a native sampling base"),
        ("private var animatedWheelLayers", "animated content is separated from the native sampling base"),
        ("private var materialOverlayLayers", "tone and edge overlays share one material reveal"),
        ("glassEdgeHighlightLayer", "runtime wheel adds controlled edge highlights above native glass"),
        ("selectedWedgeLayer", "selection layer remains above the material stack"),
        ("centerContent", "content layer remains above the material stack"),
        ("iconsLayer", "icons remain above the material stack"),
        ("ControlCenterGlassEdgeLayer", "Control Center-style edge and elevation treatment"),
        (".stroke(Color.white.opacity(0.24 * strength), lineWidth: 0.55)", "single fine supplemental edge highlight"),
    ]
    for needle, reason in pie_requirements:
        require(pie_view, needle, reason)

    settings_requirements = [
        ('title: Loc.string("settings.opacity")', "opacity slider label"),
        ("value: $appState.settings.menuOpacity", "opacity slider binding"),
        ("range: 0.15...1.0", "opacity slider range with visible low end"),
        ("step: 0.05", "opacity slider step"),
        ("appState.settings.menuOpacity", "settings preview reads opacity"),
        ("NativeGlassSamplingLayer", "settings preview uses the native glass sampling base"),
        ("settingsGlassEdgeHighlightLayer", "settings preview adds controlled edge highlights"),
        ("ArclyGlassMaterial.intensity(for: appState.settings.menuOpacity)", "settings preview shares the final opacity mapping"),
    ]
    for needle, reason in settings_requirements:
        require(settings_view, needle, reason)

    forbid(app_state, "glassRefractionEnabled", "persisted glass refraction toggle")
    forbid(pie_view, "glassRefractionEnabled", "runtime glass refraction toggle")
    forbid(settings_view, "glassRefractionEnabled", "settings glass refraction toggle")
    forbid(settings_view, "玻璃折射", "user-facing glass refraction control")
    forbid(settings_view, "折射强度", "user-facing refraction strength control")
    forbid(settings_view, "refractionStrength", "hidden adjustable refraction strength setting")
    forbid(app_state, "refractionStrength", "persisted adjustable refraction strength setting")
    forbid(pie_view, "refractionStrength", "runtime adjustable refraction strength setting")
    forbid(pie_view, "glass.contentView =", "native glass must remain a sampling base, not host the wheel content")
    forbid(pie_view, ".clipShape(Circle())", "SwiftUI clipping that can crop the native glass edge")
    forbid(pie_view, "ArclyNativeGlassExperiment", "finished native style experiment selector")
    forbid(pie_view, "ARCLY_GLASS_REGULAR_STYLE", "finished regular style experiment flag")
    forbid(pie_view, "ArclyTransparencyStair", "finished transparency staircase selector")
    forbid(pie_view, "ARCLY_TRANSPARENCY_STAIR_", "finished transparency staircase flags")
    forbid(pie_view, "ControlCenterGlassToneLayer", "removed custom tone layer")
    forbid(pie_view, "glassToneMappingLayer", "removed runtime tone overlay")
    forbid(pie_view, ".shadow(color: Color.black.opacity(0.16 * strength)", "removed synthetic outer shadow")
    forbid(pie_view, "private var glassSurfaceFillOpacity", "old fake white glass fill")
    forbid(pie_view, "glassSurfaceLayer", "old fake glass surface layer")
    forbid(pie_view, "glassRefractionLayer", "old fake refraction overlay")
    forbid(pie_view, "revealMask", "synthetic expanding material reveal")
    forbid(pie_view, "CABasicAnimation(keyPath: \"transform.scale\")", "AppKit sampler scale animation")
    forbid(pie_view, ".frame(width: diameter - 7, height: diameter - 7)", "duplicate inner outer-rim stroke")
    forbid(pie_view, ".blur(radius: appState.isMenuVisible ? 0 : MenuMotion.menuHiddenBlur)", "material-changing whole-wheel blur animation")
    forbid(pie_view, ".glassEffect(.regular.interactive()", "SwiftUI glass overlay should not be the primary wheel material")
    forbid(settings_view, "private var glassSurfaceFillOpacity", "old settings fake white glass fill")
    forbid(settings_view, "settingsGlassSurfaceLayer", "old settings fake glass surface layer")
    forbid(settings_view, "settingsGlassRefractionLayer", "old settings fake refraction overlay")
    forbid(settings_view, "settingsGlassToneMappingLayer", "removed settings tone overlay")

    window_requirements = [
        ("self.alphaValue = 1", "window always presents native glass at its final density"),
        ("self.displayIfNeeded()", "window forces the native glass composition before reveal"),
        ("self.orderFrontRegardless()", "wheel can present in the desktop-only Space without activating another app"),
        (".stationary", "wheel is not displaced by desktop window management"),
        (".ignoresCycle", "wheel remains outside normal app window cycling"),
        ("self.ignoresMouseEvents = true", "hidden warm window cannot intercept pointer input"),
        ("revealWorkItem", "pending reveal work is cancellable during fast dismiss or repeated invocation"),
        ("dismissWorkItem", "pending dismiss completion cannot race a repeated invocation"),
        ("self.orderOut(nil)", "dismissed screen-saver-level window leaves the active desktop space"),
    ]
    for needle, reason in window_requirements:
        require(wheel_window, needle, reason)

    app_requirements = [
        ("if let existing = wheelWindow", "wheel window is reused across presentations"),
        ("window = existing", "existing native glass hierarchy is retained"),
        ("wheelWindow = created", "new wheel window is stored for later reuse"),
    ]
    for needle, reason in app_requirements:
        require(app_source, needle, reason)

    forbid(wheel_window, "self.animator().alphaValue", "whole-window alpha animation that changes glass density")
    forbid(wheel_window, "warmAlpha", "persistent near-transparent screen-saver-level window")

    print("Glass appearance contract passed.")


if __name__ == "__main__":
    main()
