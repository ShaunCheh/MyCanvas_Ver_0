# 20260407_140811_gif_phase6_ios_editor_record

## 记录范围

- 记录内容：新增共享 `CanvasGIFFrameImportEditorContext`，把 GIF 选帧页真正需要的源数据、帧数和配置集中收口。
- 记录内容：在 `CanvasEditorSession` 中增加 `gifFrameImportEditorContext(...)`，让 iOS 页面不再自己复制 GIF 数据读取与帧数解析逻辑。
- 记录内容：调整 iOS 入口控制器，让 GIF 页面打开前先拿共享 editor context，并补齐打开失败时的专用错误提示。
- 记录内容：把 `iOSGIFFrameImportViewController` 从阶段 5 的占位壳子升级为真正可用的 4 列 `UICollectionView` 多选页。
- 记录内容：补充 editor context 的 transient / persisted 两条定向测试，确保共享层给 UI 的上下文来源正确。
- 涉及文件：`MyCanvas_Ver_0/Canvas/GIF/CanvasGIFFrameService.swift`
- 涉及文件：`MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/iOS/iOSGIFFrameImportViewController.swift`
- 涉及文件：`MyCanvas_Ver_0Tests/CanvasGIFFrameImportBuilderTests.swift`
- 本记录不包含：阶段 7 的 macOS `NSCollectionView` 多选页。
- 本记录不包含：阶段 8 的回归矩阵与性能收口。
- 本记录不包含：`.cursor/plans/*.md` 的计划文件状态变化。
- 本记录不包含：git commit / push。

## 修改一：共享 GIF 服务新增编辑页上下文模型，并补齐 `frameCount(...)` 基础能力

### 修改前

- `CanvasGIFFrameService` 只有纯解码 / 元数据能力。
- iOS 页面如果要做真实多选网格，只能自己再拼：
  - 源 GIF `Data`
  - `CGImageSource`
  - 帧数
  - 选帧页配置
  - 缩略图最大像素
- 这会把“GIF 原始数据读取 + 帧数解析”的共享语义重新泄漏回平台层。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/GIF/CanvasGIFFrameService.swift
// 类型/函数: CanvasGIFFrameService.makeImageSource(from:) / animatedMetadata(from:) / decodeFrame(at:from:maxPixelSize:)
// 功能说明: 修改前共享层只有 GIF 解码与元数据能力，没有给选帧页面准备好的 editor context 模型。
enum CanvasGIFFrameService {
    private static let defaultFrameDelay: TimeInterval = 0.1
    private static let minimumAcceptedFrameDelay: TimeInterval = 0.011
    private static let minimumThumbnailPixelSize = 64

    static func makeImageSource(from data: Data) -> CGImageSource? {
        CGImageSourceCreateWithData(data as CFData, nil)
    }

    static func animatedMetadata(
        from imageSource: CGImageSource
    ) -> CanvasAnimatedImageMetadata? {
        let frameCount = CGImageSourceGetCount(imageSource)
        guard frameCount > 1 else {
            return nil
        }
        // ...
    }

    static func decodeFrame(
        at frameIndex: Int,
        from imageSource: CGImageSource,
        maxPixelSize: Int? = nil
    ) -> CGImage? {
        let frameCount = CGImageSourceGetCount(imageSource)
        guard frameIndex >= 0, frameIndex < frameCount else {
            return nil
        }
        // ...
    }
}
```

### 修改后

- 新增 `CanvasGIFFrameImportEditorContext`，明确收口 GIF 选帧页真正需要的最小共享输入：
  - `itemID`
  - `gifData`
  - `frameCount`
  - `selectionGrid`
  - `thumbnailMaxPixelSize`
- 新增 `CanvasGIFFrameService.frameCount(from:)`，把帧数读取也统一归到共享服务，不再在平台层直接碰 `CGImageSourceGetCount(...)`。
- `animatedMetadata(...)` / `playbackMetadata(...)` / `decodeFrame(...)` 也改为统一复用这个 helper，避免同一个基础操作散落多处。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/GIF/CanvasGIFFrameService.swift
// 类型/函数: CanvasGIFFrameImportEditorContext / CanvasGIFFrameService.frameCount(from:)
// 功能说明: 修改后共享层直接向平台页面提供 editor context 模型，并把帧数读取收口成统一 helper。
import CoreGraphics
import Foundation
import ImageIO

struct CanvasGIFFrameImportEditorContext {
    let itemID: CanvasItemID
    let gifData: Data
    let frameCount: Int
    let selectionGrid: CanvasGIFFrameImportGridConfiguration
    let thumbnailMaxPixelSize: Int

    var frameIndices: Range<Int> {
        0..<frameCount
    }
}

enum CanvasGIFFrameService {
    static func makeImageSource(from data: Data) -> CGImageSource? {
        CGImageSourceCreateWithData(data as CFData, nil)
    }

    static func frameCount(
        from imageSource: CGImageSource
    ) -> Int {
        CGImageSourceGetCount(imageSource)
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/GIF/CanvasGIFFrameService.swift
// 类型/函数: animatedMetadata(from:) / playbackMetadata(from:importedMetadata:) / decodeFrame(at:from:maxPixelSize:)
// 功能说明: 修改后 GIF 服务内部的帧数判断也统一走 frameCount(from:)，减少基础判断逻辑漂移。
static func animatedMetadata(
    from imageSource: CGImageSource
) -> CanvasAnimatedImageMetadata? {
    let frameCount = frameCount(from: imageSource)
    guard frameCount > 1 else {
        return nil
    }
    // ...
}

static func playbackMetadata(
    from imageSource: CGImageSource,
    importedMetadata: CanvasAnimatedImageMetadata?
) -> CanvasAnimatedImageMetadata? {
    let frameCount = frameCount(from: imageSource)
    guard frameCount > 1 else {
        return nil
    }
    // ...
}

static func decodeFrame(
    at frameIndex: Int,
    from imageSource: CGImageSource,
    maxPixelSize: Int? = nil
) -> CGImage? {
    let frameCount = frameCount(from: imageSource)
    guard frameIndex >= 0, frameIndex < frameCount else {
        return nil
    }
    // ...
}
```

## 修改二：`CanvasEditorSession` 增加 `gifFrameImportEditorContext(...)`，把 UI 所需共享语义留在 session 层

### 修改前

- `CanvasEditorSession` 只有 `gifFrameImportRequest(...)`，偏向“用户已经选好帧并准备落板”的提交阶段。
- 但阶段 6 的 iOS 页面需要的不是最终 request，而是“用于渲染多选网格”的编辑上下文。
- 如果没有这层入口，平台页就要自己拿 item、读 transient / persisted GIF 数据、再自己建 `CGImageSource` 和读帧数，职责会重新外溢。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 类型/函数: gifFrameImportRequest(for:frameIndices:configuration:userDefaults:)
// 功能说明: 修改前 session 只有最终导入 request 构造入口，没有给选帧页面使用的 editor context。
func gifFrameImportRequest(
    for itemID: CanvasItemID,
    frameIndices: [Int],
    configuration: CanvasGIFFrameImportConfiguration = .current,
    userDefaults: UserDefaults = .standard
) throws -> CanvasImportRequest {
    guard
        let sourceItem = scene.item(withID: itemID),
        sourceItem.isVideo == false,
        sourceItem.assetKind == .animatedGIF
    else {
        throw CanvasGIFFrameImportBuilderError.invalidAnimatedGIFItem(
            itemID: itemID
        )
    }

    let sourceData = try gifFrameImportSourceData(
        for: sourceItem,
        userDefaults: userDefaults
    )
    return try CanvasGIFFrameImportBuilder.makeImportRequest(
        from: sourceItem,
        gifData: sourceData,
        selectedFrameIndices: frameIndices,
        configuration: configuration
    )
}
```

### 修改后

- 新增 `gifFrameImportEditorContext(...)`，继续复用已有的 `gifFrameImportSourceData(...)` 数据回退链路：
  - 先读 transient payload
  - 读不到再回退 persisted GIF asset data
- 该方法在共享层完成：
  - item 类型校验
  - GIF 数据读取
  - `CGImageSource` 构建
  - 帧数合法性检查
  - 选帧页配置打包
- 这样阶段 6 的 iOS 页面只消费 editor context，不再自己关心 GIF 原始资源是 transient 还是 persisted。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 类型/函数: gifFrameImportEditorContext(for:configuration:userDefaults:)
// 功能说明: 修改后 session 会把 GIF 页面真正需要的上下文收口出来，避免平台层自己拼装 GIF 数据与帧数。
func gifFrameImportEditorContext(
    for itemID: CanvasItemID,
    configuration: CanvasGIFFrameImportConfiguration = .current,
    userDefaults: UserDefaults = .standard
) throws -> CanvasGIFFrameImportEditorContext {
    guard
        let sourceItem = scene.item(withID: itemID),
        sourceItem.isVideo == false,
        sourceItem.assetKind == .animatedGIF
    else {
        throw CanvasGIFFrameImportBuilderError.invalidAnimatedGIFItem(
            itemID: itemID
        )
    }

    let sourceData = try gifFrameImportSourceData(
        for: sourceItem,
        userDefaults: userDefaults
    )
    guard
        let imageSource = CanvasGIFFrameService.makeImageSource(from: sourceData)
    else {
        throw CanvasGIFFrameImportBuilderError.invalidGIFData
    }

    let frameCount = CanvasGIFFrameService.frameCount(from: imageSource)
    guard frameCount > 1 else {
        throw CanvasGIFFrameImportBuilderError.invalidGIFData
    }

    return CanvasGIFFrameImportEditorContext(
        itemID: itemID,
        gifData: sourceData,
        frameCount: frameCount,
        selectionGrid: configuration.selectionGrid,
        thumbnailMaxPixelSize: configuration.thumbnailMaxPixelSize
    )
}
```

## 修改三：iOS 入口从“只传 itemID 的壳子”升级为“先拿共享 context，再打开真实页面”

### 修改前

- `iOSViewController` 在阶段 5 只是把 `itemID + configuration` 塞给一个占位页面壳子。
- 页面如果要变成真正可用的多选网格，仍然会被迫自己去找 GIF 原始数据和读帧数。
- 同时打开失败也没有 GIF 专用的错误提示。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 类型/函数: presentGIFFrameImportEditor(for:)
// 功能说明: 修改前 iOS 入口只把 itemID 与配置传给壳子控制器，真实 GIF 编辑上下文还没有在共享层收口。
private func presentGIFFrameImportEditor(for itemID: CanvasItemID) {
    guard presentedViewController == nil else {
        return
    }

    let editorViewController = iOSGIFFrameImportViewController(
        itemID: itemID,
        configuration: .current
    ) { [weak self] frameIndices in
        guard let self else {
            throw iOSGIFFrameImportFlowError.presenterUnavailable
        }

        try self.performGIFFrameImport(
            for: itemID,
            frameIndices: frameIndices
        )
    }
    present(editorViewController, animated: true)
}
```

### 修改后

- `presentGIFFrameImportEditor(for:)` 现在会先调用 `editorSession.gifFrameImportEditorContext(for:)`。
- iOS 页面改为直接吃 `editorContext`，这使得 UI 层天然复用共享数据语义。
- 打开失败时增加 `presentGIFFrameImportEditorError(...)`，与视频入口一样有明确错误提示，而不是静默失败。
- 导入动作的提交阶段仍然保持不变，继续走 `performGIFFrameImport(...) -> .importMedia(request)`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 类型/函数: presentGIFFrameImportEditor(for:) / performGIFFrameImport(for:frameIndices:)
// 功能说明: 修改后 iOS 入口会先拿共享 editor context，再打开真正的多选页，提交时继续复用 importMedia 主链。
private func presentGIFFrameImportEditor(for itemID: CanvasItemID) {
    guard presentedViewController == nil else {
        return
    }

    do {
        let editorContext = try editorSession.gifFrameImportEditorContext(
            for: itemID
        )
        let editorViewController = iOSGIFFrameImportViewController(
            editorContext: editorContext
        ) { [weak self] frameIndices in
            guard let self else {
                throw iOSGIFFrameImportFlowError.presenterUnavailable
            }

            try self.performGIFFrameImport(
                for: itemID,
                frameIndices: frameIndices
            )
        }
        present(editorViewController, animated: true)
    } catch {
        presentGIFFrameImportEditorError(
            message: error.localizedDescription
        )
    }
}

private func performGIFFrameImport(
    for itemID: CanvasItemID,
    frameIndices: [Int]
) throws {
    let request = try editorSession.gifFrameImportRequest(
        for: itemID,
        frameIndices: frameIndices
    )
    performCommand(.importMedia(request))
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 类型/函数: presentGIFFrameImportEditorError(message:)
// 功能说明: 修改后 iOS 端在 GIF 页面无法打开时会走专用错误提示，避免平台入口静默失败。
private func presentGIFFrameImportEditorError(message: String) {
    let alertController = UIAlertController(
        title: "Unable to Open GIF Frame Importer",
        message: message,
        preferredStyle: .alert
    )
    alertController.addAction(UIAlertAction(title: "OK", style: .default))
    present(alertController, animated: true)
}
```

## 修改四：`iOSGIFFrameImportViewController` 从占位壳子升级为真正的 4 列多选 `UICollectionView` 页面

### 修改前

- 阶段 5 的 iOS 页面只是一个“可打开”的占位壳子。
- 页面里没有：
  - `UICollectionView`
  - 多选状态
  - 缩略图异步加载
  - cell 生命周期清理
  - 4 列布局计算
- `selectedFrameIndices` 只是 `[Int]`，但没有任何 UI 会去维护它，所以导入按钮实际上无法进入真实工作流。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSGIFFrameImportViewController.swift
// 类型/函数: iOSGIFFrameImportViewController.viewDidLoad() / handleImportButtonTap()
// 功能说明: 修改前 iOS 端只是一个占位壳子，无法展示 GIF 帧网格，也无法维护多选状态。
final class iOSGIFFrameImportViewController: UIViewController {
    private let itemID: CanvasItemID
    private let configuration: CanvasGIFFrameImportConfiguration
    private let onImportSelectedFrames: ([Int]) throws -> Void
    private let detailLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.font = .systemFont(ofSize: 15)
        return label
    }()

    private var selectedFrameIndices: [Int] = [] {
        didSet {
            updateImportButtonConfiguration()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupViewHierarchy()
        setupConstraints()
        configureButtons()
        applyInitialState()
    }

    private func applyInitialState() {
        detailLabel.text =
            "GIF item: \(itemID.uuidString)\n\n" +
            "The \(configuration.selectionGrid.columns)-column multi-selection frame grid " +
            "and thumbnail loading UI will be added in the next phase."
        updateImportButtonConfiguration()
    }
}
```

### 修改后

- 页面现在真正实现了阶段 6 要求的 iOS 多选帧页：
  - `UICollectionViewFlowLayout`
  - 固定 4 列，列数来自 `editorContext.selectionGrid.columns`
  - `selectedFrameIndices: Set<Int>`
  - 多选交互
  - 导入中禁用交互
  - 按需异步解码缩略图
  - 滚出屏幕时取消缩略图任务
- 页面不再自己管理 GIF 数据源文件路径，而是直接消费共享 `editorContext`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSGIFFrameImportViewController.swift
// 类型/函数: iOSGIFFrameImportViewController.init(editorContext:onImportSelectedFrames:) / updateCollectionLayout()
// 功能说明: 修改后 iOS 端真正拥有固定列数的多选网格页面，列数和缩略图参数都来自共享 editor context。
final class iOSGIFFrameImportViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    private enum Layout {
        static let titleTopInset: CGFloat = 20
        static let horizontalInset: CGFloat = 24
        static let summaryTopSpacing: CGFloat = 16
        static let collectionTopSpacing: CGFloat = 18
        static let minimumItemWidth: CGFloat = 56
        static let itemHeightExtra: CGFloat = 34
    }

    private let editorContext: CanvasGIFFrameImportEditorContext
    private let onImportSelectedFrames: ([Int]) throws -> Void
    private let collectionViewLayout = UICollectionViewFlowLayout()
    private lazy var collectionView: UICollectionView = {
        let collectionView = UICollectionView(
            frame: .zero,
            collectionViewLayout: collectionViewLayout
        )
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.allowsSelection = true
        collectionView.allowsMultipleSelection = true
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(
            iOSGIFFrameImportCollectionViewCell.self,
            forCellWithReuseIdentifier: iOSGIFFrameImportCollectionViewCell.reuseIdentifier
        )
        return collectionView
    }()

    init(
        editorContext: CanvasGIFFrameImportEditorContext,
        onImportSelectedFrames: @escaping ([Int]) throws -> Void
    ) {
        self.editorContext = editorContext
        self.onImportSelectedFrames = onImportSelectedFrames
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        modalTransitionStyle = .coverVertical
    }

    private func updateCollectionLayout() {
        let selectionGrid = editorContext.selectionGrid
        let safeAreaInsets = view.safeAreaInsets
        collectionViewLayout.scrollDirection = .vertical
        collectionViewLayout.sectionInset = UIEdgeInsets(
            top: selectionGrid.contentInsets.top,
            left: selectionGrid.contentInsets.leading,
            bottom: selectionGrid.contentInsets.bottom + safeAreaInsets.bottom,
            right: selectionGrid.contentInsets.trailing
        )
        collectionViewLayout.minimumInteritemSpacing =
            selectionGrid.horizontalSpacing
        collectionViewLayout.minimumLineSpacing =
            selectionGrid.verticalSpacing

        let availableWidth = max(
            collectionView.bounds.width
                - collectionViewLayout.sectionInset.left
                - collectionViewLayout.sectionInset.right,
            Layout.minimumItemWidth
        )
        let columns = max(selectionGrid.columns, 1)
        let totalSpacing = selectionGrid.horizontalSpacing * CGFloat(columns - 1)
        let resolvedItemWidth = floor(
            max(
                availableWidth - totalSpacing,
                Layout.minimumItemWidth * CGFloat(columns)
            ) / CGFloat(columns)
        )
        collectionViewLayout.itemSize = CGSize(
            width: resolvedItemWidth,
            height: resolvedItemWidth + Layout.itemHeightExtra
        )
        collectionViewLayout.invalidateLayout()
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSGIFFrameImportViewController.swift
// 类型/函数: scheduleThumbnailLoad(for:) / cancelThumbnailLoad(for:) / reloadFrameIfVisible(_:)
// 功能说明: 修改后 iOS 页面会按需异步解码 GIF 缩略图，并在 cell 不可见时取消任务，避免一次性预解码所有帧。
private func scheduleThumbnailLoad(
    for frameIndex: Int
) {
    if let state = thumbnailStates[frameIndex] {
        switch state {
        case .idle, .failed:
            break
        case .loading, .loaded:
            return
        }
    }

    thumbnailStates[frameIndex] = .loading

    var workItem: DispatchWorkItem?
    workItem = DispatchWorkItem { [weak self] in
        guard let self, workItem?.isCancelled == false else {
            return
        }

        let resolvedImage: UIImage?
        if let imageSource = self.imageSource,
           let cgImage = CanvasGIFFrameService.decodeFrame(
                at: frameIndex,
                from: imageSource,
                maxPixelSize: self.editorContext.thumbnailMaxPixelSize
           ) {
            resolvedImage = UIImage(cgImage: cgImage)
        } else {
            resolvedImage = nil
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            self.thumbnailLoadWorkItems[frameIndex] = nil
            guard workItem?.isCancelled == false else {
                self.thumbnailStates[frameIndex] = .idle
                self.reloadFrameIfVisible(frameIndex)
                return
            }

            if let resolvedImage {
                self.thumbnailStates[frameIndex] = .loaded(resolvedImage)
            } else {
                self.thumbnailStates[frameIndex] = .failed
            }
            self.reloadFrameIfVisible(frameIndex)
        }
    }
    thumbnailLoadWorkItems[frameIndex] = workItem
    workerQueue.async(execute: workItem!)
}

private func cancelThumbnailLoad(for frameIndex: Int) {
    guard let workItem = thumbnailLoadWorkItems.removeValue(forKey: frameIndex) else {
        return
    }

    workItem.cancel()
    if case .loading = thumbnailStates[frameIndex] {
        thumbnailStates[frameIndex] = .idle
    }
}

private func reloadFrameIfVisible(_ frameIndex: Int) {
    let indexPath = IndexPath(item: frameIndex, section: 0)
    guard collectionView.indexPathsForVisibleItems.contains(indexPath) else {
        return
    }

    collectionView.reloadItems(at: [indexPath])
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSGIFFrameImportViewController.swift
// 类型/函数: handleImportButtonTap() / collectionView(_:cellForItemAt:) / collectionView(_:shouldSelectItemAt:)
// 功能说明: 修改后 iOS 页面真正维护多选状态，未选中时禁止导入，导入时禁用交互并继续把选中的 frameIndex 列表回传给共享导入链路。
@objc
private func handleImportButtonTap() {
    guard
        isImporting == false,
        selectedFrameIndices.isEmpty == false
    else {
        return
    }

    let resolvedFrameIndices = selectedFrameIndices.sorted()
    isImporting = true
    DispatchQueue.main.async { [weak self] in
        guard let self else {
            return
        }

        do {
            try self.onImportSelectedFrames(resolvedFrameIndices)
            self.dismiss(animated: true)
        } catch {
            self.isImporting = false
            self.presentError(
                title: "Unable to Import GIF Frames",
                message: error.localizedDescription
            )
        }
    }
}

func collectionView(
    _ collectionView: UICollectionView,
    cellForItemAt indexPath: IndexPath
) -> UICollectionViewCell {
    guard let cell = collectionView.dequeueReusableCell(
        withReuseIdentifier: iOSGIFFrameImportCollectionViewCell.reuseIdentifier,
        for: indexPath
    ) as? iOSGIFFrameImportCollectionViewCell else {
        return UICollectionViewCell()
    }

    let frameIndex = indexPath.item
    let thumbnailState = thumbnailStates[frameIndex] ?? .idle
    cell.apply(
        frameIndex: frameIndex,
        thumbnailState: thumbnailState
    )
    cell.isSelected = selectedFrameIndices.contains(frameIndex)
    if case .idle = thumbnailState {
        scheduleThumbnailLoad(for: frameIndex)
    }
    return cell
}

func collectionView(
    _ collectionView: UICollectionView,
    shouldSelectItemAt indexPath: IndexPath
) -> Bool {
    guard isImporting == false else {
        return false
    }

    if selectedFrameIndices.contains(indexPath.item) {
        collectionView.deselectItem(at: indexPath, animated: true)
        updateSelection(
            isSelected: false,
            at: indexPath
        )
        return false
    }

    return true
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSGIFFrameImportViewController.swift
// 类型/函数: iOSGIFFrameImportCollectionViewCell.apply(frameIndex:thumbnailState:) / updateSelectionAppearance()
// 功能说明: 修改后 cell 有完整的缩略图、占位态、失败态和选中高亮，不再只是文本占位。
private final class iOSGIFFrameImportCollectionViewCell: UICollectionViewCell {
    static let reuseIdentifier = "iOSGIFFrameImportCollectionViewCell"

    func apply(
        frameIndex: Int,
        thumbnailState: iOSGIFFrameImportViewController.ThumbnailState
    ) {
        frameLabel.text = "Frame \(frameIndex + 1)"

        switch thumbnailState {
        case .idle, .loading:
            imageView.image = nil
            placeholderLabel.text = "Loading..."
            placeholderLabel.isHidden = false
            activityIndicatorView.startAnimating()
        case let .loaded(image):
            imageView.image = image
            placeholderLabel.text = nil
            placeholderLabel.isHidden = true
            activityIndicatorView.stopAnimating()
        case .failed:
            imageView.image = nil
            placeholderLabel.text = "Unable to load"
            placeholderLabel.isHidden = false
            activityIndicatorView.stopAnimating()
        }
    }

    private func updateSelectionAppearance() {
        contentView.layer.borderColor = isSelected
            ? UIColor.systemBlue.cgColor
            : UIColor.separator.cgColor
        contentView.backgroundColor = isSelected
            ? UIColor.systemBlue.withAlphaComponent(0.12)
            : UIColor.tertiarySystemBackground
        selectionBadgeView.isHidden = isSelected == false
    }
}
```

## 修改五：补充 editor context 的共享层定向测试

### 修改前

- `CanvasGIFFrameImportBuilderTests` 已经验证了：
  - builder 直接构造 request
  - `gifFrameImportRequest(...)` 的 transient 路径
  - `gifFrameImportRequest(...)` 的 persisted 回退路径
- 但还没有覆盖阶段 6 新增的 `gifFrameImportEditorContext(...)`。
- 这意味着即使 iOS 页面能编译，也没有自动验证它拿到的 editor context 是否真的来自正确的数据源链路。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasGIFFrameImportBuilderTests.swift
// 类型/函数: CanvasGIFFrameImportBuilderTests
// 功能说明: 修改前测试只覆盖 request 构造链路，没有覆盖 editor context 的 transient / persisted 两条来源路径。
final class CanvasGIFFrameImportBuilderTests: XCTestCase {
    func testSessionGIFFrameImportRequestUsesTransientPayloadSourceData() throws {
        // ...
    }

    func testSessionGIFFrameImportRequestFallsBackToPersistedGIFAssetData() throws {
        // ...
    }
}
```

### 修改后

- 新增两组测试：
  - `testSessionGIFFrameImportEditorContextUsesTransientPayloadSourceData()`
  - `testSessionGIFFrameImportEditorContextFallsBackToPersistedGIFAssetData()`
- 现在共享层会自动验证：
  - editor context 的 `gifData` 是否来自正确来源
  - `frameCount` 是否正确
  - `selectionGrid` / `thumbnailMaxPixelSize` 是否准确透传配置

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasGIFFrameImportBuilderTests.swift
// 类型/函数: testSessionGIFFrameImportEditorContextUsesTransientPayloadSourceData()
// 功能说明: 修改后测试会验证 session 给 iOS 页面返回的 editor context 是否正确复用 transient GIF 源数据与当前配置。
func testSessionGIFFrameImportEditorContextUsesTransientPayloadSourceData() throws {
    let session = makeGIFFrameImportTestSession()
    let gifData = try makeGIFFrameImportTestGIFData(
        frames: [
            GIFFrameImportTestSpec(
                image: try makeGIFFrameImportTestImage(
                    red: 1,
                    green: 0,
                    blue: 0
                ),
                delayTime: 0.1
            ),
            GIFFrameImportTestSpec(
                image: try makeGIFFrameImportTestImage(
                    red: 0,
                    green: 1,
                    blue: 0
                ),
                delayTime: 0.1
            ),
            GIFFrameImportTestSpec(
                image: try makeGIFFrameImportTestImage(
                    red: 0,
                    green: 0,
                    blue: 1
                ),
                delayTime: 0.1
            )
        ]
    )
    let sourceImage = try XCTUnwrap(
        CanvasResolvedImportImage(
            data: gifData,
            typeIdentifier: UTType.gif.identifier,
            filenameHint: "editor-context-source.gif"
        )
    )
    let importedItem = try XCTUnwrap(
        session.appendImportedMedia(
            [.image(sourceImage)],
            placement: .worldPoint(CGPoint(x: 30, y: 45)),
            layout: .stacked
        ).first
    )

    let editorContext = try session.gifFrameImportEditorContext(
        for: importedItem.id
    )

    XCTAssertEqual(editorContext.itemID, importedItem.id)
    XCTAssertEqual(editorContext.gifData, gifData)
    XCTAssertEqual(editorContext.frameCount, 3)
    XCTAssertEqual(
        editorContext.selectionGrid,
        CanvasGIFFrameImportConfiguration.current.selectionGrid
    )
    XCTAssertEqual(
        editorContext.thumbnailMaxPixelSize,
        CanvasGIFFrameImportConfiguration.current.thumbnailMaxPixelSize
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasGIFFrameImportBuilderTests.swift
// 类型/函数: testSessionGIFFrameImportEditorContextFallsBackToPersistedGIFAssetData()
// 功能说明: 修改后测试会验证 session 在没有 transient payload 时，仍能从持久化 GIF asset data 正确构造 editor context。
func testSessionGIFFrameImportEditorContextFallsBackToPersistedGIFAssetData() throws {
    try withTemporaryGIFFrameImportWorkspace { _, userDefaults in
        let session = makeGIFFrameImportTestSession()
        session.startNewBoard(
            now: Date(timeIntervalSince1970: 1_710_001_100)
        )
        let boardID = try XCTUnwrap(session.activeBoardID)
        let gifData = try makeGIFFrameImportTestGIFData(
            frames: [
                GIFFrameImportTestSpec(
                    image: try makeGIFFrameImportTestImage(
                        red: 1,
                        green: 0,
                        blue: 0
                    ),
                    delayTime: 0.1
                ),
                GIFFrameImportTestSpec(
                    image: try makeGIFFrameImportTestImage(
                        red: 0,
                        green: 1,
                        blue: 0
                    ),
                    delayTime: 0.1
                )
            ]
        )
        let persistedFilename = "persisted-editor-context.gif"
        let posterImage = try makeGIFFrameImportTestImage(
            red: 1,
            green: 0,
            blue: 0
        )
        let sourceItem = CanvasImageItem(
            asset: CanvasImageAsset(
                reference: .persistedAnimatedGIF(filename: persistedFilename),
                poster: CanvasImagePoster(cgImage: posterImage),
                logicalPixelSize: CGSize(
                    width: posterImage.width,
                    height: posterImage.height
                )
            ),
            center: CGPoint(x: 50, y: 80),
            size: CGSize(width: 140, height: 90),
            zIndex: 0
        )
        session.scene.append(sourceItem)

        let assetsDirectoryURL = try BoardStore.ensureAssetsDirectoryURL(
            for: boardID,
            userDefaults: userDefaults
        )
        try CoordinatedFileIO.writeData(
            gifData,
            to: assetsDirectoryURL.appendingPathComponent(
                persistedFilename
            )
        )

        let editorContext = try session.gifFrameImportEditorContext(
            for: sourceItem.id,
            userDefaults: userDefaults
        )

        XCTAssertEqual(editorContext.itemID, sourceItem.id)
        XCTAssertEqual(editorContext.gifData, gifData)
        XCTAssertEqual(editorContext.frameCount, 2)
    }
}
```

## 验证结果

- 已执行：`xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=macOS" -only-testing:"MyCanvas_Ver_0Tests/CanvasGIFFrameImportBuilderTests"`
- 结果：`CanvasGIFFrameImportBuilderTests` 通过，包含新增的 editor context 定向测试。
- 已执行：`xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "generic/platform=iOS"`
- 结果：iOS 构建通过，说明阶段 6 的多选页 UI 与入口接线已可编译。
- 已检查：`CanvasGIFFrameService.swift`、`CanvasEditorSession.swift`、`iOSViewController.swift`、`iOSGIFFrameImportViewController.swift`、`CanvasGIFFrameImportBuilderTests.swift` 无新增 linter 问题。

