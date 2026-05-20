# 20260520_170834_markdown_scrollbar_record

## 记录范围

- 记录内容：
  - 在 markdown block 的共享渲染层上增加可见滚动条 UI chrome。
  - 滚动条只在 markdown 内容高度超过 viewport 高度时显示，并跟随已有的 `scrollOffsetY` 同步更新 thumb 位置。
- 涉及文件：
  - `MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownItemLayer.swift`
  - `MyCanvas_Ver_0Tests/CanvasMarkdownLayerTests.swift`
- 参考现状：
  - 本记录创建前，`git status --short` 显示当前工作区共有 `2` 个已跟踪代码文件处于修改状态。
  - `git diff --stat -- <本次相关文件>` 显示本次滚动条改动总计：`2 files changed, 172 insertions(+)`。
  - 本记录不包含任何 git 提交行为。

```bash
# 文件路径: /Users/shaun/cloudDev/MyCanvas_Ver_0
# 命令: date +"%Y%m%d_%H%M%S_markdown_scrollbar_record"
# 功能说明: 使用系统 date 命令生成本记录文件名的时间戳前缀。
20260520_170834_markdown_scrollbar_record
```

```bash
# 文件路径: /Users/shaun/cloudDev/MyCanvas_Ver_0
# 命令: git status --short
# 功能说明: 如实记录创建本记录前的当前工作区状态；以下 2 个文件属于这次 markdown 滚动条改动。
 M MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownItemLayer.swift
 M MyCanvas_Ver_0Tests/CanvasMarkdownLayerTests.swift
```

```bash
# 文件路径: /Users/shaun/cloudDev/MyCanvas_Ver_0
# 命令: git diff --stat -- "MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownItemLayer.swift" "MyCanvas_Ver_0Tests/CanvasMarkdownLayerTests.swift"
# 功能说明: 统计这次“markdown 可见滚动条”真实改动量，不直接贴原始 diff。
 .../Shared/Rendering/CanvasMarkdownItemLayer.swift | 152 +++++++++++++++++++++
 MyCanvas_Ver_0Tests/CanvasMarkdownLayerTests.swift |  20 +++
 2 files changed, 172 insertions(+)
```

## 当前 changes 摘要

- 这次没有去改 markdown bitmap 的绘制内容，也没有把滚动条烤进缓存图像。
- 滚动条是挂在 `CanvasMarkdownItemLayer` 上的 overlay layer，因此会跟着 item 的缩放、旋转、裁切一起工作。
- scrollbar 的显示条件依赖 `contentSize.height > logicalSize.height`，所以只有真正 overflow 的 markdown block 才会出现。
- scrollbar thumb 的位置不自己维护独立状态，而是直接由当前已经存在的 `scrollOffsetY` 推导，保证和内部滚动语义一致。

## 修改一：在共享 item layer 上增加滚动条 layer

### 1.1 修改前

- `CanvasMarkdownItemLayer` 只持有 `contentLayer`，负责容器几何、旋转缩放和内容 layer 挂载。
- `update(...)` 在内容层更新后直接结束，没有针对 overflow 状态去计算任何滚动条 UI。
- `configureLayer()` 也只会把 `contentLayer` 挂到 item layer 上。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownItemLayer.swift（修改前摘要）
// 函数名/类型: CanvasMarkdownItemLayer / update(with:markdownPayload:contentsScale:) / configureLayer()
// 功能说明: 修改前 item layer 只托管 markdown 内容层，不持有滚动条 track/thumb，也不会根据 overflow 状态补 UI chrome。
final class CanvasMarkdownItemLayer: CALayer {
    let itemID: CanvasItemID
    let contentLayer: CanvasMarkdownContentLayer

    func update(
        with item: CanvasRenderItem,
        markdownPayload: CanvasMarkdownRenderPayload,
        contentsScale: CGFloat
    ) {
        // ... 更新 bounds / position / transform / zPosition ...
        contentLayer.update(
            with: markdownPayload,
            contentsScale: contentsScale
        )
    }

    private func configureLayer() {
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        masksToBounds = true
        if contentLayer.superlayer !== self {
            addSublayer(contentLayer)
        }
    }
}
```

### 1.2 修改后

- `CanvasMarkdownItemLayer` 新增 `scrollbarTrackLayer`、`scrollbarThumbLayer`，并引入 `ScrollbarMetrics` 缓存上次几何结果。
- `update(...)` 在 `contentLayer.update(...)` 之后，使用 `contentLayer.bounds.size` 和 `contentLayer.position.y` 反推当前滚动条状态。
- `configureLayer()` 统一配置 track/thumb 的颜色、裁切和挂载关系，让滚动条作为 item layer 的 overlay 存在。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownItemLayer.swift
// 函数名/类型: CanvasMarkdownItemLayer / update(with:markdownPayload:contentsScale:) / configureLayer()
// 功能说明: 修改后 item layer 除了托管内容层，还托管 scrollbar track/thumb；滚动条不会进入 markdown bitmap 缓存，只作为独立 overlay 渲染。
final class CanvasMarkdownItemLayer: CALayer {
    private static let scrollbarVisibilityEpsilon: CGFloat = 0.5
    private static let preferredScrollbarThickness: CGFloat = 4
    private static let minimumScrollbarThickness: CGFloat = 2
    private static let preferredScrollbarInset: CGFloat = 3

    private struct ScrollbarMetrics: Equatable {
        let trackFrame: CGRect
        let thumbFrame: CGRect
    }

    let itemID: CanvasItemID
    let contentLayer: CanvasMarkdownContentLayer
    let scrollbarTrackLayer: CALayer
    let scrollbarThumbLayer: CALayer

    func update(
        with item: CanvasRenderItem,
        markdownPayload: CanvasMarkdownRenderPayload,
        contentsScale: CGFloat
    ) {
        // ... 更新 bounds / position / transform / zPosition ...
        contentLayer.update(
            with: markdownPayload,
            contentsScale: contentsScale
        )
        applyScrollbar(
            logicalSize: markdownPayload.logicalSize,
            contentSize: contentLayer.bounds.size,
            scrollOffsetY: max(-contentLayer.position.y, 0)
        )
    }

    private func configureLayer() {
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        masksToBounds = true
        if contentLayer.superlayer !== self {
            addSublayer(contentLayer)
        }
        configureScrollbarLayer(scrollbarTrackLayer)
        configureScrollbarLayer(scrollbarThumbLayer)
        if scrollbarTrackLayer.superlayer !== self {
            addSublayer(scrollbarTrackLayer)
        }
        if scrollbarThumbLayer.superlayer !== self {
            addSublayer(scrollbarThumbLayer)
        }
    }
}
```

## 修改二：根据 overflow 和 `scrollOffsetY` 计算 scrollbar 几何

### 2.1 修改前

- markdown 内部滚动已经存在，但可见 UI 只有内容位移，没有滚动条几何。
- 因为没有 track/thumb 计算逻辑，所以用户无法从 UI 上判断当前 block 是否 overflow、也无法判断自己已经滚到了哪一段。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownItemLayer.swift（修改前摘要）
// 函数名/类型: CanvasMarkdownItemLayer
// 功能说明: 修改前没有任何 scrollbar metrics、显示/隐藏、thumb 高度或 thumb 位置计算逻辑。
final class CanvasMarkdownItemLayer: CALayer {
    // 只有 item 几何与 content layer 更新逻辑。
}
```

### 2.2 修改后

- `resolvedScrollbarMetrics(...)` 先检查是否真的 overflow；如果内容高度没有超出 viewport，则直接返回 `nil`，上层会隐藏滚动条。
- thumb 高度按 `viewportHeight / contentHeight` 比例计算，同时保留一个最小高度，避免长文档下 thumb 小到不可见。
- thumb 位置按 `scrollOffsetY / maxScrollOffsetY` 线性映射到 track 可移动区间，和真实内部滚动进度保持一致。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasMarkdownItemLayer.swift
// 函数名/类型: applyScrollbar(logicalSize:contentSize:scrollOffsetY:) / resolvedScrollbarMetrics(logicalSize:contentSize:scrollOffsetY:) / resolvedScrollbarThickness(forLogicalWidth:)
// 功能说明: 修改后滚动条几何完全由 viewport 尺寸、全文内容尺寸和当前 scrollOffsetY 推导；无 overflow 时隐藏，有 overflow 时按比例更新 thumb。
private func applyScrollbar(
    logicalSize: CGSize,
    contentSize: CGSize,
    scrollOffsetY: CGFloat
) {
    guard let metrics = resolvedScrollbarMetrics(
        logicalSize: logicalSize,
        contentSize: contentSize,
        scrollOffsetY: scrollOffsetY
    ) else {
        scrollbarTrackLayer.isHidden = true
        scrollbarThumbLayer.isHidden = true
        lastAppliedScrollbarMetrics = nil
        return
    }

    if lastAppliedScrollbarMetrics != metrics {
        scrollbarTrackLayer.frame = metrics.trackFrame
        scrollbarTrackLayer.cornerRadius = metrics.trackFrame.width / 2
        scrollbarThumbLayer.frame = metrics.thumbFrame
        scrollbarThumbLayer.cornerRadius = metrics.thumbFrame.width / 2
        lastAppliedScrollbarMetrics = metrics
    }
    scrollbarTrackLayer.isHidden = false
    scrollbarThumbLayer.isHidden = false
}

private func resolvedScrollbarMetrics(
    logicalSize: CGSize,
    contentSize: CGSize,
    scrollOffsetY: CGFloat
) -> ScrollbarMetrics? {
    guard
        logicalSize.width > 0,
        logicalSize.height > 0,
        contentSize.height - logicalSize.height > Self.scrollbarVisibilityEpsilon
    else {
        return nil
    }

    let thickness = resolvedScrollbarThickness(forLogicalWidth: logicalSize.width)
    let horizontalInset = min(
        Self.preferredScrollbarInset,
        max((logicalSize.width - thickness) / 2, 0)
    )
    let verticalInset = min(
        Self.preferredScrollbarInset,
        max((logicalSize.height - thickness) / 2, 0)
    )
    let trackHeight = logicalSize.height - (verticalInset * 2)
    guard trackHeight > 0 else {
        return nil
    }

    let maxScrollOffsetY = max(contentSize.height - logicalSize.height, 0)
    guard maxScrollOffsetY > Self.scrollbarVisibilityEpsilon else {
        return nil
    }

    let minimumThumbHeight = min(trackHeight, thickness * 2)
    let proportionalThumbHeight = trackHeight * (logicalSize.height / contentSize.height)
    let thumbHeight = min(
        max(proportionalThumbHeight, minimumThumbHeight),
        trackHeight
    )
    let thumbTravel = max(trackHeight - thumbHeight, 0)
    let progress = min(max(scrollOffsetY / maxScrollOffsetY, 0), 1)
    let trackX = max(logicalSize.width - horizontalInset - thickness, 0)
    let trackY = verticalInset
    let thumbY = trackY + (thumbTravel * progress)
    return ScrollbarMetrics(
        trackFrame: CGRect(
            x: trackX,
            y: trackY,
            width: thickness,
            height: trackHeight
        ),
        thumbFrame: CGRect(
            x: trackX,
            y: thumbY,
            width: thickness,
            height: thumbHeight
        )
    )
}
```

## 修改三：补齐 layer 回归测试，覆盖隐藏/显示与底部位置

### 3.1 修改前

- `CanvasMarkdownLayerTests` 只验证 markdown item layer 的内容层挂载、layout 尺寸、bitmap raster 与滚动位移。
- 没有任何测试去约束滚动条在“无 overflow”时应该隐藏，也没有验证“滚到最大值时 thumb 应该在轨道底部”。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasMarkdownLayerTests.swift（修改前摘要）
// 函数名/类型: testItemLayerUsesLogicalBoundsAndCameraScaleTransform() / testContentLayerOffsetsBitmapByClampedScrollOffset()
// 功能说明: 修改前测试关注点只有内容层与位图滚动，没有 scrollbar layer 的可见性和几何断言。
XCTAssertTrue(layer.masksToBounds)
XCTAssertTrue(layer.contentLayer.superlayer === layer)
XCTAssertEqual(layer.contentLayer.bounds.size, expectedLayout.contentSize)

XCTAssertEqual(
    layer.contentLayer.position.y,
    -expectedMaxScrollOffsetY,
    accuracy: 0.0001
)
```

### 3.2 修改后

- `testItemLayerUsesLogicalBoundsAndCameraScaleTransform()` 现在额外断言 scrollbar track/thumb 已挂到 item layer 上，并且在无 overflow 时保持隐藏。
- `testContentLayerOffsetsBitmapByClampedScrollOffset()` 现在额外断言 scrollbar 会显示、thumb 比 track 短，并且在滚动到最大偏移时对齐轨道底部。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasMarkdownLayerTests.swift
// 函数名/类型: testItemLayerUsesLogicalBoundsAndCameraScaleTransform() / testContentLayerOffsetsBitmapByClampedScrollOffset()
// 功能说明: 修改后测试把 scrollbar layer 的挂载关系、隐藏条件和最大滚动位置的 thumb 几何一起纳入回归约束。
XCTAssertTrue(layer.masksToBounds)
XCTAssertTrue(layer.contentLayer.superlayer === layer)
XCTAssertTrue(layer.scrollbarTrackLayer.superlayer === layer)
XCTAssertTrue(layer.scrollbarThumbLayer.superlayer === layer)
XCTAssertTrue(layer.scrollbarTrackLayer.isHidden)
XCTAssertTrue(layer.scrollbarThumbLayer.isHidden)

XCTAssertEqual(
    layer.contentLayer.position.y,
    -expectedMaxScrollOffsetY,
    accuracy: 0.0001
)
XCTAssertFalse(layer.scrollbarTrackLayer.isHidden)
XCTAssertFalse(layer.scrollbarThumbLayer.isHidden)
XCTAssertLessThan(
    layer.scrollbarThumbLayer.frame.height,
    layer.scrollbarTrackLayer.frame.height
)
XCTAssertEqual(
    layer.scrollbarThumbLayer.frame.maxY,
    layer.scrollbarTrackLayer.frame.maxY,
    accuracy: 0.0001
)
```

## 验证

```bash
# 文件路径: /Users/shaun/cloudDev/MyCanvas_Ver_0
# 命令: xcodebuild test -scheme "MyCanvas_Ver_0" -project "MyCanvas_Ver_0.xcodeproj" -destination 'platform=macOS' -only-testing:MyCanvas_Ver_0Tests/CanvasMarkdownLayerTests -only-testing:MyCanvas_Ver_0Tests/CanvasMarkdownContractTests
# 功能说明: 定向验证 markdown layer 与 markdown contract 回归，确认滚动条接入没有破坏现有 markdown 渲染/滚动合同。
# 结果: success（exit code 0）
```

```bash
# 文件路径: /Users/shaun/cloudDev/MyCanvas_Ver_0
# 命令: xcodebuild build -scheme "MyCanvas_Ver_0" -project "MyCanvas_Ver_0.xcodeproj" -destination 'generic/platform=iOS'
# 功能说明: 验证共享 layer 改动在 iOS 目标上可以正常编译通过。
# 结果: success（exit code 0）
```

## 结果说明

- 这次记录的“滚动条”改动没有改变 markdown 的内容测量、bitmap raster 和 `scrollOffsetY` 持久化合同，只是在共享 item layer 上增加了可见滚动条 UI。
- 因为滚动条几何直接从 `contentSize`、`logicalSize` 和 `scrollOffsetY` 推导，所以它天然和已有的 resize、内部滚动、撤销重做行为保持一致。
