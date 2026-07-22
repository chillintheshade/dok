#!/usr/bin/env python3
"""可读副本必须与内嵌 helper 脚本逐字一致。

helper 代码同时存在于两处：NowPlayingService 里的内嵌字符串（运行时真正执行的），
以及 Sources/Helper/mr_info.swift（可阅读、可单独调试的副本）。
两者漂移过一次，这里锁死它们。
"""
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
SERVICE = ROOT / "Sources" / "dok" / "NowPlayingService.swift"
COPY = ROOT / "Sources" / "Helper" / "mr_info.swift"


def embedded_script() -> str:
    source = SERVICE.read_text()
    match = re.search(r'private static let helperScript = """\n(.*?)\n    """', source, re.S)
    assert match, "helperScript literal not found"
    body = match.group(1)
    body = "\n".join(line[4:] if line.startswith("    ") else line for line in body.split("\n"))
    # 还原 Swift 多行字符串里的转义
    return body.replace("\\\\(", "\\(").replace("\\\\n", "\\n")


def readable_copy() -> str:
    text = COPY.read_text()
    lines = text.split("\n")
    start = next(i for i, line in enumerate(lines) if not line.startswith("//") and line.strip())
    return "\n".join(lines[start:]).rstrip("\n")


def main() -> None:
    script = embedded_script()

    # 封面必须参与变化比对，否则封面会永远慢一首曲目
    assert "artworkID" in script, "artwork must take part in change detection"
    assert "artworkStale" in script, "stale artwork must be flagged to the app"
    assert "emit(force: true)" in script, "a settle pass must confirm artwork that never changes"
    assert "Timer.scheduledTimer" in script, "poll fallback for players that skip notifications"
    assert "RunLoop.main.run()" in script, "helper must stay resident"
    assert "exit(0)" not in script, "helper must not be one-shot"

    assert script.rstrip("\n") == readable_copy(), (
        "Sources/Helper/mr_info.swift has drifted from NowPlayingService.helperScript"
    )

    print("Now-playing helper sync contract passed.")


if __name__ == "__main__":
    main()
