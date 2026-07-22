#!/usr/bin/env python3
"""常驻 helper 的生命周期契约。

旧实现每次刷新都新起一个解释器进程，每次要付 1~3 秒编译成本，
因此需要一整套在途排队逻辑。现在改为进程常驻、事件驱动推送，
排队逻辑被取消，取而代之的要求是：不得重复拉起、异常退出要能恢复。
"""
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Sources" / "dok" / "NowPlayingService.swift"


def main() -> None:
    source = SOURCE.read_text()

    start = re.search(r"private func startHelper\(\) \{(?P<body>.*?)\n    \}\n", source, re.S)
    assert start, "startHelper body not found"
    assert "guard helperProcess == nil" in start.group("body"), (
        "helper must not be spawned again while one is already running"
    )

    # 意外退出后要能恢复，但要延迟重启，避免异常时进程被反复拉起。
    assert "private func helperDidTerminate()" in source, "helper termination should be handled"
    term = re.search(r"private func helperDidTerminate\(\) \{(?P<body>.*?)\n    \}\n", source, re.S)
    assert term, "helperDidTerminate body not found"
    term_body = term.group("body")
    assert "guard isObserving else { return }" in term_body, "a stopped service must not resurrect the helper"
    assert "asyncAfter" in term_body, "helper restart should be delayed, not immediate"

    # 停止观察时必须回收进程，避免泄漏常驻子进程。
    stop = re.search(r"func stopObserving\(\) \{(?P<body>.*?)\n    \}\n", source, re.S)
    assert stop, "stopObserving body not found"
    assert "stopHelper()" in stop.group("body"), "stopObserving must terminate the persistent helper"
    assert "proc.terminate()" in source, "helper process should be terminated explicitly"

    # 每次刷新起一个进程的旧模型不应回归。
    assert "refreshQueuedAfterInFlight" not in source, "per-refresh process queueing should be gone"
    assert "activeRefreshID" not in source, "per-refresh id tracking should be gone"

    print("Now-playing helper lifecycle contract passed.")


if __name__ == "__main__":
    main()
