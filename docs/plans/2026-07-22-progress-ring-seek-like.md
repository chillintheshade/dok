# 任务：音乐进度环 + 点击跳转 + 喜欢（按优先级）

> 交接文档。开工前先完整阅读本文件和 `AGENTS.md`。
> 本文件描述的现状对应 commit「Adopt perl-based MediaRemote adapter」之后的代码。

## 一、你需要知道的近期变更（不在你的记忆里）

音乐子系统在 2026-07-21 ~ 07-22 被重写过，现状：

1. **常驻 helper 架构**。`NowPlayingService` 不再按次刷新，而是启动一个常驻子进程，
   子进程在播放状态变化时向 stdout 推送一行 JSON。`LineBuffer` 按行重组后
   `apply(_ snapshot:)` 更新 `@Published` 状态。
2. **后端队列**（`backendQueue`，按优先级）：
   - `perlAdapter`（主力）：`/usr/bin/perl` 运行打包在 App 内的
     `MediaRemoteAdapter.framework`（vendor 自 ungive/mediaremote-adapter，BSD-3，
     源码在 `Vendor/MediaRemoteAdapter/`，由 project.yml 的 `MediaRemoteAdapter`
     target 构建，嵌入 App 但**不链接**）。启动参数：
     `perl <mediaremote-adapter.pl> <framework 路径> stream --no-diff`。
     已在本机对 QQ音乐 实测可读到 title/artist/album/duration/elapsedTime/
     timestamp/playbackRate/artworkData/bundleIdentifier。
   - `swiftToolchain`（兜底）：旧方案，脚本交给 CLT/Xcode 的 swift 解释执行。
     脚本内容内嵌在 `NowPlayingService.helperScript`，与
     `Sources/Helper/mr_info.swift` 逐字同步（有契约测试锁定）。
   - 后端启动后 5 秒内退出视为不可用，自动切下一个。
3. **播放控制路由**：perl adapter 活跃时，播放/下一首/上一首分别走一次性
   `send 2/4/5` 命令；adapter 不可用时才退回系统媒体按键。原因是无 Now Playing
   会话所有者时，系统媒体按键会启动默认的 Apple Music。仅因播放器运行而显示的
   占位控制器不立即发送媒体命令，也不激活播放器窗口：播放键只记录一个约 12 秒、
   按 bundle ID 定向的 pending intent；目标播放器随后出现可控会话时，由 perl
   adapter 恰好补发一次 `send 2`。若 payload 已是 playing，则只消费意图，避免反向
   暂停。上一首/下一首不响应。目标播放器优先级为 MediaRemote 会话所有者 → 最近
   激活的已知播放器 → 现有兜底顺序。
4. **封面滞后判定**在 App 侧（`applyArtwork`）：曲目变了但封面字节没变 → 视为
   上一首的封面，暂显占位，1.5 秒后无新封面则认可。
5. 内购层已全部删除；项目 GPL-3.0；vendor 目录 BSD-3 且**保持逐字**（唯一
   例外见下文"喜欢"部分，若确需改动必须在 `Vendor/MediaRemoteAdapter/README.md`
   的 Local changes 段登记）。
6. 契约测试：`for t in work/*-test.py; do python3 "$t" || exit 1; done` 必须全过。
   改 `NowPlayingService` 时注意 `arcly-now-playing-*` 和
   `arcly-mediaremote-adapter-test.py`；改内嵌脚本必须同步 `mr_info.swift`
   （`arcly-now-playing-helper-sync-test.py` 锁定）。
7. 构建流程：`xcodegen generate`（project.yml 变更后）→ swift build 只编译
   App 源码（不含 vendor framework）→ 完整验证用 xcodebuild（见 AGENTS.md）。

## 二、任务 1：进度环（优先做）

**目标**：轮盘中心音乐控制器里，封面外围画一圈细进度环，随播放前进。

要点：

- 数据已经在 perl 后端的 payload 里，目前被 `parseAdapterLine` 丢弃。需要：
  - `NowPlayingSnapshot` 增加 `duration: Double?`、`elapsedTime: Double?`、
    `timestamp: Date?`、`playbackRate: Double?`（adapter 的 `timestamp` 是
    ISO8601 字符串，如 `2026-07-22T01:50:49Z`）。
  - `NowPlayingService` 新增 `@Published` 进度状态。**不要每秒推送 elapsed**：
    存 `elapsedTime + timestamp + playbackRate`，由视图层用 `TimelineView`
    或定时器本地外推：`elapsed = elapsedTime + (now - timestamp) * playbackRate`
    （仅播放中外推；暂停时用原值）。这是 adapter README 推荐的做法。
- swift 兜底后端的脚本不含这些字段。两个选择，任选其一并写明：
  a) 同步扩展内嵌脚本 + `mr_info.swift`（保持逐字同步）；
  b) 兜底后端无进度数据时隐藏进度环（`duration == nil` → 不绘制）。
  倾向 b，改动面小；无论哪种，环在无数据时必须优雅消失而不是显示 0%。
- 绘制位置：`ArclyWheelView.musicController` 的封面 (`musicArtworkSize`) 外围，
  用 `Circle().trim(from:0, to:progress)` 旋转 -90°。风格克制：线宽 ~2pt，
  `Color.primary` 低透明度打底 + accent 前景。所有尺寸乘
  `centerMusicControlScale` 跟随缩放。
- 切歌瞬间进度必须立刻归零重算（跟 trackChanged 走），不要出现上一首的进度
  残影。

## 三、任务 2：点击进度环跳转（seek）

**目标**：点击进度环任意位置，跳到对应播放时间。

要点：

- 命令通道：一次性进程调用
  `/usr/bin/perl <脚本> <framework> seek <微秒>`（注意单位是**微秒**）。
  perl 启动是毫秒级的，一次性 spawn 没有性能问题。给 `NowPlayingService`
  加 `func seek(to seconds: Double)`，内部换算微秒、spawn、不等待输出
  （`standardOutput = FileHandle.nullDevice`）。
- 仅 perl 后端可用。当前活跃后端不是 perlAdapter 时不响应（并且不画可点态）。
- 命中判定在 `ArclyWheelWindow`：现有 `centerClickAction(dx:dy:distance:)` 里
  加一个环形命中带（半径 = 封面半径 + 环偏移 ± ~8pt 容差），由
  `atan2` 算角度 → 比例 → 时间。注意窗口坐标 y 向上、SwiftUI 绘制 -90° 起点，
  两边的角度基准要对齐，先写单元可验证的纯函数再接 UI。
- seek 后乐观更新本地进度（立即跳到目标值），并沿用 `playingFrozenUntil`
  的思路加短暂冻结，防止旧进度回弹。

## 四、任务 3：喜欢（先验证，再决定做不做）

**现状（重要）**：adapter 的 `send` 命令表只有 0-13，**不含喜欢**。
私有头 `MediaRemote.h` 里有 `kMRLikeTrack = 0x6A`，需要带
trackID/stationID/stationHash 的 userInfo 才能发送——上游源码里标记为 TODO，
未实现。读取侧倒是现成的：payload 里可能有 `isLiked` / `supportsIsLiked`。

**执行顺序（严格）**：

1. 先做一个 5 分钟验证，不写任何 UI：临时脚本直接调
   `g_mediaRemote.sendCommand(0x6A, userInfo)`（userInfo 按
   `MediaRemote.h` 注释组装，ID 取自 payload 的 `contentItemIdentifier` 等），
   对 QQ音乐 实测能否改变喜欢状态。
2. 验证失败或行为怪异 → **放弃此任务**，在本文件登记结论即止。QQ音乐 很可能
   根本不响应 MediaRemote 的喜欢命令。
3. 验证成功 → 修改 vendor：给 `adapter_send` 增加 like 分支（或新增
   `adapter_like`），改动登记进 `Vendor/MediaRemoteAdapter/README.md` 的
   Local changes；UI 上在音乐控制器加心形按钮，仅当
   `supportsIsLiked == true` 时显示。

### 验证结论（2026-07-22）

已按上述流程对 QQ音乐 做无 UI 实测，结论为**放弃实现**：

- 选取一首界面明确显示“添加到我喜欢”的未喜欢歌曲作为对照。
- payload 只有 `contentItemIdentifier`，没有 `supportsIsLiked`、`isLiked`、
  `radioStationIdentifier` 或 `radioStationHash`。
- 临时探针向 `MRMediaRemoteSendCommand(0x6A, userInfo)` 传入当前歌曲 ID；API
  返回 `true`，但两秒后 QQ音乐 仍显示“添加到我喜欢”，喜欢数量未变化，后续
  payload 也没有出现喜欢状态。
- 因此 `true` 只能证明系统命令入口接收了请求，不能证明 QQ音乐 执行了喜欢。
  Arcly 不修改 vendor，也不添加无法可靠工作的心形按钮。

## 五、验收

- `python3 work/*-test.py` 全过（新行为补契约测试，沿用现有测试的风格）。
- `xcodegen generate && xcodebuild ...`（AGENTS.md 的完整流程）构建成功。
- 实测：QQ音乐播放中 → 进度环随歌前进；切歌进度立刻重置；点环跳转生效且不回弹；
  暂停时环停住。swift 兜底路径（临时把 backendQueue 首项去掉模拟）下进度环
  隐藏、其余功能正常。
- 设置窗口保持 920×520 两个 tab 不变；轮盘交互（选中、启动 App）零回归。

## 六、进度显示稳定性补充（2026-07-22）

- 进度环最终移至中心圆边界，只绘制已播放弧；未播放轨道、中心边界和头部圆点
  在所有状态下都不绘制。
- `playbackProgress(at:)` 对 helper 小于 `1.5s` 的双向偏差做渐进收敛：沿上次
  已显示基准继续外推，每次只吸收 `8%` 差值，避免进度弧周期性前蹦或后退。
- 差距达到 `1.5s`、切歌、暂停/恢复或 Arcly 发起 seek 时允许重置；切歌归零
  和 seek 乐观冻结规则保持不变。
