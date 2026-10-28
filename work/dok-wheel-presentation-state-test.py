#!/usr/bin/env python3
"""轮盘可见性单一状态机与"空玻璃盘"不变量契约。"""
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WINDOW = (ROOT / "Sources" / "dok" / "DokWheelWindow.swift").read_text()
APP = (ROOT / "Sources" / "dok" / "DokApp.swift").read_text()


def section(source: str, start: str, end: str) -> str:
    return source.split(start, 1)[1].split(end, 1)[0]


def main() -> None:
    requirements = [
        ("case hidden, revealing, shown, dismissing", "four-state visibility machine"),
        ("private(set) var presentation: Presentation = .hidden", "state is private to the window"),
        ("var isPresented: Bool { presentation == .revealing || presentation == .shown }", "trigger-facing derived state"),
        ("private static let hiddenContentTolerance: TimeInterval = 0.2", "0.2s invisible-content tolerance"),
        ("override func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int)", "rogue order-in guard"),
        ("RunLoop.main.add(timer, forMode: .common)", "guard runs during menu tracking too"),
        ("self.level = .popUpMenu", "wheel sits below system screenshot overlays"),
        (".fullScreenAuxiliary", "wheel still presents over full-screen apps"),
    ]
    for needle, reason in requirements:
        assert needle in WINDOW, f"Missing {reason}: {needle}"

    assert "CGShieldingWindowLevel" not in WINDOW, "shielding level must not return"
    assert WINDOW.count("presentation = next") == 1, "presentation changes only inside setPresentation"

    hide = section(WINDOW, "private func finishHiding() {", "override func order(")
    order = ["setPresentation(.hidden)", "orderOut(nil)", "alphaValue = MenuMotion.windowWarmupAlpha"]
    positions = [hide.index(needle) for needle in order]
    assert positions == sorted(positions), "hidden: state, order out, then stay transparent"
    assert "alphaValue = 1" not in hide, "a hidden window must never be left at full alpha"

    settings = section(WINDOW, "func dismissForSettings() {", "// MARK: - 可见性状态机")
    assert "finishHiding()" in settings, "settings dismissal uses the single hidden transition"
    assert "alphaValue = 1" not in settings, "settings dismissal must not reset alpha to 1"

    show = section(WINDOW, "func showAt(point: NSPoint) {", "private func installEventMonitors()")
    assert show.index("setPresentation(.revealing)") < show.index("self.orderFrontRegardless()"), \
        "state leaves hidden before the window is ordered in"
    assert "self.setPresentation(.shown)" in show, "reveal completes the transition"

    guard = section(WINDOW, "private func checkVisibilityInvariant() {", "private func removeMonitors()")
    assert "isVisible, !appState.isMenuVisible" in guard, "invariant compares window and content visibility"
    assert "finishHiding()" in guard, "invariant violation orders the window out"

    assert "var isMenuOpen: Bool { wheelWindow?.isPresented ?? false }" in APP, "no duplicate open flag"
    assert "isMenuOpen = " not in APP, "app delegate never writes its own open flag"
    assert "onDismiss" not in APP and "onDismiss" not in WINDOW, "no side-channel dismiss callback"

    print("Wheel presentation state contract passed.")


if __name__ == "__main__":
    main()
