#!/usr/bin/env python3
"""perl adapter 集成契约。

音乐信息的首选后端是打包在 App 内的 MediaRemoteAdapter.framework，
由系统自带的 /usr/bin/perl 加载 —— 所有用户无需安装开发工具即可显示歌名封面。
Swift 工具链脚本降级为兜底后端。
"""
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
SERVICE = ROOT / "Sources" / "dok" / "NowPlayingService.swift"
PROJECT = ROOT / "project.yml"
VENDOR = ROOT / "Vendor" / "MediaRemoteAdapter"


def main() -> None:
    # 1. vendor 完整性：协议文件和关键源码必须在库
    assert (VENDOR / "LICENSE").exists(), "vendored BSD-3 LICENSE is missing"
    assert "BSD 3-Clause" in (VENDOR / "LICENSE").read_text(), "LICENSE must be BSD 3-Clause"
    for rel in [
        "bin/mediaremote-adapter.pl",
        "include/MediaRemoteAdapter.h",
        "src/adapter/stream.m",
        "src/adapter/globals.m",
        "src/private/MediaRemote.m",
        "src/utility/helpers.m",
    ]:
        assert (VENDOR / rel).exists(), f"vendored file missing: {rel}"

    # 上游文件头部的版权声明必须保留（BSD-3 条款一）
    stream = (VENDOR / "src" / "adapter" / "stream.m").read_text()
    assert "Jonas van den Berg" in stream, "upstream copyright notice must be retained"

    # 2. 工程配置：框架 target + 嵌入 + perl 脚本资源
    project = PROJECT.read_text()
    assert "MediaRemoteAdapter:" in project, "framework target missing from project.yml"
    assert "type: framework" in project, "MediaRemoteAdapter must build as a framework"
    assert "mediaremote-adapter.pl" in project, "perl script must ship as an app resource"
    assert "embed: true" in project, "framework must be embedded in the app bundle"
    assert "link: false" in project, (
        "the app must NOT link the framework; it is loaded by perl at runtime"
    )
    assert "GCC_SYMBOLS_PRIVATE_EXTERN: false" in project, (
        "exported symbols must stay visible for perl's dlsym"
    )

    # 3. NowPlayingService：perl 后端优先，swift 工具链兜底
    source = SERVICE.read_text()
    assert '"/usr/bin/perl"' in source, "perl backend should use the system perl binary"
    assert 'forResource: "mediaremote-adapter", withExtension: "pl"' in source, (
        "the bundled perl script must be resolved from app resources"
    )
    assert 'appendingPathComponent("MediaRemoteAdapter.framework")' in source, (
        "the bundled framework must be resolved from the app's Frameworks directory"
    )
    # 轮盘打开期间用 stream 实时推送；启动和唤醒用一次性 get 预热缓存。
    assert '[script.path, framework.path, "stream", "--no-diff"]' in source, "event-driven stream while open"
    assert '[script.path, framework.path, "get"]' in source, "one-shot get warms the cache"
    assert source.count('"stream", "--no-diff"') == 1, "only one place may start a stream"
    update = re.search(r"private func updateAdapterStream\(\) \{(?P<body>.*?)\n    \}\n", source, re.S)
    assert update and "consumers.contains(.summonedWheel) || pinnedNeedsStream || pendingPlaybackIntent != nil" in update.group("body"), (
        "the stream exists only while the wheel is open or a play intent waits; never resident"
    )
    assert "private static func parseAdapterOutput" in source, "get output needs its own parser"
    assert "private static func parseAdapterStreamLine" in source, "stream lines need their own parser"
    assert ".fragmentsAllowed" in source, "get prints a bare null when nothing is playing"

    # perl adapter 是唯一的元数据来源。连续失败后播放命令退回媒体键，下一次唤出照常重试。
    assert "private static let adapterFailureLimit = 3" in source
    assert "Self.adapterAvailable && adapterFailures < Self.adapterFailureLimit" in source
    accept = re.search(r"private func acceptAdapterSnapshot\(_ snapshot: NowPlayingSnapshot\) \{(?P<body>.*?)\n    \}\n", source, re.S)
    assert accept and "adapterFailures = 0" in accept.group("body"), "one good read restores the adapter"
    for gone in ["startHelper", "helperSwiftURL", "backendQueue", "/usr/bin/swift"]:
        assert gone not in source, f"no second metadata backend: {gone}"

    print("MediaRemote adapter integration contract passed.")


if __name__ == "__main__":
    main()
