# 20260413_134934_interaction_intent_phase0_contract_record

## 记录说明

本记录基于当前工作区里“刚刚这次 interaction intent `phase0` 边界冻结”的实际 `git status`、`git diff --stat`、`git diff` 与当前代码状态整理，不包含原始 `git diff` 文本。

本次共涉及 4 个业务代码文件：

- `MyCanvas_Ver_0/Canvas/Input/CanvasInputBoundaryAnchor.swift`
- `MyCanvas_Ver_0/Canvas/Transfer/CanvasTransferTypes.swift`
- `MyCanvas_Ver_0/Canvas/Import/CanvasImportTypes.swift`
- `MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift`

本次工作分支：

- `feat/interaction-intent-phase0`

写入本记录前的代码状态依据：

- `git status --short -- <4 个业务文件>` 显示：
- `M MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift`
- `M MyCanvas_Ver_0/Canvas/Import/CanvasImportTypes.swift`
- `M MyCanvas_Ver_0/Canvas/Transfer/CanvasTransferTypes.swift`
- `?? MyCanvas_Ver_0/Canvas/Input/CanvasInputBoundaryAnchor.swift`
- `git diff --stat -- <3 个已跟踪源码文件>` 统计为：`3 files changed, 6 insertions(+)`
- `git diff --no-index --stat -- /dev/null <新文件>` 统计为：`1 file changed, 5 insertions(+)`
- 本记录文件是随后新增的说明材料，不属于上述 4 个业务代码文件本身。

本记录不包含：

- 原始 `git diff` 文本
- git commit / push
- `phase1` 及后续 `Intent / Decision / Policy` 类型实现

## 时间戳与取证命令

```bash
# 文件路径: 系统命令 /bin/date
# 函数名/命令名: date
# 功能说明: 生成本记录文件名使用的时间戳前缀。
date +"%Y%m%d_%H%M%S"
```

```bash
# 文件路径: 系统命令 /usr/bin/git
# 函数名/命令名: git checkout -b
# 功能说明: 从当前开发分支切出本次 phase0 的独立实施分支。
git checkout -b feat/interaction-intent-phase0
```

```bash
# 文件路径: 系统命令 /usr/bin/git
# 函数名/命令名: git status / git diff
# 功能说明: 提取这次 interaction intent phase0 的真实变更范围与当前工作区状态。
git status --short -- \
  "MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift" \
  "MyCanvas_Ver_0/Canvas/Import/CanvasImportTypes.swift" \
  "MyCanvas_Ver_0/Canvas/Transfer/CanvasTransferTypes.swift" \
  "MyCanvas_Ver_0/Canvas/Input/CanvasInputBoundaryAnchor.swift"

git diff --stat -- \
  "MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift" \
  "MyCanvas_Ver_0/Canvas/Import/CanvasImportTypes.swift" \
  "MyCanvas_Ver_0/Canvas/Transfer/CanvasTransferTypes.swift"

git diff --no-index --stat -- /dev/null \
  "MyCanvas_Ver_0/Canvas/Input/CanvasInputBoundaryAnchor.swift"

git diff -- \
  "MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift" \
  "MyCanvas_Ver_0/Canvas/Import/CanvasImportTypes.swift" \
  "MyCanvas_Ver_0/Canvas/Transfer/CanvasTransferTypes.swift"
```

## 本次 phase0 的目标

这一步没有进入 `phase1` 的 `CanvasInteractionIntent` / `CanvasInteractionDecision` / `CanvasInteractionPolicy` 代码实现，而是只把 `phase0` 计划要求的边界先固化在代码里：

1. 建立 `Canvas/Input/` 目录锚点，给未来 input-intent lane 一个代码级落点。
2. 明确 `CanvasTransferRequest` 是平台 capture 之后、已解析媒体 payload 的结构。
3. 明确 `CanvasImportRequest` 是 transfer 下游、lowering 之后的文档级导入结构。
4. 明确 `CanvasCommand.importMedia(CanvasImportRequest)` 已经属于 command lane，而不是 raw capture input。

## 修改一：新增 `Canvas/Input` 目录锚点

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Input/CanvasInputBoundaryAnchor.swift
// 函数名/符号名: CanvasInputBoundaryAnchor
// 功能说明: 修改前仓库中不存在这个锚点文件，`Canvas/Input/` 目录也还没有代码级边界标记。
// 文件不存在。
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Input/CanvasInputBoundaryAnchor.swift
// 函数名/符号名: CanvasInputBoundaryAnchor
// 功能说明: 修改后新增 phase0 边界锚点，明确未来 input-attempt 类型必须位于 TransferRequest / ImportRequest / importMedia 之前。
// Phase 0 boundary anchor for the future input-intent lane.
//
// Input-attempt types added in later phases must stay upstream of
// CanvasTransferRequest, CanvasImportRequest, and CanvasCommand.importMedia(_).
enum CanvasInputBoundaryAnchor {}
```

### 修改意图

这一步不是开始实现 `Intent` 体系，而是先把目录边界钉住，避免后续把输入尝试类型随手散落到 `Transfer`、`Import` 或 `Editing` 目录里。

## 修改二：冻结 `CanvasTransferRequest` 的语义边界

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Transfer/CanvasTransferTypes.swift
// 函数名/符号名: CanvasTransferRequest
// 功能说明: 修改前这里只有结构定义，没有在代码里明确说明它不是 raw input attempt。
struct CanvasTransferRequest {
    let items: [CanvasTransferItem]
    let placement: CanvasImportPlacement
    let layout: CanvasImportLayout
    let sourceDescription: String
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Transfer/CanvasTransferTypes.swift
// 函数名/符号名: CanvasTransferRequest
// 功能说明: 修改后明确 TransferRequest 只表示 capture 之后、已解析完成的媒体批次，而不是用户的原始输入尝试。
// Transfer requests stay downstream of platform capture. They model already
// resolved media payload plus placement/layout metadata, not raw input attempts.
struct CanvasTransferRequest {
    let items: [CanvasTransferItem]
    let placement: CanvasImportPlacement
    let layout: CanvasImportLayout
    let sourceDescription: String
}
```

### 修改意图

这一步把 `TransferRequest` 的职责固定在“capture 之后、transfer lane 中段”，为后续把 `CanvasInteractionIntent` 放在它之前预留清晰边界。

## 修改三：冻结 `CanvasImportRequest` 的语义边界

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Import/CanvasImportTypes.swift
// 函数名/符号名: CanvasImportRequest
// 功能说明: 修改前这里只有导入请求字段，没有在代码里明确说明它已经是 document-ready 的下游结构。
struct CanvasImportRequest {
    let items: [CanvasImportItem]
    let placement: CanvasImportPlacement
    let layout: CanvasImportLayout
    let presentationTemplate: CanvasImportPresentationTemplate?
    let sourceDescription: String
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Import/CanvasImportTypes.swift
// 函数名/符号名: CanvasImportRequest
// 功能说明: 修改后明确 ImportRequest 位于 TransferRequest 下游，承载的是已经 lower 过的文档级导入内容，而不是 capture intent。
// Import requests stay downstream of transfer requests. They carry document-ready
// media items plus presentation metadata after lowering, not raw capture intents.
struct CanvasImportRequest {
    let items: [CanvasImportItem]
    let placement: CanvasImportPlacement
    let layout: CanvasImportLayout
    let presentationTemplate: CanvasImportPresentationTemplate?
    let sourceDescription: String
}
```

### 修改意图

这一步把 `ImportRequest` 的职责固定在“transfer 下游、command lowering 之前”的桥接位置，避免后续把输入尝试语义误塞进 `Import` 模型。

## 修改四：冻结 `CanvasCommand.importMedia` 的命令车道归属

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift
// 函数名/符号名: CanvasCommand.importMedia
// 功能说明: 修改前枚举 case 直接声明为 importMedia(CanvasImportRequest)，但没有在代码里明确它已经属于 command lane。
enum CanvasCommand {
    case importMedia(CanvasImportRequest)
    case addTextItem
    case beginTextEdit(itemID: CanvasItemID)
    case commitTextEdit
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift
// 函数名/符号名: CanvasCommand.importMedia
// 功能说明: 修改后明确 importMedia 消费的是 ImportRequest，并且它位于 transfer/import lowering 之后的 command lane。
enum CanvasCommand {
    // importMedia lives in the command lane after transfer/import lowering and
    // intentionally consumes CanvasImportRequest instead of raw capture input.
    case importMedia(CanvasImportRequest)
    case addTextItem
    case beginTextEdit(itemID: CanvasItemID)
    case commitTextEdit
}
```

### 修改意图

这一步把 `.importMedia` 和后续计划里的 `command(CanvasCommandID)` 语义边界先钉住，避免后续把 `pasteMenu` / `pasteKeyboardShortcut` 之类 transfer entry 直接误建模成 command。

## 本次明确没有做的事情

- 没有新增 `CanvasInteractionIntent`
- 没有新增 `CanvasInteractionDecision`
- 没有新增 `CanvasInteractionPolicy`
- 没有改 `iOSViewController` / `macOSViewController`
- 没有改 `performTransferRequest(_:)`
- 没有改 `CanvasTransferCommandLowerer`

这和 `phase0` 计划是一致的：先冻结边界，再进入 `phase1` 的 shared 类型骨架。

## 构建验证

```bash
# 文件路径: 系统命令 /usr/bin/xcodebuild
# 函数名/命令名: xcodebuild
# 功能说明: 验证 phase0 边界冻结代码不会破坏现有 macOS 工程构建。
xcodebuild -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -destination "platform=macOS" \
  build
```

验证结果：

- 构建通过
- 本次 4 个业务文件未引入新增 lints

## 结论

这次 `phase0` 的真实落点是“目录锚点 + 现有边界类型契约固化”：

1. `Canvas/Input/` 已经有了代码级锚点。
2. `CanvasTransferRequest` 的职责被明确为 capture 后的 resolved payload。
3. `CanvasImportRequest` 的职责被明确为 transfer 下游的 document-ready request。
4. `CanvasCommand.importMedia` 的职责被明确为 command lane，而不是 capture intent。

因此，后续进入 `phase1` 时，新增 `Intent / Decision / Policy` 类型就有了稳定的上游落点，不需要再反过来重解释现有 `Transfer / Import / Command` 三层的职责。
