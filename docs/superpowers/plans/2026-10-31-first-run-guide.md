# 首次引导 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用三步引导替换首次启动的 `NSAlert`，让新用户亲手按一次快捷键、用一次轮盘。

**Architecture:** `FirstRunGuideController` 是一个小状态机，由真实的快捷键和轮盘事件推进，界面是一个不抢焦点的玻璃面板。在轮盘常驻完成之后实现。

**Tech Stack:** Swift 5 模式，SwiftUI + AppKit，macOS 13+，Python 源码合约测试（`work/*-test.py`）。

**Spec:** `docs/superpowers/specs/2026-10-31-first-run-guide-design.md`

## Global Constraints

- 不改 bundle id；新文件手动加入 `dok.xcodeproj/project.pbxproj`，不运行 xcodegen。
- 透明窗口不用 `.blur()`；文案中英双语，名称末尾不加省略号；遵循"减少动态效果"；macOS 13+。
- 引导里不触发任何权限弹窗。
- **不提交也不推送，除非用户明确要求。** 每个任务结束时构建、跑 `work/*-test.py`、装到 /Applications，命令同常驻计划。
- 验证时不反复唤出窗口打断用户，需要肉眼确认的项目汇总后请用户看。

## Review Focus

- 快捷键被其他软件占用，注册失败：8 秒后的兜底按钮能走完引导（Task 2）。
- 老用户的 `settings.json` 没有 `hasCompletedOnboarding` 字段：不被当成新用户（Task 1）。
- 用户在第一步改了快捷键：键帽和判定都换成新快捷键（Task 2）。
- 引导中途退出应用：下次从第一步开始，不留下半完成状态（Task 1）。
- 从设置里重看时用的是按住模式：松手算完成，提示文案不同（Task 2）。

---

### Task 1: 状态机、卡片和第一步

**Files:**
- Create: `Sources/dok/FirstRunGuide.swift`（加入 pbxproj）
- Modify: `AppState.swift`（decoder）、`DokApp.swift`（`showOnboarding`、`handleHotKeyDown`）、两份 strings
- Test: `work/dok-first-run-guide-test.py`

**Interfaces:**
- Produces:
  - `enum FirstRunGuideStep { case pressHotkey, useWheel, finished }`
  - `final class FirstRunGuideController: ObservableObject`，`init(appState: AppState)`，`@Published var step`，`func start()`，`func skip()`，`func hotkeyDidFire()`，`func wheelDidClose()`
- `AppDelegate` 持有 `firstRunGuide: FirstRunGuideController?`

- [ ] **Step 1: 写失败的测试**，断言：
  - `AppState.swift` 含 `hasCompletedOnboarding = (try? c.decode(Bool.self, forKey: .hasCompletedOnboarding)) ?? true`（只有已有配置才走 decoder，全新安装用属性默认值 false）。
  - `DokApp.swift` 不再出现 `NSAlert` 的 onboarding 代码和 `onboarding.openAccessibility`；`handleHotKeyDown` 调用 `firstRunGuide?.hotkeyDidFire()`。
  - 面板是 `.nonactivatingPanel`。
  - `hasCompletedOnboarding = true` 只出现在 `skip()` 和完成路径。
  - 无 `AXIsProcessTrustedWithOptions`，也无 `CGRequestListenEventAccess`；全局 `flagsChanged` 监听前有 `CGPreflightListenEventAccess()`。
- [ ] **Step 2:** 运行，预期 FAIL。
- [ ] **Step 3:** 实现卡片：屏幕中央，用 `KeyCap` 风格的大键帽（`hotkey.keySymbols`），文案"现在按一下试试"（Press it now），右上角"跳过"（Skip）。快捷键触发时进入 `useWheel`。清理 `onboarding.*` 旧文案。
- [ ] **Step 4:** 构建安装、全部测试。

### Task 2: 第二、三步、兜底和重看

**Files:**
- Modify: `FirstRunGuide.swift`、`DokWheelWindow.swift`（关闭回调）、`SettingsView.swift`（系统组）、两份 strings
- Test: `work/dok-first-run-guide-test.py`（扩充）

**Interfaces:**
- Consumes: Task 1 的控制器
- Produces: `DokWheelWindow.onDidHide: (() -> Void)?`，在 `finishHiding()` 里调用；`FirstRunGuideController.fallbackDelay: TimeInterval = 8`

- [ ] **Step 1: 写失败的测试**，断言：
  - `fallbackDelay = 8`；兜底路径调用 `showDok()`。
  - "换个快捷键"复用 `KeyActionRecorderControl` 的录入并发 `.hotkeyChanged`，之后回到 `.pressHotkey`。
  - `finishHiding` 调用 `onDidHide`，第二步由它推进。
  - 按住模式有独立文案键 `guide.useWheel.hold`。
  - 第三步有 `guide.openSettings` 和 `guide.start` 两个按钮。
  - 通用页系统组有"重新查看引导"（`settings.replayGuide`），调用 `firstRunGuide.start()`。
- [ ] **Step 2:** 运行，预期 FAIL。
- [ ] **Step 3:** 实现文案：
  - 第二步"移到图标上，点一下就能打开"（Move to an icon and click to open）；按住模式"按住快捷键，移到图标上，松开就打开"（Hold the shortcut, move to an icon, and release to open）。
  - 第三步"快捷键可以在设置里改，轮盘也可以常驻桌面"（You can change the shortcut in Settings, or keep the wheel on your desktop）。
  - 按钮：去设置（Open Settings）、开始使用（Get started）。
  - 兜底：点这里打开轮盘（Open the wheel）、换个快捷键（Change shortcut）。
  - 第二步提示放在轮盘之外，鼠标贴近屏幕边缘时换到另一侧。重看不改写 `hasCompletedOnboarding`。
- [ ] **Step 4:** 构建安装、全部测试。把引导走一遍的确认项汇总给用户。
