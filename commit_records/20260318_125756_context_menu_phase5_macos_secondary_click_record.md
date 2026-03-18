# 20260318_125756_context_menu_phase5_macos_secondary_click_record

## 记录范围

- 记录内容：
  1. 新增共享 `CanvasContextMenuCommandResolver`，把“上下文 -> 菜单命令列表”和“菜单命令 -> CanvasCommand”从平台层收敛到共享层。
  2. 在 `macOSCanvasViewportView` 增加 secondary click 输入桥，把右键位置送到 `macOSViewController`。
  3. 在 `macOSViewController` 打通 `secondary click -> resolveContext -> presentContextMenu -> execute command` 主链路。
  4. 在 `CanvasContextMenuHostView` 的 `macOS` 分支补齐 `rightMouseDown`，保证菜单打开后再次右键也能正确关闭。
  5. 在 `iOSViewController` 同步切到共享 `CanvasContextMenuCommandResolver`，为后续阶段 6 复用同一套菜单命令策略做准备。
- 涉及文件：
  - `MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift`
  - `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuHostView.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- 本记录不包含：
  - `iOS` 长按菜单桥接
  - `selection handle / rotate handle / crop outline / crop handle` 的上下文菜单
  - `delete / duplicate / z-order` 命令扩展
  - 原始 gif diff

## 修改一：新增共享菜单命令解析器，固化右键 selection 策略

### 修改前

- 平台层需要自己决定 `commandIDs`，也需要自己把 `CanvasCommandID` 映射成 `CanvasCommand`。
- “右键命中未选中 item 是否自动改选中”这件事还没有被收敛成共享策略。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: presentContextMenu(for:commandIDs:) / contextMenuCommand(for:in:)
// 功能说明: 修改前菜单展示依赖平台层传入 commandIDs，命令映射也留在 controller 私有方法里。
private func presentContextMenu(
    for resolvedContext: CanvasContextMenuContext,
    commandIDs: [CanvasCommandID]
) {
    let commandStates = frozenContextMenuCommandStates(
        for: commandIDs
    )
    guard commandStates.isEmpty == false else {
        dismissContextMenu()
        return
    }

    contextMenuState = CanvasContextMenuState(
        resolvedContext: resolvedContext,
        commandStates: commandStates
    )
}

private func contextMenuCommand(
    for commandID: CanvasCommandID,
    in state: CanvasContextMenuState
) -> CanvasCommand? {
    switch commandID {
    case .crop:
        return .crop
    case .undo:
        return .undo
    case .redo:
        return .redo
    case .selectItem:
        guard let itemID = state.resolvedContext.targetItemID else {
            return nil
        }
        return .selectItem(
            itemID: itemID,
            recordHistory: true
        )
    case .clearSelection:
        return .clearSelection(recordHistory: true)
    }
}
```

### 修改后

- 新增 `CanvasContextMenuCommandResolver`。
- 第一批上下文策略被收口为共享规则：
  - `blank` -> `clearSelection / undo / redo`
  - `selectedItemBody` -> `crop / clearSelection / undo / redo`
  - `unselectedItemBody` -> `selectItem / undo / redo`
- 对 `unselectedItemBody` 明确采用“先不自动改选中”的策略，只在用户真的点了 `Select` 之后才改 selection 和 history。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift
// 函数名/类型名: CanvasContextMenuCommandResolver.commandIDs(for:session:) / command(for:context:) / canPresent(_:for:session:)
// 功能说明: 修改后新增共享菜单命令解析器，统一决定不同上下文显示哪些菜单项，并收敛命令映射。
import Foundation

struct CanvasContextMenuCommandResolver {
    private let commandCatalog = CanvasCommandCatalog()

    func commandIDs(
        for context: CanvasContextMenuContext,
        session: CanvasEditorSession
    ) -> [CanvasCommandID] {
        let candidateIDs: [CanvasCommandID]

        switch context.targetKind {
        case .blank:
            candidateIDs = [
                .clearSelection,
                .undo,
                .redo
            ]
        case .selectedItemBody:
            candidateIDs = [
                .crop,
                .clearSelection,
                .undo,
                .redo
            ]
        case .unselectedItemBody:
            // 保持 invocation target 和当前 selection 解耦，避免仅因右键弹菜单就污染 history。
            candidateIDs = [
                .selectItem,
                .undo,
                .redo
            ]
        case .rotateHandle, .cropHandle, .cropOutline, .selectionHandle:
            return []
        }

        return candidateIDs.filter { commandID in
            canPresent(
                commandID,
                for: context,
                session: session
            )
        }
    }

    func command(
        for commandID: CanvasCommandID,
        context: CanvasContextMenuContext
    ) -> CanvasCommand? {
        switch commandID {
        case .crop:
            return .crop
        case .undo:
            return .undo
        case .redo:
            return .redo
        case .selectItem:
            guard let itemID = context.targetItemID else {
                return nil
            }

            return .selectItem(
                itemID: itemID,
                recordHistory: true
            )
        case .clearSelection:
            return .clearSelection(recordHistory: true)
        }
    }

    private func canPresent(
        _ commandID: CanvasCommandID,
        for context: CanvasContextMenuContext,
        session: CanvasEditorSession
    ) -> Bool {
        switch commandID {
        case .selectItem:
            guard
                let itemID = context.targetItemID,
                session.canSelectItem(withID: itemID)
            else {
                return false
            }
        case .clearSelection:
            guard context.selectedItemID != nil else {
                return false
            }
        case .crop, .undo, .redo:
            break
        }

        return commandCatalog.descriptor(
            for: commandID,
            session: session
        ).isEnabled
    }
}
```

## 修改二：`macOSCanvasViewportView` 增加 secondary click 输入桥

### 修改前

- `ViewportView` 只向外暴露 primary pointer、pan、zoom。
- `macOS` 右键坐标没有桥到平台 controller。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名/类型名: onPointerDown / onPointerMove / onPointerUp / onPointerCancel / mouseUp(with:)
// 功能说明: 修改前 viewport 只上报主键输入，没有 secondary click 回调。
var onPointerDown: ((CGPoint) -> Void)?
var onPointerMove: ((CGPoint, CGPoint) -> Void)?
var onPointerUp: ((CGPoint) -> Void)?
var onPointerCancel: (() -> Void)?
var onPan: ((CGPoint) -> Void)?
var onZoom: ((CGFloat, CGPoint) -> Void)?

override func mouseUp(with event: NSEvent) {
    let location = convert(event.locationInWindow, from: nil)
    lastPrimaryPointerLocation = nil
    onPointerUp?(location)
}
```

### 修改后

- 新增 `onSecondaryClick`。
- 新增 `rightMouseDown(with:)`，把右键点的 viewport 坐标原样抛出给 controller。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名/类型名: onSecondaryClick / rightMouseDown(with:)
// 功能说明: 修改后 viewport 新增 secondary click 桥接，把右键坐标送给平台层做 context resolve。
var onPointerDown: ((CGPoint) -> Void)?
var onPointerMove: ((CGPoint, CGPoint) -> Void)?
var onPointerUp: ((CGPoint) -> Void)?
var onPointerCancel: (() -> Void)?
var onSecondaryClick: ((CGPoint) -> Void)?
var onPan: ((CGPoint) -> Void)?
var onZoom: ((CGFloat, CGPoint) -> Void)?

override func rightMouseDown(with event: NSEvent) {
    window?.makeFirstResponder(self)
    let location = convert(event.locationInWindow, from: nil)
    onSecondaryClick?(location)
}
```

## 修改三：`macOSViewController` 打通右键菜单主链路

### 修改前

- `setupCanvasViewport()` 还没有 secondary click 绑定。
- `handlePrimaryPointerDown(at:)` 会直接进入 `pressed`，不会先收起已经打开的菜单。
- 没有 `handleSecondaryClick(at:)` 和 `prepareForSecondaryClickContextMenu()`。
- 菜单打开期间，滚轮平移和缩放没有先 dismiss 菜单。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: setupCanvasViewport() / handlePrimaryPointerDown(at:) / handleIndirectPan(_:) / handleZoom(_:around:)
// 功能说明: 修改前 controller 还没有 secondary click 主链路，菜单与现有 pointer/pan/zoom 也没有协作边界。
private func setupCanvasViewport() {
    canvasViewportView.onPointerDown = { [weak self] location in
        self?.handlePrimaryPointerDown(at: location)
    }
    canvasViewportView.onPointerMove = { [weak self] location, previousLocation in
        self?.handlePrimaryPointerMove(to: location, from: previousLocation)
    }
    canvasViewportView.onPointerUp = { [weak self] location in
        self?.handlePrimaryPointerUp(at: location)
    }
    canvasViewportView.onPointerCancel = { [weak self] in
        self?.handlePrimaryPointerCancel()
    }
    canvasViewportView.onPan = { [weak self] translation in
        self?.handleIndirectPan(translation)
    }
    canvasViewportView.onZoom = { [weak self] scaleDelta, anchor in
        self?.handleZoom(scaleDelta, around: anchor)
    }

    installCanvasContentView(canvasViewportView)
    refreshCanvas()
}

private func handlePrimaryPointerDown(at location: CGPoint) {
    let pressContext = resolveContext(at: location)
    pointerDragState = .pressed(
        pressedLocation: location,
        pressContext: pressContext
    )
    beginPointerHistoryTransactionIfNeeded(for: pressContext)
}

private func handleIndirectPan(_ translation: CGPoint) {
    camera.pan(by: translation)
    refreshCanvas()
    scheduleAutosave(reason: "pan canvas")
}

private func handleZoom(_ scaleDelta: CGFloat, around anchor: CGPoint) {
    camera.zoom(by: scaleDelta, around: anchor)
    refreshCanvas()
    scheduleAutosave(reason: "zoom canvas")
}
```

### 修改后

- `setupCanvasViewport()` 把 `onSecondaryClick` 绑定到 `handleSecondaryClick(at:)`。
- `handleSecondaryClick(at:)` 先同步 viewport size，再统一调用 `prepareForSecondaryClickContextMenu()` 收掉当前交互，然后用 `resolveContext(at:)` 解析位置语义并展示菜单。
- `prepareForSecondaryClickContextMenu()` 复用现有 `handlePrimaryPointerCancel()` 语义，避免右键过程中留下半提交的 drag/crop/rotate 状态。
- `handlePrimaryPointerDown(at:)`、`handleIndirectPan(_:)`、`handleZoom(_:around:)` 都先对打开中的菜单做 dismiss，避免菜单显示期和原有交互状态机互相打断。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: setupCanvasViewport() / handlePrimaryPointerDown(at:) / handleSecondaryClick(at:) / prepareForSecondaryClickContextMenu()
// 功能说明: 修改后 controller 打通 secondary click -> resolveContext -> presentContextMenu 主链路，并先收敛当前交互状态。
private func setupCanvasViewport() {
    canvasViewportView.onPointerDown = { [weak self] location in
        self?.handlePrimaryPointerDown(at: location)
    }
    canvasViewportView.onPointerMove = { [weak self] location, previousLocation in
        self?.handlePrimaryPointerMove(to: location, from: previousLocation)
    }
    canvasViewportView.onPointerUp = { [weak self] location in
        self?.handlePrimaryPointerUp(at: location)
    }
    canvasViewportView.onPointerCancel = { [weak self] in
        self?.handlePrimaryPointerCancel()
    }
    canvasViewportView.onSecondaryClick = { [weak self] location in
        self?.handleSecondaryClick(at: location)
    }
    canvasViewportView.onPan = { [weak self] translation in
        self?.handleIndirectPan(translation)
    }
    canvasViewportView.onZoom = { [weak self] scaleDelta, anchor in
        self?.handleZoom(scaleDelta, around: anchor)
    }

    installCanvasContentView(canvasViewportView)
    refreshCanvas()
}

private func handlePrimaryPointerDown(at location: CGPoint) {
    if contextMenuState != nil {
        dismissContextMenu()
        return
    }

    let pressContext = resolveContext(at: location)
    pointerDragState = .pressed(
        pressedLocation: location,
        pressContext: pressContext
    )
    beginPointerHistoryTransactionIfNeeded(for: pressContext)
}

private func handleSecondaryClick(at location: CGPoint) {
    updateCameraViewportSizeIfNeeded()
    prepareForSecondaryClickContextMenu()

    let resolvedContext = resolveContext(at: location)
    presentContextMenu(for: resolvedContext)
}

private func prepareForSecondaryClickContextMenu() {
    dismissContextMenu()

    switch pointerDragState {
    case .idle:
        break
    case .pressed,
         .croppingSelectedItem,
         .movingCropFrame,
         .rotatingSelectedItem,
         .draggingSelectedItem,
         .resizingSelectedItem,
         .draggingCanvas:
        // 复用 primary cancel 语义，避免 secondary click 留下半提交的交互态。
        handlePrimaryPointerCancel()
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: handleIndirectPan(_:) / handleZoom(_:around:)
// 功能说明: 修改后菜单显示期间不继续让滚轮平移和缩放直接作用到画布，而是先关闭菜单。
private func handleIndirectPan(_ translation: CGPoint) {
    if contextMenuState != nil {
        dismissContextMenu()
        return
    }

    camera.pan(by: translation)
    refreshCanvas()
    scheduleAutosave(reason: "pan canvas")
}

private func handleZoom(_ scaleDelta: CGFloat, around anchor: CGPoint) {
    if contextMenuState != nil {
        dismissContextMenu()
        return
    }

    camera.zoom(by: scaleDelta, around: anchor)
    refreshCanvas()
    scheduleAutosave(reason: "zoom canvas")
}
```

## 修改四：`macOSViewController` 改为消费共享菜单命令解析器

### 修改前

- `performCommand(_:)` 不会先关掉菜单。
- `presentContextMenu(...)` 仍由调用方传 `commandIDs`。
- `performContextMenuCommand(_:)` 还依赖 controller 自己的 `contextMenuCommand(...)` 私有映射。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: performCommand(_:) / presentContextMenu(for:commandIDs:) / performContextMenuCommand(_:)
// 功能说明: 修改前 macOS controller 还没有完全切到共享命令解析器，菜单执行前也不会统一 dismiss。
private func performCommand(_ command: CanvasCommand) {
    guard commandExecutor.canExecute(command) else {
        return
    }

    if command.shouldCancelActiveRotation {
        cancelRotationInteractionIfNeeded(
            resetPointerDragState: command.shouldResetPointerDragStateWhenCancellingRotation
        )
    }

    guard let executionResult = commandExecutor.execute(command) else {
        return
    }

    updateInlineEditButtonsAppearance()

    if executionResult.refreshReason != nil {
        refreshCanvas()
    }
}

private func presentContextMenu(
    for resolvedContext: CanvasContextMenuContext,
    commandIDs: [CanvasCommandID]
) {
    let commandStates = frozenContextMenuCommandStates(
        for: commandIDs
    )
    guard commandStates.isEmpty == false else {
        dismissContextMenu()
        return
    }

    contextMenuState = CanvasContextMenuState(
        resolvedContext: resolvedContext,
        commandStates: commandStates
    )
}
```

### 修改后

- 增加 `contextMenuCommandResolver` 成员。
- `performCommand(_:)` 统一先 `dismissContextMenu()`。
- `presentContextMenu(for:)` 改为内部向共享 resolver 取命令列表。
- `performContextMenuCommand(_:)` 改为向共享 resolver 取真正执行的 `CanvasCommand`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: contextMenuCommandResolver / performCommand(_:) / presentContextMenu(for:) / performContextMenuCommand(_:)
// 功能说明: 修改后 macOS controller 只负责调用共享 resolver，不再自己维护菜单命令列表和命令映射。
private let commandCatalog = CanvasCommandCatalog()
private let contextMenuCommandResolver = CanvasContextMenuCommandResolver()

private func performCommand(_ command: CanvasCommand) {
    guard commandExecutor.canExecute(command) else {
        return
    }

    dismissContextMenu()

    if command.shouldCancelActiveRotation {
        cancelRotationInteractionIfNeeded(
            resetPointerDragState: command.shouldResetPointerDragStateWhenCancellingRotation
        )
    }

    guard let executionResult = commandExecutor.execute(command) else {
        return
    }

    updateInlineEditButtonsAppearance()

    if executionResult.refreshReason != nil {
        refreshCanvas()
    }
}

private func presentContextMenu(
    for resolvedContext: CanvasContextMenuContext
) {
    let commandIDs = contextMenuCommandResolver.commandIDs(
        for: resolvedContext,
        session: editorSession
    )
    let commandStates = frozenContextMenuCommandStates(
        for: commandIDs
    )
    guard commandStates.isEmpty == false else {
        dismissContextMenu()
        return
    }

    contextMenuState = CanvasContextMenuState(
        resolvedContext: resolvedContext,
        commandStates: commandStates
    )
}

private func performContextMenuCommand(_ commandID: CanvasCommandID) {
    guard
        let contextMenuState,
        let command = contextMenuCommandResolver.command(
            for: commandID,
            context: contextMenuState.resolvedContext
        )
    else {
        dismissContextMenu()
        return
    }

    dismissContextMenu()
    performCommand(command)
}
```

## 修改五：菜单宿主支持右键外部关闭

### 修改前

- `macOS` 菜单宿主只处理 `mouseDown(with:)`。
- 菜单打开后再次右键外部区域，宿主没有对称的 dismiss 入口。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuHostView.swift
// 函数名/类型名: CanvasContextMenuHostView.mouseDown(with:)
// 功能说明: 修改前 macOS 菜单宿主只在主键点击外部时关闭菜单。
override func mouseDown(with event: NSEvent) {
    guard currentState != nil else {
        super.mouseDown(with: event)
        return
    }

    let location = convert(event.locationInWindow, from: nil)
    if menuContainerView.frame.contains(location) == false {
        onDismissRequested?()
    }
}
```

### 修改后

- 新增 `rightMouseDown(with:)`。
- 菜单打开后再次右键外部区域，也能走相同的 dismiss 逻辑。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuHostView.swift
// 函数名/类型名: CanvasContextMenuHostView.rightMouseDown(with:)
// 功能说明: 修改后 macOS 菜单宿主补齐 secondary click 外部关闭逻辑，保持菜单生命周期一致。
override func rightMouseDown(with event: NSEvent) {
    guard currentState != nil else {
        super.rightMouseDown(with: event)
        return
    }

    let location = convert(event.locationInWindow, from: nil)
    if menuContainerView.frame.contains(location) == false {
        onDismissRequested?()
    }
}
```

## 修改六：`iOSViewController` 同步切到共享菜单命令解析器

### 修改前

- `iOS` 也和 `macOS` 一样，平台层自己维护 `contextMenuCommand(...)` 私有映射。
- `performCommand(_:)` 不会在命令执行前统一关闭菜单。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: performCommand(_:) / presentContextMenu(for:commandIDs:) / contextMenuCommand(for:in:)
// 功能说明: 修改前 iOS controller 仍由平台层自己维护菜单命令列表和命令映射。
private let commandCatalog = CanvasCommandCatalog()

private func performCommand(_ command: CanvasCommand) {
    guard commandExecutor.canExecute(command) else {
        return
    }

    if command.shouldCancelActiveRotation {
        cancelRotationInteractionIfNeeded(
            resetPointerDragState: command.shouldResetPointerDragStateWhenCancellingRotation
        )
    }

    guard let executionResult = commandExecutor.execute(command) else {
        return
    }

    updateInlineEditButtonsAppearance()

    if let refreshReason = executionResult.refreshReason {
        requestCanvasRefresh(reason: refreshReason)
    }
}

private func presentContextMenu(
    for resolvedContext: CanvasContextMenuContext,
    commandIDs: [CanvasCommandID]
) {
    let commandStates = frozenContextMenuCommandStates(
        for: commandIDs
    )
    guard commandStates.isEmpty == false else {
        dismissContextMenu()
        return
    }

    contextMenuState = CanvasContextMenuState(
        resolvedContext: resolvedContext,
        commandStates: commandStates
    )
}
```

### 修改后

- `iOS` 同步增加 `contextMenuCommandResolver`。
- `performCommand(_:)` 统一先 `dismissContextMenu()`。
- `presentContextMenu(for:)` 和 `performContextMenuCommand(_:)` 改为直接消费共享 resolver，为阶段 6 复用同一套菜单策略铺路。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: contextMenuCommandResolver / performCommand(_:) / presentContextMenu(for:) / performContextMenuCommand(_:)
// 功能说明: 修改后 iOS controller 与 macOS 对齐，菜单命令策略收敛到共享 resolver。
private let commandCatalog = CanvasCommandCatalog()
private let contextMenuCommandResolver = CanvasContextMenuCommandResolver()

private func performCommand(_ command: CanvasCommand) {
    guard commandExecutor.canExecute(command) else {
        return
    }

    dismissContextMenu()

    if command.shouldCancelActiveRotation {
        cancelRotationInteractionIfNeeded(
            resetPointerDragState: command.shouldResetPointerDragStateWhenCancellingRotation
        )
    }

    guard let executionResult = commandExecutor.execute(command) else {
        return
    }

    updateInlineEditButtonsAppearance()

    if let refreshReason = executionResult.refreshReason {
        requestCanvasRefresh(reason: refreshReason)
    }
}

private func presentContextMenu(
    for resolvedContext: CanvasContextMenuContext
) {
    let commandIDs = contextMenuCommandResolver.commandIDs(
        for: resolvedContext,
        session: editorSession
    )
    let commandStates = frozenContextMenuCommandStates(
        for: commandIDs
    )
    guard commandStates.isEmpty == false else {
        dismissContextMenu()
        return
    }

    contextMenuState = CanvasContextMenuState(
        resolvedContext: resolvedContext,
        commandStates: commandStates
    )
}

private func performContextMenuCommand(_ commandID: CanvasCommandID) {
    guard
        let contextMenuState,
        let command = contextMenuCommandResolver.command(
            for: commandID,
            context: contextMenuState.resolvedContext
        )
    else {
        dismissContextMenu()
        return
    }

    dismissContextMenu()
    performCommand(command)
}
```

## 验证结果

- 已通过 `date +"%Y%m%d_%H%M%S"` 获取本记录时间戳：`20260318_125756`
- 已通过 `ReadLints` 检查本次改动文件，无新增 lint 问题
- 已通过 `xcodebuild` 构建验证：
  - `macOS`: `generic/platform=macOS`
  - `iOS`: `generic/platform=iOS`

## 当前阶段结论

- 阶段 5 已经把 `macOS` 右键菜单主链路打通：`secondary click -> resolveContext -> presentContextMenu -> execute command`
- 已明确落地 selection 策略：右键命中未选中 item 时，不自动改 selection，只在用户点击 `Select` 命令时才记录 selection/history 变化
- 第一批动态菜单上下文已落地：
  - 空白区域
  - 已选中 item body
  - 未选中 item body
- 第二批上下文仍待后续阶段处理：
  - `selection handle`
  - `rotate handle`
  - `crop outline / crop handle`
