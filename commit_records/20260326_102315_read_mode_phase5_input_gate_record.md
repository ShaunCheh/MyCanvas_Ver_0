# 20260326_102315_read_mode_phase5_input_gate_record

## 记录范围

- 记录内容：实施“阅读模式切换”计划的 `Phase 5`，把输入链收敛为“阅读模式只允许平移 / 缩放 / 小地图导航 / 返回”。
- 记录内容：让共享命中解析层在阅读模式下统一降级为画布空白命中，而不是继续命中 item body / selection handle / crop handle / rotate handle。
- 记录内容：让 `iOSViewController` / `macOSViewController` 对长按 / 副键菜单 / 导入 / 拖拽导入 / 粘贴 / 直接进入文字编辑等不走 `CanvasCommandExecutor` 的系统输入入口做阅读模式早退。
- 记录内容：修复 Phase 4 之后残留的一个根因问题: 阅读模式下真实 `inlineEditState` 仍在，`handlePrimaryPointerDown` 继续先走 `commitActiveTextEditIfNeeded()`，但 `commitTextEdit` 已被命令层阻断，导致输入被吞掉、无法自然进入画布导航。
- 涉及源码文件：`MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift`
- 涉及源码文件：`MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
- 涉及源码文件：`MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- 涉及源码文件：`MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 本记录不包含：Phase 6 的手工回归验证记录。
- 本记录不包含：原始 gif diff。

## 修改一：共享 resolver 在阅读模式下统一把命中降级为 `.blank`

### 修改前

- `CanvasContextResolver` 只接收 `isInlineEditModeActive` / `isInlineCropModeActive`，并不知道当前是否处于阅读模式。
- 结果是即使 UI 已经隐藏了 toolbar / 选中框 / 裁剪框，只要底层 scene 里还能命中 item，pointer 仍然会被解析为 `.selectedItemBody`、`.unselectedItemBody`、`.selectionHandle`、`.cropHandle`、`.rotateHandle` 等编辑语义。
- 这会迫使双端控制器在输入层到处打补丁，无法从根因上把“阅读模式只剩导航”变成共享规则。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift
// 函数名/符号名: resolvePointerTarget(...) / resolveContext(...) / resolveTarget(...)
// 功能说明: 修改前共享命中层不感知阅读模式，仍然会把手势解析为 item body 或编辑句柄，导致上层输入状态机继续偏向编辑分支。
struct CanvasContextResolver {
    func resolvePointerTarget(
        at viewportPoint: CGPoint,
        scene: CanvasScene,
        camera: CanvasCamera,
        renderSnapshot: CanvasRenderSnapshot,
        selectedItemID: CanvasItemID?,
        isInlineEditModeActive: Bool,
        interactionMetrics: CanvasContextResolverMetrics
    ) -> CanvasPointerPressContext {
        let invocationWorldPoint = camera.viewportToWorld(viewportPoint)
        let resolution = resolveTarget(
            at: viewportPoint,
            invocationWorldPoint: invocationWorldPoint,
            scene: scene,
            renderSnapshot: renderSnapshot,
            selectedItemID: selectedItemID,
            isInlineEditModeActive: isInlineEditModeActive,
            interactionMetrics: interactionMetrics
        )

        return makePointerPressContext(
            viewportPoint: viewportPoint,
            worldPoint: invocationWorldPoint,
            resolvedTarget: resolution.resolvedTarget
        )
    }

    func resolveContext(
        at viewportPoint: CGPoint,
        scene: CanvasScene,
        camera: CanvasCamera,
        renderSnapshot: CanvasRenderSnapshot,
        selectedItemID: CanvasItemID?,
        isInlineEditModeActive: Bool,
        isInlineCropModeActive: Bool,
        interactionMetrics: CanvasContextResolverMetrics
    ) -> CanvasContextMenuContext {
        let invocationWorldPoint = camera.viewportToWorld(viewportPoint)
        let resolution = resolveTarget(
            at: viewportPoint,
            invocationWorldPoint: invocationWorldPoint,
            scene: scene,
            renderSnapshot: renderSnapshot,
            selectedItemID: selectedItemID,
            isInlineEditModeActive: isInlineEditModeActive,
            interactionMetrics: interactionMetrics
        )

        return makeContext(
            viewportPoint: viewportPoint,
            worldPoint: invocationWorldPoint,
            resolvedTarget: resolution.resolvedTarget,
            selectedItemID: selectedItemID,
            isInlineEditModeActive: isInlineEditModeActive,
            isInlineCropModeActive: isInlineCropModeActive
        )
    }

    private func resolveTarget(
        at viewportPoint: CGPoint,
        invocationWorldPoint: CGPoint,
        scene: CanvasScene,
        renderSnapshot: CanvasRenderSnapshot,
        selectedItemID: CanvasItemID?,
        isInlineEditModeActive: Bool,
        interactionMetrics: CanvasContextResolverMetrics
    ) -> ResolutionResult {
        if let editOverlayHitTarget = editOverlayHitTester.resolve(
            at: viewportPoint,
            renderSnapshot: renderSnapshot,
            metrics: interactionMetrics
        ) {
            return ResolutionResult(
                branch: contextResolverBranch(for: editOverlayHitTarget),
                resolvedTarget: resolvedTarget(from: editOverlayHitTarget)
            )
        }

        if isInlineEditModeActive {
            return ResolutionResult(
                branch: "inlineEditBlank",
                resolvedTarget: ResolvedTarget(pointerTargetKind: .blank)
            )
        }

        guard let itemID = scene.topmostBoardItemID(containing: invocationWorldPoint) else {
            return ResolutionResult(
                branch: "blank",
                resolvedTarget: ResolvedTarget(pointerTargetKind: .blank)
            )
        }

        let targetKind: CanvasPointerTargetKind =
            itemID == selectedItemID ? .selectedItemBody : .unselectedItemBody

        return ResolutionResult(
            branch: "itemBody",
            resolvedTarget: ResolvedTarget(
                pointerTargetKind: targetKind,
                targetItemID: itemID,
                anchorRect: itemAnchorRect(for: itemID, renderSnapshot: renderSnapshot)
            ),
            sceneHitItemID: itemID
        )
    }
}
```

### 修改后

- 给 `resolvePointerTarget(...)` / `resolveContext(...)` / `resolveTarget(...)` 增加 `isReadingModeActive` 参数。
- 在 `resolveTarget(...)` 的最前面增加阅读模式分支：
  - 如果点到了 board item，仍然记录 `sceneHitItemID` 进入日志；
  - 但真正返回给 pointer 状态机和 context menu 的 `resolvedTarget` 一律降级为 `.blank`。
- 这样现有双端状态机不用大改，就会天然更偏向走 `draggingCanvas`，而不是继续触发选中、拖拽、裁剪、旋转、文字编辑这些编辑语义。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift
// 函数名/符号名: resolvePointerTarget(...) / resolveContext(...) / resolveTarget(...)
// 功能说明: 修改后共享命中层直接感知阅读模式，并把所有 item / overlay 命中统一降级成 blank 导航语义。
struct CanvasContextResolver {
    func resolvePointerTarget(
        at viewportPoint: CGPoint,
        scene: CanvasScene,
        camera: CanvasCamera,
        renderSnapshot: CanvasRenderSnapshot,
        selectedItemID: CanvasItemID?,
        isInlineEditModeActive: Bool,
        isReadingModeActive: Bool,
        interactionMetrics: CanvasContextResolverMetrics
    ) -> CanvasPointerPressContext {
        let invocationWorldPoint = camera.viewportToWorld(viewportPoint)
        let resolution = resolveTarget(
            at: viewportPoint,
            invocationWorldPoint: invocationWorldPoint,
            scene: scene,
            renderSnapshot: renderSnapshot,
            selectedItemID: selectedItemID,
            isInlineEditModeActive: isInlineEditModeActive,
            isReadingModeActive: isReadingModeActive,
            interactionMetrics: interactionMetrics
        )

        return makePointerPressContext(
            viewportPoint: viewportPoint,
            worldPoint: invocationWorldPoint,
            resolvedTarget: resolution.resolvedTarget
        )
    }

    func resolveContext(
        at viewportPoint: CGPoint,
        scene: CanvasScene,
        camera: CanvasCamera,
        renderSnapshot: CanvasRenderSnapshot,
        selectedItemID: CanvasItemID?,
        isInlineEditModeActive: Bool,
        isInlineCropModeActive: Bool,
        isReadingModeActive: Bool,
        interactionMetrics: CanvasContextResolverMetrics
    ) -> CanvasContextMenuContext {
        let invocationWorldPoint = camera.viewportToWorld(viewportPoint)
        let resolution = resolveTarget(
            at: viewportPoint,
            invocationWorldPoint: invocationWorldPoint,
            scene: scene,
            renderSnapshot: renderSnapshot,
            selectedItemID: selectedItemID,
            isInlineEditModeActive: isInlineEditModeActive,
            isReadingModeActive: isReadingModeActive,
            interactionMetrics: interactionMetrics
        )

        return makeContext(
            viewportPoint: viewportPoint,
            worldPoint: invocationWorldPoint,
            resolvedTarget: resolution.resolvedTarget,
            selectedItemID: selectedItemID,
            isInlineEditModeActive: isInlineEditModeActive,
            isInlineCropModeActive: isInlineCropModeActive
        )
    }

    private func resolveTarget(
        at viewportPoint: CGPoint,
        invocationWorldPoint: CGPoint,
        scene: CanvasScene,
        renderSnapshot: CanvasRenderSnapshot,
        selectedItemID: CanvasItemID?,
        isInlineEditModeActive: Bool,
        isReadingModeActive: Bool,
        interactionMetrics: CanvasContextResolverMetrics
    ) -> ResolutionResult {
        if isReadingModeActive {
            let sceneHitItemID = scene.topmostBoardItemID(
                containing: invocationWorldPoint
            )
            return ResolutionResult(
                branch: sceneHitItemID == nil
                    ? "readingModeBlank"
                    : "readingModeItemSuppressed",
                resolvedTarget: ResolvedTarget(pointerTargetKind: .blank),
                sceneHitItemID: sceneHitItemID
            )
        }

        if let editOverlayHitTarget = editOverlayHitTester.resolve(
            at: viewportPoint,
            renderSnapshot: renderSnapshot,
            metrics: interactionMetrics
        ) {
            return ResolutionResult(
                branch: contextResolverBranch(for: editOverlayHitTarget),
                resolvedTarget: resolvedTarget(from: editOverlayHitTarget)
            )
        }

        // ... 省略与本次改动无关的后续 blank / itemBody 分支 ...
    }
}
```

### 结果

- 阅读模式下，shared hit test 的真源已经从“编辑命中”切成“导航命中”。
- 这样双端 pointer 状态机不需要到处额外判断 item / handle 类型，只要保持 `.blank -> draggingCanvas` 的现有分支即可。

## 修改二：`CanvasEditorSession` 把阅读模式语义透传到共享 resolver

### 修改前

- `CanvasEditorSession.resolveContext(...)` / `resolvePointerTarget(...)` 只透传选中状态和 inline edit / crop 状态，没有把 `workspaceMode` 往下送。
- 所以上一节即使想在共享层做阅读模式降级，也拿不到统一语义输入。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名/符号名: resolveContext(at:interactionMetrics:) / resolvePointerTarget(at:interactionMetrics:)
// 功能说明: 修改前 editor session 没有把阅读模式透传给共享 resolver，resolver 无法从根因上降级命中结果。
func resolveContext(
    at viewportPoint: CGPoint,
    interactionMetrics: CanvasContextResolverMetrics
) -> CanvasContextMenuContext {
    contextResolver.resolveContext(
        at: viewportPoint,
        scene: scene,
        camera: camera,
        renderSnapshot: lastRenderSnapshot,
        selectedItemID: interactionState.selectedItemID,
        isInlineEditModeActive: isInlineEditModeActive,
        isInlineCropModeActive: isInlineCropModeActive,
        interactionMetrics: interactionMetrics
    )
}

func resolvePointerTarget(
    at viewportPoint: CGPoint,
    interactionMetrics: CanvasContextResolverMetrics
) -> CanvasPointerPressContext {
    contextResolver.resolvePointerTarget(
        at: viewportPoint,
        scene: scene,
        camera: camera,
        renderSnapshot: lastRenderSnapshot,
        selectedItemID: interactionState.selectedItemID,
        isInlineEditModeActive: isInlineEditModeActive,
        interactionMetrics: interactionMetrics
    )
}
```

### 修改后

- 两个入口都增加了 `isReadingModeActive: isReadingModeActive` 透传。
- `CanvasEditorSession` 继续作为 workspace 语义的共享中心，平台层仍只调 `editorSession.resolve*`，不需要自己直连 `CanvasContextResolver`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名/符号名: resolveContext(at:interactionMetrics:) / resolvePointerTarget(at:interactionMetrics:)
// 功能说明: 修改后由 editor session 把阅读模式统一透传给 resolver，形成“workspaceMode -> hit test -> input state machine”的共享链路。
func resolveContext(
    at viewportPoint: CGPoint,
    interactionMetrics: CanvasContextResolverMetrics
) -> CanvasContextMenuContext {
    contextResolver.resolveContext(
        at: viewportPoint,
        scene: scene,
        camera: camera,
        renderSnapshot: lastRenderSnapshot,
        selectedItemID: interactionState.selectedItemID,
        isInlineEditModeActive: isInlineEditModeActive,
        isInlineCropModeActive: isInlineCropModeActive,
        isReadingModeActive: isReadingModeActive,
        interactionMetrics: interactionMetrics
    )
}

func resolvePointerTarget(
    at viewportPoint: CGPoint,
    interactionMetrics: CanvasContextResolverMetrics
) -> CanvasPointerPressContext {
    contextResolver.resolvePointerTarget(
        at: viewportPoint,
        scene: scene,
        camera: camera,
        renderSnapshot: lastRenderSnapshot,
        selectedItemID: interactionState.selectedItemID,
        isInlineEditModeActive: isInlineEditModeActive,
        isReadingModeActive: isReadingModeActive,
        interactionMetrics: interactionMetrics
    )
}
```

### 结果

- 阅读模式命中降级不再散落在双端控制器，而是先进入共享 session，再下沉到共享 resolver。
- 共享状态层和平台输入层之间的职责边界保持清晰。

## 修改三：iOS 侧对不走 command 的输入入口统一做阅读模式早退

### 修改前

- `handlePrimaryPointerDown(at:)` 无条件先走 `commitActiveTextEditIfNeeded()`。
- `handleLongPress(at:)` 会继续弹上下文菜单。
- `handleImportButtonTap()`、`UIDropInteraction`、`picker(_:didFinishPicking:)`、`handlePasteRequest()`、`performTransferRequest(_:)` 都没有阅读模式守卫。
- `beginTextEditIfPossible(for:)` 也没有阅读模式守卫，意味着某些“再次点选文字进入编辑”的手势入口仍然存在漏口。
- 结果是 Phase 4 虽然已经把命令层挡住，但系统输入层仍然会继续尝试发起这些编辑行为。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/符号名: handlePrimaryPointerDown(at:) / handleLongPress(at:) / handleImportButtonTap() / dropInteraction(...) / canTransferContent(from:) / performTransferRequest(_) / beginTextEditIfPossible(for:)
// 功能说明: 修改前 iOS 侧仍有多个系统输入入口绕过共享命令门控，阅读模式下可能继续触发菜单、导入、粘贴和文字编辑。
private func handlePrimaryPointerDown(at location: CGPoint) {
    syncCameraViewportSizeFromCurrentBoundsIfPossible()
    guard hasRenderableViewportSize else {
        return
    }

    if commitActiveTextEditIfNeeded() {
        return
    }

    if contextMenuState != nil {
        dismissContextMenu()
        return
    }

    let pressContext = resolvePointerPressContext(at: location)
    pointerDragState = .pressed(
        pressedLocation: location,
        pressContext: pressContext
    )
}

private func handleLongPress(at location: CGPoint) {
    syncCameraViewportSizeFromCurrentBoundsIfPossible()
    guard hasRenderableViewportSize else {
        return
    }

    if commitActiveTextEditIfNeeded() {
        return
    }

    prepareForLongPressContextMenu()
    let resolvedContext = resolveContext(at: location)
    presentContextMenu(for: resolvedContext)
}

@objc
private func handleImportButtonTap() {
    commitActiveTextEditIfNeeded()
    var configuration = PHPickerConfiguration(photoLibrary: .shared())
    configuration.filter = .images
    configuration.selectionLimit = 0
    let pickerViewController = PHPickerViewController(configuration: configuration)
    pickerViewController.delegate = self
    present(pickerViewController, animated: true)
}

func dropInteraction(
    _ interaction: UIDropInteraction,
    canHandle session: UIDropSession
) -> Bool {
    iOSCanvasImportAdapter.canResolveTransfer(from: session)
}

func dropInteraction(
    _ interaction: UIDropInteraction,
    sessionDidUpdate session: UIDropSession
) -> UIDropProposal {
    if iOSCanvasImportAdapter.canResolveTransfer(from: session) {
        return UIDropProposal(operation: .copy)
    }

    return UIDropProposal(operation: .cancel)
}

func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    picker.dismiss(animated: true)

    guard results.isEmpty == false else {
        return
    }

    // ... 省略与本次改动无关的 transferRequest 构建代码 ...
}

private func canTransferContent(from pasteboard: UIPasteboard) -> Bool {
    iOSCanvasImportAdapter.canResolveTransfer(from: pasteboard)
}

private func performTransferRequest(
    _ request: CanvasTransferRequest
) -> Bool {
    guard let command = CanvasTransferCommandLowerer.loweredCommand(
        for: request
    ) else {
        return false
    }

    performCommand(command)
    return true
}

private func beginTextEditIfPossible(for itemID: CanvasItemID) -> Bool {
    guard scene.textItem(withID: itemID) != nil else {
        return false
    }

    performCommand(.beginTextEdit(itemID: itemID))
    return isInlineTextModeActive
}
```

### 修改后

- `handlePrimaryPointerDown(at:)` 改为只有编辑模式才会先 `commitActiveTextEditIfNeeded()`，避免阅读模式下隐藏中的真实 text edit state 抢先吞掉导航输入。
- `handleLongPress(at:)` 在阅读模式下直接 `dismissContextMenu()` 并返回，不再进入上下文菜单链。
- `handleImportButtonTap()`、`UIDropInteraction`、`picker(_:didFinishPicking:)`、`canTransferContent(from:)`、`performTransferRequest(_:)` 全部补上阅读模式守卫。
- `beginTextEditIfPossible(for:)` 也补上阅读模式守卫，彻底堵住“再次点文字进入编辑”的漏口。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/符号名: handlePrimaryPointerDown(at:) / handleLongPress(at:) / handleImportButtonTap() / dropInteraction(...) / canTransferContent(from:) / performTransferRequest(_) / beginTextEditIfPossible(for:)
// 功能说明: 修改后 iOS 侧把命中层以外的系统输入入口全部收口到阅读模式语义，只保留平移、缩放、小地图导航和返回。
private func handlePrimaryPointerDown(at location: CGPoint) {
    syncCameraViewportSizeFromCurrentBoundsIfPossible()
    guard hasRenderableViewportSize else {
        return
    }

    if workspaceMode == .editing, commitActiveTextEditIfNeeded() {
        return
    }

    if contextMenuState != nil {
        dismissContextMenu()
        return
    }

    let pressContext = resolvePointerPressContext(at: location)
    pointerDragState = .pressed(
        pressedLocation: location,
        pressContext: pressContext
    )
}

private func handleLongPress(at location: CGPoint) {
    syncCameraViewportSizeFromCurrentBoundsIfPossible()
    guard hasRenderableViewportSize else {
        return
    }

    guard isReadingModeActive == false else {
        dismissContextMenu()
        return
    }

    if commitActiveTextEditIfNeeded() {
        return
    }

    prepareForLongPressContextMenu()
    let resolvedContext = resolveContext(at: location)
    presentContextMenu(for: resolvedContext)
}

@objc
private func handleImportButtonTap() {
    guard isReadingModeActive == false else {
        return
    }

    commitActiveTextEditIfNeeded()
    var configuration = PHPickerConfiguration(photoLibrary: .shared())
    configuration.filter = .images
    configuration.selectionLimit = 0
    let pickerViewController = PHPickerViewController(configuration: configuration)
    pickerViewController.delegate = self
    present(pickerViewController, animated: true)
}

func dropInteraction(
    _ interaction: UIDropInteraction,
    canHandle session: UIDropSession
) -> Bool {
    isReadingModeActive == false &&
        iOSCanvasImportAdapter.canResolveTransfer(from: session)
}

func dropInteraction(
    _ interaction: UIDropInteraction,
    sessionDidUpdate session: UIDropSession
) -> UIDropProposal {
    if isReadingModeActive == false,
       iOSCanvasImportAdapter.canResolveTransfer(from: session)
    {
        return UIDropProposal(operation: .copy)
    }

    return UIDropProposal(operation: .cancel)
}

func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    picker.dismiss(animated: true)

    guard results.isEmpty == false, isReadingModeActive == false else {
        return
    }

    // ... 省略与本次改动无关的 transferRequest 构建代码 ...
}

private func canTransferContent(from pasteboard: UIPasteboard) -> Bool {
    isReadingModeActive == false &&
        iOSCanvasImportAdapter.canResolveTransfer(from: pasteboard)
}

private func performTransferRequest(
    _ request: CanvasTransferRequest
) -> Bool {
    guard isReadingModeActive == false else {
        return false
    }

    guard let command = CanvasTransferCommandLowerer.loweredCommand(
        for: request
    ) else {
        return false
    }

    performCommand(command)
    return true
}

private func beginTextEditIfPossible(for itemID: CanvasItemID) -> Bool {
    guard isReadingModeActive == false else {
        return false
    }

    guard scene.textItem(withID: itemID) != nil else {
        return false
    }

    performCommand(.beginTextEdit(itemID: itemID))
    return isInlineTextModeActive
}
```

### 结果

- iOS 侧阅读模式下不会再弹长按菜单、不会接受拖拽导入、不会响应粘贴、不会重新进入文字编辑。
- `pointer down` 在阅读模式下也不再被隐藏中的真实 text edit state 卡住，能继续走 resolver 降级后的画布导航路径。

## 修改四：macOS 侧对副键菜单、导入、粘贴和直接进入编辑统一做阅读模式早退

### 修改前

- `handlePrimaryPointerDown(at:)` 同样无条件先走 `commitActiveTextEditIfNeeded()`。
- `handleSecondaryClick(at:)` 会继续构造上下文菜单。
- `handleImportButtonClick()`、`handlePasteRequest()`、`dragOperation(for:)`、`handleImportDrop(pasteboard:)`、`performTransferRequest(_:)` 都没有阅读模式守卫。
- `beginTextEditIfPossible(for:)` 也没有阅读模式守卫。
- 控制器内部没有 `isReadingModeActive` 的便捷访问属性，多个分支如果都直接写 `editorSession.isReadingModeActive`，后面会继续拉低双端结构对称性。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/符号名: handlePrimaryPointerDown(at:) / handleSecondaryClick(at:) / handleImportButtonClick() / canTransferContent(from:) / handlePasteRequest() / handleImportDrop(pasteboard:) / performTransferRequest(_) / beginTextEditIfPossible(for:)
// 功能说明: 修改前 macOS 侧的副键菜单、open panel、拖放、粘贴和直接进入文字编辑都没有阅读模式早退。
private func handlePrimaryPointerDown(at location: CGPoint) {
    if commitActiveTextEditIfNeeded() {
        return
    }
    if contextMenuState != nil {
        dismissContextMenu()
        return
    }

    let pressContext = resolvePointerPressContext(at: location)
    pointerDragState = .pressed(
        pressedLocation: location,
        pressContext: pressContext
    )
}

private func handleSecondaryClick(at location: CGPoint) {
    if commitActiveTextEditIfNeeded() {
        return
    }

    updateCameraViewportSizeIfNeeded(trigger: "secondary click")
    prepareForSecondaryClickContextMenu()
    let resolvedContext = resolveContext(at: location)
    presentContextMenu(for: resolvedContext)
}

@objc
private func handleImportButtonClick() {
    commitActiveTextEditIfNeeded()
    guard let window = view.window else {
        return
    }

    let openPanel = NSOpenPanel()
    openPanel.allowedContentTypes = [.image]
    openPanel.allowsMultipleSelection = true
    openPanel.beginSheetModal(for: window) { [weak self] response in
        guard
            response == .OK,
            let self
        else {
            return
        }

        // ... 省略与本次改动无关的 transferRequest 构建代码 ...
    }
}

private func canTransferContent(from pasteboard: NSPasteboard) -> Bool {
    macOSCanvasImportAdapter.canResolveTransfer(from: pasteboard)
}

private func handlePasteRequest() {
    guard let transferRequest = macOSCanvasImportAdapter.transferRequest(
        from: .general,
        sourceDescription: "pasteboard"
    ) else {
        return
    }

    _ = performTransferRequest(transferRequest)
}

private func handleImportDrop(
    pasteboard: NSPasteboard
) -> Bool {
    guard let transferRequest = macOSCanvasImportAdapter.transferRequest(
        from: pasteboard,
        sourceDescription: "drag and drop"
    ) else {
        return false
    }

    let didImport = performTransferRequest(transferRequest)
    return didImport
}

private func performTransferRequest(
    _ request: CanvasTransferRequest
) -> Bool {
    guard let command = CanvasTransferCommandLowerer.loweredCommand(
        for: request
    ) else {
        return false
    }

    performCommand(command)
    return true
}

private func beginTextEditIfPossible(for itemID: CanvasItemID) -> Bool {
    guard scene.textItem(withID: itemID) != nil else {
        return false
    }

    performCommand(.beginTextEdit(itemID: itemID))
    return isInlineTextModeActive
}
```

### 修改后

- `handlePrimaryPointerDown(at:)` 改为只有编辑模式才会先 `commitActiveTextEditIfNeeded()`。
- `handleSecondaryClick(at:)` 在阅读模式下直接关闭旧菜单并返回，不再继续进入 context menu 解析链。
- `handleImportButtonClick()`、open panel 回调、`canTransferContent(from:)`、`handlePasteRequest()`、`handleImportDrop(pasteboard:)`、`performTransferRequest(_:)` 全部补上阅读模式守卫。
- 新增 `private var isReadingModeActive: Bool` 便捷属性，保持与 iOS 侧一致。
- `beginTextEditIfPossible(for:)` 同样补上阅读模式守卫，封住再次进入文字编辑的入口。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/符号名: handlePrimaryPointerDown(at:) / handleSecondaryClick(at:) / handleImportButtonClick() / canTransferContent(from:) / handlePasteRequest() / handleImportDrop(pasteboard:) / performTransferRequest(_) / isReadingModeActive / beginTextEditIfPossible(for:)
// 功能说明: 修改后 macOS 侧把副键菜单、open panel、拖放、粘贴和直接进入编辑全部统一收口到阅读模式语义。
private func handlePrimaryPointerDown(at location: CGPoint) {
    if workspaceMode == .editing, commitActiveTextEditIfNeeded() {
        return
    }
    if contextMenuState != nil {
        dismissContextMenu()
        return
    }

    let pressContext = resolvePointerPressContext(at: location)
    pointerDragState = .pressed(
        pressedLocation: location,
        pressContext: pressContext
    )
}

private func handleSecondaryClick(at location: CGPoint) {
    guard isReadingModeActive == false else {
        dismissContextMenu()
        return
    }

    if commitActiveTextEditIfNeeded() {
        return
    }

    updateCameraViewportSizeIfNeeded(trigger: "secondary click")
    prepareForSecondaryClickContextMenu()
    let resolvedContext = resolveContext(at: location)
    presentContextMenu(for: resolvedContext)
}

@objc
private func handleImportButtonClick() {
    guard isReadingModeActive == false else {
        return
    }

    commitActiveTextEditIfNeeded()
    guard let window = view.window else {
        return
    }

    let openPanel = NSOpenPanel()
    openPanel.allowedContentTypes = [.image]
    openPanel.allowsMultipleSelection = true
    openPanel.beginSheetModal(for: window) { [weak self] response in
        guard
            response == .OK,
            let self
        else {
            return
        }

        guard self.isReadingModeActive == false else {
            return
        }

        // ... 省略与本次改动无关的 transferRequest 构建代码 ...
    }
}

private func canTransferContent(from pasteboard: NSPasteboard) -> Bool {
    isReadingModeActive == false &&
        macOSCanvasImportAdapter.canResolveTransfer(from: pasteboard)
}

private func handlePasteRequest() {
    guard isReadingModeActive == false else {
        return
    }

    guard let transferRequest = macOSCanvasImportAdapter.transferRequest(
        from: .general,
        sourceDescription: "pasteboard"
    ) else {
        return
    }

    _ = performTransferRequest(transferRequest)
}

private func handleImportDrop(
    pasteboard: NSPasteboard
) -> Bool {
    guard isReadingModeActive == false else {
        return false
    }

    guard let transferRequest = macOSCanvasImportAdapter.transferRequest(
        from: pasteboard,
        sourceDescription: "drag and drop"
    ) else {
        return false
    }

    let didImport = performTransferRequest(transferRequest)
    return didImport
}

private func performTransferRequest(
    _ request: CanvasTransferRequest
) -> Bool {
    guard isReadingModeActive == false else {
        return false
    }

    guard let command = CanvasTransferCommandLowerer.loweredCommand(
        for: request
    ) else {
        return false
    }

    performCommand(command)
    return true
}

private var isReadingModeActive: Bool {
    editorSession.isReadingModeActive
}

private func beginTextEditIfPossible(for itemID: CanvasItemID) -> Bool {
    guard isReadingModeActive == false else {
        return false
    }

    guard scene.textItem(withID: itemID) != nil else {
        return false
    }

    performCommand(.beginTextEdit(itemID: itemID))
    return isInlineTextModeActive
}
```

### 结果

- macOS 侧阅读模式下不会再弹副键菜单，也不会再接受 open panel 导入、拖放导入、粘贴或再次进入文字编辑。
- 双端平台控制器在“输入链门控”层面保持了对称结构：共享 resolver 先降级，平台入口再兜底。

## 校验结果

- `ReadLints` 已检查：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- `ReadLints` 结果：无报错。
- 已执行 `xcrun --sdk macosx swiftc -frontend -parse`，静态解析通过：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasContextResolver.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 本次未执行完整 iOS 本地编译；当前环境仍按 IDE lint 结果做静态确认。

## 本阶段结论

- Phase 5 之后，“阅读模式只允许导航”的约束不再只依赖 UI 隐藏或命令层门控，而是形成了完整链路：
  - `CanvasWorkspaceMode`
  - `CanvasEditorSession.isReadingModeActive`
  - `CanvasContextResolver` 命中降级
  - `iOSViewController` / `macOSViewController` 系统输入早退
- 这样即使真实编辑状态仍被保留在内存里，阅读模式下也只会呈现和接受导航相关输入，不会继续进入任何编辑型路径。
