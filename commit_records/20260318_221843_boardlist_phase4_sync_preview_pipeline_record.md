# 20260318_221843_boardlist_phase4_sync_preview_pipeline_record

## 记录范围

- 记录目标 1：把 `BoardList` 首屏预览从“cell 直接吃 `previewSeed`”收口成 shared 的同步 preview pipeline。
- 记录目标 2：为阶段 5 的真实缩略图异步替换预留统一的 `previewContent` / `previewProvider` / `renderer` 边界。
- 记录目标 3：保持阶段 4 仍然只走同步几何预览，不提前引入真实缩略图后台任务。
- 涉及文件：`MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewContent.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewRenderer.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardPreviewView.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardPreviewView.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift`
- 本记录不包含：阶段 3 的 `collection/list/grid` 容器初次落地。
- 本记录不包含：阶段 5 的真实缩略图后台渲染、缓存、取消与回填。
- 本记录不包含：git commit。

## 修改一：新增 shared 预览内容、provider 与 renderer，把同步几何预览收口成统一入口

### 修改前

- 项目里没有 `BoardPreviewContent`，预览内容类型没有统一抽象。
- 项目里没有 `BoardPreviewProvider`，controller 也没有“同步拿首屏预览”的明确入口。
- 项目里没有 `BoardPreviewRenderer`，几何预览绘制逻辑散落在双端 preview view 内部。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewContent.swift
// 函数名/类型名: BoardPreviewContent
// 功能说明: 修改前文件不存在，BoardList 还没有统一的预览内容抽象。
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift
// 函数名/类型名: BoardPreviewProvider
// 功能说明: 修改前文件不存在，controller 还没有统一的同步预览提供者。
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewRenderer.swift
// 函数名/类型名: BoardPreviewRenderer
// 功能说明: 修改前文件不存在，几何预览的 layer 渲染逻辑还没有被收口到 shared 层。
```

### 修改后

- 新增 `BoardPreviewContent`，统一表达：
- `.empty`
- `.geometry(BoardPreviewSeed)`
- `.thumbnail(CGImage)`，先预留给阶段 5
- 新增 `BoardPreviewProvider`，阶段 4 只实现同步接口 `immediatePreview(for:)`，永远秒回几何预览。
- 新增 `BoardPreviewRenderer`，统一处理：
- `empty`
- `geometry`
- 未来 `thumbnail`

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewContent.swift
// 函数名/类型名: BoardPreviewContent
// 功能说明: 修改后 preview content 统一承载 empty、geometry 和未来 thumbnail 三种预览内容形态。
import CoreGraphics
import Foundation

enum BoardPreviewContent {
    case empty
    case geometry(BoardPreviewSeed)
    case thumbnail(CGImage)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift
// 函数名/类型名: BoardPreviewProvider.immediatePreview(for:)
// 功能说明: 修改后 controller 通过统一 provider 获取首屏同步预览，阶段 4 默认直接返回 geometry。
import Foundation

struct BoardPreviewProvider {
    func immediatePreview(for item: BoardCatalogItem) -> BoardPreviewContent {
        .geometry(item.previewSeed)
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewRenderer.swift
// 函数名/类型名: BoardPreviewRenderer.render(content:viewBounds:contentInset:imageLayer:boardLayer:occupancyLayer:)
// 功能说明: 修改后 shared renderer 统一负责根据 preview content 驱动 imageLayer、boardLayer 和 occupancyLayer 的显示。
import CoreGraphics
import Foundation
import QuartzCore

enum BoardPreviewRenderer {
    static func render(
        content: BoardPreviewContent,
        viewBounds: CGRect,
        contentInset: CGFloat,
        imageLayer: CALayer,
        boardLayer: CAShapeLayer,
        occupancyLayer: CAShapeLayer
    ) {
        let roundedBounds = viewBounds.integral
        imageLayer.frame = roundedBounds
        boardLayer.frame = roundedBounds
        occupancyLayer.frame = roundedBounds

        switch content {
        case .empty:
            imageLayer.contents = nil
            imageLayer.isHidden = true
            boardLayer.path = nil
            boardLayer.isHidden = true
            occupancyLayer.path = nil
            occupancyLayer.isHidden = true

        case let .geometry(seed):
            imageLayer.contents = nil
            imageLayer.isHidden = true

            let layout = BoardGeometryPreviewLayout(
                seed: seed,
                viewBounds: roundedBounds,
                contentInset: contentInset
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

        case let .thumbnail(image):
            imageLayer.contents = image
            imageLayer.isHidden = false
            boardLayer.path = nil
            boardLayer.isHidden = true
            occupancyLayer.path = nil
            occupancyLayer.isHidden = true
        }
    }
}
```

## 修改二：双端 preview view 从直接吃 `BoardPreviewSeed`，改成消费统一的 `BoardPreviewContent`

### 修改前

- `macOSBoardPreviewView` / `iOSBoardPreviewView` 都直接持有 `BoardPreviewSeed`。
- preview view 自己负责：
- 调 `BoardGeometryPreviewLayout`
- 拼 path
- 更新 board / occupancy layer
- 这意味着一旦阶段 5 要引入真实缩略图，preview view 还得改接口和内部逻辑。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardPreviewView.swift
// 函数名/类型名: macOSBoardPreviewView.seed / apply(seed:) / refreshPreview()
// 功能说明: 修改前 macOS preview view 直接依赖 BoardPreviewSeed，并在 view 内部手工完成几何预览的全部绘制过程。
private let backgroundLayer = CALayer()
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
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardPreviewView.swift
// 函数名/类型名: iOSBoardPreviewView.seed / apply(seed:) / refreshPreview()
// 功能说明: 修改前 iOS preview view 同样直接吃 BoardPreviewSeed，内部没有预留 thumbnail 这种预览内容的扩展位。
private let backgroundLayer = CALayer()
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
    // ... geometry path rendering ...
}
```

### 修改后

- 双端 preview view 都改成持有 `BoardPreviewContent`。
- 新增 `imageLayer`，为阶段 5 的真实缩略图渲染预留同一个 view 层级。
- `refreshPreview()` 不再自己展开几何绘制细节，而是统一委托给 `BoardPreviewRenderer.render(...)`。
- 阶段 4 里虽然还没有真实缩略图，但 preview view 的输入模型和渲染边界已经稳定下来了。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardPreviewView.swift
// 函数名/类型名: macOSBoardPreviewView.content / apply(content:) / refreshPreview()
// 功能说明: 修改后 macOS preview view 统一消费 BoardPreviewContent，并把具体渲染逻辑委托给 shared renderer。
#if os(macOS)
import AppKit

final class macOSBoardPreviewView: NSView {
    private static let contentInset: CGFloat = 10
    private static let cornerRadius: CGFloat = 10
    private static let borderWidth: CGFloat = 1
    private static let boardLineWidth: CGFloat = 1.5

    private let backgroundLayer = CALayer()
    private let imageLayer = CALayer()
    private let boardLayer = CAShapeLayer()
    private let occupancyLayer = CAShapeLayer()
    private var content: BoardPreviewContent = .empty

    func apply(content: BoardPreviewContent) {
        self.content = content
        performWithoutLayerActions {
            refreshPreview()
        }
    }

    private func refreshPreview() {
        BoardPreviewRenderer.render(
            content: content,
            viewBounds: bounds,
            contentInset: Self.contentInset,
            imageLayer: imageLayer,
            boardLayer: boardLayer,
            occupancyLayer: occupancyLayer
        )
    }
}
#endif
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardPreviewView.swift
// 函数名/类型名: iOSBoardPreviewView.content / apply(content:) / refreshPreview()
// 功能说明: 修改后 iOS preview view 和 macOS 使用同一个 preview content 协议，只保留平台层的 layer 装配差异。
#if os(iOS)
import UIKit

final class iOSBoardPreviewView: UIView {
    private static let contentInset: CGFloat = 10
    private static let cornerRadius: CGFloat = 10
    private static let borderWidth: CGFloat = 1
    private static let boardLineWidth: CGFloat = 1.5

    private let backgroundLayer = CALayer()
    private let imageLayer = CALayer()
    private let boardLayer = CAShapeLayer()
    private let occupancyLayer = CAShapeLayer()
    private var content: BoardPreviewContent = .empty

    func apply(content: BoardPreviewContent) {
        self.content = content
        performWithoutLayerActions {
            refreshPreview()
        }
    }

    private func refreshPreview() {
        BoardPreviewRenderer.render(
            content: content,
            viewBounds: bounds,
            contentInset: Self.contentInset,
            imageLayer: imageLayer,
            boardLayer: boardLayer,
            occupancyLayer: occupancyLayer
        )
    }
}
#endif
```

## 修改三：cell 与 controller 接入 `previewProvider`，让 controller 成为同步预览链入口

### 修改前

- cell 直接从 `BoardCatalogItem.previewSeed` 取预览数据。
- controller 只负责拿目录项并把它交给 cell，没有显式参与 preview pipeline。
- 这样一来，后续如果要接入异步 thumbnail，cell 就会被迫承担更多数据源职责。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift
// 函数名/类型名: macOSBoardCollectionItem.configure(with:displayMode:)
// 功能说明: 修改前 macOS cell 直接使用 item.previewSeed，cell 既知道目录项，也直接知道几何预览来源。
func configure(
    with item: BoardCatalogItem,
    displayMode: BoardListDisplayMode
) {
    titleLabel.stringValue = item.title
    previewView.apply(seed: item.previewSeed)
    applyDisplayMode(displayMode)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift
// 函数名/类型名: iOSBoardCollectionViewCell.prepareForReuse() / configure(with:displayMode:)
// 功能说明: 修改前 iOS cell 也直接清空和绑定 BoardPreviewSeed，而不是统一的 preview content。
override func prepareForReuse() {
    super.prepareForReuse()
    titleLabel.text = nil
    previewView.apply(seed: .empty)
}

func configure(
    with item: BoardCatalogItem,
    displayMode: BoardListDisplayMode
) {
    titleLabel.text = item.title
    previewView.apply(seed: item.previewSeed)
    applyDisplayMode(displayMode)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名/类型名: macOSBoardListViewController.collectionView(_:itemForRepresentedObjectAt:)
// 功能说明: 修改前 macOS controller 只是把 BoardCatalogItem 原样交给 cell，没有显式 preview provider 层。
func collectionView(
    _ collectionView: NSCollectionView,
    itemForRepresentedObjectAt indexPath: IndexPath
) -> NSCollectionViewItem {
    guard
        let item = collectionView.makeItem(
            withIdentifier: macOSBoardCollectionItem.reuseIdentifier,
            for: indexPath
        ) as? macOSBoardCollectionItem
    else {
        return NSCollectionViewItem()
    }

    item.configure(with: availableBoards[indexPath.item], displayMode: displayMode)
    return item
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/类型名: iOSBoardListViewController.collectionView(_:cellForItemAt:)
// 功能说明: 修改前 iOS controller 同样不参与 preview pipeline，只负责把 BoardCatalogItem 交给 cell。
func collectionView(
    _ collectionView: UICollectionView,
    cellForItemAt indexPath: IndexPath
) -> UICollectionViewCell {
    guard
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: iOSBoardCollectionViewCell.reuseIdentifier,
            for: indexPath
        ) as? iOSBoardCollectionViewCell
    else {
        return UICollectionViewCell()
    }

    cell.configure(with: availableBoards[indexPath.item], displayMode: displayMode)
    return cell
}
```

### 修改后

- cell 改成只接收 `previewContent`，不再自己决定预览来源。
- `prepareForReuse()` 也改为清空 `.empty` 预览内容。
- 双端 controller 新增 `previewProvider` 属性。
- controller 在绑定 cell 时先取 `catalogItem`，再取 `previewProvider.immediatePreview(for:)`，最后一起交给 cell。
- 至此，阶段 4 的同步预览链是：
- `BoardCatalogItem`
- `BoardPreviewProvider.immediatePreview(for:)`
- `BoardPreviewContent`
- `BoardPreviewView`

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift
// 函数名/类型名: macOSBoardCollectionItem.prepareForReuse() / configure(with:previewContent:displayMode:)
// 功能说明: 修改后 macOS cell 只消费 preview content，预览来源被上移到 controller/provider。
override func prepareForReuse() {
    super.prepareForReuse()
    titleLabel.stringValue = ""
    previewView.apply(content: .empty)
}

func configure(
    with item: BoardCatalogItem,
    previewContent: BoardPreviewContent,
    displayMode: BoardListDisplayMode
) {
    titleLabel.stringValue = item.title
    previewView.apply(content: previewContent)
    applyDisplayMode(displayMode)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift
// 函数名/类型名: iOSBoardCollectionViewCell.prepareForReuse() / configure(with:previewContent:displayMode:)
// 功能说明: 修改后 iOS cell 也只接收统一的 preview content，为后续异步 thumbnail 回填保留稳定接口。
override func prepareForReuse() {
    super.prepareForReuse()
    titleLabel.text = nil
    previewView.apply(content: .empty)
}

func configure(
    with item: BoardCatalogItem,
    previewContent: BoardPreviewContent,
    displayMode: BoardListDisplayMode
) {
    titleLabel.text = item.title
    previewView.apply(content: previewContent)
    applyDisplayMode(displayMode)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名/类型名: macOSBoardListViewController.previewProvider / collectionView(_:itemForRepresentedObjectAt:)
// 功能说明: 修改后 macOS controller 显式调用 preview provider 获取同步 geometry 预览，再把 preview content 交给 cell。
private let previewProvider = BoardPreviewProvider()

func collectionView(
    _ collectionView: NSCollectionView,
    itemForRepresentedObjectAt indexPath: IndexPath
) -> NSCollectionViewItem {
    let catalogItem = availableBoards[indexPath.item]
    let previewContent = previewProvider.immediatePreview(for: catalogItem)
    guard
        let item = collectionView.makeItem(
            withIdentifier: macOSBoardCollectionItem.reuseIdentifier,
            for: indexPath
        ) as? macOSBoardCollectionItem
    else {
        return NSCollectionViewItem()
    }

    item.configure(
        with: catalogItem,
        previewContent: previewContent,
        displayMode: displayMode
    )
    return item
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/类型名: iOSBoardListViewController.previewProvider / collectionView(_:cellForItemAt:)
// 功能说明: 修改后 iOS controller 与 macOS 共享同一条同步 preview pipeline，只是在平台容器和 cell 控件上不同。
private let previewProvider = BoardPreviewProvider()

func collectionView(
    _ collectionView: UICollectionView,
    cellForItemAt indexPath: IndexPath
) -> UICollectionViewCell {
    let catalogItem = availableBoards[indexPath.item]
    let previewContent = previewProvider.immediatePreview(for: catalogItem)
    guard
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: iOSBoardCollectionViewCell.reuseIdentifier,
            for: indexPath
        ) as? iOSBoardCollectionViewCell
    else {
        return UICollectionViewCell()
    }

    cell.configure(
        with: catalogItem,
        previewContent: previewContent,
        displayMode: displayMode
    )
    return cell
}
```

## 验证情况

- 已检查阶段 4 相关文件的 IDE lints。
- 本轮结果：`No linter errors found`。
- 本记录未执行 git commit。
- 本记录未执行完整 Xcode build。
