# 20260408_124413_toolbar_transition_phase1_host_presentation_record

## 记录范围

- 记录内容：
  1. 为 iOS / macOS 的工具栏 Host 引入内容裁切层 `contentClipView`，把按钮栈从直接贴住 Host 外框的结构改成“外框 + 裁切内容层 + 按钮栈”的三层结构。
  2. 为 iOS / macOS 的工具栏 Host 增加 `renderTransition(_:)`、`completeTransition(applying:)`、`cancelTransition(applying:)` 三个过渡渲染入口，接通 `Phase 0` 的 `CanvasToolbarTransitionPresentation`。
  3. 为 iOS / macOS 的工具栏 Host 增加过渡期交互门控与内容外观应用逻辑，让后续控制器可以直接驱动 `alpha / scale / keepsHostVisible / isInteractive`。
- 涉及文件：
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift`
  - `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift`
- 当前 changes 依据：
  - `git status --short` 当前仅显示两份已修改文件：
    - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift`
    - `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift`
  - `git diff -- <path>` 可确认这次改动只发生在双端 Host，且是围绕内容裁切层、transition 接口、命中门控和内容缩放展开，没有控制器改动。
- 本记录不包含：
  - `Phase 0` 的共享过渡契约与几何 helper
  - `Phase 2` / `Phase 3` 的控制器动画编排
  - `Phase 4` 的布局竞争与 reconcile 收口
  - git commit / push

## 修改一：Host 内部层级从“背景 + 按钮栈”改为“背景 + 内容裁切层 + 按钮栈”

### 修改前

- iOS / macOS Host 都是直接把 `buttonsStackView` 加到 Host 根视图上。
- `buttonsStackView` 四边约束直接贴到 Host 外框：
  - 顶部 + 左右 inset
  - 底部也强约束到 Host 底部
- 这意味着后续如果直接缩 Host 高度，让工具栏外框收拢到正方形，就会把按钮栈和固定按钮尺寸一起往里挤，容易和约束体系冲突。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
// 函数名: init(frame:)
// 功能说明: 修改前 iOS Host 直接把 buttonsStackView 挂到 Host 根视图，按钮栈底部强约束到 Host 底部，不适合后续“底部向上升”的收拢动画。
override init(frame: CGRect) {
    super.init(frame: frame)
    translatesAutoresizingMaskIntoConstraints = false
    addSubview(backgroundView)
    addSubview(buttonsStackView)
    NSLayoutConstraint.activate([
        backgroundView.topAnchor.constraint(equalTo: topAnchor),
        backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
        backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
        backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
        buttonsStackView.topAnchor.constraint(equalTo: topAnchor, constant: CanvasToolbarChromeMetrics.verticalInset),
        buttonsStackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: CanvasToolbarChromeMetrics.horizontalInset),
        buttonsStackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -CanvasToolbarChromeMetrics.horizontalInset),
        buttonsStackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -CanvasToolbarChromeMetrics.verticalInset)
    ])
    updateDockEdgeLayout()
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// 函数名: init(frame:)
// 功能说明: 修改前 macOS Host 与 iOS 一样，按钮栈直接贴住 Host 外框，后续如果缩 Host 高度，会直接把按钮布局一起挤压。
override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    translatesAutoresizingMaskIntoConstraints = false
    addSubview(backgroundView)
    addSubview(buttonsStackView)
    NSLayoutConstraint.activate([
        backgroundView.topAnchor.constraint(equalTo: topAnchor),
        backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
        backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
        backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
        buttonsStackView.topAnchor.constraint(equalTo: topAnchor, constant: CanvasToolbarChromeMetrics.verticalInset),
        buttonsStackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: CanvasToolbarChromeMetrics.horizontalInset),
        buttonsStackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -CanvasToolbarChromeMetrics.horizontalInset),
        buttonsStackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -CanvasToolbarChromeMetrics.verticalInset)
    ])
    updateDockEdgeLayout()
}
```

### 修改后

- iOS / macOS Host 都新增了 `contentClipView`。
- `buttonsStackView` 不再直接挂到 Host 根视图，而是挂到 `contentClipView` 内部。
- 同时移除了按钮栈到底部的强约束，只保留：
  - 顶部约束
  - 左右约束
- 这样后续外框缩高时，真正变化的是 Host 和 `contentClipView` 的可见区域，按钮栈内容被裁切，而不是被 Auto Layout 硬压缩。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
// 函数名: init(frame:)
// 功能说明: 修改后 iOS Host 引入 contentClipView，按钮栈转而挂在裁切层里，后续收拢到正方形时可以通过裁切隐藏底部内容，而不是压缩按钮约束。
private let contentClipView: iOSCanvasChromeOverlayView = {
    let view = iOSCanvasChromeOverlayView()
    view.translatesAutoresizingMaskIntoConstraints = false
    view.clipsToBounds = true
    return view
}()

override init(frame: CGRect) {
    super.init(frame: frame)
    translatesAutoresizingMaskIntoConstraints = false
    addSubview(backgroundView)
    addSubview(contentClipView)
    contentClipView.addSubview(buttonsStackView)
    NSLayoutConstraint.activate([
        backgroundView.topAnchor.constraint(equalTo: topAnchor),
        backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
        backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
        backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
        contentClipView.topAnchor.constraint(equalTo: topAnchor),
        contentClipView.leadingAnchor.constraint(equalTo: leadingAnchor),
        contentClipView.trailingAnchor.constraint(equalTo: trailingAnchor),
        contentClipView.bottomAnchor.constraint(equalTo: bottomAnchor),
        buttonsStackView.topAnchor.constraint(
            equalTo: contentClipView.topAnchor,
            constant: CanvasToolbarChromeMetrics.verticalInset
        ),
        buttonsStackView.leadingAnchor.constraint(
            equalTo: contentClipView.leadingAnchor,
            constant: CanvasToolbarChromeMetrics.horizontalInset
        ),
        buttonsStackView.trailingAnchor.constraint(
            equalTo: contentClipView.trailingAnchor,
            constant: -CanvasToolbarChromeMetrics.horizontalInset
        )
    ])
    updateDockEdgeLayout()
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// 函数名: init(frame:)
// 功能说明: 修改后 macOS Host 与 iOS 对称，引入 contentClipView 并启用 layer 裁切，让工具栏内容可在后续过渡中按可见区域被裁掉。
private let contentClipView: macOSCanvasChromeOverlayView = {
    let view = macOSCanvasChromeOverlayView()
    view.translatesAutoresizingMaskIntoConstraints = false
    view.layer?.masksToBounds = true
    return view
}()

override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    translatesAutoresizingMaskIntoConstraints = false
    addSubview(backgroundView)
    addSubview(contentClipView)
    contentClipView.addSubview(buttonsStackView)
    NSLayoutConstraint.activate([
        backgroundView.topAnchor.constraint(equalTo: topAnchor),
        backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
        backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
        backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
        contentClipView.topAnchor.constraint(equalTo: topAnchor),
        contentClipView.leadingAnchor.constraint(equalTo: leadingAnchor),
        contentClipView.trailingAnchor.constraint(equalTo: trailingAnchor),
        contentClipView.bottomAnchor.constraint(equalTo: bottomAnchor),
        buttonsStackView.topAnchor.constraint(
            equalTo: contentClipView.topAnchor,
            constant: CanvasToolbarChromeMetrics.verticalInset
        ),
        buttonsStackView.leadingAnchor.constraint(
            equalTo: contentClipView.leadingAnchor,
            constant: CanvasToolbarChromeMetrics.horizontalInset
        ),
        buttonsStackView.trailingAnchor.constraint(
            equalTo: contentClipView.trailingAnchor,
            constant: -CanvasToolbarChromeMetrics.horizontalInset
        )
    ])
    updateDockEdgeLayout()
}
```

## 修改二：为双端 Host 增加统一的 transition 渲染接口

### 修改前

- iOS / macOS Host 都只有 `render(_ state: CanvasToolbarState)` 这个 steady-state 入口。
- 这个入口会直接根据 `state.items.isEmpty` 切 `isHidden`，也只会消费 steady-state 的 `items` 和 `showsBackground`。
- 因此在 `Phase 2 / Phase 3` 到来之前，控制器没有办法把 `CanvasToolbarTransitionPresentation` 这种“过渡中的 frame/alpha/scale/可见性/交互性”交给 Host。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
// 函数名: render(_:)
// 功能说明: 修改前 iOS Host 只支持 steady-state CanvasToolbarState，无法承接过渡态 presentation。
func render(_ state: CanvasToolbarState) {
    preferredAxisOverride = state.preferredAxis
    dockEdge = state.placement.preferredEdge
    backgroundView.isHidden = state.showsBackground == false
    isHidden = state.items.isEmpty
    syncButtons(with: state.items)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// 函数名: render(_:)
// 功能说明: 修改前 macOS Host 同样只接受 steady-state CanvasToolbarState，无法直接消费 Phase 0 的过渡 presentation。
func render(_ state: CanvasToolbarState) {
    preferredAxisOverride = state.preferredAxis
    dockEdge = state.placement.preferredEdge
    backgroundView.isHidden = state.showsBackground == false
    isHidden = state.items.isEmpty
    syncButtons(with: state.items)
}
```

### 修改后

- 双端 Host 都新增：
  - `renderTransition(_:)`
  - `completeTransition(applying:)`
  - `cancelTransition(applying:)`
- steady-state `render(_:)` 仍然保留，但在进入 transition 时，Host 可以直接消费 `CanvasToolbarTransitionPresentation`。
- `renderTransition(_:)` 现在会真实应用：
  - `presentation.frame`
  - `presentation.itemStates`
  - `presentation.showsBackground`
  - `presentation.contentAlpha`
  - `presentation.contentScale`
  - `presentation.keepsHostVisible`
  - `presentation.isInteractive`

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
// 函数名: renderTransition(_:) / completeTransition(applying:) / cancelTransition(applying:)
// 功能说明: 修改后 iOS Host 正式具备 transition 渲染入口，后续控制器只需传入 CanvasToolbarTransitionPresentation 即可驱动过渡展示。
func renderTransition(_ presentation: CanvasToolbarTransitionPresentation) {
    isTransitionRendering = true
    transitionInteractivity = presentation.isInteractive
    backgroundView.isHidden = presentation.showsBackground == false
    if frame != presentation.frame {
        frame = presentation.frame
    }
    syncButtons(with: presentation.itemStates)
    applyContentTransitionAppearance(
        alpha: presentation.contentAlpha,
        scale: presentation.contentScale
    )
    isHidden = presentation.keepsHostVisible == false
}

func completeTransition(applying state: CanvasToolbarState) {
    isTransitionRendering = false
    render(state)
}

func cancelTransition(applying state: CanvasToolbarState) {
    isTransitionRendering = false
    render(state)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// 函数名: renderTransition(_:) / completeTransition(applying:) / cancelTransition(applying:)
// 功能说明: 修改后 macOS Host 与 iOS 对称，后续控制器可以直接向 Host 下发共享过渡 presentation，而不需要自己操作内部视图。
func renderTransition(_ presentation: CanvasToolbarTransitionPresentation) {
    isTransitionRendering = true
    transitionInteractivity = presentation.isInteractive
    backgroundView.isHidden = presentation.showsBackground == false
    if frame != presentation.frame {
        frame = presentation.frame
    }
    syncButtons(with: presentation.itemStates)
    applyContentTransitionAppearance(
        alpha: presentation.contentAlpha,
        scale: presentation.contentScale
    )
    isHidden = presentation.keepsHostVisible == false
}

func completeTransition(applying state: CanvasToolbarState) {
    isTransitionRendering = false
    render(state)
}

func cancelTransition(applying state: CanvasToolbarState) {
    isTransitionRendering = false
    render(state)
}
```

## 修改三：增加过渡期交互门控和内容外观应用

### 修改前

- iOS / macOS Host 的 `hitTest` 都是直接透传命中结果，没有过渡期交互门控。
- Host 内部也没有一个统一函数来应用内容 `alpha / scale`。
- 这意味着后续即使控制器有了 transition progress，也没有地方把“内容变淡、缩小、不可交互”稳定落到 Host 内部。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
// 函数名: hitTest(_:with:)
// 功能说明: 修改前 iOS Host 不区分 steady-state 与 transition-state，命中测试不会因为过渡态而被统一关闭。
override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    let hitView = super.hitTest(point, with: event)
    return hitView === self ? nil : hitView
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// 函数名: hitTest(_:)
// 功能说明: 修改前 macOS Host 也没有过渡期交互门控；后续如果直接上动画，过渡中的按钮仍可能响应命中。
override func hitTest(_ point: NSPoint) -> NSView? {
    let hitView = super.hitTest(point)
    return hitView === self ? nil : hitView
}
```

### 修改后

- 双端 Host 都新增：
  - `transitionInteractivity`
  - `applyContentTransitionAppearance(alpha:scale:)`
- `hitTest` 现在先看 `transitionInteractivity`，如果过渡态要求不可交互，直接返回 `nil`。
- `render(_:)` 会把内容恢复到 steady-state 的 `alpha = 1`、`scale = 1`。
- `renderTransition(_:)` 会按 presentation 里的值应用：
  - iOS：`buttonsStackView.alpha + transform`
  - macOS：`buttonsStackView.alphaValue + layer affine transform`

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
// 函数名: hitTest(_:with:) / applyContentTransitionAppearance(alpha:scale:)
// 功能说明: 修改后 iOS Host 可以在过渡期间统一禁用命中，并把内容透明度和缩放应用到按钮栈。
override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    guard transitionInteractivity else {
        return nil
    }
    let hitView = super.hitTest(point, with: event)
    return hitView === self ? nil : hitView
}

private func applyContentTransitionAppearance(
    alpha: CGFloat,
    scale: CGFloat
) {
    let clampedAlpha = min(max(alpha, 0), 1)
    let clampedScale = max(scale, 0)
    buttonsStackView.alpha = clampedAlpha
    buttonsStackView.transform = CGAffineTransform(
        scaleX: clampedScale,
        y: clampedScale
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// 函数名: hitTest(_:) / applyContentTransitionAppearance(alpha:scale:)
// 功能说明: 修改后 macOS Host 与 iOS 对称，在过渡期间可以统一关掉命中，并把 alpha / scale 落到按钮栈 layer。
override func hitTest(_ point: NSPoint) -> NSView? {
    guard transitionInteractivity else {
        return nil
    }
    let hitView = super.hitTest(point)
    return hitView === self ? nil : hitView
}

private func applyContentTransitionAppearance(
    alpha: CGFloat,
    scale: CGFloat
) {
    let clampedAlpha = min(max(alpha, 0), 1)
    let clampedScale = max(scale, 0)
    buttonsStackView.alphaValue = clampedAlpha
    buttonsStackView.layer?.setAffineTransform(
        CGAffineTransform(scaleX: clampedScale, y: clampedScale)
    )
}
```

## 修改四：保持本次改动边界只在 Host 层

### 修改前

- `Phase 1` 计划明确要求：
  - 只改 Host
  - 不接模式切换按钮
  - 不引入平台动画驱动
  - 不处理 layout reconcile

### 修改后

- 结合当前 `git status --short` 和本次 `git diff`，可以确认：
  - 只有 `iOSCanvasToolbarHostView.swift`、`macOSCanvasToolbarHostView.swift` 两个文件发生修改
  - 共享过渡 contract 文件、控制器文件、plan 文件都没有新增这一步的代码改动
- 因此本次代码状态仍严格落在 `Phase 1` 边界内：
  - Host 已可消费 `CanvasToolbarTransitionPresentation`
  - 控制器尚未开始编排 `beginToolbarModeTransition(...)`
  - 用户可见模式切换动画尚未接通

## 验证情况

- `ReadLints` 检查 Host 文件，无 linter 报错。
- 已执行构建校验：
  - `xcodebuild -scheme "MyCanvas_Ver_0" -project "MyCanvas_Ver_0.xcodeproj" -destination "generic/platform=iOS Simulator" build CODE_SIGNING_ALLOWED=NO`
  - `xcodebuild -scheme "MyCanvas_Ver_0" -project "MyCanvas_Ver_0.xcodeproj" -destination "platform=macOS" build CODE_SIGNING_ALLOWED=NO`
  - 结果：iOS / macOS 构建均通过。

## 当前结论

- 本次改动如实对应 `Phase 1`：
  - 双端 Host 已具备内容裁切层
  - 双端 Host 已具备 transition 渲染入口
  - 双端 Host 已具备过渡期交互门控与内容外观应用
- 但控制器尚未接入，所以当前实际产品行为仍是 steady-state；真正的阅读/编辑模式动画要到 `Phase 2` / `Phase 3` 才会出现。
