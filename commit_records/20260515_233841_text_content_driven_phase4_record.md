# 20260515_233841_text_content_driven_phase4_record

## 记录范围

- 记录内容：
  - 实施“文字内容驱动尺寸”计划的 `phase 4`，调整单文字与含文字组选的 resize 交互语义。
  - 让单选 text item 不再出现 selection resize handles，但仍保留平移与旋转语义。
  - 让含 text 的组选缩放不再只改几何 `size`，而是把缩放比例映射到文字 `fontSize`，再重新测量 intrinsic `size`。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasSelectionTransformState.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
  - `MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift`
  - `MyCanvas_Ver_0Tests/CanvasSelectionTransformStateTests.swift`
- 参考现状：
  - 生成本记录前，`git status --short --untracked-files=all` 显示上述 7 个文件处于修改状态。
  - 生成本记录前，`git diff --stat` 显示这 7 个已跟踪文件共 `338 insertions(+), 39 deletions(-)`。
- 本记录不包含：
  - 旧文档加载归一
  - inline text editor 的字号控件与命令接线
  - 更大范围的命中测试 / context menu 语义调整

## 当前 changes 摘要

- `CanvasRenderer` 现在会区分单选 text 与其他选区：单选 text 不再产出 resize handles。
- `CanvasSelectionTransformSnapshot` 不再只保留几何快照，还会保留成员 item 语义，以便 shared transform 层在组选缩放时区分 image 和 text。
- `CanvasSelectionTransformState` 新增 `resizedMemberItems(...)` 路径：
  - image 成员继续几何缩放
  - text 成员改为字号缩放 + intrinsic 尺寸重算
- `CanvasScene` 新增 `applyBoardItems(...)` 原子写口，让 controller 仍然只负责分发，不直接管理 text 特判。
- iOS / macOS controller 的组选缩放提交都切到 `resizedMemberItems(...) + applyBoardItems(...)`。
- 新增回归测试，锁住：
  - 单选文字没有 resize handles
  - 单选图片仍然保留 resize handles
  - 含文字组选缩放会更新文字 `fontSize` 与 intrinsic `size`

## 修改一：单选文字选区不再产出 resize handles

### 修改前

- `CanvasRenderer.makeSelectionEditOverlay(...)` 无论当前单选的是 image 还是 text，都会统一调用 `makeCornerEditHandles(for:)`。
- 这会让单个文字项继续表现得像一个可手动拉伸的文本框，不符合“内容决定尺寸”的新语义。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift（修改前）
// 函数名: makeSelectionEditOverlay(scene:camera:interactionState:inlineEditState:rotationPreviewState:)
// 功能说明: 修改前 selection overlay 不区分单选 image 与单选 text，所有单选都会统一产出四角 resize handles。
if selectedItems.count == 1,
   let effectiveItem = selectedItems.first
{
    subject = .singleItem(itemID: effectiveItem.id)
    worldQuad = effectiveItem.worldQuad
    screenQuad = camera.worldToViewport(worldQuad)
    screenCenter = camera.worldToViewport(effectiveItem.center)
} else {
    // ...
}

return CanvasEditRenderOverlay(
    itemID: subject.primaryItemID,
    kind: .selection,
    activeWorldQuad: worldQuad,
    activeScreenQuad: screenQuad,
    handles: makeCornerEditHandles(for: screenQuad),
    payload: .selection(selectionPayload)
)
```

### 修改后

- 新增 `selectionHandles` 分支变量。
- 单选 text 时返回空 handles；单选 image 与多选仍保留原有四角 handles。
- 这样单文字项仍然可以被选中、移动、旋转，但不会再被误导成“手动 resize 文本框”。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeSelectionEditOverlay(scene:camera:interactionState:inlineEditState:rotationPreviewState:)
// 功能说明: 修改后 selection overlay 会对单选 text 隐藏 resize handles，但单选 image 与多选仍继续保留 shared selection handles。
let subject: CanvasEditSelectionOverlaySubject
let worldQuad: CanvasQuad
let screenQuad: CanvasQuad
let screenCenter: CGPoint
let selectionHandles: [CanvasEditHandleGeometry]
if selectedItems.count == 1,
   let effectiveItem = selectedItems.first
{
    subject = .singleItem(itemID: effectiveItem.id)
    worldQuad = effectiveItem.worldQuad
    screenQuad = camera.worldToViewport(worldQuad)
    screenCenter = camera.worldToViewport(effectiveItem.center)
    selectionHandles = effectiveItem.kind == .text
        ? []
        : makeCornerEditHandles(for: screenQuad)
} else {
    // ...
    selectionHandles = makeCornerEditHandles(for: screenQuad)
}

return CanvasEditRenderOverlay(
    itemID: subject.primaryItemID,
    kind: .selection,
    activeWorldQuad: worldQuad,
    activeScreenQuad: screenQuad,
    handles: selectionHandles,
    payload: .selection(selectionPayload)
)
```

## 修改二：shared transform snapshot 保留成员 item 语义

### 修改前

- `CanvasSelectionTransformSnapshot` 只存 `memberGeometries` 和 `selectionBounds`。
- 组选缩放阶段只能看到“纯几何”，无法知道某个成员是 image 还是 text，也就无法在 shared transform 层做 text 专用语义。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasSelectionTransformState.swift（修改前）
// 函数名/类型名: CanvasSelectionTransformSnapshot.init?(scene:interactionState:) / init(primaryItemID:memberGeometries:selectionBounds:)
// 功能说明: 修改前 snapshot 只保留成员几何信息，shared transform 阶段无法区分图片成员和文字成员。
struct CanvasSelectionTransformSnapshot: Equatable {
    let primaryItemID: CanvasItemID
    let memberGeometries: [CanvasBoardItemGeometry]
    let selectionBounds: CGRect

    init?(
        scene: CanvasScene,
        interactionState: CanvasInteractionState
    ) {
        let memberItems = interactionState.selectedItemIDs.compactMap { itemID in
            scene.boardItem(withID: itemID)
        }
        guard
            memberItems.isEmpty == false,
            let primaryItemID = interactionState.primarySelectedItemID
        else {
            return nil
        }

        self.init(
            primaryItemID: primaryItemID,
            memberGeometries: memberItems.map(CanvasBoardItemGeometry.init(item:)),
            selectionBounds: Self.selectionBounds(
                for: memberItems.map(CanvasBoardItemGeometry.init(item:))
            )
        )
    }
}
```

### 修改后

- 新增 `sourceItemsByID`，把成员 item 本体保留在 snapshot 中。
- 新增 `memberItems` 初始化入口，保证 shared transform 后续既能读几何，也能读 item kind / text style。
- 同时把 selection 归一逻辑前置，避免 snapshot 内成员顺序与主选中项不一致。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasSelectionTransformState.swift
// 函数名/类型名: CanvasSelectionTransformSnapshot / init?(scene:interactionState:) / init(primaryItemID:memberItems:selectionBounds:)
// 功能说明: 修改后 snapshot 同时保留成员几何和成员 item 语义，为后续“image 继续几何缩放、text 改为字号缩放”提供 shared transform 输入。
struct CanvasSelectionTransformSnapshot: Equatable {
    let primaryItemID: CanvasItemID
    let memberGeometries: [CanvasBoardItemGeometry]
    let selectionBounds: CGRect
    private let sourceItemsByID: [CanvasItemID: CanvasBoardItem]

    init?(
        scene: CanvasScene,
        interactionState: CanvasInteractionState
    ) {
        let normalizedSelection = normalizeCanvasSelectionState(
            selectedItemIDs: interactionState.selectedItemIDs,
            primarySelectedItemID: interactionState.primarySelectedItemID
        )
        let memberItems = normalizedSelection.selectedItemIDs.compactMap { itemID in
            scene.boardItem(withID: itemID)
        }
        guard
            memberItems.isEmpty == false,
            memberItems.count == normalizedSelection.selectedItemIDs.count,
            let primaryItemID = normalizedSelection.primarySelectedItemID
        else {
            return nil
        }

        self.init(
            primaryItemID: primaryItemID,
            memberItems: memberItems,
            selectionBounds: Self.selectionBounds(
                for: memberItems.map(CanvasBoardItemGeometry.init(item:))
            )
        )
    }

    init(
        primaryItemID: CanvasItemID,
        memberItems: [CanvasBoardItem],
        selectionBounds: CGRect? = nil
    ) {
        self.init(
            primaryItemID: primaryItemID,
            memberGeometries: memberItems.map(CanvasBoardItemGeometry.init(item:)),
            sourceItemsByID: Dictionary(
                uniqueKeysWithValues: memberItems.map { ($0.id, $0) }
            ),
            selectionBounds: selectionBounds
        )
    }
}
```

## 修改三：组选缩放不再只吐 geometry，而是对 text 做字号缩放

### 修改前

- `resizedMemberGeometries(...)` 会对所有成员统一按比例缩放 `center` 和 `size`。
- 这对 image 成员是正确的，但对 text 成员会继续把文字当成“可拉伸矩形框”，而不是内容驱动 item。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasSelectionTransformState.swift（修改前）
// 函数名: resizedMemberGeometries(handleRole:draggedWorldCorner:minimumScale:)
// 功能说明: 修改前组选缩放对所有成员都只做纯几何缩放，text 成员也会直接改 size，而不会更新 fontSize 或重测 intrinsic size。
func resizedMemberGeometries(
    handleRole: CanvasSelectionHandleRole,
    draggedWorldCorner: CGPoint,
    minimumScale: CGFloat
) -> [CanvasBoardItemGeometry]? {
    guard
        let resizeDraft = resizeDraft(
            handleRole: handleRole,
            draggedWorldCorner: draggedWorldCorner,
            minimumScale: minimumScale
        )
    else {
        return nil
    }

    return memberGeometries.map { geometry in
        CanvasBoardItemGeometry(
            itemID: geometry.itemID,
            center: canvasScalePoint(
                geometry.center,
                around: resizeDraft.fixedCorner,
                by: resizeDraft.scale
            ),
            size: CGSize(
                width: geometry.size.width * resizeDraft.scale,
                height: geometry.size.height * resizeDraft.scale
            ),
            rotationRadians: geometry.rotationRadians
        )
    }
}
```

### 修改后

- 保留 `resizedMemberGeometries(...)` 给纯几何使用，但新增 `resizedMemberItems(...)` 作为组选缩放的共享写入口。
- `image` 成员继续走 `applyingGeometry(...)`。
- `text` 成员改为：
  1. 用组选缩放比例更新 `fontSize`
  2. 保持缩放后的 `center`
  3. 用新的 text style 重新测量 intrinsic `size`

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasSelectionTransformState.swift
// 函数名: resizedMemberItems(handleRole:draggedWorldCorner:minimumScale:) / resizedItem(_:using:) / resizedTextItem(_:scaledCenter:scale:)
// 功能说明: 修改后组选缩放在 shared transform 层按成员 kind 分流；image 继续几何缩放，text 改为字号缩放并重算 intrinsic size。
func resizedMemberItems(
    handleRole: CanvasSelectionHandleRole,
    draggedWorldCorner: CGPoint,
    minimumScale: CGFloat
) -> [CanvasBoardItem]? {
    guard
        let resizeDraft = resizeDraft(
            handleRole: handleRole,
            draggedWorldCorner: draggedWorldCorner,
            minimumScale: minimumScale
        )
    else {
        return nil
    }

    var resizedItems: [CanvasBoardItem] = []
    resizedItems.reserveCapacity(memberItemIDs.count)
    for itemID in memberItemIDs {
        guard let item = sourceItemsByID[itemID] else {
            return nil
        }
        resizedItems.append(
            resizedItem(
                item,
                using: resizeDraft
            )
        )
    }
    return resizedItems
}

private func resizedItem(
    _ item: CanvasBoardItem,
    using resizeDraft: CanvasSelectionResizeDraft
) -> CanvasBoardItem {
    let scaledItemGeometry = scaledGeometry(
        from: CanvasBoardItemGeometry(item: item),
        using: resizeDraft
    )
    switch item {
    case .image:
        return item.applyingGeometry(scaledItemGeometry) ?? item
    case let .text(textItem):
        return .text(
            resizedTextItem(
                textItem,
                scaledCenter: scaledItemGeometry.center,
                scale: resizeDraft.scale
            )
        )
    }
}

private func resizedTextItem(
    _ item: CanvasTextItem,
    scaledCenter: CGPoint,
    scale: CGFloat
) -> CanvasTextItem {
    let resizedStyle = CanvasTextStyle(
        fontName: item.style.fontName,
        fontSize: CanvasTextLayoutMeasurer.renderFontSize(
            for: item.style,
            scale: scale
        ),
        color: item.style.color
    )
    return CanvasTextItem(
        id: item.id,
        text: item.text,
        style: resizedStyle,
        center: scaledCenter,
        size: CanvasTextLayoutMeasurer.intrinsicItemSize(
            for: item.text,
            style: resizedStyle
        ),
        zIndex: item.zIndex,
        rotationRadians: item.rotationRadians
    )
}
```

## 修改四：Scene 新增完整 item 的原子写口

### 修改前

- `CanvasScene.applyBoardItemGeometries(...)` 只接受几何数组。
- 这让 controller 只能把组选缩放结果约束成“几何更新”，不适合接收 text 成员的 `style + size` 联动更新。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift（修改前）
// 函数名: applyBoardItemGeometries(_:)
// 功能说明: 修改前 Scene 只能原子提交 geometry 变更；如果某个 shared transform 需要同时更新 style 和 size，就没有合适的 shared 写口。
func applyBoardItemGeometries(
    _ geometries: [CanvasBoardItemGeometry]
) -> [CanvasBoardItem]? {
    guard geometries.isEmpty == false else {
        return []
    }

    // ... 校验 geometry ...
    var updatedItems = items
    var updatedBoardItems: [CanvasBoardItem] = []

    for geometry in geometries {
        guard
            let index = updatedItems.firstIndex(where: { $0.id == geometry.itemID }),
            let updatedItem = updatedItems[index].applyingGeometry(geometry)
        else {
            return nil
        }

        updatedItems[index] = updatedItem
        updatedBoardItems.append(updatedItem)
    }

    items = updatedItems
    return updatedBoardItems
}
```

### 修改后

- `applyBoardItemGeometries(...)` 先把 geometry 映射成完整 `CanvasBoardItem`，再委托给新的 `applyBoardItems(...)`。
- 新增 `applyBoardItems(...)`，统一做：
  - 尺寸合法性校验
  - 重复 itemID 校验
  - kind 一致性校验
  - 原子写回

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasScene.swift
// 函数名: applyBoardItemGeometries(_:) / applyBoardItems(_:)
// 功能说明: 修改后 Scene 同时支持“纯 geometry 原子写回”和“完整 board item 原子写回”，让 shared transform 可以在不下沉到 controller 的前提下提交 text 的 style + size 更新。
func applyBoardItemGeometries(
    _ geometries: [CanvasBoardItemGeometry]
) -> [CanvasBoardItem]? {
    guard geometries.isEmpty == false else {
        return []
    }

    var updatedBoardItems: [CanvasBoardItem] = []
    updatedBoardItems.reserveCapacity(geometries.count)
    for geometry in geometries {
        guard
            let currentItem = boardItem(withID: geometry.itemID),
            let updatedItem = currentItem.applyingGeometry(geometry)
        else {
            return nil
        }
        updatedBoardItems.append(updatedItem)
    }

    return applyBoardItems(updatedBoardItems)
}

func applyBoardItems(
    _ updatedBoardItems: [CanvasBoardItem]
) -> [CanvasBoardItem]? {
    guard updatedBoardItems.isEmpty == false else {
        return []
    }

    var updatedItemIDs = Set<CanvasItemID>()
    for updatedItem in updatedBoardItems {
        guard
            updatedItem.size.width > 0,
            updatedItem.size.height > 0,
            updatedItemIDs.insert(updatedItem.id).inserted
        else {
            return nil
        }
    }

    var nextItems = items
    for updatedItem in updatedBoardItems {
        guard
            let index = nextItems.firstIndex(where: { $0.id == updatedItem.id }),
            nextItems[index].kind == updatedItem.kind
        else {
            return nil
        }

        nextItems[index] = updatedItem
    }

    items = nextItems
    return updatedBoardItems
}
```

## 修改五：平台 controller 只切换 shared 调用口，不加 text 特判

### 修改前

- iOS / macOS 的 `resizeSelection(...)` 都走 `resizedMemberGeometries(...) + scene.applyBoardItemGeometries(...)`。
- 这条路径天然只能提交几何更新，无法表达 text 成员的字号缩放语义。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift（修改前）
// 函数名: resizeSelection(using:to:)
// 功能说明: 修改前 iOS 组选缩放只会拿到 geometry 数组，再统一提交 geometry 写回。
guard
    let resizedGeometries = resizeState.resizedMemberGeometries(
        for: camera.viewportToWorld(viewportLocation)
    ),
    let resizedItems = scene.applyBoardItemGeometries(resizedGeometries),
    let resizedBounds = worldBounds(for: resizedItems)
else {
    return
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift（修改前）
// 函数名: resizeSelection(using:to:)
// 功能说明: 修改前 macOS 组选缩放与 iOS 一样，只能提交几何更新，无法在 shared 路径里表达 text 的 fontSize 变化。
guard
    let resizedGeometries = resizeState.resizedMemberGeometries(
        for: camera.viewportToWorld(viewportLocation)
    ),
    let resizedItems = scene.applyBoardItemGeometries(resizedGeometries),
    let resizedBounds = worldBounds(for: resizedItems)
else {
    return
}
```

### 修改后

- 两个平台的 controller 都只切换到新的 shared API：
  - `resizeState.resizedMemberItems(...)`
  - `scene.applyBoardItems(...)`
- controller 不知道 text 的具体规则，只负责把共享 transform 的结果写回 Scene。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: resizeSelection(using:to:)
// 功能说明: 修改后 iOS controller 只切换 shared transform / scene 的调用口，不直接处理 text 特判细节。
guard
    let resizedItems = resizeState.resizedMemberItems(
        for: camera.viewportToWorld(viewportLocation)
    ),
    let appliedItems = scene.applyBoardItems(resizedItems),
    let resizedBounds = worldBounds(for: appliedItems)
else {
    return
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: resizeSelection(using:to:)
// 功能说明: 修改后 macOS controller 与 iOS 保持一致，只分发 shared transform 结果，不承担 text-specific 逻辑。
guard
    let resizedItems = resizeState.resizedMemberItems(
        for: camera.viewportToWorld(viewportLocation)
    ),
    let appliedItems = scene.applyBoardItems(resizedItems),
    let resizedBounds = worldBounds(for: appliedItems)
else {
    return
}
```

## 修改六：补充 phase 4 的回归测试

### 修改前

- `CanvasEditorSessionAlignmentOverlayTests` 只验证了多选 overlay 的 handles 与命中，没有覆盖“单选 text 不再显示 resize handles”。
- `CanvasSelectionTransformStateTests` 只验证了纯几何缩放，没有覆盖“含 text 组选缩放会更新 fontSize 与 intrinsic size”。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift（修改前）
// 函数名: testMakeCanvasSnapshotProducesSelectionHighlightsAndGroupOverlayForMultiSelection()
// 功能说明: 修改前 overlay 测试只锁定多选 handles 存在，没有覆盖单选 text 应隐藏 resize handles 的新语义。
func testMakeCanvasSnapshotProducesSelectionHighlightsAndGroupOverlayForMultiSelection() {
    // ...
    XCTAssertEqual(editOverlay.handles.count, CanvasSelectionHandleRole.allCases.count)
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasSelectionTransformStateTests.swift（修改前）
// 函数名: testResizedMemberGeometriesScaleCentersAndSizesFromFixedCorner()
// 功能说明: 修改前 transform 测试只验证统一几何缩放，没有覆盖 text 成员需要字号缩放 + intrinsic size 重算的新语义。
func testResizedMemberGeometriesScaleCentersAndSizesFromFixedCorner() throws {
    // ...
    XCTAssertEqual(firstGeometry.size, CGSize(width: 30, height: 30))
    XCTAssertEqual(secondGeometry.size, CGSize(width: 60, height: 30))
}
```

### 修改后

- `CanvasEditorSessionAlignmentOverlayTests` 新增：
  - `testMakeCanvasSnapshotOmitsResizeHandlesForSingleTextSelection()`
  - `testMakeCanvasSnapshotKeepsResizeHandlesForSingleImageSelection()`
- `CanvasSelectionTransformStateTests` 新增：
  - `testResizedMemberItemsScaleTextFontSizeAndRecomputeIntrinsicSize()`
- 这样 phase 4 最核心的两个行为都有自动化回归保护。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift
// 函数名: testMakeCanvasSnapshotOmitsResizeHandlesForSingleTextSelection() / testMakeCanvasSnapshotKeepsResizeHandlesForSingleImageSelection()
// 功能说明: 修改后 overlay 测试同时锁住“单选 text 无 resize handles”和“单选 image 仍保留 resize handles”。
func testMakeCanvasSnapshotOmitsResizeHandlesForSingleTextSelection() throws {
    let item = CanvasTextItem(
        text: "single text",
        center: CGPoint(x: 40, y: 20),
        size: CGSize(width: 120, height: 48)
    )
    let session = makeAlignmentOverlayTestSession(with: item)

    let snapshot = session.makeCanvasSnapshot()
    let editOverlay = try XCTUnwrap(snapshot.editOverlay)

    guard case let .selection(payload) = editOverlay.payload else {
        XCTFail("Expected single text selection overlay payload.")
        return
    }

    XCTAssertEqual(editOverlay.itemID, item.id)
    XCTAssertTrue(editOverlay.handles.isEmpty)
    XCTAssertFalse(payload.rotateAffordance.handle.screenCenter.x.isNaN)
}

func testMakeCanvasSnapshotKeepsResizeHandlesForSingleImageSelection() throws {
    let item = try makeAlignmentOverlayTestImageItem()
    let session = makeAlignmentOverlayTestSession(with: item)
    let snapshot = session.makeCanvasSnapshot()
    let editOverlay = try XCTUnwrap(snapshot.editOverlay)

    XCTAssertEqual(editOverlay.itemID, item.id)
    XCTAssertEqual(editOverlay.handles.count, CanvasSelectionHandleRole.allCases.count)
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasSelectionTransformStateTests.swift
// 函数名: testResizedMemberItemsScaleTextFontSizeAndRecomputeIntrinsicSize()
// 功能说明: 修改后 transform 测试直接锁定含 text 组选缩放时，text 成员会更新 fontSize 与 intrinsic size，而 image 成员继续几何缩放。
func testResizedMemberItemsScaleTextFontSizeAndRecomputeIntrinsicSize() throws {
    let textStyle = CanvasTextStyle(fontSize: 20)
    let textItem = CanvasTextItem(
        text: "Scale me",
        style: textStyle,
        center: CGPoint(x: 25, y: 25),
        size: CanvasTextLayoutMeasurer.intrinsicItemSize(
            for: "Scale me",
            style: textStyle
        )
    )
    // ... 省略 image 构造 ...
    let resizedItems = try XCTUnwrap(
        snapshot.resizedMemberItems(
            handleRole: .bottomTrailing,
            draggedWorldCorner: CGPoint(x: 150, y: 150),
            minimumScale: 0.1
        )
    )
    let resizedTextItem = try XCTUnwrap(
        resizedItems.first(where: { $0.id == textItem.id })?.textItem
    )
    let expectedTextStyle = CanvasTextStyle(
        fontName: textStyle.fontName,
        fontSize: 30,
        color: textStyle.color
    )

    XCTAssertEqual(resizedTextItem.center, CGPoint(x: 37.5, y: 37.5))
    XCTAssertEqual(resizedTextItem.style, expectedTextStyle)
    XCTAssertEqual(
        resizedTextItem.size,
        CanvasTextLayoutMeasurer.intrinsicItemSize(
            for: textItem.text,
            style: expectedTextStyle
        )
    )
}
```

## 验证情况

- `ReadLints` 检查结果：本次改动未引入新的诊断问题。
- `macOS` 定向测试通过：
  - `xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS,arch=arm64' -only-testing:MyCanvas_Ver_0Tests/CanvasSelectionTransformStateTests -only-testing:MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests -only-testing:MyCanvas_Ver_0Tests/CanvasTextLayoutMeasurerTests -only-testing:MyCanvas_Ver_0Tests/CanvasTextLayerTests`
- `iOS Simulator` 构建通过：
  - `xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=iOS Simulator,name=iPhone 17'`

## 当前阶段结论

- `phase 4` 已把“单文字 intrinsic item 不再表现成可手动拉伸文本框”的语义落到 shared renderer / transform / scene 链路中。
- 含 text 的组选缩放现在会正确把缩放比例映射到 `fontSize`，并同步重测文字 intrinsic `size`；图片成员则继续走现有几何缩放路径。
- 控制器层本次只切换共享调用口，没有引入平台私有的 text 特判，后续 `phase 5` 可以直接在 shared 加载链路里继续推进旧文档归一。
