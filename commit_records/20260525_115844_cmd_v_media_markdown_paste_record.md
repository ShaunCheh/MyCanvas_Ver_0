# 20260525_115844_cmd_v_media_markdown_paste_record

## 记录范围

- 记录内容：
  - 将画布态 `cmd+v` 从“仅尝试媒体导入”扩展为“媒体优先导入、文本兜底创建 markdown block”。
  - 保持文本输入态与 markdown 编辑器态的原生粘贴语义，不把文本编辑器里的 `cmd+v` 误改成创建 markdown block。
  - 为新分流补充命令层回归测试，确认带文本的 markdown 创建命令会真正使用剪贴板文本，而不是回退成默认模板。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/Input/CanvasPastePayload.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSCanvasPasteboardPayloadResolver.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSCanvasPasteboardPayloadResolver.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasCommandExecutor.swift`
  - `MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
  - `MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests.swift`

## 参考现状

- 生成本记录前，执行 `date +"%Y%m%d_%H%M%S"`，得到时间戳：`20260525_115844`，本文件按该时间戳命名。
- 生成本记录前，针对本次修改相关文件执行 `git status --short -- ...`，结果为：
  - `M MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift`
  - `M MyCanvas_Ver_0/Canvas/Editing/CanvasCommandExecutor.swift`
  - `M MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift`
  - `M MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `M MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
  - `M MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests.swift`
  - `?? MyCanvas_Ver_0/Canvas/Input/CanvasPastePayload.swift`
  - `?? MyCanvas_Ver_0/Platform/iOS/iOSCanvasPasteboardPayloadResolver.swift`
  - `?? MyCanvas_Ver_0/Platform/macOS/macOSCanvasPasteboardPayloadResolver.swift`
- 生成本记录前，执行整体 `git status --short`，确认当前工作区还同时保留以下与本文无关的既有改动：
  - `M MyCanvas_Ver_0/Platform/Shared/BoardList/BoardListActionPanelState.swift`
  - `M MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift`
  - `M MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift`
  - 本文只记录本轮 `cmd+v -> media / markdown` 分流修改，不覆盖上述 `BoardList` 相关 changes。
- 生成本记录前，执行 `git diff -- ...`，确认当前 changes 包含：
  - `CanvasPastePayload` 共享枚举新增 `media / markdownText` 双分支
  - iOS / macOS 平台新增 pasteboard payload resolver，并统一采用“媒体优先，文本兜底”
  - `CanvasCommand.addMarkdownItem` 从无参命令扩展为可携带 `markdownSource`
  - iOS / macOS 控制器在画布态 paste 时改为按 payload 分流；在文本编辑态仍保留原生粘贴
  - `CanvasCommandPolicyParityTests` 同步改用新命令签名，并新增“带文本创建 markdown”断言
- 生成本记录前，已执行验证并通过：
  - `xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS' build`
  - `xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.1' build`
  - `xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS' test -only-testing:MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests`

## 当前 changes 摘要

- 根因不是 `markdown block` 无法承载外部文本，而是现有 `cmd+v` 入口被建模成了“transfer/import 媒体入口”，只会向下游请求 `CanvasTransferRequest`。
- `CanvasEditorSession` 其实早已支持 `addMarkdownItem(markdownSource:)`；缺口在于平台层没有先判断剪贴板里到底是媒体还是文本，也没有把“带文本创建 markdown”提升为正规的 command lane。
- 本轮修改没有把纯文本硬塞进 `CanvasTransferRequest`，而是新增一层 `CanvasPastePayload`：
  - 媒体继续走现有 `CanvasTransferRequest -> CanvasImportRequest -> importMedia`
  - 文本改走 `CanvasCommand.addMarkdownItem(markdownSource:)`
- 两个平台都保留了原生文本编辑粘贴：
  - iOS inline 文本编辑框 `firstResponder` 时，仍直接调用 `textView.paste(...)`
  - macOS 当前 `firstResponder` 是可编辑 `NSTextView` 时，菜单栏 `Paste` 与快捷键 `cmd+v` 都继续交给 responder 处理
- macOS 新增了一个防误判：如果剪贴板来源是 Finder 复制出的 `file URL`，即便系统同时暴露了路径字符串，也不会把路径字符串误当成 markdown 内容。

## 修改一：把 paste 入口从“只尝试媒体 transfer”改成“先判型再分流”

### 修改前

- `handlePasteRequest()` 直接调用平台 import adapter 请求 `CanvasTransferRequest`。
- 一旦剪贴板里不是图片 / 视频，对应分支就会直接 `return`，文本没有任何业务落点。
- 这也是为什么此前 `cmd+v` 只能表现成“导入媒体”，无法基于文本内容创建 markdown block。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: handlePasteRequest()
// 功能说明: 修改前 iOS 的 paste 入口只尝试解析媒体 transfer request；文本不会进入任何后续创建逻辑。
private func handlePasteRequest() {
    Task { @MainActor [weak self] in
        guard let self else {
            return
        }

        guard let transferRequest = await iOSCanvasImportAdapter.transferRequest(
            from: .general,
            sourceDescription: "pasteboard"
        ) else {
            return
        }

        _ = self.performTransferRequest(transferRequest)
        self.becomeFirstResponder()
    }
}
```

### 修改后

- 新增共享 `CanvasPastePayload`，把平台 paste 解析结果拆成：
  - `.media(CanvasTransferRequest)`
  - `.markdownText(String)`
- iOS / macOS 各自新增 resolver，统一采用“媒体优先、文本兜底”的判型顺序。
- 其中 macOS 额外拦截 `file URL`，避免 Finder 非媒体文件的路径字符串被误当成 markdown。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Input/CanvasPastePayload.swift
// 符号: CanvasPastePayload
// 功能说明: 修改后新增共享 paste payload，把媒体导入和 markdown 文本创建明确拆成两个业务分支。
enum CanvasPastePayload {
    case media(CanvasTransferRequest)
    case markdownText(String)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSCanvasPasteboardPayloadResolver.swift
// 函数名: resolvedPayload(from:sourceDescription:placement:layout:)
// 功能说明: 修改后 iOS 平台先尝试保留原媒体导入能力；只有媒体解析失败时，才把非空字符串降级为 markdownText。
static func resolvedPayload(
    from pasteboard: UIPasteboard,
    sourceDescription: String,
    placement: CanvasImportPlacement = .cameraCenter,
    layout: CanvasImportLayout = .automatic
) async -> CanvasPastePayload? {
    if let transferRequest = await iOSCanvasImportAdapter.transferRequest(
        from: pasteboard,
        sourceDescription: sourceDescription,
        placement: placement,
        layout: layout
    ) {
        return .media(transferRequest)
    }

    guard let text = resolvedMarkdownText(from: pasteboard) else {
        return nil
    }

    return .markdownText(text)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSCanvasPasteboardPayloadResolver.swift
// 函数名: resolvedPayload(from:sourceDescription:placement:layout:)
// 功能说明: 修改后 macOS 除了媒体优先，还会拦住 Finder file URL，避免把路径字符串误判成 markdown 文本。
static func resolvedPayload(
    from pasteboard: NSPasteboard,
    sourceDescription: String,
    placement: CanvasImportPlacement = .cameraCenter,
    layout: CanvasImportLayout = .automatic
) -> CanvasPastePayload? {
    if let transferRequest = macOSCanvasImportAdapter.transferRequest(
        from: pasteboard,
        sourceDescription: sourceDescription,
        placement: placement,
        layout: layout
    ) {
        return .media(transferRequest)
    }

    // Finder copies can expose both file URLs and path strings. If the file
    // URL is not importable media, avoid reinterpreting the path string as
    // markdown content.
    guard
        containsFileURLs(from: pasteboard) == false,
        let text = resolvedMarkdownText(from: pasteboard)
    else {
        return nil
    }

    return .markdownText(text)
}
```

## 修改二：把“带文本创建 markdown”正规提升到 command lane

### 修改前

- `CanvasCommand.addMarkdownItem` 是无参命令。
- `CanvasCommandExecutor` 也只会调用 `session.addMarkdownItem()`，因此无论入口来自工具栏、上下文菜单还是未来的 paste 分支，都只能创建默认模板 markdown。
- 如果平台层想临时绕过命令层、直接去调 `editorSession.addMarkdownItem(markdownSource:)`，又会绕开既有的命令语义、刷新链和统一收尾逻辑。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift
// 符号: CanvasCommand.addMarkdownItem
// 功能说明: 修改前 addMarkdownItem 不携带 markdownSource，命令层无法表达“用指定文本创建 markdown block”。
enum CanvasCommand {
    case importMedia(CanvasImportRequest)
    case addTextItem
    case addMarkdownItem
    case addHandDrawingItem(paper: CanvasHandDrawingPaperSpec)
    // ... 省略其他命令 ...
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommandExecutor.swift
// 函数名: execute(_:)
// 功能说明: 修改前执行器只会创建默认 markdown 模板，无法透传剪贴板文本。
case .addMarkdownItem:
    guard let addedMarkdownItem = session.addMarkdownItem() else {
        return nil
    }

    return CanvasCommandExecutionResult(
        refreshReason: "add markdown item \(addedMarkdownItem.id.uuidString)"
    )
```

### 修改后

- `CanvasCommand.addMarkdownItem` 升级为 `case addMarkdownItem(markdownSource: String?)`。
- `CanvasCommandExecutor` 根据 `markdownSource` 是否存在分流：
  - 有文本：`session.addMarkdownItem(markdownSource: markdownSource)`
  - 无文本：继续走原有默认模板创建
- 这样 paste 分支、工具栏按钮、上下文菜单都还能共用同一条命令链；只是默认入口显式传 `nil`，paste 文本入口传具体字符串。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommand.swift
// 符号: CanvasCommand.addMarkdownItem
// 功能说明: 修改后命令层支持透传可选 markdownSource，为 cmd+v 文本创建 markdown block 提供正规入口。
enum CanvasCommand {
    case importMedia(CanvasImportRequest)
    case addTextItem
    case addMarkdownItem(markdownSource: String?)
    case addHandDrawingItem(paper: CanvasHandDrawingPaperSpec)
    // ... 省略其他命令 ...
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasCommandExecutor.swift
// 函数名: execute(_:)
// 功能说明: 修改后执行器会把传入的 markdownSource 下发到 session；没有文本时仍保留默认 markdown 模板行为。
case let .addMarkdownItem(markdownSource):
    let addedMarkdownItem: CanvasMarkdownItem?
    if let markdownSource {
        addedMarkdownItem = session.addMarkdownItem(markdownSource: markdownSource)
    } else {
        addedMarkdownItem = session.addMarkdownItem()
    }

    guard let addedMarkdownItem else {
        return nil
    }

    return CanvasCommandExecutionResult(
        refreshReason: "add markdown item \(addedMarkdownItem.id.uuidString)"
    )
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift
// 函数名: command(for:context:)
// 功能说明: 修改后原有“Add Markdown”入口显式传入 nil，继续保持默认模板创建，不影响现有 UI 操作语义。
case .addMarkdownItem:
    return .addMarkdownItem(markdownSource: nil)
```

## 修改三：iOS 在文本编辑态保留原生 paste，在画布态改成 payload 分流

### 修改前

- 快捷键标题仍写死为 `Paste Image`。
- `handlePasteKeyCommand(_:)` 不区分当前焦点是否在 inline 文本编辑框，只要进来就继续往画布的媒体导入链路里走。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: setupKeyboardCommands() / handlePasteKeyCommand(_:)
// 功能说明: 修改前 iOS 的 discoverability 标题仍是 Paste Image，且 paste 处理没有先判断当前是不是文本输入态。
pasteCommand.discoverabilityTitle = "Paste Image"

@objc
private func handlePasteKeyCommand(_ sender: UIKeyCommand) {
    handleCapturedInput(
        .pasteKeyboardShortcut,
        sourceDescription: RawInputDeliverySource.pasteKeyCommand.debugName
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

### 修改后

- 快捷键标题改为更符合实际能力的 `Paste`。
- 如果当前焦点在 `textEditorOverlayView.textView`，则直接调用系统 `paste(sender)`，不创建 markdown block。
- 只有画布主态才会进一步调用 resolver：
  - `.media` -> 沿用现有导入逻辑
  - `.markdownText` -> 创建 markdown block

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: setupKeyboardCommands() / handlePasteKeyCommand(_:) / handlePasteRequest()
// 功能说明: 修改后 iOS 文本输入态保持原生 paste；画布态才按媒体或文本 payload 分流。
pasteCommand.discoverabilityTitle = "Paste"

@objc
private func handlePasteKeyCommand(_ sender: UIKeyCommand) {
    if textEditorOverlayView.textView.isFirstResponder {
        textEditorOverlayView.textView.paste(sender)
        return
    }

    handleCapturedInput(
        .pasteKeyboardShortcut,
        sourceDescription: RawInputDeliverySource.pasteKeyCommand.debugName
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

private func handlePasteRequest() {
    Task { @MainActor [weak self] in
        guard let self else {
            return
        }

        guard let pastePayload = await iOSCanvasPasteboardPayloadResolver.resolvedPayload(
            from: .general,
            sourceDescription: "pasteboard"
        ) else {
            return
        }

        switch pastePayload {
        case let .media(transferRequest):
            _ = self.performTransferRequest(transferRequest)
        case let .markdownText(markdownSource):
            self.performCommand(.addMarkdownItem(markdownSource: markdownSource))
        }
        self.becomeFirstResponder()
    }
}
```

## 修改四：macOS 的菜单栏 Paste / 快捷键 Paste 同时支持 responder 转发和 payload 分流

### 修改前

- `validateUserInterfaceItem(_:)` 只检查 `canTransferContent(...)`，菜单 `Paste` 的可用态完全等同于“当前能不能导入媒体”。
- `paste(_:)` 也不先看当前 `firstResponder` 是不是可编辑 `NSTextView`，导致文本编辑态的 paste 行为没有和画布态做清晰分层。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: validateUserInterfaceItem(_:) / paste(_:)
// 功能说明: 修改前 macOS 的菜单 Paste 与快捷键 Paste 都只围绕媒体 transfer 做判定和执行。
case #selector(macOSViewController.paste(_:)):
    return canTransferContent(
        from: .general,
        entry: resolvedPasteTransferEntryIntent()
    )

@objc
func paste(_ sender: Any?) {
    let rawInput = CanvasRawInputIntent.pasteKeyboardShortcut
    if consumeObservedKeyboardShortcut(rawInput) {
        handlePasteRequest()
        return
    }
    // ... 后续只会继续走 transferEntry / handlePasteRequest ...
}
```

### 修改后

- 新增 `currentEditableTextResponder`：
  - 当前 `firstResponder` 是可编辑 `NSTextView` 时，菜单栏 `Paste` 与快捷键 `cmd+v` 都继续交给 responder
- 新增 `canPasteContent(...)`：
  - 画布主态下，不再只认媒体，而是按新的 `CanvasPastePayload` 能力判断菜单栏 `Paste` 是否可用
- `handlePasteRequest()` 则与 iOS 一样改为 `media / markdownText` 双分支

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: validateUserInterfaceItem(_:) / paste(_:) / canPasteContent(...) / handlePasteRequest() / currentEditableTextResponder
// 功能说明: 修改后 macOS 在可编辑 NSTextView 上保留原生 paste；在画布主态则按新的 paste payload 分流。
case #selector(macOSViewController.paste(_:)):
    if let editableTextResponder = currentEditableTextResponder {
        return NSPasteboard.general.availableType(
            from: editableTextResponder.readablePasteboardTypes
        ) != nil
    }

    return canPasteContent(
        from: .general,
        entry: resolvedPasteTransferEntryIntent()
    )

@objc
func paste(_ sender: Any?) {
    if let editableTextResponder = currentEditableTextResponder {
        editableTextResponder.paste(sender)
        return
    }

    let rawInput = CanvasRawInputIntent.pasteKeyboardShortcut
    if consumeObservedKeyboardShortcut(rawInput) {
        handlePasteRequest()
        return
    }
    // ... 后续继续保留 interaction gate 与快捷键观察逻辑 ...
}

private func canPasteContent(
    from pasteboard: NSPasteboard,
    entry: CanvasTransferEntryIntent
) -> Bool {
    isTransferEntryAllowed(entry) &&
        macOSCanvasPasteboardPayloadResolver.canResolvePayload(from: pasteboard)
}

private func handlePasteRequest() {
    guard let pastePayload = macOSCanvasPasteboardPayloadResolver.resolvedPayload(
        from: .general,
        sourceDescription: "pasteboard"
    ) else {
        return
    }

    switch pastePayload {
    case let .media(transferRequest):
        _ = performTransferRequest(transferRequest)
    case let .markdownText(markdownSource):
        performCommand(.addMarkdownItem(markdownSource: markdownSource))
    }
}

private var currentEditableTextResponder: NSTextView? {
    guard
        let textView = NSApp.keyWindow?.firstResponder as? NSTextView,
        textView.isEditable
    else {
        return nil
    }

    return textView
}
```

## 修改五：测试同步到新命令签名，并新增“带文本创建 markdown”断言

### 修改前

- `CanvasCommandPolicyParityTests` 仍按旧命令签名断言 `executor.canExecute(.addMarkdownItem)`。
- 测试里也没有覆盖“传入 markdownSource 时，命令执行器是否真的把指定文本透传给 session”。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests.swift
// 函数名: testAddMarkdownDescriptorAndExecutorMatchPolicyInEditingMode()
// 功能说明: 修改前测试仍使用无参 addMarkdownItem，无法约束新的带文本创建分支。
XCTAssertTrue(executor.canExecute(.addMarkdownItem))
```

### 修改后

- 现有可执行性断言统一改成 `.addMarkdownItem(markdownSource: nil)`，与命令新签名保持一致。
- 新增 `testAddMarkdownCommandUsesProvidedSourceWhenPresent()`，直接验证执行器会把传入文本写入选中的 markdown item。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests.swift
// 函数名: testAddMarkdownDescriptorAndExecutorMatchPolicyInEditingMode() / testAddMarkdownCommandUsesProvidedSourceWhenPresent()
// 功能说明: 修改后测试同时覆盖 nil 与显式文本两种 addMarkdownItem 调用方式，防止回退成默认模板。
XCTAssertTrue(executor.canExecute(.addMarkdownItem(markdownSource: nil)))

func testAddMarkdownCommandUsesProvidedSourceWhenPresent() throws {
    let session = makeCommandPolicyParityTestSession(workspaceMode: .editing)
    let executor = CanvasCommandExecutor(session: session)
    CanvasCommandPolicyParityTestRetainer.executors.append(executor)
    let source = """
    # Pasted

    Body from clipboard.
    """

    let result = try XCTUnwrap(
        executor.execute(.addMarkdownItem(markdownSource: source))
    )
    let item = try XCTUnwrap(session.selectedMarkdownItem)

    XCTAssertEqual(item.markdownSource, source)
    XCTAssertEqual(
        result.refreshReason,
        "add markdown item \(item.id.uuidString)"
    )
}
```

## 结果说明

- 画布主态下：
  - 复制图片 / 视频后按 `cmd+v`，仍然直接导入画布
  - 复制非空文本后按 `cmd+v`，会直接创建一个内容等于剪贴板原文的 markdown block
- 文本输入态 / markdown 编辑器态下：
  - 粘贴继续交给原生文本控件处理，不会误创建 markdown block
- 当前工作区里仍然保留 `BoardList` 删除功能相关的未提交 changes；这份记录只覆盖本轮 `cmd+v` 分流修改本身。
