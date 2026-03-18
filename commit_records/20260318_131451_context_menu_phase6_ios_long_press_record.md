# 20260318_131451_context_menu_phase6_ios_long_press_record

## 记录范围

- 记录内容：
  1. 在 `iOSCanvasViewportView` 增加 `UILongPressGestureRecognizer` 和 `onLongPress` 输入桥。
  2. 扩展 `TouchInteractionState`，让 `primary pointer / long press / pinch` 在输入层有明确边界。
  3. 在 `iOSViewController` 打通 `long press -> resolveContext -> presentContextMenu` 主链路。
  4. 明确菜单显示期间与 `pointer drag / pinch zoom` 的协作策略。
- 涉及文件：
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- 本记录不包含：
  - `.cursor/plans/上下文菜单分阶段_e62bfffe.plan.md` 的状态同步
  - `macOS` secondary click 代码
  - `delete / duplicate / z-order` 等阶段 7 命令扩展
  - 原始 gif diff

## 修改一：`iOSCanvasViewportView` 增加长按桥接与菜单态

### 修改前

- `iOS` 输入层只有 `pointer + pinch` 两条链路。
- `TouchInteractionState` 没有菜单态，`viewport` 也没有对外的 `onLongPress` 回调。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名/类型名: TouchInteractionState / onPointerDown / onPointerMove / onPointerUp / onPointerCancel / pinchGestureRecognizer
// 功能说明: 修改前 viewport 只处理 primary pointer 和 pinch，没有长按桥接，也没有菜单展示中的输入状态。
private enum TouchInteractionState {
    case idle
    case trackingPrimaryPointer(trackedTouch: UITouch, lastLocation: CGPoint)
    case awaitingPinch
    case pinching
}

var onPointerDown: ((CGPoint) -> Void)?
var onPointerMove: ((CGPoint, CGPoint) -> Void)?
var onPointerUp: ((CGPoint) -> Void)?
var onPointerCancel: (() -> Void)?
var onZoom: ((CGFloat, CGPoint) -> Void)?
var onViewportSizeChange: ((CGSize) -> Void)?

private lazy var pinchGestureRecognizer: UIPinchGestureRecognizer = {
    let gestureRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
    gestureRecognizer.cancelsTouchesInView = false
    return gestureRecognizer
}()
```

### 修改后

- 增加 `longPressMinimumDuration` 与 `longPressAllowableMovement`。
- `TouchInteractionState` 增加 `presentingContextMenu(trackedTouch:)`。
- 对外暴露 `onLongPress`，并新增 `UILongPressGestureRecognizer`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名/类型名: TouchInteractionState / onLongPress / longPressGestureRecognizer
// 功能说明: 修改后 viewport 增加长按桥接与菜单展示态，为后续 controller 的上下文菜单主链路提供入口。
private static let longPressMinimumDuration: TimeInterval = 0.5
private static let longPressAllowableMovement: CGFloat = 4

private enum TouchInteractionState {
    case idle
    case trackingPrimaryPointer(
        trackedTouch: UITouch,
        pressedLocation: CGPoint,
        lastLocation: CGPoint
    )
    case awaitingPinch
    case pinching
    case presentingContextMenu(trackedTouch: UITouch)
}

var onPointerDown: ((CGPoint) -> Void)?
var onPointerMove: ((CGPoint, CGPoint) -> Void)?
var onPointerUp: ((CGPoint) -> Void)?
var onPointerCancel: (() -> Void)?
var onLongPress: ((CGPoint) -> Void)?
var onZoom: ((CGFloat, CGPoint) -> Void)?
var onViewportSizeChange: ((CGSize) -> Void)?

private lazy var pinchGestureRecognizer: UIPinchGestureRecognizer = {
    let gestureRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
    gestureRecognizer.cancelsTouchesInView = false
    return gestureRecognizer
}()

private lazy var longPressGestureRecognizer: UILongPressGestureRecognizer = {
    let gestureRecognizer = UILongPressGestureRecognizer(
        target: self,
        action: #selector(handleLongPress(_:))
    )
    gestureRecognizer.cancelsTouchesInView = false
    gestureRecognizer.minimumPressDuration = Self.longPressMinimumDuration
    gestureRecognizer.allowableMovement = Self.longPressAllowableMovement
    gestureRecognizer.numberOfTouchesRequired = 1
    return gestureRecognizer
}()
```

## 修改二：输入层状态机改成“长按优先不误触拖拽”

### 修改前

- `touchesMoved` 里只要位置变了就会继续向 controller 上抛 `onPointerMove`。
- `touchesEnded` 没有区分“这次触摸是否已经进入菜单态”。
- `reconcileTouchInteractionState()` 和 `handlePinch(_:)` 都不知道 context menu 的存在。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名/类型名: touchesMoved(_:with:) / touchesEnded(_:with:) / reconcileTouchInteractionState() / handlePinch(_:)
// 功能说明: 修改前 touch 状态机只围绕 pointer/pinch 设计，没有为长按菜单预留状态边界。
override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
    super.touchesMoved(touches, with: event)
    registerActiveTouches(touches)

    guard !isPinchGestureActive else {
        cancelPrimaryPointerIfNeeded()
        interactionState = .pinching
        return
    }

    switch interactionState {
    case let .trackingPrimaryPointer(trackedTouch, lastLocation):
        guard activeTouchCount == 1 else {
            cancelPrimaryPointerIfNeeded()
            interactionState = .awaitingPinch
            return
        }

        guard let currentTouch = touchMatching(trackedTouch, in: touches) else {
            return
        }

        let currentLocation = currentTouch.location(in: self)
        interactionState = .trackingPrimaryPointer(
            trackedTouch: trackedTouch,
            lastLocation: currentLocation
        )

        guard currentLocation != lastLocation else {
            return
        }

        onPointerMove?(currentLocation, lastLocation)
    case .idle, .awaitingPinch, .pinching:
        reconcileTouchInteractionState()
    }
}

override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
    super.touchesEnded(touches, with: event)
    let pointerUpLocation = trackedPointerLocation(in: touches)
    unregisterActiveTouches(touches)

    guard !isPinchGestureActive else {
        interactionState = .pinching
        return
    }

    if let pointerUpLocation {
        onPointerUp?(pointerUpLocation)
    }

    reconcileTouchInteractionState()
}

private func reconcileTouchInteractionState() {
    guard !isPinchGestureActive else {
        cancelPrimaryPointerIfNeeded()
        interactionState = .pinching
        return
    }

    switch activeTouchCount {
    case 0:
        interactionState = .idle
    case 1:
        guard let touch = soleActiveTouch else {
            interactionState = .idle
            return
        }

        if case let .trackingPrimaryPointer(trackedTouch, _) = interactionState, trackedTouch === touch {
            return
        }

        beginPrimaryPointerTracking(with: touch)
    default:
        cancelPrimaryPointerIfNeeded()
        interactionState = .awaitingPinch
    }
}

@objc
private func handlePinch(_ gestureRecognizer: UIPinchGestureRecognizer) {
    switch gestureRecognizer.state {
    case .began, .changed:
        cancelPrimaryPointerIfNeeded()
        interactionState = .pinching
        let scaleDelta = gestureRecognizer.scale
        guard scaleDelta.isFinite, scaleDelta > 0 else {
            return
        }

        onZoom?(scaleDelta, gestureRecognizer.location(in: self))
        gestureRecognizer.scale = 1
    case .ended, .cancelled, .failed:
        reconcileTouchInteractionState()
    default:
        break
    }
}
```

### 修改后

- 在 `touchesMoved` 中，如果当前还处于 long press 的可识别窗口，就先不把 move 继续上抛，避免“想长按却先误触拖拽”。
- `touchesEnded` 会识别当前触摸是否已经进入菜单态；如果是，就只负责收尾，不再继续走 `pointerUp`。
- `reconcileTouchInteractionState()` 增加 `presentingContextMenu` 分支。
- `handlePinch(_:)` 在菜单态直接返回，避免 pinch 与菜单同时生效。
- 新增 `handleLongPress(_:)`，长按成立后先 `cancelPrimaryPointerIfNeeded()`，再切到菜单态并把位置回调给 controller。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名/类型名: touchesMoved(_:with:) / touchesEnded(_:with:) / reconcileTouchInteractionState() / handlePinch(_:) / handleLongPress(_:)
// 功能说明: 修改后输入层明确区分 pointer、long press、pinch 三种路径，避免菜单和拖拽/缩放互相污染。
override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
    super.touchesMoved(touches, with: event)
    registerActiveTouches(touches)

    if case .presentingContextMenu = interactionState {
        return
    }

    guard !isPinchGestureActive else {
        cancelPrimaryPointerIfNeeded()
        interactionState = .pinching
        return
    }

    switch interactionState {
    case let .trackingPrimaryPointer(trackedTouch, pressedLocation, lastLocation):
        guard activeTouchCount == 1 else {
            cancelPrimaryPointerIfNeeded()
            interactionState = .awaitingPinch
            return
        }

        guard let currentTouch = touchMatching(trackedTouch, in: touches) else {
            return
        }

        let currentLocation = currentTouch.location(in: self)
        guard currentLocation != lastLocation else {
            return
        }

        // 在长按仍可识别的移动窗口内，先不要把 move 传给 controller，避免误触拖拽。
        if longPressGestureRecognizer.state == .possible,
           distance(from: pressedLocation, to: currentLocation) <= Self.longPressAllowableMovement
        {
            return
        }

        interactionState = .trackingPrimaryPointer(
            trackedTouch: trackedTouch,
            pressedLocation: pressedLocation,
            lastLocation: currentLocation
        )
        onPointerMove?(currentLocation, lastLocation)
    case .idle, .awaitingPinch, .pinching, .presentingContextMenu:
        reconcileTouchInteractionState()
    }
}

override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
    super.touchesEnded(touches, with: event)
    let wasPresentingContextMenu = isContextMenuTouch(in: touches)
    let pointerUpLocation = trackedPointerLocation(in: touches)
    unregisterActiveTouches(touches)

    if wasPresentingContextMenu {
        if activeTouchCount == 0 {
            interactionState = .idle
        }
        return
    }

    guard !isPinchGestureActive else {
        interactionState = .pinching
        return
    }

    if let pointerUpLocation {
        onPointerUp?(pointerUpLocation)
    }

    reconcileTouchInteractionState()
}

private func reconcileTouchInteractionState() {
    if case let .presentingContextMenu(trackedTouch) = interactionState {
        if activeTouchCount == 1,
           let soleActiveTouch,
           soleActiveTouch === trackedTouch
        {
            return
        }

        if activeTouchCount == 0 {
            interactionState = .idle
        }
        return
    }

    guard !isPinchGestureActive else {
        cancelPrimaryPointerIfNeeded()
        interactionState = .pinching
        return
    }

    switch activeTouchCount {
    case 0:
        interactionState = .idle
    case 1:
        guard let touch = soleActiveTouch else {
            interactionState = .idle
            return
        }

        if case let .trackingPrimaryPointer(trackedTouch, _, _) = interactionState,
           trackedTouch === touch
        {
            return
        }

        beginPrimaryPointerTracking(with: touch)
    default:
        cancelPrimaryPointerIfNeeded()
        interactionState = .awaitingPinch
    }
}

@objc
private func handlePinch(_ gestureRecognizer: UIPinchGestureRecognizer) {
    if case .presentingContextMenu = interactionState {
        return
    }

    switch gestureRecognizer.state {
    case .began, .changed:
        cancelPrimaryPointerIfNeeded()
        interactionState = .pinching

        let scaleDelta = gestureRecognizer.scale
        guard scaleDelta.isFinite, scaleDelta > 0 else {
            return
        }

        onZoom?(scaleDelta, gestureRecognizer.location(in: self))
        gestureRecognizer.scale = 1
    case .ended, .cancelled, .failed:
        reconcileTouchInteractionState()
    default:
        break
    }
}

@objc
private func handleLongPress(_ gestureRecognizer: UILongPressGestureRecognizer) {
    guard gestureRecognizer.state == .began else {
        return
    }

    guard
        activeTouchCount == 1,
        let trackedTouch = trackedTouchForContextMenuPresentation()
    else {
        return
    }

    cancelPrimaryPointerIfNeeded()
    interactionState = .presentingContextMenu(trackedTouch: trackedTouch)
    onLongPress?(gestureRecognizer.location(in: self))
}
```

## 修改三：`iOSViewController` 接入长按菜单主链路

### 修改前

- `setupCanvasViewport()` 只绑定 `pointer / zoom / viewportSizeChange`。
- `handlePrimaryPointerDown(at:)` 不会先处理已经打开的菜单。
- controller 没有 `handleLongPress(at:)` 和 `prepareForLongPressContextMenu()`。
- `handleZoom(_:around:)` 在菜单显示时仍会直接缩放画布。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: setupCanvasViewport() / handlePrimaryPointerDown(at:) / handleZoom(_:around:)
// 功能说明: 修改前 controller 还没有长按菜单入口，菜单与 pointer/pinch 也没有显式协作边界。
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
    canvasViewportView.onZoom = { [weak self] scaleDelta, anchor in
        self?.handleZoom(scaleDelta, around: anchor)
    }
    canvasViewportView.onViewportSizeChange = { [weak self] viewportSize in
        self?.syncCameraViewportSizeIfNeeded(
            viewportSize,
            source: "viewport layout"
        )
    }

    installCanvasContentView(canvasViewportView)
    requestCanvasRefresh(reason: "initial setup")
}

private func handlePrimaryPointerDown(at location: CGPoint) {
    syncCameraViewportSizeFromCurrentBoundsIfPossible()
    guard hasRenderableViewportSize else {
        logIgnoredCanvasInput("pointer down \(describe(point: location))")
        return
    }

    let pressContext = resolveContext(at: location)
    pointerDragState = .pressed(
        pressedLocation: location,
        pressContext: pressContext
    )
    beginPointerHistoryTransactionIfNeeded(for: pressContext)
}

private func handleZoom(_ scaleDelta: CGFloat, around anchor: CGPoint) {
    syncCameraViewportSizeFromCurrentBoundsIfPossible()
    guard hasRenderableViewportSize else {
        logIgnoredCanvasInput(
            "zoom scaleDelta=\(String(format: "%.4f", scaleDelta)) anchor=\(describe(point: anchor))"
        )
        return
    }

    camera.zoom(by: scaleDelta, around: anchor)
    requestCanvasRefresh(
        reason: "zoom scaleDelta=\(String(format: "%.4f", scaleDelta)) anchor=\(describe(point: anchor))"
    )
    scheduleAutosave(reason: "zoom canvas")
}
```

### 修改后

- `setupCanvasViewport()` 增加 `onLongPress` 绑定。
- `handlePrimaryPointerDown(at:)` 先处理已显示菜单，避免菜单开着时再次进入新的 `pressed`。
- 新增 `handleLongPress(at:)` 和 `prepareForLongPressContextMenu()`，长按时先复用现有 `handlePrimaryPointerCancel()` 语义收掉当前交互，再走 `resolveContext -> presentContextMenu`。
- `handleZoom(_:around:)` 在菜单显示期间先关闭菜单，不继续缩放。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: setupCanvasViewport() / handlePrimaryPointerDown(at:) / handleLongPress(at:) / prepareForLongPressContextMenu() / handleZoom(_:around:)
// 功能说明: 修改后 controller 接入长按菜单主链路，并把菜单与 pointer/pinch 的协作边界收敛到平台层。
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
    canvasViewportView.onLongPress = { [weak self] location in
        self?.handleLongPress(at: location)
    }
    canvasViewportView.onZoom = { [weak self] scaleDelta, anchor in
        self?.handleZoom(scaleDelta, around: anchor)
    }
    canvasViewportView.onViewportSizeChange = { [weak self] viewportSize in
        self?.syncCameraViewportSizeIfNeeded(
            viewportSize,
            source: "viewport layout"
        )
    }

    installCanvasContentView(canvasViewportView)
    requestCanvasRefresh(reason: "initial setup")
}

private func handlePrimaryPointerDown(at location: CGPoint) {
    syncCameraViewportSizeFromCurrentBoundsIfPossible()
    guard hasRenderableViewportSize else {
        logIgnoredCanvasInput("pointer down \(describe(point: location))")
        return
    }

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

private func handleLongPress(at location: CGPoint) {
    syncCameraViewportSizeFromCurrentBoundsIfPossible()
    guard hasRenderableViewportSize else {
        logIgnoredCanvasInput("long press \(describe(point: location))")
        return
    }

    prepareForLongPressContextMenu()

    let resolvedContext = resolveContext(at: location)
    presentContextMenu(for: resolvedContext)
}

private func prepareForLongPressContextMenu() {
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
        // 复用 primary cancel 语义，避免长按时留下半提交的交互态。
        handlePrimaryPointerCancel()
    }
}

private func handleZoom(_ scaleDelta: CGFloat, around anchor: CGPoint) {
    syncCameraViewportSizeFromCurrentBoundsIfPossible()
    guard hasRenderableViewportSize else {
        logIgnoredCanvasInput(
            "zoom scaleDelta=\(String(format: "%.4f", scaleDelta)) anchor=\(describe(point: anchor))"
        )
        return
    }

    if contextMenuState != nil {
        dismissContextMenu()
        return
    }

    camera.zoom(by: scaleDelta, around: anchor)
    requestCanvasRefresh(
        reason: "zoom scaleDelta=\(String(format: "%.4f", scaleDelta)) anchor=\(describe(point: anchor))"
    )
    scheduleAutosave(reason: "zoom canvas")
}
```

## 验证结果

- 已通过 `date +"%Y%m%d_%H%M%S"` 获取本记录时间戳：`20260318_131451`
- 已通过 `ReadLints` 检查本次改动文件，无新增 lint 问题
- 已通过 `xcodebuild` 构建验证：
  - `iOS`: `generic/platform=iOS`
  - `macOS`: `generic/platform=macOS`

## 当前阶段结论

- 阶段 6 已把 `iOS` 长按菜单主链路接通：`long press -> resolveContext -> presentContextMenu`
- 这次落定的协作策略是：
  - 长按识别开始前，允许 primary pointer 先进入 `pressed`
  - 长按真正成立时，立即 cancel 当前 pointer interaction，再弹菜单
  - 菜单显示期间，不继续让这次长按对应的拖拽链路和 pinch 缩放直接作用到画布
- 到这里，`macOS` 右键和 `iOS` 长按都已经有了各自的输入桥接；后续阶段 7 可以集中补命令面和回归验证
