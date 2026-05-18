# 20260518_202202_CST_hand_drawing_multilayer_phase1_layered_document_record

## 记录范围

- 记录内容：
  1. 实施 `手绘多图层` 计划的阶段 1：`Layered 文档模型与版本演进`。
  2. 把 `HandDrawingDocument` 从单层 `strokes` 升级为 `layers + activeLayerID` 的多 layer 文档模型。
  3. 让 `HandDrawingDocumentCodec` 同时兼容旧 `v1 flat strokes` 文档和新 `v2 layered` 文档。
  4. 补齐阶段 1 的最小测试工装与回归测试。
- 时间戳来源：
  - `date +"%Y%m%d_%H%M%S_%Z"` -> `20260518_202202_CST`
- 说明：
  - 本记录只覆盖刚刚实施的多 layer 阶段 1，不包含阶段 2 之后的渲染、工具、UI 和宿主兼容改造。
  - 本记录基于当前 `git status`、当前 `git diff`、当前文件内容与本轮验证结果整理。
  - 不放原始 `git diff`，只按“修改前 / 修改后”如实说明。
- 参考依据：
  - `git status --short`
  - `git diff -- MyCanvas_Ver_0/Canvas/HandDrawing/Core/HandDrawingDocument.swift MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingDocumentCodec.swift MyCanvas_Ver_0Tests/HandDrawingCoreTestFixtures.swift MyCanvas_Ver_0Tests/HandDrawingDocumentCodecTests.swift MyCanvas_Ver_0Tests/HandDrawingDocumentLoaderTests.swift`
  - 计划文件：
    - `.cursor/plans/手绘多图层_1e238dea.plan.md`
- 当前 changes 摘要：
  - `M MyCanvas_Ver_0/Canvas/HandDrawing/Core/HandDrawingDocument.swift`
  - `M MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingDocumentCodec.swift`
  - `M MyCanvas_Ver_0Tests/HandDrawingCoreTestFixtures.swift`
  - `M MyCanvas_Ver_0Tests/HandDrawingDocumentCodecTests.swift`
  - `M MyCanvas_Ver_0Tests/HandDrawingDocumentLoaderTests.swift`
- 验证结果：
  - `xcodebuild test -scheme "MyCanvas_Ver_0" -project "MyCanvas_Ver_0.xcodeproj" -destination 'platform=macOS,arch=arm64,name=My Mac' -only-testing:MyCanvas_Ver_0Tests/HandDrawingDocumentCodecTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingDocumentLoaderTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingDocumentStoreTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingMigrationServiceTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingEditorEngineTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingPreviewRendererTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingCanvasRendererTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingPixelEraserToolControllerTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingLassoSelectionTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingMoveSelectionTests -only-testing:MyCanvas_Ver_0Tests/CanvasHandDrawingEditingSessionTests -only-testing:MyCanvas_Ver_0Tests/BoardHandDrawingStorageTests`
    - 通过
  - `xcodebuild build -scheme "MyCanvas_Ver_0" -project "MyCanvas_Ver_0.xcodeproj" -destination 'generic/platform=iOS Simulator'`
    - 通过
  - `ReadLints`
    - 本次改动文件未引入新的 linter 问题
- 本记录不包含：
  - 阶段 2 的按 layer 合成渲染
  - 阶段 3 的 engine layer 命令与历史栈
  - 阶段 4 的工具只作用当前 layer
  - 阶段 5 的 iPad layer UI
  - git commit / push

## 修改一：`HandDrawingDocument` 从单层 `strokes` 升级为 `layers + activeLayerID`

### 修改前

- `HandDrawingDocument` 只有 `paper + strokes + formatVersion`。
- `formatVersion` 仍是 `1`。
- 文档级 API 例如 `isEmpty`、`renderedBounds`、`appendStroke(_:)`、`stroke(withID:)` 都默认整个文档只有一层扁平 `strokes`。
- 这种结构无法承载“当前活动层”“图层名称”“显隐/锁定”等多 layer 基础语义。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Core/HandDrawingDocument.swift
// 函数名: HandDrawingDocument.init(paper:strokes:formatVersion:) / appendStroke(_:) / stroke(withID:)
// 功能注释: 修改前文档模型仍是单层扁平 strokes，尚未具备多 layer 结构。
struct HandDrawingDocument: Codable, Equatable {
    static let currentFormatVersion = 1

    let formatVersion: Int
    var paper: HandDrawingPaper
    var strokes: [HandDrawingStroke]

    init(
        paper: HandDrawingPaper = .square,
        strokes: [HandDrawingStroke] = [],
        formatVersion: Int = Self.currentFormatVersion
    ) {
        self.formatVersion = formatVersion
        self.paper = paper
        self.strokes = strokes
    }

    var isEmpty: Bool {
        strokes.allSatisfy(\\.isEmpty)
    }

    var renderedBounds: CGRect? {
        strokes.compactMap(\\.bounds).reduce(nil) { partialResult, bounds in
            partialResult?.union(bounds) ?? bounds
        }
    }

    mutating func appendStroke(_ stroke: HandDrawingStroke) {
        strokes.append(stroke)
    }

    func stroke(withID id: UUID) -> HandDrawingStroke? {
        strokes.first { $0.id == id }
    }
}
```

### 修改后

- 新增 `HandDrawingLayer`：`id`、`name`、`isVisible`、`isLocked`、`strokes`。
- `HandDrawingDocument` 升级为：
  - `formatVersion = 2`
  - `layers`
  - `activeLayerID`
- 补了当前阶段需要的文档级聚合语义：
  - `allStrokes`
  - `activeLayer`
  - `activeLayerIndex`
  - `layer(withID:)`
  - `setActiveLayer(withID:)`
  - `ensureActiveLayerExists()`
  - `replaceStrokesInActiveLayer(with:)`
- 同时保留了过渡兼容入口：`document.strokes` 现在等价于“当前 active layer 的 strokes”，这样现有 engine / renderer / tool 的单层主链先不需要在阶段 1 一次性全改。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Core/HandDrawingDocument.swift
// 函数名: HandDrawingLayer.init(...) / HandDrawingDocument.init(paper:layers:activeLayerID:formatVersion:) / ensureActiveLayerExists()
// 功能注释: 修改后文档模型正式具备多 layer 基础结构，并保留 active layer 兼容入口。
struct HandDrawingLayer: Codable, Equatable {
    let id: UUID
    var name: String
    var isVisible: Bool
    var isLocked: Bool
    var strokes: [HandDrawingStroke]

    init(
        id: UUID = UUID(),
        name: String = "",
        isVisible: Bool = true,
        isLocked: Bool = false,
        strokes: [HandDrawingStroke] = []
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.isVisible = isVisible
        self.isLocked = isLocked
        self.strokes = strokes
    }
}

struct HandDrawingDocument: Codable, Equatable {
    static let currentFormatVersion = 2
    private static let defaultLayerBaseName = "Layer"

    let formatVersion: Int
    var paper: HandDrawingPaper
    private(set) var layers: [HandDrawingLayer]
    private(set) var activeLayerID: UUID

    init(
        paper: HandDrawingPaper = .square,
        layers: [HandDrawingLayer],
        activeLayerID: UUID? = nil,
        formatVersion: Int = Self.currentFormatVersion
    ) {
        self.formatVersion = Self.normalizedFormatVersion(formatVersion)
        self.paper = paper
        let normalizedLayers = Self.normalizedLayers(layers)
        self.layers = normalizedLayers
        self.activeLayerID = Self.resolvedActiveLayerID(
            activeLayerID,
            layers: normalizedLayers
        )
    }

    var strokes: [HandDrawingStroke] {
        get {
            activeLayer?.strokes ?? []
        }
        set {
            replaceStrokesInActiveLayer(with: newValue)
        }
    }

    mutating func ensureActiveLayerExists() -> UUID {
        if let activeLayerIndex {
            return layers[activeLayerIndex].id
        }
        if layers.isEmpty {
            let defaultLayer = Self.makeDefaultLayer(at: 1)
            layers = [defaultLayer]
            activeLayerID = defaultLayer.id
            return defaultLayer.id
        }
        activeLayerID = layers[0].id
        return activeLayerID
    }
}
```

## 修改二：`HandDrawingDocumentCodec` 同时兼容旧 `v1 flat` 和新 `v2 layered`

### 修改前

- `decodeDocument(from:)` 先 probe `formatVersion`，然后要求它必须严格等于 `HandDrawingDocument.currentFormatVersion`。
- 在修改前，`currentFormatVersion` 还是 `1`，所以 codec 只支持一种“扁平 `strokes`”文档形状。
- 一旦把文档模型升成 `layers + activeLayerID`，如果不先做多版本解码分支，旧文档会直接打不开。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingDocumentCodec.swift
// 函数名: decodeDocument(from:)
// 功能注释: 修改前 codec 只接受与 currentFormatVersion 完全相等的单一文档版本。
static func decodeDocument(from data: Data) throws -> HandDrawingDocument {
    let decoder = JSONDecoder()
    let formatProbe: FormatVersionProbe
    do {
        formatProbe = try decoder.decode(FormatVersionProbe.self, from: data)
    } catch {
        throw HandDrawingDocumentCodecError.invalidDocumentData
    }
    guard formatProbe.formatVersion == HandDrawingDocument.currentFormatVersion else {
        throw HandDrawingDocumentCodecError.unsupportedDocumentFormatVersion(
            formatProbe.formatVersion
        )
    }
    do {
        return try decoder.decode(HandDrawingDocument.self, from: data)
    } catch {
        throw HandDrawingDocumentCodecError.invalidDocumentData
    }
}
```

### 修改后

- 新增两种 payload：
  - `LegacyFlatDocumentPayload`
  - `LayeredDocumentPayload`
- `decodeDocument(from:)` 现在支持的版本集合是：
  - `1`：旧 flat 文档
  - `HandDrawingDocument.currentFormatVersion`：当前 layered 文档
- 旧 `v1 flat` 解码后，不是简单返回旧结构，而是立即构造成新的 `HandDrawingDocument(paper:strokes:)`，借助新的初始化逻辑自动包装成默认层。
- 新 `v2 layered` 则解码 `layers + activeLayerID` 后返回当前模型。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingDocumentCodec.swift
// 函数名: decodeDocument(from:) / decodeLegacyFlatDocument(from:using:) / decodeLayeredDocument(from:using:)
// 功能注释: 修改后 codec 具备 v1 flat -> v2 layered 的兼容解码能力。
private struct LegacyFlatDocumentPayload: Decodable {
    let formatVersion: Int
    let paper: HandDrawingPaper
    let strokes: [HandDrawingStroke]
}

private struct LayeredDocumentPayload: Decodable {
    let formatVersion: Int
    let paper: HandDrawingPaper
    let layers: [HandDrawingLayer]
    let activeLayerID: UUID
}

static func decodeDocument(from data: Data) throws -> HandDrawingDocument {
    let decoder = JSONDecoder()
    let formatProbe: FormatVersionProbe
    do {
        formatProbe = try decoder.decode(FormatVersionProbe.self, from: data)
    } catch {
        throw HandDrawingDocumentCodecError.invalidDocumentData
    }
    guard supportedDocumentFormatVersions.contains(formatProbe.formatVersion) else {
        throw HandDrawingDocumentCodecError.unsupportedDocumentFormatVersion(
            formatProbe.formatVersion
        )
    }

    switch formatProbe.formatVersion {
    case 1:
        return try decodeLegacyFlatDocument(
            from: data,
            using: decoder
        )
    case HandDrawingDocument.currentFormatVersion:
        return try decodeLayeredDocument(
            from: data,
            using: decoder
        )
    default:
        throw HandDrawingDocumentCodecError.unsupportedDocumentFormatVersion(
            formatProbe.formatVersion
        )
    }
}

private static func decodeLegacyFlatDocument(
    from data: Data,
    using decoder: JSONDecoder
) throws -> HandDrawingDocument {
    let legacyPayload = try decoder.decode(
        LegacyFlatDocumentPayload.self,
        from: data
    )
    return HandDrawingDocument(
        paper: legacyPayload.paper,
        strokes: legacyPayload.strokes
    )
}
```

## 修改三：测试工装升级，并补阶段 1 的 layered / migration 定点测试

### 修改前

- `HandDrawingCoreTestFixtures.swift` 只能快速构造单层 `HandDrawingDocument(strokes: ...)`。
- `HandDrawingDocumentCodecTests.swift` 只覆盖：
  - 当前文档 round-trip
  - manifest round-trip
  - preview PNG round-trip
  - 非法 preview / 非法 formatVersion
- `HandDrawingDocumentLoaderTests.swift` 只验证：
  - typed document 能加载
  - legacy `PKDrawing` 能转成单层文档
- 在文档模型升成 layered 之后，如果没有专门的 fixture 和定点测试，就很难确保“旧 flat -> 默认层”“空数据 -> 默认层”“新 layered -> round-trip”这些阶段 1 的核心目标真的落稳。

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingCoreTestFixtures.swift
// 函数名: makeHandDrawingTestDocument(...)
// 功能注释: 修改前测试工装只能快速构造单层文档，不方便表达多 layer 文档。
func makeHandDrawingTestDocument(
    paper: HandDrawingPaper = HandDrawingPaper(
        id: "stage4-paper",
        size: CGSize(width: 120, height: 120)
    ),
    includeEraseMask: Bool = false
) -> HandDrawingDocument {
    HandDrawingDocument(
        paper: paper,
        strokes: [
            makeHandDrawingTestStroke(includeEraseMask: includeEraseMask)
        ]
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingDocumentLoaderTests.swift
// 函数名: testHandDrawingDocumentLoaderLoadsTypedDocumentData() / testHandDrawingDocumentLoaderConvertsLegacyPencilKitDrawing()
// 功能注释: 修改前 loader tests 还没有显式验证默认 layer 包装语义。
func testHandDrawingDocumentLoaderLoadsTypedDocumentData() throws {
    let document = makeHandDrawingTestDocument(includeEraseMask: true)
    let documentData = try HandDrawingDocumentCodec.makeDocumentData(
        for: document
    )
    let loadedDocument = try HandDrawingDocumentLoader.loadDocument(
        from: documentData,
        paper: document.paper.canvasPaperSpec
    )

    XCTAssertEqual(loadedDocument, document)
}
```

### 修改后

- `HandDrawingCoreTestFixtures.swift` 新增：
  - `makeHandDrawingLayeredTestDocument(...)`
  - `makeHandDrawingTestLayer(...)`
- `HandDrawingDocumentCodecTests.swift`：
  - 把原 round-trip 测试升级成真正的 layered 文档 round-trip
  - 新增 `testHandDrawingDocumentCodecDecodesLegacyFlatDocumentAsDefaultLayeredDocument()`
- `HandDrawingDocumentLoaderTests.swift`：
  - typed document 测试升级为 layered 输入
  - 新增 `testHandDrawingDocumentLoaderBuildsDefaultLayeredDocumentForEmptyData()`
  - legacy `PKDrawing` 测试新增默认层断言
- 这批测试没有提前去测 layer UI 或工具行为，只聚焦阶段 1 要保证的模型和迁移边界。

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingCoreTestFixtures.swift
// 函数名: makeHandDrawingLayeredTestDocument(...) / makeHandDrawingTestLayer(...)
// 功能注释: 修改后测试工装可以直接构造 layered document 和 layer，方便阶段 1 定点测试。
func makeHandDrawingLayeredTestDocument(
    paper: HandDrawingPaper = HandDrawingPaper(
        id: "stage4-paper",
        size: CGSize(width: 120, height: 120)
    ),
    layers: [HandDrawingLayer],
    activeLayerID: UUID? = nil
) -> HandDrawingDocument {
    HandDrawingDocument(
        paper: paper,
        layers: layers,
        activeLayerID: activeLayerID
    )
}

func makeHandDrawingTestLayer(
    id: UUID = UUID(),
    name: String = "Layer 1",
    isVisible: Bool = true,
    isLocked: Bool = false,
    strokes: [HandDrawingStroke]
) -> HandDrawingLayer {
    HandDrawingLayer(
        id: id,
        name: name,
        isVisible: isVisible,
        isLocked: isLocked,
        strokes: strokes
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingDocumentCodecTests.swift
// 函数名: testHandDrawingDocumentCodecRoundTripsCustomDocument() / testHandDrawingDocumentCodecDecodesLegacyFlatDocumentAsDefaultLayeredDocument()
// 功能注释: 修改后 codec tests 同时覆盖 layered round-trip 与旧 flat 文档自动包装默认层。
func testHandDrawingDocumentCodecRoundTripsCustomDocument() throws {
    let baseLayer = makeHandDrawingTestLayer(
        name: "Sketch",
        strokes: [baseStroke]
    )
    let detailLayer = makeHandDrawingTestLayer(
        name: "Details",
        strokes: [erasedStroke]
    )
    let document = makeHandDrawingLayeredTestDocument(
        layers: [baseLayer, detailLayer],
        activeLayerID: detailLayer.id
    )

    let data = try HandDrawingDocumentCodec.makeDocumentData(for: document)
    let decodedDocument = try HandDrawingDocumentCodec.decodeDocument(from: data)

    XCTAssertEqual(decodedDocument, document)
}

func testHandDrawingDocumentCodecDecodesLegacyFlatDocumentAsDefaultLayeredDocument() throws {
    let legacyDocument = makeHandDrawingTestDocument(includeEraseMask: true)
    let legacyData = try makeLegacyFlatDocumentData(
        paper: legacyDocument.paper,
        strokes: legacyDocument.strokes
    )

    let decodedDocument = try HandDrawingDocumentCodec.decodeDocument(
        from: legacyData
    )
    let decodedLayer = try XCTUnwrap(decodedDocument.layers.first)

    XCTAssertEqual(decodedDocument.layers.count, 1)
    XCTAssertEqual(decodedDocument.activeLayerID, decodedLayer.id)
    XCTAssertEqual(decodedLayer.name, "Layer 1")
    XCTAssertEqual(decodedLayer.strokes, legacyDocument.strokes)
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingDocumentLoaderTests.swift
// 函数名: testHandDrawingDocumentLoaderLoadsTypedDocumentData() / testHandDrawingDocumentLoaderBuildsDefaultLayeredDocumentForEmptyData() / testHandDrawingDocumentLoaderConvertsLegacyPencilKitDrawing()
// 功能注释: 修改后 loader tests 覆盖三条入口：新 layered 文档、空数据、旧 PKDrawing。
func testHandDrawingDocumentLoaderLoadsTypedDocumentData() throws {
    let baseLayer = makeHandDrawingTestLayer(
        name: "Sketch",
        strokes: [
            makeHandDrawingTestStroke(id: UUID())
        ]
    )
    let detailLayer = makeHandDrawingTestLayer(
        name: "Ink",
        strokes: [
            makeHandDrawingTestStroke(
                id: UUID(),
                includeEraseMask: true,
                transform: HandDrawingStrokeTransform(translationY: 20)
            )
        ]
    )
    let document = makeHandDrawingLayeredTestDocument(
        layers: [baseLayer, detailLayer],
        activeLayerID: detailLayer.id
    )
    let documentData = try HandDrawingDocumentCodec.makeDocumentData(
        for: document
    )

    let loadedDocument = try HandDrawingDocumentLoader.loadDocument(
        from: documentData,
        paper: document.paper.canvasPaperSpec
    )

    XCTAssertEqual(loadedDocument, document)
}

func testHandDrawingDocumentLoaderBuildsDefaultLayeredDocumentForEmptyData() throws {
    let loadedDocument = try HandDrawingDocumentLoader.loadDocument(
        from: Data(),
        paper: .square
    )
    let loadedLayer = try XCTUnwrap(loadedDocument.layers.first)

    XCTAssertEqual(loadedDocument.layers.count, 1)
    XCTAssertEqual(loadedDocument.activeLayerID, loadedLayer.id)
    XCTAssertEqual(loadedLayer.name, "Layer 1")
}
```

## 结果小结

- 阶段 1 这次没有直接改渲染器、工具控制器或 iPad layer UI，而是先把文档模型和版本兼容打稳。
- 当前真实状态是：
  - 文档本体已经是 `layers + activeLayerID`
  - 旧 flat 文档可以自动包装成默认层
  - 现有单层主链仍可通过 `document.strokes` 这个过渡兼容入口继续工作
- 这样后续阶段 2-5 可以在不破坏当前主链的前提下，逐步把 renderer、engine、tool、UI 收口到真正的多 layer 语义。
