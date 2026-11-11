#!/usr/bin/env python3
"""直读优先契约。

进程内直读是即时的，在未被系统限制的机器上应当优先采用；
被限制时由 perl adapter 提供数据。启动时两者都要尝试，直读在前。
"""
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Sources" / "dok" / "NowPlayingService.swift"


def main() -> None:
    source = SOURCE.read_text()

    assert "private func directRead" in source, "NowPlayingService should have an in-process MediaRemote reader"
    assert "private func readAdapterOnce()" in source, "the perl adapter warms the cache at startup"

    match = re.search(r"func startObserving\(\) \{(?P<body>.*?)\n    \}\n", source, re.S)
    assert match, "startObserving body not found"
    body = match.group("body")

    direct_index = body.find("directRead()")
    adapter_index = body.find("readAdapterOnce()")
    assert direct_index != -1, "startObserving should attempt an immediate direct read"
    assert adapter_index != -1, "startObserving should warm the cache through the adapter"
    assert direct_index < adapter_index, "direct MediaRemote read should run before spawning perl"
    assert "startHelper" not in body, "there is no resident fallback to start"

    # 直读被限制时返回空标题，这种空值不得覆盖 adapter 推送的有效数据。
    assert "guard !title.isEmpty else {" in source, (
        "direct reads should only apply when they include track metadata"
    )
    assert "directRead(applyEmpty: !Self.adapterAvailable)" in source, (
        "adapter output must win over restricted direct reads"
    )

    assert "🎵" not in source, "temporary diagnostic music logs should not ship"

    print("Now-playing direct primary contract passed.")


if __name__ == "__main__":
    main()
