# 20260324_114510_gif_phase5_playback_system_record

## 记录范围

- 记录内容：
  - 新增主画布 GIF 播放子系统，按 `assetReference` 管理播放实例与时间推进。
  - 为 `CanvasEditorSession` 和 `BoardStore` 增加统一的 GIF 播放源解析入口，兼容 transient 导入资源与持久化资源。
  - 调整 iOS / macOS viewport，在可见项刷新、窗口挂载、前后台切换时接入 GIF 播放生命周期。
  - 调整 iOS / macOS view controller，把 autoplay 配置和播放源解析器注入 viewport。
- 涉及文件：
  - `MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasAnimatedImagePlayback.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift`
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift`
  - `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 本记录不包含：
  - 阶段 0 GIF 语义契约
  - 阶段 1 图片资产模型拆分
  - 阶段 2 导入原始 GIF 资源保留
  - 阶段 3 文档格式与存储迁移
  - 阶段 4 render contract 稳定化
  - 阶段 6 预览链路与成本控制
  - git commit / push

## 修改一：新增共享 GIF 播放子系统，播放不再依赖 viewport 全量重刷

### 修改前

- 阶段 4 虽然已经把 `CanvasImageLayer` 拆成静态 poster 路径和动画预备路径，但还没有真正的播放注册表、tick 驱动和资源级复用。
- viewport 对动画图片仍然只会执行 `updateAnimatedPresentation(...)`，不会推进帧，也不会按可见项建立播放控制器。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: refreshAnimatedImageLayer(_:with:imagePayload:contentsScale:)
// 功能说明: 修改前动画图片分支只把 layer 切到“播放预备态”，没有共享播放注册表、tick，也没有逐帧驱动。
private func refreshAnimatedImageLayer(
    _ imageLayer: CanvasImageLayer,
    with item: CanvasRenderItem,
    imagePayload: CanvasImageRenderPayload,
    contentsScale: CGFloat
) {
    // Stage 4 splits animated-image reconciliation away from static-image
    // poster drawing so a later playback controller can own frame updates
    // without forcing the viewport to rebuild its item refresh flow.
    imageLayer.updateAnimatedPresentation(
        with: item,
        imagePayload: imagePayload,
        contentsScale: contentsScale
    )
}
```

### 修改后

- 新增 `CanvasAnimatedImagePlayback.swift`，把播放内核抽成共享层：
  - `CanvasAnimatedImagePlaybackSource` 表达 GIF 原始数据和动画元数据。
  - `CanvasAnimatedImagePlaybackBinding` 表达“哪个 item / 哪个 layer 正在显示这个资产”。
  - `CanvasAnimationTicker` 在主线程 RunLoop 上推进时间。
  - `CanvasGIFPlaybackRegistry` 负责可见项 reconcile、按 `assetReference` 复用 controller、在无需要时停止 ticker。
  - `CanvasGIFPlaybackController` 负责 `CGImageSource` 解帧、延迟时间推进、循环次数和向多个 layer 分发当前帧。
- 这样 GIF 帧更新直接推给 `CanvasImageLayer.displayPlaybackFrame(...)`，不再需要依赖重新生成 render snapshot。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasAnimatedImagePlayback.swift
// 函数名: reconcileVisibleBindings(_:) / setPlaybackEnabled(_:) / handleTick(elapsedTime:) / needsTicks
// 功能说明: 修改后新增共享 GIF 播放子系统；以 assetReference 复用控制器，按可见 binding 注册 layer，并在有限循环播放结束后自动停表。
struct CanvasAnimatedImagePlaybackSource {
    let assetReference: CanvasImageAssetReference
    let data: Data
    let animatedMetadata: CanvasAnimatedImageMetadata?
}

struct CanvasAnimatedImagePlaybackBinding {
    let itemID: CanvasItemID
    let displayContract: CanvasImageDisplayContract
    let layer: CanvasImageLayer
}

final class CanvasGIFPlaybackRegistry {
    typealias SourceResolver = (CanvasImageAssetReference) -> CanvasAnimatedImagePlaybackSource?

    private let resolveSource: SourceResolver
    private let ticker: CanvasAnimationTicker
    private var visibleBindingsByItemID: [CanvasItemID: CanvasAnimatedImagePlaybackBinding] = [:]
    private var controllersByAssetReference: [CanvasImageAssetReference: CanvasGIFPlaybackController] = [:]
    private var isPlaybackEnabled = false

    func reconcileVisibleBindings(_ bindings: [CanvasAnimatedImagePlaybackBinding]) {
        // 对可见 item 做 diff，离屏解绑，入屏绑定。
    }

    func setPlaybackEnabled(_ enabled: Bool) {
        // 前后台 / window 生命周期统一从这里开关播放。
    }

    private func handleTick(elapsedTime: TimeInterval) {
        for controller in controllersByAssetReference.values {
            controller.tick(elapsedTime: elapsedTime)
        }
        updateTickerState()
    }

    private func updateTickerState() {
        let shouldTick = isPlaybackEnabled &&
            controllersByAssetReference.values.contains { $0.needsTicks }
        if shouldTick {
            ticker.startIfNeeded()
        } else {
            ticker.stop()
        }
    }
}

private final class CanvasGIFPlaybackController {
    private var boundLayersByItemID: [CanvasItemID: CanvasImageLayer] = [:]
    private var currentFrameIndex = 0
    private var currentPlaybackFrame: CGImage?
    private var accumulatedFrameTime: TimeInterval = 0
    private var completedLoopCount = 0
    private var isFinished = false

    var needsTicks: Bool {
        hasBindings && isFinished == false
    }

    func tick(elapsedTime: TimeInterval) {
        // 根据 GIF 每帧延迟推进时间，并把下一帧直接推给 layer。
    }
}
```

## 修改二：`CanvasEditorSession` / `BoardStore` 新增统一播放源解析入口

### 修改前

- `CanvasEditorSession` 只暴露 `transientImageAssetPayload(for:)`，它更偏向阶段 2/3 的导入与保存链路，并不是给播放层直接消费的抽象。
- `BoardStore` 也只有 `loadBoard(...)` 这种“整板恢复”入口，没有给 GIF 播放器单独读取某个持久化资源文件的方法。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: transientImageAssetPayload(for:)
// 功能说明: 修改前 Session 只提供 transient payload 查询能力，没有统一的 GIF 播放源解析接口。
func transientImageAssetPayload(
    for assetReference: CanvasImageAssetReference
) -> CanvasTransientImageAssetPayload? {
    transientImageAssetPayloads[assetReference]
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift
// 函数名: loadBoard(id:userDefaults:)
// 功能说明: 修改前存储层只有整板恢复入口，播放系统无法按 asset filename 直接取回 GIF 原始数据。
static func loadBoard(
    id: UUID,
    userDefaults: UserDefaults = .standard
) throws -> BoardRuntimeState {
    // ... 读取 board.json ...
    // ... 读取 assets 并恢复运行时 item ...
}
```

### 修改后

- `CanvasEditorSession.animatedImagePlaybackSource(for:)` 成为播放层唯一入口：
  - 如果当前资产还在 session 的 transient 注册表里，优先直接返回原始导入数据和元数据。
  - 如果 transient 数据不存在，则回退到当前 board 的持久化 assets 目录读取对应文件。
- `BoardStore.loadImageAssetData(boardID:filename:)` 补齐了按资源文件名读取资产数据的能力，让播放层不必重新走整板恢复流程。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: animatedImagePlaybackSource(for:)
// 功能说明: 修改后 Session 统一封装 GIF 播放源解析；优先读 transient 导入资源，缺失时回退到当前 board 的持久化 assets。
func animatedImagePlaybackSource(
    for assetReference: CanvasImageAssetReference
) -> CanvasAnimatedImagePlaybackSource? {
    guard assetReference.kind.isAnimated else {
        return nil
    }

    if let payload = transientImageAssetPayload(for: assetReference),
       let data = payload.source?.data
    {
        return CanvasAnimatedImagePlaybackSource(
            assetReference: assetReference,
            data: data,
            animatedMetadata: payload.animatedMetadata
        )
    }

    guard let activeBoardID else {
        return nil
    }

    guard let data = try? BoardStore.loadImageAssetData(
        boardID: activeBoardID,
        filename: assetReference.stableAssetFilename
    ) else {
        return nil
    }

    return CanvasAnimatedImagePlaybackSource(
        assetReference: assetReference,
        data: data,
        animatedMetadata: nil
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardStore.swift
// 函数名: loadImageAssetData(boardID:filename:userDefaults:)
// 功能说明: 修改后存储层支持按 boardID + 资产文件名直接读取 GIF 原始数据，供播放系统按需解码。
static func loadImageAssetData(
    boardID: UUID,
    filename: String,
    userDefaults: UserDefaults = .standard
) throws -> Data {
    try SelectedFolderAccess.withBoardsDirectoryURL(userDefaults: userDefaults) { boardsDirectoryURL in
        let boardDirectoryURL = self.boardDirectoryURL(
            for: boardID,
            boardsDirectoryURL: boardsDirectoryURL
        )
        let assetsDirectoryURL = boardDirectoryURL.appendingPathComponent(
            assetsDirectoryName,
            isDirectory: true
        )
        let assetURL = assetsDirectoryURL.appendingPathComponent(filename)
        return try CoordinatedFileIO.readData(at: assetURL)
    }
}
```

## 修改三：iOS viewport 从“动画 poster 预备态”升级为“可见项注册 + 生命周期播放控制”

### 修改前

- `iOSCanvasViewportView` 只有 `imageLayers` / `textLayers` 这样的渲染层缓存。
- `refreshItemLayers()` 虽然会区分静态图和动画图，但动画图只进入 `refreshAnimatedImageLayer(...)`，没有可见项绑定列表，也没有前后台播放开关。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: refreshItemLayers()
// 功能说明: 修改前 iOS viewport 只负责刷新 layer 几何与 poster 展示，不会为 GIF 收集可见 binding，也不会驱动播放。
private func refreshItemLayers() {
    let contentsScale = window?.screen.scale ?? UIScreen.main.scale
    for item in snapshot.items {
        switch item.payload {
        case let .image(imagePayload):
            let imageLayer = imageLayer(for: item.id)
            refreshImageLayer(
                imageLayer,
                with: item,
                imagePayload: imagePayload,
                contentsScale: contentsScale
            )
        case let .text(textPayload):
            let textLayer = textLayer(for: item.id)
            textLayer.update(
                with: item,
                textPayload: textPayload,
                contentsScale: contentsScale
            )
        }
    }
}
```

### 修改后

- `iOSCanvasViewportView` 新增：
  - `animatedPlaybackRegistry`
  - `resolveAnimatedImagePlaybackSource`
  - `shouldAutoplayAnimatedImages`
  - `animatedPlaybackObservers`
  - `isApplicationPlaybackActive`
- `refreshItemLayers()` 现在会为可见 GIF item 生成 `CanvasAnimatedImagePlaybackBinding`，并把结果交给 `animatedPlaybackRegistry.reconcileVisibleBindings(...)`。
- `layoutSubviews()`、`didBecomeActive`、`willResignActive`、`deinit` 统一参与播放开关，确保切后台、window 脱离、销毁时停止 tick 并恢复 poster。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: refreshItemLayers() / setupAnimatedPlaybackLifecycle() / updateAnimatedPlaybackState()
// 功能说明: 修改后 iOS viewport 在可见项刷新阶段收集 GIF binding，并按窗口与前后台生命周期统一开关播放。
private lazy var animatedPlaybackRegistry = CanvasGIFPlaybackRegistry { [weak self] assetReference in
    self?.resolveAnimatedImagePlaybackSource?(assetReference)
}
private var animatedPlaybackObservers: [NSObjectProtocol] = []
private var isApplicationPlaybackActive =
    UIApplication.shared.applicationState == .active
var resolveAnimatedImagePlaybackSource: ((CanvasImageAssetReference) -> CanvasAnimatedImagePlaybackSource?)?
var shouldAutoplayAnimatedImages = true

private func refreshItemLayers() {
    let contentsScale = window?.screen.scale ?? UIScreen.main.scale
    var animatedBindings: [CanvasAnimatedImagePlaybackBinding] = []
    for item in snapshot.items {
        switch item.payload {
        case let .image(imagePayload):
            let imageLayer = imageLayer(for: item.id)
            refreshImageLayer(
                imageLayer,
                with: item,
                imagePayload: imagePayload,
                contentsScale: contentsScale
            )
            if imagePayload.displayContract.isAnimatedAsset {
                animatedBindings.append(
                    CanvasAnimatedImagePlaybackBinding(
                        itemID: item.id,
                        displayContract: imagePayload.displayContract,
                        layer: imageLayer
                    )
                )
            }
        case let .text(textPayload):
            // ... 文本逻辑不变 ...
            break
        }
    }

    animatedPlaybackRegistry.reconcileVisibleBindings(animatedBindings)
    updateAnimatedPlaybackState()
}

private func setupAnimatedPlaybackLifecycle() {
    let notificationCenter = NotificationCenter.default
    animatedPlaybackObservers = [
        notificationCenter.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isApplicationPlaybackActive = true
            self?.updateAnimatedPlaybackState()
        },
        notificationCenter.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isApplicationPlaybackActive = false
            self?.updateAnimatedPlaybackState()
        }
    ]
}

private func updateAnimatedPlaybackState() {
    animatedPlaybackRegistry.setPlaybackEnabled(
        shouldAutoplayAnimatedImages &&
            isApplicationPlaybackActive &&
            window != nil &&
            bounds.isEmpty == false
    )
}
```

## 修改四：macOS viewport 同步接入 GIF 可见性与应用激活生命周期

### 修改前

- `macOSCanvasViewportView` 和 iOS 一样，只会把动画图片交给 `refreshAnimatedImageLayer(...)`，没有共享播放注册表，也没有 `NSApplication` 激活状态联动。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: refreshItemLayers()
// 功能说明: 修改前 macOS viewport 只负责 layer 几何与 poster 刷新，动画资源仍停留在“准备好播放”的阶段。
private func refreshItemLayers() {
    let contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    for item in snapshot.items {
        switch item.payload {
        case let .image(imagePayload):
            let imageLayer = imageLayer(for: item.id)
            refreshImageLayer(
                imageLayer,
                with: item,
                imagePayload: imagePayload,
                contentsScale: contentsScale
            )
        case let .text(textPayload):
            let textLayer = textLayer(for: item.id)
            textLayer.update(
                with: item,
                textPayload: textPayload,
                contentsScale: contentsScale
            )
        }
    }
}
```

### 修改后

- `macOSCanvasViewportView` 对齐 iOS：
  - 可见 GIF item 建立 binding。
  - `animatedPlaybackRegistry` 负责 reconcile 与播放开关。
  - `NSApplication.didBecomeActiveNotification` / `didResignActiveNotification` 控制后台暂停。
  - `layout()`、`deinit` 也参与播放状态同步。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: refreshItemLayers() / setupAnimatedPlaybackLifecycle() / updateAnimatedPlaybackState()
// 功能说明: 修改后 macOS viewport 以可见 binding 管理 GIF 播放，并在应用失活、window 脱离或 view 销毁时及时停表。
private lazy var animatedPlaybackRegistry = CanvasGIFPlaybackRegistry { [weak self] assetReference in
    self?.resolveAnimatedImagePlaybackSource?(assetReference)
}
private var animatedPlaybackObservers: [NSObjectProtocol] = []
private var isApplicationPlaybackActive = NSApplication.shared.isActive
var resolveAnimatedImagePlaybackSource: ((CanvasImageAssetReference) -> CanvasAnimatedImagePlaybackSource?)?
var shouldAutoplayAnimatedImages = true

private func refreshItemLayers() {
    let contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    var animatedBindings: [CanvasAnimatedImagePlaybackBinding] = []
    for item in snapshot.items {
        switch item.payload {
        case let .image(imagePayload):
            let imageLayer = imageLayer(for: item.id)
            refreshImageLayer(
                imageLayer,
                with: item,
                imagePayload: imagePayload,
                contentsScale: contentsScale
            )
            if imagePayload.displayContract.isAnimatedAsset {
                animatedBindings.append(
                    CanvasAnimatedImagePlaybackBinding(
                        itemID: item.id,
                        displayContract: imagePayload.displayContract,
                        layer: imageLayer
                    )
                )
            }
        case let .text(textPayload):
            // ... 文本逻辑不变 ...
            break
        }
    }

    animatedPlaybackRegistry.reconcileVisibleBindings(animatedBindings)
    updateAnimatedPlaybackState()
}

private func setupAnimatedPlaybackLifecycle() {
    let notificationCenter = NotificationCenter.default
    animatedPlaybackObservers = [
        notificationCenter.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isApplicationPlaybackActive = true
            self?.updateAnimatedPlaybackState()
        },
        notificationCenter.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isApplicationPlaybackActive = false
            self?.updateAnimatedPlaybackState()
        }
    ]
}

private func updateAnimatedPlaybackState() {
    animatedPlaybackRegistry.setPlaybackEnabled(
        shouldAutoplayAnimatedImages &&
            isApplicationPlaybackActive &&
            window != nil &&
            bounds.isEmpty == false
    )
}
```

## 修改五：iOS / macOS controller 显式把 autoplay 契约与播放源解析器注入 viewport

### 修改前

- `setupCanvasViewport()` 只负责指针、缩放、拖拽等交互回调接线，viewport 侧没有办法拿到 GIF 播放源解析器。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: setupCanvasViewport()
// 功能说明: 修改前 controller 只接入交互事件，viewport 无法向 session 请求 GIF 播放源。
private func setupCanvasViewport() {
    canvasViewportView.onPointerDown = { [weak self] location in
        self?.handlePrimaryPointerDown(at: location)
    }
    canvasViewportView.onPointerMove = { [weak self] location, previousLocation in
        self?.handlePrimaryPointerMove(to: location, from: previousLocation)
    }
    // ... 其余交互 wiring ...
}
```

### 修改后

- iOS / macOS controller 都在 `setupCanvasViewport()` 里显式注入：
  - `shouldAutoplayAnimatedImages`
  - `resolveAnimatedImagePlaybackSource`
- 这样 autoplay 契约仍然由 session 统一提供，viewport 只做可见性与生命周期层的播放编排。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: setupCanvasViewport()
// 功能说明: 修改后 iOS controller 把 GIF autoplay 契约与播放源解析器注入 viewport，保持播放策略仍由 session 统一定义。
private func setupCanvasViewport() {
    canvasViewportView.shouldAutoplayAnimatedImages =
        editorSession.shouldAutoplayAnimatedImagesOnCanvas
    canvasViewportView.resolveAnimatedImagePlaybackSource = { [weak self] assetReference in
        self?.editorSession.animatedImagePlaybackSource(for: assetReference)
    }
    canvasViewportView.onPointerDown = { [weak self] location in
        self?.handlePrimaryPointerDown(at: location)
    }
    // ... 其余交互 wiring 保持不变 ...
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: setupCanvasViewport()
// 功能说明: 修改后 macOS controller 同步注入 GIF autoplay 契约与播放源解析器，保证双端播放接线一致。
private func setupCanvasViewport() {
    canvasViewportView.shouldAutoplayAnimatedImages =
        editorSession.shouldAutoplayAnimatedImagesOnCanvas
    canvasViewportView.resolveAnimatedImagePlaybackSource = { [weak self] assetReference in
        self?.editorSession.animatedImagePlaybackSource(for: assetReference)
    }
    canvasViewportView.onPointerDown = { [weak self] location in
        self?.handlePrimaryPointerDown(at: location)
    }
    // ... 其余交互 wiring 保持不变 ...
}
```

## 本阶段结果

- 主画布 GIF 已具备本地播放子系统：
  - 只为当前可见的动画图片建立播放 binding。
  - 按 `assetReference` 复用播放控制器，避免同资源重复解码。
  - 前后台切换、window / view 生命周期变化时会停表并恢复 poster。
  - 有限循环 GIF 播放完成后会自动停止继续 tick。
- 本阶段仍未覆盖：
  - board list / persisted thumbnail / minimap 的 GIF 预览成本控制
  - 阶段 6 的静态预览链路收敛
