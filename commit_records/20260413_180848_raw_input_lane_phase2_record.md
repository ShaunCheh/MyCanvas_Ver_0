# 20260413_180848_raw_input_lane_phase2_record

## 记录说明

本记录基于当前工作区里“刚刚这次 raw input lane `phase2` controller ingress 归一”的实际 `git status`、`git diff --stat`、当前代码状态、构建结果与诊断结果整理，不包含原始 `git diff` 文本。

本次共涉及 2 个业务代码文件：

- `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`

本次工作分支：

- `feat/cross-platform-input-indicator`

写入本记录前的代码状态依据：

- `git status --short --branch` 显示当前位于 `feat/cross-platform-input-indicator`
- 当前 changes 只包含 `2` 个已跟踪 controller 文件修改：
  - `M MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `M MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- `git diff --stat -- <2 个 controller 文件>` 统计为：`2 files changed, 137 insertions(+), 14 deletions(-)`
- 本记录文件是随后新增的说明材料，不属于上述 2 个业务代码文件本身。

本记录不包含：

- 原始 `git diff` 文本
- git commit / push
- `phase3` 的胶囊 UI、queue、formatter、layout solver
- pointer / touch 的全量 controller 迁移

## 时间戳与取证命令

```bash
# 文件路径: 系统命令 /bin/date
# 函数名/命令名: date
# 功能说明: 生成本记录文件名使用的时间戳前缀。
date +"%Y%m%d_%H%M%S"
```

`date` 实际输出：`20260413_180848`

```bash
# 文件路径: 系统命令 /usr/bin/git
# 函数名/命令名: git status / git diff
# 功能说明: 提取这次 raw input lane phase2 的真实变更范围与当前工作区状态。
git status --short --branch

git diff --stat -- \
  "MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift" \
  "MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift"

git diff -- \
  "MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift" \
  "MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift"
```

## 本次 phase2 的真实目标

这一步没有进入 `phase3` 的展示层，也没有把 pointer / touch 的全部入口都迁完，而是严格按计划只做 controller ingress 归一：

1. 在 `iOSViewController` 和 `macOSViewController` 内挂上 shared `CanvasInputRoutingResolver`。
2. 新增 `handleCapturedInput(...)` 和 raw-input routing 日志，把平台捕获到的低风险输入入口先归一到 shared raw-input lane。
3. 优先迁移低风险粘贴入口：
   - `iOS` 的 `UIKeyCommand` 粘贴
   - `macOS` 标准 `paste(_:)` 的键盘分支
   - `macOS` 的 supplemental keyboard capture
4. 保持菜单粘贴和既有 interaction gate / transfer continuation 语义不变。

## 修改一：`iOSViewController` 新增 shared raw-input resolver 依赖

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/符号名: iOSViewController 属性区
// 功能说明: 修改前 iOS controller 只有 interactionPolicy，还没有 shared raw-input routing resolver。
private let commandCatalog = CanvasCommandCatalog()
private let toolbarStateBuilder = CanvasToolbarStateBuilder()
private let contextMenuActionResolver = CanvasContextMenuActionResolver()
private let interactionPolicy = CanvasInteractionPolicy()
private let canvasHostView: UIView = {
    let view = UIView()
    view.translatesAutoresizingMaskIntoConstraints = false
    view.backgroundColor = .systemBackground
    view.clipsToBounds = true
    return view
}()
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/符号名: iOSViewController 属性区
// 功能说明: 修改后 controller 持有 shared CanvasInputRoutingResolver，为 phase2 的 raw-input ingress 提供统一路由入口。
private let commandCatalog = CanvasCommandCatalog()
private let toolbarStateBuilder = CanvasToolbarStateBuilder()
private let contextMenuActionResolver = CanvasContextMenuActionResolver()
private let interactionPolicy = CanvasInteractionPolicy()
private let inputRoutingResolver = CanvasInputRoutingResolver()
private let canvasHostView: UIView = {
    let view = UIView()
    view.translatesAutoresizingMaskIntoConstraints = false
    view.backgroundColor = .systemBackground
    view.clipsToBounds = true
    return view
}()
```

### 修改意图

这一步只是把 shared resolver 注入到 controller 内，不改变现有 interaction policy 的职责，也不直接接 UI。

## 修改二：`iOS` 的 `Command + V` 先进入 raw-input ingress，再下沉到现有 interaction gate

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/符号名: handlePasteKeyCommand(_:)
// 功能说明: 修改前 iOS 的键盘粘贴直接以 transferEntry 语义进入 interaction gate，没有先经过 raw-input lane。
@objc
private func handlePasteKeyCommand(_ sender: UIKeyCommand) {
    handleTransferEntryAttempt(
        .pasteKeyboardShortcut,
        deliverySource: .iOSKeyCommand
    ) {
        handlePasteRequest()
        return true
    }
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/符号名: makePasteKeyboardShortcutRawInput() / handlePasteKeyCommand(_:)
// 功能说明: 修改后 iOS 的键盘粘贴先构造原始键盘输入，再通过 handleCapturedInput(...) 进入 shared routing；只有当 routingResult 仍然导出 pasteKeyboardShortcut 时才继续执行既有粘贴路径。
private func makePasteKeyboardShortcutRawInput() -> CanvasRawInputIntent {
    .keyChord(
        CanvasKeyChord(
            modifiers: [.command],
            key: .character("v")
        )
    )
}

@objc
private func handlePasteKeyCommand(_ sender: UIKeyCommand) {
    handleCapturedInput(
        makePasteKeyboardShortcutRawInput(),
        sourceDescription: TransferEntryDeliverySource.iOSKeyCommand.debugName
    ) { routingResult in
        guard
            routingResult.interactionIntent
                == .transferEntry(.pasteKeyboardShortcut)
        else {
            return false
        }
        handlePasteRequest()
        return true
    }
}
```

### 修改意图

这一步把 `iOS` 的硬件键盘粘贴变成了 phase2 计划里的第一条 raw-input ingress，但仍然复用既有 `handlePasteRequest()` 与 `handleInteractionAttempt(...)`，没有改变下游执行路径。

## 修改三：`iOSViewController` 新增 `handleCapturedInput(...)` 与 raw-input routing 日志

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/符号名: handleInteractionAttempt(_:sourceDescription:continueIfAllowed:)
// 功能说明: 修改前 iOS 只有 interaction gate helper，还没有位于它上游的 raw-input ingress helper。
@discardableResult
private func handleInteractionAttempt(
    _ intent: CanvasInteractionIntent,
    sourceDescription: String,
    continueIfAllowed: () -> Bool
) -> Bool {
    let decision = interactionDecision(for: intent)
    logInteractionDecision(
        intent: intent,
        decision: decision,
        sourceDescription: sourceDescription
    )
    switch decision {
    case .allow:
        return continueIfAllowed()
    case .block(_, let feedback):
        if let feedback {
            applyInteractionFeedback(feedback)
        }
        return false
    }
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/符号名: logCapturedInputRouting(...) / handleCapturedInput(...)
// 功能说明: 修改后 iOS 在 interaction gate 之前新增 raw-input ingress，先做 shared routing，再决定是否继续下沉到现有 interactionAttempt。
private func logCapturedInputRouting(
    rawInput: CanvasRawInputIntent,
    routingResult: CanvasInputRoutingResult,
    sourceDescription: String
) {
    print(
        "[Canvas iOS][RawInputRoute] " +
        "source=\"\(sourceDescription)\" " +
        "rawInput=\(rawInput.debugName) " +
        routingResult.debugSummary
    )
}

@discardableResult
private func handleCapturedInput(
    _ rawInput: CanvasRawInputIntent,
    sourceDescription: String,
    continueIfAllowed: (CanvasInputRoutingResult) -> Bool
) -> Bool {
    let routingResult = inputRoutingResolver.route(rawInput)
    logCapturedInputRouting(
        rawInput: rawInput,
        routingResult: routingResult,
        sourceDescription: sourceDescription
    )

    guard let interactionIntent = routingResult.interactionIntent else {
        return continueIfAllowed(routingResult)
    }

    return handleInteractionAttempt(
        interactionIntent,
        sourceDescription: sourceDescription
    ) {
        continueIfAllowed(routingResult)
    }
}
```

### 修改意图

这一步把 phase1 的 shared `CanvasInputRoutingResolver` 真正接到了 `iOS controller` 上，但仍然是薄桥接层：routing 以后要不要继续进入 business lane，仍由现有 `interaction gate` 负责。

## 修改四：`macOSViewController` 新增 shared raw-input resolver 依赖

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/符号名: macOSViewController 属性区
// 功能说明: 修改前 macOS controller 只有 interactionPolicy，还没有 shared raw-input routing resolver。
private let commandCatalog = CanvasCommandCatalog()
private let toolbarStateBuilder = CanvasToolbarStateBuilder()
private let contextMenuActionResolver = CanvasContextMenuActionResolver()
private let interactionPolicy = CanvasInteractionPolicy()
private let canvasHostView: NSView = {
    let view = NSView()
    view.translatesAutoresizingMaskIntoConstraints = false
    view.wantsLayer = true
    view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    return view
}()
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/符号名: macOSViewController 属性区
// 功能说明: 修改后 macOS controller 也持有 shared CanvasInputRoutingResolver，和 iOS 对齐 phase2 的 raw-input ingress 落点。
private let commandCatalog = CanvasCommandCatalog()
private let toolbarStateBuilder = CanvasToolbarStateBuilder()
private let contextMenuActionResolver = CanvasContextMenuActionResolver()
private let interactionPolicy = CanvasInteractionPolicy()
private let inputRoutingResolver = CanvasInputRoutingResolver()
private let canvasHostView: NSView = {
    let view = NSView()
    view.translatesAutoresizingMaskIntoConstraints = false
    view.wantsLayer = true
    view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    return view
}()
```

### 修改意图

这一步让两端 controller 的 ingress 结构对齐，后续 phase3/phase4 才能在双端基于同一 shared routing 继续展开。

## 修改五：`macOS` 标准 `paste(_:)` 分离键盘粘贴与菜单粘贴路径

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/符号名: paste(_:)
// 功能说明: 修改前 macOS 标准 paste 路径直接把 resolvedPasteTransferEntryIntent() 结果喂给 handleTransferEntryAttempt(...)，键盘和菜单仍共用一层入口。
@objc
func paste(_ sender: Any?) {
    handleTransferEntryAttempt(
        resolvedPasteTransferEntryIntent(),
        deliverySource: .macOSPasteAction
    ) {
        handlePasteRequest()
        return true
    }
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/符号名: paste(_:)
// 功能说明: 修改后标准 paste 路径显式分离 keyboard 和 menu 语义；键盘粘贴先走 raw-input ingress，菜单粘贴保留原有 transferEntry 入口。
@objc
func paste(_ sender: Any?) {
    switch resolvedPasteTransferEntryIntent() {
    case .pasteKeyboardShortcut:
        handleCapturedInput(
            makePasteKeyboardShortcutRawInput(),
            sourceDescription: TransferEntryDeliverySource.macOSPasteAction.debugName
        ) { routingResult in
            guard
                routingResult.interactionIntent
                    == .transferEntry(.pasteKeyboardShortcut)
            else {
                return false
            }

            handlePasteRequest()
            return true
        }
    case .pasteMenu:
        handleTransferEntryAttempt(
            .pasteMenu,
            deliverySource: .macOSPasteAction
        ) {
            handlePasteRequest()
            return true
        }
    case .importButton,
         .dragAndDrop:
        return
    }
}
```

### 修改意图

这一步的核心不是改菜单逻辑，而是把 `macOS` 键盘粘贴从标准 responder 路径里先抬到 raw-input ingress；同时保留 `pasteMenu` 原有语义，严格符合 phase2 “只迁低风险硬件输入入口”的边界。

## 修改六：`macOSViewController` 新增 `handleCapturedInput(...)` 与 raw-input routing 日志

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/符号名: handleInteractionAttempt(_:sourceDescription:continueIfAllowed:)
// 功能说明: 修改前 macOS 只有 interaction gate helper，没有 shared raw-input ingress helper。
@discardableResult
private func handleInteractionAttempt(
    _ intent: CanvasInteractionIntent,
    sourceDescription: String,
    continueIfAllowed: () -> Bool
) -> Bool {
    let decision = interactionDecision(for: intent)
    logInteractionDecision(
        intent: intent,
        decision: decision,
        sourceDescription: sourceDescription
    )
    switch decision {
    case .allow:
        return continueIfAllowed()
    case .block(_, let feedback):
        if let feedback {
            applyInteractionFeedback(feedback)
        }
        return false
    }
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/符号名: logCapturedInputRouting(...) / handleCapturedInput(...)
// 功能说明: 修改后 macOS 也在 interaction gate 之前新增 raw-input ingress，并输出统一的 RawInputRoute 调试日志。
private func logCapturedInputRouting(
    rawInput: CanvasRawInputIntent,
    routingResult: CanvasInputRoutingResult,
    sourceDescription: String
) {
    print(
        "[Canvas macOS][RawInputRoute] " +
        "source=\"\(sourceDescription)\" " +
        "rawInput=\(rawInput.debugName) " +
        routingResult.debugSummary
    )
}

@discardableResult
private func handleCapturedInput(
    _ rawInput: CanvasRawInputIntent,
    sourceDescription: String,
    continueIfAllowed: (CanvasInputRoutingResult) -> Bool
) -> Bool {
    let routingResult = inputRoutingResolver.route(rawInput)
    logCapturedInputRouting(
        rawInput: rawInput,
        routingResult: routingResult,
        sourceDescription: sourceDescription
    )

    guard let interactionIntent = routingResult.interactionIntent else {
        return continueIfAllowed(routingResult)
    }

    return handleInteractionAttempt(
        interactionIntent,
        sourceDescription: sourceDescription
    ) {
        continueIfAllowed(routingResult)
    }
}
```

### 修改意图

这一步让 `macOS` 的 keyboard-origin input 在进入 `interaction gate` 之前，也先经过 shared raw-input routing；这正是 phase2 计划里的 controller ingress 归一点。

## 修改七：`macOS` supplemental keyboard capture 改走 raw-input ingress

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/符号名: handleSupplementalKeyboardCapture(_:)
// 功能说明: 修改前 supplemental keyboard monitor 在阅读模式下直接投递 transferEntry(.pasteKeyboardShortcut)。
private func handleSupplementalKeyboardCapture(
    _ event: NSEvent
) -> NSEvent? {
    guard
        shouldEnableSupplementalKeyboardCapture(),
        let window = view.window,
        event.window === window,
        isPasteKeyboardShortcutEvent(event)
    else {
        return event
    }

    guard case .block = transferEntryDecision(for: .pasteKeyboardShortcut) else {
        return event
    }

    _ = handleTransferEntryAttempt(
        .pasteKeyboardShortcut,
        deliverySource: .macOSLocalKeyMonitor
    ) {
        false
    }
    return nil
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/符号名: handleSupplementalKeyboardCapture(_:) / makePasteKeyboardShortcutRawInput()
// 功能说明: 修改后 supplemental keyboard monitor 先构造原始键盘输入，再统一走 handleCapturedInput(...)；continue 闭包仍保持 false，不改变 phase3 时就有的 block-only 行为。
private func handleSupplementalKeyboardCapture(
    _ event: NSEvent
) -> NSEvent? {
    guard
        shouldEnableSupplementalKeyboardCapture(),
        let window = view.window,
        event.window === window,
        isPasteKeyboardShortcutEvent(event)
    else {
        return event
    }

    guard case .block = transferEntryDecision(for: .pasteKeyboardShortcut) else {
        return event
    }

    _ = handleCapturedInput(
        makePasteKeyboardShortcutRawInput(),
        sourceDescription: TransferEntryDeliverySource.macOSLocalKeyMonitor.debugName
    ) { _ in
        false
    }
    return nil
}

private func makePasteKeyboardShortcutRawInput() -> CanvasRawInputIntent {
    .keyChord(
        CanvasKeyChord(
            modifiers: [.command],
            key: .character("v")
        )
    )
}
```

### 修改意图

这一步把 `macOS` 阅读模式下那条“标准路径可能观测不到 keyboard attempt”的特殊 monitor，也接入了 phase2 的统一 ingress，但保留其原本只用于 block+feedback 的行为边界。

## 本次明确没有做的事情

- 没有新增 `InputIndicatorHostView`、queue、formatter、layout solver
- 没有把 pointer / touch 的其它入口迁入 `handleCapturedInput(...)`
- 没有改 `setupCanvasViewport()` 里现有 pointer 编辑逻辑
- 没有修改 `CanvasInputRoutingResolver` 的 phase1 shared 规则
- 没有新增测试文件
- 没有跑 test target

这和 phase2 计划是一致的：先让低风险粘贴入口统一进入 controller ingress，再进入后续 phase 的展示层和更广泛 capture 迁移。

## 构建与诊断验证

```bash
# 文件路径: 系统命令 /usr/bin/xcodebuild
# 函数名/命令名: xcodebuild build (macOS)
# 功能说明: 验证 phase2 的 macOS controller ingress 改动不会破坏现有 app target 构建。
xcodebuild -scheme "MyCanvas_Ver_0" \
  -destination "platform=macOS" \
  build
```

```bash
# 文件路径: 系统命令 /usr/bin/xcodebuild
# 函数名/命令名: xcodebuild build (iOS)
# 功能说明: 验证 phase2 的 iOS controller ingress 改动不会破坏现有 app target 构建。
xcodebuild -scheme "MyCanvas_Ver_0" \
  -destination "generic/platform=iOS" \
  build
```

验证结果：

- `ReadLints` 未发现 `iOSViewController.swift` 与 `macOSViewController.swift` 的新增诊断
- `xcodebuild -scheme "MyCanvas_Ver_0" -destination "platform=macOS" build` 通过
- `xcodebuild -scheme "MyCanvas_Ver_0" -destination "generic/platform=iOS" build` 通过
- 本次 phase2 未运行 test target；当前验证口径仅为双端 build + lints

## 结论

这次 `phase2` 的真实落点是“在双端 controller 上建立 raw-input ingress 的第一条统一桥”：

1. `iOS` 的 `Command + V` 现在先构造成 `CanvasRawInputIntent.keyChord(...)`，再通过 shared routing 决定是否继续下沉到现有 interaction gate。
2. `macOS` 的键盘粘贴现在在标准 `paste(_:)` 路径和 supplemental monitor 路径上都先进入 shared raw-input ingress。
3. `macOS` 的菜单粘贴没有被强行迁成 raw-input lane，仍保留原有 `pasteMenu` 语义。
4. pointer / touch 编辑路径和展示层都还没启动，因此这一步严格属于计划里的 controller ingress 阶段，不是 UI 阶段。

因此，后续进入 `phase3` 时，双端已经具备一条可观测、可记录、可继续扩展的 raw-input 统一入口，不需要再回头拆键盘粘贴路径。
