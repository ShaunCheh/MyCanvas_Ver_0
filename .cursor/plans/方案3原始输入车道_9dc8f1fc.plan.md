---
name: 方案3原始输入车道
overview: 将刚刚关于“方案 3”的回答固化为严格一致的分阶段计划：在现有方案 4 之上新增 Raw Input Lane，再接 Interaction Lane 与 Indicator Lane，双端按阶段落地且不推翻既有输入意图收敛成果。
todos:
  - id: phase0-freeze-three-lanes
    content: 冻结 Raw Input Lane、Interaction Lane、Indicator Lane 的职责边界与非目标项。
    status: pending
  - id: phase1-build-shared-raw-input
    content: 新增 shared raw-input 契约、routing resolver 与基础单测。
    status: pending
  - id: phase2-unify-controller-ingress
    content: 在 iOS/macOS controller 建立统一 raw-input ingress，先接低风险 capture 入口。
    status: pending
  - id: phase3-build-shared-indicator-ui
    content: 实现 shared 胶囊栈 host view、queue、formatter 与布局求解器。
    status: pending
  - id: phase4-wire-macos-raw-input
    content: 接通 macOS 键盘、左/右键、滚动与缩放的 raw-input 投递与去重。
    status: pending
  - id: phase5-wire-ios-raw-input
    content: 接通 iOS/iPadOS 快捷键、触控与基础间接输入的 raw-input 投递。
    status: pending
  - id: phase6-bridge-text-editor-responder
    content: 处理文本编辑态 responder 切换，保证快捷键指示器持续可用。
    status: pending
  - id: phase7-route-business-intents
    content: 把部分 raw input 继续下沉到现有 interaction lane 与 shared policy。
    status: pending
  - id: phase8-cleanup-and-verify
    content: 清理重复入口与临时桥接，补齐测试与双端回归矩阵。
    status: pending
isProject: false
---

# 方案3分阶段计划

## 总体目标

在现有 [MyCanvas_Ver_0/Canvas/Input/CanvasInteractionIntent.swift](MyCanvas_Ver_0/Canvas/Input/CanvasInteractionIntent.swift) 与 [MyCanvas_Ver_0/Canvas/Input/CanvasInteractionPolicy.swift](MyCanvas_Ver_0/Canvas/Input/CanvasInteractionPolicy.swift) 之上新增一条 `Raw Input Lane`，形成统一链路：

`Platform Capture -> CanvasRawInputIntent -> CanvasInputRoutingResolver -> { CanvasInputIndicatorEvent, CanvasInteractionIntent? } -> CanvasInteractionPolicy -> 平台执行/反馈`

这条链路的目标不是把“鼠标键盘指示器”直接做成给 `CanvasInteractionIntent` 扩 case，而是在其上游补一层真正的原始输入语义层；现有 `方案4` 保持为下游业务意图层，继续复用而不推翻。

## 关键原则

- 新增 `Raw Input Lane`，但不把所有鼠标键盘事实直接塞进现有 `CanvasInteractionIntent`；`CanvasInteractionIntent` 继续承载业务语义。
- 保留 [MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift](MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift) 与 [MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift](MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift) 作为平台 capture 分岔点；统一点落在 controller 归一入口之后。
- 展示层放到双端现有 `chromeOverlayView` 所在 chrome lane，布局复用 [MyCanvas_Ver_0/Platform/Shared/CanvasChromeLayoutContext.swift](MyCanvas_Ver_0/Platform/Shared/CanvasChromeLayoutContext.swift)，避免与 toolbar / minimap / button chrome 撞车。
- `Indicator Lane` 只消费可展示事件，不反向污染 `CanvasCommand`；像 `Command + C`、`Left Click`、`Tap` 这类输入事实优先从原始输入层捕获，而不是从命令执行结果反推。
- 双端首版都交付，但语义按平台事实落地：`macOS` 优先完整桌面输入语义，`iOS/iPadOS` 优先键盘组合键与触控/间接输入语义；`iPhone Mirroring` 首版按 UIKit 能稳定观测到的事实事件展示。

## 现状锚点

- [MyCanvas_Ver_0/Canvas/Input/CanvasInteractionIntent.swift](MyCanvas_Ver_0/Canvas/Input/CanvasInteractionIntent.swift) 当前仍是业务语义层，不是物理输入总线。
- [MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift](MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift) 与 [MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift](MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift) 已经分别在 `setupCanvasViewport()` 内汇总 pointer / touch capture，是上提 raw-input ingress 的最佳落点。
- [MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift](MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift) 已具备 `first responder + UIKeyCommand` 基础，但目前只覆盖 `Command + V`。
- [MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasTextEditorOverlayView.swift](MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasTextEditorOverlayView.swift) 与 [MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasTextEditorOverlayView.swift](MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasTextEditorOverlayView.swift) 会在文本编辑态切走 responder，这会影响键盘指示器，需要单独分 phase 处理。

## Phase 0：冻结三层车道边界

- 目标：冻结 `Raw Input Lane / Interaction Lane / Indicator Lane` 的职责边界，避免后续边做边改模型。
- 新增契约只先定名不接运行时：`CanvasRawInputIntent`、`CanvasRawInputSource`、`CanvasKeyChord`、`CanvasInputIndicatorEvent`、`CanvasInputRoutingResult`、`CanvasInputRoutingResolver`。
- 非目标冻结：不做系统级全局输入监听；不显示普通逐字输入与 IME 组合过程；不把 `NSEvent` / `UIEvent` 直接泄漏到 shared；不把平台 `deliverySource` 细节放进 shared domain。
- 主要文件：继续以 [MyCanvas_Ver_0/Canvas/Input/CanvasInteractionIntent.swift](MyCanvas_Ver_0/Canvas/Input/CanvasInteractionIntent.swift) 和 [MyCanvas_Ver_0/Canvas/Input/CanvasInteractionPolicy.swift](MyCanvas_Ver_0/Canvas/Input/CanvasInteractionPolicy.swift) 为既有边界真源，新契约计划新增到 `MyCanvas_Ver_0/Canvas/Input/`。
- 完成标志：不再争论“Left Click / Tap / Command+C”是否直接属于 `CanvasInteractionIntent`；所有 phase 都基于三层车道模型展开。

## Phase 1：搭 shared raw-input 骨架

- 目标：新增 raw-input 的 shared 纯模型与 resolver，但暂时不切任何真实入口。
- 计划新增文件：`MyCanvas_Ver_0/Canvas/Input/CanvasRawInputIntent.swift`、`MyCanvas_Ver_0/Canvas/Input/CanvasInputIndicatorEvent.swift`、`MyCanvas_Ver_0/Canvas/Input/CanvasInputRoutingResult.swift`、`MyCanvas_Ver_0/Canvas/Input/CanvasInputRoutingResolver.swift`。
- 关键约束：不是每个 raw input 都必须降成 `CanvasInteractionIntent`；例如 `Command + V` 需要导出 `.transferEntry(.pasteKeyboardShortcut)`，但 `Left Click` 在首版可以只生成 indicator event，不强行进入 business lane。
- 主要测试：新增 `CanvasInputRoutingResolverTests` 与 `CanvasInputIndicatorEventTests`，只验证 shared 映射，不依赖 controller。
- 完成标志：shared 层可以在纯测试中验证 `raw input -> indicator event / interaction intent` 的归一路径。

## Phase 2：在 controller 建立统一 ingress

- 目标：双端所有硬件/触控输入尝试先汇合到一个 controller 归一入口，再分流到 indicator 与 interaction lane。
- 建议新增统一桥接函数：`handleCapturedInput(_ rawInput: CanvasRawInputIntent, source: ..., continueIfAllowed: ...)`。
- 优先迁移低风险入口：iOS 的 `keyCommands`、macOS 的 `paste(_:)`、macOS 的 `handleSupplementalKeyboardCapture(_:)`；现有下游 `handleTransferEntryAttempt(...)`、`performCommand(_:)` 与 pointer 编辑逻辑先不改语义。
- 主要文件：[MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift](MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift)、[MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift](MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift)。
- 完成标志：controller 已有统一 raw-input ingress，可同时吐出 `rawInput` 与 `derived interaction intent` 日志，但用户侧还看不到胶囊 UI。

## Phase 3：做 shared 指示器展示层

- 目标：实现胶囊栈 UI、队列、格式化与渐隐动画，作为纯展示层挂到双端 chrome overlay。
- 计划新增文件：`MyCanvas_Ver_0/Platform/Shared/InputIndicator/CanvasInputIndicatorHostView.swift`、`MyCanvas_Ver_0/Platform/Shared/InputIndicator/CanvasInputIndicatorQueue.swift`、`MyCanvas_Ver_0/Platform/Shared/InputIndicator/CanvasInputIndicatorFormatter.swift`、`MyCanvas_Ver_0/Platform/Shared/InputIndicator/CanvasInputIndicatorLayoutSolver.swift`。
- 结构要求：参考现有 shared host 方案，不让 host view 负责 capture；队列负责新事件入栈、旧事件上推、渐隐和超时移除。
- 布局要求：挂在双端 `chromeOverlayView`，布局复用 [MyCanvas_Ver_0/Platform/Shared/CanvasChromeLayoutContext.swift](MyCanvas_Ver_0/Platform/Shared/CanvasChromeLayoutContext.swift)，以 toolbar / minimap / backButton / workspaceModeButton 为 blocker 计算底部可用区。
- 主要文件：[MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift](MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift)、[MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift](MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift)、[MyCanvas_Ver_0/Platform/Shared/CanvasChromeLayoutContext.swift](MyCanvas_Ver_0/Platform/Shared/CanvasChromeLayoutContext.swift)。
- 完成标志：可以通过假数据注入稳定看到底部胶囊栈、上推动画与渐隐移除。

## Phase 4：接通 macOS raw input

- 目标：先把 macOS 做成完整桌面输入语义。
- 输入来源：继续复用 [MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift](MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift) 的 `onPointerDown / onSecondaryClick / onPan / onZoom`，并扩展 [MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift](MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift) 的 `NSEvent.addLocalMonitorForEvents` 观察键盘组合键。
- 首批事件：`Command + C`、`Command + V`、`Command + Z`、`Shift + Command + Z`、`Left Click`、`Right Click`、`Scroll`、`Zoom`。
- 风险与边界：现有 `pasteKeyboardShortcut` 补充 monitor 已存在，新通用 keyboard observer 必须与标准 responder 路径去重；编辑模式继续让标准路径负责真实执行，observer 只做观察与 raw-input 投递。
- 完成标志：macOS 上 copy / paste / click / scroll / zoom 都能稳定冒泡且不双发。

## Phase 5：接通 iOS / iPadOS raw input

- 目标：让 `iPhone / iPad + 蓝牙键盘 / 触控 / Mirroring` 至少进入统一输入总线。
- 键盘路径：扩展 [MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift](MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift) 的 `keyCommands`，首批覆盖 `Command + C / V / Z / Shift + Command + Z`。
- 触控/手势路径：复用 [MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift](MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift) 的 `onPointerDown / onLongPress / onPan / onZoom`。
- 首版展示语义：`Tap`、`Long Press`、`Scroll`、`Pinch`、`Command + ...`；`iPad pointer / iPhone Mirroring` 在未验证到稳定的桌面点击语义前，按 UIKit 能观测到的事实事件显示，不贸然统一成 `Left Click`。
- 完成标志：iOS / iPadOS 已能稳定显示高价值快捷键与基本手势输入。

## Phase 6：补文本编辑 responder 桥

- 目标：解决文本编辑态 controller 不再是 first responder 时，键盘指示器可能失效的问题。
- 原因锚点：[MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasTextEditorOverlayView.swift](MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasTextEditorOverlayView.swift) 与 [MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasTextEditorOverlayView.swift](MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasTextEditorOverlayView.swift) 都会在编辑态切走 responder。
- 处理策略：macOS 优先继续复用 monitor，尽量不侵入 `NSTextView`；iOS 视验证结果决定是否在 `UITextView` 侧补 forwarding。
- 首版边界：文本编辑态只显示快捷键，不显示每个字符输入，不碰 IME 组合态。
- 完成标志：文本编辑开启时，`Command + C / V / Z` 仍可显示，且不破坏现有编辑行为。

## Phase 7：把更多 business intent 接到 raw-input lane

- 目标：让 raw-input lane 不只是给 indicator 看，而是逐步喂给现有 interaction lane。
- 优先迁移：`right click / long press -> contextMenuRequest`；`Command + V -> transferEntry(.pasteKeyboardShortcut)`；`Command + Z / Shift + Command + Z` 视需要统一转成 `.command(.undo/.redo)`。
- 暂缓项：selection / crop / drag 这类 pointer-heavy 编辑态不在这一阶段整体迁移，避免把“输入可视化”扩成一次性大重构。
- 主要文件：[MyCanvas_Ver_0/Canvas/Input/CanvasInteractionIntent.swift](MyCanvas_Ver_0/Canvas/Input/CanvasInteractionIntent.swift)、[MyCanvas_Ver_0/Canvas/Input/CanvasInteractionPolicy.swift](MyCanvas_Ver_0/Canvas/Input/CanvasInteractionPolicy.swift)、[MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift](MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift)、[MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift](MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift)。
- 完成标志：现有 `方案4` 的 interaction lane 开始真正复用 raw-input lane 的统一上游输入。

## Phase 8：清理重复入口、补齐测试与回归矩阵

- 目标：收口迁移期重复桥接、安全网与临时日志，形成稳定可回归的双端输入体系。
- 清理顺序：先删已被 raw-input ingress 完全覆盖的重复 observer / helper，再删 controller 内 indicator 直连逻辑，最后收敛旧日志。
- 测试补齐：`CanvasInputRoutingResolverTests`、`CanvasInputIndicatorFormatterTests`、`CanvasInputIndicatorQueueTests`，必要时补 controller bridge tests。
- 手工回归矩阵：`macOS` 的鼠标/触控板/快捷键/阅读模式/编辑模式/文本编辑态；`iPad` 的触控/蓝牙键盘/触控板；`iPhone` 的蓝牙键盘/镜像输入/文本编辑态。
- 完成标志：不双发、不丢发、不破坏 responder、不与 toolbar / minimap 撞位。

## 里程碑建议

- 里程碑 1：`Phase 0 ~ 3`，架构成型，UI 可注入，但尚未完整对外可见。
- 里程碑 2：`Phase 4 ~ 5`，双端主路径用户可见，达到可交付 v1。
- 里程碑 3：`Phase 6 ~ 8`，文本编辑、镜像输入、清理与稳定性补齐，达到架构收敛版。

## 关键取舍

- 不把“鼠标键盘指示器”直接做成给 [MyCanvas_Ver_0/Canvas/Input/CanvasInteractionIntent.swift](MyCanvas_Ver_0/Canvas/Input/CanvasInteractionIntent.swift) 扩 case；而是在其上游新增 `Raw Input Lane`。
- 不推翻已经完成的 `方案4`；现有 interaction policy 与 business lane 继续作为下游复用。
- 双端一起交付，但按平台事实语义落地，而不是强求 `iOS / iPadOS / iPhone Mirroring` 在首版完全等价于 `macOS` 的桌面鼠标语义。

