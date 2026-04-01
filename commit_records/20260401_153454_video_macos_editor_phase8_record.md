# 20260401_153454_video_macos_editor_phase8_record

## 记录范围

- 记录内容：将 macOS 视频展示画面编辑页从阶段 6 的说明型壳子页升级为可实际选帧的 `AppKit` sheet。
- 记录内容：接入 `AVPlayerLayer` 预览区、`NSSlider` 进度条、横向 `NSCollectionView` 帧预览条和“Use Current Frame”提交按钮，保持默认不自动播放。
- 记录内容：补齐 macOS 端的 `ESC` / Cancel 关闭路径、滑杆拖动暂停恢复逻辑，以及底部帧条高亮选择反馈。
- 记录内容：接通 macOS 画板页到 `editorSession.commitVideoPosterFrame(...)` 的回写闭环，提交后立即刷新画板。
- 涉及文件：`MyCanvas_Ver_0/Platform/macOS/macOSVideoDisplayFrameEditorViewController.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 本记录不包含：阶段 9 的验证与收口。
- 本记录不包含：git commit / push。

## 修改一：macOS 视频编辑页从占位说明 sheet 升级为完整 AppKit 编辑页

### 修改前

- 页面只有标题、说明文字和关闭按钮。
- 可以看到视频元信息，但还不能播放、拖动时间、浏览帧条或提交展示帧。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSVideoDisplayFrameEditorViewController.swift
// 类型/函数: macOSVideoDisplayFrameEditorViewController.init(editorContext:) / viewDidLoad()
// 功能说明: 修改前页面只是阶段 6 的占位 sheet，用于展示共享 editorContext 元信息，尚未具备真正的视频编辑交互。
#if os(macOS)
import AppKit

final class macOSVideoDisplayFrameEditorViewController: NSViewController {
    private let editorContext: CanvasVideoEditorContext
    private let titleLabel: NSTextField = {
        let label = NSTextField(labelWithString: "Set Display Frame")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 24, weight: .semibold)
        return label
    }()
    private let detailLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 13, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        return label
    }()
    private let closeButton: NSButton = {
        let button = NSButton(title: "Done", target: nil, action: nil)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.controlSize = .large
        return button
    }()

    init(editorContext: CanvasVideoEditorContext) {
        self.editorContext = editorContext
        super.init(nibName: nil, bundle: nil)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = CGSize(width: 520, height: 240)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        detailLabel.stringValue =
            "Video item: \(editorContext.itemID.uuidString)\n" +
            "Source video: \(editorContext.sourceVideoFilename)\n" +
            "Current poster: \(editorContext.currentPosterFilename)\n" +
            "Poster time: \(formatVideoDisplayFrameEditorSeconds(editorContext.currentPosterTimeSeconds))\n" +
            "Duration: \(formatVideoDisplayFrameEditorSeconds(editorContext.durationSeconds))\n" +
            "Video size: \(Int(editorContext.naturalPixelSize.width)) x \(Int(editorContext.naturalPixelSize.height))\n" +
            "The shared frame extraction and poster persistence services are ready. The full platform UI will be added in the next phase."
    }
}
#endif
```

### 修改后

- 控制器引入 `AVFoundation`，直接持有 `AVPlayer`、`NSSlider`、`NSCollectionView` 和提交闭包。
- 页面固定为更大的编辑 sheet，并在首次显示时将焦点交给时间滑杆。
- 新增 `cancelOperation(_:)`，使 `ESC` 可以直接关闭当前 sheet。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSVideoDisplayFrameEditorViewController.swift
// 类型/函数: 属性定义 / init(editorContext:onCommitFrameImage:) / viewDidLoad() / viewDidAppear() / cancelOperation(_:)
// 功能说明: 修改后页面成为真正的 AppKit 视频编辑页，负责承载视频预览、时间控制、帧条选择、提交动作和键盘取消路径。
#if os(macOS)
import AVFoundation
import AppKit

final class macOSVideoDisplayFrameEditorViewController: NSViewController {
    private let editorContext: CanvasVideoEditorContext
    private let onCommitFrameImage: (CanvasVideoFrameImage) throws -> Void
    private let workerQueue = DispatchQueue(
        label: "MyCanvas.macOS.VideoDisplayFrameEditor",
        qos: .userInitiated
    )
    private let player = AVPlayer()
    private let closeButton: NSButton = {
        let button = NSButton(title: "Cancel", target: nil, action: nil)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.controlSize = .large
        button.bezelStyle = .rounded
        button.keyEquivalent = "\u{1b}"
        return button
    }()
    private let playerView: macOSVideoDisplayFramePlayerView = {
        let view = macOSVideoDisplayFramePlayerView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    private let timeSlider: macOSVideoDisplayFrameSlider = {
        let slider = macOSVideoDisplayFrameSlider(
            value: 0,
            minValue: 0,
            maxValue: 1,
            target: nil,
            action: nil
        )
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.controlSize = .regular
        slider.isContinuous = true
        return slider
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
    private let setDisplayFrameButton: NSButton = {
        let button = NSButton(title: "Use Current Frame", target: nil, action: nil)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.controlSize = .large
        button.bezelStyle = .rounded
        button.keyEquivalent = "\r"
        return button
    }()

    init(
        editorContext: CanvasVideoEditorContext,
        onCommitFrameImage: @escaping (CanvasVideoFrameImage) throws -> Void
    ) {
        self.editorContext = editorContext
        self.onCommitFrameImage = onCommitFrameImage
        currentPreviewTimeSeconds = editorContext.currentPosterTimeSeconds
        super.init(nibName: nil, bundle: nil)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = CGSize(width: 760, height: 620)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        configureCollectionView()
        configureButtons()
        configurePlayer()
        setupViewHierarchy()
        setupConstraints()
        applyInitialState()
        loadPreviewStrip()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard hasPerformedInitialSeek == false else {
            return
        }

        hasPerformedInitialSeek = true
        seekPreview(
            to: currentPreviewTimeSeconds,
            pausePlayback: true,
            updateSlider: true,
            updateSelection: true
        )
        view.window?.makeFirstResponder(timeSlider)
    }

    override func cancelOperation(_ sender: Any?) {
        dismiss(self)
    }
}
#endif
```

## 修改二：补齐播放区、滑杆、帧条与提交展示帧逻辑

### 修改前

- 页面内没有 `AVPlayerItem`、没有时间更新观察、没有帧条数据源，也没有提交展示帧的逻辑。
- 唯一交互只有点击 Done 关闭页面。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSVideoDisplayFrameEditorViewController.swift
// 类型/函数: viewDidLoad() / handleCloseButtonClick()
// 功能说明: 修改前只有静态说明文案和关闭操作，不能操作视频时间轴，也不能把某一帧提交为展示画面。
override func viewDidLoad() {
    super.viewDidLoad()
    preferredContentSize = CGSize(width: 520, height: 240)
    view.wantsLayer = true
    view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    detailLabel.stringValue =
        "Video item: \(editorContext.itemID.uuidString)\n" +
        "Source video: \(editorContext.sourceVideoFilename)\n" +
        "Current poster: \(editorContext.currentPosterFilename)\n" +
        "Poster time: \(formatVideoDisplayFrameEditorSeconds(editorContext.currentPosterTimeSeconds))\n" +
        "Duration: \(formatVideoDisplayFrameEditorSeconds(editorContext.durationSeconds))\n" +
        "Video size: \(Int(editorContext.naturalPixelSize.width)) x \(Int(editorContext.naturalPixelSize.height))\n" +
        "The shared frame extraction and poster persistence services are ready. The full platform UI will be added in the next phase."
    closeButton.target = self
    closeButton.action = #selector(handleCloseButtonClick)
}

@objc
private func handleCloseButtonClick() {
    dismiss(self)
}
```

### 修改后

- `configurePlayer()` 建立 `AVPlayerItem` 与 `AVPlayerLayer`，并通过 `addPeriodicTimeObserver` 驱动时间显示。
- `loadPreviewStrip()` 通过共享 `CanvasVideoFrameService.previewStrip(...)` 生成底部帧条。
- `macOSVideoDisplayFrameSlider` 在鼠标拖动开始/结束时回调，确保拖动滑杆时暂停，拖完后按需恢复播放。
- 点击提交按钮时，先用 `CanvasVideoFrameService.frameImage(..., quality: .posterCommit)` 抽取高质量帧，再通过闭包向外层提交。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSVideoDisplayFrameEditorViewController.swift
// 类型/函数: configureButtons() / configurePlayer() / loadPreviewStrip() / handleTimeSliderChanged(_:) / handleSetDisplayFrameButtonClick() / handleCommitFrameImageResult(_:)
// 功能说明: 修改后编辑页具备真实的视频预览、时间定位、帧条加载和展示帧提交能力，且默认保持静音与不自动播放。
private func configureButtons() {
    closeButton.target = self
    closeButton.action = #selector(handleCloseButtonClick)
    playPauseButton.target = self
    playPauseButton.action = #selector(handlePlayPauseButtonClick)
    timeSlider.target = self
    timeSlider.action = #selector(handleTimeSliderChanged(_:))
    timeSlider.onWillStartScrubbing = { [weak self] in
        guard let self else {
            return
        }

        self.shouldResumePlaybackAfterScrub =
            self.player.timeControlStatus == .playing
        self.pausePlayback()
    }
    timeSlider.onDidEndScrubbing = { [weak self] in
        guard let self else {
            return
        }

        if self.shouldResumePlaybackAfterScrub {
            self.player.play()
            self.updatePlayPauseButtonAppearance()
        }
        self.shouldResumePlaybackAfterScrub = false
    }
    setDisplayFrameButton.target = self
    setDisplayFrameButton.action = #selector(handleSetDisplayFrameButtonClick)
}

private func configurePlayer() {
    let playerItem = AVPlayerItem(url: editorContext.sourceVideoURL)
    player.replaceCurrentItem(with: playerItem)
    player.actionAtItemEnd = .pause
    // Poster selection does not need audio feedback, so keep playback muted.
    player.isMuted = true
    playerView.playerLayer.player = player
    playerView.playerLayer.videoGravity = .resizeAspect
    playbackEndedObserver = NotificationCenter.default.addObserver(
        forName: .AVPlayerItemDidPlayToEndTime,
        object: playerItem,
        queue: .main
    ) { [weak self] _ in
        self?.handlePlaybackDidReachEnd()
    }
    playerTimeObserver = player.addPeriodicTimeObserver(
        forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
        queue: .main
    ) { [weak self] time in
        self?.handlePlayerTimeUpdate(time)
    }
}

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

@objc
private func handleTimeSliderChanged(_ sender: NSSlider) {
    seekPreview(
        to: sender.doubleValue,
        pausePlayback: false,
        updateSlider: true,
        updateSelection: true
    )
}

@objc
private func handleSetDisplayFrameButtonClick() {
    guard isCommitting == false else {
        return
    }

    isCommitting = true
    pausePlayback()
    let commitTimeSeconds = currentPreviewTimeSeconds
    let sourceVideoURL = editorContext.sourceVideoURL
    workerQueue.async { [weak self] in
        let result = Result {
            try CanvasVideoFrameService.frameImage(
                from: sourceVideoURL,
                at: commitTimeSeconds,
                quality: .posterCommit
            )
        }
        DispatchQueue.main.async {
            self?.handleCommitFrameImageResult(result)
        }
    }
}

private func handleCommitFrameImageResult(
    _ result: Result<CanvasVideoFrameImage, Error>
) {
    switch result {
    case let .success(frameImage):
        do {
            try onCommitFrameImage(frameImage)
            dismiss(self)
        } catch {
            isCommitting = false
            presentError(
                title: "Unable to Set Display Frame",
                message: error.localizedDescription
            )
        }
    case let .failure(error):
        isCommitting = false
        presentError(
            title: "Unable to Set Display Frame",
            message: error.localizedDescription
        )
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSVideoDisplayFrameEditorViewController.swift
// 类型/函数: NSCollectionViewDataSource / NSCollectionViewDelegate / macOSVideoDisplayFrameSlider.mouseDown(with:) / macOSVideoDisplayFramePreviewItem.apply(frame:isHighlighted:)
// 功能说明: 修改后底部帧条会展示抽出的缩略图，允许点击某帧跳转，并对当前命中的时间点做高亮反馈；滑杆拖动也会进入受控的暂停/恢复流程。
extension macOSVideoDisplayFrameEditorViewController: NSCollectionViewDataSource {
    func collectionView(
        _ collectionView: NSCollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        previewFrames.count
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {
        guard
            let item = collectionView.makeItem(
                withIdentifier: macOSVideoDisplayFramePreviewItem.reuseIdentifier,
                for: indexPath
            ) as? macOSVideoDisplayFramePreviewItem,
            previewFrames.indices.contains(indexPath.item)
        else {
            return NSCollectionViewItem()
        }

        item.apply(
            frame: previewFrames[indexPath.item],
            isHighlighted: indexPath.item == selectedPreviewFrameIndex
        )
        return item
    }
}

extension macOSVideoDisplayFrameEditorViewController: NSCollectionViewDelegate {
    func collectionView(
        _ collectionView: NSCollectionView,
        didSelectItemsAt indexPaths: Set<IndexPath>
    ) {
        guard
            let indexPath = indexPaths.sorted().first,
            previewFrames.indices.contains(indexPath.item)
        else {
            return
        }

        let selectedFrame = previewFrames[indexPath.item]
        seekPreview(
            to: selectedFrame.timeSeconds,
            pausePlayback: true,
            updateSlider: true,
            updateSelection: true
        )
    }
}

private final class macOSVideoDisplayFrameSlider: NSSlider {
    var onWillStartScrubbing: (() -> Void)?
    var onDidEndScrubbing: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onWillStartScrubbing?()
        super.mouseDown(with: event)
        onDidEndScrubbing?()
    }
}

private final class macOSVideoDisplayFramePreviewItem: NSCollectionViewItem {
    func apply(
        frame: CanvasVideoPreviewStripFrame,
        isHighlighted: Bool
    ) {
        previewImageView.image = NSImage(
            cgImage: frame.cgImage,
            size: NSSize(
                width: frame.cgImage.width,
                height: frame.cgImage.height
            )
        )
        timeLabel.stringValue = formatVideoDisplayFrameEditorSeconds(
            frame.timeSeconds
        )
        updateSelectionAppearance(isHighlighted: isHighlighted)
    }
}
```

## 修改三：macOS 画板页接通展示帧提交回写闭环

### 修改前

- `macOSViewController` 只负责根据 `editorContext` 打开占位 sheet。
- 页面关闭后不会触发视频 poster 的回写，也不会刷新画板上的展示画面。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 类型/函数: presentVideoDisplayFrameEditor(for:)
// 功能说明: 修改前只负责把共享 editorContext 传给占位 sheet，还没有把“选择某一帧”回写到 scene / history / autosave 链路。
private func presentVideoDisplayFrameEditor(for itemID: CanvasItemID) {
    guard presentedViewControllers.isEmpty else {
        return
    }

    do {
        let editorContext = try editorSession.videoEditorContext(for: itemID)
        let editorViewController = macOSVideoDisplayFrameEditorViewController(
            editorContext: editorContext
        )
        presentAsSheet(editorViewController)
    } catch {
        presentVideoEditorError(message: error.localizedDescription)
    }
}
```

### 修改后

- 控制器创建编辑页时传入提交闭包，不再只负责展示 sheet。
- 闭包内部直接调用 `editorSession.commitVideoPosterFrame(...)`，让新 poster 继续复用阶段 6 建好的持久化和历史链路。
- 成功后立刻 `refreshCanvas(reason:)`，让画板上的视频封面即时刷新。
- 新增 `macOSVideoEditorFlowError.presenterUnavailable`，避免编辑页异步提交时宿主控制器已释放却没有明确错误。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 类型/函数: presentVideoDisplayFrameEditor(for:) / macOSVideoEditorFlowError
// 功能说明: 修改后 macOS 画板页负责承接编辑页提交的 frameImage，并把结果写回 editorSession，再刷新当前画板。
private func presentVideoDisplayFrameEditor(for itemID: CanvasItemID) {
    guard presentedViewControllers.isEmpty else {
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

private enum macOSVideoEditorFlowError: LocalizedError {
    case presenterUnavailable

    var errorDescription: String? {
        switch self {
        case .presenterUnavailable:
            "The canvas editor is no longer available."
        }
    }
}
```

## 验证

- 已对阶段 8 相关 Swift 文件执行静态诊断，`ReadLints` 返回无报错。
- 本次记录生成前，已复核当前文件内容与 `git diff`，确认变更边界集中在 macOS 视频编辑页本体和 macOS 控制器接线。
- 本次未执行整项目 `xcodebuild` 编译验证；当前环境仍指向 `/Library/Developer/CommandLineTools`，缺少完整 Xcode。
