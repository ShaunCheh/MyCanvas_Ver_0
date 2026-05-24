# 20260524_171120_markdown_overlay_explicit_state_record

## 记录范围

- 记录内容：
  - 修复 `markdown block` 在 `Edit Markdown` 提交并关闭编辑器后，`edit / smaller / larger` 悬浮工具栏仍不恢复的问题。
  - 将 `overlay editor` 的展示状态从“读取系统 `presentedViewController(s)` 推断”改为“控制器显式维护并由 editor 生命周期回写”。
  - 同步把这套显式状态接入 `markdown / video display frame / GIF frame import / hand drawing` 等 overlay editor，避免同类问题继续残留。
- 涉及文件：
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/Markdown/macOSCanvasMarkdownEditorViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSVideoDisplayFrameEditorViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSGIFFrameImportViewController.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/iOS/Markdown/iOSCanvasMarkdownEditorViewController.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSVideoDisplayFrameEditorViewController.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSGIFFrameImportViewController.swift`
  - `MyCanvas_Ver_0/Platform/iOS/HandDrawing/iOSHandDrawingEditorViewController.swift`

## 参考现状

- 生成本记录前，执行 `date +%Y%m%d_%H%M%S`，得到时间戳：`20260524_171120`，本文件按该时间戳命名。
- 生成本记录前，执行 `git status --short -- ...`，相关文件状态为：
  - `M MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
  - `M MyCanvas_Ver_0/Platform/macOS/Markdown/macOSCanvasMarkdownEditorViewController.swift`
  - `M MyCanvas_Ver_0/Platform/macOS/macOSVideoDisplayFrameEditorViewController.swift`
  - `M MyCanvas_Ver_0/Platform/macOS/macOSGIFFrameImportViewController.swift`
  - `M MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `M MyCanvas_Ver_0/Platform/iOS/Markdown/iOSCanvasMarkdownEditorViewController.swift`
  - `M MyCanvas_Ver_0/Platform/iOS/iOSVideoDisplayFrameEditorViewController.swift`
  - `M MyCanvas_Ver_0/Platform/iOS/iOSGIFFrameImportViewController.swift`
  - `M MyCanvas_Ver_0/Platform/iOS/HandDrawing/iOSHandDrawingEditorViewController.swift`
- 生成本记录前，执行 `git diff -- ...`，确认当前 changes 同时包含：
  - `macOS / iOS ViewController` 新增 `OverlayEditorPresentationState`
  - `markdown accessory resolver` 的 `hasPresentedOverlayEditor` 来源切换为显式状态
  - 各类 overlay editor 的构造与 `viewDidDisappear` 回调已接入显式回写
  - 当前 changes 中仍保留上一轮用于定位问题的 `markdown accessory` 日志与异步恢复逻辑；这份记录聚焦本轮新增的“显式状态源根因修复”
- 生成本记录前，已执行编译验证并通过：
  - `xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -sdk macosx build`
  - `xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' build`

## 当前 changes 摘要

- 根因不是 `restoreMarkdownSelectionAccessoryAfterEditorDismiss(...)` 没有执行，而是 resolver 的环境值 `hasPresentedOverlayEditor` 在编辑器关闭后依然持续为 `true`。
- 之前这项环境值来自 `presentedViewController(s)`；从实际运行日志看，这个系统态在 markdown editor dismiss 后并没有按预期及时清空，导致 accessory resolver 始终返回空状态。
- 本轮修改把状态源从“系统推断”改为“显式维护”：
  - 打开 overlay editor 时，由控制器将状态设置为对应 editor 类型
  - editor 真正 `viewDidDisappear` 时，再由 editor 自身回写清空
  - accessory resolver 与 editor 打开 guard 都统一使用这套显式状态

## 修改一：把 overlay editor 是否展示，改成显式状态而不是系统推断

### 修改前

- `macOSViewController` 和 `iOSViewController` 都直接读取 `presentedViewController(s)` 判断是否存在 overlay editor。
- 这个做法依赖系统控制器层级状态及时同步；但从实际日志看，markdown editor 关闭后它仍可能长时间保持“已展示”，进而把 accessory 恢复永久挡住。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: resolvedMarkdownSelectionAccessoryState()
// 功能说明: 修改前直接读取系统 presentedViewControllers 推断 overlay editor 是否存在；一旦系统态滞后，resolver 就会被错误阻断。
private func resolvedMarkdownSelectionAccessoryState() -> SelectionAccessoryState? {
    let resolvedWorkspaceMode = workspaceMode
    let resolvedIsTransitionInteractionFrozen = isTransitionInteractionFrozen
    let resolvedHasContextMenu = contextMenuState != nil
    let resolvedHasPresentedOverlayEditor =
        !(presentedViewControllers?.isEmpty ?? true)
    let resolvedHasInlineEditPresentation = presentationInlineEditState != nil

    return markdownSelectionAccessoryResolver.resolveState(
        session: editorSession,
        environment: CanvasMarkdownSelectionAccessoryResolver.Environment(
            workspaceMode: resolvedWorkspaceMode,
            isTransitionInteractionFrozen: resolvedIsTransitionInteractionFrozen,
            hasContextMenu: resolvedHasContextMenu,
            hasPresentedOverlayEditor: resolvedHasPresentedOverlayEditor,
            hasInlineEditPresentation: resolvedHasInlineEditPresentation
        ),
        anchorRect: editorSession.singleSelectedItemID.flatMap {
            markdownSelectionAccessoryAnchorRect(for: $0)
        }
    )
}
```

### 修改后

- 控制器引入 `OverlayEditorPresentationState`，把 editor 展示状态显式建模为 `.none / .markdown / .videoDisplayFrame / ...`。
- resolver 不再依赖系统控制器层级，而是只看 `activeOverlayEditorPresentationState != .none`。
- 这一步是根因修复：直接替换掉不可靠的状态源。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: OverlayEditorPresentationState / resolvedMarkdownSelectionAccessoryState()
// 功能说明: 修改后由控制器显式维护 overlay editor 状态，避免系统 presentedViewControllers 残留把 accessory resolver 永久挡住。
private enum OverlayEditorPresentationState: Equatable {
    case none
    case videoDisplayFrame
    case gifFrameImport
    case markdown
}

private var activeOverlayEditorPresentationState: OverlayEditorPresentationState = .none

private func resolvedMarkdownSelectionAccessoryState() -> SelectionAccessoryState? {
    let resolvedWorkspaceMode = workspaceMode
    let resolvedIsTransitionInteractionFrozen = isTransitionInteractionFrozen
    let resolvedHasContextMenu = contextMenuState != nil
    let resolvedHasPresentedOverlayEditor =
        activeOverlayEditorPresentationState != .none
    let resolvedHasInlineEditPresentation = presentationInlineEditState != nil

    return markdownSelectionAccessoryResolver.resolveState(
        session: editorSession,
        environment: CanvasMarkdownSelectionAccessoryResolver.Environment(
            workspaceMode: resolvedWorkspaceMode,
            isTransitionInteractionFrozen: resolvedIsTransitionInteractionFrozen,
            hasContextMenu: resolvedHasContextMenu,
            hasPresentedOverlayEditor: resolvedHasPresentedOverlayEditor,
            hasInlineEditPresentation: resolvedHasInlineEditPresentation
        ),
        anchorRect: editorSession.singleSelectedItemID.flatMap {
            markdownSelectionAccessoryAnchorRect(for: $0)
        }
    )
}
```

## 修改二：打开各类 overlay editor 时，显式标记“谁正在展示”

### 修改前

- 打开 `markdown / video / GIF / hand drawing` editor 时，只做 `present(...)` 或 `presentAsSheet(...)`。
- 守卫逻辑也只看 `presentedViewController(s)` 是否为空。
- 一旦系统态残留，既会挡住 accessory 恢复，也会让后续 editor 打开判断不再可靠。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: presentMarkdownEditor(for:)
// 功能说明: 修改前只依赖系统 presentedViewController 作为 guard，也没有在打开时记录“当前是哪种 overlay editor”。
private func presentMarkdownEditor(for itemID: CanvasItemID) {
    guard presentedViewController == nil else {
        return
    }

    let editorViewController = iOSCanvasMarkdownEditorViewController(
        markdownSource: item.markdownSource,
        onCommitMarkdownSource: { [weak self] markdownSource in
            // 提交 markdown 内容
            // ... 省略 ...
            return true
        }
    )
    present(editorViewController, animated: true)
}
```

### 修改后

- 控制器打开 editor 前先检查 `activeOverlayEditorPresentationState == .none`。
- 真正打开后，立刻把状态写成对应 editor 类型。
- 这保证了 accessory resolver 与 editor 打开 guard 使用的是同一套可控状态。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: presentMarkdownEditor(for:)
// 功能说明: 修改后在打开 markdown editor 前后显式维护展示状态，保证 resolver 与打开 guard 使用同一状态源。
private func presentMarkdownEditor(for itemID: CanvasItemID) {
    guard activeOverlayEditorPresentationState == .none else {
        return
    }

    let editorViewController = iOSCanvasMarkdownEditorViewController(
        markdownSource: item.markdownSource,
        onCommitMarkdownSource: { [weak self] markdownSource in
            // 提交 markdown 内容
            // ... 省略 ...
            return true
        },
        onDidDismiss: { [weak self] in
            // 编辑器真正离场后再清空展示状态
            self?.activeOverlayEditorPresentationState = .none
        },
        onDismissAfterSuccessfulCommit: { [weak self] in
            // 成功提交后再恢复 markdown accessory
            self?.restoreMarkdownSelectionAccessoryAfterEditorDismiss(
                reason: "markdown editor dismiss"
            )
        }
    )
    activeOverlayEditorPresentationState = .markdown
    present(editorViewController, animated: true)
}
```

## 修改三：editor 生命周期增加 dismiss 回写，确保状态真正清空

### 修改前

- 各类 editor 自身在关闭时只做 `dismiss(...)`，不会主动通知父控制器“我已经真正离场”。
- 父控制器只能继续被动读取系统 `presentedViewController(s)`，无法在生命周期边界上拿到一个稳定的“已关闭”信号。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Markdown/macOSCanvasMarkdownEditorViewController.swift
// 函数名: init(...) / viewDidDisappear()
// 功能说明: 修改前 markdown editor 只有提交回调，没有通用的 dismiss 回写钩子；父控制器无法在 editor 真正消失时清空显式状态。
final class macOSCanvasMarkdownEditorViewController: NSViewController {
    private let initialMarkdownSource: String
    private let onCommitMarkdownSource: (String) -> Bool
    private let onDismissAfterSuccessfulCommit: (() -> Void)?

    init(
        markdownSource: String,
        onCommitMarkdownSource: @escaping (String) -> Bool,
        onDismissAfterSuccessfulCommit: (() -> Void)? = nil
    ) {
        self.initialMarkdownSource = markdownSource
        self.onCommitMarkdownSource = onCommitMarkdownSource
        self.onDismissAfterSuccessfulCommit = onDismissAfterSuccessfulCommit
        super.init(nibName: nil, bundle: nil)
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        guard shouldNotifyDismissAfterSuccessfulCommit else {
            return
        }
        shouldNotifyDismissAfterSuccessfulCommit = false
        onDismissAfterSuccessfulCommit?()
    }
}
```

### 修改后

- editor 控制器统一增加 `onDidDismiss` 回调。
- 在 `viewDidDisappear` 里先执行 `onDidDismiss?()`，把“editor 确认已离场”这件事显式回传给父控制器。
- markdown editor 仍保留 `onDismissAfterSuccessfulCommit`，但它现在建立在“先清状态、再恢复 accessory”的正确顺序上。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Markdown/macOSCanvasMarkdownEditorViewController.swift
// 函数名: init(...) / viewDidDisappear()
// 功能说明: 修改后 editor 在真正消失时先回写 onDidDismiss，用稳定生命周期信号清空父控制器的 overlay editor 状态。
final class macOSCanvasMarkdownEditorViewController: NSViewController {
    private let initialMarkdownSource: String
    private let onCommitMarkdownSource: (String) -> Bool
    private let onDidDismiss: (() -> Void)?
    private let onDismissAfterSuccessfulCommit: (() -> Void)?

    init(
        markdownSource: String,
        onCommitMarkdownSource: @escaping (String) -> Bool,
        onDidDismiss: (() -> Void)? = nil,
        onDismissAfterSuccessfulCommit: (() -> Void)? = nil
    ) {
        self.initialMarkdownSource = markdownSource
        self.onCommitMarkdownSource = onCommitMarkdownSource
        self.onDidDismiss = onDidDismiss
        self.onDismissAfterSuccessfulCommit = onDismissAfterSuccessfulCommit
        super.init(nibName: nil, bundle: nil)
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        onDidDismiss?()
        guard shouldNotifyDismissAfterSuccessfulCommit else {
            return
        }
        shouldNotifyDismissAfterSuccessfulCommit = false
        onDismissAfterSuccessfulCommit?()
    }
}
```

## 修改四：把同样的 dismiss 回写扩散到其它 overlay editor，封住同类入口

### 修改前

- 除 markdown editor 外，其它 overlay editor 也没有统一的“dismiss 回写父控制器”能力。
- 这意味着即便 markdown 的恢复问题被绕过去，`video / GIF / hand drawing` 仍可能继续把控制器状态卡在“有 overlay editor”。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSVideoDisplayFrameEditorViewController.swift
// 函数名: init(...) / viewWillDisappear(_:)
// 功能说明: 修改前 video editor 只处理自身播放资源清理，不会在消失时回写父控制器的 overlay editor 状态。
final class iOSVideoDisplayFrameEditorViewController: UIViewController {
    private let editorContext: CanvasVideoEditorContext
    private let loadTimelineStrip: (CanvasVideoTimelineStripRequest) throws -> CanvasVideoTimelineStrip
    private let onCommitFrameImage: (CanvasVideoFrameImage) throws -> Void

    init(
        editorContext: CanvasVideoEditorContext,
        loadTimelineStrip: @escaping (CanvasVideoTimelineStripRequest) throws -> CanvasVideoTimelineStrip,
        onCommitFrameImage: @escaping (CanvasVideoFrameImage) throws -> Void
    ) {
        self.editorContext = editorContext
        self.loadTimelineStrip = loadTimelineStrip
        self.onCommitFrameImage = onCommitFrameImage
        super.init(nibName: nil, bundle: nil)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        timelineLoadWorkItem?.cancel()
        pausePlayback()
    }
}
```

### 修改后

- `video / GIF / hand drawing` editor 都加上 `onDidDismiss`。
- 父控制器为这些 editor 传入统一的状态清空闭包。
- 这样“显式状态”不是 markdown 特例，而是整个 overlay editor 体系的通用约束。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSVideoDisplayFrameEditorViewController.swift
// 函数名: init(...) / viewDidDisappear(_:)
// 功能说明: 修改后 video editor 在消失时统一回写 onDidDismiss，让父控制器可靠地清空 overlay editor 显式状态。
final class iOSVideoDisplayFrameEditorViewController: UIViewController {
    private let editorContext: CanvasVideoEditorContext
    private let loadTimelineStrip: (CanvasVideoTimelineStripRequest) throws -> CanvasVideoTimelineStrip
    private let onCommitFrameImage: (CanvasVideoFrameImage) throws -> Void
    private let onDidDismiss: (() -> Void)?

    init(
        editorContext: CanvasVideoEditorContext,
        loadTimelineStrip: @escaping (CanvasVideoTimelineStripRequest) throws -> CanvasVideoTimelineStrip,
        onDidDismiss: (() -> Void)? = nil,
        onCommitFrameImage: @escaping (CanvasVideoFrameImage) throws -> Void
    ) {
        self.editorContext = editorContext
        self.loadTimelineStrip = loadTimelineStrip
        self.onDidDismiss = onDidDismiss
        self.onCommitFrameImage = onCommitFrameImage
        super.init(nibName: nil, bundle: nil)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        onDidDismiss?()
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/iOSHandDrawingEditorViewController.swift
// 函数名: init(...) / viewDidDisappear(_:)
// 功能说明: hand drawing editor 也加入同样的 dismiss 回写，避免不同 editor 继续各自维护、再次产生状态漂移。
final class iOSHandDrawingEditorViewController: UIViewController {
    private let onCommitSubmission: (CanvasHandDrawingEditSubmission) throws -> Void
    private let onDidDismiss: (() -> Void)?

    init(
        editorContext: CanvasHandDrawingEditorContext,
        onDidDismiss: (() -> Void)? = nil,
        onCommitSubmission: @escaping (CanvasHandDrawingEditSubmission) throws -> Void
    ) throws {
        self.onCommitSubmission = onCommitSubmission
        self.onDidDismiss = onDidDismiss
        // ... 省略 coordinator 初始化 ...
        super.init(nibName: nil, bundle: nil)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        onDidDismiss?()
    }
}
```

## 修改五：本轮修复与上一轮异步恢复逻辑的关系

- 上一轮已经加了 `restoreMarkdownSelectionAccessoryAfterEditorDismiss(...)` 和相关日志；这些代码在当前 changes 中仍然存在。
- 但从这次日志可知，异步恢复本身不是根因，真正阻塞点是 resolver 的 `hasPresentedOverlayEditor` 一直为 `true`。
- 因此本轮不是继续叠加更多 `DispatchQueue.main.async`，而是直接修正状态源，让：
  - `onDidDismiss` 先清空显式状态
  - `onDismissAfterSuccessfulCommit` 再恢复 accessory
- 结果上，异步恢复逻辑仍可保留作为时序缓冲，但它不再承担“纠正错误状态源”的职责。

## 结论

- 本轮修改把问题从“恢复 accessory 的时机猜测”推进到“overlay editor 状态源的根因修复”。
- 修复后的关键变化是：
  - accessory resolver 不再依赖不稳定的系统 `presentedViewController(s)`
  - overlay editor 的展示与消失都通过显式状态和生命周期回写闭环管理
  - 同类 editor 全量接入，避免 markdown 修好、其它 editor 继续污染状态
- 编译验证已覆盖 `macOS` 与 `iOS Simulator`，当前修改至少在静态层面闭环成立。
