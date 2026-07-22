#!/usr/bin/env python3
"""helper stdout 必须边跑边读。

封面数据可能很大，等到进程结束再一次性读取会把管道写满并造成死锁。
常驻 helper 更是永不退出，只能流式读取。
"""
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Sources" / "Arcly" / "NowPlayingService.swift"


def main() -> None:
    source = SOURCE.read_text()
    match = re.search(r"private func launchHelper\(_ backend: HelperBackend\) \{(?P<body>.*?)\n    \}\n", source, re.S)
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

    print("Now-playing pipe drain contract passed.")


if __name__ == "__main__":
    main()
