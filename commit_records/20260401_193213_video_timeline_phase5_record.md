# 20260401_193213_video_timeline_phase5_record

## 记录范围

- 记录内容：实施 `@.cursor/plans/视频时间线轨道改造_4a257c8b.plan.md` 的 `phase5`，把时间线缩放路径上的性能收口和占位态收口纳入主路径。
- 记录内容：重点覆盖同一视频解码会话复用、超宽 viewport 的缩略图密度上限、时间线视图内聚 loading / 空态，以及双端控制器去掉外置 placeholder overlay。
- 涉及文件：`MyCanvas_Ver_0/Canvas/Video/CanvasVideoFrameService.swift`
- 涉及文件：`MyCanvas_Ver_0/Canvas/Video/CanvasVideoTimeline.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/iOS/iOSVideoTimelineView.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/macOS/macOSVideoTimelineView.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/iOS/iOSVideoDisplayFrameEditorViewController.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/macOS/macOSVideoDisplayFrameEditorViewController.swift`
- 涉及文件：`MyCanvas_Ver_0Tests/CanvasVideoTimelineStripServiceTests.swift`
- 涉及文件：`MyCanvas_Ver_0Tests/CanvasVideoEditorPreviewStateTests.swift`
- 本记录不包含：`git commit` / `git push`

## 修改一：服务层复用解码会话，并限制时间线缩略图密度

### 修改前

- `frameImage(...)`、`previewStrip(...)`、`timelineStrip(...)` 每次请求都会重新创建 `AVURLAsset` 和 `AVAssetImageGenerator`。
- `timelineStrip(...)` 直接按 `request.targetFrameCount` 取帧，极端放大和超宽 viewport 下没有统一的上限。
- `editorContext(...)` 也会单独再建一次 `AVURLAsset` 来取 duration / natural size。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Video/CanvasVideoFrameService.swift
// 类型/函数: editorContext(for:boardID:userDefaults:) / frameImage(from:at:quality:) / previewStrip(from:frameCount:maxPixelSize:) / timelineStrip(from:request:)
// 功能说明: 修改前服务层每次进入时间线或取帧都重新创建 asset 和 image generator，时间线帧数直接跟随 request.targetFrameCount 线性膨胀。
static func editorContext(
    for item: CanvasImageItem,
    boardID: UUID,
    userDefaults: UserDefaults = .standard
) throws -> CanvasVideoEditorContext {
    // ... 省略前置校验
    let asset = AVURLAsset(url: sourceVideoURL)
    return CanvasVideoEditorContext(
        boardID: boardID,
        itemID: item.id,
        sourceVideoURL: sourceVideoURL,
        sourceVideoFilename: sourceVideoFilename,
        currentPosterFilename: item.assetReference.stableAssetFilename,
        currentPosterTimeSeconds: sanitizedTimeSeconds(item.posterTimeSeconds ?? 0),
        durationSeconds: sanitizedDurationSeconds(asset.duration),
        naturalPixelSize: naturalVideoPixelSize(for: asset) ?? item.logicalPixelSize
    )
}

static func frameImage(
    from localFileURL: URL,
    at timeSeconds: Double,
    quality: CanvasVideoFrameRenderQuality
) throws -> CanvasVideoFrameImage {
    let asset = AVURLAsset(url: localFileURL)
    let filename = localFileURL.lastPathComponent
    let imageGenerator = makeImageGenerator(
        for: asset,
        quality: quality
    )
    return try makeFrameImage(
        from: asset,
        filename: filename,
        at: timeSeconds,
        imageGenerator: imageGenerator
    )
}

static func timelineStrip(
    from localFileURL: URL,
    request: CanvasVideoTimelineStripRequest
) throws -> CanvasVideoTimelineStrip {
    let asset = AVURLAsset(url: localFileURL)
    let normalizedRequest = CanvasVideoTimelineStripRequest(
        viewport: request.viewport.with(
            durationSeconds: sanitizedDurationSeconds(asset.duration)
        ),
        thumbnailWidth: request.thumbnailWidth,
        maxPixelSize: request.maxPixelSize,
        overscanWidth: request.overscanWidth
    )
    let cacheKey = CanvasVideoTimelineStripCacheKey(
        localFileURL: localFileURL,
        request: normalizedRequest
    )
    if let cachedStrip = timelineStripCache.strip(for: cacheKey) {
        return cachedStrip
    }

    let filename = localFileURL.lastPathComponent
    let imageGenerator = makeImageGenerator(
        for: asset,
        quality: .previewStripThumbnail(
            maxPixelSize: normalizedRequest.maxPixelSize
        )
    )
    let sampleTimes = normalizedRequest.sampleTimes()
    // ... 省略逐帧构建 strip 的现有逻辑
}
```

### 修改后

- 新增 `CanvasVideoFrameDecodeSessionCache` 和 `CanvasVideoFrameDecodeSession`，按视频 URL 复用 `AVURLAsset` 与按质量分桶的 `AVAssetImageGenerator`。
- 新增 `maximumTimelineStripFrameCount = 48`，统一限制时间线轨道一次最多解多少帧。
- `CanvasVideoTimelineStripCacheKey` 现在把“收口后的有效 frame count”纳入 key，避免不同密度请求被错误复用。
- `editorContext(...)`、`frameImage(...)`、`previewStrip(...)`、`timelineStrip(...)` 都统一走 decode session。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Video/CanvasVideoFrameService.swift
// 类型/函数: CanvasVideoFrameDecodeSessionCache / CanvasVideoFrameDecodeSession / timelineStrip(from:request:) / effectiveTimelineStripFrameCount(for:)
// 功能说明: 修改后服务层把同一视频的 asset 和 image generator 生命周期收口到 decode session，并对时间线 strip 的最大帧数做硬上限，避免缩放时重复建重对象和一次性解过多帧。
private final class CanvasVideoFrameDecodeSessionCache {
    private let lock = NSLock()
    private let countLimit: Int
    private var sessions: [NSString: CanvasVideoFrameDecodeSession] = [:]
    private var orderedKeys: [NSString] = []

    init(countLimit: Int = 12) {
        self.countLimit = max(countLimit, 1)
    }

    func session(for localFileURL: URL) -> CanvasVideoFrameDecodeSession {
        let standardizedURL = localFileURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let cacheKey = standardizedURL.path as NSString
        // ... 省略 LRU 复用细节
    }
}

private final class CanvasVideoFrameDecodeSession {
    private enum GeneratorKey: Hashable {
        case posterCommit
        case previewStripThumbnail(maxPixelSize: Int)
    }

    let asset: AVURLAsset
    let filename: String
    let durationSeconds: Double
    let naturalPixelSize: CGSize?

    private let lock = NSLock()
    private var imageGenerators: [GeneratorKey: AVAssetImageGenerator] = [:]

    func timelineStrip(
        request: CanvasVideoTimelineStripRequest,
        frameCount: Int
    ) throws -> CanvasVideoTimelineStrip {
        lock.lock()
        defer { lock.unlock() }

        let imageGenerator = generator(
            for: .previewStripThumbnail(maxPixelSize: request.maxPixelSize)
        )
        let sampleTimes = request.sampleTimes(frameCount: frameCount)
        let frames = try sampleTimes.map { sampleTime in
            let frameImage = try CanvasVideoFrameService.makeFrameImage(
                from: asset,
                filename: filename,
                at: sampleTime,
                imageGenerator: imageGenerator,
                naturalPixelSize: naturalPixelSize
            )
            return CanvasVideoTimelineStripFrame(
                cgImage: frameImage.cgImage,
                requestedTimeSeconds: sampleTime,
                actualTimeSeconds: frameImage.actualTimeSeconds,
                contentX: request.viewport.contentX(
                    forTimeSeconds: frameImage.actualTimeSeconds
                )
            )
        }
        return CanvasVideoTimelineStrip(
            request: request,
            frames: frames
        )
    }
}

enum CanvasVideoFrameService {
    static let maximumTimelineStripFrameCount = 48

    private static let timelineStripCache = CanvasVideoTimelineStripCache()
    private static let frameDecodeSessionCache = CanvasVideoFrameDecodeSessionCache()

    static func timelineStrip(
        from localFileURL: URL,
        request: CanvasVideoTimelineStripRequest
    ) throws -> CanvasVideoTimelineStrip {
        let decodeSession = frameDecodeSession(for: localFileURL)
        let normalizedRequest = CanvasVideoTimelineStripRequest(
            viewport: request.viewport.with(
                durationSeconds: decodeSession.durationSeconds
            ),
            thumbnailWidth: request.thumbnailWidth,
            maxPixelSize: request.maxPixelSize,
            overscanWidth: request.overscanWidth
        )
        let targetFrameCount = effectiveTimelineStripFrameCount(
            for: normalizedRequest
        )
        let cacheKey = CanvasVideoTimelineStripCacheKey(
            localFileURL: localFileURL,
            request: normalizedRequest,
            targetFrameCount: targetFrameCount
        )
        if let cachedStrip = timelineStripCache.strip(for: cacheKey) {
            return cachedStrip
        }

        let strip = try decodeSession.timelineStrip(
            request: normalizedRequest,
            frameCount: targetFrameCount
        )
        timelineStripCache.insert(strip, for: cacheKey)
        return strip
    }

    private static func effectiveTimelineStripFrameCount(
        for request: CanvasVideoTimelineStripRequest
    ) -> Int {
        min(max(request.targetFrameCount, 1), maximumTimelineStripFrameCount)
    }
}
```

## 修改二：共享时间线契约补齐 placeholder 状态

### 修改前

- `CanvasVideoTimeline.swift` 只定义了 viewport / request / strip 一类几何与取帧契约。
- loading / 空态 / 错误提示都还没有共享状态枚举，宿主只能各自临时拼 UI。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Video/CanvasVideoTimeline.swift
// 类型/函数: CanvasVideoTimelineStrip / 文件结尾
// 功能说明: 修改前共享时间线契约只覆盖几何和 strip 数据，不包含 timeline host 自己的 placeholder 语义。
struct CanvasVideoTimelineStrip {
    let request: CanvasVideoTimelineStripRequest
    let frames: [CanvasVideoTimelineStripFrame]

    var visibleTimeRange: ClosedRange<Double> {
        request.visibleTimeRange
    }

    var requestedTimeRange: ClosedRange<Double> {
        request.requestedTimeRange
    }
}
```

### 修改后

- 新增 `CanvasVideoTimelinePlaceholderState`，把 `hidden / loading(message:) / message(String)` 抽成共享契约。
- 双端 timeline view 和双端控制器都改为围绕这一个状态流转，不再各自发明一套占位态含义。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Video/CanvasVideoTimeline.swift
// 类型/函数: CanvasVideoTimelinePlaceholderState
// 功能说明: 修改后把时间线 host 的隐藏、加载中、消息提示统一抽成共享状态枚举，双端视图与控制器围绕同一份语义同步。
enum CanvasVideoTimelinePlaceholderState: Equatable {
    case hidden
    case loading(message: String)
    case message(String)
}
```

## 修改三：iOS 时间线视图内聚 loading / 空态，并复用缩略图 layer

### 修改前

- `iOSVideoTimelineView` 只负责轨道几何、滚动、缩放和 strip 渲染，占位态仍然挂在控制器外面。
- `renderTrackFrames()` 每次都 `removeFromSuperlayer()` 再整批新建 `CALayer`，滚动和缩放时容易频繁闪烁。
- tap 和 pinch 都挂在 timeline view 上，但没有显式约束 tap 在 pinch 失败后再触发。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSVideoTimelineView.swift
// 类型/函数: 属性区块 / configure(durationSeconds:playheadTimeSeconds:zoomScale:) / setupViewHierarchy() / renderTrackFrames()
// 功能说明: 修改前 iOS 时间线视图只渲染轨道本体，loading / 空态留在控制器外，轨道帧 layer 每次重绘都整批销毁重建。
private let playheadHandleView: UIView = {
    let view = UIView()
    view.translatesAutoresizingMaskIntoConstraints = false
    view.backgroundColor = .systemRed
    view.layer.cornerRadius = 5
    return view
}()

private let trackFrameLayer = CALayer()
private let rulerTickLayer = CALayer()
private let rulerLabelLayer = CALayer()

private var lastEmittedLoadSignature: StripLoadSignature?

func configure(
    durationSeconds: Double,
    playheadTimeSeconds: Double,
    zoomScale: CanvasVideoTimelineScale? = nil
) {
    self.durationSeconds = CanvasVideoTimelineMath.sanitizedDurationSeconds(
        durationSeconds
    )
    self.zoomScale = zoomScale ?? Self.defaultZoomScale
    self.playheadTimeSeconds = CanvasVideoTimelineMath.clampedTimeSeconds(
        playheadTimeSeconds,
        durationSeconds: self.durationSeconds
    )
    applyStrip(nil)
    setNeedsLayout()
}

private func setupViewHierarchy() {
    addSubview(scrollView)
    scrollView.addSubview(contentView)
    contentView.addSubview(rulerView)
    contentView.addSubview(trackView)
    addSubview(playheadView)
    addSubview(playheadHandleView)

    addGestureRecognizer(pinchGestureRecognizer)
    addGestureRecognizer(tapGestureRecognizer)
}

private func renderTrackFrames() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    trackFrameLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
    guard let strip, strip.frames.isEmpty == false else {
        CATransaction.commit()
        return
    }

    for index in strip.frames.indices {
        let frame = strip.frames[index]
        let frameLayer = CALayer()
        frameLayer.contents = frame.cgImage
        frameLayer.contentsGravity = .resizeAspectFill
        frameLayer.masksToBounds = true
        // ... 省略 frame 布局计算
        trackFrameLayer.addSublayer(frameLayer)
    }
    CATransaction.commit()
}
```

### 修改后

- timeline view 自己持有 `timelineLoadingIndicator`、`timelinePlaceholderLabel` 和 `placeholderState`。
- `configure(...)` 会直接切到 `.loading(...)`，`applyStrip(...)` 会在 `hidden / message(...)` 间收口。
- 新增 `reusableFrameLayers`，`renderTrackFrames()` 改为 layer 复用，不再反复销毁重建。
- `tapGestureRecognizer.require(toFail: pinchGestureRecognizer)` 明确让 pinch 优先，减少手势互相吞噬。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSVideoTimelineView.swift
// 类型/函数: 属性区块 / configure(durationSeconds:playheadTimeSeconds:zoomScale:) / setPlaceholderState(_:) / setupViewHierarchy() / renderTrackFrames() / updatePlaceholderAppearance()
// 功能说明: 修改后 iOS 时间线视图自己承载 loading / 空态，占位语义不再散落在控制器里；同时复用缩略图 layer，降低滚动和缩放时的闪烁与重建成本。
private let timelineLoadingIndicator: UIActivityIndicatorView = {
    let indicator = UIActivityIndicatorView(style: .medium)
    indicator.translatesAutoresizingMaskIntoConstraints = false
    indicator.hidesWhenStopped = true
    indicator.isUserInteractionEnabled = false
    return indicator
}()
private let timelinePlaceholderLabel: UILabel = {
    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 14, weight: .medium)
    label.textColor = .secondaryLabel
    label.textAlignment = .center
    label.numberOfLines = 0
    label.isUserInteractionEnabled = false
    return label
}()

private var reusableFrameLayers: [CALayer] = []
private var placeholderState: CanvasVideoTimelinePlaceholderState = .loading(
    message: "Loading timeline..."
)

func configure(
    durationSeconds: Double,
    playheadTimeSeconds: Double,
    zoomScale: CanvasVideoTimelineScale? = nil
) {
    self.durationSeconds = CanvasVideoTimelineMath.sanitizedDurationSeconds(
        durationSeconds
    )
    self.zoomScale = zoomScale ?? Self.defaultZoomScale
    self.playheadTimeSeconds = CanvasVideoTimelineMath.clampedTimeSeconds(
        playheadTimeSeconds,
        durationSeconds: self.durationSeconds
    )
    setPlaceholderState(.loading(message: "Loading timeline..."))
    applyStrip(nil)
    setNeedsLayout()
}

func setPlaceholderState(_ state: CanvasVideoTimelinePlaceholderState) {
    placeholderState = state
    updatePlaceholderAppearance()
}

private func setupViewHierarchy() {
    addSubview(scrollView)
    scrollView.addSubview(contentView)
    contentView.addSubview(rulerView)
    contentView.addSubview(trackView)
    addSubview(playheadView)
    addSubview(playheadHandleView)
    addSubview(timelineLoadingIndicator)
    addSubview(timelinePlaceholderLabel)

    addGestureRecognizer(pinchGestureRecognizer)
    addGestureRecognizer(tapGestureRecognizer)
    tapGestureRecognizer.require(toFail: pinchGestureRecognizer)
}

private func renderTrackFrames() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    guard let strip, strip.frames.isEmpty == false else {
        hideReusableFrameLayers(startingAt: 0)
        CATransaction.commit()
        return
    }

    for index in strip.frames.indices {
        let frame = strip.frames[index]
        let frameLayer = reusableFrameLayer(at: index)
        frameLayer.contents = frame.cgImage
        frameLayer.contentsGravity = .resizeAspectFill
        frameLayer.contentsScale = frameContentsScale
        frameLayer.masksToBounds = true
        // ... 省略 frame 布局计算
        frameLayer.isHidden = false
    }

    hideReusableFrameLayers(startingAt: strip.frames.count)
    CATransaction.commit()
}

private func updatePlaceholderAppearance() {
    switch placeholderState {
    case .hidden:
        timelineLoadingIndicator.stopAnimating()
        timelinePlaceholderLabel.isHidden = true
        timelinePlaceholderLabel.text = nil
    case let .loading(message):
        timelineLoadingIndicator.startAnimating()
        timelinePlaceholderLabel.text = message
        timelinePlaceholderLabel.isHidden = message.isEmpty
    case let .message(message):
        timelineLoadingIndicator.stopAnimating()
        timelinePlaceholderLabel.text = message
        timelinePlaceholderLabel.isHidden = false
    }
}
```

## 修改四：macOS 时间线视图同样内聚占位态，并复用轨道 layer

### 修改前

- `macOSVideoTimelineView` 与 iOS 类似，也只渲染 timeline 本体，占位态仍依赖控制器外面的 `NSProgressIndicator` / `NSTextField`。
- `renderTrackFrames()` 每次渲染都整批删除 `trackFrameLayer.sublayers`。
- 轨道本体和 placeholder 语义没有统一收口，控制器和视图都要一起改。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSVideoTimelineView.swift
// 类型/函数: 属性区块 / configure(durationSeconds:playheadTimeSeconds:zoomScale:) / setupViewHierarchy() / renderTrackFrames()
// 功能说明: 修改前 macOS 时间线视图只负责轨道渲染和交互，loading / 空态仍然在控制器层额外叠一层宿主 UI。
private let playheadHandleView: NSView = {
    let view = NSView()
    view.translatesAutoresizingMaskIntoConstraints = false
    view.wantsLayer = true
    view.layer?.backgroundColor = NSColor.systemRed.cgColor
    view.layer?.cornerRadius = 5
    return view
}()

private let trackFrameLayer = CALayer()
private let rulerTickLayer = CALayer()
private let rulerLabelLayer = CALayer()

private var dragState: DragState?
private var lastMagnificationValue: CGFloat = 0
private var scrollInteractionEndWorkItem: DispatchWorkItem?

func configure(
    durationSeconds: Double,
    playheadTimeSeconds: Double,
    zoomScale: CanvasVideoTimelineScale? = nil
) {
    self.durationSeconds = CanvasVideoTimelineMath.sanitizedDurationSeconds(
        durationSeconds
    )
    self.zoomScale = zoomScale ?? Self.defaultZoomScale
    self.playheadTimeSeconds = CanvasVideoTimelineMath.clampedTimeSeconds(
        playheadTimeSeconds,
        durationSeconds: self.durationSeconds
    )
    applyStrip(nil)
    needsLayout = true
}

private func setupViewHierarchy() {
    scrollView.documentView = contentContainerView
    addSubview(scrollView)
    contentContainerView.addSubview(rulerView)
    contentContainerView.addSubview(trackView)
    addSubview(playheadView)
    addSubview(playheadHandleView)
}

private func renderTrackFrames() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    trackFrameLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
    guard let strip, strip.frames.isEmpty == false else {
        CATransaction.commit()
        return
    }

    for index in strip.frames.indices {
        let frame = strip.frames[index]
        let frameLayer = CALayer()
        frameLayer.contents = frame.cgImage
        frameLayer.contentsGravity = .resizeAspectFill
        frameLayer.contentsScale = layerContentsScale
        frameLayer.masksToBounds = true
        // ... 省略 frame 布局计算
        trackFrameLayer.addSublayer(frameLayer)
    }
    CATransaction.commit()
}
```

### 修改后

- macOS 侧也新增 `timelineLoadingIndicator`、`timelinePlaceholderLabel`、`placeholderState` 和 `reusableFrameLayers`。
- `configure(...)` / `applyStrip(...)` / `setPlaceholderState(_:)` 的职责与 iOS 对齐。
- `renderTrackFrames()` 改为复用 `CALayer`，同时把 placeholder 展示完全内聚到 view 内部。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSVideoTimelineView.swift
// 类型/函数: 属性区块 / configure(durationSeconds:playheadTimeSeconds:zoomScale:) / setPlaceholderState(_:) / setupViewHierarchy() / renderTrackFrames() / updatePlaceholderAppearance()
// 功能说明: 修改后 macOS 时间线视图和 iOS 使用同一套占位态语义，loading / 空态不再由控制器额外托管，轨道缩略图 layer 也改为按索引复用。
private let timelineLoadingIndicator: NSProgressIndicator = {
    let indicator = NSProgressIndicator()
    indicator.translatesAutoresizingMaskIntoConstraints = false
    indicator.style = .spinning
    indicator.controlSize = .regular
    indicator.isDisplayedWhenStopped = false
    return indicator
}()
private let timelinePlaceholderLabel: NSTextField = {
    let label = NSTextField(wrappingLabelWithString: "")
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 13, weight: .medium)
    label.textColor = .secondaryLabelColor
    label.alignment = .center
    label.maximumNumberOfLines = 2
    return label
}()

private var reusableFrameLayers: [CALayer] = []
private var placeholderState: CanvasVideoTimelinePlaceholderState = .loading(
    message: "Loading timeline..."
)

func configure(
    durationSeconds: Double,
    playheadTimeSeconds: Double,
    zoomScale: CanvasVideoTimelineScale? = nil
) {
    self.durationSeconds = CanvasVideoTimelineMath.sanitizedDurationSeconds(
        durationSeconds
    )
    self.zoomScale = zoomScale ?? Self.defaultZoomScale
    self.playheadTimeSeconds = CanvasVideoTimelineMath.clampedTimeSeconds(
        playheadTimeSeconds,
        durationSeconds: self.durationSeconds
    )
    setPlaceholderState(.loading(message: "Loading timeline..."))
    applyStrip(nil)
    needsLayout = true
}

func setPlaceholderState(_ state: CanvasVideoTimelinePlaceholderState) {
    placeholderState = state
    updatePlaceholderAppearance()
}

private func setupViewHierarchy() {
    scrollView.documentView = contentContainerView
    addSubview(scrollView)
    contentContainerView.addSubview(rulerView)
    contentContainerView.addSubview(trackView)
    addSubview(playheadView)
    addSubview(playheadHandleView)
    addSubview(timelineLoadingIndicator)
    addSubview(timelinePlaceholderLabel)
}

private func renderTrackFrames() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    guard let strip, strip.frames.isEmpty == false else {
        hideReusableFrameLayers(startingAt: 0)
        CATransaction.commit()
        return
    }

    for index in strip.frames.indices {
        let frame = strip.frames[index]
        let frameLayer = reusableFrameLayer(at: index)
        frameLayer.contents = frame.cgImage
        frameLayer.contentsGravity = .resizeAspectFill
        frameLayer.contentsScale = layerContentsScale
        frameLayer.masksToBounds = true
        // ... 省略 frame 布局计算
        frameLayer.isHidden = false
    }

    hideReusableFrameLayers(startingAt: strip.frames.count)
    CATransaction.commit()
}

private func updatePlaceholderAppearance() {
    switch placeholderState {
    case .hidden:
        timelineLoadingIndicator.stopAnimation(nil)
        timelinePlaceholderLabel.stringValue = ""
        timelinePlaceholderLabel.isHidden = true
    case let .loading(message):
        timelineLoadingIndicator.startAnimation(nil)
        timelinePlaceholderLabel.stringValue = message
        timelinePlaceholderLabel.isHidden = message.isEmpty
    case let .message(message):
        timelineLoadingIndicator.stopAnimation(nil)
        timelinePlaceholderLabel.stringValue = message
        timelinePlaceholderLabel.isHidden = false
    }
}
```

## 修改五：双端编辑器移除外置时间线 overlay，改由 timeline view 自己承载

### 修改前

- iOS 和 macOS 控制器各自都多维护一层 `timelineLoadingIndicator` + `timelinePlaceholderLabel`。
- `setupViewHierarchy()` / `setupConstraints()` / `scheduleTimelineStripLoad(...)` / `handleTimelineStripLoadResult(...)` 都要显式同步这层 overlay。
- 同一个 loading / 空态语义同时散落在 timeline view 和控制器宿主两边，后续改动容易重复。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSVideoDisplayFrameEditorViewController.swift
// 类型/函数: 属性区块 / setupViewHierarchy() / scheduleTimelineStripLoad(for:) / handleTimelineStripLoadResult(_:generation:)
// 功能说明: 修改前 iOS 控制器自己叠加一层 timeline loading / placeholder 视图，并在异步请求回调里手动控制显示与隐藏。
private let timelineLoadingIndicator: UIActivityIndicatorView = {
    let indicator = UIActivityIndicatorView(style: .medium)
    indicator.translatesAutoresizingMaskIntoConstraints = false
    indicator.hidesWhenStopped = true
    return indicator
}()
private let timelinePlaceholderLabel: UILabel = {
    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.text = "Loading timeline..."
    return label
}()

private func setupViewHierarchy() {
    view.addSubview(timelineView)
    view.addSubview(timelineLoadingIndicator)
    view.addSubview(timelinePlaceholderLabel)
    view.addSubview(setDisplayFrameButton)
}

private func scheduleTimelineStripLoad(
    for request: CanvasVideoTimelineStripRequest
) {
    if timelineView.hasRenderableStrip == false {
        timelinePlaceholderLabel.text = "Loading timeline..."
        timelinePlaceholderLabel.isHidden = false
        timelineLoadingIndicator.startAnimating()
    }
    // ... 省略异步请求逻辑
}

private func handleTimelineStripLoadResult(
    _ result: Result<CanvasVideoTimelineStrip, Error>,
    generation: Int
) {
    timelineLoadingIndicator.stopAnimating()
    switch result {
    case let .success(strip):
        timelineView.applyStrip(strip)
        timelinePlaceholderLabel.isHidden = true
    case let .failure(error):
        if timelineView.hasRenderableStrip == false {
            timelineView.applyStrip(nil)
            timelinePlaceholderLabel.isHidden = false
            timelinePlaceholderLabel.text = "Unable to load timeline."
            presentError(
                title: "Unable to Load Timeline",
                message: error.localizedDescription
            )
        }
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSVideoDisplayFrameEditorViewController.swift
// 类型/函数: 属性区块 / setupViewHierarchy() / scheduleTimelineStripLoad(for:) / handleTimelineStripLoadResult(_:generation:)
// 功能说明: 修改前 macOS 控制器也单独维护 NSProgressIndicator 和 NSTextField 作为时间线占位层，和视图本体存在重复职责。
private let timelineLoadingIndicator: NSProgressIndicator = {
    let indicator = NSProgressIndicator()
    indicator.translatesAutoresizingMaskIntoConstraints = false
    indicator.style = .spinning
    indicator.isDisplayedWhenStopped = false
    return indicator
}()
private let timelinePlaceholderLabel: NSTextField = {
    let label = NSTextField(wrappingLabelWithString: "Loading timeline...")
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
}()

private func setupViewHierarchy() {
    view.addSubview(timelineView)
    view.addSubview(timelineLoadingIndicator)
    view.addSubview(timelinePlaceholderLabel)
    view.addSubview(setDisplayFrameButton)
}

private func scheduleTimelineStripLoad(
    for request: CanvasVideoTimelineStripRequest
) {
    if timelineView.hasRenderableStrip == false {
        timelinePlaceholderLabel.stringValue = "Loading timeline..."
        timelinePlaceholderLabel.isHidden = false
        timelineLoadingIndicator.startAnimation(nil)
    }
    // ... 省略异步请求逻辑
}

private func handleTimelineStripLoadResult(
    _ result: Result<CanvasVideoTimelineStrip, Error>,
    generation: Int
) {
    timelineLoadingIndicator.stopAnimation(nil)
    switch result {
    case let .success(strip):
        timelineView.applyStrip(strip)
        timelinePlaceholderLabel.isHidden = true
    case let .failure(error):
        if timelineView.hasRenderableStrip == false {
            timelineView.applyStrip(nil)
            timelinePlaceholderLabel.isHidden = false
            timelinePlaceholderLabel.stringValue = "Unable to load timeline."
            presentError(
                title: "Unable to Load Timeline",
                message: error.localizedDescription
            )
        }
    }
}
```

### 修改后

- 双端控制器都只保留 `timelineView`，不再单独加 loading indicator 和 placeholder label。
- 请求前如果当前还没有可渲染 strip，就直接把 `timelineView` 切到 `.loading(...)`。
- 请求成功后由 `timelineView.applyStrip(...)` 决定隐藏占位态；如果 strip 为空则切到 `.message(...)`。
- 请求失败时只有在当前没有可渲染 strip 的情况下才切错误消息，避免已有轨道时被错误态闪掉。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSVideoDisplayFrameEditorViewController.swift
// 类型/函数: 属性区块 / setupViewHierarchy() / scheduleTimelineStripLoad(for:) / handleTimelineStripLoadResult(_:generation:)
// 功能说明: 修改后 iOS 控制器把时间线占位态完全交给 timelineView 自己承载，宿主只负责请求时机和错误提示。
private let timelineView: iOSVideoTimelineView = {
    let view = iOSVideoTimelineView()
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
}()

private func setupViewHierarchy() {
    view.addSubview(timelineView)
    view.addSubview(setDisplayFrameButton)
}

private func scheduleTimelineStripLoad(
    for request: CanvasVideoTimelineStripRequest
) {
    timelineLoadWorkItem?.cancel()
    timelineLoadGeneration += 1
    let generation = timelineLoadGeneration

    if timelineView.hasRenderableStrip == false {
        timelineView.setPlaceholderState(
            .loading(message: "Loading timeline...")
        )
    }

    // ... 省略异步请求逻辑
}

private func handleTimelineStripLoadResult(
    _ result: Result<CanvasVideoTimelineStrip, Error>,
    generation: Int
) {
    guard generation == timelineLoadGeneration else {
        return
    }

    switch result {
    case let .success(strip):
        timelineView.applyStrip(strip)
        if strip.frames.isEmpty {
            timelineView.setPlaceholderState(
                .message("No timeline frames available.")
            )
        }
    case let .failure(error):
        if timelineView.hasRenderableStrip == false {
            timelineView.applyStrip(nil)
            timelineView.setPlaceholderState(
                .message("Unable to load timeline.")
            )
            presentError(
                title: "Unable to Load Timeline",
                message: error.localizedDescription
            )
        }
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSVideoDisplayFrameEditorViewController.swift
// 类型/函数: 属性区块 / setupViewHierarchy() / scheduleTimelineStripLoad(for:) / handleTimelineStripLoadResult(_:generation:)
// 功能说明: 修改后 macOS 控制器和 iOS 一样，只保留 timelineView，自身不再托管额外的时间线占位层。
private let timelineView: macOSVideoTimelineView = {
    let view = macOSVideoTimelineView()
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
}()

private func setupViewHierarchy() {
    view.addSubview(timelineView)
    view.addSubview(setDisplayFrameButton)
}

private func scheduleTimelineStripLoad(
    for request: CanvasVideoTimelineStripRequest
) {
    timelineLoadWorkItem?.cancel()
    timelineLoadGeneration += 1
    let generation = timelineLoadGeneration

    if timelineView.hasRenderableStrip == false {
        timelineView.setPlaceholderState(
            .loading(message: "Loading timeline...")
        )
    }

    // ... 省略异步请求逻辑
}

private func handleTimelineStripLoadResult(
    _ result: Result<CanvasVideoTimelineStrip, Error>,
    generation: Int
) {
    guard generation == timelineLoadGeneration else {
        return
    }

    switch result {
    case let .success(strip):
        timelineView.applyStrip(strip)
        if strip.frames.isEmpty {
            timelineView.setPlaceholderState(
                .message("No timeline frames available.")
            )
        }
    case let .failure(error):
        if timelineView.hasRenderableStrip == false {
            timelineView.applyStrip(nil)
            timelineView.setPlaceholderState(
                .message("Unable to load timeline.")
            )
            presentError(
                title: "Unable to Load Timeline",
                message: error.localizedDescription
            )
        }
    }
}
```

## 修改六：补齐性能边界测试，并对齐测试 target 的默认 MainActor 隔离

### 修改前

- `CanvasVideoTimelineStripServiceTests` 只在 `setUp / tearDown` 重置 `timelineStripCache`。
- `testTimelineStripNormalizesDurationAndExpandsRequestedRangeWithOverscan()` 直接断言 `strip.frames.count == strip.request.targetFrameCount`，没有覆盖“帧数上限收口”。
- 还没有“重复取帧复用 decode session”与“超宽 viewport 被强制限帧”的测试。
- `CanvasVideoEditorPreviewStateTests` 没有显式 `@MainActor`，在工程默认隔离设置下会出现未来 Swift 6 模式的 actor warning。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasVideoTimelineStripServiceTests.swift
// 类型/函数: setUp() / tearDown() / testTimelineStripNormalizesDurationAndExpandsRequestedRangeWithOverscan()
// 功能说明: 修改前测试只验证了 timeline strip 缓存和基础几何，不覆盖 decode session 复用与极端 viewport 限帧。
override func setUp() {
    super.setUp()
    CanvasVideoFrameService.resetTimelineStripCache()
}

override func tearDown() {
    CanvasVideoFrameService.resetTimelineStripCache()
    super.tearDown()
}

func testTimelineStripNormalizesDurationAndExpandsRequestedRangeWithOverscan() throws {
    // ... 省略前置构造
    XCTAssertEqual(strip.frames.count, strip.request.targetFrameCount)
    XCTAssertTrue(strip.frames.isEmpty == false)
    XCTAssertTrue(framesAreMonotonic(strip.frames))
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasVideoEditorPreviewStateTests.swift
// 类型/函数: 测试类声明
// 功能说明: 修改前 preview state 测试类没有显式 MainActor 注解，在当前工程默认隔离配置下会出现 actor 隔离 warning。
final class CanvasVideoEditorPreviewStateTests: XCTestCase {
    // ... 省略其它测试
}
```

### 修改后

- `CanvasVideoTimelineStripServiceTests` 现在同时重置 `timelineStripCache` 和 `frameDecodeSessionCache`。
- `testTimelineStripNormalizesDurationAndExpandsRequestedRangeWithOverscan()` 改为断言“实际帧数 == min(targetFrameCount, maximumTimelineStripFrameCount)”。
- 新增 `testFrameDecodeSessionCacheReusesSessionForRepeatedFrameRequests()`。
- 新增 `testTimelineStripCapsFrameCountForExtremelyWideViewportRequests()`。
- `CanvasVideoEditorPreviewStateTests` 显式加上 `@MainActor`，对齐当前测试 target 的默认隔离设定。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasVideoTimelineStripServiceTests.swift
// 类型/函数: setUp() / tearDown() / testTimelineStripNormalizesDurationAndExpandsRequestedRangeWithOverscan() / testFrameDecodeSessionCacheReusesSessionForRepeatedFrameRequests() / testTimelineStripCapsFrameCountForExtremelyWideViewportRequests()
// 功能说明: 修改后测试把 decode session 复用和极端 viewport 限帧都补成了纯逻辑断言，避免 phase5 的性能收口后续被回退。
override func setUp() {
    super.setUp()
    CanvasVideoFrameService.resetTimelineStripCache()
    CanvasVideoFrameService.resetFrameDecodeSessionCache()
}

override func tearDown() {
    CanvasVideoFrameService.resetTimelineStripCache()
    CanvasVideoFrameService.resetFrameDecodeSessionCache()
    super.tearDown()
}

func testTimelineStripNormalizesDurationAndExpandsRequestedRangeWithOverscan() throws {
    // ... 省略前置构造
    XCTAssertEqual(
        strip.frames.count,
        min(
            strip.request.targetFrameCount,
            CanvasVideoFrameService.maximumTimelineStripFrameCount
        )
    )
}

func testFrameDecodeSessionCacheReusesSessionForRepeatedFrameRequests() throws {
    _ = try CanvasVideoFrameService.frameImage(
        from: videoURL,
        at: 0.2,
        quality: .posterCommit
    )
    _ = try CanvasVideoFrameService.frameImage(
        from: videoURL,
        at: 0.8,
        quality: .previewStripThumbnail(maxPixelSize: 48)
    )

    XCTAssertEqual(CanvasVideoFrameService.frameDecodeSessionEntryCount(), 1)
}

func testTimelineStripCapsFrameCountForExtremelyWideViewportRequests() throws {
    XCTAssertGreaterThan(
        request.targetFrameCount,
        CanvasVideoFrameService.maximumTimelineStripFrameCount
    )

    let strip = try CanvasVideoFrameService.timelineStrip(
        from: videoURL,
        request: request
    )

    XCTAssertEqual(
        strip.frames.count,
        CanvasVideoFrameService.maximumTimelineStripFrameCount
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasVideoEditorPreviewStateTests.swift
// 类型/函数: 测试类声明
// 功能说明: 修改后显式把 preview state 测试类对齐到 MainActor，避免未来 Swift 6 模式下的 actor 隔离告警升级为错误。
@MainActor
final class CanvasVideoEditorPreviewStateTests: XCTestCase {
    // ... 省略其它测试
}
```

## 验证结果

- `ReadLints` 检查以下文件，无新增诊断：
- `MyCanvas_Ver_0/Canvas/Video/CanvasVideoFrameService.swift`
- `MyCanvas_Ver_0/Canvas/Video/CanvasVideoTimeline.swift`
- `MyCanvas_Ver_0/Platform/iOS/iOSVideoTimelineView.swift`
- `MyCanvas_Ver_0/Platform/macOS/macOSVideoTimelineView.swift`
- `MyCanvas_Ver_0/Platform/iOS/iOSVideoDisplayFrameEditorViewController.swift`
- `MyCanvas_Ver_0/Platform/macOS/macOSVideoDisplayFrameEditorViewController.swift`
- `MyCanvas_Ver_0Tests/CanvasVideoTimelineStripServiceTests.swift`
- `MyCanvas_Ver_0Tests/CanvasVideoEditorPreviewStateTests.swift`
- macOS 测试通过：
- `xcodebuild test -scheme "MyCanvas_Ver_0" -destination "platform=macOS" -derivedDataPath "/tmp/MyCanvas_Ver_0-phase5-macos"`
- iOS 构建通过：
- `xcodebuild build -scheme "MyCanvas_Ver_0" -destination "generic/platform=iOS Simulator" -derivedDataPath "/tmp/MyCanvas_Ver_0-phase5-ios"`
- 新增测试通过：
- `CanvasVideoTimelineStripServiceTests.testFrameDecodeSessionCacheReusesSessionForRepeatedFrameRequests()`
- `CanvasVideoTimelineStripServiceTests.testTimelineStripCapsFrameCountForExtremelyWideViewportRequests()`
