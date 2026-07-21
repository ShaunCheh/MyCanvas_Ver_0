#if os(macOS)
import AVFoundation
import AppKit

final class macOSVideoDisplayFrameEditorViewController: NSViewController {
    private let editorContext: CanvasVideoEditorContext
    private let loadTimelineStrip: (CanvasVideoTimelineStripRequest) throws -> CanvasVideoTimelineStrip
    private let onCommitFrameImage: (CanvasVideoFrameImage) throws -> Void
    private let onDidDismiss: (() -> Void)?
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
    private let timelineView: macOSVideoTimelineView = {
        let view = macOSVideoTimelineView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    private let setDisplayFrameButton: NSButton = {
        let button = NSButton(title: "Use Current Frame", target: nil, action: nil)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.controlSize = .large
        button.bezelStyle = .rounded
        button.keyEquivalent = "\r"
        return button
    }()

    private var previewState: CanvasVideoEditorPreviewState
    private var hasPerformedInitialSeek = false
    private var isCommitting = false {
        didSet {
            updateCommitButtonAppearance()
        }
    }
    private var playerTimeObserver: Any?
    private var playbackEndedObserver: NSObjectProtocol?
    private var timelineLoadGeneration = 0
    private var timelineLoadWorkItem: DispatchWorkItem?

    init(
        editorContext: CanvasVideoEditorContext,
        loadTimelineStrip: @escaping (CanvasVideoTimelineStripRequest) throws -> CanvasVideoTimelineStrip,
        onDidDismiss: (() -> Void)? = nil,
        onCommitFrameImage: @escaping (CanvasVideoFrameImage) throws -> Void
    ) {
        self.editorContext = editorContext
        self.loadTimelineStrip = loadTimelineStrip
        self.onDidDismiss = onDidDismiss
        self.onCommitFrameImage = onCommitFrameImage
        previewState = CanvasVideoEditorPreviewState(
            currentTimeSeconds: editorContext.currentPosterTimeSeconds,
            posterTimeSeconds: editorContext.currentPosterTimeSeconds,
            durationSeconds: editorContext.durationSeconds
        )
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        timelineLoadWorkItem?.cancel()
        if let playerTimeObserver {
            player.removeTimeObserver(playerTimeObserver)
        }
        if let playbackEndedObserver {
            NotificationCenter.default.removeObserver(playbackEndedObserver)
        }
    }

    override func loadView() {
        let rootView = macOSAppearanceAwareView()
        rootView.onEffectiveAppearanceChange = { [weak self] in
            self?.updateAppearance()
        }
        view = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = CGSize(width: 760, height: 620)
        view.wantsLayer = true
        updateAppearance()
        configureTimelineView()
        configureButtons()
        configurePlayer()
        setupViewHierarchy()
        setupConstraints()
        applyInitialState()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard hasPerformedInitialSeek == false else {
            return
        }

        hasPerformedInitialSeek = true
        seekPreview(
            to: previewState.snapshot.currentTimeSeconds,
            pausePlayback: true,
            updateSlider: true,
            updateTimeline: true
        )
        view.window?.makeFirstResponder(timeSlider)
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        timelineLoadWorkItem?.cancel()
        pausePlayback()
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        onDidDismiss?()
    }

    override func cancelOperation(_ sender: Any?) {
        dismiss(self)
    }

    private func updateAppearance() {
        guard isViewLoaded else {
            return
        }

        let appearance = view.effectiveAppearance
        PlatformLayerAppearance.performWithoutAnimations {
            view.layer?.backgroundColor = PlatformLayerAppearance.resolvedCGColor(
                .windowBackgroundColor,
                for: appearance
            )
        }
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

            self.beginPreviewInteraction(.slider)
        }
        timeSlider.onDidEndScrubbing = { [weak self] in
            guard let self else {
                return
            }

            self.endPreviewInteraction(.slider)
        }
        setDisplayFrameButton.target = self
        setDisplayFrameButton.action = #selector(handleSetDisplayFrameButtonClick)
        updatePlayPauseButtonAppearance()
        updateCommitButtonAppearance()
    }

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
        view.addSubview(timelineView)
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

            timelineView.topAnchor.constraint(equalTo: currentTimeLabel.bottomAnchor, constant: 18),
            timelineView.leadingAnchor.constraint(equalTo: playerView.leadingAnchor),
            timelineView.trailingAnchor.constraint(equalTo: playerView.trailingAnchor),
            timelineView.heightAnchor.constraint(equalToConstant: 112),

            setDisplayFrameButton.topAnchor.constraint(
                equalTo: timelineView.bottomAnchor,
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
        let snapshot = previewState.snapshot
        timelineView.configure(
            durationSeconds: snapshot.durationSeconds,
            playheadTimeSeconds: snapshot.currentTimeSeconds
        )
        currentTimeSecondsDidChange(
            snapshot.currentTimeSeconds,
            updateSlider: true,
            updateTimeline: false
        )
        timeSlider.maxValue = max(editorContext.durationSeconds, 0.001)
        let hasPlayableDuration = editorContext.durationSeconds > 0
        timeSlider.isEnabled = hasPlayableDuration
        playPauseButton.isEnabled = hasPlayableDuration
    }

    private func handlePlayerTimeUpdate(_ time: CMTime) {
        guard previewState.snapshot.shouldAcceptPlayerTimeUpdates else {
            return
        }

        let timeSeconds = time.seconds
        guard timeSeconds.isFinite else {
            return
        }

        currentTimeSecondsDidChange(
            clampedTimeSeconds(timeSeconds),
            updateSlider: true,
            updateTimeline: true
        )
    }

    private func handlePlaybackDidReachEnd() {
        pausePlayback()
        currentTimeSecondsDidChange(
            clampedTimeSeconds(editorContext.durationSeconds),
            updateSlider: true,
            updateTimeline: true
        )
    }

    private func currentTimeSecondsDidChange(
        _ timeSeconds: Double,
        updateSlider: Bool,
        updateTimeline: Bool
    ) {
        previewState.setCurrentTimeSeconds(timeSeconds)
        applyPreviewState(
            updateSlider: updateSlider,
            updateTimeline: updateTimeline
        )
    }

    private func seekPreview(
        to timeSeconds: Double,
        pausePlayback: Bool,
        updateSlider: Bool,
        updateTimeline: Bool
    ) {
        let clampedTimeSeconds = clampedTimeSeconds(timeSeconds)
        if pausePlayback {
            self.pausePlayback()
        }
        currentTimeSecondsDidChange(
            clampedTimeSeconds,
            updateSlider: updateSlider,
            updateTimeline: updateTimeline
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
        let snapshot = previewState.snapshot
        setDisplayFrameButton.title = isCommitting
            ? "Setting Display Frame..."
            : (snapshot.isCurrentPosterSelected
                ? "Current Frame Already Used"
                : "Use Current Frame")
        setDisplayFrameButton.isEnabled = (
            isCommitting == false &&
                snapshot.isCurrentPosterSelected == false
        )
    }

    private func clampedTimeSeconds(_ timeSeconds: Double) -> Double {
        CanvasVideoTimelineViewport.clampedTimeSeconds(
            timeSeconds,
            durationSeconds: editorContext.durationSeconds
        )
    }

    private func applyPreviewState(
        updateSlider: Bool,
        updateTimeline: Bool
    ) {
        let snapshot = previewState.snapshot
        currentTimeLabel.stringValue = formatVideoDisplayFrameEditorSeconds(
            snapshot.currentTimeSeconds
        )
        durationLabel.stringValue = formatVideoDisplayFrameEditorSeconds(
            snapshot.durationSeconds
        )
        if updateSlider, snapshot.isInteracting(with: .slider) == false {
            timeSlider.doubleValue = snapshot.currentTimeSeconds
        }
        if updateTimeline {
            timelineView.setPlayheadTimeSeconds(
                snapshot.currentTimeSeconds,
                animated: false
            )
        }
        updateCommitButtonAppearance()
    }

    private func beginPreviewInteraction(
        _ source: CanvasVideoEditorPreviewInteractionSource
    ) {
        let playbackIntent = previewState.beginInteraction(
            source,
            wasPlaying: player.timeControlStatus == .playing
        )
        if playbackIntent == .pause {
            pausePlayback()
        }
        updateCommitButtonAppearance()
    }

    private func endPreviewInteraction(
        _ source: CanvasVideoEditorPreviewInteractionSource
    ) {
        let playbackIntent = previewState.endInteraction(source)
        if playbackIntent == .resume {
            player.play()
            updatePlayPauseButtonAppearance()
        }
        updateCommitButtonAppearance()
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
        let startTime = previewState.snapshot.currentTimeSeconds
            >= restartFromBeginningThreshold
            ? 0
            : previewState.snapshot.currentTimeSeconds
        currentTimeSecondsDidChange(
            startTime,
            updateSlider: true,
            updateTimeline: true
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
            updateTimeline: true
        )
    }

    @objc
    private func handleSetDisplayFrameButtonClick() {
        guard isCommitting == false else {
            return
        }

        isCommitting = true
        pausePlayback()
        let commitTimeSeconds = previewState.snapshot.currentTimeSeconds
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

private func formatVideoDisplayFrameEditorSeconds(
    _ timeSeconds: Double
) -> String {
    String(format: "%.2fs", timeSeconds)
}
#endif
