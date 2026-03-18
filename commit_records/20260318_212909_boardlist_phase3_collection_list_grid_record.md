# 20260318_212909_boardlist_phase3_collection_list_grid_record

## 记录范围

- 记录目标 1：把双端 `BoardList` 从“按钮占位页”升级成统一的 `collection` 容器。
- 记录目标 2：在不引入真实缩略图异步替换链路的前提下，先接上阶段 2 的几何预览 seed，支持展示“缩略图 + 名字”。
- 记录目标 3：支持同一套数据源下的 `grid/list` 两种显示模式，而不是分两套容器实现。
- 涉及文件：`MyCanvas_Ver_0/Platform/Shared/BoardList/BoardListDisplayMode.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/Shared/BoardList/BoardGeometryPreviewLayout.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardPreviewView.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardPreviewView.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift`
- 本记录不包含：阶段 1 的显式路由改造。
- 本记录不包含：阶段 2 的 catalog / geometry seed 链路。
- 本记录不包含：阶段 4/5 的后台真实缩略图替换。
- 本记录不包含：git commit。

## 修改一：补齐 `list/grid` 显示模式与几何预览布局映射的 shared 类型

### 修改前

- 项目里没有 `BoardList` 专用的共享显示模式类型。
- 项目里也没有“把 `BoardPreviewSeed` 映射成 preview view 可直接消费的 rect/path”的 shared 布局层。
- 这意味着一旦双端开始接 `collection`，显示模式状态、几何映射逻辑都会散落在各自平台控制器里。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardListDisplayMode.swift
// 函数名/类型名: BoardListDisplayMode
// 功能说明: 修改前文件不存在，BoardList 没有统一的 list/grid 显示模式定义。
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardGeometryPreviewLayout.swift
// 函数名/类型名: BoardGeometryPreviewLayout
// 功能说明: 修改前文件不存在，BoardPreviewSeed 还没有被转换成 preview view 可直接绘制的 boardRect / nodePaths。
```

### 修改后

- 新增 `BoardListDisplayMode`，统一承载：
- `segmentIndex`
- `title`
- 默认回退逻辑 `init(segmentIndex:)`
- 新增 `BoardGeometryPreviewLayout`，负责把 `BoardPreviewSeed` 转成：
- `boardRect`
- `nodePaths`
- 双端 preview view 不再自己直接依赖 `CanvasMiniMapViewGeometry` 做散射式转换。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardListDisplayMode.swift
// 函数名/类型名: BoardListDisplayMode
// 功能说明: 修改后 BoardList 用同一个 shared enum 管理 grid/list 两种显示模式与 segmented control 下标映射。
import Foundation

enum BoardListDisplayMode: Int {
    case grid
    case list

    init(segmentIndex: Int) {
        self = BoardListDisplayMode(rawValue: segmentIndex) ?? .grid
    }

    var segmentIndex: Int {
        rawValue
    }

    var title: String {
        switch self {
        case .grid:
            return "Grid"
        case .list:
            return "List"
        }
    }

    static let allCases: [BoardListDisplayMode] = [.grid, .list]
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardGeometryPreviewLayout.swift
// 函数名/类型名: BoardGeometryPreviewLayout.init(seed:viewBounds:contentInset:geometryPreviewBuilder:)
// 功能说明: 修改后 shared 布局层统一把几何预览 seed 映射成 preview view 可直接绘制的 boardRect 与 nodePaths。
import CoreGraphics
import Foundation

struct BoardGeometryPreviewLayout {
    let boardRect: CGRect?
    let nodePaths: [CGPath]

    init(
        seed: BoardPreviewSeed,
        viewBounds: CGRect,
        contentInset: CGFloat,
        geometryPreviewBuilder: BoardGeometryPreviewBuilder = BoardGeometryPreviewBuilder()
    ) {
        let snapshot = geometryPreviewBuilder.makeSnapshot(from: seed)
        guard
            let geometry = CanvasMiniMapViewGeometry(
                displayWorldRect: snapshot.displayWorldRect,
                viewBounds: viewBounds,
                contentInset: contentInset
            )
        else {
            boardRect = nil
            nodePaths = []
            return
        }

        let mappedBoardRect = geometry.worldToMiniMap(snapshot.boardWorldRect)
        if mappedBoardRect.width > 0, mappedBoardRect.height > 0 {
            boardRect = mappedBoardRect
        } else {
            boardRect = nil
        }

        nodePaths = snapshot.nodes.compactMap { node in
            let mappedQuad = geometry.worldToMiniMap(node.worldQuad)
            let mappedBounds = mappedQuad.boundingRect.standardized
            guard mappedBounds.width > 0, mappedBounds.height > 0 else {
                return nil
            }

            return mappedQuad.cgPath
        }
    }
}
```

## 修改二：新增双端几何预览 view 与 `collection` cell

### 修改前

- `BoardList` 页面没有 preview view，也没有 `collection` item / cell。
- 双端页面都只是“标题 + 说明 + 选择目录按钮 + 打开按钮 + 状态文字”的占位结构。
- 即使阶段 2 已经准备好了 `BoardPreviewSeed`，本阶段之前也没有地方把它绘制出来。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名/类型名: macOSBoardListViewController.setupViewHierarchy()
// 功能说明: 修改前 macOS BoardList 只有基础按钮和状态文本，没有 preview view 与 collection item 容器。
private func setupViewHierarchy() {
    view.wantsLayer = true
    view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    view.addSubview(titleLabel)
    view.addSubview(subtitleLabel)
    view.addSubview(selectFolderButton)
    view.addSubview(openCanvasButton)
    view.addSubview(bookmarkStatusLabel)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/类型名: iOSBoardListViewController.setupViewHierarchy()
// 功能说明: 修改前 iOS BoardList 同样只有按钮和状态文本，没有任何 board cell 展示层。
private func setupViewHierarchy() {
    view.backgroundColor = .systemBackground
    view.addSubview(titleLabel)
    view.addSubview(subtitleLabel)
    view.addSubview(selectFolderButton)
    view.addSubview(openCanvasButton)
    view.addSubview(bookmarkStatusLabel)
}
```

### 修改后

- `macOS` 新增 `macOSBoardPreviewView` 与 `macOSBoardCollectionItem`。
- `iOS` 新增 `iOSBoardPreviewView` 与 `iOSBoardCollectionViewCell`。
- preview view 的职责是：
- 读取 `BoardPreviewSeed`
- 使用 `BoardGeometryPreviewLayout`
- 绘制 board 边界和 node 占位
- cell 的职责是：
- 承载 preview view
- 显示 board 标题
- 根据 `BoardListDisplayMode` 在 `grid/list` 之间切换约束
- 响应选中态边框与背景样式

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardPreviewView.swift
// 函数名/类型名: macOSBoardPreviewView.apply(seed:) / refreshPreview()
// 功能说明: 修改后 macOS preview view 会把 BoardPreviewSeed 映射成 boardRect 与 nodePaths，并绘制成静态几何缩略图。
#if os(macOS)
import AppKit

final class macOSBoardPreviewView: NSView {
    private static let contentInset: CGFloat = 10
    private let boardLayer = CAShapeLayer()
    private let occupancyLayer = CAShapeLayer()
    private var seed: BoardPreviewSeed = .empty

    func apply(seed: BoardPreviewSeed) {
        self.seed = seed
        performWithoutLayerActions {
            refreshPreview()
        }
    }

    private func refreshPreview() {
        let layout = BoardGeometryPreviewLayout(
            seed: seed,
            viewBounds: bounds,
            contentInset: Self.contentInset
        )

        if let boardRect = layout.boardRect {
            boardLayer.path = CGPath(rect: boardRect, transform: nil)
            boardLayer.isHidden = false
        } else {
            boardLayer.path = nil
            boardLayer.isHidden = true
        }

        if layout.nodePaths.isEmpty {
            occupancyLayer.path = nil
            occupancyLayer.isHidden = true
            return
        }

        let path = CGMutablePath()
        for nodePath in layout.nodePaths {
            path.addPath(nodePath)
        }
        occupancyLayer.path = path
        occupancyLayer.isHidden = false
    }

    private func performWithoutLayerActions(_ updates: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updates()
        CATransaction.commit()
    }
}
#endif
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift
// 函数名/类型名: macOSBoardCollectionItem.configure(with:displayMode:) / applyDisplayMode(_:)
// 功能说明: 修改后 macOS collection item 统一承载预览图和标题，并根据显示模式在 grid/list 两套约束间切换。
#if os(macOS)
import AppKit

final class macOSBoardCollectionItem: NSCollectionViewItem {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("macOSBoardCollectionItem")

    private let previewView = macOSBoardPreviewView()
    private let titleLabel: NSTextField = {
        let label = NSTextField(wrappingLabelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .labelColor
        label.maximumNumberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
        return label
    }()

    private var gridConstraints: [NSLayoutConstraint] = []
    private var listConstraints: [NSLayoutConstraint] = []

    func configure(
        with item: BoardCatalogItem,
        displayMode: BoardListDisplayMode
    ) {
        titleLabel.stringValue = item.title
        previewView.apply(seed: item.previewSeed)
        applyDisplayMode(displayMode)
    }

    private func applyDisplayMode(_ displayMode: BoardListDisplayMode) {
        NSLayoutConstraint.deactivate(gridConstraints + listConstraints)

        switch displayMode {
        case .grid:
            titleLabel.alignment = .center
            NSLayoutConstraint.activate(gridConstraints)
        case .list:
            titleLabel.alignment = .left
            NSLayoutConstraint.activate(listConstraints)
        }
    }
}
#endif
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardPreviewView.swift
// 函数名/类型名: iOSBoardPreviewView.apply(seed:) / refreshPreview()
// 功能说明: 修改后 iOS preview view 与 macOS 共用同一套几何布局输入，只保留平台层绘制与外观差异。
#if os(iOS)
import UIKit

final class iOSBoardPreviewView: UIView {
    private static let contentInset: CGFloat = 10
    private let boardLayer = CAShapeLayer()
    private let occupancyLayer = CAShapeLayer()
    private var seed: BoardPreviewSeed = .empty

    func apply(seed: BoardPreviewSeed) {
        self.seed = seed
        performWithoutLayerActions {
            refreshPreview()
        }
    }

    private func refreshPreview() {
        let layout = BoardGeometryPreviewLayout(
            seed: seed,
            viewBounds: bounds,
            contentInset: Self.contentInset
        )

        if let boardRect = layout.boardRect {
            boardLayer.path = CGPath(rect: boardRect, transform: nil)
            boardLayer.isHidden = false
        } else {
            boardLayer.path = nil
            boardLayer.isHidden = true
        }

        if layout.nodePaths.isEmpty {
            occupancyLayer.path = nil
            occupancyLayer.isHidden = true
            return
        }

        let path = CGMutablePath()
        for nodePath in layout.nodePaths {
            path.addPath(nodePath)
        }
        occupancyLayer.path = path
        occupancyLayer.isHidden = false
    }

    private func performWithoutLayerActions(_ updates: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updates()
        CATransaction.commit()
    }
}
#endif
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift
// 函数名/类型名: iOSBoardCollectionViewCell.configure(with:displayMode:) / applyDisplayMode(_:)
// 功能说明: 修改后 iOS cell 会在一个 UICollectionViewCell 内承载预览图和标题，并统一支持 grid/list 两种布局。
#if os(iOS)
import UIKit

final class iOSBoardCollectionViewCell: UICollectionViewCell {
    static let reuseIdentifier = "iOSBoardCollectionViewCell"

    private let previewView = iOSBoardPreviewView()
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .label
        label.numberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
        return label
    }()

    private var gridConstraints: [NSLayoutConstraint] = []
    private var listConstraints: [NSLayoutConstraint] = []

    func configure(
        with item: BoardCatalogItem,
        displayMode: BoardListDisplayMode
    ) {
        titleLabel.text = item.title
        previewView.apply(seed: item.previewSeed)
        applyDisplayMode(displayMode)
    }

    private func applyDisplayMode(_ displayMode: BoardListDisplayMode) {
        NSLayoutConstraint.deactivate(gridConstraints + listConstraints)

        switch displayMode {
        case .grid:
            titleLabel.textAlignment = .center
            NSLayoutConstraint.activate(gridConstraints)
        case .list:
            titleLabel.textAlignment = .left
            NSLayoutConstraint.activate(listConstraints)
        }
    }
}
#endif
```

## 修改三：双端 `BoardList` controller 从“打开最新画板”过渡页重构为 `collection + list/grid`

### 修改前

- 双端 controller 都只有：
- `selectFolderButton`
- `openCanvasButton`
- `bookmarkStatusLabel`
- 点击打开时，逻辑是“如果有板子就打开最新板，否则新建板”。
- 这是一套阶段 2 的过渡逻辑，并不具备：
- board 选择
- `grid/list` 切换
- collection 复用容器
- 空态视图

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名/类型名: macOSBoardListViewController.refreshBookmarkStatus() / updateOpenCanvasButtonState(hasSelectedFolder:) / handleOpenCanvasButtonClick()
// 功能说明: 修改前 macOS controller 仍然停留在“读 catalog -> 显示数量 -> 打开最新 board”的过渡阶段。
private func refreshBookmarkStatus() {
    let bookmarkText = FolderBookmarkStore.statusText()
    do {
        let boards = try catalogLoader.loadCatalog()
        availableBoards = boards
        bookmarkStatusLabel.stringValue = "\(bookmarkText)\n\nBoards available: \(boards.count)"
        updateOpenCanvasButtonState(hasSelectedFolder: true)
    } catch FolderBookmarkStoreError.missingBookmarkData {
        availableBoards = []
        bookmarkStatusLabel.stringValue = bookmarkText
        updateOpenCanvasButtonState(hasSelectedFolder: false)
    } catch {
        availableBoards = []
        bookmarkStatusLabel.stringValue = "\(bookmarkText)\n\nStorage error: \(error.localizedDescription)"
        updateOpenCanvasButtonState(hasSelectedFolder: false)
    }
}

private func updateOpenCanvasButtonState(hasSelectedFolder: Bool) {
    guard hasSelectedFolder else {
        openCanvasButton.title = "Select Folder First"
        openCanvasButton.isEnabled = false
        return
    }

    openCanvasButton.title = availableBoards.isEmpty
        ? "Create Board"
        : "Open Latest Board"
    openCanvasButton.isEnabled = true
}

@objc
private func handleOpenCanvasButtonClick() {
    guard FolderBookmarkStore.hasStoredBookmarkData() else {
        return
    }

    if let latestBoard = availableBoards.first {
        onOpenBoard?(latestBoard.boardID)
    } else {
        onCreateBoard?()
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/类型名: iOSBoardListViewController.refreshBookmarkStatus() / updateOpenCanvasButtonState(hasSelectedFolder:) / handleOpenCanvasButtonTap()
// 功能说明: 修改前 iOS controller 也只支持“Create Board / Open Latest Board”这条单按钮过渡链路。
private func refreshBookmarkStatus() {
    let bookmarkText = FolderBookmarkStore.statusText()
    do {
        let boards = try catalogLoader.loadCatalog()
        availableBoards = boards
        bookmarkStatusLabel.text = "\(bookmarkText)\n\nBoards available: \(boards.count)"
        updateOpenCanvasButtonState(hasSelectedFolder: true)
    } catch FolderBookmarkStoreError.missingBookmarkData {
        availableBoards = []
        bookmarkStatusLabel.text = bookmarkText
        updateOpenCanvasButtonState(hasSelectedFolder: false)
    } catch {
        availableBoards = []
        bookmarkStatusLabel.text = "\(bookmarkText)\n\nStorage error: \(error.localizedDescription)"
        updateOpenCanvasButtonState(hasSelectedFolder: false)
    }
}

private func updateOpenCanvasButtonState(hasSelectedFolder: Bool) {
    var configuration = openCanvasButton.configuration ?? UIButton.Configuration.tinted()
    if hasSelectedFolder {
        configuration.title = availableBoards.isEmpty
            ? "Create Board"
            : "Open Latest Board"
        openCanvasButton.isEnabled = true
    } else {
        configuration.title = "Select Folder First"
        openCanvasButton.isEnabled = false
    }
    openCanvasButton.configuration = configuration
}

@objc
private func handleOpenCanvasButtonTap() {
    guard FolderBookmarkStore.hasStoredBookmarkData() else {
        return
    }

    if let latestBoard = availableBoards.first {
        onOpenBoard?(latestBoard.boardID)
    } else {
        onCreateBoard?()
    }
}
```

### 修改后

- 双端 controller 都新增了：
- `displayMode`
- `selectedBoardID`
- `hasSelectedFolder`
- `collectionView`
- `emptyStateLabel`
- `reloadBoardList()`
- `syncCollectionSelection()`
- `openSelectedBoardIfNeeded()`
- `openCanvasButton` 的语义从“Open Latest Board”改成“Open Board”。
- 当目录里存在 board 时，controller 会：
- 默认选中第一个 board
- 允许用户在 collection 中切换选中项
- 用同一个 collection 在 `grid/list` 间切换布局
- `macOS` 额外支持 `doubleAction` 双击打开。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名/类型名: macOSBoardListViewController.displayMode / setupViewHierarchy() / reloadBoardList() / handleOpenCanvasButtonClick()
// 功能说明: 修改后 macOS controller 用一套 NSCollectionView 容器承接列表与网格，并从“打开最新板”切换为“打开当前选中板”。
final class macOSBoardListViewController: NSViewController, NSCollectionViewDataSource, NSCollectionViewDelegate {
    private enum Layout {
        static let listItemHeight: CGFloat = 96
        static let gridItemHeight: CGFloat = 184
        static let minimumGridItemWidth: CGFloat = 220
        static let sectionHorizontalInset: CGFloat = 24
        static let sectionBottomInset: CGFloat = 24
        static let sectionTopInset: CGFloat = 0
        static let itemSpacing: CGFloat = 16
    }

    private var selectedBoardID: UUID?
    private var hasSelectedFolder = false
    private var displayMode: BoardListDisplayMode = .grid {
        didSet {
            guard oldValue != displayMode else {
                return
            }

            updateCollectionLayout()
            collectionView.reloadData()
            syncCollectionSelection()
        }
    }

    private lazy var displayModeControl: NSSegmentedControl = {
        let control = NSSegmentedControl(
            labels: BoardListDisplayMode.allCases.map(\.title),
            trackingMode: .selectOne,
            target: nil,
            action: nil
        )
        control.translatesAutoresizingMaskIntoConstraints = false
        control.selectedSegment = displayMode.segmentIndex
        control.isEnabled = false
        return control
    }()

    private let collectionViewLayout = NSCollectionViewFlowLayout()

    private lazy var collectionView: NSCollectionView = {
        let collectionView = NSCollectionView()
        collectionView.backgroundColors = [.clear]
        collectionView.collectionViewLayout = collectionViewLayout
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.isSelectable = true
        collectionView.register(
            macOSBoardCollectionItem.self,
            forItemWithIdentifier: macOSBoardCollectionItem.reuseIdentifier
        )
        collectionView.target = self
        collectionView.doubleAction = #selector(handleCollectionViewDoubleClick)
        return collectionView
    }()

    private func setupViewHierarchy() {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        actionStackView.addArrangedSubview(selectFolderButton)
        actionStackView.addArrangedSubview(displayModeControl)
        actionStackView.addArrangedSubview(openCanvasButton)

        view.addSubview(titleLabel)
        view.addSubview(subtitleLabel)
        view.addSubview(actionStackView)
        view.addSubview(bookmarkStatusLabel)
        view.addSubview(collectionScrollView)
        view.addSubview(emptyStateLabel)
    }

    private func reloadBoardList() {
        collectionView.reloadData()
        updateCollectionVisibility()
        updateDisplayModeControlState()
        updateOpenCanvasButtonState()
        updateCollectionLayout()
        syncCollectionSelection()
    }

    @objc
    private func handleOpenCanvasButtonClick() {
        guard FolderBookmarkStore.hasStoredBookmarkData() else {
            return
        }

        if availableBoards.isEmpty {
            onCreateBoard?()
        } else {
            openSelectedBoardIfNeeded()
        }
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/类型名: iOSBoardListViewController.displayMode / setupViewHierarchy() / reloadBoardList() / handleOpenCanvasButtonTap()
// 功能说明: 修改后 iOS controller 也改成统一的 UICollectionView 容器，显示模式切换与选中逻辑与 macOS 共享同一套行为模型。
final class iOSBoardListViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    private enum Layout {
        static let listItemHeight: CGFloat = 96
        static let gridItemHeight: CGFloat = 184
        static let minimumGridItemWidth: CGFloat = 176
        static let sectionInset = UIEdgeInsets(top: 0, left: 24, bottom: 24, right: 24)
        static let itemSpacing: CGFloat = 16
    }

    private var selectedBoardID: UUID?
    private var hasSelectedFolder = false
    private var displayMode: BoardListDisplayMode = .grid {
        didSet {
            guard oldValue != displayMode else {
                return
            }

            updateCollectionLayout()
            collectionView.reloadData()
            syncCollectionSelection()
        }
    }

    private lazy var displayModeControl: UISegmentedControl = {
        let control = UISegmentedControl(items: BoardListDisplayMode.allCases.map(\.title))
        control.translatesAutoresizingMaskIntoConstraints = false
        control.selectedSegmentIndex = displayMode.segmentIndex
        control.isEnabled = false
        return control
    }()

    private let collectionViewLayout = UICollectionViewFlowLayout()

    private lazy var collectionView: UICollectionView = {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: collectionViewLayout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.allowsSelection = true
        collectionView.register(
            iOSBoardCollectionViewCell.self,
            forCellWithReuseIdentifier: iOSBoardCollectionViewCell.reuseIdentifier
        )
        return collectionView
    }()

    private func setupViewHierarchy() {
        view.backgroundColor = .systemBackground

        actionStackView.addArrangedSubview(selectFolderButton)
        actionStackView.addArrangedSubview(displayModeControl)
        actionStackView.addArrangedSubview(openCanvasButton)

        view.addSubview(titleLabel)
        view.addSubview(subtitleLabel)
        view.addSubview(actionStackView)
        view.addSubview(bookmarkStatusLabel)
        view.addSubview(collectionView)
        view.addSubview(emptyStateLabel)
    }

    private func reloadBoardList() {
        collectionView.reloadData()
        updateCollectionVisibility()
        updateDisplayModeControlState()
        updateOpenCanvasButtonState()
        updateCollectionLayout()
        syncCollectionSelection()
    }

    @objc
    private func handleOpenCanvasButtonTap() {
        guard FolderBookmarkStore.hasStoredBookmarkData() else {
            return
        }

        if availableBoards.isEmpty {
            onCreateBoard?()
        } else {
            openSelectedBoardIfNeeded()
        }
    }
}
```

## 验证情况

- 已检查阶段 3 相关文件的 IDE lints。
- 本轮结果：`No linter errors found`。
- 本记录未执行 git commit。
- 本记录未执行完整 Xcode build。
