#!/usr/bin/env python3
"""显示进度契约：helper 的双向小偏差都只能渐进收敛。"""
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SERVICE = (ROOT / "Sources" / "Arcly" / "NowPlayingService.swift").read_text()


def stabilized(last: float, elapsed_since_display: float, candidate: float, rate: float = 1.0) -> float:
    continued = last + elapsed_since_display * rate
    diff = candidate - continued
    return continued + diff * 0.08 if abs(diff) < 1.5 else candidate


def main() -> None:
    assert abs(stabilized(10.0, 1.0, 10.4) - 10.952) < 1e-9, (
        "sub-1.5s helper lag must converge gradually instead of jumping backward"
    )
    assert abs(stabilized(10.0, 1.0, 11.6) - 11.048) < 1e-9, (
        "sub-1.5s helper lead must converge gradually instead of jumping forward"
    )
    assert stabilized(10.0, 1.0, 9.5) == 9.5, "a 1.5s regression is an intentional reset"
    assert stabilized(10.0, 1.0, 12.5) == 12.5, "a 1.5s advance is an intentional reset"
    assert stabilized(10.0, 1.0, 8.0) == 8.0, "large regressions must remain possible"
    assert stabilized(10.0, 1.0, 10.0, rate=0.0) == 10.0, "paused progress must remain still"

    requirements = [
        ("private var lastDisplayedElapsed: TimeInterval?", "last displayed elapsed state"),
        ("private var lastDisplayedAt: Date?", "last display timestamp"),
        ("minorProgressRegressionTolerance: TimeInterval = 1.5", "1.5 second regression threshold"),
        ("let continuedDisplayedElapsed", "old display baseline extrapolation"),
        ("let diff = clampedCandidate - continuedDisplayedElapsed", "symmetric official/display difference"),
        ("if abs(diff) < minorProgressRegressionTolerance", "bidirectional dead zone"),
        ("continuedDisplayedElapsed + diff * 0.08", "eight-percent gradual convergence"),
        ("resetDisplayedProgress(to: target, at: optimisticTimestamp)", "seek baseline reset"),
        ("let playbackStateChanged = isPlaying != snapshot.playing", "pause and resume detection"),
        ("if playbackStateChanged {\n                resetDisplayedProgressTracking()", "pause and resume baseline reset"),
        ("private func clearProgress()", "track and missing-data reset path"),
        ("playbackRate = nil\n        resetDisplayedProgressTracking()", "clear resets displayed baseline"),
    ]
    for needle, reason in requirements:
        assert needle in SERVICE, f"missing {reason}: {needle}"

    print("Now-playing monotonic progress contract passed.")


if __name__ == "__main__":
    main()
