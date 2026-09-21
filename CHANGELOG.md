# 更新记录 / Changelog

## 1.4.2 — 2026-09-21

- 应用显示名称统一为 Dok，包括应用包、设置窗口、菜单及中英文提示。
- 保留 com.qingshan.orbis 和原有数据路径，兼容现有配置。
- 构建、回归检查及签名校验通过。沿用 1.4.1 的动画改动，实际动画效果仍待视觉确认。
- Developer ID 已签名，未进行 Apple 公证。

## 1.4.1 — 2026-09-21

- 轮盘选中扇形减淡、边缘柔化，内外两端渐隐。
- 设置侧栏选中背景增加平滑移动与悬停过渡。
- 分段选项使用持续存在的滑块移动，包括最近内容数量 1–4。
- 最近内容开关增加圆钮移动过渡；拖动条支持点按滑动、连续拖动和松开对齐刻度。
- 上述设置控件采用自定义 SwiftUI 外观；玻璃底层保持原有原生实现。尊重系统“减少动态效果”。

验证：Swift Release、Xcode Release 构建及回归检查通过。动画实际效果尚未完成视觉验证。

安装包已使用 Developer ID 签名，未进行 Apple 公证；macOS 可能拦截首次打开。

## 1.4.0 — 2026-09-21

1.4.0 安装包已通过 Developer ID 签名校验，本次发布不进行 Apple 公证；macOS 可能拦截首次打开。

The 1.4.0 installer is Developer ID-signed and is not Apple-notarized. macOS may block the first launch.

### 新增

- 按键动作槽位：直接录入组合键，在轮盘中一键执行；可选指定目标应用。
- 网址槽位支持网站图标和自定义名称。
- 删除轮盘项目后，可在中心撤销并恢复原位置。

### 改善

- macOS 27 主轮盘和卫星采用无额外染色的原生 regular 液态玻璃，移除本地透明度干预。
- 音乐控制按钮增加轻微悬停反馈；进度弧保留原有粗细和颜色。
- 最近内容卫星的运行标记移至圆内，移除原生玻璃边缘的重复裁切。
- 设置页减轻分组底色，增加单色侧栏悬停和键盘导航，移除叠加的焦点边框。
- 关闭音乐显示时停止对应后台监听，重新开启时恢复观察。

### 输入与焦点修正

- 按键动作名称使用支持中文组合输入的原生文本编辑器。
- 修正设置窗口关闭、重开时的延迟激活竞争。
- 应用搜索框只在首次就绪时设置焦点，不再于切换输入法或重新激活时反复抢焦点。
- 搜索框在拼音组合期间不刷新搜索绑定，选词提交后再过滤应用列表。

### 验证状态

- Swift Release 构建、Universal 2 Xcode 构建与回归测试通过。
- 原生搜索框的组合输入、中文提交、通知期间焦点保持及销毁清理测试通过。
- 用户实机确认：冷启动首次打开及再次打开“添加应用”时，微信输入法候选词和中文提交正常。

### English

- Add recorded keyboard-combination slots, website icons and custom names, and undo for wheel-item removal.
- Refine native glass, satellite indicators, music-control hover feedback, and settings navigation.
- Stop music observation when the feature is disabled and resume it when enabled.
- Remove repeated search-field focus reclamation and defer filtering until IME composition commits.
- The user confirmed WeType candidate display and Chinese text submission after a cold launch and after reopening the app picker.
