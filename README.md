# Arcly

<p align="center">
  <img src="Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="132" alt="Arcly app icon">
</p>

<p align="center">
  <strong>A liquid-glass command wheel for macOS.</strong><br>
  <strong>一款 macOS 液态玻璃轮盘启动器。</strong>
</p>

<p align="center">
  <img alt="macOS 26+" src="https://img.shields.io/badge/macOS-26%2B-lightgrey">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-5-orange">
  <img alt="Language" src="https://img.shields.io/badge/language-English%20%7C%20简体中文-blue">
  <img alt="License" src="https://img.shields.io/badge/license-GPL--3.0-blue">
</p>

Arcly puts your everyday Mac actions under your cursor: launch apps, open files and folders, and control music from a quiet radial menu.

Arcly 把高频操作放到鼠标附近：启动应用、打开文件和文件夹、控制音乐，都在一个轻量的轮盘里完成。

Every feature is available for free. Arcly has no account requirement, paid tier, or in-app purchase.

全部功能免费开放，不需要账号，没有付费分层，也没有应用内购买。

Arcly currently requires macOS 26.0 or later.

Arcly 当前需要 macOS 26.0 或更高版本。

## Preview / 预览

These preview images predate the latest uncommitted wheel and settings refinements.

以下预览图早于当前尚未提交的轮盘与设置界面调整。

<p align="center">
  <img src="docs/github/arcly-wheel-music.png" width="620" alt="Arcly command wheel with music controls">
</p>

<p align="center">
  <img src="docs/github/arcly-settings-wheel.png" width="760" alt="Arcly wheel settings">
</p>

<p align="center">
  <img src="docs/github/arcly-settings-general.png" width="760" alt="Arcly general settings">
</p>

## Highlights / 亮点

- Liquid-glass radial menu that floats above the desktop  
  液态玻璃质感的 macOS 轮盘，轻盈覆盖在当前工作区上
- Launch apps, files, and folders from fixed wheel slots  
  常用应用、文件、文件夹可以固定到轮盘槽位
- Playback controls in the center, with track info where the system allows it  
  中心区域提供播放控制，在系统允许的情况下同时显示当前曲目
- Hotkey and mouse-trigger launch modes  
  支持快捷键唤出，也支持鼠标按键触发
- Adjustable radius, icon size, opacity, theme, and position  
  可调整半径、图标大小、透明度、主题和唤出位置
- English and Simplified Chinese UI, following the macOS system language  
  支持英文和简体中文界面，自动跟随 macOS 系统语言

## Download / 下载

Download the latest DMG from [GitHub Releases](https://github.com/chillintheshade/Arcly/releases/latest), then drag `Arcly.app` into `/Applications`.

从 [GitHub Releases](https://github.com/chillintheshade/Arcly/releases/latest) 下载最新 DMG，然后把 `Arcly.app` 拖到 `/Applications`。

This self-distributed build is ad-hoc signed, but not notarized by Apple yet. If macOS says Arcly cannot be verified or is damaged, install it to `/Applications` first, then run:

当前自分发版本采用临时签名，但还没有经过 Apple notarization。如果 macOS 提示无法验证或 App 已损坏，先拖到 `/Applications`，再运行：

```bash
sudo xattr -dr com.apple.quarantine /Applications/Arcly.app
```

After that, open Arcly again.

然后重新打开 Arcly。

## Build From Source / 从源码构建

```bash
swift build -c release
for test in work/*-test.py; do python3 "$test" || exit 1; done
xcodebuild -project Arcly.xcodeproj -scheme Arcly -configuration Release build CODE_SIGNING_ALLOWED=NO
```

The Swift package build is the fast compile check. Use the Xcode project to produce the full `.app` with assets and localized resources.

Swift Package 用于快速编译检查；需要完整 App、图标和本地化资源时，请使用 Xcode 工程构建。

The bundle identifier still uses `com.qingshan.orbis` to preserve update compatibility. The user-facing app name is `Arcly`.

为了兼容旧版本更新，bundle identifier 仍然保留 `com.qingshan.orbis`；用户看到的名称是 `Arcly`。

## Music Support / 音乐功能说明

**Playback controls work on every Mac.** Previous, play/pause, and next are sent as system media keys, so they drive whichever player is active.

**播放控制在所有 Mac 上都可用。** 上一首、播放/暂停、下一首通过系统媒体按键发送，对当前活跃的播放器都有效。

**Track name and artwork are another matter.** Recent versions of macOS only expose Now Playing metadata to Apple-signed processes. Arcly reads it through a helper that runs on the Swift toolchain, so the track name and artwork appear only on machines with Xcode or the Command Line Tools installed. Without them, the center shows a generic music placeholder — the playback controls still work.

**歌名和封面则受系统限制。** 较新版本的 macOS 只向 Apple 签名的进程开放"正在播放"信息。Arcly 通过 Swift 工具链上的 helper 读取，因此歌名和封面只在装有 Xcode 或命令行工具（Command Line Tools）的机器上显示。没有安装时，中心区域显示通用的音乐占位图，播放控制不受影响。

If you want the full display, install the toolchain with:

如果需要完整显示，可以安装工具链：

```bash
xcode-select --install
```

## Notes / 说明

- Arcly ships as one free feature set; there is no Pro tier or purchase flow.
  Arcly 只有一套完整免费功能，不再包含 Pro 分层或购买流程。
- Music metadata relies on Apple's private MediaRemote framework, which suits self-distribution but is not App Store compatible.
  音乐信息依赖 Apple 的私有 MediaRemote framework，适合自行分发，但不符合 App Store 上架要求。

## Support / 支持

If Arcly matches the way you like to work on macOS, starring the repo helps more people find it.

如果你喜欢这种 macOS 轮盘式工作流，给这个仓库一个 star 会帮助更多人看到它。

## License / 许可协议

Arcly is released under the [GNU General Public License v3.0](LICENSE). You may use, modify, and redistribute it freely, provided that derivative works are also released under the GPL-3.0 with their source code available.

Arcly 基于 [GNU General Public License v3.0](LICENSE) 发布。你可以自由使用、修改和再分发，但衍生作品同样需要以 GPL-3.0 开源并提供源码。
