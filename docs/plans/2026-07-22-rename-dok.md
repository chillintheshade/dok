# 任务：App 改名 Arcly → dok

> 交接文档（2026-07-22）。开工前先读 `AGENTS.md`。
> 时机说明：项目尚未公开发布，这是改名零历史包袱的唯一窗口。
> 本文档写作时仓库处于 commit `525de94`（角标已完成）之后、工作区含
> AGENTS.md 的未提交更新。不要回滚任何现有未提交改动。

## 命名规范

- **用户可见名一律小写 `dok`**：菜单栏、主菜单、设置窗口标题、onboarding、
  README。中文语境写法如「dok 设置」「显示 dok」「退出 dok」。
- **Swift 类型/文件前缀 `Dok`**：`ArclyApp` → `DokApp`、`ArclyWheelView` →
  `DokWheelView`、`ArclyWheelWindow` → `DokWheelWindow`，文件名随类型走。
- **工程产物全部 `dok`**：target、scheme、`PRODUCT_NAME`、
  `CFBundleName`/`CFBundleDisplayName`、生成 `dok.xcodeproj`、产出 `dok.app`。
- **契约测试文件前缀** `arcly-` → `dok-`。

## 铁律：明确不改

- **Bundle ID `com.qingshan.orbis` 一个字符都不动**（更新兼容，AGENTS.md 既有规矩）。
  由它派生的命名空间同样不动（如 `com.qingshan.orbis.dock-notification-badges`
  队列标签、UserDefaults/Application Support 位置）。
- `Vendor/MediaRemoteAdapter/` 整个目录逐字保持，含
  `com.vandenbe.MediaRemoteAdapter` 与 framework 名。
- `docs/plans/` 里既有任务书是历史文档，里面的 Arcly/Orbis 字样**不改**。
- `dist/Arcly-1.0.1.dmg` 是历史产物，不动。
- 本地仓库文件夹名 `orbis` 不改（只是本地路径，与产品无关）。
- 设置窗口 920×520 两 tab、所有既有功能行为：零改动、零回归。

## 执行顺序（两阶段，每阶段结束跑全部测试 + 完整构建）

### 阶段 1：产品层

1. `project.yml`：target 名、scheme、`PRODUCT_NAME`、bundle 显示名改 `dok`
   （bundle ID 不动）；`xcodegen generate` 生成 `dok.xcodeproj`；删除旧
   `Arcly.xcodeproj` 目录（工作区删除即可，commit 由用户执行）。
2. `Resources/{en,zh-Hans}.lproj/Localizable.strings`：所有 `Arcly` 字样 → `dok`
   （`settings.windowTitle`、`menu.show`、`menu.quit`、`onboarding.title` 等）。
3. `README.md`：全部名称、构建命令（`dok.xcodeproj -scheme dok`）、仓库 URL 改
   `github.com/chillintheshade/dok`；预览图引用改新文件名
   `docs/github/dok-wheel-music.png`、`dok-settings-wheel.png`、
   `dok-settings-general.png`，并删除三张旧 `arcly-*.png`
   （新图由用户侧稍后放入，README 短暂悬空引用可接受）。
4. `AGENTS.md`：标题、路径、构建命令、Current State 里的名称同步；项目规矩里
   「`Orbis` and `PieMenu` may appear only in…」扩为把 `Arcly` 也列入
   仅限兼容标识/历史文档的名单。

### 阶段 2：内部标识

5. `Sources/Arcly/` 目录 → `Sources/dok/`；三个 `Arcly*` 类型与文件按命名规范
   重命名；全仓引用同步（`project.yml` sources 路径、`Package.swift` 若涉及）。
6. `work/` 契约测试：路径、锁定字符串、文件名前缀全部跟进；
   `arcly-rename-test.py` 重写为 dok 版命名契约：产品名处处为 `dok`，
   `Arcly`/`Orbis`/`PieMenu` 只允许出现在兼容标识、迁移代码和历史文档中。
7. 代码注释里的 Arcly 字样顺手更新，但 `Sources/Helper/mr_info.swift` 与
   `NowPlayingService.helperScript` 受逐字同步测试锁定：改任何一侧注释必须
   两侧同步，跑 `dok-now-playing-helper-sync-test.py`（改名后）确认。

## 验收

- `for t in work/*-test.py; do python3 "$t" || exit 1; done` 全过。
- `xcodegen generate` + `xcodebuild -project dok.xcodeproj -scheme dok
  -configuration Release build CODE_SIGNING_ALLOWED=NO` 成功。
- 构建产物安装为 `/Applications/dok.app`，ad-hoc 签名；提醒用户删除旧
  `/Applications/Arcly.app`，并重新勾选一次「开机启动」（登录项指向新 app）。
- 实机检查：菜单栏与退出菜单显示 dok；设置窗口标题「dok 设置」；onboarding
  文案为 dok；轮盘、音乐、卫星、角标、右键退出全部零回归。
- 完成后停下等用户实机验收，**不要 commit**。
