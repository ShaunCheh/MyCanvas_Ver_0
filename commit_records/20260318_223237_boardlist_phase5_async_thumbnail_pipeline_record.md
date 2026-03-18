# 20260318_223237_boardlist_phase5_async_thumbnail_pipeline_record

## 记录范围

- 记录目标 1：在阶段 4 的同步几何预览基础上，补齐阶段 5 的后台真实缩略图渲染链。
- 记录目标 2：让 `BoardList` 支持“首屏 geometry、后台 thumbnail、命中缓存直接回显”的混合预览流程。
- 记录目标 3：补上 cell 复用取消、回填校验、按显示模式计算目标像素尺寸，避免串图和无效渲染。
- 记录目标 4：修正真实缩略图接入后的 preview layer 叠放顺序，避免 board fill 覆盖缩略图。
- 涉及文件：`MyCanvas_Ver_0/Platform/Shared/BoardList/BoardCatalogItem.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/Shared/BoardList/BoardCatalogLoader.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewContent.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewRenderer.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewRequestToken.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailCache.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardPreviewView.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardPreviewView.swift`
- 本记录不包含：阶段 6 的持久化 `thumbnail.png`。
- 本记录不包含：git commit。

## 修改一：给 catalog 补齐资产目录输入，解决真实缩略图渲染拿不到资产路径的问题

### 修改前

- `BoardCatalogItem` 只有 `document` 和 `previewSeed`。
- `BoardCatalogLoader.loadCatalog()` 只把文档和几何 seed 装进 catalog item。
- 阶段 4 的同步几何预览够用，但阶段 5 需要读取 `assets/*.png` 做真实缩略图时，shared 层没有资产目录输入。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardCatalogItem.swift
// 函数名/类型名: BoardCatalogItem
// 功能说明: 修改前 catalog item 只保存文档和 geometry preview seed，真实缩略图渲染拿不到 assets 目录。
import Foundation

struct BoardCatalogItem {
    let document: BoardDocument
    let previewSeed: BoardPreviewSeed

    var boardID: UUID {
        document.boardID
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardCatalogLoader.swift
// 函数名/类型名: BoardCatalogLoader.loadCatalog()
// 功能说明: 修改前 catalog loader 只映射 document 和 previewSeed，还没有把 entry.assetsDirectoryURL 带进 shared 模型。
import Foundation

struct BoardCatalogLoader {
    func loadCatalog() throws -> [BoardCatalogItem] {
        try BoardStore.listBoardDocumentEntries(userDefaults: userDefaults).map { entry in
            BoardCatalogItem(
                document: entry.document,
                previewSeed: geometryPreviewBuilder.makeSeed(from: entry.document)
            )
        }
    }
}
```

### 修改后

- `BoardCatalogItem` 新增 `assetsDirectoryURL`。
- `BoardCatalogLoader.loadCatalog()` 把 `entry.assetsDirectoryURL` 一并带入，后续 renderer / provider 不再需要重复推导目录。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardCatalogItem.swift
// 函数名/类型名: BoardCatalogItem
// 功能说明: 修改后 catalog item 同时携带 board 文档、assets 目录和 geometry preview seed，供异步缩略图管线直接消费。
import Foundation

struct BoardCatalogItem {
    let document: BoardDocument
    let assetsDirectoryURL: URL
    let previewSeed: BoardPreviewSeed

    var boardID: UUID {
        document.boardID
    }

    var revisionToken: String {
        "\(boardID.uuidString)-\(updatedAt.timeIntervalSince1970)"
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardCatalogLoader.swift
// 函数名/类型名: BoardCatalogLoader.loadCatalog()
// 功能说明: 修改后 loader 直接把 entry.assetsDirectoryURL 注入 catalog item，缩略图 renderer 可以无缝读取 board 资产文件。
import Foundation

struct BoardCatalogLoader {
    func loadCatalog() throws -> [BoardCatalogItem] {
        try BoardStore.listBoardDocumentEntries(userDefaults: userDefaults).map { entry in
            BoardCatalogItem(
                document: entry.document,
                assetsDirectoryURL: entry.assetsDirectoryURL,
                previewSeed: geometryPreviewBuilder.makeSeed(from: entry.document)
            )
        }
    }
}
```

## 修改二：shared 层新增真实缩略图异步管线，并把同步 geometry provider 扩成“缓存 + 异步回填”入口

### 修改前

- `BoardPreviewContent` 只有 `.thumbnail(CGImage)` 这种预留类型，没有携带 `BoardPreviewSeed`，真实图一旦显示，board rect 无法继续复用。
- `BoardPreviewProvider` 只有同步接口 `immediatePreview(for:)`，永远返回 `.geometry(item.previewSeed)`。
- 项目里不存在：
- `BoardPreviewRequestToken`
- `BoardThumbnailCache`
- `BoardThumbnailRenderer`
- 也不存在“后台渲染、取消、缓存命中回调”的 shared 边界。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewContent.swift
// 函数名/类型名: BoardPreviewContent
// 功能说明: 修改前 thumbnail 只携带 CGImage，本身不保留 boardRect 所需的 preview seed。
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
// 功能说明: 修改前 provider 只有同步 geometry 入口，没有缓存、没有异步请求、没有取消能力。
import Foundation

struct BoardPreviewProvider {
    func immediatePreview(for item: BoardCatalogItem) -> BoardPreviewContent {
        .geometry(item.previewSeed)
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewRequestToken.swift
// 函数名/类型名: BoardPreviewRequestToken
// 功能说明: 修改前文件不存在，cell 复用时没有统一的异步预览取消令牌。
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailCache.swift
// 函数名/类型名: BoardThumbnailCache / BoardThumbnailCacheKey
// 功能说明: 修改前文件不存在，shared 层还没有基于 board revision 与目标像素尺寸的内存缩略图缓存。
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift
// 函数名/类型名: BoardThumbnailRenderer.renderThumbnail(for:targetPixelSize:contentInset:cancellationCheck:)
// 功能说明: 修改前文件不存在，shared 层还没有把 board 文档和资产离屏渲染成真实缩略图的能力。
```

### 修改后

- `BoardPreviewContent.thumbnail` 扩成 `.thumbnail(CGImage, BoardPreviewSeed)`，真实图回填后仍能继续使用 board seed。
- `BoardPreviewContent` 新增 `isThumbnail`，让 controller / cell 判断是否还需要继续请求后台图更直接。
- 新增 `BoardPreviewRequestToken`，统一封装取消状态与取消回调。
- 新增 `BoardThumbnailCacheKey` / `BoardThumbnailCache`，缓存 key 由 `boardID + revisionToken + 目标像素尺寸` 组成，避免旧 revision 误命中。
- 新增 `BoardThumbnailRenderer`，按 `document.items + assetsDirectoryURL + CanvasMiniMapViewGeometry` 离屏绘制真实缩略图。
- `BoardPreviewProvider` 从同步 struct 扩成 final class，内部持有：
- `thumbnailCache`
- `thumbnailRenderer`
- `renderQueue`
- `callbackQueue`
- 新增 `requestThumbnail(for:targetPixelSize:completion:)`，统一做缓存命中、后台渲染、取消检查、主线程回填。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewContent.swift
// 函数名/类型名: BoardPreviewContent / BoardPreviewContent.isThumbnail
// 功能说明: 修改后 thumbnail 预览既携带真实图，也携带 preview seed，回填后还能继续绘制 board 边界。
import CoreGraphics
import Foundation

enum BoardPreviewContent {
    case empty
    case geometry(BoardPreviewSeed)
    case thumbnail(CGImage, BoardPreviewSeed)

    var isThumbnail: Bool {
        if case .thumbnail = self {
            return true
        }

        return false
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewRequestToken.swift
// 函数名/类型名: BoardPreviewRequestToken.cancel() / setCancellationHandler(_:)
// 功能说明: 修改后 request token 统一承接取消状态和 operation 取消回调，cell 复用时可以安全终止后台任务。
import Foundation

final class BoardPreviewRequestToken {
    private let lock = NSLock()
    private var cancellationHandler: (() -> Void)?
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func setCancellationHandler(_ handler: @escaping () -> Void) {
        lock.lock()
        if cancelled {
            lock.unlock()
            handler()
            return
        }

        cancellationHandler = handler
        lock.unlock()
    }

    func cancel() {
        let handler: (() -> Void)?
        lock.lock()
        guard cancelled == false else {
            lock.unlock()
            return
        }

        cancelled = true
        handler = cancellationHandler
        cancellationHandler = nil
        lock.unlock()

        handler?()
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailCache.swift
// 函数名/类型名: BoardThumbnailCacheKey.init?(item:targetPixelSize:) / BoardThumbnailCache
// 功能说明: 修改后缓存 key 同时绑定 board revision 和目标像素尺寸，避免不同显示模式或旧 revision 共用错误缩略图。
import CoreGraphics
import Foundation

struct BoardThumbnailCacheKey {
    let boardID: UUID
    let revisionToken: String
    let pixelWidth: Int
    let pixelHeight: Int

    init?(
        item: BoardCatalogItem,
        targetPixelSize: CGSize
    ) {
        let normalizedPixelSize = targetPixelSize.normalizedBoardThumbnailPixelSize
        guard normalizedPixelSize.width > 0, normalizedPixelSize.height > 0 else {
            return nil
        }

        boardID = item.boardID
        revisionToken = item.revisionToken
        pixelWidth = Int(normalizedPixelSize.width)
        pixelHeight = Int(normalizedPixelSize.height)
    }

    var cacheKey: NSString {
        "\(boardID.uuidString)-\(revisionToken)-\(pixelWidth)x\(pixelHeight)" as NSString
    }
}

final class BoardThumbnailCache {
    private let cache = NSCache<NSString, Entry>()

    func image(for key: BoardThumbnailCacheKey) -> CGImage? {
        cache.object(forKey: key.cacheKey)?.image
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift
// 函数名/类型名: BoardThumbnailRenderer.renderThumbnail(for:targetPixelSize:contentInset:cancellationCheck:)
// 功能说明: 修改后 renderer 会按 mini map 几何映射离屏绘制每个 item，并在绘制过程中持续检查取消状态。
import CoreGraphics
import Foundation
import ImageIO

final class BoardThumbnailRenderer {
    func renderThumbnail(
        for item: BoardCatalogItem,
        targetPixelSize: CGSize,
        contentInset: CGFloat = 10,
        cancellationCheck: () throws -> Void = {}
    ) throws -> CGImage? {
        let snapshot = geometryPreviewBuilder.makeSnapshot(from: item.previewSeed)
        guard
            let geometry = CanvasMiniMapViewGeometry(
                displayWorldRect: snapshot.displayWorldRect,
                viewBounds: CGRect(origin: .zero, size: targetPixelSize),
                contentInset: contentInset
            )
        else {
            return nil
        }

        for itemRecord in orderedItemRecords(from: item.document.items) {
            try cancellationCheck()
            try drawItemRecord(
                itemRecord,
                assetsDirectoryURL: item.assetsDirectoryURL,
                geometry: geometry,
                in: context,
                cancellationCheck: cancellationCheck
            )
        }

        try cancellationCheck()
        return context.makeImage()
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift
// 函数名/类型名: BoardPreviewProvider.immediatePreview(for:targetPixelSize:) / requestThumbnail(for:targetPixelSize:completion:)
// 功能说明: 修改后 provider 统一承接“缓存命中直接回显，未命中则先返回 geometry、后台异步补图”的完整阶段 5 入口。
import CoreGraphics
import Foundation

final class BoardPreviewProvider {
    private let thumbnailCache: BoardThumbnailCache
    private let thumbnailRenderer: BoardThumbnailRenderer
    private let renderQueue: OperationQueue
    private let callbackQueue: DispatchQueue

    func immediatePreview(
        for item: BoardCatalogItem,
        targetPixelSize: CGSize? = nil
    ) -> BoardPreviewContent {
        if let targetPixelSize,
           let cacheKey = BoardThumbnailCacheKey(
               item: item,
               targetPixelSize: targetPixelSize
           ),
           let cachedImage = thumbnailCache.image(for: cacheKey) {
            return .thumbnail(cachedImage, item.previewSeed)
        }

        return .geometry(item.previewSeed)
    }

    @discardableResult
    func requestThumbnail(
        for item: BoardCatalogItem,
        targetPixelSize: CGSize,
        completion: @escaping (BoardPreviewContent?) -> Void
    ) -> BoardPreviewRequestToken {
        let requestToken = BoardPreviewRequestToken()
        let operation = BlockOperation()
        requestToken.setCancellationHandler {
            operation.cancel()
        }

        operation.addExecutionBlock { [weak operation] in
            guard
                let operation,
                operation.isCancelled == false,
                requestToken.isCancelled == false
            else {
                return
            }

            guard
                let renderedImage = try? self.thumbnailRenderer.renderThumbnail(
                    for: item,
                    targetPixelSize: cacheKey.pixelSize,
                    cancellationCheck: {
                        if operation.isCancelled || requestToken.isCancelled {
                            throw BoardThumbnailRendererError.cancelled
                        }
                    }
                )
            else {
                return
            }

            self.thumbnailCache.insert(renderedImage, for: cacheKey)
            self.callbackQueue.async { [weak requestToken] in
                guard let requestToken, requestToken.isCancelled == false else {
                    return
                }

                completion(.thumbnail(renderedImage, item.previewSeed))
            }
        }

        renderQueue.addOperation(operation)
        return requestToken
    }
}
```

## 修改三：renderer 与 preview view 同步调整，确保真实缩略图替换后还能保留 board 轮廓且不会被半透明 fill 覆盖

### 修改前

- `BoardPreviewRenderer` 的 `thumbnail` 分支只做 `imageLayer.contents = image`，同时把 `boardLayer` 直接隐藏。
- `macOSBoardPreviewView` / `iOSBoardPreviewView` 的 layer 顺序是：
- `backgroundLayer`
- `imageLayer`
- `boardLayer`
- `occupancyLayer`
- 一旦真实缩略图出来，`boardLayer.fillColor` 会压在 `imageLayer` 上面，导致缩略图被蒙灰。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewRenderer.swift
// 函数名/类型名: BoardPreviewRenderer.render(content:viewBounds:contentInset:imageLayer:boardLayer:occupancyLayer:)
// 功能说明: 修改前 thumbnail 只显示 image，不再保留 boardRect，真实图替换后会丢失板面轮廓层。
case let .thumbnail(image):
    imageLayer.contents = image
    imageLayer.isHidden = false
    boardLayer.path = nil
    boardLayer.isHidden = true
    occupancyLayer.path = nil
    occupancyLayer.isHidden = true
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardPreviewView.swift
// 函数名/类型名: macOSBoardPreviewView.setupLayers()
// 功能说明: 修改前 macOS preview view 先叠 imageLayer 再叠 boardLayer，board 的半透明 fill 会盖在真实缩略图上面。
private func setupLayers() {
    layer?.addSublayer(backgroundLayer)
    layer?.addSublayer(imageLayer)
    layer?.addSublayer(boardLayer)
    layer?.addSublayer(occupancyLayer)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardPreviewView.swift
// 函数名/类型名: iOSBoardPreviewView.setupLayers()
// 功能说明: 修改前 iOS preview view 的 layer 顺序与 macOS 相同，真实图回填后同样会被 board fill 覆盖一层。
private func setupLayers() {
    layer.addSublayer(backgroundLayer)
    layer.addSublayer(imageLayer)
    layer.addSublayer(boardLayer)
    layer.addSublayer(occupancyLayer)
}
```

### 修改后

- `BoardPreviewRenderer` 的 `thumbnail` 分支改成读取 `.thumbnail(image, seed)`，继续用 `seed` 计算 board rect。
- 双端 preview view 把 layer 顺序改成：
- `backgroundLayer`
- `boardLayer`
- `imageLayer`
- `occupancyLayer`
- 这样 board 边框仍在，但 board fill 不会再盖住真实缩略图内容。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewRenderer.swift
// 函数名/类型名: BoardPreviewRenderer.render(content:viewBounds:contentInset:imageLayer:boardLayer:occupancyLayer:)
// 功能说明: 修改后 thumbnail 分支仍会保留 boardRect 的绘制，真实缩略图替换后不会丢掉板面边界信息。
case let .thumbnail(image, seed):
    imageLayer.contents = image
    imageLayer.isHidden = false

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

    occupancyLayer.path = nil
    occupancyLayer.isHidden = true
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardPreviewView.swift
// 函数名/类型名: macOSBoardPreviewView.setupLayers()
// 功能说明: 修改后 macOS preview view 先放 boardLayer 再放 imageLayer，真实缩略图不会再被 board fill 蒙住。
private func setupLayers() {
    layer?.addSublayer(backgroundLayer)
    layer?.addSublayer(boardLayer)
    layer?.addSublayer(imageLayer)
    layer?.addSublayer(occupancyLayer)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardPreviewView.swift
// 函数名/类型名: iOSBoardPreviewView.setupLayers()
// 功能说明: 修改后 iOS preview view 也同步调整 layer 顺序，保持双端真实缩略图的视觉层级一致。
private func setupLayers() {
    layer.addSublayer(backgroundLayer)
    layer.addSublayer(boardLayer)
    layer.addSublayer(imageLayer)
    layer.addSublayer(occupancyLayer)
}
```

## 修改四：双端 cell 与 controller 接入异步请求、取消、像素尺寸计算和回填校验

### 修改前

- `macOSBoardCollectionItem` / `iOSBoardCollectionViewCell` 只负责：
- `configure(with:previewContent:displayMode:)`
- `prepareForReuse() -> previewView.apply(.empty)`
- 没有：
- `thumbnailRequestToken`
- `representedBoardID`
- `representedRevisionToken`
- `targetThumbnailPixelSize(...)`
- `cancelThumbnailRequest()`
- `requestThumbnail(...)`
- `macOSBoardListViewController` / `iOSBoardListViewController` 在 `cellForItemAt` / `itemForRepresentedObjectAt` 中只会做一次同步 `immediatePreview(for:)`。
- iOS 也没有在 cell 离屏时主动取消后台缩略图任务。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift
// 函数名/类型名: macOSBoardCollectionItem.prepareForReuse() / configure(with:previewContent:displayMode:)
// 功能说明: 修改前 macOS cell 只负责显示同步 preview content，不管理异步缩略图请求生命周期。
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
// 功能说明: 修改前 iOS cell 和 macOS 对应实现一致，也没有取消、尺寸推导和回填校验逻辑。
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
// 函数名/类型名: macOSBoardListViewController.collectionView(_:itemForRepresentedObjectAt:)
// 功能说明: 修改前 macOS controller 只拿同步 geometry 预览，没有目标像素尺寸、没有后台补图请求。
func collectionView(
    _ collectionView: NSCollectionView,
    itemForRepresentedObjectAt indexPath: IndexPath
) -> NSCollectionViewItem {
    let catalogItem = availableBoards[indexPath.item]
    let previewContent = previewProvider.immediatePreview(for: catalogItem)
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
// 函数名/类型名: iOSBoardListViewController.collectionView(_:cellForItemAt:)
// 功能说明: 修改前 iOS controller 同样只做同步 immediatePreview，也没有 didEndDisplaying 的取消处理。
func collectionView(
    _ collectionView: UICollectionView,
    cellForItemAt indexPath: IndexPath
) -> UICollectionViewCell {
    let catalogItem = availableBoards[indexPath.item]
    let previewContent = previewProvider.immediatePreview(for: catalogItem)
    cell.configure(
        with: catalogItem,
        previewContent: previewContent,
        displayMode: displayMode
    )
    return cell
}
```

### 修改后

- 双端 cell 新增：
- `representedBoardID`
- `representedRevisionToken`
- `thumbnailRequestToken`
- `cancelThumbnailRequest()`
- `targetThumbnailPixelSize(for:)`
- `requestThumbnail(using:for:displayMode:)`
- `prepareForReuse()` 会先取消旧请求，再清空自身代表的 board 身份。
- 回调里会同时校验 `boardID + revisionToken`，避免旧异步结果回填到新复用 cell。
- 双端 controller 在配置 cell 时会先根据当前显示模式和屏幕 scale 推导目标像素尺寸。
- 先调用 `immediatePreview(for:targetPixelSize:)`，如果缓存命中就直接显示真实图。
- 如果返回的还不是 thumbnail，再继续发后台请求。
- iOS 在 `didEndDisplaying` 中显式调用 `cancelThumbnailRequest()`，把离屏任务及时停掉。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift
// 函数名/类型名: macOSBoardCollectionItem.cancelThumbnailRequest() / targetThumbnailPixelSize(for:) / requestThumbnail(using:for:displayMode:)
// 功能说明: 修改后 macOS cell 自己管理异步请求生命周期，并在回填时校验当前 cell 仍然代表同一个 board revision。
private var representedBoardID: UUID?
private var representedRevisionToken: String?
private var thumbnailRequestToken: BoardPreviewRequestToken?

override func prepareForReuse() {
    super.prepareForReuse()
    cancelThumbnailRequest()
    representedBoardID = nil
    representedRevisionToken = nil
    titleLabel.stringValue = ""
    previewView.apply(content: .empty)
}

func requestThumbnail(
    using previewProvider: BoardPreviewProvider,
    for item: BoardCatalogItem,
    displayMode: BoardListDisplayMode
) {
    cancelThumbnailRequest()

    thumbnailRequestToken = previewProvider.requestThumbnail(
        for: item,
        targetPixelSize: targetThumbnailPixelSize(for: displayMode)
    ) { [weak self] previewContent in
        guard
            let self,
            let previewContent,
            self.representedBoardID == item.boardID,
            self.representedRevisionToken == item.revisionToken
        else {
            return
        }

        self.previewView.apply(content: previewContent)
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift
// 函数名/类型名: iOSBoardCollectionViewCell.cancelThumbnailRequest() / targetThumbnailPixelSize(for:) / requestThumbnail(using:for:displayMode:)
// 功能说明: 修改后 iOS cell 与 macOS 共用同一套思路，按 displayMode 计算目标像素尺寸，并在回填前做 board revision 校验。
private var representedBoardID: UUID?
private var representedRevisionToken: String?
private var thumbnailRequestToken: BoardPreviewRequestToken?

func targetThumbnailPixelSize(
    for displayMode: BoardListDisplayMode
) -> CGSize {
    contentView.layoutIfNeeded()

    let previewSize = resolvedPreviewViewSize(for: displayMode)
    let contentsScale = window?.screen.scale ?? UIScreen.main.scale
    return CGSize(
        width: previewSize.width * contentsScale,
        height: previewSize.height * contentsScale
    )
}

func requestThumbnail(
    using previewProvider: BoardPreviewProvider,
    for item: BoardCatalogItem,
    displayMode: BoardListDisplayMode
) {
    thumbnailRequestToken = previewProvider.requestThumbnail(
        for: item,
        targetPixelSize: targetThumbnailPixelSize(for: displayMode)
    ) { [weak self] previewContent in
        guard
            let self,
            let previewContent,
            self.representedBoardID == item.boardID,
            self.representedRevisionToken == item.revisionToken
        else {
            return
        }

        self.previewView.apply(content: previewContent)
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名/类型名: macOSBoardListViewController.collectionView(_:itemForRepresentedObjectAt:)
// 功能说明: 修改后 macOS controller 会先按当前 cell 尺寸查缓存，未命中再下发后台缩略图请求。
func collectionView(
    _ collectionView: NSCollectionView,
    itemForRepresentedObjectAt indexPath: IndexPath
) -> NSCollectionViewItem {
    let catalogItem = availableBoards[indexPath.item]
    let targetPixelSize = item.targetThumbnailPixelSize(for: displayMode)
    let previewContent = previewProvider.immediatePreview(
        for: catalogItem,
        targetPixelSize: targetPixelSize
    )

    item.configure(
        with: catalogItem,
        previewContent: previewContent,
        displayMode: displayMode
    )

    if previewContent.isThumbnail == false {
        item.requestThumbnail(
            using: previewProvider,
            for: catalogItem,
            displayMode: displayMode
        )
    }

    return item
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/类型名: iOSBoardListViewController.collectionView(_:cellForItemAt:) / collectionView(_:didEndDisplaying:forItemAt:)
// 功能说明: 修改后 iOS controller 同时接入缓存命中、后台补图和离屏取消三段逻辑，避免滚动时残留无效任务。
func collectionView(
    _ collectionView: UICollectionView,
    cellForItemAt indexPath: IndexPath
) -> UICollectionViewCell {
    let catalogItem = availableBoards[indexPath.item]
    let targetPixelSize = cell.targetThumbnailPixelSize(for: displayMode)
    let previewContent = previewProvider.immediatePreview(
        for: catalogItem,
        targetPixelSize: targetPixelSize
    )

    cell.configure(
        with: catalogItem,
        previewContent: previewContent,
        displayMode: displayMode
    )

    if previewContent.isThumbnail == false {
        cell.requestThumbnail(
            using: previewProvider,
            for: catalogItem,
            displayMode: displayMode
        )
    }

    return cell
}

func collectionView(
    _ collectionView: UICollectionView,
    didEndDisplaying cell: UICollectionViewCell,
    forItemAt indexPath: IndexPath
) {
    (cell as? iOSBoardCollectionViewCell)?.cancelThumbnailRequest()
}
```

## 验证情况

- 已对 `Platform/Shared/BoardList`、双端 `BoardList` 相关文件执行 lint 读取检查，未发现新增 lints。
- 尝试执行 `xcodebuild` 级别验证时失败，当前环境提示 active developer directory 指向 `CommandLineTools`，不是完整 Xcode，因此本次记录没有包含工程级编译通过截图或日志。
- 本阶段代码层面已经补齐：
- 真实缩略图离屏渲染
- 内存缓存
- cell 复用取消
- board revision 回填校验
- 双端 controller 接入

## 阶段结果

- 阶段 5 完成后，`BoardList` 预览链已经从“只有同步几何图”升级为“同步几何首屏 + 后台真实缩略图 + 缓存命中直接回显”的混合方案。
- 这为下一阶段是否落持久化 `thumbnail.png` 提供了稳定边界，后续只需要替换 `BoardPreviewProvider` 内部数据源，而不必再推翻双端 cell / controller 接口。
