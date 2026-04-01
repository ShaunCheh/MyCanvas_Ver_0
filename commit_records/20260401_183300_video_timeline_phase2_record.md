# 20260401_183300_video_timeline_phase2_record

## 记录范围

- 记录内容：实施 `@.cursor/plans/视频时间线轨道改造_4a257c8b.plan.md` 的 `phase2`，把 iOS 视频选帧页底部卡片式预览条替换为单轨时间线视图。
- 记录内容：保留顶部 `UISlider`，首版支持拖动轨道、点击跳转、双指缩放，并且和播放器共用同一份当前时间状态。
- 涉及文件：`MyCanvas_Ver_0/Platform/iOS/iOSVideoTimelineView.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/iOS/iOSVideoDisplayFrameEditorViewController.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- 本记录不包含：`git commit` / `git push`

## 修改一：新增独立的 iOS 单轨时间线视图

### 修改前

- 项目里还没有独立的 iOS 时间线视图文件。
- 底部选帧能力全部散落在 `iOSVideoDisplayFrameEditorViewController` 内，由 `UICollectionView + UICollectionViewFlowLayout` 直接渲染一排离散卡片。
- 这意味着“轨道绘制”“时间刻度”“拖动定位”“缩放锚点稳定”都没有单独的视图抽象承接。

### 修改后

- 新增 `iOSVideoTimelineView`，专门负责时间线展示和交互，不再让控制器自己维护底部轨道的渲染细节。
- 视图内部用 `UIScrollView` 承载横向内容，用 `CALayer` 平铺轨道缩略图，用单独的 ruler layer 画稀疏时间刻度。
- 新增点击跳转、拖动 scrub、双指缩放，并且缩放时以手势 anchor 对应的时间点为中心，避免缩放时轨道跳动。
- 视图只通过闭包向外报告 `playheadTime`、交互状态、以及当前 viewport 对应的 `CanvasVideoTimelineStripRequest`，不直接持有播放器或 session。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSVideoTimelineView.swift
// 类型/函数: iOSVideoTimelineView / makeVisibleStripRequest() / renderTrackFrames() / handleTap(_:) / handlePinch(_:)
// 功能说明: 修改后新增独立时间线视图，用 UIScrollView 承载可滚动轨道，用 CALayer 连续绘制缩略图，并把点击、拖动、缩放都转换成统一的时间线请求与播放头时间。
final class iOSVideoTimelineView: UIView {
    var onPlayheadTimeChangeRequested: ((Double) -> Void)?
    var onInteractionStateChanged: ((Bool) -> Void)?
    var onStripRequestChanged: ((CanvasVideoTimelineStripRequest) -> Void)?

    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = false
        scrollView.alwaysBounceHorizontal = false
        scrollView.bounces = false
        scrollView.delaysContentTouches = false
        scrollView.canCancelContentTouches = true
        scrollView.contentInsetAdjustmentBehavior = .never
        return scrollView
    }()
    private let trackView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .secondarySystemBackground
        view.layer.cornerRadius = 14
        view.layer.cornerCurve = .continuous
        view.layer.masksToBounds = true
        view.layer.borderWidth = 1
        view.layer.borderColor = UIColor.separator.cgColor
        return view
    }()

    private let trackFrameLayer = CALayer()
    private let rulerTickLayer = CALayer()
    private let rulerLabelLayer = CALayer()

    private let thumbnailWidth: Double = 52
    private let maxPixelSize = 180
    private let overscanWidthMultiplier = 0.75
    private static let defaultZoomScale = CanvasVideoTimelineScale(
        zoomScale: 4,
        basePointsPerSecond: 18,
        minZoomScale: 1,
        maxZoomScale: 32
    )

    private func makeVisibleStripRequest() -> CanvasVideoTimelineStripRequest? {
        guard bounds.width > 0 else {
            return nil
        }

        let geometryViewport = makeGeometryViewport()
        let centeredTrackX = min(
            max(Double(scrollView.contentOffset.x), 0),
            geometryViewport.contentWidth
        )
        let leftVisibleTrackX = max(centeredTrackX - Double(bounds.width / 2), 0)
        let rightVisibleTrackX = min(
            centeredTrackX + Double(bounds.width / 2),
            geometryViewport.contentWidth
        )
        let visibleTrackWidth = max(rightVisibleTrackX - leftVisibleTrackX, 1)
        let visibleViewport = CanvasVideoTimelineViewport(
            durationSeconds: durationSeconds,
            playheadTimeSeconds: geometryViewport.timeSeconds(
                forContentX: centeredTrackX
            ),
            zoomScale: zoomScale,
            visibleWidth: visibleTrackWidth,
            contentOffsetX: leftVisibleTrackX,
            minimumContentWidth: 1
        )
        return CanvasVideoTimelineStripRequest(
            viewport: visibleViewport,
            thumbnailWidth: thumbnailWidth,
            maxPixelSize: maxPixelSize,
            overscanWidth: visibleTrackWidth * overscanWidthMultiplier
        )
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
            let leftEdge: Double
            if index == strip.frames.startIndex {
                leftEdge = strip.request.requestedContentRange.lowerBound
            } else {
                leftEdge = (strip.frames[index - 1].contentX + frame.contentX) / 2
            }
            let rightEdge: Double
            if index == strip.frames.index(before: strip.frames.endIndex) {
                rightEdge = strip.request.requestedContentRange.upperBound
            } else {
                rightEdge = (frame.contentX + strip.frames[index + 1].contentX) / 2
            }

            let frameLayer = CALayer()
            frameLayer.contents = frame.cgImage
            frameLayer.contentsGravity = .resizeAspectFill
            frameLayer.masksToBounds = true
            frameLayer.frame = CGRect(
                x: leftEdge,
                y: 0,
                width: max(rightEdge - leftEdge, 1),
                height: trackView.bounds.height
            )
            trackFrameLayer.addSublayer(frameLayer)
        }
        CATransaction.commit()
    }

    @objc
    private func handleTap(_ gestureRecognizer: UITapGestureRecognizer) {
        guard gestureRecognizer.state == .ended, bounds.width > 0 else {
            return
        }

        beginInteractionIfNeeded()
        let location = gestureRecognizer.location(in: self)
        let targetOffsetX = Double(
            scrollView.contentOffset.x + location.x - bounds.midX
        )
        setProgrammaticScrollOffsetX(targetOffsetX, animated: false)
        updatePlayheadTimeFromScrollOffset(notify: true)
        emitStripRequestIfNeeded()
        endInteractionIfNeeded()
    }

    @objc
    private func handlePinch(_ gestureRecognizer: UIPinchGestureRecognizer) {
        guard bounds.width > 0 else {
            return
        }

        switch gestureRecognizer.state {
        case .began:
            pinchLastScale = max(gestureRecognizer.scale, 0.0001)
            beginInteractionIfNeeded()
        case .changed:
            let rawScale = max(gestureRecognizer.scale, 0.0001)
            let rawScaleDelta = rawScale / max(pinchLastScale, 0.0001)
            pinchLastScale = rawScale

            let anchorLocationX = gestureRecognizer.location(in: self).x
            let anchorTrackX = Double(
                scrollView.contentOffset.x + anchorLocationX - bounds.width / 2
            )
            let anchorTimeSeconds = makeGeometryViewport().timeSeconds(
                forContentX: anchorTrackX
            )
            zoomScale = zoomScale.withZoomScale(
                zoomScale.zoomScale * Double(rawScaleDelta)
            )
            updateGeometry(recenterOnPlayhead: false)

            let newAnchorTrackX = makeGeometryViewport().contentX(
                forTimeSeconds: anchorTimeSeconds
            )
            let targetOffsetX = newAnchorTrackX
                - Double(anchorLocationX - bounds.width / 2)
            setProgrammaticScrollOffsetX(targetOffsetX, animated: false)
            updatePlayheadTimeFromScrollOffset(notify: true)
            emitStripRequestIfNeeded()
        case .ended, .cancelled, .failed:
            pinchLastScale = 1
            endInteractionIfNeeded()
        default:
            break
        }
    }
}
```

## 修改二：把 iOS 编辑器从卡片式帧条切到单轨时间线，并统一时间状态

### 修改前

- 控制器直接持有 `previewStripCollectionView`、`previewFrames`、`selectedPreviewFrameIndex`、`isScrubbing`、`shouldResumePlaybackAfterScrub`。
- `loadPreviewStrip()` 固定请求 `10` 帧，底部预览条本质上是离散样本列表，不是连续轨道。
- 选中高亮依赖 `updateSelectedPreviewFrameIndex(...)` 和 `UICollectionView` 的 reload / scroll 行为，`slider` 和卡片条之间是控制器内部拼出来的同步关系。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSVideoDisplayFrameEditorViewController.swift
// 类型/函数: previewStripCollectionView / loadPreviewStrip() / updateSelectedPreviewFrameIndex(for:shouldScrollToSelection:) / handleTimeSliderTouchDown()
// 功能说明: 修改前底部预览条仍然是 UICollectionView 卡片列表，固定请求 10 帧，控制器自己维护高亮索引与 slider scrubbing 状态。
private let previewStripCollectionView: UICollectionView = {
    let layout = UICollectionViewFlowLayout()
    layout.scrollDirection = .horizontal
    layout.minimumInteritemSpacing = 12
    layout.minimumLineSpacing = 12
    let collectionView = UICollectionView(
        frame: .zero,
        collectionViewLayout: layout
    )
    collectionView.translatesAutoresizingMaskIntoConstraints = false
    collectionView.backgroundColor = .clear
    collectionView.showsHorizontalScrollIndicator = false
    return collectionView
}()
private let previewStripLoadingIndicator: UIActivityIndicatorView = {
    let indicator = UIActivityIndicatorView(style: .medium)
    indicator.translatesAutoresizingMaskIntoConstraints = false
    indicator.hidesWhenStopped = true
    return indicator
}()
private let previewStripPlaceholderLabel: UILabel = {
    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 14, weight: .medium)
    label.textColor = .secondaryLabel
    label.textAlignment = .center
    label.numberOfLines = 0
    label.text = "Loading preview frames..."
    return label
}()

private var previewFrames: [CanvasVideoPreviewStripFrame] = []
private var selectedPreviewFrameIndex: Int?
private var isScrubbing = false
private var shouldResumePlaybackAfterScrub = false

private func loadPreviewStrip() {
    previewStripLoadingIndicator.startAnimating()
    previewStripPlaceholderLabel.text = "Loading preview frames..."
    let sourceVideoURL = editorContext.sourceVideoURL
    workerQueue.async { [weak self] in
        let result = Result {
            try CanvasVideoFrameService.previewStrip(
                from: sourceVideoURL,
                frameCount: 10,
                maxPixelSize: 180
            )
        }
        DispatchQueue.main.async {
            self?.handlePreviewStripLoadResult(result)
        }
    }
}

private func updateSelectedPreviewFrameIndex(
    for timeSeconds: Double,
    shouldScrollToSelection: Bool
) {
    let nextIndex = makePreviewStripTimelineResult(
        for: timeSeconds
    ).highlightedSampleIndex
    guard selectedPreviewFrameIndex != nextIndex else {
        return
    }

    let indexPathsToReload = [selectedPreviewFrameIndex, nextIndex]
        .compactMap { index -> IndexPath? in
            guard let index else {
                return nil
            }
            return IndexPath(item: index, section: 0)
        }
    selectedPreviewFrameIndex = nextIndex
    if indexPathsToReload.isEmpty == false {
        previewStripCollectionView.reloadItems(at: indexPathsToReload)
    } else {
        previewStripCollectionView.reloadData()
    }
}

@objc
private func handleTimeSliderTouchDown() {
    isScrubbing = true
    shouldResumePlaybackAfterScrub = player.timeControlStatus == .playing
    pausePlayback()
}
```

### 修改后

- 控制器不再持有旧的卡片列表，而是引入 `timelineView` 和 `loadTimelineStrip` 闭包。
- `slider`、`timeline`、`AVPlayer` 现在只读写 `currentPreviewTimeSeconds` 这一份时间状态。
- `activeInteractionSources` 统一管理 `slider` 和 `timeline` 两种交互来源，避免再维护两套互相穿插的暂停/恢复逻辑。
- `scheduleTimelineStripLoad(...)` 改成按 `CanvasVideoTimelineStripRequest` 去抖加载，并用 generation 丢弃过期回包。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSVideoDisplayFrameEditorViewController.swift
// 类型/函数: configureTimelineView() / currentTimeSecondsDidChange(_:updateSlider:updateTimeline:) / beginPreviewInteraction(_:) / scheduleTimelineStripLoad(for:)
// 功能说明: 修改后控制器只负责时间状态与播放器协调，不再直接维护底部卡片列表，而是通过 timelineView 回调和 timeline strip 请求驱动连续轨道。
private let loadTimelineStrip: (
    CanvasVideoTimelineStripRequest
) throws -> CanvasVideoTimelineStrip
private let timelineView: iOSVideoTimelineView = {
    let view = iOSVideoTimelineView()
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
}()
private let timelineLoadingIndicator: UIActivityIndicatorView = {
    let indicator = UIActivityIndicatorView(style: .medium)
    indicator.translatesAutoresizingMaskIntoConstraints = false
    indicator.hidesWhenStopped = true
    return indicator
}()
private let timelinePlaceholderLabel: UILabel = {
    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 14, weight: .medium)
    label.textColor = .secondaryLabel
    label.textAlignment = .center
    label.numberOfLines = 0
    label.text = "Loading timeline..."
    return label
}()

private var activeInteractionSources: Set<PreviewInteractionSource> = []
private var shouldResumePlaybackAfterInteraction = false
private var timelineLoadGeneration = 0
private var timelineLoadWorkItem: DispatchWorkItem?

private func configureTimelineView() {
    timelineView.onPlayheadTimeChangeRequested = { [weak self] timeSeconds in
        guard let self else {
            return
        }

        self.seekPreview(
            to: timeSeconds,
            pausePlayback: false,
            updateSlider: true,
            updateTimeline: false
        )
    }
    timelineView.onInteractionStateChanged = { [weak self] isInteracting in
        guard let self else {
            return
        }

        if isInteracting {
            self.beginPreviewInteraction(.timeline)
        } else {
            self.endPreviewInteraction(.timeline)
        }
    }
    timelineView.onStripRequestChanged = { [weak self] request in
        self?.scheduleTimelineStripLoad(for: request)
    }
}

private func currentTimeSecondsDidChange(
    _ timeSeconds: Double,
    updateSlider: Bool,
    updateTimeline: Bool
) {
    currentPreviewTimeSeconds = clampedTimeSeconds(timeSeconds)
    currentTimeLabel.text = formatVideoDisplayFrameEditorSeconds(
        currentPreviewTimeSeconds
    )
    durationLabel.text = formatVideoDisplayFrameEditorSeconds(
        editorContext.durationSeconds
    )
    if updateSlider, activeInteractionSources.contains(.slider) == false {
        timeSlider.value = Float(currentPreviewTimeSeconds)
    }
    if updateTimeline {
        timelineView.setPlayheadTimeSeconds(
            currentPreviewTimeSeconds,
            animated: false
        )
    }
}

private func beginPreviewInteraction(_ source: PreviewInteractionSource) {
    let wasEmpty = activeInteractionSources.isEmpty
    activeInteractionSources.insert(source)
    guard wasEmpty else {
        return
    }

    shouldResumePlaybackAfterInteraction = player.timeControlStatus == .playing
    pausePlayback()
}

private func endPreviewInteraction(_ source: PreviewInteractionSource) {
    activeInteractionSources.remove(source)
    guard activeInteractionSources.isEmpty else {
        return
    }

    if shouldResumePlaybackAfterInteraction {
        player.play()
        updatePlayPauseButtonConfiguration()
    }
    shouldResumePlaybackAfterInteraction = false
}

private func scheduleTimelineStripLoad(
    for request: CanvasVideoTimelineStripRequest
) {
    timelineLoadWorkItem?.cancel()
    timelineLoadGeneration += 1
    let generation = timelineLoadGeneration

    if timelineView.hasRenderableStrip == false {
        timelinePlaceholderLabel.text = "Loading timeline..."
        timelinePlaceholderLabel.isHidden = false
        timelineLoadingIndicator.startAnimating()
    }

    var workItem: DispatchWorkItem?
    workItem = DispatchWorkItem { [weak self] in
        guard let self, workItem?.isCancelled == false else {
            return
        }

        let result = Result {
            try self.loadTimelineStrip(request)
        }
        DispatchQueue.main.async {
            self.handleTimelineStripLoadResult(
                result,
                generation: generation
            )
        }
    }
    timelineLoadWorkItem = workItem
    workerQueue.asyncAfter(
        deadline: .now() + 0.06,
        execute: workItem!
    )
}

@objc
private func handleTimeSliderTouchDown() {
    beginPreviewInteraction(.slider)
}

@objc
private func handleTimeSliderTouchEnded() {
    endPreviewInteraction(.slider)
}
```

## 修改三：把 iOS 展示入口接到共享 timeline strip 服务

### 修改前

- `iOSViewController` 在弹出视频选帧页时，只传入 `editorContext` 和最终提交封面帧的闭包。
- 这样编辑器页拿不到 `editorSession.videoTimelineStrip(for:request:)`，底部时间线也就无法从 session 层请求与当前 viewport 对应的 strip。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 类型/函数: presentVideoDisplayFrameEditor(for:)
// 功能说明: 修改前编辑器入口只注入 editorContext 和提交封面图回调，尚未把共享时间线 strip 能力传进视频编辑页。
private func presentVideoDisplayFrameEditor(for itemID: CanvasItemID) {
    guard presentedViewController == nil else {
        return
    }

    do {
        let editorContext = try editorSession.videoEditorContext(for: itemID)
        let editorViewController = iOSVideoDisplayFrameEditorViewController(
            editorContext: editorContext
        ) { [weak self] frameImage in
            guard let self else {
                throw iOSVideoEditorFlowError.presenterUnavailable
            }

            let updateResult = try self.editorSession.commitVideoPosterFrame(
                withID: itemID,
                frameImage: frameImage
            )
            self.requestCanvasRefresh(reason: updateResult.refreshReason)
        }
        present(editorViewController, animated: true)
    } catch {
        presentVideoEditorError(message: error.localizedDescription)
    }
}
```

### 修改后

- `iOSViewController` 现在显式把 `editorSession.videoTimelineStrip(for:request:)` 包成 `loadTimelineStrip` 闭包传给编辑器页。
- 编辑器页仍然只关心“按 request 取 strip”，不需要自己知道 session 之外的更深层细节。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 类型/函数: presentVideoDisplayFrameEditor(for:)
// 功能说明: 修改后展示入口把共享 timeline strip 能力一起注入编辑器页，让时间线视图能够按当前 viewport 和缩放级别请求底部轨道数据。
private func presentVideoDisplayFrameEditor(for itemID: CanvasItemID) {
    guard presentedViewController == nil else {
        return
    }

    do {
        let editorContext = try editorSession.videoEditorContext(for: itemID)
        let editorViewController = iOSVideoDisplayFrameEditorViewController(
            editorContext: editorContext,
            loadTimelineStrip: { [weak self] request in
                guard let self else {
                    throw iOSVideoEditorFlowError.presenterUnavailable
                }

                return try self.editorSession.videoTimelineStrip(
                    for: itemID,
                    request: request
                )
            }
        ) { [weak self] frameImage in
            guard let self else {
                throw iOSVideoEditorFlowError.presenterUnavailable
            }

            let updateResult = try self.editorSession.commitVideoPosterFrame(
                withID: itemID,
                frameImage: frameImage
            )
            self.requestCanvasRefresh(reason: updateResult.refreshReason)
        }
        present(editorViewController, animated: true)
    } catch {
        presentVideoEditorError(message: error.localizedDescription)
    }
}
```

## 验证结果

- `ReadLints` 检查以下文件，无新增诊断：
- `MyCanvas_Ver_0/Platform/iOS/iOSVideoTimelineView.swift`
- `MyCanvas_Ver_0/Platform/iOS/iOSVideoDisplayFrameEditorViewController.swift`
- `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- iOS 构建验证通过：
- `xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -sdk iphonesimulator -derivedDataPath "/tmp/MyCanvas_Ver_0-phase2-iosbuild" build`
- macOS 回归测试通过：
- `xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=macOS" -derivedDataPath "/tmp/MyCanvas_Ver_0-phase2-macos-test" test`
