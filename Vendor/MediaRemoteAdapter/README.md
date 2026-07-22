# MediaRemoteAdapter (vendored)

Vendored from [ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter)
at version 0.7.6 (master, fetched 2026-07-21). Licensed under the BSD 3-Clause
License — see `LICENSE` in this directory. Copyright (c) 2025 Jonas van den Berg
and contributors.

来源：[ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter)，
版本 0.7.6（master 分支，2026-07-21 抓取）。BSD 3-Clause 协议，见本目录 `LICENSE`。

## Why / 用途

macOS only exposes MediaRemote "Now Playing" metadata to Apple-signed
processes. This adapter runs a bundled framework through `/usr/bin/perl`
(an Apple-signed system binary present on every Mac), which is entitled to
read that metadata. Arcly launches it as a resident child process and reads
JSON lines from stdout. No developer tools are required on the user's machine.

macOS 只向 Apple 签名的进程开放"正在播放"信息。本组件把打包在 App 内的框架
交给系统自带的 `/usr/bin/perl`（Apple 签名）加载运行，从而读取音乐信息。
用户机器不需要安装任何开发工具。

## Local changes / 本地改动

- `src/adapter/test.m` and `src/test/` are not vendored. They implement the
  optional `test` command, which requires a separate `MediaRemoteAdapterTestClient`
  executable that Arcly does not use. All other sources are verbatim copies.
  未收录 `src/adapter/test.m` 与 `src/test/`（可选的 `test` 命令，依赖 Arcly
  用不到的独立测试程序）。其余源文件与上游逐字一致。
- The framework is built by the `MediaRemoteAdapter` target in `project.yml`
  (XcodeGen) instead of the upstream CMake build.
  框架改由 `project.yml` 里的 `MediaRemoteAdapter` target 构建，不使用上游 CMake。
