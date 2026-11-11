#!/usr/bin/env python3
"""adapter stream 的生命周期契约。

最早的实现每次刷新都新起一个解释器进程，需要一整套在途排队逻辑；之后改成常驻的
Swift 工具链 helper。两者都已移除：现在只有按需的 perl adapter stream。
要求是：不得重复拉起、异常退出要能延迟恢复、停止观察时回收进程。
"""
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Sources" / "dok" / "NowPlayingService.swift"


def body(source: str, signature: str) -> str:
    match = re.search(re.escape(signature) + r" \{(?P<body>.*?)\n    \}\n", source, re.S)
    assert match, f"{signature} body not found"
    return match.group("body")


def main() -> None:
    source = SOURCE.read_text()

    start = body(source, "private func startAdapterStream()")
    assert "guard adapterStreamProcess == nil" in start, (
        "a stream must not be spawned again while one is already running"
    )

    # 意外退出后要能恢复，但要延迟重启，避免异常时进程被反复拉起。
    exited = body(source, "private func adapterStreamDidTerminate(status: Int32, wasSignal: Bool, observationID: UUID)")
    assert "guard isObserving, self.observationID == observationID else { return }" in exited, (
        "a stopped service must not resurrect the stream"
    )
    assert "guard adapterUsable else { return }" in exited, "repeated failures stop the restart loop"
    assert "asyncAfter" in exited, "restart goes through a delayed work item"

    # 失败累计后不换后端：停掉 stream，等下一次唤出再试。
    failure = body(source, "private func recordAdapterFailure()")
    assert "stopAdapterStream()" in failure and "canSeek = false" in failure
    update = body(source, "private func updateAdapterStream()")
    assert "Self.adapterAvailable" in update and "adapterUsable" not in update, (
        "every summon retries the adapter even after the failure limit"
    )

    # 停止观察时必须回收进程，避免泄漏子进程。
    stop = body(source, "func stopObserving()")
    assert "stopAdapterStream()" in stop, "stopObserving must terminate the stream"
    assert "process.terminate()" in body(source, "private func stopAdapterStream()")

    # 旧模型不应回归。
    for gone in ["refreshQueuedAfterInFlight", "activeRefreshID", "helperProcess", "startHelper",
                 "scheduleHelperRestart", "helperScript"]:
        assert gone not in source, f"removed now-playing machinery must not return: {gone}"

    # 旧版本写进 Application Support 的脚本在启动时清掉。
    cleanup = body(source, "private static func removeLegacyHelperScripts()")
    assert '"mr_watch.swift"' in cleanup and "removeItem" in cleanup
    assert "Self.removeLegacyHelperScripts()" in body(source, "func startObserving()")
    assert not (ROOT / "Sources" / "Helper").exists(), "the readable helper copy is gone with the helper"

    print("Now-playing stream lifecycle contract passed.")


if __name__ == "__main__":
    main()
