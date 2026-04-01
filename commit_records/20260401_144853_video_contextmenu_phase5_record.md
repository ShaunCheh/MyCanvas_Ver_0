# 20260401_144853_video_contextmenu_phase5_record

## 记录范围

- 记录内容：把 Canvas 上下文菜单从只承载 `CanvasCommandID` 的 command-only 模型，扩成“文档命令 + UI action”双通道。
- 记录内容：仅对视频 item 增加 `Set Display Frame` 菜单入口，图片 / 文本原有菜单语义保持不变。
- 记录内容：接入 iOS / macOS 控制器，让视频菜单项分别打开全屏页 / sheet，而不是错误地下沉到 `CanvasCommandExecutor`。
- 记录内容：新增两个平台原生编辑页壳子，作为后续阶段 6 / 7 / 8 的承接点。
- 涉及文件：`MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuState.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuHostView.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/iOS/iOSVideoDisplayFrameEditorViewController.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/macOS/macOSVideoDisplayFrameEditorViewController.swift`
- 本记录不包含：阶段 6 的共享 `AVFoundation` 帧提取与 poster 落盘服务。
- 本记录不包含：阶段 7 / 8 的完整视频展示画面编辑 UI、播放进度条、帧条与回写逻辑。
- 本记录不包含：git commit / push。

## 修改一：上下文菜单状态模型从 command-only 扩成 action model

### 修改前

- `CanvasContextMenuState` 只保存 `commandStates`。
- 每个菜单项只能表达一个 `CanvasCommandID`，无法表达“打开 UI 页面”这种非文档命令行为。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuState.swift
// 类型/函数: CanvasContextMenuCommandState / CanvasContextMenuState
// 功能说明: 修改前上下文菜单状态只承载 CanvasCommandID，菜单点击天然只能走命令执行链。
struct CanvasContextMenuCommandState {
    let commandID: CanvasCommandID
    let descriptor: CanvasCommandDescriptor
}

struct CanvasContextMenuState {
    let resolvedContext: CanvasContextMenuContext
    let layoutAnchorPoint: CGPoint
    let commandStates: [CanvasContextMenuCommandState]

    var isEmpty: Bool {
        commandStates.isEmpty
    }
}
```

### 修改后

- 新增 `CanvasContextMenuActionDescriptor`、`CanvasContextMenuUIActionID`、`CanvasContextMenuActionID`、`CanvasContextMenuActionState`。
- `CanvasContextMenuState` 改为保存 `actionStates`，从状态层就能同时表达 command 和 UI action。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuState.swift
// 类型/函数: CanvasContextMenuActionDescriptor / CanvasContextMenuActionID / CanvasContextMenuState
// 功能说明: 修改后上下文菜单状态可同时承载文档命令和 UI action，为视频“设置展示画面”提供独立通道。
struct CanvasContextMenuActionDescriptor {
    let title: String
    let systemImageName: String
    let isEnabled: Bool
    let isActive: Bool

    init(commandDescriptor: CanvasCommandDescriptor) {
        self.init(
            title: commandDescriptor.title,
            systemImageName: commandDescriptor.systemImageName,
            isEnabled: commandDescriptor.isEnabled,
            isActive: commandDescriptor.isActive
        )
    }
}

enum CanvasContextMenuUIActionID: String {
    case editVideoDisplayFrame

    var rawValueDescription: String {
        rawValue
    }
}

enum CanvasContextMenuActionID {
    case command(CanvasCommandID)
    case uiAction(CanvasContextMenuUIActionID)

    var rawValueDescription: String {
        switch self {
        case let .command(commandID):
            return commandID.rawValue
        case let .uiAction(uiActionID):
            return uiActionID.rawValueDescription
        }
    }
}

struct CanvasContextMenuActionState {
    let actionID: CanvasContextMenuActionID
    let descriptor: CanvasContextMenuActionDescriptor
}

struct CanvasContextMenuState {
    let resolvedContext: CanvasContextMenuContext
    let layoutAnchorPoint: CGPoint
    let actionStates: [CanvasContextMenuActionState]

    var isEmpty: Bool {
        actionStates.isEmpty
    }
}
```

## 修改二：Resolver 从“产出命令 ID”改成“产出 action state”，并仅对视频暴露 UI action

### 修改前

- `CanvasContextMenuCommandResolver` 只会返回启用后的 `CanvasCommandID`。
- `selectedItemCommandIDs(...)` / `unselectedItemCommandIDs(...)` 里没有任何 UI action 概念。
- 这意味着菜单层无法加入“打开视频编辑页”这种非命令行为。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift
// 类型/函数: CanvasContextMenuCommandResolver.commandIDs(for:session:) / candidateCommandIDs(for:session:)
// 功能说明: 修改前 resolver 只解析 CanvasCommandID，最终返回值也只有文档命令集合。
struct CanvasContextMenuCommandResolver {
    private let commandCatalog = CanvasCommandCatalog()

    func commandIDs(
        for context: CanvasContextMenuContext,
        session: CanvasEditorSession
    ) -> [CanvasCommandID] {
        let candidateIDs = candidateCommandIDs(
            for: context,
            session: session
        )

        let enabledIDs = candidateIDs.filter { commandID in
            commandCatalog.descriptor(
                for: commandID,
                session: session,
                context: context
            ).isEnabled
        }
        return enabledIDs
    }

    private func selectedItemCommandIDs(
        includeCropCommand: Bool,
        includeBeginTextEditCommand: Bool
    ) -> [CanvasCommandID] {
        var commandIDs: [CanvasCommandID] = []
        if includeCropCommand {
            commandIDs.append(.crop)
        }
        if includeBeginTextEditCommand {
            commandIDs.append(.beginTextEdit)
        }
        commandIDs.append(contentsOf: [
            .duplicateItem,
            .deleteItem,
            .bringItemForward,
            .sendItemBackward,
            .bringItemToFront,
            .sendItemToBack,
            .clearSelection,
            .undo,
            .redo
        ])
        return commandIDs
    }
}
```

### 修改后

- Resolver 结构体重命名为 `CanvasContextMenuActionResolver`。
- `actionStates(...)` 先构造候选 `CanvasContextMenuActionID`，再按 descriptor 做启用态过滤。
- 新增 `uiActionDescriptor(...)` 与 `targetVideoItemID(...)`，只有目标 item 为视频时才插入 `.uiAction(.editVideoDisplayFrame)`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift
// 类型/函数: CanvasContextMenuActionResolver.actionStates(for:session:) / candidateActionIDs(for:session:)
// 功能说明: 修改后 resolver 统一产出 action state，并仅在命中视频 item 时追加“设置展示画面”这一 UI action。
struct CanvasContextMenuActionResolver {
    private let commandCatalog = CanvasCommandCatalog()

    func actionStates(
        for context: CanvasContextMenuContext,
        session: CanvasEditorSession
    ) -> [CanvasContextMenuActionState] {
        let candidateActionIDs = candidateActionIDs(
            for: context,
            session: session
        )

        let actionStates = candidateActionIDs.map { actionID in
            CanvasContextMenuActionState(
                actionID: actionID,
                descriptor: descriptor(
                    for: actionID,
                    context: context,
                    session: session
                )
            )
        }
        return actionStates.filter(\.descriptor.isEnabled)
    }

    private func uiActionDescriptor(
        for uiActionID: CanvasContextMenuUIActionID,
        context: CanvasContextMenuContext,
        session: CanvasEditorSession
    ) -> CanvasContextMenuActionDescriptor {
        switch uiActionID {
        case .editVideoDisplayFrame:
            return CanvasContextMenuActionDescriptor(
                title: "Set Display Frame",
                systemImageName: "movieclapper",
                isEnabled: targetVideoItemID(
                    in: context,
                    session: session
                ) != nil,
                isActive: false
            )
        }
    }

    private func selectedItemActionIDs(
        includeCropCommand: Bool,
        includeBeginTextEditCommand: Bool,
        includeVideoDisplayFrameAction: Bool
    ) -> [CanvasContextMenuActionID] {
        var actionIDs: [CanvasContextMenuActionID] = []
        if includeCropCommand {
            actionIDs.append(.command(.crop))
        }
        if includeBeginTextEditCommand {
            actionIDs.append(.command(.beginTextEdit))
        }
        if includeVideoDisplayFrameAction {
            actionIDs.append(.uiAction(.editVideoDisplayFrame))
        }
        actionIDs.append(contentsOf: [
            .command(.duplicateItem),
            .command(.deleteItem),
            .command(.bringItemForward),
            .command(.sendItemBackward),
            .command(.bringItemToFront),
            .command(.sendItemToBack),
            .command(.clearSelection),
            .command(.undo),
            .command(.redo)
        ])
        return actionIDs
    }

    private func targetVideoItemID(
        in context: CanvasContextMenuContext,
        session: CanvasEditorSession
    ) -> CanvasItemID? {
        guard
            let itemID = context.targetItemID,
            let item = session.scene.item(withID: itemID),
            item.isVideo
        else {
            return nil
        }

        return itemID
    }
}
```

## 修改三：ContextMenu HostView 从回传命令 ID 改成回传 action ID

### 修改前

- `CanvasContextMenuHostView` 维护的是 `commandStackView` 和 `commandIDs`。
- 按钮点击只能回调 `onCommandSelected`。
- 布局日志也只输出 `commandIDs`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuHostView.swift
// 类型/函数: CanvasContextMenuHostView.onCommandSelected / rebuildCommandButtons(for:) / handleCommandButtonTap(_:)
// 功能说明: 修改前 HostView 只知道“按钮对应哪个 CanvasCommandID”，不知道 UI action。
final class CanvasContextMenuHostView: UIView {
    var onCommandSelected: ((CanvasCommandID) -> Void)?
    private let commandStackView = UIStackView()
    private var commandIDs: [CanvasCommandID] = []

    private func rebuildCommandButtons(for state: CanvasContextMenuState) {
        commandIDs = []
        commandStackView.arrangedSubviews.forEach { arrangedSubview in
            commandStackView.removeArrangedSubview(arrangedSubview)
            arrangedSubview.removeFromSuperview()
        }

        for commandState in state.commandStates {
            let button = makeCommandButton(for: commandState)
            button.tag = commandIDs.count
            commandIDs.append(commandState.commandID)
            commandStackView.addArrangedSubview(button)
        }
    }

    @objc
    private func handleCommandButtonTap(_ sender: UIButton) {
        let index = sender.tag
        guard commandIDs.indices.contains(index) else {
            return
        }

        onCommandSelected?(commandIDs[index])
    }
}
```

### 修改后

- `commandStackView` / `commandIDs` 全部替换为 `actionStackView` / `actionIDs`。
- iOS / macOS 两个平台分支都改成回调 `onActionSelected`。
- 布局日志同步改为输出 `actionIDs`，避免日志语义滞后。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuHostView.swift
// 类型/函数: CanvasContextMenuHostView.onActionSelected / rebuildActionButtons(for:) / handleActionButtonTap(_:)
// 功能说明: 修改后 HostView 只负责把 action state 渲染成按钮，并把点击结果按 CanvasContextMenuActionID 回传给控制器。
final class CanvasContextMenuHostView: UIView {
    var onActionSelected: ((CanvasContextMenuActionID) -> Void)?
    private let actionStackView = UIStackView()
    private var actionIDs: [CanvasContextMenuActionID] = []

    private func rebuildActionButtons(for state: CanvasContextMenuState) {
        actionIDs = []
        actionStackView.arrangedSubviews.forEach { arrangedSubview in
            actionStackView.removeArrangedSubview(arrangedSubview)
            arrangedSubview.removeFromSuperview()
        }

        for actionState in state.actionStates {
            let button = makeActionButton(for: actionState)
            button.tag = actionIDs.count
            actionIDs.append(actionState.actionID)
            actionStackView.addArrangedSubview(button)
        }
    }

    @objc
    private func handleActionButtonTap(_ sender: UIButton) {
        let index = sender.tag
        guard actionIDs.indices.contains(index) else {
            return
        }

        onActionSelected?(actionIDs[index])
    }
}

// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuHostView.swift
// 类型/函数: logContextMenuLayout(platform:state:hostBounds:safeBounds:occupiedRects:preferredSize:resolvedMenuFrame:)
// 功能说明: 修改后日志链路也按 actionIDs 输出，便于区分 command 与 UI action。
private func logContextMenuLayout(
    platform: String,
    state: CanvasContextMenuState,
    hostBounds: CGRect,
    safeBounds: CGRect,
    occupiedRects: [CGRect],
    preferredSize: CGSize,
    resolvedMenuFrame: CGRect?
) {
    let actionIDsDescription = state.actionStates
        .map(\.actionID.rawValueDescription)
        .joined(separator: ",")

    print(
        "[Canvas \(platform)][ContextMenuLayout] " +
        "actionIDs=[\(actionIDsDescription)]"
    )
}
```

## 修改四：iOS 控制器改为消费 action，并把视频菜单项路由到全屏编辑页

### 修改前

- `iOSViewController` 持有的是 `CanvasContextMenuCommandResolver`。
- `presentContextMenu(...)` 会先要 `commandIDs`，再构造 `commandStates`。
- 点击菜单时直接走 `performContextMenuCommand(...)`，没有 UI action 分流，也没有视频编辑页入口。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 类型/函数: presentContextMenu(for:) / performContextMenuCommand(_:) / setupContextMenuHostView()
// 功能说明: 修改前 iOS 端菜单选择会直接转成 CanvasCommand 执行，无法表达“打开视频展示画面编辑页”。
private let contextMenuCommandResolver = CanvasContextMenuCommandResolver()

private func presentContextMenu(
    for resolvedContext: CanvasContextMenuContext
) {
    let commandIDs = contextMenuCommandResolver.commandIDs(
        for: resolvedContext,
        session: editorSession
    )
    let commandStates = frozenContextMenuCommandStates(
        for: commandIDs,
        context: resolvedContext
    )
    guard commandStates.isEmpty == false else {
        dismissContextMenu()
        return
    }

    contextMenuState = CanvasContextMenuState(
        resolvedContext: resolvedContext,
        layoutAnchorPoint: contextMenuLayoutAnchorPoint(for: resolvedContext),
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

private func setupContextMenuHostView() {
    contextMenuHostView.onDismissRequested = { [weak self] in
        self?.dismissContextMenu()
    }
    contextMenuHostView.onCommandSelected = { [weak self] commandID in
        self?.performContextMenuCommand(commandID)
    }
}
```

### 修改后

- `presentContextMenu(...)` 直接拿 `actionStates`，不再生成临时 `frozenContextMenuCommandStates(...)`。
- 新增 `performContextMenuAction(...)`、`performContextMenuUIAction(...)`、`targetVideoItemID(...)`、`presentVideoDisplayFrameEditor(for:)`。
- 视频菜单项点击后会打开 `iOSVideoDisplayFrameEditorViewController`，并使用 `.fullScreen` 呈现。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 类型/函数: presentContextMenu(for:) / performContextMenuAction(_:) / presentVideoDisplayFrameEditor(for:)
// 功能说明: 修改后 iOS 端先消费统一 action，再把 command 继续下发给执行器，把视频 UI action 路由到全屏编辑页。
private let contextMenuActionResolver = CanvasContextMenuActionResolver()

private func presentContextMenu(
    for resolvedContext: CanvasContextMenuContext
) {
    let actionStates = contextMenuActionResolver.actionStates(
        for: resolvedContext,
        session: editorSession
    )
    guard actionStates.isEmpty == false else {
        dismissContextMenu()
        return
    }

    contextMenuState = CanvasContextMenuState(
        resolvedContext: resolvedContext,
        layoutAnchorPoint: contextMenuLayoutAnchorPoint(for: resolvedContext),
        actionStates: actionStates
    )
}

private func performContextMenuAction(_ actionID: CanvasContextMenuActionID) {
    guard let contextMenuState else {
        dismissContextMenu()
        return
    }

    switch actionID {
    case let .command(commandID):
        guard let command = contextMenuActionResolver.command(
            for: commandID,
            context: contextMenuState.resolvedContext
        ) else {
            dismissContextMenu()
            return
        }

        dismissContextMenu()
        performCommand(command)
    case let .uiAction(uiActionID):
        dismissContextMenu()
        performContextMenuUIAction(
            uiActionID,
            context: contextMenuState.resolvedContext
        )
    }
}

private func performContextMenuUIAction(
    _ actionID: CanvasContextMenuUIActionID,
    context: CanvasContextMenuContext
) {
    switch actionID {
    case .editVideoDisplayFrame:
        guard let itemID = targetVideoItemID(for: context) else {
            return
        }

        presentVideoDisplayFrameEditor(for: itemID)
    }
}

private func presentVideoDisplayFrameEditor(for itemID: CanvasItemID) {
    guard presentedViewController == nil else {
        return
    }

    let editorViewController = iOSVideoDisplayFrameEditorViewController(
        itemID: itemID
    )
    editorViewController.modalPresentationStyle = .fullScreen
    present(editorViewController, animated: true)
}

private func setupContextMenuHostView() {
    contextMenuHostView.onDismissRequested = { [weak self] in
        self?.dismissContextMenu()
    }
    contextMenuHostView.onActionSelected = { [weak self] actionID in
        self?.performContextMenuAction(actionID)
    }
}
```

## 修改五：macOS 控制器改为消费 action，并把视频菜单项路由到 sheet

### 修改前

- `macOSViewController` 与 iOS 一样，也是 command-only 链路。
- 菜单点击后只能进入 `performContextMenuCommand(...)`，没有视频 UI action 入口。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 类型/函数: presentContextMenu(for:) / performContextMenuCommand(_:) / setupContextMenuHostView()
// 功能说明: 修改前 macOS 端和 iOS 一样，只支持命令分发，不支持打开独立视频编辑 sheet。
private let contextMenuCommandResolver = CanvasContextMenuCommandResolver()

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

private func setupContextMenuHostView() {
    contextMenuHostView.onDismissRequested = { [weak self] in
        self?.dismissContextMenu()
    }
    contextMenuHostView.onCommandSelected = { [weak self] commandID in
        self?.performContextMenuCommand(commandID)
    }
}
```

### 修改后

- macOS 改成与 iOS 相同的 action 分发模式。
- 视频 UI action 最终会走到 `presentVideoDisplayFrameEditor(for:)`，并用 `presentAsSheet(...)` 打开 `macOSVideoDisplayFrameEditorViewController`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 类型/函数: performContextMenuAction(_:) / performContextMenuUIAction(_:context:) / presentVideoDisplayFrameEditor(for:)
// 功能说明: 修改后 macOS 端将视频 UI action 路由到 sheet，命令型菜单仍旧继续走 CanvasCommand 执行链。
private let contextMenuActionResolver = CanvasContextMenuActionResolver()

private func performContextMenuAction(_ actionID: CanvasContextMenuActionID) {
    guard let contextMenuState else {
        dismissContextMenu()
        return
    }

    switch actionID {
    case let .command(commandID):
        guard let command = contextMenuActionResolver.command(
            for: commandID,
            context: contextMenuState.resolvedContext
        ) else {
            dismissContextMenu()
            return
        }

        dismissContextMenu()
        performCommand(command)
    case let .uiAction(uiActionID):
        dismissContextMenu()
        performContextMenuUIAction(
            uiActionID,
            context: contextMenuState.resolvedContext
        )
    }
}

private func performContextMenuUIAction(
    _ actionID: CanvasContextMenuUIActionID,
    context: CanvasContextMenuContext
) {
    switch actionID {
    case .editVideoDisplayFrame:
        guard let itemID = targetVideoItemID(for: context) else {
            return
        }

        presentVideoDisplayFrameEditor(for: itemID)
    }
}

private func presentVideoDisplayFrameEditor(for itemID: CanvasItemID) {
    guard presentedViewControllers.isEmpty else {
        return
    }

    let editorViewController = macOSVideoDisplayFrameEditorViewController(
        itemID: itemID
    )
    presentAsSheet(editorViewController)
}

private func setupContextMenuHostView() {
    contextMenuHostView.onDismissRequested = { [weak self] in
        self?.dismissContextMenu()
    }
    contextMenuHostView.onActionSelected = { [weak self] actionID in
        self?.performContextMenuAction(actionID)
    }
}
```

## 修改六：新增 iOS / macOS 视频展示画面编辑页壳子

### 修改前

- 阶段 5 之前不存在这两个文件。
- 就算菜单层面增加了视频入口，也没有一个平台原生容器可供后续阶段继续填充 UI。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSVideoDisplayFrameEditorViewController.swift
// 类型/函数: 文件级新增
// 功能说明: 修改前无此文件，iOS 端没有视频展示画面编辑页壳子。
// 无
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSVideoDisplayFrameEditorViewController.swift
// 类型/函数: 文件级新增
// 功能说明: 修改前无此文件，macOS 端没有视频展示画面编辑 sheet 壳子。
// 无
```

### 修改后

- 新增 `iOSVideoDisplayFrameEditorViewController`，提供全屏页最小骨架。
- 新增 `macOSVideoDisplayFrameEditorViewController`，提供 sheet 最小骨架。
- 两个平台页面目前都只包含标题、item ID 提示和关闭按钮，明确把完整帧编辑 UI 留给后续阶段。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSVideoDisplayFrameEditorViewController.swift
// 类型/函数: iOSVideoDisplayFrameEditorViewController.viewDidLoad() / handleCloseButtonTap()
// 功能说明: 修改后 iOS 端已有可被上下文菜单打开的全屏视频编辑页壳子，后续可继续填入视频预览、进度条和帧条。
final class iOSVideoDisplayFrameEditorViewController: UIViewController {
    private let itemID: CanvasItemID

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        detailLabel.text =
            "Video item: \(itemID.uuidString)\n" +
            "The platform-specific frame controls will be added in the next phase."
        closeButton.addTarget(
            self,
            action: #selector(handleCloseButtonTap),
            for: .touchUpInside
        )
    }

    @objc
    private func handleCloseButtonTap() {
        dismiss(animated: true)
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSVideoDisplayFrameEditorViewController.swift
// 类型/函数: macOSVideoDisplayFrameEditorViewController.viewDidLoad() / handleCloseButtonClick()
// 功能说明: 修改后 macOS 端已有可被上下文菜单打开的 sheet 壳子，后续可以在此承接播放区、帧条与 poster 回写。
final class macOSVideoDisplayFrameEditorViewController: NSViewController {
    private let itemID: CanvasItemID

    override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = CGSize(width: 520, height: 240)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        detailLabel.stringValue =
            "Video item: \(itemID.uuidString)\n" +
            "The platform-specific frame controls will be added in the next phase."
        closeButton.target = self
        closeButton.action = #selector(handleCloseButtonClick)
    }

    @objc
    private func handleCloseButtonClick() {
        dismiss(self)
    }
}
```

## 验证

- 已对本阶段涉及的 7 个 Swift 文件执行静态诊断，`ReadLints` 返回无报错。
- 本次记录生成过程中未额外执行整项目 `xcodebuild` 编译验证。
