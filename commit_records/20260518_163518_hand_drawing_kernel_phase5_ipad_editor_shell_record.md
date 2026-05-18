# 20260518_163518_hand_drawing_kernel_phase5_ipad_editor_shell_record

## 记录范围

- 记录内容：
  1. 把 handDrawing 编辑上下文与提交桥接从 `drawingData` 语义改成 engine-agnostic 的 `documentData`。
  2. 新增 legacy `PKDrawing` -> 自研 `HandDrawingDocument` 的加载适配层，并抽出共享的 stroke rasterizer。
  3. 用 `coordinator + surface + palette` 替换 iOS 旧 `PKCanvasView` 托管页，形成新的 iPad 编辑器壳。
  4. 收口 iPad only 平台能力判断，并补本阶段新增/变更测试。
- 时间戳来源：
  - `date +"%Y%m%d_%H%M%S"` -> `20260518_163518`
- 说明：
  - 本记录以阶段 4 完成态为基线，重点说明阶段 5 刚刚新增/改写的代码。
  - 对于本阶段新增文件，修改前如实记录为“文件不存在”。
  - 对于已跟踪文件，本记录结合当前 `git diff`、当前 `git status` 和当前文件内容整理，不放原始 diff。
  - 工作区内与本阶段无关的其它变更不纳入本记录。
- 参考依据：
  - `git status --short -- "MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift" "MyCanvas_Ver_0/Canvas/Editing/CanvasHandDrawingEditing.swift" "MyCanvas_Ver_0/Canvas/HandDrawing" "MyCanvas_Ver_0/Platform/iOS/HandDrawing" "MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift" "MyCanvas_Ver_0Tests/CanvasHandDrawingEditingSessionTests.swift" "MyCanvas_Ver_0Tests/HandDrawingDocumentLoaderTests.swift" "MyCanvas_Ver_0Tests/HandDrawingMigrationServiceTests.swift"`
  - `git diff -- "MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift" "MyCanvas_Ver_0/Canvas/Editing/CanvasHandDrawingEditing.swift" "MyCanvas_Ver_0/Canvas/HandDrawing" "MyCanvas_Ver_0/Platform/iOS/HandDrawing" "MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift" "MyCanvas_Ver_0Tests/CanvasHandDrawingEditingSessionTests.swift" "MyCanvas_Ver_0Tests/HandDrawingDocumentLoaderTests.swift" "MyCanvas_Ver_0Tests/HandDrawingMigrationServiceTests.swift"`
  - 阶段 4 记录：
    - `commit_records/20260518_160130_hand_drawing_kernel_phase4_engine_core_record.md`
  - 旧 PencilKit 编辑页记录：
    - `commit_records/20260518_130612_hand_drawing_phase5_ios_editor_entry_record.md`
- 当前工作区涉及文件：
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasHandDrawingEditing.swift`
  - `MyCanvas_Ver_0/Canvas/HandDrawing/Core/HandDrawingPlatformColor.swift`
  - `MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingDocumentLoader.swift`
  - `MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingStrokeRasterizer.swift`
  - `MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingPreviewRenderer.swift`
  - `MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift`
  - `MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift`
  - `MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingToolPaletteView.swift`
  - `MyCanvas_Ver_0/Platform/iOS/HandDrawing/iOSHandDrawingEditorViewController.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0Tests/CanvasHandDrawingEditingSessionTests.swift`
  - `MyCanvas_Ver_0Tests/HandDrawingDocumentLoaderTests.swift`
  - `MyCanvas_Ver_0Tests/HandDrawingMigrationServiceTests.swift`
- 当前 changes 摘要：
  - `M MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
  - `M MyCanvas_Ver_0/Canvas/Editing/CanvasHandDrawingEditing.swift`
  - `M MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingPreviewRenderer.swift`
  - `M MyCanvas_Ver_0/Platform/iOS/HandDrawing/iOSHandDrawingEditorViewController.swift`
  - `M MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `M MyCanvas_Ver_0Tests/CanvasHandDrawingEditingSessionTests.swift`
  - `M MyCanvas_Ver_0Tests/HandDrawingMigrationServiceTests.swift`
  - `?? MyCanvas_Ver_0/Canvas/HandDrawing/Core/HandDrawingPlatformColor.swift`
  - `?? MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingDocumentLoader.swift`
  - `?? MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingStrokeRasterizer.swift`
  - `?? MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift`
  - `?? MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift`
  - `?? MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingToolPaletteView.swift`
  - `?? MyCanvas_Ver_0Tests/HandDrawingDocumentLoaderTests.swift`
- 验证结果：
  - `xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "generic/platform=iOS"`
    - 通过
  - `xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=macOS" -only-testing:"MyCanvas_Ver_0Tests/HandDrawingDocumentLoaderTests" -only-testing:"MyCanvas_Ver_0Tests/HandDrawingDocumentCodecTests" -only-testing:"MyCanvas_Ver_0Tests/HandDrawingDocumentStoreTests" -only-testing:"MyCanvas_Ver_0Tests/HandDrawingEditorEngineTests" -only-testing:"MyCanvas_Ver_0Tests/HandDrawingPreviewRendererTests" -only-testing:"MyCanvas_Ver_0Tests/CanvasHandDrawingEditingSessionTests" -only-testing:"MyCanvas_Ver_0Tests/HandDrawingMigrationServiceTests" -only-testing:"MyCanvas_Ver_0Tests/BoardHandDrawingStorageTests"`
    - 通过
  - `ReadLints`
    - 本次改动文件未引入新的 linter 问题
- 本记录不包含：
  - 阶段 6 的 pressure 驱动像素橡皮真正启用
  - 阶段 7 的套索选择 / 移动能力真正启用
  - git commit / push

## 修改一：把编辑上下文与提交桥接改成 `documentData`，不再把 session 语义绑定到 PencilKit bytes

### 修改前

- `CanvasHandDrawingEditorContext` 和 `CanvasHandDrawingEditSubmission` 里使用的是 `drawingData`。
- `CanvasEditorSession.commitHandDrawingEdit(...)` 在比较和回写时也默认提交内容就是 `drawingData`，这让编辑器桥接层仍然带着明显的 PencilKit 历史包袱。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasHandDrawingEditing.swift
// 函数名: CanvasHandDrawingEditorContext / CanvasHandDrawingEditSubmission
// 功能说明: 修改前 handDrawing 编辑桥接仍然把源内容命名为 drawingData，语义上仍偏向旧 PencilKit 承载形式。
struct CanvasHandDrawingEditorContext {
    let itemID: CanvasItemID
    let documentID: HandDrawingDocumentID
    let paper: CanvasHandDrawingPaperSpec
    let drawingData: Data
    let isEmpty: Bool
    let storage: BoardHandDrawingStorageRecord
    let didMigrateLegacyDocument: Bool
}

struct CanvasHandDrawingEditSubmission {
    let drawingData: Data
    let previewCGImage: CGImage
    let isEmpty: Bool
    let contentRevision: UUID
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: handDrawingEditorContext(for:) / commitHandDrawingEdit(withID:submission:)
// 功能说明: 修改前 session 在 editorContext 与 commit 阶段都直接透传和比较 submission.drawingData。
return CanvasHandDrawingEditorContext(
    itemID: itemID,
    documentID: item.documentID,
    paper: item.paper,
    drawingData: payload.drawingData,
    isEmpty: item.isEmpty,
    storage: .bundle,
    didMigrateLegacyDocument: false
)

if item.contentRevision == submission.contentRevision,
   item.isEmpty == submission.isEmpty,
   resolvedHandDrawingSourceData(for: item) == submission.drawingData
{
    return nil
}

transientHandDrawingAssetPayloads[itemID] =
    BoardTransientHandDrawingAssetPayload(
        itemID: itemID,
        drawingData: submission.drawingData,
        previewCGImage: submission.previewCGImage
    )
```

### 修改后

- `CanvasHandDrawingEditorContext` / `CanvasHandDrawingEditSubmission` 全部切到 `documentData`。
- `CanvasEditorSession` 的编辑器入口和提交回写链只关心“文档数据”，不再假定这一定是 `PKDrawing.dataRepresentation()`。
- 底层持久化暂时仍然复用 `BoardTransientHandDrawingAssetPayload.drawingData` 字段名，但桥接层已经和具体编辑内核解耦。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasHandDrawingEditing.swift
// 函数名: CanvasHandDrawingEditorContext / CanvasHandDrawingEditSubmission
// 功能说明: 修改后编辑桥接层统一使用 documentData，显式表达“提交的是 handDrawing 文档”，而不是某个特定框架的 bytes。
struct CanvasHandDrawingEditorContext {
    let itemID: CanvasItemID
    let documentID: HandDrawingDocumentID
    let paper: CanvasHandDrawingPaperSpec
    let documentData: Data
    let isEmpty: Bool
    let storage: BoardHandDrawingStorageRecord
    let didMigrateLegacyDocument: Bool
}

struct CanvasHandDrawingEditSubmission {
    let documentData: Data
    let previewCGImage: CGImage
    let isEmpty: Bool
    let contentRevision: UUID
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: handDrawingEditorContext(for:) / commitHandDrawingEdit(withID:submission:)
// 功能说明: 修改后 session 只把提交内容当作 documentData 处理，比较、回写和 transient payload 更新都不再绑定 PencilKit 语义。
func handDrawingEditorContext(
    for itemID: CanvasItemID
) throws -> CanvasHandDrawingEditorContext {
    if let payload = transientHandDrawingAssetPayload(for: itemID) {
        return CanvasHandDrawingEditorContext(
            itemID: itemID,
            documentID: item.documentID,
            paper: item.paper,
            documentData: payload.drawingData,
            isEmpty: item.isEmpty,
            storage: .bundle,
            didMigrateLegacyDocument: false
        )
    }

    return CanvasHandDrawingEditorContext(
        itemID: itemID,
        documentID: item.documentID,
        paper: item.paper,
        documentData: preparedDocument.drawingData,
        isEmpty: item.isEmpty,
        storage: preparedDocument.record.storage,
        didMigrateLegacyDocument: preparedDocument.didMigrateLegacyDocument
    )
}

if item.contentRevision == submission.contentRevision,
   item.isEmpty == submission.isEmpty,
   resolvedHandDrawingSourceData(for: item) == submission.documentData
{
    return nil
}

transientHandDrawingAssetPayloads[itemID] =
    BoardTransientHandDrawingAssetPayload(
        itemID: itemID,
        drawingData: submission.documentData,
        previewCGImage: submission.previewCGImage
    )
```

## 修改二：补 `PKDrawing` 兼容加载层，并把笔迹/局部擦除绘制抽成共享 rasterizer

### 修改前

- 阶段 4 已经有 `HandDrawingDocumentCodec`、`HandDrawingEditorEngine`、`HandDrawingPreviewRenderer`，但缺一个正式的“打开文档适配层”：
  - typed document 可以解码；
  - legacy `PKDrawing` 还没有被显式转换成自研 document。
- `HandDrawingPreviewRenderer` 内部自己持有 `drawStrokeInk(...)` / `applyEraseMask(...)` / `drawDisk(...)`，编辑器实时草稿如果也要渲染 stroke，就只能再复制一套逻辑。
- 项目里还没有 `HandDrawingPlatformColor.swift`、`HandDrawingDocumentLoader.swift`、`HandDrawingStrokeRasterizer.swift`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingDocumentLoader.swift
// 函数名: 无
// 功能说明: 修改前阶段4完成态下，还不存在“typed document / legacy PKDrawing 双路加载”的统一入口。
// 修改前不存在该文件。
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Core/HandDrawingPlatformColor.swift
// 函数名: 无
// 功能说明: 修改前项目里还没有平台颜色与 HandDrawingColor 的双向转换适配层。
// 修改前不存在该文件。
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingPreviewRenderer.swift
// 函数名: drawStroke(_:into:pixelWidth:pixelHeight:scale:) / drawStrokeInk(_:in:) / applyEraseMask(_:transform:in:)
// 功能说明: 修改前 preview renderer 自己独占 stroke ink 与局部擦除逻辑，无法被编辑器草稿层直接复用。
private func drawStroke(
    _ stroke: HandDrawingStroke,
    into compositeContext: CGContext,
    pixelWidth: Int,
    pixelHeight: Int,
    scale: CGFloat
) throws {
    let strokeContext = try makeBitmapContext(width: pixelWidth, height: pixelHeight)
    strokeContext.scaleBy(x: scale, y: scale)
    drawStrokeInk(stroke, in: strokeContext)
    applyEraseMask(stroke.eraseMask, transform: stroke.transform, in: strokeContext)
    // 其余合成逻辑省略
}
```

### 修改后

- `HandDrawingDocumentLoader.loadDocument(...)` 成为正式入口：
  1. 空数据 -> 空白 `HandDrawingDocument`
  2. typed document -> 直接 decode
  3. legacy `PKDrawing` -> `HandDrawingLegacyPencilKitBridge.makeDocument(...)`
  4. 两条都失败 -> 抛 `invalidSourceData`
- `HandDrawingLegacyPencilKitBridge` 会把旧 `PKStroke` 转成：
  - 采样点
  - brush color / opacity / baseSize
  - 已应用 transform 的 stroke points
- `HandDrawingPlatformColor` 负责 `UIColor` / `NSColor` 和 `HandDrawingColor` 的桥接。
- `HandDrawingStrokeRasterizer` 抽出共享绘制逻辑，`preview renderer` 和编辑器草稿层可以复用同一套 ink / erase 实现。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingDocumentLoader.swift
// 函数名: loadDocument(from:paper:) / HandDrawingLegacyPencilKitBridge.makeDocument(from:paper:)
// 功能说明: 修改后 loader 会先尝试自研 document 解码，失败时回退解析 legacy PKDrawing，并转换成新的 HandDrawingDocument。
enum HandDrawingDocumentLoader {
    static func loadDocument(
        from data: Data,
        paper: CanvasHandDrawingPaperSpec
    ) throws -> HandDrawingDocument {
        if data.isEmpty {
            return HandDrawingDocument(paper: HandDrawingPaper(paper))
        }

        if let document = try? HandDrawingDocumentCodec.decodeDocument(from: data) {
            return document
        }

        if let legacyDrawing = try? PKDrawing(data: data) {
            return HandDrawingLegacyPencilKitBridge.makeDocument(
                from: legacyDrawing,
                paper: paper
            )
        }

        throw HandDrawingDocumentLoaderError.invalidSourceData
    }
}

enum HandDrawingLegacyPencilKitBridge {
    static func makeDocument(
        from drawing: PKDrawing,
        paper: CanvasHandDrawingPaperSpec
    ) -> HandDrawingDocument {
        let strokes = drawing.strokes.compactMap(makeStroke(from:))
        return HandDrawingDocument(
            paper: HandDrawingPaper(paper),
            strokes: strokes
        )
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Core/HandDrawingPlatformColor.swift
// 函数名: HandDrawingColor.init(platformColor:) / UIColor.init(handDrawingColor:)
// 功能说明: 修改后平台色值和 HandDrawingColor 之间可以双向转换，legacy 迁移与 iOS palette 都能直接复用。
#if canImport(UIKit)
typealias HandDrawingPlatformColor = UIColor
#elseif canImport(AppKit)
typealias HandDrawingPlatformColor = NSColor
#endif

extension HandDrawingColor {
    init(platformColor: HandDrawingPlatformColor) {
        let resolvedColor = platformColor.resolvedColor(with: .current)
        if resolvedColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            self.init(
                red: Double(red),
                green: Double(green),
                blue: Double(blue),
                alpha: Double(alpha)
            )
        } else {
            self = .black
        }
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingStrokeRasterizer.swift
// 函数名: draw(_:in:) / drawStrokeInk(_:in:) / applyEraseMask(_:transform:in:)
// 功能说明: 修改后 ink 绘制与局部擦除从 preview renderer 中抽离出来，成为编辑器草稿层和 preview 共用的 stroke rasterizer。
enum HandDrawingStrokeRasterizer {
    static func draw(
        _ stroke: HandDrawingStroke,
        in context: CGContext
    ) {
        drawStrokeInk(stroke, in: context)
        applyEraseMask(stroke.eraseMask, transform: stroke.transform, in: context)
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingPreviewRenderer.swift
// 函数名: drawStroke(_:into:pixelWidth:pixelHeight:scale:)
// 功能说明: 修改后 preview renderer 不再独占笔迹绘制细节，而是直接调用 HandDrawingStrokeRasterizer 复用共享逻辑。
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
    HandDrawingStrokeRasterizer.draw(stroke, in: strokeContext)
    guard let strokeImage = strokeContext.makeImage() else {
        throw HandDrawingPreviewRendererError.failedToCreatePreviewImage
    }
    compositeContext.draw(
        strokeImage,
        in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
    )
}
```

## 修改三：用 `coordinator + surface + palette` 替换旧 `PKCanvasView` 托管页，形成新的 iPad 编辑器壳

### 修改前

- `iOSHandDrawingEditorViewController` 直接依赖 `PKCanvasView + PKToolPicker`。
- controller 自己承担：
  - 打开 `PKDrawing`
  - 缩放/居中
  - tool picker
  - dirty 判定
  - preview 导出
  - commit 生成
- 旧编辑页本质上还是 PencilKit 托管页，不是独立模块。
- `iOSViewController.supportsHandDrawingEditing` 在 iOS 下恒为 `true`，没有落实“iPad only”。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/iOSHandDrawingEditorViewController.swift
// 函数名: configureCanvasView() / finishEditingAndDismiss() / makePreviewCGImage(for:isEmpty:)
// 功能说明: 修改前 controller 直接托管 PKCanvasView 与 PKToolPicker，并在页面里自己负责 preview 导出和 commit 判定。
final class iOSHandDrawingEditorViewController: UIViewController, PKCanvasViewDelegate {
    private let editorContext: CanvasHandDrawingEditorContext
    private let initialDrawing: PKDrawing
    private let toolPicker = PKToolPicker()
    private let canvasView: PKCanvasView = {
        let view = PKCanvasView()
        view.backgroundColor = .white
        view.alwaysBounceVertical = true
        view.alwaysBounceHorizontal = true
        view.bouncesZoom = true
        return view
    }()

    private func configureCanvasView() {
        canvasView.delegate = self
        canvasView.drawing = initialDrawing
        canvasView.drawingPolicy = .pencilOnly
        canvasView.tool = PKInkingTool(.pen, color: .black, width: 6)
        canvasView.contentSize = editorContext.paper.size
    }

    private func finishEditingAndDismiss() {
        let drawing = canvasView.drawing
        let isEmpty = drawing.strokes.isEmpty
        if shouldCommit(drawing: drawing, isEmpty: isEmpty) {
            try onCommitSubmission(
                CanvasHandDrawingEditSubmission(
                    drawingData: drawing.dataRepresentation(),
                    previewCGImage: try makePreviewCGImage(for: drawing, isEmpty: isEmpty),
                    isEmpty: isEmpty,
                    contentRevision: UUID()
                )
            )
        }
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: supportsHandDrawingEditing
// 功能说明: 修改前 iOS 侧 handDrawing 编辑能力在所有 iOS idiom 下都默认开启。
private var supportsHandDrawingEditing: Bool {
    true
}
```

### 修改后

- `iOSHandDrawingEditorViewController` 现在只做页面壳：
  - 顶部标题 / 提交 / 关闭
  - 挂载 `paletteView`
  - 挂载 `surfaceView`
  - 调用 `coordinator.makeCommitSubmissionIfNeeded()`
- 新增 `HandDrawingEditorCoordinator`：
  - 打开时统一走 `HandDrawingDocumentLoader`
  - 维护 `HandDrawingEditorEngine`
  - 管理当前 brush/color/lineWidth
  - 管理 draft stroke、undo/redo、最终 `CanvasHandDrawingEditSubmission`
- 新增 `HandDrawingCanvasSurfaceView`：
  - 手指只用于 `UIScrollView` 的 pan / zoom
  - Pencil 触点走 `HandDrawingInputSample`
  - 草稿层用 `HandDrawingStrokeRasterizer` 实时绘制
- 新增 `HandDrawingToolPaletteView`：
  - V1 提供画笔、颜色、粗细、撤销、重做
  - `Eraser` / `Lasso` 先只保留按钮与状态位，当前如实保持 disabled
- `iOSViewController.supportsHandDrawingEditing` 改成只在 `traitCollection.userInterfaceIdiom == .pad` 时成立。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/iOSHandDrawingEditorViewController.swift
// 函数名: viewDidLoad() / configureCoordinator() / configurePaletteView() / configureSurfaceView() / finishEditingAndDismiss()
// 功能说明: 修改后 VC 只保留编辑器壳职责，真正的绘制、状态管理和提交数据生成都交给 coordinator 与子视图协作完成。
final class iOSHandDrawingEditorViewController: UIViewController {
    private let onCommitSubmission: (CanvasHandDrawingEditSubmission) throws -> Void
    private let coordinator: HandDrawingEditorCoordinator
    private let paletteView = HandDrawingToolPaletteView()
    private let surfaceView = HandDrawingCanvasSurfaceView()

    override func viewDidLoad() {
        super.viewDidLoad()
        configureButtons()
        configureCoordinator()
        configurePaletteView()
        configureSurfaceView()
        setupViewHierarchy()
        setupConstraints()
        updateChromeConfiguration()
        coordinator.activate()
    }

    private func configureCoordinator() {
        coordinator.onSurfaceStateChange = { [weak self] state in
            self?.surfaceView.apply(state: state)
        }
        coordinator.onPaletteStateChange = { [weak self] state in
            self?.paletteView.apply(state: state)
        }
    }

    private func finishEditingAndDismiss() {
        guard isFinishing == false else {
            return
        }

        isFinishing = true
        do {
            if let submission = try coordinator.makeCommitSubmissionIfNeeded() {
                try onCommitSubmission(submission)
            }
            dismiss(animated: true)
        } catch {
            isFinishing = false
            presentCommitError(message: error.localizedDescription)
        }
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift
// 函数名: init(editorContext:) / handlePencilStrokeBegan(_:) / handlePencilStrokeEnded(_:) / makeCommitSubmissionIfNeeded()
// 功能说明: 修改后 coordinator 成为 iPad 编辑器的状态中枢，负责 document 加载、engine 驱动、草稿 stroke 管理与最终 commit bridge 生成。
@MainActor
final class HandDrawingEditorCoordinator {
    private let editorContext: CanvasHandDrawingEditorContext
    private let previewRenderer = HandDrawingPreviewRenderer()
    private let initialDocument: HandDrawingDocument
    private var engine: HandDrawingEditorEngine
    private var selectedTool: HandDrawingEditorTool = .brush
    private var selectedColor: HandDrawingColor
    private var selectedLineWidth: CGFloat
    private var activeStrokeBrush: HandDrawingBrushStyle?
    private var activeStrokeSamples: [HandDrawingInputSample] = []

    init(editorContext: CanvasHandDrawingEditorContext) throws {
        self.editorContext = editorContext
        let document = try HandDrawingDocumentLoader.loadDocument(
            from: editorContext.documentData,
            paper: editorContext.paper
        )
        initialDocument = document
        engine = HandDrawingEditorEngine(document: document)
        let initialBrush = document.strokes.last?.brush ?? .defaultPen
        selectedColor = initialBrush.color
        selectedLineWidth = CGFloat(initialBrush.baseSize)
    }

    func handlePencilStrokeBegan(_ sample: HandDrawingInputSample) {
        guard selectedTool == .brush else {
            return
        }
        activeStrokeBrush = currentBrushStyle
        activeStrokeSamples = [sample]
        publishSurfaceState()
    }

    func handlePencilStrokeEnded(_ samples: [HandDrawingInputSample]) {
        guard let activeStrokeBrush else {
            return
        }
        appendStrokeSamples(samples)
        _ = engine.appendStroke(
            brush: activeStrokeBrush,
            samples: activeStrokeSamples
        )
        refreshCommittedImageAndPublishState()
    }

    func makeCommitSubmissionIfNeeded() throws -> CanvasHandDrawingEditSubmission? {
        let currentDocument = engine.state.document
        guard currentDocument != initialDocument else {
            return nil
        }

        return CanvasHandDrawingEditSubmission(
            documentData: try engine.encodedDocumentData(),
            previewCGImage: try previewRenderer.renderPreviewImage(for: currentDocument, scale: 1),
            isEmpty: currentDocument.isEmpty,
            contentRevision: UUID()
        )
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift
// 函数名: configureScrollView() / touchesBegan(_:with:) / makeSamples(from:event:) / HandDrawingCanvasDraftOverlayView.draw(_:)
// 功能说明: 修改后 surface view 让手指只负责 pan/zoom，Apple Pencil 直接下采样成 HandDrawingInputSample，草稿 stroke 则复用共享 rasterizer 绘制。
private func configureScrollView() {
    scrollView.delegate = self
    scrollView.panGestureRecognizer.allowedTouchTypes = [
        NSNumber(value: UITouch.TouchType.direct.rawValue)
    ]
    scrollView.pinchGestureRecognizer?.allowedTouchTypes = [
        NSNumber(value: UITouch.TouchType.direct.rawValue)
    ]
}

override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    super.touchesBegan(touches, with: event)
    guard activePencilTouchID == nil, let touch = firstPencilTouch(in: touches) else {
        return
    }
    activePencilTouchID = ObjectIdentifier(touch)
    if let sample = makeSample(from: touch) {
        onPencilStrokeBegan?(sample)
    }
}

private func makeSamples(
    from touch: UITouch,
    event: UIEvent?
) -> [HandDrawingInputSample] {
    let touches = event?.coalescedTouches(for: touch) ?? [touch]
    return touches.compactMap(makeSample(from:))
}

override func draw(_ rect: CGRect) {
    super.draw(rect)
    guard let draftStroke, let context = UIGraphicsGetCurrentContext() else {
        return
    }
    HandDrawingStrokeRasterizer.draw(draftStroke, in: context)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingToolPaletteView.swift
// 函数名: apply(state:) / rebuildColorButtonsIfNeeded(colors:) / rebuildLineWidthButtonsIfNeeded(lineWidths:) / updateToolButtonSelection(_:isSelected:isEnabled:)
// 功能说明: 修改后 palette 提供预设画笔、颜色、粗细、撤销和重做入口，并显式保留 Eraser/Lasso 的禁用状态位，为后续阶段留接口。
func apply(state: HandDrawingToolPaletteState) {
    rebuildColorButtonsIfNeeded(colors: state.availableColors)
    rebuildLineWidthButtonsIfNeeded(lineWidths: state.availableLineWidths)
    updateToolButtonSelection(
        brushButton,
        isSelected: state.selectedTool == .brush,
        isEnabled: true
    )
    updateToolButtonSelection(
        eraserButton,
        isSelected: state.selectedTool == .pixelEraser,
        isEnabled: state.isPixelEraserEnabled
    )
    updateToolButtonSelection(
        lassoButton,
        isSelected: state.selectedTool == .lasso,
        isEnabled: state.isLassoEnabled
    )
    undoButton.isEnabled = state.canUndo
    redoButton.isEnabled = state.canRedo
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: supportsHandDrawingEditing
// 功能说明: 修改后 handDrawing 编辑能力显式收口到 iPad，和本轮“iPad 编辑器壳”范围保持一致。
private var supportsHandDrawingEditing: Bool {
    traitCollection.userInterfaceIdiom == .pad
}
```

## 修改四：补 `document loader` 测试，并把既有 handDrawing 测试切到 `documentData`

### 修改前

- 还没有 `HandDrawingDocumentLoaderTests.swift`。
- `CanvasHandDrawingEditingSessionTests` 仍然用 `Data("ink".utf8)` 伪造提交内容。
- `HandDrawingMigrationServiceTests` 断言的是 `firstContext.drawingData` / `secondContext.drawingData`。

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingDocumentLoaderTests.swift
// 函数名: 无
// 功能说明: 修改前项目里还没有覆盖 typed document / legacy PKDrawing 双路加载的专门测试文件。
// 修改前不存在该文件。
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasHandDrawingEditingSessionTests.swift
// 函数名: testCommitHandDrawingEditUpdatesItemAndSupportsUndoRedo()
// 功能说明: 修改前编辑提交测试仍然使用任意字符串 Data 作为 drawingData，没有验证 typed document 提交桥接。
let result = try XCTUnwrap(
    session.commitHandDrawingEdit(
        withID: item.id,
        submission: CanvasHandDrawingEditSubmission(
            drawingData: Data("ink".utf8),
            previewCGImage: previewImage,
            isEmpty: false,
            contentRevision: updatedRevision
        )
    )
)
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingMigrationServiceTests.swift
// 函数名: testCanvasEditorSessionHandDrawingEditorContextMigratesLegacyDocumentBeforeOpen()
// 功能说明: 修改前迁移测试仍然断言 editorContext.drawingData。
XCTAssertEqual(firstContext.drawingData, fixture.drawingData)
XCTAssertEqual(secondContext.drawingData, fixture.drawingData)
```

### 修改后

- 新增 `HandDrawingDocumentLoaderTests`，分别验证：
  - typed document round-trip load
  - legacy `PKDrawing` 到自研 document 的转换
- `CanvasHandDrawingEditingSessionTests` 现在提交真实 `HandDrawingDocumentCodec.makeDocumentData(...)` 的结果。
- `HandDrawingMigrationServiceTests` 断言字段同步切到 `documentData`，和新桥接命名保持一致。

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingDocumentLoaderTests.swift
// 函数名: testHandDrawingDocumentLoaderLoadsTypedDocumentData() / testHandDrawingDocumentLoaderConvertsLegacyPencilKitDrawing()
// 功能说明: 修改后新增 loader 测试，既覆盖 typed document，也覆盖 legacy PKDrawing -> HandDrawingDocument 的兼容转换。
@MainActor
final class HandDrawingDocumentLoaderTests: XCTestCase {
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

    func testHandDrawingDocumentLoaderConvertsLegacyPencilKitDrawing() throws {
        let legacyDrawing = makeLegacyDrawing()
        let loadedDocument = try HandDrawingDocumentLoader.loadDocument(
            from: legacyDrawing.dataRepresentation(),
            paper: .square
        )

        XCTAssertEqual(loadedDocument.strokes.count, 1)
        XCTAssertFalse(loadedDocument.isEmpty)
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasHandDrawingEditingSessionTests.swift
// 函数名: testCommitHandDrawingEditUpdatesItemAndSupportsUndoRedo()
// 功能说明: 修改后编辑提交测试显式提交 typed documentData，验证 session 提交桥接已经从 raw drawingData 切换到自研文档数据。
let documentData = try HandDrawingDocumentCodec.makeDocumentData(
    for: makeHandDrawingTestDocument()
)

let result = try XCTUnwrap(
    session.commitHandDrawingEdit(
        withID: item.id,
        submission: CanvasHandDrawingEditSubmission(
            documentData: documentData,
            previewCGImage: previewImage,
            isEmpty: false,
            contentRevision: updatedRevision
        )
    )
)
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingMigrationServiceTests.swift
// 函数名: testCanvasEditorSessionHandDrawingEditorContextMigratesLegacyDocumentBeforeOpen()
// 功能说明: 修改后迁移测试跟随 editorContext 字段命名调整，验证懒迁移后返回的是 documentData。
XCTAssertEqual(firstContext.documentData, fixture.drawingData)
XCTAssertEqual(secondContext.documentData, fixture.drawingData)
```

## 阶段 5 完成态结论

- 旧的 PencilKit 全屏托管页已经被新的自研编辑器壳替换掉：
  - `VC` 只做外层页面
  - `Coordinator` 负责状态与提交
  - `Surface` 负责 Pencil 输入和手指缩放/平移
  - `Palette` 负责基础工具 UI
- legacy `PKDrawing` 首次进入新编辑器时，已经能被转换成自研 `HandDrawingDocument` 打开。
- `documentData` 已经成为 handDrawing 编辑桥接层的正式语义。
- 本阶段如实保留的范围边界：
  - `Brush + 颜色 + 粗细 + Undo/Redo` 可用
  - `Eraser` / `Lasso` 仅预留入口，尚未启用实际编辑能力
