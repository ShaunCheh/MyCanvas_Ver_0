# 20260518_160130_hand_drawing_kernel_phase4_engine_core_record

## 记录范围

- 记录内容：
  1. 新增 handDrawing 自研文档模型，把 `stroke`、`sample`、`brush`、`transform`、`eraseMask` 正式建模。
  2. 扩展 `HandDrawingDocumentCodec` / `HandDrawingDocumentStore`，让 `document.hdraw` 不再只是黑盒 `Data`，而是可编解码、可 round-trip 的 typed document。
  3. 新增不依赖 UIKit 的编辑内核骨架：`HandDrawingEditorEngine`、`HandDrawingHistoryController`、`HandDrawingDirtyRegionTracker`。
  4. 新增 `HandDrawingPreviewRenderer`，支持基于自研文档直接导出 preview，并让局部擦除从一开始就是 stroke-local 合成语义。
  5. 补充阶段 4 的 fixtures / codec / store / engine / renderer 测试，并保留阶段 2、3 既有链路回归验证。
- 时间戳来源：
  - `date +"%Y%m%d_%H%M%S"` -> `20260518_160130`
- 说明：
  - 本记录中的“修改前”以阶段 3 完成态为基线，不回退到更早版本。
  - 对于本阶段新增文件，修改前如实记录为“文件不存在”。
  - 对于已跟踪文件，本记录结合当前 `git diff`、当前文件内容和当前 `git status` 整理，不放原始 diff。
- 参考依据：
  - `git status --short -- "MyCanvas_Ver_0/Canvas/HandDrawing" "MyCanvas_Ver_0Tests/HandDrawingCoreTestFixtures.swift" "MyCanvas_Ver_0Tests/HandDrawingDocumentCodecTests.swift" "MyCanvas_Ver_0Tests/HandDrawingDocumentStoreTests.swift" "MyCanvas_Ver_0Tests/HandDrawingEditorEngineTests.swift" "MyCanvas_Ver_0Tests/HandDrawingPreviewRendererTests.swift"`
  - `git diff -- "MyCanvas_Ver_0/Canvas/HandDrawing" "MyCanvas_Ver_0Tests/HandDrawingCoreTestFixtures.swift" "MyCanvas_Ver_0Tests/HandDrawingDocumentCodecTests.swift" "MyCanvas_Ver_0Tests/HandDrawingDocumentStoreTests.swift" "MyCanvas_Ver_0Tests/HandDrawingEditorEngineTests.swift" "MyCanvas_Ver_0Tests/HandDrawingPreviewRendererTests.swift"`
  - 阶段 3 记录：
    - `commit_records/20260518_152750_hand_drawing_kernel_phase3_lazy_migration_record.md`
- 当前工作区涉及文件：
  - `MyCanvas_Ver_0/Canvas/HandDrawing/Core/HandDrawingDocument.swift`
  - `MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingEditorEngine.swift`
  - `MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingHistoryController.swift`
  - `MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingDirtyRegionTracker.swift`
  - `MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingPreviewRenderer.swift`
  - `MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingDocumentCodec.swift`
  - `MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingDocumentStore.swift`
  - `MyCanvas_Ver_0Tests/HandDrawingCoreTestFixtures.swift`
  - `MyCanvas_Ver_0Tests/HandDrawingDocumentCodecTests.swift`
  - `MyCanvas_Ver_0Tests/HandDrawingDocumentStoreTests.swift`
  - `MyCanvas_Ver_0Tests/HandDrawingEditorEngineTests.swift`
  - `MyCanvas_Ver_0Tests/HandDrawingPreviewRendererTests.swift`
- 当前 changes 摘要：
  - `M MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingDocumentCodec.swift`
  - `M MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingDocumentStore.swift`
  - `M MyCanvas_Ver_0Tests/HandDrawingDocumentStoreTests.swift`
  - `?? MyCanvas_Ver_0/Canvas/HandDrawing/Core/HandDrawingDocument.swift`
  - `?? MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingEditorEngine.swift`
  - `?? MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingHistoryController.swift`
  - `?? MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingDirtyRegionTracker.swift`
  - `?? MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingPreviewRenderer.swift`
  - `?? MyCanvas_Ver_0Tests/HandDrawingCoreTestFixtures.swift`
  - `?? MyCanvas_Ver_0Tests/HandDrawingDocumentCodecTests.swift`
  - `?? MyCanvas_Ver_0Tests/HandDrawingEditorEngineTests.swift`
  - `?? MyCanvas_Ver_0Tests/HandDrawingPreviewRendererTests.swift`
- 验证结果：
  - `xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=macOS" -only-testing:"MyCanvas_Ver_0Tests/HandDrawingDocumentCodecTests" -only-testing:"MyCanvas_Ver_0Tests/HandDrawingDocumentStoreTests" -only-testing:"MyCanvas_Ver_0Tests/HandDrawingEditorEngineTests" -only-testing:"MyCanvas_Ver_0Tests/HandDrawingPreviewRendererTests"`
    - 通过
  - `xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=macOS" -only-testing:"MyCanvas_Ver_0Tests/HandDrawingDocumentCodecTests" -only-testing:"MyCanvas_Ver_0Tests/HandDrawingDocumentStoreTests" -only-testing:"MyCanvas_Ver_0Tests/HandDrawingEditorEngineTests" -only-testing:"MyCanvas_Ver_0Tests/HandDrawingPreviewRendererTests" -only-testing:"MyCanvas_Ver_0Tests/HandDrawingMigrationServiceTests" -only-testing:"MyCanvas_Ver_0Tests/BoardHandDrawingStorageTests" -only-testing:"MyCanvas_Ver_0Tests/CanvasHandDrawingEditingSessionTests" -only-testing:"MyCanvas_Ver_0Tests/HandDrawingPreviewPipelineTests"`
    - 通过
  - `ReadLints`
    - 本次改动文件未引入新的 linter 问题
- 本记录不包含：
  - 阶段 5 的 iPad 编辑器壳、surface view 与 palette 接入
  - 阶段 6 的 pressure 驱动像素橡皮
  - 阶段 7 的套索选择与移动
  - git commit / push

## 修改一：新增自研文档模型，把 `document.hdraw` 的业务语义从黑盒 `Data` 提升为结构化 document

### 修改前

- 阶段 3 已经完成 bundle persistence 和懒迁移，但 `document.hdraw` 仍然只是被当作一段原始二进制内容读写。
- 项目里还没有 handDrawing 自研文档模型文件，也没有 `stroke` / `brush` / `sample` / `eraseMask` 这一层的 typed contract。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Core/HandDrawingDocument.swift
// 函数名: 无
// 功能说明: 阶段3完成态下，项目里还不存在自研 handDrawing 文档模型文件。
// 修改前不存在该文件。
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingDocumentStore.swift
// 函数名: loadDocumentData(...) / persistDocument(documentID:paper:contentRevision:isEmpty:drawingData:previewImageData:previewCGImage:boardDirectoryURL:migrationOrigin:legacyBackupDrawingData:)
// 功能说明: 阶段3完成态下，store 只能把 handDrawing 文档当成原始 Data 读取和写入。
enum HandDrawingDocumentStore {
    static func loadDocumentData(
        documentID: HandDrawingDocumentID,
        boardDirectoryURL: URL
    ) throws -> Data {
        let locator = HandDrawingBundleLocator(documentID: documentID)
        let documentURL = locator.documentURL(in: boardDirectoryURL)
        // 其余 bundle 校验逻辑省略
        return try CoordinatedFileIO.readData(at: documentURL)
    }

    static func persistDocument(
        documentID: HandDrawingDocumentID,
        paper: CanvasHandDrawingPaperSpec,
        contentRevision: UUID,
        isEmpty: Bool,
        drawingData: Data,
        previewImageData: Data?,
        previewCGImage: CGImage?,
        boardDirectoryURL: URL,
        migrationOrigin: HandDrawingManifestMigrationOrigin? = nil,
        legacyBackupDrawingData: Data? = nil
    ) throws {
        // 修改前只负责直接写入 manifest / document / preview。
    }
}
```

### 修改后

- 新增 `HandDrawingDocument.swift`，把自研文档层正式建出来。
- `HandDrawingDocument` 以 `strokes` 为核心集合，每笔 `HandDrawingStroke` 都显式携带：
  - `brush`
  - `samplePoints`
  - `transform`
  - `eraseMask`
- `HandDrawingPaper`、`HandDrawingColor`、`HandDrawingSamplePoint`、`HandDrawingErasePath` 这些底层值对象也一起落地，后面阶段 5 到 7 的编辑 UI / 橡皮 / 套索都可以直接挂在这套模型上。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Core/HandDrawingDocument.swift
// 函数名: HandDrawingBrushStyle.init(...) / HandDrawingStroke.init(...) / HandDrawingDocument.init(...) / appendStroke(_:)
// 功能说明: 修改后 handDrawing 有了独立文档模型，stroke 成为一等对象，并为 transform 与局部擦除遮罩预留稳定数据边界。
struct HandDrawingBrushStyle: Codable, Equatable {
    enum Kind: String, Codable, Equatable {
        case pen
    }

    static let defaultPen = HandDrawingBrushStyle(
        kind: .pen,
        color: .black,
        baseSize: 6,
        opacity: 1
    )

    var kind: Kind
    var color: HandDrawingColor
    var baseSize: Double
    var opacity: Double
}

struct HandDrawingStroke: Codable, Equatable {
    let id: UUID
    var brush: HandDrawingBrushStyle
    var samplePoints: [HandDrawingSamplePoint]
    var transform: HandDrawingStrokeTransform
    var eraseMask: [HandDrawingErasePath]
}

struct HandDrawingDocument: Codable, Equatable {
    static let currentFormatVersion = 1

    let formatVersion: Int
    var paper: HandDrawingPaper
    var strokes: [HandDrawingStroke]

    var paperBounds: CGRect {
        CGRect(origin: .zero, size: paper.size)
    }

    var isEmpty: Bool {
        strokes.allSatisfy(\.isEmpty)
    }

    mutating func appendStroke(_ stroke: HandDrawingStroke) {
        strokes.append(stroke)
    }
}
```

## 修改二：扩展 codec/store，让 `document.hdraw` 支持 typed 编解码与 round-trip

### 修改前

- `HandDrawingDocumentCodec` 只负责：
  - `manifest.json` 的 JSON 编解码
  - `preview.png` 的 PNG 编解码
- `HandDrawingDocumentStore` 只能返回 `Data`，并没有 `loadDocument(...)` / `persistDocument(_ document: ...)` 这种 typed API。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingDocumentCodec.swift
// 函数名: makeManifestData(for:) / decodeManifest(from:) / makePNGData(...) / decodePreviewImage(...)
// 功能说明: 阶段3完成态下，codec 还没有自研 handDrawing document 的编解码能力。
enum HandDrawingDocumentCodec {
    static func makeManifestData(for manifest: HandDrawingManifest) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(manifest)
    }

    static func decodeManifest(from data: Data) throws -> HandDrawingManifest {
        let decoder = JSONDecoder()
        return try decoder.decode(HandDrawingManifest.self, from: data)
    }

    static func makePNGData(
        for previewImage: CGImage,
        documentID: HandDrawingDocumentID
    ) throws -> Data {
        // PNG 编码逻辑省略
    }
}
```

### 修改后

- `HandDrawingDocumentCodec` 新增：
  - `makeDocumentData(for:)`
  - `decodeDocument(from:)`
  - `FormatVersionProbe`
  - `invalidDocumentData` / `unsupportedDocumentFormatVersion` 错误
- `HandDrawingDocumentStore` 新增：
  - `loadDocument(...)`
  - `persistDocument(_ document:documentID:contentRevision:previewImageData:previewCGImage:boardDirectoryURL:migrationOrigin:legacyBackupDrawingData:)`
- 结果是：
  - `document.hdraw` 现在可以按自研模型稳定 round-trip。
  - `formatVersion` 在 codec 层先被探测和校验，而不是交给更外层逻辑猜测。
  - 旧的 raw `Data` API 仍然保留，阶段 2、3 链路没有被打断。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingDocumentCodec.swift
// 函数名: makeDocumentData(for:) / decodeDocument(from:)
// 功能说明: 修改后 codec 可以直接把自研 HandDrawingDocument 编解码为 document.hdraw，并在解码前先探测 formatVersion。
enum HandDrawingDocumentCodec {
    private struct FormatVersionProbe: Decodable {
        let formatVersion: Int
    }

    static func makeDocumentData(for document: HandDrawingDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }

    static func decodeDocument(from data: Data) throws -> HandDrawingDocument {
        let decoder = JSONDecoder()
        let formatProbe = try decoder.decode(FormatVersionProbe.self, from: data)
        guard formatProbe.formatVersion == HandDrawingDocument.currentFormatVersion else {
            throw HandDrawingDocumentCodecError.unsupportedDocumentFormatVersion(
                formatProbe.formatVersion
            )
        }
        return try decoder.decode(HandDrawingDocument.self, from: data)
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Persistence/HandDrawingDocumentStore.swift
// 函数名: loadDocument(...) / persistDocument(_ document:documentID:contentRevision:previewImageData:previewCGImage:boardDirectoryURL:migrationOrigin:legacyBackupDrawingData:)
// 功能说明: 修改后 store 同时支持 raw Data 与 typed document 两条持久化路径，为 headless engine/save 流程提供稳定入口。
enum HandDrawingDocumentStore {
    static func loadDocument(
        documentID: HandDrawingDocumentID,
        boardDirectoryURL: URL
    ) throws -> HandDrawingDocument {
        try HandDrawingDocumentCodec.decodeDocument(
            from: loadDocumentData(
                documentID: documentID,
                boardDirectoryURL: boardDirectoryURL
            )
        )
    }

    static func persistDocument(
        _ document: HandDrawingDocument,
        documentID: HandDrawingDocumentID,
        contentRevision: UUID,
        previewImageData: Data?,
        previewCGImage: CGImage?,
        boardDirectoryURL: URL,
        migrationOrigin: HandDrawingManifestMigrationOrigin? = nil,
        legacyBackupDrawingData: Data? = nil
    ) throws {
        try persistDocument(
            documentID: documentID,
            paper: document.paper.canvasPaperSpec,
            contentRevision: contentRevision,
            isEmpty: document.isEmpty,
            drawingData: try HandDrawingDocumentCodec.makeDocumentData(for: document),
            previewImageData: previewImageData,
            previewCGImage: previewCGImage,
            boardDirectoryURL: boardDirectoryURL,
            migrationOrigin: migrationOrigin,
            legacyBackupDrawingData: legacyBackupDrawingData
        )
    }
}
```

## 修改三：新增无 UI 编辑内核骨架，支持追加笔迹、历史栈、dirty region 与导出

### 修改前

- 阶段 3 还没有独立的 headless engine。
- 项目里也没有 history controller 和 dirty region tracker 这两个基础组件。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingEditorEngine.swift
// 函数名: 无
// 功能说明: 阶段3完成态下，项目里还没有 handDrawing 的无 UI 编辑内核文件。
// 修改前不存在该文件。
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingHistoryController.swift
// 函数名: 无
// 功能说明: 阶段3完成态下，项目里还没有独立的撤销/重做历史控制器。
// 修改前不存在该文件。
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingDirtyRegionTracker.swift
// 函数名: 无
// 功能说明: 阶段3完成态下，项目里还没有 handDrawing dirty region 聚合器。
// 修改前不存在该文件。
```

### 修改后

- 新增 `HandDrawingEditorEngine`，能在不依赖 UIKit / `PKCanvasView` 的情况下直接工作。
- 当前 engine 已具备的能力：
  - 从 `HandDrawingDocument` 或 `documentData` 初始化
  - 追加笔迹
  - 选择 / 取消选择
  - undo / redo
  - 导出 typed document data
  - 直接请求 preview image
  - 追踪并消费 dirty region
- 新增 `HandDrawingHistoryController`，明确维护 undo/redo 快照栈。
- 新增 `HandDrawingDirtyRegionTracker`，把多次局部更新合并为一个脏区输出。
- 最终实现把 `engine` / `historyController` 收敛为值语义 `struct`，避免默认 `MainActor` 隔离环境下 class deinit 生命周期问题污染测试链路。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingEditorEngine.swift
// 函数名: init(documentData:) / appendStroke(...) / selectStrokes(withIDs:) / apply(command:) / undo() / redo() / encodedDocumentData() / renderPreviewImage(...) / consumeDirtyRegion()
// 功能说明: 修改后 editor engine 已经能 headless 地加载文档、追加笔迹、管理历史、导出文档并驱动 preview 渲染。
struct HandDrawingEditorEngine {
    private let previewRenderer: HandDrawingPreviewRenderer
    private var historyController: HandDrawingHistoryController

    private(set) var state: HandDrawingEditorState
    private(set) var dirtyRegionTracker = HandDrawingDirtyRegionTracker()

    init(documentData: Data) throws {
        self.init(
            document: try HandDrawingDocumentCodec.decodeDocument(from: documentData)
        )
    }

    @discardableResult
    mutating func appendStroke(
        brush: HandDrawingBrushStyle,
        samples: [HandDrawingInputSample],
        transform: HandDrawingStrokeTransform = .identity
    ) -> HandDrawingStroke? {
        guard samples.isEmpty == false else {
            return nil
        }
        let stroke = HandDrawingStroke(
            brush: brush,
            samplePoints: samples.map {
                HandDrawingSamplePoint(
                    point: $0.location,
                    force: Double($0.force),
                    timestamp: $0.timestamp,
                    azimuthRadians: $0.azimuthRadians.map(Double.init),
                    altitudeRadians: $0.altitudeRadians.map(Double.init)
                )
            },
            transform: transform
        )
        return appendStroke(stroke)
    }

    @discardableResult
    mutating func undo() -> Bool {
        guard let snapshot = historyController.undo(current: makeSnapshot()) else {
            return false
        }
        restore(snapshot: snapshot)
        return true
    }

    func encodedDocumentData() throws -> Data {
        try HandDrawingDocumentCodec.makeDocumentData(for: state.document)
    }

    func renderPreviewImage(
        scale: CGFloat = 1,
        backgroundColor: HandDrawingColor? = nil
    ) throws -> CGImage {
        try previewRenderer.renderPreviewImage(
            for: state.document,
            scale: scale,
            backgroundColor: backgroundColor
        )
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingHistoryController.swift
// 函数名: record(snapshot:) / undo(current:) / redo(current:)
// 功能说明: 修改后历史控制器把 document 快照与 selectedStrokeIDs 一起纳入撤销/重做栈。
struct HandDrawingHistorySnapshot: Equatable {
    var document: HandDrawingDocument
    var selectedStrokeIDs: Set<UUID>
}

struct HandDrawingHistoryController {
    private var undoStack: [HandDrawingHistorySnapshot] = []
    private var redoStack: [HandDrawingHistorySnapshot] = []

    mutating func record(snapshot: HandDrawingHistorySnapshot) {
        undoStack.append(snapshot)
        redoStack.removeAll()
    }

    mutating func undo(
        current: HandDrawingHistorySnapshot
    ) -> HandDrawingHistorySnapshot? {
        guard let previousSnapshot = undoStack.popLast() else {
            return nil
        }
        redoStack.append(current)
        return previousSnapshot
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingDirtyRegionTracker.swift
// 函数名: markDirty(_:) / consumeDirtyRegion() / reset()
// 功能说明: 修改后 dirty region tracker 会把多次局部脏区聚合为 union，并在消费后清空。
struct HandDrawingDirtyRegionTracker {
    private(set) var dirtyRegion: CGRect?

    mutating func markDirty(_ rect: CGRect?) {
        guard let rect, rect.isNull == false, rect.isEmpty == false else {
            return
        }
        dirtyRegion = dirtyRegion?.union(rect) ?? rect
    }

    mutating func consumeDirtyRegion() -> CGRect? {
        defer {
            dirtyRegion = nil
        }
        return dirtyRegion
    }
}
```

## 修改四：新增 preview renderer，把 preview 导出逻辑从宿主链路里提前抽成内核能力

### 修改前

- 阶段 3 没有 `HandDrawingPreviewRenderer` 文件。
- preview 仍然主要依赖外层 bundle 中已有的 `preview.png`，自研 document 还没有直接渲染能力。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingPreviewRenderer.swift
// 函数名: 无
// 功能说明: 阶段3完成态下，项目里还没有基于自研 handDrawing document 的 preview renderer。
// 修改前不存在该文件。
```

### 修改后

- 新增 `HandDrawingPreviewRenderer`。
- 渲染策略不是把整张纸全局 replay，而是：
  - 每个 stroke 先在单独 bitmap context 里画 ink
  - 再在这个 stroke-local context 上应用 `eraseMask`
  - 最后把 stroke image 合成到总图
- 这样后续阶段 6 的“像素式局部擦除”可以继续沿着 stroke-local 语义往前走，而不会反向把架构逼回整张纸重放。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingPreviewRenderer.swift
// 函数名: renderPreviewImage(for:scale:backgroundColor:) / drawStroke(_:into:pixelWidth:pixelHeight:scale:) / drawStrokeInk(_:in:) / applyEraseMask(_:transform:in:)
// 功能说明: 修改后 preview renderer 能直接从自研 document 导出预览图，并把局部擦除限制在单笔 stroke 的离屏合成上下文中。
struct HandDrawingPreviewRenderer {
    func renderPreviewImage(
        for document: HandDrawingDocument,
        scale: CGFloat = 1,
        backgroundColor: HandDrawingColor? = nil
    ) throws -> CGImage {
        let resolvedScale = max(scale, 0.25)
        let paperSize = document.paper.size
        let pixelWidth = max(Int(ceil(paperSize.width * resolvedScale)), 1)
        let pixelHeight = max(Int(ceil(paperSize.height * resolvedScale)), 1)
        let compositeContext = try makeBitmapContext(
            width: pixelWidth,
            height: pixelHeight
        )

        for stroke in document.strokes where stroke.isEmpty == false {
            try drawStroke(
                stroke,
                into: compositeContext,
                pixelWidth: pixelWidth,
                pixelHeight: pixelHeight,
                scale: resolvedScale
            )
        }

        guard let image = compositeContext.makeImage() else {
            throw HandDrawingPreviewRendererError.failedToCreatePreviewImage
        }
        return image
    }

    private func drawStroke(
        _ stroke: HandDrawingStroke,
        into compositeContext: CGContext,
        pixelWidth: Int,
        pixelHeight: Int,
        scale: CGFloat
    ) throws {
        let strokeContext = try makeBitmapContext(
            width: pixelWidth,
            height: pixelHeight
        )
        strokeContext.scaleBy(x: scale, y: scale)
        drawStrokeInk(stroke, in: strokeContext)
        applyEraseMask(stroke.eraseMask, transform: stroke.transform, in: strokeContext)
        guard let strokeImage = strokeContext.makeImage() else {
            throw HandDrawingPreviewRendererError.failedToCreatePreviewImage
        }
        compositeContext.draw(
            strokeImage,
            in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
        )
    }

    private func applyEraseMask(
        _ eraseMask: [HandDrawingErasePath],
        transform: HandDrawingStrokeTransform,
        in context: CGContext
    ) {
        guard eraseMask.isEmpty == false else {
            return
        }

        context.saveGState()
        context.setBlendMode(.clear)
        // 其余单笔局部擦除逻辑省略
        context.restoreGState()
    }
}
```

## 修改五：补齐阶段 4 fixtures 与专用测试，把 codec / store / engine / renderer 都拉进回归面

### 修改前

- 阶段 3 之前只有：
  - `HandDrawingDocumentStoreTests` 对 bundle raw `Data` round-trip 和 orphan cleanup 的验证
  - 以及阶段 2、3 既有的 storage / migration / session / preview pipeline 回归
- 还没有：
  - handDrawing core test fixtures
  - document codec tests
  - editor engine tests
  - preview renderer tests

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingCoreTestFixtures.swift
// 函数名: 无
// 功能说明: 阶段3完成态下，项目里还没有 handDrawing core 的共享测试夹具文件。
// 修改前不存在该文件。
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingDocumentCodecTests.swift / MyCanvas_Ver_0Tests/HandDrawingEditorEngineTests.swift / MyCanvas_Ver_0Tests/HandDrawingPreviewRendererTests.swift
// 函数名: 无
// 功能说明: 阶段3完成态下，还没有针对自研 codec / engine / preview renderer 的专用测试文件。
// 修改前不存在这些文件。
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingDocumentStoreTests.swift
// 函数名: testHandDrawingDocumentStorePersistsBundleRoundTrip() / testHandDrawingDocumentStoreRemovesOrphanedBundles()
// 功能说明: 阶段3完成态下，store tests 只覆盖原始 Data round-trip 和 orphan cleanup。
final class HandDrawingDocumentStoreTests: XCTestCase {
    func testHandDrawingDocumentStorePersistsBundleRoundTrip() throws {
        // 验证 raw drawingData + previewImage 能正常落 bundle。
    }

    func testHandDrawingDocumentStoreRemovesOrphanedBundles() throws {
        // 验证 orphan bundle 会被删除。
    }
}
```

### 修改后

- 新增 `HandDrawingCoreTestFixtures.swift`，统一生成测试 document / stroke / RGBA 采样辅助，避免阶段 4 之后每个测试文件自己拼一套文档样本。
- 新增：
  - `HandDrawingDocumentCodecTests`
  - `HandDrawingEditorEngineTests`
  - `HandDrawingPreviewRendererTests`
- 扩展 `HandDrawingDocumentStoreTests`，增加 typed document round-trip 验证。
- 这批测试既覆盖阶段 4 的新内核，也继续保留阶段 2、3 的 bundle / migration / session 回归。

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingCoreTestFixtures.swift
// 函数名: makeHandDrawingTestDocument(...) / makeHandDrawingTestStroke(...) / sampleRGBA(from:x:y:)
// 功能说明: 修改后共享测试夹具统一生成文档、笔迹、局部擦除样本和像素采样工具，供 codec / engine / renderer / store 测试复用。
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

func makeHandDrawingTestStroke(
    id: UUID = UUID(),
    includeEraseMask: Bool = false,
    transform: HandDrawingStrokeTransform = .identity
) -> HandDrawingStroke {
    // 根据 includeEraseMask 决定是否生成局部擦除样本。
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingDocumentCodecTests.swift / MyCanvas_Ver_0Tests/HandDrawingEditorEngineTests.swift / MyCanvas_Ver_0Tests/HandDrawingPreviewRendererTests.swift
// 函数名: testHandDrawingDocumentCodecRoundTripsCustomDocument() / testHandDrawingDocumentCodecRejectsUnsupportedFormatVersion() / testHandDrawingEditorEngineAppendsStrokeExportsAndReloadsDocument() / testHandDrawingEditorEngineUndoRedoAndDeselect() / testHandDrawingPreviewRendererProducesVisiblePixelsForStroke() / testHandDrawingPreviewRendererAppliesStrokeLocalEraseMask()
// 功能说明: 修改后阶段4新增测试分别验证 document 编解码、历史栈/dirty region、以及局部擦除对 preview 像素结果的影响。
@MainActor
final class HandDrawingDocumentCodecTests: XCTestCase {
    func testHandDrawingDocumentCodecRoundTripsCustomDocument() throws {
        let document = makeHandDrawingTestDocument(includeEraseMask: true)
        let data = try HandDrawingDocumentCodec.makeDocumentData(for: document)
        let decodedDocument = try HandDrawingDocumentCodec.decodeDocument(from: data)
        XCTAssertEqual(decodedDocument, document)
    }
}

@MainActor
final class HandDrawingEditorEngineTests: XCTestCase {
    func testHandDrawingEditorEngineAppendsStrokeExportsAndReloadsDocument() throws {
        var engine = HandDrawingEditorEngine(
            document: HandDrawingDocument(
                paper: HandDrawingPaper(
                    id: "engine-paper",
                    size: CGSize(width: 120, height: 120)
                )
            )
        )
        _ = engine.appendStroke(brush: .defaultPen, samples: [
            HandDrawingInputSample(location: CGPoint(x: 20, y: 20)),
            HandDrawingInputSample(location: CGPoint(x: 80, y: 80))
        ])
        XCTAssertNotNil(engine.consumeDirtyRegion())
    }
}

@MainActor
final class HandDrawingPreviewRendererTests: XCTestCase {
    func testHandDrawingPreviewRendererAppliesStrokeLocalEraseMask() throws {
        let renderer = HandDrawingPreviewRenderer()
        let document = makeHandDrawingTestDocument(includeEraseMask: true)
        let image = try renderer.renderPreviewImage(for: document, scale: 1)
        let erasedPixel = sampleRGBA(from: image, x: 60, y: 60)
        let preservedPixel = sampleRGBA(from: image, x: 35, y: 60)
        XCTAssertLessThan(erasedPixel.alpha, preservedPixel.alpha)
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingDocumentStoreTests.swift
// 函数名: testHandDrawingDocumentStorePersistsTypedDocumentRoundTrip()
// 功能说明: 修改后 store tests 新增 typed document round-trip，验证 HandDrawingDocument 可以经由 bundle 保存后再按 typed API 读取回来。
@MainActor
final class HandDrawingDocumentStoreTests: XCTestCase {
    func testHandDrawingDocumentStorePersistsTypedDocumentRoundTrip() throws {
        try withTemporaryHandDrawingBoardDirectory { boardDirectoryURL in
            let documentID = UUID()
            let contentRevision = UUID()
            let document = makeHandDrawingTestDocument(includeEraseMask: true)
            let previewImage = try HandDrawingPreviewRenderer().renderPreviewImage(
                for: document,
                scale: 1
            )

            try HandDrawingDocumentStore.persistDocument(
                document,
                documentID: documentID,
                contentRevision: contentRevision,
                previewImageData: nil,
                previewCGImage: previewImage,
                boardDirectoryURL: boardDirectoryURL
            )

            let loadedDocument = try HandDrawingDocumentStore.loadDocument(
                documentID: documentID,
                boardDirectoryURL: boardDirectoryURL
            )
            XCTAssertEqual(loadedDocument, document)
        }
    }
}
```

## 结果小结

- 阶段 4 完成后，handDrawing 已经具备“自研文档模型 + typed codec/store + headless editor engine + preview renderer + 阶段化测试”的完整无 UI 内核雏形。
- 当前 bundle persistence、lazy migration、session 入口和 preview pipeline 的旧链路仍保持可用，说明阶段 4 不是替换式破坏改动，而是在阶段 2、3 边界内继续向内核化推进。
- 后续阶段 5 可以直接基于这套 engine/document/renderer 接 iPad 编辑器壳，不需要再把文档模型和预览导出逻辑埋回 UI 层。
