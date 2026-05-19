# 20260519_205736_markdown_bitmap_phase0_contract_record

## 记录范围

- 记录内容：
  - 实施 `@.cursor/plans/markdown位图重构_bb0734a4.plan.md` 的阶段 0。
  - 本阶段目标不是提前切换 markdown 渲染架构，而是先冻结不能破坏的模型契约、渲染几何契约和编辑链语义，并补上后续迁移要依赖的回归测试基线。
  - 本次实际改动包括：为 `CanvasMarkdownItem`、`CanvasMarkdownRenderPayload`、`CanvasRenderItem`、`CanvasRenderer.makeMarkdownRenderItem(...)`、`CanvasEditorSession.measuredMarkdownItemSize(...)` 增补契约注释；新增 `CanvasMarkdownContractTests` 锁定阶段 0 回归基线。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasBoardItem.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
  - `MyCanvas_Ver_0Tests/CanvasMarkdownContractTests.swift`
- 参考现状：
  - `git status --short` 显示本次阶段 0 相关变更为 `4` 个已跟踪修改文件和 `1` 个未跟踪新增测试文件。
  - `git diff --stat` 显示已跟踪文件的变化为：`4 files changed, 14 insertions(+), 2 deletions(-)`。
  - 由于 `MyCanvas_Ver_0Tests/CanvasMarkdownContractTests.swift` 是新增未跟踪文件，它不会出现在这条 `git diff --stat` 输出里，但已经出现在 `git status --short` 中。
- 本记录不包含：
  - `@.cursor/plans/markdown位图重构_bb0734a4.plan.md` 的内容改动。
  - 任何 git 提交行为。

```bash
# 命令: git status --short
 M MyCanvas_Ver_0/Canvas/Core/CanvasBoardItem.swift
 M MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
 M MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
 M MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
?? MyCanvas_Ver_0Tests/CanvasMarkdownContractTests.swift
```

```bash
# 命令: git diff --stat -- MyCanvas_Ver_0/Canvas/Core/CanvasBoardItem.swift MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
 MyCanvas_Ver_0/Canvas/Core/CanvasBoardItem.swift        | 6 ++++--
 MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift   | 4 ++++
 MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift         | 3 +++
 MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift | 3 +++
 4 files changed, 14 insertions(+), 2 deletions(-)
```

## 当前 changes 摘要

- `CanvasMarkdownItem.size` 的语义从“有一个显式 frame”提升为更严格的模型层契约：`width` 是持久化布局宽度来源，`height` 是提交后的容器/裁剪高度，允许与当前内容的 intrinsic height 分离。
- `CanvasMarkdownRenderPayload` 与 `CanvasRenderItem` 新增了说明性注释，明确 markdown 的临时布局产物仍停留在渲染层，不允许反向污染文档模型；同时 `screenQuad`、`screenFrame`、`screenCenter`、`screenBoundsSize` 继续作为共享几何契约存在。
- `CanvasRenderer.makeMarkdownRenderItem(...)` 没有改变几何计算公式，但补充了“屏幕几何仍然必须来源于 world geometry”的契约说明，用于约束后续 `ItemLayer + ContentLayer` 位图化迁移。
- `CanvasEditorSession` 明确了 markdown 仍从固定默认宽度启动，并且编辑回写流程继续执行“保宽重测高”的逻辑。
- 新增 `CanvasMarkdownContractTests`，把模型容器高度、编辑保宽重测高、snapshot 屏幕几何映射三个阶段 0 基线锁成回归测试。

## 修改一：冻结 `CanvasMarkdownItem.size` 的模型层容器语义

### 1.1 修改前

- `CanvasMarkdownItem.size` 只有“显式 frame”这一层较宽泛的说明。
- 注释没有明确区分“布局宽度来源”和“容器高度/裁剪高度”，后续如果直接把 intrinsic layout height 回写进模型层，表面上也不会违反文字描述。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasBoardItem.swift（修改前）
// 函数名: CanvasMarkdownItem（类型定义）
// 功能说明: 修改前只说明 markdown 有一个持久化的显式 frame，没有明确 width 和 height 在后续位图重构里的约束边界。
struct CanvasMarkdownItem {
    let id: CanvasItemID
    var markdownSource: String
    var style: CanvasTextStyle
    var center: CGPoint
    // Markdown keeps an explicit canvas container size. Later phases may reflow
    // content inside this box, but phase 1 only needs a persisted frame.
    var size: CGSize
    var zIndex: CGFloat
    var rotationRadians: CGFloat
}
```

### 1.2 修改后

- `size.width` 被明确冻结为持久化布局宽度来源。
- `size.height` 被明确冻结为提交后的容器/裁剪高度，允许和当前文本 intrinsic height 不一致，从而给后续“内容位图层 + 外部几何缩放”迁移留下稳定模型边界。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasBoardItem.swift
// 函数名: CanvasMarkdownItem（类型定义）
// 功能说明: 修改后显式冻结 markdown 容器几何契约，防止后续布局缓存或 intrinsic size 直接反向改写模型字段。
struct CanvasMarkdownItem {
    let id: CanvasItemID
    var markdownSource: String
    var style: CanvasTextStyle
    var center: CGPoint
    // Markdown keeps explicit canvas container geometry in the model. Width is
    // the persisted layout width source; height is the committed container or
    // clip height and may intentionally differ from the current intrinsic
    // content height after manual resize.
    var size: CGSize
    var zIndex: CGFloat
    var rotationRadians: CGFloat
}
```

## 修改二：冻结 render payload 与共享屏幕几何的边界

### 2.1 修改前

- `CanvasMarkdownRenderPayload` 只有字段，没有说明它是纯渲染期数据。
- `CanvasRenderItem` 也没有显式说明 `screenQuad`、`screenFrame`、`screenCenter`、`screenBoundsSize` 是选区、命中、accessory anchor 等公共消费方依赖的共享契约。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift（修改前）
// 函数名: CanvasMarkdownRenderPayload / CanvasRenderItem（类型定义）
// 功能说明: 修改前 render payload 与 screen geometry 的存在方式偏“事实实现”，没有把它们写成后续迁移不可破坏的边界。
struct CanvasMarkdownRenderPayload {
    let markdownSource: String
    let style: CanvasTextStyle
    let zoomScale: CGFloat
}

struct CanvasRenderItem {
    let id: CanvasItemID
    let screenFrame: CGRect
    let screenQuad: CanvasQuad
    let screenCenter: CGPoint
    let screenBoundsSize: CGSize
    let rotationRadians: CGFloat
    let zIndex: CGFloat
    let payload: CanvasRenderPayload
}
```

### 2.2 修改后

- `CanvasMarkdownRenderPayload` 被显式约束为 render-time 数据，不允许把未来 bitmap cache 或中间 layout 结构塞回文档模型。
- `CanvasRenderItem` 被显式定义为跨 viewport / overlay / hit-testing 共享的几何契约，这使后续 markdown 内容层重构只能替换内容承载方式，不能破坏几何输出。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
// 函数名: CanvasMarkdownRenderPayload / CanvasRenderItem（类型定义）
// 功能说明: 修改后把 markdown 渲染期数据与共享屏幕几何边界写死，给后续位图内容层改造提供稳定接口。
// Markdown payload stays strictly render-time. Future bitmap caches or
// intermediate layout artifacts must remain outside the document model.
struct CanvasMarkdownRenderPayload {
    let markdownSource: String
    let style: CanvasTextStyle
    let zoomScale: CGFloat
}

// Screen geometry is the shared contract consumed by selection chrome,
// accessory anchors, hit-testing, and viewport layers across item types.
struct CanvasRenderItem {
    let id: CanvasItemID
    let screenFrame: CGRect
    let screenQuad: CanvasQuad
    let screenCenter: CGPoint
    let screenBoundsSize: CGSize
    let rotationRadians: CGFloat
    let zIndex: CGFloat
    let payload: CanvasRenderPayload
}
```

## 修改三：冻结 `makeMarkdownRenderItem(...)` 的 world-to-screen 几何来源

### 3.1 修改前

- `makeMarkdownRenderItem(...)` 事实上已经用 `camera.worldToViewport(effectiveMarkdownItem.worldQuad)` 生成 markdown 的屏幕四边形。
- 但这一点只体现在实现里，没有被写成注释契约；后续如果为了位图化改造而把 `screenQuad` 换成另一套屏幕空间推导，很容易误伤选区、旋转和 accessory anchor。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift（修改前）
// 函数名: makeMarkdownRenderItem(for:camera:rotationPreviewState:)
// 功能说明: 修改前逻辑上已经由 world geometry 映射 screen geometry，但没有明确说明这是必须保持的公共契约。
private func makeMarkdownRenderItem(
    for item: CanvasMarkdownItem,
    camera: CanvasCamera,
    rotationPreviewState: CanvasRotationPreviewState?
) -> CanvasRenderItem {
    // ... 省略 effectiveMarkdownItem 解析 ...
    let screenQuad = camera.worldToViewport(effectiveMarkdownItem.worldQuad)
    return CanvasRenderItem(
        id: effectiveMarkdownItem.id,
        screenFrame: screenQuad.boundingRect.standardized,
        screenQuad: screenQuad,
        screenCenter: camera.worldToViewport(effectiveMarkdownItem.center),
        screenBoundsSize: CGSize(
            width: effectiveMarkdownItem.size.width * camera.zoomScale,
            height: effectiveMarkdownItem.size.height * camera.zoomScale
        ),
        rotationRadians: effectiveMarkdownItem.rotationRadians,
        zIndex: effectiveMarkdownItem.zIndex,
        payload: .markdown(
            CanvasMarkdownRenderPayload(
                markdownSource: effectiveMarkdownItem.markdownSource,
                style: effectiveMarkdownItem.style,
                zoomScale: camera.zoomScale
            )
        )
    )
}
```

### 3.2 修改后

- 本次没有改几何计算公式，只在同一段逻辑上补了契约注释。
- 注释明确指出：后续即便切到 `MarkdownItemLayer + MarkdownContentLayer`，markdown 的屏幕几何仍然必须来自 world geometry 映射，不能因为内容层升级为 bitmap 而篡改 `screenQuad` / `screenFrame` / `screenCenter` 语义。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeMarkdownRenderItem(for:camera:rotationPreviewState:)
// 功能说明: 修改后显式声明 markdown 的屏幕几何继续由 world geometry 映射得到，后续内容层替换不能破坏选区与命中链路。
private func makeMarkdownRenderItem(
    for item: CanvasMarkdownItem,
    camera: CanvasCamera,
    rotationPreviewState: CanvasRotationPreviewState?
) -> CanvasRenderItem {
    // ... 省略 effectiveMarkdownItem 解析 ...
    // Keep markdown screen geometry sourced from world geometry so future
    // content-layer swaps do not break selection, rotation, or accessory
    // anchoring contracts.
    let screenQuad = camera.worldToViewport(effectiveMarkdownItem.worldQuad)
    return CanvasRenderItem(
        id: effectiveMarkdownItem.id,
        screenFrame: screenQuad.boundingRect.standardized,
        screenQuad: screenQuad,
        screenCenter: camera.worldToViewport(effectiveMarkdownItem.center),
        screenBoundsSize: CGSize(
            width: effectiveMarkdownItem.size.width * camera.zoomScale,
            height: effectiveMarkdownItem.size.height * camera.zoomScale
        ),
        rotationRadians: effectiveMarkdownItem.rotationRadians,
        zIndex: effectiveMarkdownItem.zIndex,
        payload: .markdown(
            CanvasMarkdownRenderPayload(
                markdownSource: effectiveMarkdownItem.markdownSource,
                style: effectiveMarkdownItem.style,
                zoomScale: camera.zoomScale
            )
        )
    )
}
```

## 修改四：冻结 `CanvasEditorSession` 的默认宽度和“保宽重测高”编辑链

### 4.1 修改前

- `defaultMarkdownMaxLayoutWidth = 320` 和 `measuredMarkdownItemSize(...)` 的逻辑已经存在。
- 但代码本身没有显式说明：默认宽度是新建 markdown 的启动布局宽度，而编辑回写必须沿用当前容器宽度，仅重算高度。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift（修改前）
// 函数名: CanvasEditorSession / measuredMarkdownItemSize(for:style:layoutWidth:)
// 功能说明: 修改前默认宽度与测量逻辑已经在跑，但没有把“固定启动宽度”和“保宽重测高”的约束写成显式契约。
private static let defaultMarkdownSource = """
## Markdown

Write here.
"""
private static let defaultMarkdownMaxLayoutWidth: CGFloat = 320

func measuredMarkdownItemSize(
    for markdownSource: String,
    style: CanvasTextStyle,
    layoutWidth: CGFloat
) -> CGSize {
    let resolvedLayoutWidth = max(layoutWidth, 1)
    return CGSize(
        width: resolvedLayoutWidth,
        height: CanvasMarkdownLayoutMeasurer.measuredContentHeight(
            markdownSource: markdownSource,
            style: style,
            maxLayoutWidth: resolvedLayoutWidth
        )
    )
}
```

### 4.2 修改后

- 给 `defaultMarkdownMaxLayoutWidth` 加了说明，明确新建 markdown 仍从固定 world-space 宽度启动。
- 给 `measuredMarkdownItemSize(...)` 加了说明，明确编辑回写与后续内容变更继续遵循“保宽重测高”。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: CanvasEditorSession / measuredMarkdownItemSize(for:style:layoutWidth:)
// 功能说明: 修改后显式冻结 markdown 编辑链语义，约束新建和更新都继续以当前容器宽度作为唯一测量宽度来源。
private static let defaultMarkdownSource = """
## Markdown

Write here.
"""
// New markdown items still bootstrap from a fixed world-space layout width.
private static let defaultMarkdownMaxLayoutWidth: CGFloat = 320

func measuredMarkdownItemSize(
    for markdownSource: String,
    style: CanvasTextStyle,
    layoutWidth: CGFloat
) -> CGSize {
    // Markdown reflow is width-driven: edits keep the current container
    // width and only recompute the committed height from content.
    let resolvedLayoutWidth = max(layoutWidth, 1)
    return CGSize(
        width: resolvedLayoutWidth,
        height: CanvasMarkdownLayoutMeasurer.measuredContentHeight(
            markdownSource: markdownSource,
            style: style,
            maxLayoutWidth: resolvedLayoutWidth
        )
    )
}
```

## 修改五：新增阶段 0 契约回归测试

### 5.1 修改前

- 修改前没有专门的 `CanvasMarkdownContractTests.swift`。
- 项目里虽然已经有一些 markdown 相关测试，但缺少一个把“模型容器高度语义 + 编辑保宽重测高 + snapshot world-to-screen 几何映射”组合锁住的阶段 0 契约测试集。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasMarkdownContractTests.swift（修改前）
// 函数名: 新文件（修改前不存在）
// 功能说明: 修改前没有专门面向 markdown 位图重构阶段 0 的契约测试文件。
// 无此文件
```

### 5.2 修改后

- 新增 `CanvasMarkdownContractTests`，把三个后续迁移不能破坏的基线锁进测试：
  - `CanvasMarkdownItem.size.height` 可以小于 intrinsic content height，模型层仍保持显式容器高度；
  - `updateMarkdownItemContent(...)` 仍然保留当前宽度并重算高度；
  - `makeCanvasSnapshot()` 产出的 markdown `screenQuad` / `screenFrame` / `screenCenter` / `screenBoundsSize` 仍然来自 world geometry 映射与 zoom 计算。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasMarkdownContractTests.swift
// 函数名: testMarkdownItemKeepsExplicitContainerHeightEvenWhenIntrinsicHeightDiffers()
// 功能说明: 验证 markdown 模型层允许显式容器高度与 intrinsic height 分离，防止后续布局结果反向污染持久化几何。
func testMarkdownItemKeepsExplicitContainerHeightEvenWhenIntrinsicHeightDiffers() {
    let source = """
    ## Title

    A long markdown paragraph that intentionally wraps across multiple lines
    so the measured intrinsic height is much taller than the stored
    container height.
    """
    let style = CanvasTextStyle(fontSize: 18)
    let item = CanvasMarkdownItem(
        markdownSource: source,
        style: style,
        center: CGPoint(x: 120, y: -40),
        size: CGSize(width: 180, height: 44),
        zIndex: 2,
        rotationRadians: .pi / 5
    )
    let measuredHeight = CanvasMarkdownLayoutMeasurer.measuredContentHeight(
        markdownSource: source,
        style: style,
        maxLayoutWidth: item.size.width
    )

    XCTAssertGreaterThan(measuredHeight, item.size.height)
    XCTAssertEqual(item.localQuad.boundingRect.standardized.size, item.size)
    XCTAssertEqual(item.worldQuad.center, item.center)
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasMarkdownContractTests.swift
// 函数名: testUpdateMarkdownItemContentKeepsCurrentWidthAndRemeasuresHeight()
// 功能说明: 验证 markdown 编辑回写继续执行“保宽重测高”，不会因为内容更新而擅自改写容器宽度、中心点、旋转角度或层级。
func testUpdateMarkdownItemContentKeepsCurrentWidthAndRemeasuresHeight() throws {
    let session = makeMarkdownContractTestSession()
    let originalItem = CanvasMarkdownItem(
        markdownSource: "Seed",
        style: CanvasTextStyle(fontSize: 18),
        center: CGPoint(x: 40, y: 24),
        size: CGSize(width: 210, height: 48),
        zIndex: 1,
        rotationRadians: .pi / 9
    )
    session.scene.append(originalItem)

    let updatedItem = try XCTUnwrap(
        session.updateMarkdownItemContent(
            withID: originalItem.id,
            markdownSource: updatedSource,
            style: updatedStyle
        )
    )

    XCTAssertEqual(updatedItem.center, originalItem.center)
    XCTAssertEqual(updatedItem.rotationRadians, originalItem.rotationRadians)
    XCTAssertEqual(updatedItem.zIndex, originalItem.zIndex)
    XCTAssertEqual(updatedItem.size.width, originalItem.size.width)
    XCTAssertEqual(updatedItem.size.height, expectedHeight, accuracy: 0.0001)
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasMarkdownContractTests.swift
// 函数名: testCanvasSnapshotMapsMarkdownWorldGeometryIntoSharedScreenContract()
// 功能说明: 验证 snapshot 输出的 markdown 屏幕几何继续从 world geometry + camera zoom 推导，确保选区/命中/accessory 依赖的 screen contract 不被后续位图化改造打散。
func testCanvasSnapshotMapsMarkdownWorldGeometryIntoSharedScreenContract() throws {
    let session = makeMarkdownContractTestSession()
    session.camera = CanvasCamera(
        center: CGPoint(x: 100, y: -20),
        zoomScale: 1.5,
        viewportSize: CGSize(width: 400, height: 300)
    )

    session.scene.append(item)

    let snapshot = session.makeCanvasSnapshot()
    let renderItem = try XCTUnwrap(snapshot.items.first(where: { $0.id == item.id }))
    let expectedQuad = session.camera.worldToViewport(item.worldQuad)
    let expectedCenter = session.camera.worldToViewport(item.center)
    let expectedBoundsSize = CGSize(
        width: item.size.width * session.camera.zoomScale,
        height: item.size.height * session.camera.zoomScale
    )

    XCTAssertEqual(renderItem.screenQuad, expectedQuad)
    XCTAssertEqual(renderItem.screenFrame, expectedQuad.boundingRect.standardized)
    XCTAssertEqual(renderItem.screenCenter, expectedCenter)
    XCTAssertEqual(renderItem.screenBoundsSize, expectedBoundsSize)
}
```

## 验证记录

- 本次已执行定向 lints 检查，未发现新增 linter 问题。
- 本次已执行 markdown 阶段 0 相关定向测试，覆盖新增契约测试以及既有 markdown 语义回归测试。

```bash
# 命令: xcodebuild test -scheme "MyCanvas_Ver_0" -destination "platform=macOS,arch=arm64" -only-testing:"MyCanvas_Ver_0Tests/CanvasMarkdownContractTests" -only-testing:"MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests/testAddMarkdownItemUsesMeasuredHeightAtDefaultWidth" -only-testing:"MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests/testCommitMarkdownEditKeepsCurrentWidthAndRemeasuresHeight" -only-testing:"MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests/testIncreaseMarkdownContentSizeCommandRecordsHistoryAndSupportsUndoRedo" -only-testing:"MyCanvas_Ver_0Tests/CanvasSelectionTransformStateTests/testResizedMemberItemsKeepMarkdownFontSizeAndStretchContainerGeometry"
** TEST SUCCEEDED **
Test case 'CanvasCommandPolicyParityTests.testAddMarkdownItemUsesMeasuredHeightAtDefaultWidth()' passed
Test case 'CanvasCommandPolicyParityTests.testCommitMarkdownEditKeepsCurrentWidthAndRemeasuresHeight()' passed
Test case 'CanvasCommandPolicyParityTests.testIncreaseMarkdownContentSizeCommandRecordsHistoryAndSupportsUndoRedo()' passed
Test case 'CanvasSelectionTransformStateTests.testResizedMemberItemsKeepMarkdownFontSizeAndStretchContainerGeometry()' passed
Test case 'CanvasMarkdownContractTests.testCanvasSnapshotMapsMarkdownWorldGeometryIntoSharedScreenContract()' passed
Test case 'CanvasMarkdownContractTests.testMarkdownItemKeepsExplicitContainerHeightEvenWhenIntrinsicHeightDiffers()' passed
Test case 'CanvasMarkdownContractTests.testUpdateMarkdownItemContentKeepsCurrentWidthAndRemeasuresHeight()' passed
```

## 结论

- 本次阶段 0 改动的核心性质是“冻结契约”，不是“改变渲染行为”。
- 通过注释和测试双重落点，当前代码已经把后续 markdown 位图重构需要遵守的三个边界写清楚了：
  - 模型层继续持有显式容器几何；
  - 编辑链继续保宽重测高；
  - 主画布输出继续维持共享 screen geometry 契约。
