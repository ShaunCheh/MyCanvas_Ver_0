# 20260413_174630_raw_input_lane_phase0_record

## 记录说明

本记录基于当前工作区里“刚刚这次 raw input lane `phase0` 三车道边界冻结”的实际 `git status`、`git diff --stat`、`git diff`、当前代码状态、构建结果与诊断结果整理，不包含原始 `git diff` 文本。

本次共涉及 8 个业务代码文件：

- `MyCanvas_Ver_0/Canvas/Input/CanvasInputBoundaryAnchor.swift`
- `MyCanvas_Ver_0/Canvas/Input/CanvasRawInputIntent.swift`
- `MyCanvas_Ver_0/Canvas/Input/CanvasInputIndicatorEvent.swift`
- `MyCanvas_Ver_0/Canvas/Input/CanvasInputRoutingResult.swift`
- `MyCanvas_Ver_0/Canvas/Input/CanvasInputRoutingResolver.swift`
- `MyCanvas_Ver_0/Canvas/Input/CanvasInteractionIntent.swift`
- `MyCanvas_Ver_0/Canvas/Input/CanvasInteractionDecision.swift`
- `MyCanvas_Ver_0/Canvas/Input/CanvasInteractionPolicy.swift`

本次工作分支：

- `feat/cross-platform-input-indicator`

写入本记录前的代码状态依据：

- `git status --short --branch` 显示当前位于 `feat/cross-platform-input-indicator`
- 当前 changes 包含 `4` 个已跟踪文件修改与 `4` 个新文件新增：
  - `M MyCanvas_Ver_0/Canvas/Input/CanvasInputBoundaryAnchor.swift`
  - `M MyCanvas_Ver_0/Canvas/Input/CanvasInteractionDecision.swift`
  - `M MyCanvas_Ver_0/Canvas/Input/CanvasInteractionIntent.swift`
  - `M MyCanvas_Ver_0/Canvas/Input/CanvasInteractionPolicy.swift`
  - `?? MyCanvas_Ver_0/Canvas/Input/CanvasInputIndicatorEvent.swift`
  - `?? MyCanvas_Ver_0/Canvas/Input/CanvasInputRoutingResolver.swift`
  - `?? MyCanvas_Ver_0/Canvas/Input/CanvasInputRoutingResult.swift`
  - `?? MyCanvas_Ver_0/Canvas/Input/CanvasRawInputIntent.swift`
- `git diff --stat -- <4 个已跟踪文件>` 统计为：`4 files changed, 27 insertions(+), 4 deletions(-)`
- `git diff --no-index --stat -- /dev/null <4 个新文件>` 分别统计为：
  - `CanvasRawInputIntent.swift`: `1 file changed, 12 insertions(+)`
  - `CanvasInputIndicatorEvent.swift`: `1 file changed, 5 insertions(+)`
  - `CanvasInputRoutingResult.swift`: `1 file changed, 5 insertions(+)`
  - `CanvasInputRoutingResolver.swift`: `1 file changed, 5 insertions(+)`
- 合并观察后，本次 `phase0` 当前业务代码总量为：`8 files changed, 54 insertions(+), 4 deletions(-)`
- 本记录文件是随后新增的说明材料，不属于上述 8 个业务代码文件本身。

本记录不包含：

- 原始 `git diff` 文本
- git commit / push
- `phase1` 的具体 case、字段与 resolver 运行时实现
- `iOSViewController` / `macOSViewController` 的接线改造

## 时间戳与取证命令

```bash
# 文件路径: 系统命令 /bin/date
# 函数名/命令名: date
# 功能说明: 生成本记录文件名使用的时间戳前缀。
date +"%Y%m%d_%H%M%S"
```

`date` 实际输出：`20260413_174630`

```bash
# 文件路径: 系统命令 /usr/bin/git
# 函数名/命令名: git checkout -b
# 功能说明: 从当前输入架构开发分支切出本次长期实施分支。
git checkout -b feat/cross-platform-input-indicator
```

```bash
# 文件路径: 系统命令 /usr/bin/git
# 函数名/命令名: git status / git diff
# 功能说明: 提取这次 raw input lane phase0 的真实变更范围与当前工作区状态。
git status --short --branch

git diff --stat -- \
  "MyCanvas_Ver_0/Canvas/Input/CanvasInputBoundaryAnchor.swift" \
  "MyCanvas_Ver_0/Canvas/Input/CanvasInteractionDecision.swift" \
  "MyCanvas_Ver_0/Canvas/Input/CanvasInteractionIntent.swift" \
  "MyCanvas_Ver_0/Canvas/Input/CanvasInteractionPolicy.swift"

git diff -- \
  "MyCanvas_Ver_0/Canvas/Input/CanvasInputBoundaryAnchor.swift" \
  "MyCanvas_Ver_0/Canvas/Input/CanvasInteractionDecision.swift" \
  "MyCanvas_Ver_0/Canvas/Input/CanvasInteractionIntent.swift" \
  "MyCanvas_Ver_0/Canvas/Input/CanvasInteractionPolicy.swift"

git diff --no-index --stat -- /dev/null \
  "MyCanvas_Ver_0/Canvas/Input/CanvasRawInputIntent.swift"

git diff --no-index --stat -- /dev/null \
  "MyCanvas_Ver_0/Canvas/Input/CanvasInputIndicatorEvent.swift"

git diff --no-index --stat -- /dev/null \
  "MyCanvas_Ver_0/Canvas/Input/CanvasInputRoutingResult.swift"

git diff --no-index --stat -- /dev/null \
  "MyCanvas_Ver_0/Canvas/Input/CanvasInputRoutingResolver.swift"
```

## 本次 phase0 的真实目标

这一步没有进入 `phase1` 的字段设计、resolver 映射逻辑或平台接线，而是只把三车道边界先固化在 `Canvas/Input` 目录里：

1. 明确 `Raw Input Lane` 是平台捕获后的原始输入事实层。
2. 明确 `Interaction Lane` 继续由现有 `CanvasInteractionIntent` / `CanvasInteractionPolicy` 承担，不被 raw input 直接替代。
3. 明确 `Indicator Lane` 是未来胶囊提示 UI 的展示事件层，不反向污染 `CanvasCommand`。
4. 预留 `CanvasRawInputIntent`、`CanvasInputIndicatorEvent`、`CanvasInputRoutingResult`、`CanvasInputRoutingResolver` 这些 shared 契约名，但不提前引入运行时语义。

## 修改一：扩充 `CanvasInputBoundaryAnchor` 的三车道边界说明

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Input/CanvasInputBoundaryAnchor.swift
// 函数名/符号名: CanvasInputBoundaryAnchor
// 功能说明: 修改前这里只有面向旧 input-intent lane 的单一边界锚点，还没有冻结 Raw Input / Interaction / Indicator 三车道职责。
// Phase 0 boundary anchor for the future input-intent lane.
//
// Input-attempt types added in later phases must stay upstream of
// CanvasTransferRequest, CanvasImportRequest, and CanvasCommand.importMedia(_).
enum CanvasInputBoundaryAnchor {}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Input/CanvasInputBoundaryAnchor.swift
// 函数名/符号名: CanvasInputBoundaryAnchor
// 功能说明: 修改后把三车道边界与 phase0 非目标直接冻结在代码注释里，成为后续 raw input lane 的边界真源。
// Phase 0 boundary anchor for the three-lane input architecture.
//
// Raw Input Lane:
// Physical or system input facts observed by platform capture. These types must
// stay upstream of CanvasTransferRequest, CanvasImportRequest, and
// CanvasCommand.importMedia(_).
//
// Interaction Lane:
// Shared business intents and policy decisions that stay downstream of raw
// input routing. Existing CanvasInteractionIntent and CanvasInteractionPolicy
// remain the source of truth for this lane.
//
// Indicator Lane:
// Presentation-only events consumed by the future input indicator UI. This lane
// must not mutate CanvasCommand or replace business intent routing.
//
// Phase 0 non-goals:
// - No system-wide global input capture.
// - No plain text character stream or IME composition modeling.
// - No NSEvent or UIEvent leakage into shared input types.
// - No platform delivery-source details inside shared domain contracts.
enum CanvasInputBoundaryAnchor {}
```

### 修改意图

这一步的作用不是实现任何功能，而是把“什么属于 raw input、什么属于 interaction、什么属于 indicator”先写死，避免后续阶段再把职责混回 `Transfer`、`Import`、`Command` 或现有 interaction policy。

## 修改二：新增 `CanvasRawInputIntent` 契约锚点

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Input/CanvasRawInputIntent.swift
// 函数名/符号名: CanvasRawInputSource / CanvasKeyChord / CanvasRawInputIntent
// 功能说明: 修改前仓库中不存在 raw-input lane 的 shared 契约文件。
// 文件不存在。
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Input/CanvasRawInputIntent.swift
// 函数名/符号名: CanvasRawInputSource / CanvasKeyChord / CanvasRawInputIntent
// 功能说明: 修改后新增 raw-input lane 的命名锚点，只冻结上游契约名，不引入具体 case 和字段。
import Foundation

// Phase 0 reserves the upstream raw-input lane for physical or system input
// facts captured on platform edges. Concrete cases arrive in later phases.
enum CanvasRawInputSource: Equatable, Sendable {}

// Shared key-chord naming stays upstream of command or transfer lowering.
struct CanvasKeyChord: Equatable, Sendable {}

// Raw input facts are not business intents and must not be added to
// CanvasInteractionIntent.
enum CanvasRawInputIntent: Equatable, Sendable {}
```

### 修改意图

这一步只冻结“原始输入事实层”的命名，不进入具体键盘、鼠标、触控 case，确保 `phase1` 能在一个明确的 shared 文件上继续展开，而不是把原始输入事实塞进现有 `CanvasInteractionIntent`。

## 修改三：新增 `CanvasInputIndicatorEvent` 契约锚点

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Input/CanvasInputIndicatorEvent.swift
// 函数名/符号名: CanvasInputIndicatorEvent
// 功能说明: 修改前仓库中不存在 indicator lane 的 shared 展示事件契约。
// 文件不存在。
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Input/CanvasInputIndicatorEvent.swift
// 函数名/符号名: CanvasInputIndicatorEvent
// 功能说明: 修改后新增 indicator lane 的占位契约，明确未来胶囊提示消费的是展示事件而不是命令对象。
import Foundation

// Phase 0 reserves the indicator lane for presentation-only events consumed by
// the future input indicator UI.
struct CanvasInputIndicatorEvent: Equatable, Sendable {}
```

### 修改意图

这一步把“展示事件”从一开始就独立出来，避免后续为了冒一个胶囊而直接复用 `CanvasCommand` 或 `CanvasInteractionIntent`。

## 修改四：新增 `CanvasInputRoutingResult` 契约锚点

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Input/CanvasInputRoutingResult.swift
// 函数名/符号名: CanvasInputRoutingResult
// 功能说明: 修改前仓库中不存在 raw input 到 interaction / indicator 的 shared 结果结构。
// 文件不存在。
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Input/CanvasInputRoutingResult.swift
// 函数名/符号名: CanvasInputRoutingResult
// 功能说明: 修改后新增 routing 结果占位，后续用于承接 raw input 分流到 indicator 与 interaction lane 的共享返回值。
import Foundation

// Phase 0 reserves the shared handoff from raw input into indicator and
// interaction lanes. Concrete fields are intentionally deferred to phase 1.
struct CanvasInputRoutingResult: Equatable, Sendable {}
```

### 修改意图

这一步先把“分流结果”这件事钉住，后续才能在 `phase1` 明确哪些 raw input 只产生 indicator event，哪些还会继续导出 `CanvasInteractionIntent`。

## 修改五：新增 `CanvasInputRoutingResolver` 契约锚点

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Input/CanvasInputRoutingResolver.swift
// 函数名/符号名: CanvasInputRoutingResolver
// 功能说明: 修改前仓库中不存在 raw-input lane 的 shared routing resolver。
// 文件不存在。
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Input/CanvasInputRoutingResolver.swift
// 函数名/符号名: CanvasInputRoutingResolver
// 功能说明: 修改后新增 shared routing 边界占位，明确后续 raw input -> indicator / interaction 的收敛点在 shared 层。
import Foundation

// Phase 0 reserves the shared boundary that will translate raw input facts
// into indicator events and optional interaction intents in later phases.
struct CanvasInputRoutingResolver: Sendable {}
```

### 修改意图

这一步不是写 resolver 逻辑，而是先把“统一收敛点”定下来，避免后续直接在 `iOSViewController` / `macOSViewController` 里散落一堆 ad-hoc mapping。

## 修改六：收紧 `CanvasInteractionIntent` 的职责说明

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Input/CanvasInteractionIntent.swift
// 函数名/符号名: CanvasTransferEntryIntent / CanvasInteractionIntent
// 功能说明: 修改前注释只强调它位于 transfer/import lowering 之前，但没有明确它属于 downstream interaction lane。
import Foundation

// Shared interaction intents stay upstream of transfer/import lowering.
enum CanvasTransferEntryIntent: Equatable, Sendable {
    case pasteKeyboardShortcut
    case pasteMenu
    case importButton
    case dragAndDrop
}

enum CanvasInteractionIntent: Equatable, Sendable {
    case transferEntry(CanvasTransferEntryIntent)
    case command(CanvasCommandID)
    case contextMenuRequest
    case beginTextEdit(itemID: CanvasItemID)
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Input/CanvasInteractionIntent.swift
// 函数名/符号名: CanvasTransferEntryIntent / CanvasInteractionIntent
// 功能说明: 修改后明确 InteractionIntent 属于 downstream interaction lane，而原始键盘/鼠标/触控事实必须去上游的 CanvasRawInputIntent。
import Foundation

// Shared interaction intents live in the downstream interaction lane.
// Raw keyboard, pointer, and touch facts belong to CanvasRawInputIntent.
// These intents still stay upstream of transfer/import lowering.
enum CanvasTransferEntryIntent: Equatable, Sendable {
    case pasteKeyboardShortcut
    case pasteMenu
    case importButton
    case dragAndDrop
}

enum CanvasInteractionIntent: Equatable, Sendable {
    case transferEntry(CanvasTransferEntryIntent)
    case command(CanvasCommandID)
    case contextMenuRequest
    case beginTextEdit(itemID: CanvasItemID)
}
```

### 修改意图

这一步是在现有 `方案4` 的基础上“收紧职责”，而不是改模型本身。它明确声明：`CanvasInteractionIntent` 继续做业务意图，不吸收 `Left Click`、`Tap`、`Command + C` 这类原始输入事实。

## 修改七：收紧 `CanvasInteractionDecision` 的职责说明

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Input/CanvasInteractionDecision.swift
// 函数名/符号名: CanvasInteractionEnvironment / CanvasInteractionDecision
// 功能说明: 修改前这里只有 environment 和 decision 结构，没有在文件头说明它依赖的是已经归一好的业务意图。
import Foundation

struct CanvasInteractionEnvironment: Equatable, Sendable {
    let workspaceMode: CanvasWorkspaceMode
    let isTransitionInteractionFrozen: Bool
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Input/CanvasInteractionDecision.swift
// 函数名/符号名: CanvasInteractionEnvironment / CanvasInteractionDecision
// 功能说明: 修改后明确 shared decision 发生在 raw-input routing 之后，只消费已经归一好的业务意图。
import Foundation

// Shared interaction decisions stay in the downstream interaction lane after
// raw-input routing has already normalized hardware facts into business intents.
struct CanvasInteractionEnvironment: Equatable, Sendable {
    let workspaceMode: CanvasWorkspaceMode
    let isTransitionInteractionFrozen: Bool
}
```

### 修改意图

这一步把 decision 层的时序位置写清楚，避免后续把 `CanvasInteractionDecision` 错当成“直接判原始键鼠事件”的第一层。

## 修改八：收紧 `CanvasInteractionPolicy` 的职责说明

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Input/CanvasInteractionPolicy.swift
// 函数名/符号名: CanvasInteractionPolicy
// 功能说明: 修改前 policy 文件本身没有明确声明它只负责 downstream business intent 的 allow/block 判定。
import Foundation

struct CanvasInteractionPolicy {
    func decision(
        for intent: CanvasInteractionIntent,
        environment: CanvasInteractionEnvironment
    ) -> CanvasInteractionDecision {
        if environment.isTransitionInteractionFrozen {
            return .block(reason: .transitionInteractionFrozen, feedback: nil)
        }

        // ... 后续 policy 判定逻辑保持不变，这里只展示文件头与变更附近上下文 ...
    }
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Input/CanvasInteractionPolicy.swift
// 函数名/符号名: CanvasInteractionPolicy
// 功能说明: 修改后明确 policy 只评估 downstream business intent，raw input capture 与 indicator-only event 保持在相邻车道。
import Foundation

// Shared policy evaluates downstream business intents only.
// Raw input capture and indicator-only events stay in adjacent lanes.
struct CanvasInteractionPolicy {
    func decision(
        for intent: CanvasInteractionIntent,
        environment: CanvasInteractionEnvironment
    ) -> CanvasInteractionDecision {
        if environment.isTransitionInteractionFrozen {
            return .block(reason: .transitionInteractionFrozen, feedback: nil)
        }

        // ... 后续 policy 判定逻辑保持不变，这里只展示文件头与变更附近上下文 ...
    }
}
```

### 修改意图

这一步再次强调：`CanvasInteractionPolicy` 不负责接收 `NSEvent` / `UIEvent` 这样的原始平台事件，它只负责对已经归一过的业务意图做 shared allow/block 判定。

## 本次明确没有做的事情

- 没有给 `CanvasRawInputIntent` 增加任何真实 case
- 没有给 `CanvasKeyChord`、`CanvasInputIndicatorEvent`、`CanvasInputRoutingResult` 增加字段
- 没有给 `CanvasInputRoutingResolver` 增加映射函数
- 没有改 `iOSViewController` / `macOSViewController`
- 没有改 `CanvasChromeLayoutContext`
- 没有接入任何胶囊 UI
- 没有新增测试文件
- 没有动既有 `CanvasInteractionIntent` / `CanvasInteractionPolicy` 的运行时行为

这和 `phase0` 的目标一致：先冻结边界与命名，再进入 `phase1` 的 shared raw-input 骨架与 routing 设计。

## 构建与诊断验证

```bash
# 文件路径: 系统命令 /usr/bin/xcodebuild
# 函数名/命令名: xcodebuild
# 功能说明: 验证本次 phase0 的边界冻结与空契约文件不会破坏现有 macOS 工程构建。
xcodebuild -scheme "MyCanvas_Ver_0" \
  -destination "platform=macOS" \
  build
```

验证结果：

- `xcodebuild -scheme "MyCanvas_Ver_0" -destination "platform=macOS" build` 通过
- `ReadLints` 未发现这 8 个 phase0 业务文件的新增诊断

## 结论

这次 `phase0` 的真实落点是“`Canvas/Input/` 三车道边界冻结 + raw-input/indicator/routing 契约占位 + 现有 interaction lane 职责收紧”：

1. `CanvasInputBoundaryAnchor` 现在已经明确三车道边界与非目标。
2. `CanvasRawInputIntent`、`CanvasInputIndicatorEvent`、`CanvasInputRoutingResult`、`CanvasInputRoutingResolver` 已有 stable 命名落点。
3. `CanvasInteractionIntent`、`CanvasInteractionDecision`、`CanvasInteractionPolicy` 明确保留为 downstream interaction lane，不吸收原始键鼠触事实。
4. 运行时行为与平台接线尚未启动，因此这一步严格属于“边界冻结”，没有提前进入 `phase1`。
