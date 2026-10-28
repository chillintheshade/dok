#!/usr/bin/env python3
"""helper stdout 必须边跑边读。

封面数据可能很大，等到进程结束再一次性读取会把管道写满并造成死锁。
常驻 helper 更是永不退出，只能流式读取。
"""
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Sources" / "dok" / "NowPlayingService.swift"


def main() -> None:
    source = SOURCE.read_text()
    match = re.search(r"private func launchHelper\(\) \{(?P<body>.*?)\n    \}\n", source, re.S)
    assert match, "launchHelper body not found"
    body = match.group("body")

    assert "readabilityHandler" in body, (
        "helper stdout must be drained while the process is running; large artwork "
        "can otherwise fill the pipe and stall the helper"
    )
    assert "availableData" in body, "stdout draining should append chunks from availableData"
    assert "readDataToEndOfFile" not in body, (
        "a persistent helper never terminates; waiting for EOF would block forever"
    )

    # 分片可能切断一行 JSON，必须按换行重组后再解析。
    assert "helperBuffer.append(chunk)" in body, "chunks must be reassembled into whole lines"
    assert "private final class LineBuffer" in source, "line reassembly buffer should exist"
    assert "firstIndex(of: 0x0A)" in source, "buffer should split on newline boundaries"

    # 一次性 get 的封面同样超过管道缓冲：进程运行时就在后台读到 EOF，不能等退出后再读。
    read = re.search(r"private func readAdapterOnce\(\) \{(?P<body>.*?)\n    \}\n", source, re.S)
    assert read, "readAdapterOnce body not found"
    read_body = read.group("body")
    assert read_body.index("readDataToEndOfFile()") < read_body.index("waitUntilExit()"), (
        "drain one-shot output before waiting for exit"
    )
    assert "DispatchQueue.global(" in read_body, "one-shot output is drained off the main thread"
    assert "Self.adapterReadTimeout" in read_body, "a hung get is terminated"

    print("Now-playing pipe drain contract passed.")


if __name__ == "__main__":
    main()
