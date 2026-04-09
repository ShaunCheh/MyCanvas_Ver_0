# 20260409_091353_boardlist_zoom_transition_phase1_transition_contract_record

## 记录范围

- 记录内容：实施 `boardlist缩放转场` 计划的 `Phase 1`，抽取共享转场域模型与打开/返回请求契约。
- 记录内容：让 `BoardList -> AppRoot -> Canvas -> AppRoot` 这条链路从松散闭包升级为结构化 request/context。
- 记录内容：本阶段只搭“契约”和“上下文”，不实现 `source rect / target rect` 采集，不实现 carrier，不引入视觉动画。
- 记录依据：本记录基于当前工作树的 `git status --short` 与本次修改文件的 `git diff -- [paths]`，并结合修改后的源码内容整理。
- 涉及源码文件：`MyCanvas_Ver_0/App/AppLaunchDestination.swift`
- 涉及源码文件：`MyCanvas_Ver_0/Platform/Shared/BoardList/BoardListEntry.swift`
- 涉及源码文件：`MyCanvas_Ver_0/Platform/Shared/Transition/BoardListCanvasTransitionGeometry.swift`
- 涉及源码文件：`MyCanvas_Ver_0/Platform/Shared/Transition/BoardListCanvasTransitionState.swift`
- 涉及源码文件：`MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift`
- 涉及源码文件：`MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSAppRootViewController.swift`
- 涉及源码文件：`MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift`
- 涉及源码文件：`MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift`
- 涉及源码文件：`MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- 涉及源码文件：`MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 本记录不包含：`Phase 2` 的卡片几何采集与 reveal 后目标解析。
- 本记录不包含：`Phase 3` 的 `AppRoot` 转场状态机与 `TransitionCarrier`。
- 本记录不包含：`Phase 4/5` 的 opening / closing 动画实现。
- 本记录不包含：git commit。

## 修改一：补齐共享路由基础类型，让转场上下文可直接复用现有业务语义

### 修改前

- `CanvasLaunchContext` 只承载 `existing/newBoard` 两种 case，没有供转场层复用的派生语义。
- `AppLaunchDestination` 与 `BoardListEntryID` 还没有统一声明 `Sendable`，不利于后续把它们安全放进共享转场上下文。

```swift
// 文件路径: MyCanvas_Ver_0/App/AppLaunchDestination.swift
// 函数名/符号名: CanvasLaunchContext / AppLaunchDestination
// 功能说明: 修改前路由层只有最小业务语义，转场层无法直接复用“已有 boardID”或“返回时是否需要持久化”的派生信息。
import Foundation

enum CanvasLaunchContext {
    case existing(boardID: UUID)
    case newBoard
}

enum AppLaunchDestination {
    case boardList
    case canvas(CanvasLaunchContext)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardListEntry.swift
// 函数名/符号名: BoardListEntryID
// 功能说明: 修改前 entry 标识只有 Hashable，没有和共享转场上下文一起声明 Sendable。
import Foundation

enum BoardListEntryID: Hashable {
    case newBoard
    case board(UUID)
}
```

### 修改后

- `CanvasLaunchContext` 升级为 `Hashable, Sendable`，并补上：
  - `existingBoardID`
  - `requiresBoardPersistenceOnReturn`
- `BoardListEntryID` 同步声明为 `Hashable, Sendable`，方便直接作为共享转场上下文的一部分。

```swift
// 文件路径: MyCanvas_Ver_0/App/AppLaunchDestination.swift
// 函数名/符号名: CanvasLaunchContext.existingBoardID / CanvasLaunchContext.requiresBoardPersistenceOnReturn / AppLaunchDestination
// 功能说明: 修改后共享转场层可以直接复用 launchContext 推导目标 boardID 与“新建板返回时需要先确保落盘”的语义。
import Foundation

enum CanvasLaunchContext: Hashable, Sendable {
    case existing(boardID: UUID)
    case newBoard

    var existingBoardID: UUID? {
        switch self {
        case let .existing(boardID):
            return boardID
        case .newBoard:
            return nil
        }
    }

    var requiresBoardPersistenceOnReturn: Bool {
        switch self {
        case .existing:
            return false
        case .newBoard:
            return true
        }
    }
}

enum AppLaunchDestination: Hashable, Sendable {
    case boardList
    case canvas(CanvasLaunchContext)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardListEntry.swift
// 函数名/符号名: BoardListEntryID
// 功能说明: 修改后 entry 标识可以直接进入共享 transition context，后续 Phase 2/3 不需要额外包一层平台专属类型。
import Foundation

enum BoardListEntryID: Hashable, Sendable {
    case newBoard
    case board(UUID)
}
```

## 修改二：新增共享转场几何与请求域模型

### 修改前

- 共享层还没有 `BoardList <-> Canvas` 的转场请求类型。
- `AppRoot` 只能消费“打开某个 boardID”或“无参返回列表”这种松散回调，无法暂存统一的 opening / closing 上下文。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Transition/BoardListCanvasTransitionGeometry.swift（修改前不存在）
// 函数名/符号名: 无
// 功能说明: 修改前共享层没有 source/target 几何容器，也没有统一的 rect 清洗入口。
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Transition/BoardListCanvasTransitionState.swift（修改前不存在）
// 函数名/符号名: 无
// 功能说明: 修改前共享层没有 open request、return request、transition context、carrier kind 这些领域模型。
```

### 修改后

- 新增 `BoardListCanvasTransitionSourceGeometry` / `BoardListCanvasTransitionTargetGeometry`。
- 新增 `BoardListCanvasTransitionGeometry.sanitizedRect(_:)`，先把将来采集到的 rect 做统一标准化与非法值过滤。
- 新增 `BoardListCanvasOpenRequest` / `BoardListCanvasReturnRequest` / `BoardListCanvasTransitionContext`。
- 新增 `BoardListCanvasTransitionCarrierKind`，当前先收口为 `.snapshotShell` 与未来的 `.liveCanvas`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Transition/BoardListCanvasTransitionGeometry.swift
// 函数名/符号名: BoardListCanvasTransitionSourceGeometry / BoardListCanvasTransitionTargetGeometry / BoardListCanvasTransitionGeometry.sanitizedRect(_:)
// 功能说明: 新增共享几何容器，并统一过滤空 rect、无限 rect、非有限值 rect，为后续 Phase 2 的几何采集做边界收口。
import CoreGraphics
import Foundation

struct BoardListCanvasTransitionSourceGeometry: Hashable, Sendable {
    var cardRect: CGRect?
    var previewRect: CGRect?

    init(
        cardRect: CGRect? = nil,
        previewRect: CGRect? = nil
    ) {
        self.cardRect = BoardListCanvasTransitionGeometry.sanitizedRect(
            cardRect
        )
        self.previewRect = BoardListCanvasTransitionGeometry.sanitizedRect(
            previewRect
        )
    }
}

struct BoardListCanvasTransitionTargetGeometry: Hashable, Sendable {
    var cardRect: CGRect?

    init(cardRect: CGRect? = nil) {
        self.cardRect = BoardListCanvasTransitionGeometry.sanitizedRect(
            cardRect
        )
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Transition/BoardListCanvasTransitionState.swift
// 函数名/符号名: BoardListCanvasOpenRequest / BoardListCanvasReturnRequest / BoardListCanvasTransitionContext
// 功能说明: 新增共享转场领域模型，把“打开来源”“返回来源”“目标 board 身份”“方向”“carrier 偏好”统一收口成可复用上下文。
import CoreGraphics
import Foundation

enum BoardListCanvasTransitionDirection: Hashable, Sendable {
    case opening
    case closing
}

enum BoardListCanvasTransitionCarrierKind: Hashable, Sendable {
    case snapshotShell
    case liveCanvas
}

struct BoardListCanvasOpenRequest: Hashable, Sendable {
    var launchContext: CanvasLaunchContext
    var source: BoardListCanvasOpenSource
    var preferredCarrierKind: BoardListCanvasTransitionCarrierKind

    static func existingBoard(
        boardID: UUID,
        geometry: BoardListCanvasTransitionSourceGeometry = .init(),
        preferredCarrierKind: BoardListCanvasTransitionCarrierKind = .snapshotShell
    ) -> Self {
        BoardListCanvasOpenRequest(
            launchContext: .existing(boardID: boardID),
            source: BoardListCanvasOpenSource(
                kind: .existingBoardCard,
                entryID: .board(boardID),
                boardID: boardID,
                geometry: geometry
            ),
            preferredCarrierKind: preferredCarrierKind
        )
    }

    static func newBoardPlaceholder(
        geometry: BoardListCanvasTransitionSourceGeometry = .init(),
        preferredCarrierKind: BoardListCanvasTransitionCarrierKind = .snapshotShell
    ) -> Self {
        BoardListCanvasOpenRequest(
            launchContext: .newBoard,
            source: BoardListCanvasOpenSource(
                kind: .newBoardPlaceholder,
                entryID: .newBoard,
                boardID: nil,
                geometry: geometry
            ),
            preferredCarrierKind: preferredCarrierKind
        )
    }
}
```

## 修改三：双端 `BoardList` 把打开动作统一收口为 `BoardListCanvasOpenRequest`

### 修改前

- `BoardList` 侧还是两条旧回调：
  - `onOpenBoard: ((UUID) -> Void)?`
  - `onCreateBoard: (() -> Void)?`
- `performPrimaryAction(for:)` 直接把 placeholder/newBoard 和真实 board 分裂成两条上抛路径。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/符号名: onOpenBoard / onCreateBoard / performPrimaryAction(for:)
// 功能说明: 修改前 iOS BoardList 只往上抛“打开 boardID”或“无参新建”，没有统一的 open request。
private let folderPicker = FolderPicker()
var onOpenBoard: ((UUID) -> Void)?
var onCreateBoard: (() -> Void)?

private func performPrimaryAction(for entry: BoardListEntry) {
    // ... 省略 guard ...
    switch entry {
    case .newBoardPlaceholder:
        onCreateBoard?()
    case let .board(item):
        onOpenBoard?(item.boardID)
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名/符号名: onOpenBoard / onCreateBoard / performPrimaryAction(for:)
// 功能说明: 修改前 macOS BoardList 与 iOS 相同，也是两条分裂的打开链路。
var onOpenBoard: ((UUID) -> Void)?
var onCreateBoard: (() -> Void)?

private func performPrimaryAction(for entry: BoardListEntry) {
    // ... 省略 guard ...
    switch entry {
    case .newBoardPlaceholder:
        onCreateBoard?()
    case let .board(item):
        onOpenBoard?(item.boardID)
    }
}
```

### 修改后

- 双端统一改成：
  - `onOpenCanvas: ((BoardListCanvasOpenRequest) -> Void)?`
- `performPrimaryAction(for:)` 不再直接分流到两个闭包，而是统一走 `makeOpenRequest(for:)`。
- `newBoardPlaceholder` 和真实 board 都在这里被转换成标准化的 `BoardListCanvasOpenRequest`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/符号名: onOpenCanvas / performPrimaryAction(for:) / makeOpenRequest(for:)
// 功能说明: 修改后 iOS BoardList 只向上抛统一 open request，为后续补 source rect 留出固定出口。
private let folderPicker = FolderPicker()
var onOpenCanvas: ((BoardListCanvasOpenRequest) -> Void)?

private func performPrimaryAction(for entry: BoardListEntry) {
    // ... 省略 guard ...
    onOpenCanvas?(makeOpenRequest(for: entry))
}

private func makeOpenRequest(
    for entry: BoardListEntry
) -> BoardListCanvasOpenRequest {
    switch entry {
    case .newBoardPlaceholder:
        return .newBoardPlaceholder()
    case let .board(item):
        return .existingBoard(boardID: item.boardID)
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名/符号名: onOpenCanvas / performPrimaryAction(for:) / makeOpenRequest(for:)
// 功能说明: 修改后 macOS BoardList 与 iOS 同构，统一把列表交互包装成结构化 open request。
var onOpenCanvas: ((BoardListCanvasOpenRequest) -> Void)?

private func performPrimaryAction(for entry: BoardListEntry) {
    // ... 省略 guard ...
    onOpenCanvas?(makeOpenRequest(for: entry))
}

private func makeOpenRequest(
    for entry: BoardListEntry
) -> BoardListCanvasOpenRequest {
    switch entry {
    case .newBoardPlaceholder:
        return .newBoardPlaceholder()
    case let .board(item):
        return .existingBoard(boardID: item.boardID)
    }
}
```

## 修改四：双端 `AppRoot` 开始消费结构化 open/return request，并缓存统一 transition context

### 修改前

- `AppRoot` 还在直接消费旧闭包：
  - `BoardList.onOpenBoard`
  - `BoardList.onCreateBoard`
  - `Canvas.onBackToBoardList`
- 即使路由已经能表达 `CanvasLaunchContext`，容器层也还拿不到一份显式的 opening / closing 转场上下文。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift
// 函数名/符号名: makeViewController(for:) / configureBoardListViewController(_:)
// 功能说明: 修改前 iOS AppRoot 只接收 UUID 或无参回调，无法缓存统一 transition context。
private func makeViewController(for destination: AppLaunchDestination) -> UIViewController {
    switch destination {
    case .boardList:
        boardListViewController.prepareForDisplay()
        return boardListViewController
    case let .canvas(launchContext):
        let viewController = iOSViewController()
        viewController.launchContext = launchContext
        viewController.onBackToBoardList = { [weak self] in
            self?.display(.boardList)
        }
        return viewController
    }
}

private func configureBoardListViewController(
    _ viewController: iOSBoardListViewController
) {
    viewController.onOpenBoard = { [weak self] boardID in
        self?.display(.canvas(.existing(boardID: boardID)))
    }
    viewController.onCreateBoard = { [weak self] in
        self?.display(.canvas(.newBoard))
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSAppRootViewController.swift
// 函数名/符号名: makeViewController(for:) / configureBoardListViewController(_:)
// 功能说明: 修改前 macOS AppRoot 同样没有结构化 open/return request 的入口。
private func makeViewController(for destination: AppLaunchDestination) -> NSViewController {
    switch destination {
    case .boardList:
        boardListViewController.prepareForDisplay()
        return boardListViewController
    case let .canvas(launchContext):
        let viewController = macOSViewController()
        viewController.launchContext = launchContext
        viewController.onBackToBoardList = { [weak self] in
            self?.display(.boardList)
        }
        return viewController
    }
}

private func configureBoardListViewController(
    _ viewController: macOSBoardListViewController
) {
    viewController.onOpenBoard = { [weak self] boardID in
        self?.display(.canvas(.existing(boardID: boardID)))
    }
    viewController.onCreateBoard = { [weak self] in
        self?.display(.canvas(.newBoard))
    }
}
```

### 修改后

- 双端 `AppRoot` 新增 `currentBoardListCanvasTransitionContext`。
- `BoardList` 改为向容器抛 `BoardListCanvasOpenRequest`。
- `Canvas` 改为向容器抛 `BoardListCanvasReturnRequest`。
- 当前阶段容器只负责接住 request、缓存 `transitionContext`，然后继续沿用原有 `display(...)` 路由；动画仍留给后续阶段。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift
// 函数名/符号名: currentBoardListCanvasTransitionContext / makeViewController(for:) / handleCanvasOpenRequest(_:) / handleCanvasReturnRequest(_:)
// 功能说明: 修改后 iOS AppRoot 已能完整收到 opening / closing 的结构化上下文，但仍保持现有页面切换行为不变。
private var currentBoardListCanvasTransitionContext: BoardListCanvasTransitionContext?

private func makeViewController(for destination: AppLaunchDestination) -> UIViewController {
    switch destination {
    case .boardList:
        boardListViewController.prepareForDisplay()
        return boardListViewController
    case let .canvas(launchContext):
        let viewController = iOSViewController()
        viewController.launchContext = launchContext
        viewController.onReturnToBoardList = { [weak self] request in
            self?.handleCanvasReturnRequest(request)
        }
        return viewController
    }
}

private func handleCanvasOpenRequest(
    _ request: BoardListCanvasOpenRequest
) {
    currentBoardListCanvasTransitionContext = request.transitionContext
    display(.canvas(request.launchContext))
}

private func handleCanvasReturnRequest(
    _ request: BoardListCanvasReturnRequest
) {
    currentBoardListCanvasTransitionContext = request.transitionContext
    display(.boardList)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSAppRootViewController.swift
// 函数名/符号名: currentBoardListCanvasTransitionContext / makeViewController(for:) / handleCanvasOpenRequest(_:) / handleCanvasReturnRequest(_:)
// 功能说明: 修改后 macOS AppRoot 与 iOS 对齐，容器层第一次成为统一接收转场 request/context 的中枢。
private var currentBoardListCanvasTransitionContext: BoardListCanvasTransitionContext?

private func makeViewController(for destination: AppLaunchDestination) -> NSViewController {
    switch destination {
    case .boardList:
        boardListViewController.prepareForDisplay()
        return boardListViewController
    case let .canvas(launchContext):
        let viewController = macOSViewController()
        viewController.launchContext = launchContext
        viewController.onReturnToBoardList = { [weak self] request in
            self?.handleCanvasReturnRequest(request)
        }
        return viewController
    }
}

private func handleCanvasOpenRequest(
    _ request: BoardListCanvasOpenRequest
) {
    currentBoardListCanvasTransitionContext = request.transitionContext
    display(.canvas(request.launchContext))
}

private func handleCanvasReturnRequest(
    _ request: BoardListCanvasReturnRequest
) {
    currentBoardListCanvasTransitionContext = request.transitionContext
    display(.boardList)
}
```

## 修改五：双端 `Canvas` 返回链从无参闭包升级为 `BoardListCanvasReturnRequest`

### 修改前

- 双端控制器都只暴露：
  - `var onBackToBoardList: (() -> Void)?`
- 返回按钮只能通知“回列表”，但不能回传：
  - 当前 `boardID`
  - 当前 `launchContext`
  - 这个返回是不是来自新建板，后续是否需要先确保落盘

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/符号名: onBackToBoardList / handleBackButtonTap()
// 功能说明: 修改前 iOS Canvas 返回时只能无参通知容器，容器拿不到 boardID 与返回语义。
var launchContext: CanvasLaunchContext?
var onBackToBoardList: (() -> Void)?

@objc
private func handleBackButtonTap() {
    commitActiveTextEditIfNeeded()
    dismissContextMenu()
    onBackToBoardList?()
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/符号名: onBackToBoardList / handleBackButtonClick()
// 功能说明: 修改前 macOS Canvas 返回链与 iOS 相同，也没有返回 request/context。
var launchContext: CanvasLaunchContext?
var onBackToBoardList: (() -> Void)?

@objc
private func handleBackButtonClick() {
    commitActiveTextEditIfNeeded()
    dismissContextMenu()
    onBackToBoardList?()
}
```

### 修改后

- 双端统一改成：
  - `var onReturnToBoardList: ((BoardListCanvasReturnRequest) -> Void)?`
- 返回按钮先通过 `makeReturnToBoardListRequest()` 组装结构化请求，再交给 `AppRoot`。
- 当前 request 已包含：
  - `editorSession.activeBoardID`
  - `launchContext`
  - `requiresBoardPersistence`
- 这为后续 `Phase 5` 的“新建板返回前先保存，再缩回真实新卡片”打下了契约基础。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/符号名: onReturnToBoardList / makeReturnToBoardListRequest() / handleBackButtonTap()
// 功能说明: 修改后 iOS Canvas 返回按钮会带着当前 boardID 与 launchContext 向容器发起 return request。
var launchContext: CanvasLaunchContext?
var onReturnToBoardList: ((BoardListCanvasReturnRequest) -> Void)?

private func makeReturnToBoardListRequest() -> BoardListCanvasReturnRequest {
    .backButton(
        boardID: editorSession.activeBoardID,
        launchContext: launchContext
    )
}

@objc
private func handleBackButtonTap() {
    commitActiveTextEditIfNeeded()
    dismissContextMenu()
    onReturnToBoardList?(makeReturnToBoardListRequest())
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/符号名: onReturnToBoardList / makeReturnToBoardListRequest() / handleBackButtonClick()
// 功能说明: 修改后 macOS Canvas 返回链与 iOS 对齐，统一向 AppRoot 上抛结构化 return request。
var launchContext: CanvasLaunchContext?
var onReturnToBoardList: ((BoardListCanvasReturnRequest) -> Void)?

private func makeReturnToBoardListRequest() -> BoardListCanvasReturnRequest {
    .backButton(
        boardID: editorSession.activeBoardID,
        launchContext: launchContext
    )
}

@objc
private func handleBackButtonClick() {
    commitActiveTextEditIfNeeded()
    dismissContextMenu()
    onReturnToBoardList?(makeReturnToBoardListRequest())
}
```

## 行为结果

- `BoardList` 现在不再把“打开已有板”和“新建板”分裂成两条上抛接口，而是统一输出 `BoardListCanvasOpenRequest`。
- `Canvas` 返回时不再只有“回列表”这个空动作，而是统一输出 `BoardListCanvasReturnRequest`。
- `AppRoot` 现在已经能完整拿到一次 opening request 和一次 closing request 的结构化上下文。
- 本阶段仍然没有视觉变化，页面切换继续沿用原有的 `display(...)` / `setCurrentViewController(...)`。
- `Phase 2` 可以直接在现有 request/context 上补 `source rect / target rect`，不需要再回头重写打开/返回契约。

## 校验结果

- 已通过 `ReadLints` 检查本次修改文件，未发现新的 lint 错误。
- 已执行并通过以下语法解析命令：
  - `xcrun --sdk macosx swiftc -frontend -parse "MyCanvas_Ver_0/App/AppLaunchDestination.swift" "MyCanvas_Ver_0/Platform/Shared/BoardList/BoardListEntry.swift" "MyCanvas_Ver_0/Platform/Shared/Transition/BoardListCanvasTransitionGeometry.swift" "MyCanvas_Ver_0/Platform/Shared/Transition/BoardListCanvasTransitionState.swift" "MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSAppRootViewController.swift" "MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift" "MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift"`
- iOS 侧本轮仍以 IDE lint 为主，没有额外执行完整 iOS SDK 编译解析。

## 后续衔接

- 下一阶段可以直接在 `BoardListCanvasOpenRequest.source.geometry` 上补 `source card rect / preview rect`。
- 返回链可以直接在 `BoardListCanvasReturnRequest.targetGeometry` 上补 `pendingRevealBoardID -> reveal -> target rect`。
- `AppRoot` 已经具备后续承接 `TransitionCarrier` 与显式转场状态机的基本入口，不需要再改回调签名。
