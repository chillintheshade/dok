#!/usr/bin/env python3
"""直读优先契约。

进程内直读是即时的，在未被系统限制的机器上应当优先采用；
常驻 helper 是被限制时的兜底数据源。两者都必须存在。
"""
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Sources" / "dok" / "NowPlayingService.swift"


def main() -> None:
    source = SOURCE.read_text()

    assert "private func directRead" in source, "NowPlayingService should have an in-process MediaRemote reader"
    assert "private func startHelper()" in source, "persistent helper fallback should exist"
    assert "Process()" in source, "helper fallback should remain available"

    match = re.search(r"func startObserving\(\) \{(?P<body>.*?)\n    \}\n", source, re.S)
    assert match, "startObserving body not found"
    body = match.group("body")

    direct_index = body.find("directRead()")
    helper_index = body.find("startHelper()")
    assert direct_index != -1, "startObserving should attempt an immediate direct read"
    assert helper_index != -1, "startObserving should start the persistent helper"
    assert direct_index < helper_index, "direct MediaRemote read should run before spawning the helper"

    # 直读被限制时返回空标题，这种空值不得覆盖 helper 推送的有效数据。
    assert "guard !title.isEmpty else {" in source, (
        "direct reads should only apply when they include track metadata"
    )
    assert "applyEmpty" in source, (
        "empty direct reads may only clear state when no persistent helper is running"
    )
    assert "directRead(applyEmpty: helperProcess == nil)" in source, (
        "helper output must win over restricted direct reads"
    )

    assert "🎵" not in source, "temporary diagnostic music logs should not ship"

    print("Now-playing direct primary contract passed.")


if __name__ == "__main__":
    main()
