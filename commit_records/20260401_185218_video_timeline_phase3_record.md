# 20260401_185218_video_timeline_phase3_record

## 记录范围

- 记录内容：实施 `@.cursor/plans/视频时间线轨道改造_4a257c8b.plan.md` 的 `phase3`，把 macOS 视频选帧页底部卡片式预览条替换为单轨时间线视图。
- 记录内容：保留顶部 `NSSlider`，支持拖动轨道、点击跳转、触控板缩放，并且和播放器共用同一份当前时间状态。
- 涉及文件：`MyCanvas_Ver_0/Platform/macOS/macOSVideoTimelineView.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/macOS/macOSVideoDisplayFrameEditorViewController.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 本记录不包含：`git commit` / `git push`

## 修改一：新增独立的 macOS 单轨时间线视图

### 修改前

- 项目里还没有独立的 macOS 时间线视图文件。
- 底部轨道的滚动、渲染、点击选帧、缩放入口都还没有从控制器里抽离出来。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSVideoTimelineView.swift
// 类型/函数: 文件不存在
// 功能说明: 修改前项目中还没有独立的 macOS 单轨时间线视图，底部时间线能力全部依附在编辑器控制器内部。
```

### 修改后

- 新增 `macOSVideoTimelineView`，专门负责轨道渲染和交互，不再让控制器直接维护底部卡片预览条。
- 视图内部用 `NSScrollView` 承载横向内容，用 `CALayer` 平铺缩略图轨道，用 ruler layer 绘制稀疏时间刻度。
- 新增鼠标按下拖动、点击跳转、触控板 `magnify` 缩放，并且缩放时以手势 anchor 的时间点为中心，避免缩放跳动。
- 视图只通过闭包向外上报当前播放头时间、交互状态和 `CanvasVideoTimelineStripRequest`，不直接耦合播放器或 session。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSVideoTimelineView.swift
// 类型/函数: macOSVideoTimelineView / makeVisibleStripRequest() / renderTrackFrames() / handlePointerDragged(at:) / handleMagnification(_:at:state:)
// 功能说明: 修改后新增独立的 macOS 时间线视图，用 NSScrollView 承载连续轨道，用 CALayer 渲染缩略图，并把拖动、点击、缩放统一折叠为时间线 strip 请求与播放头时间变更。
#if os(macOS)
import AppKit
import QuartzCore

final class macOSVideoTimelineView: NSView {
    var onPlayheadTimeChangeRequested: ((Double) -> Void)?
    var onInteractionStateChanged: ((Bool) -> Void)?
    var onStripRequestChanged: ((CanvasVideoTimelineStripRequest) -> Void)?

    private let scrollView: macOSVideoTimelineScrollView = {
        let scrollView = macOSVideoTimelineScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.horizontalScrollElasticity = .none
        scrollView.verticalScrollElasticity = .none
        return scrollView
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
            max(Double(currentContentOffsetX), 0),
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
            frameLayer.contentsScale = layerContentsScale
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

    private func handlePointerDragged(at location: CGPoint) {
        guard var dragState else {
            return
        }

        let deltaX = dragState.startLocationX - location.x
        if abs(deltaX) > 0.5 {
            dragState.hasMoved = true
        }
        self.dragState = dragState

        let targetOffsetX = dragState.startContentOffsetX + deltaX
        setProgrammaticContentOffsetX(Double(targetOffsetX))
        updatePlayheadTimeFromContentOffset(notify: true)
        emitStripRequestIfNeeded()
    }

    private func handleMagnification(
        _ magnification: CGFloat,
        at location: CGPoint,
        state: NSGestureRecognizer.State
    ) {
        guard bounds.width > 0 else {
            return
        }

        switch state {
        case .began:
            scrollInteractionEndWorkItem?.cancel()
            lastMagnificationValue = magnification
            beginInteractionIfNeeded()
        case .changed:
            let magnificationDelta = magnification - lastMagnificationValue
            lastMagnificationValue = magnification
            let scaleDelta = 1 + magnificationDelta
            guard scaleDelta.isFinite, scaleDelta > 0 else {
                return
            }

            let anchorTrackX = Double(
                currentContentOffsetX + location.x - bounds.width / 2
            )
            let anchorTimeSeconds = makeGeometryViewport().timeSeconds(
                forContentX: anchorTrackX
            )
            zoomScale = zoomScale.withZoomScale(
                zoomScale.zoomScale * Double(scaleDelta)
            )
            updateGeometry(recenterOnPlayhead: false)

            let newAnchorTrackX = makeGeometryViewport().contentX(
                forTimeSeconds: anchorTimeSeconds
            )
            let targetOffsetX = newAnchorTrackX
                - Double(location.x - bounds.width / 2)
            setProgrammaticContentOffsetX(targetOffsetX)
            updatePlayheadTimeFromContentOffset(notify: true)
            emitStripRequestIfNeeded()
        case .ended, .cancelled, .failed:
            lastMagnificationValue = 0
            endInteractionIfNeeded()
        default:
            break
        }
    }
}
#endif
```

## 修改二：把 macOS 编辑器从卡片式预览条切到单轨时间线，并统一时间状态

### 修改前

- 控制器直接持有 `previewStripLayout`、`previewStripCollectionView`、`previewStripScrollView`、`previewFrames`、`selectedPreviewFrameIndex`。
- `loadPreviewStrip()` 固定请求 `10` 帧，底部仍然是 `NSCollectionView` 卡片列表，不是连续轨道。
- 顶部 slider、底部预览条和播放器之间的同步依赖 `updateSelectedPreviewFrameIndex(...)` 和 collection reload/select。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSVideoDisplayFrameEditorViewController.swift
// 类型/函数: previewStripScrollView / loadPreviewStrip() / updateSelectedPreviewFrameIndex(for:shouldScrollToSelection:) / handleTimeSliderChanged(_:)
// 功能说明: 修改前 macOS 编辑页仍然依赖 NSCollectionView 卡片式预览条，固定请求 10 帧，并用选中索引同步底部高亮与顶部时间状态。
private let previewStripLayout: NSCollectionViewFlowLayout = {
    let layout = NSCollectionViewFlowLayout()
    layout.scrollDirection = .horizontal
    layout.minimumInteritemSpacing = 12
    layout.minimumLineSpacing = 12
    layout.sectionInset = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
    layout.itemSize = NSSize(width: 92, height: 84)
    return layout
}()
private lazy var previewStripCollectionView: NSCollectionView = {
    let collectionView = NSCollectionView(
        frame: NSRect(x: 0, y: 0, width: 640, height: 92)
    )
    collectionView.backgroundColors = [.clear]
    collectionView.collectionViewLayout = previewStripLayout
    collectionView.delegate = self
    collectionView.dataSource = self
    collectionView.isSelectable = true
    collectionView.register(
        macOSVideoDisplayFramePreviewItem.self,
        forItemWithIdentifier: macOSVideoDisplayFramePreviewItem.reuseIdentifier
    )
    return collectionView
}()
private lazy var previewStripScrollView: NSScrollView = {
    let scrollView = NSScrollView()
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.drawsBackground = false
    scrollView.borderType = .noBorder
    scrollView.hasHorizontalScroller = true
    scrollView.hasVerticalScroller = false
    scrollView.autohidesScrollers = true
    scrollView.documentView = previewStripCollectionView
    return scrollView
}()

private var previewFrames: [CanvasVideoPreviewStripFrame] = []
private var selectedPreviewFrameIndex: Int?

private func loadPreviewStrip() {
    previewStripLoadingIndicator.startAnimation(nil)
    previewStripPlaceholderLabel.stringValue = "Loading preview frames..."
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
        previewStripCollectionView.reloadItems(at: Set(indexPathsToReload))
    } else {
        previewStripCollectionView.reloadData()
    }
}

@objc
private func handleTimeSliderChanged(_ sender: NSSlider) {
    seekPreview(
        to: sender.doubleValue,
        pausePlayback: false,
        updateSlider: true,
        updateSelection: true
    )
}
```

### 修改后

- 控制器不再持有旧的 collection view 预览条，而是引入 `timelineView` 和 `loadTimelineStrip` 闭包。
- `currentPreviewTimeSeconds` 成为 macOS 编辑页唯一的当前时间源，统一驱动 `NSSlider`、时间线和播放器。
- `activeInteractionSources` 统一管理 `slider` 与 `timeline` 两类交互来源，替代旧的卡片高亮和独立 scrub 恢复逻辑。
- `scheduleTimelineStripLoad(...)` 改成基于 `CanvasVideoTimelineStripRequest` 的去抖加载，并用 generation 丢弃过期回包。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSVideoDisplayFrameEditorViewController.swift
// 类型/函数: configureTimelineView() / currentTimeSecondsDidChange(_:updateSlider:updateTimeline:) / beginPreviewInteraction(_:) / scheduleTimelineStripLoad(for:)
// 功能说明: 修改后 macOS 编辑器不再直接维护卡片式预览条，而是通过 timelineView 和 timeline strip 请求驱动底部连续轨道，并把 slider、时间线、播放器统一到同一份时间状态。
private let loadTimelineStrip: (
    CanvasVideoTimelineStripRequest
) throws -> CanvasVideoTimelineStrip
private let timelineView: macOSVideoTimelineView = {
    let view = macOSVideoTimelineView()
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
}()
private let timelineLoadingIndicator: NSProgressIndicator = {
    let indicator = NSProgressIndicator()
    indicator.translatesAutoresizingMaskIntoConstraints = false
    indicator.style = .spinning
    indicator.controlSize = .regular
    indicator.isDisplayedWhenStopped = false
    return indicator
}()
private let timelinePlaceholderLabel: NSTextField = {
    let label = NSTextField(wrappingLabelWithString: "Loading timeline...")
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 13, weight: .medium)
    label.textColor = .secondaryLabelColor
    label.alignment = .center
    label.maximumNumberOfLines = 2
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
    currentTimeLabel.stringValue = formatVideoDisplayFrameEditorSeconds(
        currentPreviewTimeSeconds
    )
    durationLabel.stringValue = formatVideoDisplayFrameEditorSeconds(
        editorContext.durationSeconds
    )
    if updateSlider, activeInteractionSources.contains(.slider) == false {
        timeSlider.doubleValue = currentPreviewTimeSeconds
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
        updatePlayPauseButtonAppearance()
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
        timelinePlaceholderLabel.stringValue = "Loading timeline..."
        timelinePlaceholderLabel.isHidden = false
        timelineLoadingIndicator.startAnimation(nil)
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

private func handleTimelineStripLoadResult(
    _ result: Result<CanvasVideoTimelineStrip, Error>,
    generation: Int
) {
    guard generation == timelineLoadGeneration else {
        return
    }

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

## 修改三：把 macOS 展示入口接到共享 timeline strip 服务

### 修改前

- `macOSViewController` 在弹出视频选帧 sheet 时，只传入 `editorContext` 和提交封面图的回调。
- 这样编辑器页拿不到 `editorSession.videoTimelineStrip(for:request:)`，也就无法按当前 viewport 和缩放级别请求时间线 strip。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 类型/函数: presentVideoDisplayFrameEditor(for:)
// 功能说明: 修改前 macOS 展示入口只注入 editorContext 和提交封面图回调，尚未把共享 timeline strip 能力传进视频编辑页。
private func presentVideoDisplayFrameEditor(for itemID: CanvasItemID) {
    guard presentedViewControllers?.isEmpty != false else {
        return
    }

    do {
        let editorContext = try editorSession.videoEditorContext(for: itemID)
        let editorViewController = macOSVideoDisplayFrameEditorViewController(
            editorContext: editorContext
        ) { [weak self] frameImage in
            guard let self else {
                throw macOSVideoEditorFlowError.presenterUnavailable
            }

            let updateResult = try self.editorSession.commitVideoPosterFrame(
                withID: itemID,
                frameImage: frameImage
            )
            self.refreshCanvas(reason: updateResult.refreshReason)
        }
        presentAsSheet(editorViewController)
    } catch {
        presentVideoEditorError(message: error.localizedDescription)
    }
}
```

### 修改后

- `macOSViewController` 现在显式把 `editorSession.videoTimelineStrip(for:request:)` 包成 `loadTimelineStrip` 闭包传给编辑器页。
- 编辑器页仍然只关心“按 request 取 strip”，不需要自己知道 session 以外的更深层依赖。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 类型/函数: presentVideoDisplayFrameEditor(for:)
// 功能说明: 修改后 macOS 展示入口把共享 timeline strip 能力一起注入编辑器页，让底部单轨时间线可以按当前 viewport 和缩放级别请求轨道数据。
private func presentVideoDisplayFrameEditor(for itemID: CanvasItemID) {
    guard presentedViewControllers?.isEmpty != false else {
        return
    }

    do {
        let editorContext = try editorSession.videoEditorContext(for: itemID)
        let editorViewController = macOSVideoDisplayFrameEditorViewController(
            editorContext: editorContext,
            loadTimelineStrip: { [weak self] request in
                guard let self else {
                    throw macOSVideoEditorFlowError.presenterUnavailable
                }

                return try self.editorSession.videoTimelineStrip(
                    for: itemID,
                    request: request
                )
            }
        ) { [weak self] frameImage in
            guard let self else {
                throw macOSVideoEditorFlowError.presenterUnavailable
            }

            let updateResult = try self.editorSession.commitVideoPosterFrame(
                withID: itemID,
                frameImage: frameImage
            )
            self.refreshCanvas(reason: updateResult.refreshReason)
        }
        presentAsSheet(editorViewController)
    } catch {
        presentVideoEditorError(message: error.localizedDescription)
    }
}
```

## 验证结果

- `ReadLints` 检查以下文件，无新增诊断：
- `MyCanvas_Ver_0/Platform/macOS/macOSVideoTimelineView.swift`
- `MyCanvas_Ver_0/Platform/macOS/macOSVideoDisplayFrameEditorViewController.swift`
- `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- macOS 回归测试通过：
- `xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=macOS" -derivedDataPath "/tmp/MyCanvas_Ver_0-phase3-macos-test" test`
- iOS 构建验证通过：
- `xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -sdk iphonesimulator -derivedDataPath "/tmp/MyCanvas_Ver_0-phase3-iosbuild" build`
