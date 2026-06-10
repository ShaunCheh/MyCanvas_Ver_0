# 20260610_142444_CST_arrow_endpoint_geometry_redo_record

## 记录范围

- 记录内容：
  - 将箭头几何从 `center + size + rotationRadians` 的包围盒模型，重做为 `startPoint + endPoint + shaftThickness` 的端点语义模型。
  - 修正端点拖拽时的几何保持逻辑，使拖拽只改变箭头长度与方向，不再把整支箭头当成“可拉伸图片”处理。
  - 更新箭头存储结构、运行时映射、小图预览、缩略图渲染，以及对应回归测试。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasArrowItem.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasArrowEndpointDragState.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift`
  - `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardGeometryPreviewBuilder.swift`
  - `MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift`
  - `MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests.swift`
  - `MyCanvas_Ver_0Tests/BoardSelectionStateMigrationTests.swift`
- 本次未包含：
  - 工具条按钮、命令入口、viewport 交互入口的新增接线；这些是在上一轮箭头接入中完成，本轮没有继续改动。
  - 任何提交操作。
  - 原始 `git diff` 全文粘贴。

## 命名与当前 changes 证据

```sh
# 文件路径: 无（终端命令）
# 函数名: date +"%Y%m%d_%H%M%S_%Z"
# 功能说明: 使用系统 date 命令生成本次记录文件的时间戳前缀。
20260610_142444_CST
```

```sh
# 文件路径: 无（终端命令）
# 函数名: git status --short
# 功能说明: 记录本次几何重做完成后，工作区中与箭头重做直接相关的当前 changes。
 M MyCanvas_Ver_0/Canvas/Core/CanvasArrowItem.swift
 M MyCanvas_Ver_0/Canvas/Editing/CanvasArrowEndpointDragState.swift
 M MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift
 M MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift
 M MyCanvas_Ver_0/Platform/Shared/BoardList/BoardGeometryPreviewBuilder.swift
 M MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift
 M MyCanvas_Ver_0Tests/BoardSelectionStateMigrationTests.swift
 M MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests.swift
```

```sh
# 文件路径: 无（终端命令）
# 函数名: git diff --stat -- [8 个箭头重做相关文件]
# 功能说明: 汇总本次重做的改动体量与分布，不直接粘贴原始 diff。
 MyCanvas_Ver_0/Canvas/Core/CanvasArrowItem.swift   | 264 ++++++++++++++++++---
 .../Editing/CanvasArrowEndpointDragState.swift     |   6 +-
 MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift  | 106 ++++++++-
 .../Canvas/Storage/BoardDocumentMapper.swift       |  16 +-
 .../BoardList/BoardGeometryPreviewBuilder.swift    |  13 +-
 .../Shared/BoardList/BoardThumbnailRenderer.swift  |  41 ++--
 .../BoardSelectionStateMigrationTests.swift        | 113 +++++++++
 .../CanvasCommandPolicyParityTests.swift           |  35 +++
 8 files changed, 520 insertions(+), 74 deletions(-)
```

## 根因说明

上一轮箭头已经是原生元素，不是位图资源；但其几何模型仍然是“矩形包围盒驱动箭头形状重建”。结果是：

- 端点拖拽最终会落到 `size.width / size.height / rotationRadians` 的变化上。
- `canvasArrowPolygonPoints(in:)` 又会按整个 `rect.width / rect.height` 重新推导箭杆厚度、箭头长度与箭头宽度。
- 所以用户感知上会变成“把整支箭头按盒子整体拉伸”，观感接近“图片被拉长”，而不是“固定箭头参数，只改首尾位置”。

本轮重做的核心目标，就是把箭头从“盒模型”改回“几何语义模型”。

## 1. 核心模型从包围盒改为端点语义

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasArrowItem.swift
// 函数名: CanvasArrowItem / canvasArrowPolygonPoints(in:)
// 功能说明: 修改前，箭头自身只保存 center/size/rotation；箭头外形参数由整个 bounding rect 按比例重算。
struct CanvasArrowItem {
    let id: CanvasItemID
    var center: CGPoint
    var size: CGSize
    var zIndex: CGFloat
    var rotationRadians: CGFloat
}

func canvasArrowPolygonPoints(in rect: CGRect) -> [CGPoint] {
    let standardizedRect = rect.standardized
    let tailHalfHeight = standardizedRect.height * 0.22
    let preferredHeadLength = max(
        standardizedRect.width * 0.28,
        standardizedRect.height * 0.95
    )
    let headLength = min(
        max(preferredHeadLength, standardizedRect.width * 0.18),
        standardizedRect.width * 0.55
    )
    // ...
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasArrowItem.swift
// 函数名: CanvasArrowItem / center / size / rotationRadians / canvasArrowPolygonPoints(in:)
// 功能说明: 修改后，箭头直接保存 startPoint/endPoint/shaftThickness；center/size/rotation 变为派生几何，path 只按固定比例使用“当前高度”推导箭头头部与杆身。
private let canvasArrowShaftToHeadWidthRatio: CGFloat = 0.44
private let canvasArrowHeadLengthToHeadWidthRatio: CGFloat = 0.95

struct CanvasArrowItem {
    let id: CanvasItemID
    var startPoint: CGPoint
    var endPoint: CGPoint
    var shaftThickness: CGFloat
    var zIndex: CGFloat

    var center: CGPoint {
        CGPoint(
            x: (startPoint.x + endPoint.x) / 2,
            y: (startPoint.y + endPoint.y) / 2
        )
    }

    var size: CGSize {
        CGSize(
            width: length,
            height: overallHeight
        )
    }

    var rotationRadians: CGFloat {
        normalizedCanvasAngle(
            atan2(
                endPoint.y - startPoint.y,
                endPoint.x - startPoint.x
            )
        )
    }
}

func canvasArrowPolygonPoints(in rect: CGRect) -> [CGPoint] {
    let standardizedRect = rect.standardized
    let tailHalfHeight = standardizedRect.height * canvasArrowShaftToHeadWidthRatio / 2
    let headLength = standardizedRect.height * canvasArrowHeadLengthToHeadWidthRatio
    // ...
}
```

### 结果

- `width` 主要表示箭头长度，由 `startPoint -> endPoint` 的距离决定。
- `height` 代表整支箭头的可见高度；箭杆厚度由 `shaftThickness` 单独保存。
- 箭头头部长度与宽度改为由当前高度推导，不再随着总长度增加而按比例变长。

## 2. 端点拖拽从“保留旧盒子尺寸”改为“保留当前外形高度”

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasArrowEndpointDragState.swift
// 函数名: init(item:draggedEndpointRole:minimumLength:) / updatedGeometry(draggedWorldPoint:)
// 功能说明: 修改前，拖拽状态保留的是旧模型里的 preservedThickness；结合旧 size 语义，会继续把包围盒高度当成几何输入写回。
struct CanvasArrowEndpointDragState {
    let itemID: CanvasItemID
    let draggedEndpointRole: CanvasArrowEndpointRole
    let fixedEndpointWorldPoint: CGPoint
    let preservedThickness: CGFloat
    let minimumLength: CGFloat
    let fallbackRotationRadians: CGFloat

    init(item: CanvasArrowItem, draggedEndpointRole: CanvasArrowEndpointRole, minimumLength: CGFloat) {
        preservedThickness = item.size.height
        // ...
    }

    func updatedGeometry(draggedWorldPoint: CGPoint) -> CanvasBoardItemGeometry {
        CanvasBoardItemGeometry(
            itemID: itemID,
            center: /* ... */,
            size: CGSize(
                width: length,
                height: preservedThickness
            ),
            rotationRadians: atan2(direction.y, direction.x)
        )
    }
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasArrowEndpointDragState.swift
// 函数名: init(item:draggedEndpointRole:minimumLength:) / updatedGeometry(draggedWorldPoint:)
// 功能说明: 修改后，拖拽状态保留的是 preservedOverallHeight；端点拖拽时只更新长度与方向，外形高度保持稳定，再由新模型把它换算回 shaftThickness。
struct CanvasArrowEndpointDragState {
    let itemID: CanvasItemID
    let draggedEndpointRole: CanvasArrowEndpointRole
    let fixedEndpointWorldPoint: CGPoint
    let preservedOverallHeight: CGFloat
    let minimumLength: CGFloat
    let fallbackRotationRadians: CGFloat

    init(item: CanvasArrowItem, draggedEndpointRole: CanvasArrowEndpointRole, minimumLength: CGFloat) {
        preservedOverallHeight = item.size.height
        // ...
    }

    func updatedGeometry(draggedWorldPoint: CGPoint) -> CanvasBoardItemGeometry {
        CanvasBoardItemGeometry(
            itemID: itemID,
            center: /* ... */,
            size: CGSize(
                width: length,
                height: preservedOverallHeight
            ),
            rotationRadians: atan2(direction.y, direction.x)
        )
    }
}
```

### 结果

- 端点拖拽仍然走现有 `CanvasBoardItemGeometry` 通道，不需要重写外围控制器状态机。
- 但高度的语义已经变成“保留当前箭头外形高度”，不会再诱发整支箭头随着长度一并变胖或变瘦。

## 3. 存储结构切换到新模型，并兼容旧箭头数据

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift
// 函数名: BoardArrowItemRecord
// 功能说明: 修改前，持久化结构直接保存 center/size/rotation，与旧运行时盒模型完全一致。
struct BoardArrowItemRecord: Codable, Equatable {
    let id: UUID
    var center: BoardPointRecord
    var size: BoardSizeRecord
    var zIndex: Double
    var rotationRadians: Double?
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift
// 函数名: makeArrowItem(from:) / makeArrowRecord(from:)
// 功能说明: 修改前，Mapper 在 record 和 runtime item 之间直接拷贝 center/size/rotation。
private static func makeArrowItem(from arrowRecord: BoardArrowItemRecord) -> CanvasArrowItem {
    CanvasArrowItem(
        id: arrowRecord.id,
        center: arrowRecord.center.cgPoint,
        size: arrowRecord.size.cgSize,
        zIndex: CGFloat(arrowRecord.zIndex),
        rotationRadians: CGFloat(arrowRecord.rotationRadians ?? 0)
    )
}

private static func makeArrowRecord(from item: CanvasArrowItem) -> BoardArrowItemRecord {
    BoardArrowItemRecord(
        id: item.id,
        center: BoardPointRecord(item.center),
        size: BoardSizeRecord(item.size),
        zIndex: Double(item.zIndex),
        rotationRadians: Double(item.rotationRadians)
    )
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocument.swift
// 函数名: BoardDocument.currentFormatVersion / BoardArrowItemRecord / init(from:) / encode(to:)
// 功能说明: 修改后，文档版本提升到 11；箭头 record 保存 startPoint/endPoint/shaftThickness，并在解码时兼容旧版 center/size/rotation 数据。
struct BoardDocument: Codable {
    static let currentFormatVersion = 11
}

struct BoardArrowItemRecord: Codable, Equatable {
    let id: UUID
    var startPoint: BoardPointRecord
    var endPoint: BoardPointRecord
    var shaftThickness: Double
    var zIndex: Double

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UUID.self, forKey: .id)
        let zIndex = try container.decode(Double.self, forKey: .zIndex)

        let item: CanvasArrowItem
        if
            let startPoint = try container.decodeIfPresent(BoardPointRecord.self, forKey: .startPoint),
            let endPoint = try container.decodeIfPresent(BoardPointRecord.self, forKey: .endPoint)
        {
            item = CanvasArrowItem(
                id: id,
                startPoint: startPoint.cgPoint,
                endPoint: endPoint.cgPoint,
                shaftThickness: CGFloat(
                    try container.decodeIfPresent(Double.self, forKey: .shaftThickness) ?? 0
                ),
                zIndex: CGFloat(zIndex)
            )
        } else {
            item = CanvasArrowItem(
                id: id,
                center: try container.decode(BoardPointRecord.self, forKey: .center).cgPoint,
                size: try container.decode(BoardSizeRecord.self, forKey: .size).cgSize,
                zIndex: CGFloat(zIndex),
                rotationRadians: CGFloat(
                    try container.decodeIfPresent(Double.self, forKey: .rotationRadians) ?? 0
                )
            )
        }

        self.init(
            id: item.id,
            startPoint: BoardPointRecord(item.startPoint),
            endPoint: BoardPointRecord(item.endPoint),
            shaftThickness: Double(item.shaftThickness),
            zIndex: Double(item.zIndex)
        )
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardDocumentMapper.swift
// 函数名: makeArrowItem(from:) / makeArrowRecord(from:)
// 功能说明: 修改后，Mapper 只围绕 start/end/thickness 做双向转换；旧格式兼容完全收敛到 BoardArrowItemRecord 的 decoder 中。
private static func makeArrowItem(from arrowRecord: BoardArrowItemRecord) -> CanvasArrowItem {
    CanvasArrowItem(
        id: arrowRecord.id,
        startPoint: arrowRecord.startPoint.cgPoint,
        endPoint: arrowRecord.endPoint.cgPoint,
        shaftThickness: CGFloat(arrowRecord.shaftThickness),
        zIndex: CGFloat(arrowRecord.zIndex)
    )
}

private static func makeArrowRecord(from item: CanvasArrowItem) -> BoardArrowItemRecord {
    BoardArrowItemRecord(
        id: item.id,
        startPoint: BoardPointRecord(item.startPoint),
        endPoint: BoardPointRecord(item.endPoint),
        shaftThickness: Double(item.shaftThickness),
        zIndex: Double(item.zIndex)
    )
}
```

### 结果

- 新数据落盘时不再依赖盒模型字段。
- 旧数据读取时仍可自动还原成新的端点模型，不需要额外 migration 脚本。

## 4. 预览与缩略图改为复用运行时箭头几何

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardGeometryPreviewBuilder.swift
// 函数名: makeNode(from:boardID:documentOrder:)
// 功能说明: 修改前，预览节点直接使用 arrowRecord.center / size / rotationRadians，默认箭头 record 仍然是盒模型。
case let .arrow(arrowRecord):
    return makeNode(
        boardID: boardID,
        documentOrder: documentOrder,
        id: arrowRecord.id,
        kind: .shape,
        center: arrowRecord.center,
        size: arrowRecord.size,
        zIndex: arrowRecord.zIndex,
        rotationRadians: arrowRecord.rotationRadians
    )
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift
// 函数名: drawArrowItem(_:geometry:in:traceContext:documentOrder:renderOrder:)
// 功能说明: 修改前，缩略图也直接依赖 itemRecord.center / size / rotationRadians 画箭头路径。
private func drawArrowItem(
    _ itemRecord: BoardArrowItemRecord,
    geometry: CanvasMiniMapViewGeometry,
    in context: CGContext,
    traceContext _: BoardThumbnailTraceContext,
    documentOrder _: Int?,
    renderOrder _: Int
) {
    let visibleSize = itemRecord.size.cgSize
    let mappedSize = CGSize(
        width: visibleSize.width * geometry.scale,
        height: visibleSize.height * geometry.scale
    )
    let mappedCenter = geometry.worldToMiniMap(itemRecord.center.cgPoint)
    let rotationRadians = normalizedCanvasAngle(
        CGFloat(itemRecord.rotationRadians ?? 0)
    )
    // ...
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardGeometryPreviewBuilder.swift
// 函数名: makeNode(from:boardID:documentOrder:)
// 功能说明: 修改后，先从 record 构造运行时 CanvasArrowItem，再统一使用运行时几何导出 center / size / rotationRadians，避免预览层继续理解旧盒模型字段。
case let .arrow(arrowRecord):
    let arrowItem = CanvasArrowItem(
        id: arrowRecord.id,
        startPoint: arrowRecord.startPoint.cgPoint,
        endPoint: arrowRecord.endPoint.cgPoint,
        shaftThickness: CGFloat(arrowRecord.shaftThickness),
        zIndex: CGFloat(arrowRecord.zIndex)
    )
    return makeNode(
        boardID: boardID,
        documentOrder: documentOrder,
        id: arrowRecord.id,
        kind: .shape,
        center: BoardPointRecord(arrowItem.center),
        size: BoardSizeRecord(arrowItem.size),
        zIndex: arrowRecord.zIndex,
        rotationRadians: Double(arrowItem.rotationRadians)
    )
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift
// 函数名: drawArrowItem(_:geometry:in:traceContext:documentOrder:renderOrder:)
// 功能说明: 修改后，缩略图先恢复运行时箭头几何，再按缩放后的 size 与中心点生成 path，确保缩略图与主画布看到的是同一套箭头比例。
private func drawArrowItem(
    _ itemRecord: BoardArrowItemRecord,
    geometry: CanvasMiniMapViewGeometry,
    in context: CGContext,
    traceContext _: BoardThumbnailTraceContext,
    documentOrder _: Int?,
    renderOrder _: Int
) {
    let item = CanvasArrowItem(
        id: itemRecord.id,
        startPoint: itemRecord.startPoint.cgPoint,
        endPoint: itemRecord.endPoint.cgPoint,
        shaftThickness: CGFloat(itemRecord.shaftThickness),
        zIndex: CGFloat(itemRecord.zIndex)
    )
    let visibleSize = CGSize(
        width: item.size.width * geometry.scale,
        height: item.size.height * geometry.scale
    )
    let mappedCenter = geometry.worldToMiniMap(item.center)

    context.saveGState()
    context.translateBy(x: mappedCenter.x, y: mappedCenter.y)
    context.rotate(by: item.rotationRadians)
    // ...
}
```

### 结果

- board list preview 和 thumbnail 不再保留一套“旧箭头盒模型”的私有解释。
- 运行时、存储、预览三层都统一围绕 `CanvasArrowItem` 的端点几何运转。

## 5. 回归测试补齐“新模型正确性”和“旧数据兼容性”

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0Tests/BoardSelectionStateMigrationTests.swift
// 函数名: 无
// 功能说明: 修改前，此文件中不存在针对 arrow record round-trip 或 legacy arrow decode 的测试用例。
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests.swift
// 函数名: testAddArrowCommandCreatesDefaultHorizontalArrow()
// 功能说明: 修改前，这里只验证“新增箭头命令会创建默认箭头”，还没有覆盖“端点拖拽后箭头 profile 保持不变”。
func testAddArrowCommandCreatesDefaultHorizontalArrow() throws {
    let result = try XCTUnwrap(executor.execute(.addArrowItem))
    let itemID = try XCTUnwrap(session.singleSelectedItemID)
    let item = try XCTUnwrap(session.scene.arrowItem(withID: itemID))

    XCTAssertEqual(item.center, session.camera.center)
    XCTAssertEqual(item.size, CGSize(width: 220, height: 80))
    XCTAssertEqual(item.rotationRadians, 0, accuracy: 0.0001)
    XCTAssertEqual(result.refreshReason, "add arrow item \(item.id.uuidString)")
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0Tests/BoardSelectionStateMigrationTests.swift
// 函数名: testBoardDocumentMapperRoundTripsArrowItem() / testBoardDocumentDecodesLegacyArrowGeometryIntoEndpointModel()
// 功能说明: 修改后，测试同时覆盖新箭头格式 round-trip，以及旧 center/size/rotation 存档向新端点模型的兼容解码。
func testBoardDocumentMapperRoundTripsArrowItem() throws {
    let item = CanvasArrowItem(
        id: UUID(),
        startPoint: CGPoint(x: 40, y: 20),
        endPoint: CGPoint(x: 260, y: 120),
        shaftThickness: 28,
        zIndex: 4
    )
    // ...
    XCTAssertEqual(roundTrippedItem.startPoint, item.startPoint)
    XCTAssertEqual(roundTrippedItem.endPoint, item.endPoint)
    XCTAssertEqual(roundTrippedItem.shaftThickness, item.shaftThickness)
}

func testBoardDocumentDecodesLegacyArrowGeometryIntoEndpointModel() throws {
    payload["formatVersion"] = 10
    legacyArrowPayload["center"] = ["x": 120.0, "y": 90.0]
    legacyArrowPayload["size"] = ["width": 220.0, "height": 80.0]
    legacyArrowPayload["rotationRadians"] = Double.pi / 8
    // ...
    XCTAssertEqual(arrowItem.shaftThickness, expectedItem.shaftThickness, accuracy: 0.0001)
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests.swift
// 函数名: testArrowEndpointDragPreservesArrowProfile()
// 功能说明: 修改后，测试明确验证拖动端点后，箭头起点固定、终点跟随、整体高度不变、shaftThickness 不变、箭头头部长度不变。
func testArrowEndpointDragPreservesArrowProfile() throws {
    let item = CanvasArrowItem(
        center: CGPoint(x: 120, y: 80),
        size: CGSize(width: 220, height: 80)
    )
    let dragState = CanvasArrowEndpointDragState(
        item: item,
        draggedEndpointRole: .end,
        minimumLength: 1
    )
    let draggedEndPoint = CGPoint(x: 420, y: 180)
    let geometry = dragState.updatedGeometry(draggedWorldPoint: draggedEndPoint)
    let updatedItem = try XCTUnwrap(
        CanvasBoardItem
            .arrow(item)
            .applyingGeometry(geometry)?
            .arrowItem
    )

    let originalHeadLength = item.localFrame.maxX -
        canvasArrowPolygonPoints(in: item.localFrame)[1].x
    let updatedHeadLength = updatedItem.localFrame.maxX -
        canvasArrowPolygonPoints(in: updatedItem.localFrame)[1].x

    XCTAssertEqual(updatedItem.startPoint.x, item.startPoint.x, accuracy: 0.0001)
    XCTAssertEqual(updatedItem.endPoint.x, draggedEndPoint.x, accuracy: 0.0001)
    XCTAssertEqual(updatedItem.size.height, item.size.height, accuracy: 0.0001)
    XCTAssertEqual(updatedItem.shaftThickness, item.shaftThickness, accuracy: 0.0001)
    XCTAssertEqual(originalHeadLength, updatedHeadLength, accuracy: 0.0001)
}
```

### 结果

- 新模型的读写闭环有测试兜底。
- 旧箭头存档的兼容路径有测试兜底。
- “拖端点不会把箭头整体拉伸变形”这个用户侧核心诉求，有了直接回归测试。

## 6. 验证记录

```sh
# 文件路径: 无（终端命令）
# 函数名: xcodebuild test -scheme "MyCanvas_Ver_0" -destination 'platform=macOS' -only-testing:...
# 功能说明: 定向验证箭头几何重做涉及的新增命令、单选 overlay、端点拖拽 profile 保持、新旧存储兼容。
xcodebuild test -scheme "MyCanvas_Ver_0" -destination 'platform=macOS' \
  -only-testing:'MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests/testAddArrowCommandCreatesDefaultHorizontalArrow' \
  -only-testing:'MyCanvas_Ver_0Tests/CanvasCommandPolicyParityTests/testArrowEndpointDragPreservesArrowProfile' \
  -only-testing:'MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests/testMakeCanvasSnapshotUsesEndpointHandlesForSingleArrowSelection' \
  -only-testing:'MyCanvas_Ver_0Tests/BoardSelectionStateMigrationTests/testBoardDocumentMapperRoundTripsArrowItem' \
  -only-testing:'MyCanvas_Ver_0Tests/BoardSelectionStateMigrationTests/testBoardDocumentDecodesLegacyArrowGeometryIntoEndpointModel'
```

```sh
# 文件路径: 无（终端命令输出摘录）
# 函数名: xcodebuild test
# 功能说明: 本次重做完成后，5 个箭头相关定向测试全部通过。
** TEST SUCCEEDED **

Test case 'BoardSelectionStateMigrationTests.testBoardDocumentDecodesLegacyArrowGeometryIntoEndpointModel()' passed
Test case 'BoardSelectionStateMigrationTests.testBoardDocumentMapperRoundTripsArrowItem()' passed
Test case 'CanvasCommandPolicyParityTests.testAddArrowCommandCreatesDefaultHorizontalArrow()' passed
Test case 'CanvasCommandPolicyParityTests.testArrowEndpointDragPreservesArrowProfile()' passed
Test case 'CanvasEditorSessionAlignmentOverlayTests.testMakeCanvasSnapshotUsesEndpointHandlesForSingleArrowSelection()' passed
```

补充说明：

- 已额外检查本次修改文件的 IDE 诊断，未发现新增 linter 错误。
- 本记录文件为新增文件，未覆盖或删除已有 `.md` 文件。
