# 轮盘常驻 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增"常驻"设置（关闭 / 桌面 / 置顶），轮盘可一直留在屏幕上并任意拖动，原有唤出路径不变。

**Architecture:** 唤出轮盘的 `DokWheelWindow` 不动其状态机。把"交互状态"和"命中判断"从窗口与 `AppState` 中抽出来，让常驻窗口 `PinnedWheelWindow` 用自己的一份；`PinnedWheelController` 负责模式切换、位置和小圆点。

**Tech Stack:** Swift 5 模式，SwiftUI + AppKit，macOS 13+，Python 源码合约测试（`work/*-test.py`）。

**Spec:** `docs/superpowers/specs/2026-10-31-pinned-wheel-design.md`

## Global Constraints

- 不改 bundle id `com.qingshan.orbis`；不运行 xcodegen，新文件手动加入 `dok.xcodeproj/project.pbxproj`。
- 透明窗口里不用 `.blur()`。
- macOS 13+；macOS 26 唤出轮盘的原生玻璃分支不变；13–15 走兼容材质。
- 常驻为关闭时，唤出路径的行为必须完全不变。
- 新文案中英双语（`Resources/{en,zh-Hans}.lproj/Localizable.strings`），名称末尾不加省略号。
- 所有功能免费。遵循"减少动态效果"和触感开关。
- **本项目不提交也不推送，除非用户明确要求。** 每个任务结束时只构建、测试、安装。
- 验证时不反复唤出窗口打断用户，每次改动最多截一次；失败不循环。需要肉眼确认的项目汇总后请用户看。

每个任务的"构建安装"都指：

```bash
xcodebuild -project dok.xcodeproj -scheme dok -configuration Release -derivedDataPath build build CODE_SIGNING_ALLOWED=NO
for t in work/*-test.py; do python3 "$t" || exit 1; done
osascript -e 'quit app id "com.qingshan.orbis"'; rm -rf /Applications/Dok.app && cp -R build/Build/Products/Release/Dok.app /Applications/Dok.app && codesign --force --deep -s - /Applications/Dok.app && open /Applications/Dok.app
```

Shell 命令需要 `dangerouslyDisableSandbox: true`。如果切换架构后构建报 swiftdoc 找不到，换一个新的 `-derivedDataPath`。

## Review Focus

- 外接显示器拔掉或分辨率变小：常驻轮盘和小圆点回到屏幕内，而不是消失在屏幕外（Task 5）。
- 常驻时在设置里改半径、图标大小或增删应用：窗口内容、命中范围和点击穿透区域同步更新（Task 4）。
- 系统休眠唤醒、切换桌面空间后：常驻窗口还在，内容不是空玻璃盘（Task 4）。
- 拖动中按 Esc 或拖出屏幕：不打开任何东西，位置落在屏幕内（Task 5）。
- 轮盘展开时切换模式或关闭常驻：窗口干净退出，不残留监听和 `stream` 进程（Task 3、Task 2）。

---

### Task 0: 桌面层玻璃试验（一次性）

**Files:** 临时改动，试验结束全部还原，不留在代码里。结果写回 spec。

- [ ] **Step 1:** 在 `DokWheelWindow.init` 临时把 level 设为 `NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)`，构建安装。
- [ ] **Step 2:** 用一次 `screencapture` 截桌面无窗口遮挡时的轮盘。通过标准：玻璃透出壁纸，不是空盘，也不是纯灰。
- [ ] **Step 3:** 临时加一个 `setFrameOrigin` 循环移动窗口约 3 秒，看是否闪烁或玻璃掉帧；这一项请用户看一次。
- [ ] **Step 4:** 不通过则按顺序试：更高的桌面层级 → 桌面模式用次一级磨砂材质（`NSVisualEffectView` 兼容路径，只用于常驻窗口）。
- [ ] **Step 5:** 还原临时改动，把结论（层级数值、使用的材质）写进 spec 的"我的技术决定"第 1 条。后续任务用常量 `PinnedWheelWindow.desktopLevel` 和 `usesCompatibilityMaterial` 表达这个结论。

### Task 1: 抽出交互状态和命中判断（行为不变）

**Files:**
- Create: `Sources/dok/WheelInteraction.swift`（加入 pbxproj）
- Modify: `Sources/dok/AppState.swift`、`DokWheelWindow.swift`、`DokWheelView.swift`、`SettingsView.swift`（如预览用到）
- Test: `work/dok-wheel-interaction-state-test.py`

**Interfaces:**
- Produces:
  - `final class WheelInteractionState: ObservableObject`，`@Published` 属性 `selectedIndex: Int?`、`selectedRecentAppIndex: Int?`、`isMenuVisible: Bool`、`centerControlHover: AppState.CenterControlHover?`
  - `struct WheelHitTester`，`init(appState: AppState)`，方法 `slotIndex(at: NSPoint, center: NSPoint) -> Int?`、`satelliteIndex(at: NSPoint, center: NSPoint) -> Int?`、`centerAction(dx: CGFloat, dy: CGFloat) -> WheelCenterAction?`、`isInsideCenterControls(dx: CGFloat, dy: CGFloat) -> Bool`、`isInsideWheel(at: NSPoint, center: NSPoint) -> Bool`（圆盘或任一卫星之内）
  - `enum WheelCenterAction { case openSettings, previousTrack, togglePlayPause, nextTrack, seek(to: TimeInterval) }`
  - `extension AppState { func activate(_ item: AppItem) }`：现有 `launchApp` 的主体
  - `DokWheelView.init(appState:interaction:onAppSelected:onSettingsTapped:)`

- [ ] **Step 1: 写失败的合约测试**：断言 `WheelInteraction.swift` 含上述类型；`AppState.swift` 不再声明 `@Published var selectedIndex`、`isMenuVisible`；`DokWheelWindow` 持有 `let interaction = WheelInteractionState()`；`DokWheelWindow.swift` 不再有 `private func slotIndex`。
- [ ] **Step 2:** 运行 `python3 work/dok-wheel-interaction-state-test.py`，预期 FAIL。
- [ ] **Step 3:** 搬动代码。`appState.selectedIndex` 等全部改为 `interaction.*`。`handleHotKeyUp`、`isContextMenuOpen` 等外部调用保持语义。现有合约测试里写死的字符串随之更新，但断言的含义不变。
- [ ] **Step 4:** 构建安装，全部测试通过。手动确认：唤出、悬停、点击、Esc、音乐控制和右键退出都和之前一样（用户看一次）。

### Task 2: 音乐数据按使用方计数

**Files:**
- Modify: `Sources/dok/NowPlayingService.swift`（`isMenuPresented`、`refreshForMenuPresentation`、`menuDidDismiss`、`updateAdapterStream`）
- Test: `work/dok-now-playing-consumers-test.py`，并更新 `dok-now-playing-on-demand-test.py`

**Interfaces:**
- Produces: `enum NowPlayingConsumer: Hashable { case summonedWheel, pinnedWheel, pinnedOrb }`；`func beginConsuming(_: NowPlayingConsumer)`；`func endConsuming(_: NowPlayingConsumer)`
- `refreshForMenuPresentation()` 等于 `beginConsuming(.summonedWheel)`，`menuDidDismiss()` 等于 `endConsuming(.summonedWheel)`。

- [ ] **Step 1: 写失败的测试**：断言 `private var consumers = Set<NowPlayingConsumer>()`；`updateAdapterStream` 用 `!consumers.isEmpty` 取代 `isMenuPresented`；`nextCardAnimated` 的判断用 `consumersWatching`（`consumers` 里除 `.pinnedOrb` 之外非空）。
- [ ] **Step 2:** 运行，预期 FAIL。
- [ ] **Step 3:** 实现。`hasSnapshotSincePresentation` 只在消费者从"无人观看"变为"有人观看"时复位。小圆点不算"正看着"，收起期间切歌，展开时直接显示不推入。
- [ ] **Step 4:** 构建安装、全部测试。`beginConsuming(.pinnedOrb)` 只在有播放器运行时开 `stream`：没有 `runningMusicApp` 时不启动。

### Task 3: 设置字段、设置页和控制器骨架

**Files:**
- Create: `Sources/dok/PinnedWheelController.swift`（加入 pbxproj）
- Modify: `AppState.swift`、`SettingsView.swift`（`GeneralSettingsView`）、`DokApp.swift`（状态栏菜单、启动）、两份 `Localizable.strings`
- Test: `work/dok-pinned-settings-test.py`

**Interfaces:**
- Produces:
  - `enum PinnedMode: String, Codable, CaseIterable { case off, desktop, floating }`
  - `AppSettings`：`pinnedMode: PinnedMode = .off`、`pinnedDesktopCenter: CGPoint?`、`pinnedOrbCenter: CGPoint?`、`pinnedLocked: Bool = false`，decoder 缺字段回退默认
  - `Notification.Name.pinnedModeChanged`
  - `final class PinnedWheelController`，`init(appState: AppState)`，`func apply(mode: PinnedMode)`，`var isWheelExpanded: Bool`，`func collapse()`

- [ ] **Step 1: 写失败的测试**：断言上述声明；decoder 里有 `?? .off`；通用页有 `SmoothSegmentedControl` 绑定 `pinnedMode`；状态栏菜单有常驻子菜单；中英 strings 都有 `pinned.title`、`pinned.off`、`pinned.desktop`、`pinned.floating`、`pinned.lock`、`pinned.unlock`。
- [ ] **Step 2:** 运行，预期 FAIL。
- [ ] **Step 3:** 实现。文案：常驻 / 关闭 / 桌面 / 置顶 / 锁定位置 / 解锁位置（英文 Pinned / Off / Desktop / Always on top / Lock position / Unlock position）。通用页放在"轮盘"组。`apply` 先完整拆掉当前窗口、监听和消费者，再建新的。此任务里两种模式可以先空实现。
- [ ] **Step 4:** 构建安装、全部测试。确认旧 `settings.json` 读取后模式为关闭。

### Task 4: 桌面模式窗口

**Files:**
- Create: `Sources/dok/PinnedWheelWindow.swift`（加入 pbxproj）
- Modify: `PinnedWheelController.swift`、`DokWheelView.swift`（如需让内容保持可见）
- Test: `work/dok-pinned-window-test.py`

**Interfaces:**
- Consumes: `WheelInteractionState`、`WheelHitTester`、`AppState.activate`、`beginConsuming`
- Produces: `final class PinnedWheelWindow: NSWindow`，`init(appState: AppState, level: NSWindow.Level)`，`func moveCenter(to: NSPoint)`，`var onActivate: ((AppItem) -> Void)?`；`static let desktopLevel`（来自 Task 0）；`var isInteractive: Bool`

- [ ] **Step 1: 写失败的测试**，断言：
  - 窗口尺寸取 `DokWheelView.windowSize`；`collectionBehavior` 含 `.canJoinAllSpaces` 和 `.stationary`。
  - 文件里没有 `addGlobalMonitorForEvents(matching: [.leftMouseDown])` 导致的关闭逻辑，也没有 `dismiss()`。
  - 点击穿透：`ignoresMouseEvents` 只在 `isInsideWheel` 结果变化时写。
  - 含 `occlusionState` 判断，可见时调用 `snapshotRecentApps()`、`snapshotNotificationBadges()` 和 `beginConsuming(.pinnedWheel)`，遮挡时 `endConsuming(.pinnedWheel)`。
  - 监听 `NSWorkspace.didWakeNotification` 和 `activeSpaceDidChangeNotification`。
  - 观察 `appState.$settings`，半径和图标变化后立即重算命中。
- [ ] **Step 2:** 运行，预期 FAIL。
- [ ] **Step 3:** 实现。`interaction.isMenuVisible` 常为 true。全局 `mouseMoved` 监听更新穿透和悬停。点应用调用 `appState.activate`，轮盘不收起；中心控制和进度跳转沿用 `WheelCenterAction`；点齿轮打开设置。右键运行中应用沿用退出菜单。文件拖放沿用现有逻辑，成功后不消失。
- [ ] **Step 4:** 构建安装、全部测试。用户确认：桌面图标从透明四角能点到；普通窗口盖在轮盘上；开关模式干净。

### Task 5: 拖动和位置

**Files:**
- Create: `Sources/dok/PinnedDragTracker.swift`（加入 pbxproj）
- Modify: `PinnedWheelWindow.swift`、`PinnedWheelController.swift`
- Test: `work/dok-pinned-drag-test.py`

**Interfaces:**
- Produces: `struct PinnedDragTracker`，`static let threshold: CGFloat = 4`，`mutating func press(at: NSPoint)`，`mutating func move(to: NSPoint) -> PinnedDragEvent?`，`mutating func release() -> PinnedDragResult`（`.click` / `.dragged`）；`func clampedCenter(_ center: NSPoint, radius: CGFloat, screens: [NSRect]) -> NSPoint`

- [ ] **Step 1: 写失败的测试**，断言：
  - `threshold: CGFloat = 4`。
  - 窗口在 `mouseDown` 时只记录，不执行动作；动作只在 `.click` 分支触发。
  - 拖动中 `interaction.selectedIndex = nil`。
  - `pinnedLocked` 为 true 时不进入拖动。
  - `NSApplication.didChangeScreenParametersNotification` 触发 `clampedCenter`。
  - 拖动中按 Esc 取消并回到原位。
  - 空白处右键菜单切换锁定。
- [ ] **Step 2:** 运行，预期 FAIL。
- [ ] **Step 3:** 实现。开始拖动放大 1.02 倍（减少动态效果时不放大）并 `.levelChange` 触感；松手恢复并 `.alignment` 触感，受 `hapticFeedback` 开关控制。玻璃层不缩放，只缩放内容（见 `DokWheelView` 的注释）。松手保存 `pinnedDesktopCenter` 或 `pinnedOrbCenter`，并夹回屏幕内。
- [ ] **Step 4:** 构建安装、全部测试。用户确认手感：按在图标上拖不打开应用，轻点能打开。

### Task 6: 置顶模式的小圆点

**Files:**
- Create: `Sources/dok/PinnedOrbWindow.swift`、`Sources/dok/PinnedOrbView.swift`（加入 pbxproj）
- Modify: `PinnedWheelController.swift`、两份 strings（如有）
- Test: `work/dok-pinned-orb-test.py`

**Interfaces:**
- Consumes: `PinnedDragTracker`、`PinnedWheelWindow`、`beginConsuming(.pinnedOrb)`
- Produces: `final class PinnedOrbWindow: NSWindow`；常量 `orbDiameter: CGFloat = 44`、`hoverExpandDelay: TimeInterval = 0.15`、`collapseDelay: TimeInterval = 0.25`

- [ ] **Step 1: 写失败的测试**，断言上述常量；level 为 `.popUpMenu`，`collectionBehavior` 含 `.canJoinAllSpaces`、`.fullScreenAuxiliary`；鼠标按下时取消悬停展开；`PinnedOrbView` 不含 `TimelineView(.animation`（低频更新进度）；松手调用 `snappedToEdge`；点应用后调用 `collapse()`。
- [ ] **Step 2:** 运行，预期 FAIL。
- [ ] **Step 3:** 实现。水滴用 SF 形状或 `Circle` 加高光绘制，音乐进度用 `ProgressArcBand`，1Hz 更新。展开：轮盘中心对准小圆点，放不下时用 `clampedCenter` 夹回；展开轮盘不能拖；展开时 `beginConsuming(.pinnedWheel)`，收回时结束。macOS 26+ 用原生玻璃，13–15 用兼容材质。
- [ ] **Step 4:** 构建安装、全部测试。用户确认：路过不展开、全屏应用上可见、吸边后能展开。

### Task 7: 与快捷键共存，收尾

**Files:**
- Modify: `DokApp.swift`（`handleHotKeyDown`）、`AGENTS.md`、`CHANGELOG.md`（版本号由发布时决定）
- Test: `work/dok-pinned-coexist-test.py`

- [ ] **Step 1: 写失败的测试**：`handleHotKeyDown` 开头若 `pinnedController?.isWheelExpanded == true` 则 `collapse()` 并返回；AGENTS.md 写明"常驻是另一扇窗口"的例外和"无常驻 perl"的置顶例外。
- [ ] **Step 2:** 运行，预期 FAIL。
- [ ] **Step 3:** 实现。桌面模式的常驻轮盘不算 expanded，所以快捷键照常弹临时轮盘。鼠标键触发走同一判断。常驻时唤出轮盘互不串状态。
- [ ] **Step 4:** 构建安装、全部测试。把需要肉眼确认的项目汇总给用户，并提醒 macOS 13–15 未实测。
