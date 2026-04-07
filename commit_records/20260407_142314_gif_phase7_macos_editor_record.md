# 20260407_142314_gif_phase7_macos_editor_record

## 记录范围

- 记录内容：把 macOS GIF 选帧入口从“直接打开占位页”改成“先向共享层索取 `CanvasGIFFrameImportEditorContext`，再打开 sheet”。
- 记录内容：把 `MyCanvas_Ver_0/Platform/macOS/macOSGIFFrameImportViewController.swift` 从阶段 5 的占位壳子升级成真正可用的 `NSCollectionView` 多选页。
- 记录内容：补齐 macOS 端 4 列可配置网格、缩略图异步解码、cell 复用取消、点击多选、导入中禁用交互与专用错误提示。
- 涉及文件：`MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/macOS/macOSGIFFrameImportViewController.swift`
- 本记录不包含：阶段 8 的测试补齐与回归矩阵。
- 本记录不包含：`.cursor/plans/*.md` 的计划文件状态变化。
- 本记录不包含：git commit / push。

## 修改一：macOS 入口从直接打开占位壳页，改为先取共享 editor context

### 修改前

- `macOSViewController` 在收到 GIF 菜单动作后，直接创建 `macOSGIFFrameImportViewController(itemID:configuration:onImportSelectedFrames:)`。
- 入口层没有先向 `CanvasEditorSession` 获取共享 `CanvasGIFFrameImportEditorContext`。
- 如果 GIF 页面打开前构造上下文失败，macOS 端没有 GIF 专用的打开失败提示。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 类型/函数: presentGIFFrameImportEditor(for:)
// 功能说明: 修改前入口直接打开占位页，只传 itemID 和 configuration，没有先从共享层取 GIF editor context。
private func presentGIFFrameImportEditor(for itemID: CanvasItemID) {
    guard presentedViewControllers?.isEmpty != false else {
        return
    }

    let editorViewController = macOSGIFFrameImportViewController(
        itemID: itemID,
        configuration: .current
    ) { [weak self] frameIndices in
        guard let self else {
            throw macOSGIFFrameImportFlowError.presenterUnavailable
        }

        try self.performGIFFrameImport(
            for: itemID,
            frameIndices: frameIndices
        )
    }
    presentAsSheet(editorViewController)
}
```

### 修改后

- 入口改为先调用 `editorSession.gifFrameImportEditorContext(for:)`，由共享层统一提供 GIF 源数据、帧数和页面配置。
- 页面构造参数切换为 `editorContext`，macOS 和 iOS 走同一套共享输入。
- 新增 `presentGIFFrameImportEditorError(message:)`，在上下文构造失败时给出 GIF 专用错误弹窗，不再静默失败。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 类型/函数: presentGIFFrameImportEditor(for:) / presentGIFFrameImportEditorError(message:)
// 功能说明: 修改后入口先向共享层取 editor context，再打开 sheet；如果 context 构造失败，会弹出 GIF 专用错误提示。
private func presentGIFFrameImportEditor(for itemID: CanvasItemID) {
    guard presentedViewControllers?.isEmpty != false else {
        return
    }

    do {
        let editorContext = try editorSession.gifFrameImportEditorContext(
            for: itemID
        )
        let editorViewController = macOSGIFFrameImportViewController(
            editorContext: editorContext
        ) { [weak self] frameIndices in
            guard let self else {
                throw macOSGIFFrameImportFlowError.presenterUnavailable
            }

            try self.performGIFFrameImport(
                for: itemID,
                frameIndices: frameIndices
            )
        }
        presentAsSheet(editorViewController)
    } catch {
        presentGIFFrameImportEditorError(
            message: error.localizedDescription
        )
    }
}

private func presentGIFFrameImportEditorError(message: String) {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "Unable to Open GIF Frame Importer"
    alert.informativeText = message
    alert.addButton(withTitle: "OK")

    if let window = view.window {
        alert.beginSheetModal(for: window)
    } else {
        alert.runModal()
    }
}
```

## 修改二：macOS GIF 页面从占位文本页升级为真正的 `NSCollectionView` 多选页

### 修改前

- `macOSGIFFrameImportViewController` 只保存 `itemID` 和 `configuration`。
- 页面中只有标题、取消按钮、导入按钮和一个 `detailLabel` 占位文案。
- `selectedFrameIndices` 只是简单数组，没有真实帧网格、没有缩略图状态、没有复用与异步解码。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSGIFFrameImportViewController.swift
// 类型/函数: macOSGIFFrameImportViewController.init(...) / applyInitialState()
// 功能说明: 修改前控制器只是占位 sheet，没有共享 editor context、没有 NSCollectionView，也没有真实选帧能力。
final class macOSGIFFrameImportViewController: NSViewController {
    private let itemID: CanvasItemID
    private let configuration: CanvasGIFFrameImportConfiguration
    private let onImportSelectedFrames: ([Int]) throws -> Void
    private let detailLabel: NSTextField = {
        let label = NSTextField(wrappingLabelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .center
        label.textColor = .secondaryLabelColor
        label.font = .systemFont(ofSize: 14)
        return label
    }()

    private var selectedFrameIndices: [Int] = [] {
        didSet {
            updateImportButtonAppearance()
        }
    }

    init(
        itemID: CanvasItemID,
        configuration: CanvasGIFFrameImportConfiguration = .current,
        onImportSelectedFrames: @escaping ([Int]) throws -> Void
    ) {
        self.itemID = itemID
        self.configuration = configuration
        self.onImportSelectedFrames = onImportSelectedFrames
        super.init(nibName: nil, bundle: nil)
    }

    private func applyInitialState() {
        detailLabel.stringValue =
            "GIF item: \(itemID.uuidString)\n\n" +
            "The \(configuration.selectionGrid.columns)-column multi-selection frame grid " +
            "and thumbnail loading UI will be added in the next phase."
        updateImportButtonAppearance()
    }
}
```

### 修改后

- 控制器改为持有共享 `CanvasGIFFrameImportEditorContext`，直接复用共享层提供的 GIF 数据、帧数和网格配置。
- 页面新增 `NSCollectionViewFlowLayout + NSCollectionView + NSScrollView`，真正承载 GIF 帧网格。
- 维护 `selectedFrameIndices: Set<Int>`、`thumbnailStates`、`thumbnailLoadWorkItems`，为多选和异步缩略图加载准备完整状态。
- `applyInitialState()` 不再写占位说明，而是刷新摘要文案、按钮状态并触发 collection 首次加载。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSGIFFrameImportViewController.swift
// 类型/函数: macOSGIFFrameImportViewController.init(...) / applyInitialState()
// 功能说明: 修改后控制器直接吃共享 editor context，并持有真实网格页所需的 collection、缩略图和多选状态。
final class macOSGIFFrameImportViewController: NSViewController, NSCollectionViewDataSource, NSCollectionViewDelegate {
    fileprivate enum ThumbnailState {
        case idle
        case loading
        case loaded(NSImage)
        case failed
    }

    private let editorContext: CanvasGIFFrameImportEditorContext
    private let onImportSelectedFrames: ([Int]) throws -> Void
    private let workerQueue = DispatchQueue(
        label: "MyCanvas.macOS.GIFFrameImportEditor",
        qos: .userInitiated
    )
    private lazy var imageSource: CGImageSource? = CanvasGIFFrameService.makeImageSource(
        from: editorContext.gifData
    )
    private let collectionViewLayout = NSCollectionViewFlowLayout()
    private lazy var collectionView: NSCollectionView = {
        let collectionView = NSCollectionView()
        collectionView.backgroundColors = [.clear]
        collectionView.collectionViewLayout = collectionViewLayout
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.isSelectable = false
        collectionView.register(
            macOSGIFFrameImportCollectionItem.self,
            forItemWithIdentifier: macOSGIFFrameImportCollectionItem.reuseIdentifier
        )
        return collectionView
    }()
    private lazy var collectionScrollView: NSScrollView = {
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = collectionView
        return scrollView
    }()

    private var selectedFrameIndices: Set<Int> = [] {
        didSet {
            updateSelectionSummary()
            updateImportButtonAppearance()
        }
    }
    private var thumbnailStates: [Int: ThumbnailState] = [:]
    private var thumbnailLoadWorkItems: [Int: DispatchWorkItem] = [:]

    init(
        editorContext: CanvasGIFFrameImportEditorContext,
        onImportSelectedFrames: @escaping ([Int]) throws -> Void
    ) {
        self.editorContext = editorContext
        self.onImportSelectedFrames = onImportSelectedFrames
        super.init(nibName: nil, bundle: nil)
    }

    private func applyInitialState() {
        updateSelectionSummary()
        updateImportButtonAppearance()
        collectionView.reloadData()
    }
}
```

## 修改三：补齐 4 列网格布局、缩略图异步解码和多选交互

### 修改前

- 文件中不存在 `updateCollectionLayout()`、`scheduleThumbnailLoad(for:)`、`toggleSelection(for:)` 这类真实页面能力。
- 占位页没有按照 `selectionGrid.columns` 动态计算列宽，也没有后台缩略图解码和 cell 刷新逻辑。
- 导入按钮只能基于一个简单数组做启停，没有“导入中禁用交互”和已选数量展示。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSGIFFrameImportViewController.swift
// 类型/函数: updateImportButtonAppearance() / handleImportButtonClick()
// 功能说明: 修改前按钮逻辑只处理最基本的可点击状态，页面并不存在网格布局、缩略图加载和点击多选逻辑。
private func updateImportButtonAppearance() {
    importButton.title = isImporting ? "Importing..." : "Import"
    importButton.isEnabled =
        selectedFrameIndices.isEmpty == false &&
        isImporting == false
}

@objc
private func handleImportButtonClick() {
    guard
        isImporting == false,
        selectedFrameIndices.isEmpty == false
    else {
        return
    }

    isImporting = true
    do {
        try onImportSelectedFrames(selectedFrameIndices)
        dismiss(self)
    } catch {
        isImporting = false
        presentError(
            title: "Unable to Import GIF Frames",
            message: error.localizedDescription
        )
    }
}
```

### 修改后

- `updateCollectionLayout()` 按共享 `selectionGrid` 动态计算 section inset、间距、列数、item 宽高和内容高度，真正把帧铺成 4 列可配置网格。
- `scheduleThumbnailLoad(for:)` 在后台通过 `CanvasGIFFrameService.decodeFrame(...)` 解码缩略图，回主线程更新 `thumbnailStates` 并只刷新可见 item。
- `toggleSelection(for:)` 与 `selectedFrameIndices: Set<Int>` 配合，实现点击多选；`isImporting` 会同时控制按钮文案、collection 透明度和取消按钮可用性。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSGIFFrameImportViewController.swift
// 类型/函数: updateCollectionLayout() / scheduleThumbnailLoad(for:) / toggleSelection(for:)
// 功能说明: 修改后页面按共享 grid 配置计算 4 列布局，在后台解码 GIF 缩略图，并在主线程维护可见 cell 的多选状态。
private func updateCollectionLayout() {
    let selectionGrid = editorContext.selectionGrid
    let contentInsets = selectionGrid.contentInsets
    let sectionInset = NSEdgeInsets(
        top: contentInsets.top,
        left: contentInsets.leading,
        bottom: contentInsets.bottom,
        right: contentInsets.trailing
    )
    collectionViewLayout.sectionInset = sectionInset
    collectionViewLayout.minimumLineSpacing = selectionGrid.verticalSpacing
    collectionViewLayout.minimumInteritemSpacing = selectionGrid.horizontalSpacing

    let contentWidth = max(collectionScrollView.contentView.bounds.width, 360)
    let availableWidth = max(
        contentWidth - sectionInset.left - sectionInset.right,
        Layout.minimumItemWidth
    )
    let columns = max(selectionGrid.columns, 1)
    let totalSpacing = selectionGrid.horizontalSpacing * CGFloat(columns - 1)
    let itemWidth = floor(
        max(
            availableWidth - totalSpacing,
            Layout.minimumItemWidth * CGFloat(columns)
        ) / CGFloat(columns)
    )
    let itemHeight = itemWidth + Layout.itemHeightExtra
    collectionViewLayout.itemSize = NSSize(width: itemWidth, height: itemHeight)
    // ... 后续继续根据 frameCount 计算 rowCount / contentHeight / frame ...
}

private func scheduleThumbnailLoad(
    for frameIndex: Int
) {
    thumbnailStates[frameIndex] = .loading

    var workItem: DispatchWorkItem?
    workItem = DispatchWorkItem { [weak self] in
        guard let self, workItem?.isCancelled == false else {
            return
        }

        let resolvedImage: NSImage?
        if let imageSource = self.imageSource,
           let cgImage = CanvasGIFFrameService.decodeFrame(
                at: frameIndex,
                from: imageSource,
                maxPixelSize: self.editorContext.thumbnailMaxPixelSize
           ) {
            resolvedImage = NSImage(
                cgImage: cgImage,
                size: NSSize(width: cgImage.width, height: cgImage.height)
            )
        } else {
            resolvedImage = nil
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            self.thumbnailLoadWorkItems[frameIndex] = nil
            self.thumbnailStates[frameIndex] =
                resolvedImage.map { .loaded($0) } ?? .failed
            self.reloadFrameIfVisible(frameIndex)
        }
    }

    thumbnailLoadWorkItems[frameIndex] = workItem
    workerQueue.async(execute: workItem!)
}

private func toggleSelection(for frameIndex: Int) {
    guard isImporting == false else {
        return
    }

    if selectedFrameIndices.contains(frameIndex) {
        selectedFrameIndices.remove(frameIndex)
    } else {
        selectedFrameIndices.insert(frameIndex)
    }

    let indexPath = IndexPath(item: frameIndex, section: 0)
    if let item = collectionView.item(
        at: indexPath
    ) as? macOSGIFFrameImportCollectionItem {
        item.isFrameSelected = selectedFrameIndices.contains(frameIndex)
    } else {
        collectionView.reloadItems(at: Set([indexPath]))
    }
}
```

## 修改四：新增 macOS collection item，承接缩略图显示、加载态和选中高亮

### 修改前

- 文件在 `presentError(...)` 之后直接结束。
- 阶段 5 的占位页没有独立的 `NSCollectionViewItem` 类型，也就不存在 cell 级别的缩略图、点击手势、选中徽标和复用清理。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSGIFFrameImportViewController.swift
// 类型/函数: presentError(title:message:)
// 功能说明: 修改前文件只到控制器自身结束，没有单独的 collection item 类型来承接帧缩略图 UI。
private func presentError(title: String, message: String) {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = title
    alert.informativeText = message
    alert.addButton(withTitle: "OK")

    if let window = view.window {
        alert.beginSheetModal(for: window)
    } else {
        alert.runModal()
    }
}
```

### 修改后

- 新增 `macOSGIFFrameImportCollectionItem`，把帧预览图、占位文案、加载菊花、帧序号和选中徽标都封装到 item 内。
- `prepareForReuse()` 会取消对应 frame 的在途请求并清空 UI 状态，避免滚动复用串图。
- `configure(...)` 根据 `ThumbnailState` 在 `Loading...`、成功图片、失败占位之间切换；`updateSelectionAppearance()` 统一维护边框和选中底色。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSGIFFrameImportViewController.swift
// 类型/函数: macOSGIFFrameImportCollectionItem.configure(...) / prepareForReuse() / updateSelectionAppearance()
// 功能说明: 修改后新增独立 collection item，负责缩略图显示、加载态/失败态、点击选中和复用时的 UI 清理。
private final class macOSGIFFrameImportCollectionItem: NSCollectionViewItem {
    private let imageViewContainer: NSImageView = {
        let imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyUpOrDown
        return imageView
    }()
    private let placeholderLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        return label
    }()
    private let progressIndicator: NSProgressIndicator = {
        let indicator = NSProgressIndicator()
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.style = .spinning
        indicator.isDisplayedWhenStopped = false
        return indicator
    }()
    private let selectionBadgeView: NSImageView = {
        let image = NSImage(
            systemSymbolName: "checkmark.circle.fill",
            accessibilityDescription: "Selected"
        )
        let imageView = NSImageView(image: image ?? NSImage())
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentTintColor = .controlAccentColor
        imageView.isHidden = true
        return imageView
    }()

    override func prepareForReuse() {
        super.prepareForReuse()
        imageViewContainer.image = nil
        placeholderLabel.stringValue = ""
        progressIndicator.stopAnimation(nil)
        isFrameSelected = false
    }

    func configure(
        frameIndex: Int,
        thumbnailState: macOSGIFFrameImportViewController.ThumbnailState,
        isSelected: Bool,
        onToggleSelection: @escaping (Int) -> Void,
        onPrepareForReuse: @escaping (Int) -> Void
    ) {
        frameLabel.stringValue = "Frame \(frameIndex + 1)"
        isFrameSelected = isSelected

        switch thumbnailState {
        case .idle, .loading:
            imageViewContainer.image = nil
            placeholderLabel.stringValue = "Loading..."
            placeholderLabel.isHidden = false
            progressIndicator.startAnimation(nil)
        case let .loaded(image):
            imageViewContainer.image = image
            placeholderLabel.stringValue = ""
            placeholderLabel.isHidden = true
            progressIndicator.stopAnimation(nil)
        case .failed:
            imageViewContainer.image = nil
            placeholderLabel.stringValue = "Unable to load"
            placeholderLabel.isHidden = false
            progressIndicator.stopAnimation(nil)
        }
    }

    private func updateSelectionAppearance() {
        view.layer?.borderColor = isFrameSelected
            ? NSColor.controlAccentColor.cgColor
            : NSColor.separatorColor.cgColor
        view.layer?.backgroundColor = isFrameSelected
            ? NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
            : NSColor.controlBackgroundColor.cgColor
        selectionBadgeView.isHidden = isFrameSelected == false
    }
}
```

## 验证情况

- 已执行 `ReadLints`：`MyCanvas_Ver_0/Platform/macOS/macOSGIFFrameImportViewController.swift`、`MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift` 均无 lints 报错。
- 已执行 `xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=macOS" build`：通过。
- 已执行 `xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=macOS" -only-testing:"MyCanvas_Ver_0Tests/CanvasGIFFrameImportBuilderTests" test`：通过。
