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
    private let titleLabel: NSTextField = {
        let label = NSTextField(labelWithString: "Set Display Frame")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 24, weight: .semibold)
        return label
    }()
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
    private let playPauseButton: NSButton = {
        let button = NSButton(title: "", target: nil, action: nil)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 24
        button.layer?.masksToBounds = true
        button.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.45).cgColor
        button.contentTintColor = .white
        button.imagePosition = .imageOnly
        return button
    }()
    private let currentTimeLabel: NSTextField = {
        let label = NSTextField(labelWithString: "0.00s")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .left
        return label
    }()
    private let durationLabel: NSTextField = {
        let label = NSTextField(labelWithString: "0.00s")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .right
        return label
    }()
    private let timeSlider: macOSVideoDisplayFrameSlider = {
        let slider = macOSVideoDisplayFrameSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.controlSize = .regular
        slider.isContinuous = true
        return slider
    }()
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
        let collectionView = NSCollectionView(frame: NSRect(x: 0, y: 0, width: 640, height: 92))
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
    private let previewStripLoadingIndicator: NSProgressIndicator = {
        let indicator = NSProgressIndicator()
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.style = .spinning
        indicator.controlSize = .regular
        indicator.isDisplayedWhenStopped = false
        return indicator
    }()
    private let previewStripPlaceholderLabel: NSTextField = {
        let label = NSTextField(wrappingLabelWithString: "Loading preview frames...")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.maximumNumberOfLines = 2
        return label
    }()
    private let setDisplayFrameButton: NSButton = {
        let button = NSButton(title: "Use Current Frame", target: nil, action: nil)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.controlSize = .large
        button.bezelStyle = .rounded
        button.keyEquivalent = "\r"
        return button
    }()

    private var previewFrames: [CanvasVideoPreviewStripFrame] = []
    private var currentPreviewTimeSeconds: Double
    private var selectedPreviewFrameIndex: Int?
    private var shouldResumePlaybackAfterScrub = false
    private var hasPerformedInitialSeek = false
    private var isCommitting = false {
        didSet {
            updateCommitButtonAppearance()
        }
    }
    private var playerTimeObserver: Any?
    private var playbackEndedObserver: NSObjectProtocol?

    init(
        editorContext: CanvasVideoEditorContext,
        onCommitFrameImage: @escaping (CanvasVideoFrameImage) throws -> Void
    ) {
        self.editorContext = editorContext
        self.onCommitFrameImage = onCommitFrameImage
        currentPreviewTimeSeconds = editorContext.currentPosterTimeSeconds
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let playerTimeObserver {
            player.removeTimeObserver(playerTimeObserver)
        }
        if let playbackEndedObserver {
            NotificationCenter.default.removeObserver(playbackEndedObserver)
        }
    }

    override func loadView() {
        view = NSView()
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

    override func viewWillDisappear() {
        super.viewWillDisappear()
        pausePlayback()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updatePreviewStripCollectionViewFrame()
    }

    override func cancelOperation(_ sender: Any?) {
        dismiss(self)
    }

    private func configureCollectionView() {
        previewStripCollectionView.backgroundColors = [.clear]
    }

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
        updatePlayPauseButtonAppearance()
        updateCommitButtonAppearance()
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

    private func setupViewHierarchy() {
        playerView.addSubview(playPauseButton)
        view.addSubview(titleLabel)
        view.addSubview(closeButton)
        view.addSubview(playerView)
        view.addSubview(currentTimeLabel)
        view.addSubview(timeSlider)
        view.addSubview(durationLabel)
        view.addSubview(previewStripScrollView)
        view.addSubview(previewStripLoadingIndicator)
        view.addSubview(previewStripPlaceholderLabel)
        view.addSubview(setDisplayFrameButton)
    }

    private func setupConstraints() {
        let safeArea = view.safeAreaLayoutGuide
        let videoAspectRatio = max(
            min(
                editorContext.naturalPixelSize.height /
                    max(editorContext.naturalPixelSize.width, 1),
                1.25
            ),
            0.56
        )

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: 24),
            closeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: -24),
            titleLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: closeButton.leadingAnchor,
                constant: -12
            ),

            playerView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 24),
            playerView.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: 24),
            playerView.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: -24),
            playerView.heightAnchor.constraint(
                equalTo: playerView.widthAnchor,
                multiplier: videoAspectRatio
            ),
            playerView.heightAnchor.constraint(
                lessThanOrEqualTo: safeArea.heightAnchor,
                multiplier: 0.48
            ),

            playPauseButton.centerXAnchor.constraint(equalTo: playerView.centerXAnchor),
            playPauseButton.centerYAnchor.constraint(equalTo: playerView.centerYAnchor),
            playPauseButton.widthAnchor.constraint(equalToConstant: 48),
            playPauseButton.heightAnchor.constraint(equalToConstant: 48),

            currentTimeLabel.topAnchor.constraint(equalTo: playerView.bottomAnchor, constant: 20),
            currentTimeLabel.leadingAnchor.constraint(equalTo: playerView.leadingAnchor),
            currentTimeLabel.widthAnchor.constraint(equalToConstant: 72),

            durationLabel.centerYAnchor.constraint(equalTo: currentTimeLabel.centerYAnchor),
            durationLabel.trailingAnchor.constraint(equalTo: playerView.trailingAnchor),
            durationLabel.widthAnchor.constraint(equalToConstant: 72),

            timeSlider.centerYAnchor.constraint(equalTo: currentTimeLabel.centerYAnchor),
            timeSlider.leadingAnchor.constraint(equalTo: currentTimeLabel.trailingAnchor, constant: 12),
            timeSlider.trailingAnchor.constraint(equalTo: durationLabel.leadingAnchor, constant: -12),

            previewStripScrollView.topAnchor.constraint(equalTo: currentTimeLabel.bottomAnchor, constant: 18),
            previewStripScrollView.leadingAnchor.constraint(equalTo: playerView.leadingAnchor),
            previewStripScrollView.trailingAnchor.constraint(equalTo: playerView.trailingAnchor),
            previewStripScrollView.heightAnchor.constraint(equalToConstant: 108),

            previewStripLoadingIndicator.centerXAnchor.constraint(
                equalTo: previewStripScrollView.centerXAnchor
            ),
            previewStripLoadingIndicator.centerYAnchor.constraint(
                equalTo: previewStripScrollView.centerYAnchor
            ),

            previewStripPlaceholderLabel.centerXAnchor.constraint(
                equalTo: previewStripScrollView.centerXAnchor
            ),
            previewStripPlaceholderLabel.centerYAnchor.constraint(
                equalTo: previewStripScrollView.centerYAnchor
            ),
            previewStripPlaceholderLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: previewStripScrollView.leadingAnchor,
                constant: 12
            ),
            previewStripPlaceholderLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: previewStripScrollView.trailingAnchor,
                constant: -12
            ),

            setDisplayFrameButton.topAnchor.constraint(
                equalTo: previewStripScrollView.bottomAnchor,
                constant: 22
            ),
            setDisplayFrameButton.leadingAnchor.constraint(equalTo: playerView.leadingAnchor),
            setDisplayFrameButton.trailingAnchor.constraint(equalTo: playerView.trailingAnchor),
            setDisplayFrameButton.heightAnchor.constraint(equalToConstant: 36),
            setDisplayFrameButton.bottomAnchor.constraint(
                lessThanOrEqualTo: safeArea.bottomAnchor,
                constant: -20
            )
        ])
    }

    private func applyInitialState() {
        currentTimeSecondsDidChange(
            currentPreviewTimeSeconds,
            updateSlider: true,
            updateSelection: false
        )
        timeSlider.maxValue = max(editorContext.durationSeconds, 0.001)
        let hasPlayableDuration = editorContext.durationSeconds > 0
        timeSlider.isEnabled = hasPlayableDuration
        playPauseButton.isEnabled = hasPlayableDuration
        previewStripPlaceholderLabel.isHidden = false
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

    private func handlePreviewStripLoadResult(
        _ result: Result<CanvasVideoPreviewStrip, Error>
    ) {
        previewStripLoadingIndicator.stopAnimation(nil)
        switch result {
        case let .success(previewStrip):
            previewFrames = previewStrip.frames
            previewStripCollectionView.reloadData()
            updatePreviewStripCollectionViewFrame()
            previewStripPlaceholderLabel.isHidden = previewFrames.isEmpty == false
            if previewFrames.isEmpty {
                previewStripPlaceholderLabel.stringValue = "No preview frames available."
            }
            updateSelectedPreviewFrameIndex(
                for: currentPreviewTimeSeconds,
                shouldScrollToSelection: false
            )
        case let .failure(error):
            previewFrames = []
            previewStripCollectionView.reloadData()
            updatePreviewStripCollectionViewFrame()
            previewStripPlaceholderLabel.isHidden = false
            previewStripPlaceholderLabel.stringValue = "Unable to load preview frames."
            presentError(
                title: "Unable to Load Preview Frames",
                message: error.localizedDescription
            )
        }
    }

    private func updatePreviewStripCollectionViewFrame() {
        let visibleSize = previewStripScrollView.contentSize
        let contentSize = previewStripCollectionView.collectionViewLayout?
            .collectionViewContentSize ?? visibleSize
        previewStripCollectionView.setFrameSize(
            NSSize(
                width: max(contentSize.width, visibleSize.width),
                height: max(contentSize.height, visibleSize.height)
            )
        )
    }

    private func handlePlayerTimeUpdate(_ time: CMTime) {
        let timeSeconds = time.seconds
        guard timeSeconds.isFinite else {
            return
        }

        currentTimeSecondsDidChange(
            clampedTimeSeconds(timeSeconds),
            updateSlider: true,
            updateSelection: true
        )
    }

    private func handlePlaybackDidReachEnd() {
        pausePlayback()
        currentTimeSecondsDidChange(
            clampedTimeSeconds(editorContext.durationSeconds),
            updateSlider: true,
            updateSelection: true
        )
    }

    private func currentTimeSecondsDidChange(
        _ timeSeconds: Double,
        updateSlider: Bool,
        updateSelection: Bool
    ) {
        currentPreviewTimeSeconds = clampedTimeSeconds(timeSeconds)
        currentTimeLabel.stringValue = formatVideoDisplayFrameEditorSeconds(
            currentPreviewTimeSeconds
        )
        durationLabel.stringValue = formatVideoDisplayFrameEditorSeconds(
            editorContext.durationSeconds
        )
        if updateSlider {
            timeSlider.doubleValue = currentPreviewTimeSeconds
        }
        if updateSelection {
            updateSelectedPreviewFrameIndex(
                for: currentPreviewTimeSeconds,
                shouldScrollToSelection: false
            )
        }
    }

    private func seekPreview(
        to timeSeconds: Double,
        pausePlayback: Bool,
        updateSlider: Bool,
        updateSelection: Bool
    ) {
        let clampedTimeSeconds = clampedTimeSeconds(timeSeconds)
        if pausePlayback {
            self.pausePlayback()
        }
        currentTimeSecondsDidChange(
            clampedTimeSeconds,
            updateSlider: updateSlider,
            updateSelection: updateSelection
        )
        player.seek(
            to: CMTime(seconds: clampedTimeSeconds, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    private func pausePlayback() {
        player.pause()
        updatePlayPauseButtonAppearance()
    }

    private func updatePlayPauseButtonAppearance() {
        let symbolName = player.timeControlStatus == .playing
            ? "pause.fill"
            : "play.fill"
        playPauseButton.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: player.timeControlStatus == .playing
                ? "Pause video preview"
                : "Play video preview"
        )
        playPauseButton.toolTip = player.timeControlStatus == .playing
            ? "Pause video preview"
            : "Play video preview"
    }

    private func updateCommitButtonAppearance() {
        setDisplayFrameButton.title = isCommitting
            ? "Setting Display Frame..."
            : "Use Current Frame"
        setDisplayFrameButton.isEnabled = isCommitting == false
    }

    private func updateSelectedPreviewFrameIndex(
        for timeSeconds: Double,
        shouldScrollToSelection: Bool
    ) {
        let nextIndex = nearestPreviewFrameIndex(for: timeSeconds)
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

        guard let nextIndex else {
            previewStripCollectionView.deselectAll(nil)
            return
        }

        let indexPath = IndexPath(item: nextIndex, section: 0)
        let scrollPosition: NSCollectionView.ScrollPosition = shouldScrollToSelection
            ? [.centeredHorizontally]
            : []
        previewStripCollectionView.selectItems(
            Set([indexPath]),
            scrollPosition: scrollPosition
        )
    }

    private func nearestPreviewFrameIndex(
        for timeSeconds: Double
    ) -> Int? {
        guard previewFrames.isEmpty == false else {
            return nil
        }

        return previewFrames.enumerated().min { lhs, rhs in
            abs(lhs.element.timeSeconds - timeSeconds) <
                abs(rhs.element.timeSeconds - timeSeconds)
        }?.offset
    }

    private func clampedTimeSeconds(_ timeSeconds: Double) -> Double {
        guard editorContext.durationSeconds > 0 else {
            return 0
        }

        let upperBound = max(editorContext.durationSeconds - (1.0 / 600.0), 0)
        guard timeSeconds.isFinite else {
            return 0
        }

        return min(max(timeSeconds, 0), upperBound)
    }

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

    @objc
    private func handleCloseButtonClick() {
        dismiss(self)
    }

    @objc
    private func handlePlayPauseButtonClick() {
        guard editorContext.durationSeconds > 0 else {
            return
        }

        if player.timeControlStatus == .playing {
            pausePlayback()
            return
        }

        let restartFromBeginningThreshold = max(
            editorContext.durationSeconds - 0.05,
            0
        )
        let startTime = currentPreviewTimeSeconds >= restartFromBeginningThreshold
            ? 0
            : currentPreviewTimeSeconds
        currentTimeSecondsDidChange(
            startTime,
            updateSlider: true,
            updateSelection: true
        )
        player.seek(
            to: CMTime(seconds: startTime, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self] _ in
            self?.player.play()
            self?.updatePlayPauseButtonAppearance()
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
}

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
        updateSelectedPreviewFrameIndex(
            for: selectedFrame.timeSeconds,
            shouldScrollToSelection: false
        )
    }
}

private final class macOSVideoDisplayFramePlayerView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.cornerRadius = 18
        layer?.masksToBounds = true
        playerLayer.needsDisplayOnBoundsChange = true
        layer?.addSublayer(playerLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
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
    static let reuseIdentifier = NSUserInterfaceItemIdentifier(
        "macOSVideoDisplayFramePreviewItem"
    )

    private let previewImageView: NSImageView = {
        let imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        return imageView
    }()
    private let timeLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        return label
    }()

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.wantsLayer = true
        view.layer?.cornerRadius = 14
        view.layer?.borderWidth = 1
        view.layer?.borderColor = NSColor.separatorColor.cgColor
        view.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        view.addSubview(previewImageView)
        view.addSubview(timeLabel)
        NSLayoutConstraint.activate([
            previewImageView.topAnchor.constraint(equalTo: view.topAnchor),
            previewImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewImageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            previewImageView.heightAnchor.constraint(
                equalTo: view.heightAnchor,
                multiplier: 0.74
            ),
            timeLabel.topAnchor.constraint(equalTo: previewImageView.bottomAnchor, constant: 6),
            timeLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            timeLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            timeLabel.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor)
        ])
    }

    override var isSelected: Bool {
        didSet {
            updateSelectionAppearance(isHighlighted: isSelected)
        }
    }

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

    private func updateSelectionAppearance(isHighlighted: Bool) {
        view.layer?.borderWidth = isHighlighted ? 2 : 1
        view.layer?.borderColor = isHighlighted
            ? NSColor.controlAccentColor.cgColor
            : NSColor.separatorColor.cgColor
        view.layer?.backgroundColor = isHighlighted
            ? NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor
            : NSColor.controlBackgroundColor.cgColor
    }
}

private func formatVideoDisplayFrameEditorSeconds(
    _ timeSeconds: Double
) -> String {
    String(format: "%.2fs", timeSeconds)
}
#endif
