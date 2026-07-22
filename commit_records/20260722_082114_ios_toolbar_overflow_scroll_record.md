# 20260722_082114_iOS 底部工具条横向滚动与底边动画修复记录

## 记录范围

本记录根据当前 `git diff` 与 working tree changes 整理，记录刚刚针对 iOS 底部横向工具条无法容纳内容时的 `overflow-x: scroll` 行为，以及阅读态/编辑态切换时底边离屏动画的根因修复。

当前涉及文件：

- `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift`
- `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- `MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarTransitionGeometry.swift`
- `MyCanvas_Ver_0Tests/CanvasToolbarPlacementPassTests.swift`

## 1. iOS 工具条内容容器支持横向滚动

### 修改前

按钮栈直接挂在 `contentClipView` 上。横向工具条内容超过宿主宽度时，布局系统只能裁剪或压缩约束，没有可滚动的内容区域。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
// 函数名: init(frame:)
// 功能说明: 修改前按钮栈直接放入裁剪容器，无法表达横向 overflow scroll。
addSubview(backgroundView)
addSubview(contentClipView)
contentClipView.addSubview(buttonsStackView)
NSLayoutConstraint.activate([
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
```

### 修改后

新增 `UIScrollView` 作为内容滚动容器，按钮栈绑定到 `contentLayoutGuide`；横向模式激活固定高度约束，让内容宽度可以超过 `frameLayoutGuide` 后横向滚动。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
// 函数名: init(frame:)
// 功能说明: 修改后通过 UIScrollView 承载按钮栈，横向内容超出宿主宽度时进入横向滚动。
addSubview(backgroundView)
addSubview(contentClipView)
contentClipView.addSubview(contentScrollView)
contentScrollView.addSubview(buttonsStackView)

let horizontalStackHeightConstraint = buttonsStackView.heightAnchor.constraint(
    equalTo: contentScrollView.frameLayoutGuide.heightAnchor,
    constant: -(CanvasToolbarChromeMetrics.verticalInset * 2)
)
let verticalStackWidthConstraint = buttonsStackView.widthAnchor.constraint(
    equalTo: contentScrollView.frameLayoutGuide.widthAnchor,
    constant: -(CanvasToolbarChromeMetrics.horizontalInset * 2)
)
self.horizontalStackHeightConstraint = horizontalStackHeightConstraint
self.verticalStackWidthConstraint = verticalStackWidthConstraint

NSLayoutConstraint.activate([
    contentScrollView.topAnchor.constraint(equalTo: contentClipView.topAnchor),
    contentScrollView.leadingAnchor.constraint(equalTo: contentClipView.leadingAnchor),
    contentScrollView.trailingAnchor.constraint(equalTo: contentClipView.trailingAnchor),
    contentScrollView.bottomAnchor.constraint(equalTo: contentClipView.bottomAnchor),
    buttonsStackView.topAnchor.constraint(
        equalTo: contentScrollView.contentLayoutGuide.topAnchor,
        constant: CanvasToolbarChromeMetrics.verticalInset
    ),
    buttonsStackView.leadingAnchor.constraint(
        equalTo: contentScrollView.contentLayoutGuide.leadingAnchor,
        constant: CanvasToolbarChromeMetrics.horizontalInset
    ),
    buttonsStackView.trailingAnchor.constraint(
        equalTo: contentScrollView.contentLayoutGuide.trailingAnchor,
        constant: -CanvasToolbarChromeMetrics.horizontalInset
    ),
    buttonsStackView.bottomAnchor.constraint(
        equalTo: contentScrollView.contentLayoutGuide.bottomAnchor,
        constant: -CanvasToolbarChromeMetrics.verticalInset
    )
])
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
// 函数名: updateDockEdgeLayout()
// 功能说明: 根据工具条方向切换滚动轴与约束，横向工具条启用 horizontal scroll。
let preferredAxis = preferredAxisOverride ?? dockEdge.preferredAxis
let isHorizontal = preferredAxis == .horizontal
let previousAxis = buttonsStackView.axis
buttonsStackView.axis = preferredAxis == .horizontal
    ? .horizontal
    : .vertical
buttonsStackView.alignment = preferredAxis == .horizontal
    ? .center
    : .trailing
horizontalStackHeightConstraint?.isActive = isHorizontal
verticalStackWidthConstraint?.isActive = isHorizontal == false
contentScrollView.alwaysBounceHorizontal = isHorizontal
contentScrollView.alwaysBounceVertical = isHorizontal == false
contentScrollView.showsHorizontalScrollIndicator = isHorizontal
contentScrollView.showsVerticalScrollIndicator = isHorizontal == false

if previousAxis != buttonsStackView.axis {
    contentScrollView.setContentOffset(.zero, animated: false)
}
```

## 2. iOS 底部工具条测量宽度钳制到可用区域

### 修改前

`measuredToolbarHostSize()` 直接返回工具条完整内容尺寸。底部横向工具条按钮较多时，测量宽度可能超过安全区域减去 edge inset 后的可布局宽度，导致 placement solver 返回 `.zero`，表现为工具条落到左上角或不展开。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: measuredToolbarHostSize()
// 功能说明: 修改前直接使用完整内容尺寸，横向内容过宽时会让 placement 无法求解。
private func measuredToolbarHostSize() -> CGSize {
    CanvasChromeLayoutGeometry.sanitizedSize(
        toolbarHostView.measuredContentSize()
    )
}
```

### 修改后

新增 `constrainedToolbarMeasuredSize(_:for:)`，按 dock edge 钳制主轴尺寸。对于 `.top` / `.bottom`，宽度最多为安全区域内的布局宽度，超出的按钮内容交给 scroll view 横向滚动。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: measuredToolbarHostSize()
// 功能说明: 修改后先保留实际内容测量，再按工具条停靠边钳制宿主尺寸。
private func measuredToolbarHostSize() -> CGSize {
    constrainedToolbarMeasuredSize(
        CanvasChromeLayoutGeometry.sanitizedSize(
            toolbarHostView.measuredContentSize()
        ),
        for: toolbarPreferredPlacement()
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: constrainedToolbarMeasuredSize(_:for:)
// 功能说明: 底部/顶部横向工具条只钳制宿主宽度，内容超出部分由内部 UIScrollView 处理。
private func constrainedToolbarMeasuredSize(
    _ measuredSize: CGSize,
    for placement: CanvasToolbarPlacement
) -> CGSize {
    let sanitizedSize = CanvasChromeLayoutGeometry.sanitizedSize(
        measuredSize
    )
    guard
        sanitizedSize.width > 0,
        sanitizedSize.height > 0,
        let safeBounds = CanvasChromeLayoutGeometry.sanitizedRect(
            toolbarLayoutSafeBounds()
        )
    else {
        return sanitizedSize
    }

    let configuration = CanvasToolbarPlacementConfiguration()
    let inset = max(configuration.edgeInset, 0)
    let layoutBounds = CanvasChromeLayoutGeometry.sanitizedRect(
        safeBounds.insetBy(dx: inset, dy: inset)
    ) ?? safeBounds

    switch placement.preferredEdge {
    case .top, .bottom:
        return CGSize(
            width: min(sanitizedSize.width, layoutBounds.width),
            height: sanitizedSize.height
        )
    case .leading, .trailing:
        return CGSize(
            width: sanitizedSize.width,
            height: min(sanitizedSize.height, layoutBounds.height)
        )
    }
}
```

## 3. 工具条离屏方向改为按停靠边计算

### 修改前

`offscreenFrame(from:safeBounds:)` 默认只向右侧移动，适合右侧竖向工具条，但不适合底部工具条。底部工具条在阅读态隐藏时仍按 X 方向离屏，会导致边框残留在右上角一类错误表现。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarTransitionGeometry.swift
// 函数名: offscreenFrame(from:safeBounds:)
// 功能说明: 修改前离屏方向固定为右侧，未根据 preferredEdge 调整。
static func offscreenFrame(
    from collapsedFrame: CGRect,
    safeBounds: CGRect
) -> CGRect {
    let safeBoundsMaxX = CanvasChromeLayoutGeometry
        .sanitizedRect(safeBounds)?
        .maxX ?? baseFrame.maxX
    return CGRect(
        x: max(baseFrame.minX, safeBoundsMaxX),
        y: baseFrame.minY,
        width: baseFrame.width,
        height: baseFrame.height
    ).standardized
}
```

### 修改后

保留旧签名作为 trailing 默认兼容入口，并新增带 `placement` 的重载。`.bottom` 现在从安全区域底边外侧离屏，`.top` / `.leading` / `.trailing` 也分别按各自停靠边计算。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarTransitionGeometry.swift
// 函数名: offscreenFrame(from:safeBounds:placement:)
// 功能说明: 根据工具条停靠边计算离屏目标，底部工具条沿 Y 轴移出底边。
static func offscreenFrame(
    from collapsedFrame: CGRect,
    safeBounds: CGRect,
    placement: CanvasToolbarPlacement
) -> CGRect {
    let baseFrame = sanitizedRectOrFallback(
        collapsedFrame,
        fallbackOrigin: finiteOrigin(from: collapsedFrame.origin),
        fallbackSize: CGSize(
            width: collapsedSquareEdge(from: collapsedFrame),
            height: collapsedSquareEdge(from: collapsedFrame)
        )
    )
    let sanitizedSafeBounds = CanvasChromeLayoutGeometry
        .sanitizedRect(safeBounds)
    let origin: CGPoint

    switch placement.preferredEdge {
    case .top:
        origin = CGPoint(
            x: baseFrame.minX,
            y: min(
                baseFrame.minY,
                (sanitizedSafeBounds?.minY ?? baseFrame.minY) - baseFrame.height
            )
        )
    case .bottom:
        origin = CGPoint(
            x: baseFrame.minX,
            y: max(
                baseFrame.minY,
                sanitizedSafeBounds?.maxY ?? baseFrame.maxY
            )
        )
    case .leading:
        origin = CGPoint(
            x: min(
                baseFrame.minX,
                (sanitizedSafeBounds?.minX ?? baseFrame.minX) - baseFrame.width
            ),
            y: baseFrame.minY
        )
    case .trailing:
        origin = CGPoint(
            x: max(
                baseFrame.minX,
                sanitizedSafeBounds?.maxX ?? baseFrame.maxX
            ),
            y: baseFrame.minY
        )
    }

    return CGRect(
        origin: origin,
        size: baseFrame.size
    ).standardized
}
```

## 4. 横向工具条折叠方块尺寸修正

### 修改前

折叠方块边长使用 `visibleFrame.width`。这对右侧竖向工具条成立，但对底部横向工具条会把整条工具条宽度当作折叠方块边长，造成折叠态过大。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarTransitionGeometry.swift
// 函数名: collapsedSquareEdge(from:)
// 功能说明: 修改前横向工具条折叠时错误使用宽度作为方块边长。
private static func collapsedSquareEdge(from visibleFrame: CGRect) -> CGFloat {
    if let sanitizedVisibleFrame = CanvasChromeLayoutGeometry.sanitizedRect(
        visibleFrame
    ) {
        return sanitizedVisibleFrame.width
    }
}
```

### 修改后

折叠方块边长改用可见 frame 的短边。竖向工具条仍得到原来的宽度，横向底部工具条则使用高度作为方块边长。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarTransitionGeometry.swift
// 函数名: collapsedSquareEdge(from:)
// 功能说明: 使用短边生成折叠方块，兼容竖向与横向工具条。
private static func collapsedSquareEdge(from visibleFrame: CGRect) -> CGFloat {
    if let sanitizedVisibleFrame = CanvasChromeLayoutGeometry.sanitizedRect(
        visibleFrame
    ) {
        return min(sanitizedVisibleFrame.width, sanitizedVisibleFrame.height)
    }
}
```

## 5. iOS 切换动画进度按工具条方向计算

### 修改前

iOS 切换阶段推断固定使用高度判断展开/折叠，固定使用 `minX` 判断进入/退出。底部横向工具条应使用宽度表示展开进度、使用 `minY` 表示底边滑入/滑出进度。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: initialToolbarTransitionStage(for:context:)
// 功能说明: 修改前动画阶段推断假设工具条沿 X 轴离屏、沿高度折叠。
let isCollapsed = currentFrame.height <= (collapsedFrame.height + 0.5)
let enteringProgress = toolbarLinearProgress(
    from: context.frames.offscreenFrame.minX,
    to: collapsedFrame.minX,
    current: currentFrame.minX
)
```

### 修改后

新增 `toolbarExpansionExtent(_:for:)` 与 `toolbarSlideCoordinate(_:for:)`，根据 `.top` / `.bottom` / `.leading` / `.trailing` 选择宽高和 X/Y 坐标。底部工具条现在按宽度展开，按 Y 坐标从底边滑入/滑出。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: toolbarExpansionExtent(_:for:)
// 功能说明: 根据停靠边选择展开维度，底部横向工具条使用 width。
private func toolbarExpansionExtent(
    _ frame: CGRect,
    for placement: CanvasToolbarPlacement
) -> CGFloat {
    switch placement.preferredEdge {
    case .top, .bottom:
        return frame.width
    case .leading, .trailing:
        return frame.height
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: toolbarSlideCoordinate(_:for:)
// 功能说明: 根据停靠边选择滑动坐标，底部横向工具条使用 minY。
private func toolbarSlideCoordinate(
    _ frame: CGRect,
    for placement: CanvasToolbarPlacement
) -> CGFloat {
    switch placement.preferredEdge {
    case .top, .bottom:
        return frame.minY
    case .leading, .trailing:
        return frame.minX
    }
}
```

## 6. 单元测试补充

新增测试覆盖两个关键不变量：

- 横向工具条折叠方块使用短边。
- 底部工具条隐藏帧从底边移出，而不是从右侧移出。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasToolbarPlacementPassTests.swift
// 函数名: testCollapsedFrameUsesShortEdgeForHorizontalToolbar()
// 功能说明: 验证底部横向工具条折叠后是高度大小的方块，而不是整条宽度大小的方块。
func testCollapsedFrameUsesShortEdgeForHorizontalToolbar() {
    let visibleFrame = CGRect(x: 20, y: 720, width: 350, height: 64)

    let collapsedFrame = CanvasToolbarTransitionGeometry.collapsedFrame(
        from: visibleFrame
    )

    XCTAssertEqual(collapsedFrame.origin, visibleFrame.origin)
    XCTAssertEqual(collapsedFrame.width, visibleFrame.height)
    XCTAssertEqual(collapsedFrame.height, visibleFrame.height)
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasToolbarPlacementPassTests.swift
// 函数名: testResolveDerivesBottomHiddenFrameFromVisibleToolbarFrame()
// 功能说明: 验证底部工具条隐藏帧沿底边离屏，并保留折叠方块尺寸。
func testResolveDerivesBottomHiddenFrameFromVisibleToolbarFrame() throws {
    let safeBounds = CGRect(x: 0, y: 0, width: 390, height: 844)
    let result = CanvasToolbarPlacementPass.resolve(
        safeBounds: safeBounds,
        toolbarPreferredPlacement: CanvasToolbarPlacement(
            preferredEdge: .bottom
        ),
        toolbarMeasuredSize: CGSize(width: 350, height: 64),
        baseChromeBlockers: [],
        scale: 3
    )

    let visibleFrame = try XCTUnwrap(
        CanvasChromeLayoutGeometry.sanitizedRect(result.toolbarFrame)
    )

    XCTAssertEqual(result.hiddenToolbarFrame.minX, visibleFrame.minX)
    XCTAssertEqual(result.hiddenToolbarFrame.minY, safeBounds.maxY)
    XCTAssertEqual(result.hiddenToolbarFrame.width, visibleFrame.height)
    XCTAssertEqual(result.hiddenToolbarFrame.height, visibleFrame.height)
}
```

## 验证情况

已执行并通过：

- `xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS,arch=arm64' -only-testing:MyCanvas_Ver_0Tests/CanvasToolbarPlacementPassTests`
- `xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.1'`

曾尝试使用 `iPhone 16` 模拟器执行 iOS 测试，但本机没有该模拟器；改用 Xcode 当前可用的 `iPhone 17, OS=26.1` 做 iOS Simulator build。

本次仅创建记录文件，没有提交 commit。
