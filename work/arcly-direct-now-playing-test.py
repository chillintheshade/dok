#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Sources" / "Arcly" / "NowPlayingService.swift"


def require(source: str, needle: str, reason: str) -> None:
    if needle not in source:
        raise AssertionError(f"Missing {reason}: {needle}")


def forbid(source: str, needle: str, reason: str) -> None:
    if needle in source:
        raise AssertionError(f"Forbidden {reason}: {needle}")


def main() -> None:
    source = SOURCE.read_text()

    requirements = [
        ("private static let helperScript", "external MediaRemote helper script"),
        ("private var refreshProcess: Process?", "tracked helper process"),
        ("Process()", "helper process launch for now-playing refresh"),
        ("helperSwiftURL", "helper only uses an installed developer-tool Swift binary"),
        ("readNowPlayingDirect", "in-process MediaRemote refresh path"),
        ("private func completeRefresh", "single completion path for helper refresh"),
        ("activeRefreshID", "stale async refresh protection"),
        ("refreshTimeout", "timeout for stuck MediaRemote callbacks"),
        ("refreshProcess?.terminate()", "stuck helper process is terminated"),
        ("func sendMediaCommand", "media commands are independent from display state"),
        ("postSystemMediaKey", "media controls use hardware media key events"),
        ("NX_KEYTYPE_PLAY", "play pause uses system media key"),
        ("NX_KEYTYPE_NEXT", "next track uses system media key"),
        ("NX_KEYTYPE_PREVIOUS", "previous track uses system media key"),
        ("sendMediaCommand(2, keyType: NX_KEYTYPE_PLAY)", "play pause sends command even when no title is displayed"),
        ("sendMediaCommand(4, keyType: NX_KEYTYPE_NEXT)", "next track sends command even when no title is displayed"),
        ("sendMediaCommand(5, keyType: NX_KEYTYPE_PREVIOUS)", "previous track sends command even when no title is displayed"),
        ("snapshot.title.isEmpty && snapshot.pid <= 0", "empty helper result clears the music UI"),
    ]

    for needle, reason in requirements:
        require(source, needle, reason)

    forbidden = [
        ("if trackName.isEmpty { return }", "media controls blocked by missing displayed title"),
        ('URL(fileURLWithPath: "/usr/bin/swift")', "system Swift shim can prompt users to install developer tools"),
    ]

    for needle, reason in forbidden:
        forbid(source, needle, reason)

    print("Direct now-playing contract passed.")


if __name__ == "__main__":
    main()
