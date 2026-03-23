# 20260323_195832_boardlist_rename_macos_initial_focus_stabilization_fix_record

## 记录范围

- 记录内容：
  1. 修复 `macOS BoardList` 中点击 `Rename` 后标题只短暂进入编辑态、随即退出的问题。
  2. 将 `macOSBoardCollectionItem` 的首次聚焦改为延迟申请，并为初始聚焦阶段增加稳定窗口保护。
  3. 保留 `macOS` 端既定交互语义：`Return` 提交、`Esc` 取消、点击空白区域提交。
- 涉及文件：
  - `MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift`
- 本记录不包含：
  - 之前为了排查问题而加入的 controller 侧 trace 日志整体说明
  - `iOS` 端 rename 逻辑调整
  - git commit / push

## 问题现象

- 点击 `Rename` 后，标题输入框会短暂出现，但很快又恢复成普通标题展示。
- 日志已证实：`macOS` 侧在进入编辑态后，会很快收到一次 `disposition = .unspecified` 的 `controlTextDidEndEditing(_:)`。
- 旧实现把这类 `unspecified` 结束编辑直接视为提交；而当前标题又没有变化，于是 controller 立刻走 no-op commit 路径，清掉 `editingBoardID` 并 reload 列表，造成“闪一下就退出”。

## 修改一：把首次聚焦从“立即抢焦点”改为“延迟聚焦 + 可取消请求”

### 修改前

- `beginTitleEditing()` 在进入编辑态后立刻 `makeFirstResponder(titleTextField)`。
- 这个时机仍然贴在 `Rename` 菜单点击的尾部，容易和 action panel 收起、collection selection 同步、view reuse 等事件重叠。
- item 内也没有“延迟聚焦请求 ID”或“初始聚焦稳定状态”这样的最小状态机。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift
// 函数名: beginTitleEditing()
// 功能说明: 修改前 macOS item 会在 Rename 动作刚触发完时立刻抢焦点，容易和同一轮 UI 事件尾部发生竞争。
func beginTitleEditing() {
    guard
        isTitleEditingActive,
        titleTextField.isHidden == false
    else {
        return
    }

    didHandleCurrentTitleEditEnd = false
    pendingTitleEditEndDisposition = .unspecified
    view.window?.makeFirstResponder(titleTextField)
    DispatchQueue.main.async { [weak self] in
        guard
            let self,
            self.isTitleEditingActive
        else {
            return
        }

        self.view.window?.makeFirstResponder(self.titleTextField)
        (self.view.window?.fieldEditor(true, for: self.titleTextField) as? NSTextView)?
            .selectAll(nil)
    }
}
```

### 修改后

- 新增 `TitleEditTiming`，集中声明首次聚焦延迟、异常失焦回焦延迟、稳定窗口时长、最大重试次数。
- 新增 `titleEditFocusRequestID`、`isAwaitingInitialFocusStabilization`、`unexpectedInitialEndRetryCount`，把 rename 初始进入编辑态收束成一个轻量状态机。
- `beginTitleEditing()` 不再立刻抢焦点，而是调用 `scheduleTitleEditingFocus(...)`，延迟申请 first responder。
- `scheduleTitleEditingFocus(...)` 具备“请求 ID 校验”能力，避免旧 item 或旧一轮编辑残留的异步 closure 在复用后误触发。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift
// 函数名: TitleEditTiming / 属性定义 / beginTitleEditing() / scheduleTitleEditingFocus(delay:reason:)
// 功能说明: 修改后 macOS item 不再在 Rename 点击尾部立即抢焦点，而是通过可失效的延迟聚焦请求进入稳定编辑态。
private enum TitleEditTiming {
    static let initialFocusDelay: TimeInterval = 0.12
    static let refocusDelay: TimeInterval = 0.05
    static let stabilizationDelay: TimeInterval = 0.18
    static let maximumUnexpectedEndRetries = 1
}

private var titleEditFocusRequestID = 0
private var isAwaitingInitialFocusStabilization = false
private var unexpectedInitialEndRetryCount = 0

func beginTitleEditing() {
    guard
        isTitleEditingActive,
        titleTextField.isHidden == false
    else {
        return
    }

    didHandleCurrentTitleEditEnd = false
    pendingTitleEditEndDisposition = .unspecified
    unexpectedInitialEndRetryCount = 0
    scheduleTitleEditingFocus(
        delay: TitleEditTiming.initialFocusDelay,
        reason: "initial"
    )
}

private func scheduleTitleEditingFocus(
    delay: TimeInterval,
    reason: String
) {
    titleEditFocusRequestID += 1
    let requestID = titleEditFocusRequestID
    isAwaitingInitialFocusStabilization = true
    pendingTitleEditEndDisposition = .unspecified
    logRenameTrace(
        "scheduleTitleEditingFocus",
        extra:
            "requestID=\(requestID) " +
            "delay=\(String(format: "%.2f", delay)) " +
            "reason=\(reason)"
    )

    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
        guard
            let self,
            self.titleEditFocusRequestID == requestID,
            self.isTitleEditingActive,
            self.titleTextField.isHidden == false
        else {
            self?.logRenameTrace(
                "scheduleTitleEditingFocusAborted",
                extra:
                    "requestID=\(requestID) " +
                    "reason=\(reason)"
            )
            return
        }

        self.logRenameTrace(
            "performTitleEditingFocus",
            extra:
                "requestID=\(requestID) " +
                "reason=\(reason)"
        )
        self.view.window?.makeFirstResponder(self.titleTextField)

        DispatchQueue.main.async { [weak self] in
            guard
                let self,
                self.titleEditFocusRequestID == requestID
            else {
                return
            }

            (self.view.window?.fieldEditor(true, for: self.titleTextField) as? NSTextView)?
                .selectAll(nil)
        }
    }
}
```

## 修改二：将 `unspecified end-edit` 从“直接提交”改为“稳定期内忽略并回焦”

### 修改前

- `controlTextDidEndEditing(_:)` 把 `unspecified` 和 `commit` 统一当成提交。
- 这意味着只要输入框在刚进入编辑态后意外丢失一次焦点，就会马上执行 `commitTitleEditIfNeeded()`。
- 由于这时标题通常还没改，controller 会紧接着走 no-op commit，导致编辑态退出。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift
// 函数名: controlTextDidEndEditing(_:)
// 功能说明: 修改前 macOS item 会把所有未显式标记的 end-edit 都当成提交，导致初始伪失焦也会结束 rename。
func controlTextDidEndEditing(_ obj: Notification) {
    guard obj.object as AnyObject? === titleTextField else {
        return
    }

    let disposition = pendingTitleEditEndDisposition
    pendingTitleEditEndDisposition = .unspecified
    logRenameTrace("controlTextDidEndEditing", extra: "disposition=\(String(describing: disposition))")

    switch disposition {
    case .unspecified, .commit:
        commitTitleEditIfNeeded()
    case .cancel:
        cancelTitleEditIfNeeded()
    }
}
```

### 修改后

- 新增 `controlTextDidBeginEditing(_:)`，在真正进入编辑后等待一个短暂稳定窗口，再把 `isAwaitingInitialFocusStabilization` 切回 `false`。
- `controlTextDidEndEditing(_:)` 现在分三类：
  - `.commit`：仍然立即提交。
  - `.cancel`：仍然立即取消。
  - `.unspecified`：如果发生在稳定窗口内，并且还没超过最大重试次数，则忽略本次结束事件并安排一次短延迟回焦；否则按“点击空白提交”的既定语义继续提交。
- 这样既保住了“点空白提交”，又不会把刚进入编辑态时的伪失焦误判为一次真实提交。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift
// 函数名: controlTextDidBeginEditing(_:) / controlTextDidEndEditing(_:) / scheduleRefocusAfterUnexpectedInitialEnd()
// 功能说明: 修改后 macOS item 只在稳定编辑后才把 unspecified end-edit 当成“点空白提交”；入场期异常失焦会被忽略并回焦。
func controlTextDidBeginEditing(_ obj: Notification) {
    guard obj.object as AnyObject? === titleTextField else {
        return
    }

    let requestID = titleEditFocusRequestID
    logRenameTrace("controlTextDidBeginEditing", extra: "requestID=\(requestID)")
    DispatchQueue.main.asyncAfter(deadline: .now() + TitleEditTiming.stabilizationDelay) { [weak self] in
        guard
            let self,
            self.titleEditFocusRequestID == requestID,
            self.isTitleEditingActive
        else {
            return
        }

        self.isAwaitingInitialFocusStabilization = false
        self.logRenameTrace(
            "titleEditingFocusStabilized",
            extra: "requestID=\(requestID)"
        )
    }
}

private func scheduleRefocusAfterUnexpectedInitialEnd() {
    logRenameTrace(
        "scheduleRefocusAfterUnexpectedInitialEnd",
        extra: "retryCount=\(unexpectedInitialEndRetryCount)"
    )
    scheduleTitleEditingFocus(
        delay: TitleEditTiming.refocusDelay,
        reason: "unexpectedInitialEnd"
    )
}

func controlTextDidEndEditing(_ obj: Notification) {
    guard obj.object as AnyObject? === titleTextField else {
        return
    }

    let disposition = pendingTitleEditEndDisposition
    pendingTitleEditEndDisposition = .unspecified
    logRenameTrace("controlTextDidEndEditing", extra: "disposition=\(String(describing: disposition))")

    switch disposition {
    case .commit:
        commitTitleEditIfNeeded()
    case .unspecified:
        if isAwaitingInitialFocusStabilization,
           unexpectedInitialEndRetryCount < TitleEditTiming.maximumUnexpectedEndRetries {
            unexpectedInitialEndRetryCount += 1
            logRenameTrace(
                "controlTextDidEndEditingIgnoredDuringStabilization",
                extra: "retryCount=\(unexpectedInitialEndRetryCount)"
            )
            scheduleRefocusAfterUnexpectedInitialEnd()
            return
        }

        commitTitleEditIfNeeded()
    case .cancel:
        cancelTitleEditIfNeeded()
    }
}
```

## 修改三：在复用、重配和提交/取消时显式失效旧的聚焦请求

### 修改前

- `prepareForReuse()`、`configure(...)`、`commitTitleEditIfNeeded()`、`cancelTitleEditIfNeeded()` 没有统一失效旧的异步聚焦请求。
- 一旦 item 被复用或结束编辑，旧一轮 `DispatchQueue.main.asyncAfter` 仍有机会晚到执行，产生陈旧聚焦行为。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift
// 函数名: prepareForReuse() / configure(...) / commitTitleEditIfNeeded() / cancelTitleEditIfNeeded()
// 功能说明: 修改前 item 生命周期里没有统一的“旧聚焦请求失效”机制。
override func prepareForReuse() {
    super.prepareForReuse()
    cancelThumbnailRequest()
    representedEntryID = nil
    representedBoardID = nil
    representedTitle = nil
    // ...
}

func configure(
    with entry: BoardListEntry,
    previewContent: BoardPreviewContent,
    displayMode: BoardListDisplayMode,
    isEditingTitle: Bool = false,
    onMoreActionsRequested: MoreActionsHandler? = nil,
    onRenameSubmitted: RenameSubmitHandler? = nil,
    onRenameCancelled: RenameCancelHandler? = nil
) {
    representedBoardID = entry.boardID
    representedTitle = entry.title
    isTitleEditingActive = isEditingTitle
    didHandleCurrentTitleEditEnd = false
    pendingTitleEditEndDisposition = .unspecified
}
```

### 修改后

- 新增 `invalidateTitleEditingFocusRequests()`，统一让旧一轮 `requestID` 失效，并结束“等待初始聚焦稳定”的状态。
- 在 `prepareForReuse()`、`configure(...)`、`commitTitleEditIfNeeded()`、`cancelTitleEditIfNeeded()` 中都调用这个 helper，避免过期的异步聚焦请求污染当前 item。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift
// 函数名: invalidateTitleEditingFocusRequests() / prepareForReuse() / configure(...) / commitTitleEditIfNeeded() / cancelTitleEditIfNeeded()
// 功能说明: 修改后 item 会在复用、重配和结束编辑时统一失效旧聚焦请求，防止延迟回调作用到错误的编辑会话。
private func invalidateTitleEditingFocusRequests() {
    titleEditFocusRequestID += 1
    isAwaitingInitialFocusStabilization = false
}

override func prepareForReuse() {
    super.prepareForReuse()
    if isTitleEditingActive || representedBoardID != nil {
        logRenameTrace("prepareForReuse")
    }
    invalidateTitleEditingFocusRequests()
    cancelThumbnailRequest()
    representedEntryID = nil
    representedBoardID = nil
    representedTitle = nil
    representedDisplayMode = nil
    representedRevisionToken = nil
    titleLabel.stringValue = ""
    titleTextField.stringValue = ""
    // ...
}

func configure(
    with entry: BoardListEntry,
    previewContent: BoardPreviewContent,
    displayMode: BoardListDisplayMode,
    isEditingTitle: Bool = false,
    onMoreActionsRequested: MoreActionsHandler? = nil,
    onRenameSubmitted: RenameSubmitHandler? = nil,
    onRenameCancelled: RenameCancelHandler? = nil
) {
    representedBoardID = entry.boardID
    representedTitle = entry.title
    self.onRenameSubmitted = onRenameSubmitted
    self.onRenameCancelled = onRenameCancelled
    invalidateTitleEditingFocusRequests()
    isTitleEditingActive = isEditingTitle
    didHandleCurrentTitleEditEnd = false
    pendingTitleEditEndDisposition = .unspecified
    unexpectedInitialEndRetryCount = 0
    titleLabel.stringValue = entry.title
    titleTextField.stringValue = entry.title
}

private func commitTitleEditIfNeeded() {
    guard
        isTitleEditingActive,
        didHandleCurrentTitleEditEnd == false,
        let representedBoardID
    else {
        logRenameTrace("commitTitleEditIgnored")
        return
    }

    invalidateTitleEditingFocusRequests()
    didHandleCurrentTitleEditEnd = true
    logRenameTrace("commitTitleEdit")
    onRenameSubmitted?(representedBoardID, titleTextField.stringValue)
}

private func cancelTitleEditIfNeeded() {
    guard
        isTitleEditingActive,
        didHandleCurrentTitleEditEnd == false,
        let representedBoardID
    else {
        logRenameTrace("cancelTitleEditIgnored")
        return
    }

    invalidateTitleEditingFocusRequests()
    didHandleCurrentTitleEditEnd = true
    logRenameTrace("cancelTitleEdit")
    onRenameCancelled?(representedBoardID)
}
```

## 修改四：补充 rename trace 字段，便于验证稳定期是否生效

### 修改前

- 旧日志只能看到进入/结束编辑的大致事件，无法直接看出当前是否还处于“初始聚焦稳定窗口”。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift
// 函数名: logRenameTrace(_:)
// 功能说明: 修改前日志不能直接区分“正常 blur 提交”和“初始稳定期内的异常失焦”。
private func logRenameTrace(_ phase: String, extra: String = "") {
    let extraSuffix = extra.isEmpty ? "" : " \(extra)"
    let isFirstResponder = view.window?.firstResponder === titleTextField
    print(
        "[BoardList][macOS][RenameTrace][Item] " +
            "t=\(boardListSelectionTraceTimestamp()) " +
            "phase=\(phase) " +
            "boardID=\(representedBoardID?.uuidString ?? "nil") " +
            "representedTitle=\"\(representedTitle ?? "")\" " +
            "textFieldText=\"\(titleTextField.stringValue)\" " +
            "editing=\(isTitleEditingActive) " +
            "textFieldHidden=\(titleTextField.isHidden) " +
            "isFirstResponder=\(isFirstResponder)" +
            extraSuffix
    )
}
```

### 修改后

- 新日志额外输出 `isAwaitingInitialFocusStabilization`。
- 这样复现时可以直接判断：某次 `controlTextDidEndEditing` 是否发生在“应忽略并回焦”的阶段。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift
// 函数名: logRenameTrace(_:)
// 功能说明: 修改后日志会显式输出初始聚焦稳定状态，便于验证“异常失焦被忽略并回焦”的修复是否生效。
private func logRenameTrace(_ phase: String, extra: String = "") {
    let extraSuffix = extra.isEmpty ? "" : " \(extra)"
    let isFirstResponder = view.window?.firstResponder === titleTextField
    print(
        "[BoardList][macOS][RenameTrace][Item] " +
            "t=\(boardListSelectionTraceTimestamp()) " +
            "phase=\(phase) " +
            "boardID=\(representedBoardID?.uuidString ?? "nil") " +
            "representedTitle=\"\(representedTitle ?? "")\" " +
            "textFieldText=\"\(titleTextField.stringValue)\" " +
            "editing=\(isTitleEditingActive) " +
            "textFieldHidden=\(titleTextField.isHidden) " +
            "isFirstResponder=\(isFirstResponder) " +
            "isAwaitingInitialFocusStabilization=\(isAwaitingInitialFocusStabilization)" +
            extraSuffix
    )
}
```

## 验证结果

- `ReadLints`
  - 检查文件：
    - `MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift`
  - 结果：无 linter 错误。
- `swiftc` typecheck
  - 命令：

```bash
xcrun --sdk macosx swiftc -typecheck -parse-as-library MyCanvas_Ver_0/**/*.swift
```

  - 结果：通过。

## 当前状态

- `macOS` 端 `Rename` 首次进入编辑态时，不再立即强制抢焦点。
- 如果在初始稳定窗口内收到一次异常的 `unspecified end-edit`，item 会先忽略这次结束事件并自动回焦一次。
- 稳定窗口结束后，仍保持既定交互语义：
  - `Return` 提交
  - `Esc` 取消
  - 点击空白区域提交
- 调试日志已保留，便于后续继续验证运行时序列。
