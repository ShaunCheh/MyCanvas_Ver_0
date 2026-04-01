#if os(iOS)
import AVFoundation
import UIKit

final class iOSVideoDisplayFrameEditorViewController: UIViewController {
    private let editorContext: CanvasVideoEditorContext
    private let loadTimelineStrip: (CanvasVideoTimelineStripRequest) throws -> CanvasVideoTimelineStrip
    private let onCommitFrameImage: (CanvasVideoFrameImage) throws -> Void
    private let workerQueue = DispatchQueue(
        label: "MyCanvas.iOS.VideoDisplayFrameEditor",
        qos: .userInitiated
    )
    private let player = AVPlayer()
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 28, weight: .semibold)
        label.text = "Set Display Frame"
        return label
    }()
    private let closeButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        var configuration = UIButton.Configuration.plain()
        configuration.title = "Close"
        button.configuration = configuration
        return button
    }()
    private let playerView: iOSVideoDisplayFramePlayerView = {
        let view = iOSVideoDisplayFramePlayerView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .black
        view.layer.cornerRadius = 20
        view.layer.masksToBounds = true
        return view
    }()
    private let playPauseButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    private let currentTimeLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabel
        label.textAlignment = .left
        return label
    }()
    private let durationLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabel
        label.textAlignment = .right
        return label
    }()
    private let timeSlider: UISlider = {
        let slider = UISlider()
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.minimumValue = 0
        return slider
    }()
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
    private let setDisplayFrameButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private var currentPreviewTimeSeconds: Double
    private var hasPerformedInitialSeek = false
    private var isCommitting = false {
        didSet {
            updateCommitButtonConfiguration()
        }
    }
    private var playerTimeObserver: Any?
    private var playbackEndedObserver: NSObjectProtocol?
    private var activeInteractionSources: Set<PreviewInteractionSource> = []
    private var shouldResumePlaybackAfterInteraction = false
    private var timelineLoadGeneration = 0
    private var timelineLoadWorkItem: DispatchWorkItem?

    init(
        editorContext: CanvasVideoEditorContext,
        loadTimelineStrip: @escaping (CanvasVideoTimelineStripRequest) throws -> CanvasVideoTimelineStrip,
        onCommitFrameImage: @escaping (CanvasVideoFrameImage) throws -> Void
    ) {
        self.editorContext = editorContext
        self.loadTimelineStrip = loadTimelineStrip
        self.onCommitFrameImage = onCommitFrameImage
        currentPreviewTimeSeconds = editorContext.currentPosterTimeSeconds
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        modalTransitionStyle = .coverVertical
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

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        configureTimelineView()
        configureButtons()
        configurePlayer()
        setupViewHierarchy()
        setupConstraints()
        applyInitialState()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard hasPerformedInitialSeek == false else {
            return
        }

        hasPerformedInitialSeek = true
        seekPreview(
            to: currentPreviewTimeSeconds,
            pausePlayback: true,
            updateSlider: true,
            updateTimeline: true
        )
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        timelineLoadWorkItem?.cancel()
        pausePlayback()
    }

    private func configureButtons() {
        closeButton.addTarget(
            self,
            action: #selector(handleCloseButtonTap),
            for: .touchUpInside
        )
        playPauseButton.addTarget(
            self,
            action: #selector(handlePlayPauseButtonTap),
            for: .touchUpInside
        )
        timeSlider.addTarget(
            self,
            action: #selector(handleTimeSliderTouchDown),
            for: .touchDown
        )
        timeSlider.addTarget(
            self,
            action: #selector(handleTimeSliderValueChanged),
            for: .valueChanged
        )
        timeSlider.addTarget(
            self,
            action: #selector(handleTimeSliderTouchEnded),
            for: [.touchUpInside, .touchUpOutside, .touchCancel]
        )
        setDisplayFrameButton.addTarget(
            self,
            action: #selector(handleSetDisplayFrameButtonTap),
            for: .touchUpInside
        )
        updatePlayPauseButtonConfiguration()
        updateCommitButtonConfiguration()
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
        view.addSubview(timelineLoadingIndicator)
        view.addSubview(timelinePlaceholderLabel)
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
            titleLabel.topAnchor.constraint(
                equalTo: safeArea.topAnchor,
                constant: 20
            ),
            titleLabel.leadingAnchor.constraint(
                equalTo: safeArea.leadingAnchor,
                constant: 24
            ),
            closeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            closeButton.trailingAnchor.constraint(
                equalTo: safeArea.trailingAnchor,
                constant: -24
            ),
            titleLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: closeButton.leadingAnchor,
                constant: -12
            ),

            playerView.topAnchor.constraint(
                equalTo: titleLabel.bottomAnchor,
                constant: 24
            ),
            playerView.leadingAnchor.constraint(
                equalTo: safeArea.leadingAnchor,
                constant: 24
            ),
            playerView.trailingAnchor.constraint(
                equalTo: safeArea.trailingAnchor,
                constant: -24
            ),
            playerView.heightAnchor.constraint(
                equalTo: playerView.widthAnchor,
                multiplier: videoAspectRatio
            ),
            playerView.heightAnchor.constraint(
                lessThanOrEqualTo: safeArea.heightAnchor,
                multiplier: 0.45
            ),

            playPauseButton.centerXAnchor.constraint(equalTo: playerView.centerXAnchor),
            playPauseButton.centerYAnchor.constraint(equalTo: playerView.centerYAnchor),

            currentTimeLabel.topAnchor.constraint(
                equalTo: playerView.bottomAnchor,
                constant: 20
            ),
            currentTimeLabel.leadingAnchor.constraint(
                equalTo: playerView.leadingAnchor
            ),
            currentTimeLabel.widthAnchor.constraint(equalToConstant: 64),

            durationLabel.centerYAnchor.constraint(
                equalTo: currentTimeLabel.centerYAnchor
            ),
            durationLabel.trailingAnchor.constraint(
                equalTo: playerView.trailingAnchor
            ),
            durationLabel.widthAnchor.constraint(equalToConstant: 64),

            timeSlider.centerYAnchor.constraint(
                equalTo: currentTimeLabel.centerYAnchor
            ),
            timeSlider.leadingAnchor.constraint(
                equalTo: currentTimeLabel.trailingAnchor,
                constant: 12
            ),
            timeSlider.trailingAnchor.constraint(
                equalTo: durationLabel.leadingAnchor,
                constant: -12
            ),

            timelineView.topAnchor.constraint(
                equalTo: currentTimeLabel.bottomAnchor,
                constant: 20
            ),
            timelineView.leadingAnchor.constraint(
                equalTo: playerView.leadingAnchor
            ),
            timelineView.trailingAnchor.constraint(
                equalTo: playerView.trailingAnchor
            ),
            timelineView.heightAnchor.constraint(equalToConstant: 112),

            timelineLoadingIndicator.centerXAnchor.constraint(
                equalTo: timelineView.centerXAnchor
            ),
            timelineLoadingIndicator.centerYAnchor.constraint(
                equalTo: timelineView.centerYAnchor
            ),
            timelinePlaceholderLabel.centerXAnchor.constraint(
                equalTo: timelineView.centerXAnchor
            ),
            timelinePlaceholderLabel.centerYAnchor.constraint(
                equalTo: timelineView.centerYAnchor
            ),
            timelinePlaceholderLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: timelineView.leadingAnchor,
                constant: 12
            ),
            timelinePlaceholderLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: timelineView.trailingAnchor,
                constant: -12
            ),

            setDisplayFrameButton.topAnchor.constraint(
                equalTo: timelineView.bottomAnchor,
                constant: 24
            ),
            setDisplayFrameButton.leadingAnchor.constraint(
                equalTo: playerView.leadingAnchor
            ),
            setDisplayFrameButton.trailingAnchor.constraint(
                equalTo: playerView.trailingAnchor
            ),
            setDisplayFrameButton.bottomAnchor.constraint(
                lessThanOrEqualTo: safeArea.bottomAnchor,
                constant: -20
            ),
            setDisplayFrameButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }

    private func applyInitialState() {
        timelineView.configure(
            durationSeconds: editorContext.durationSeconds,
            playheadTimeSeconds: currentPreviewTimeSeconds
        )
        currentTimeSecondsDidChange(
            currentPreviewTimeSeconds,
            updateSlider: true,
            updateTimeline: false
        )
        timeSlider.maximumValue = Float(
            max(editorContext.durationSeconds, 0.001)
        )
        let hasPlayableDuration = editorContext.durationSeconds > 0
        timeSlider.isEnabled = hasPlayableDuration
        playPauseButton.isEnabled = hasPlayableDuration
        timelinePlaceholderLabel.isHidden = false
    }

    private func handlePlayerTimeUpdate(_ time: CMTime) {
        guard isPreviewInteracting == false else {
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
        updatePlayPauseButtonConfiguration()
    }

    private func updatePlayPauseButtonConfiguration() {
        var configuration = UIButton.Configuration.filled()
        configuration.image = UIImage(
            systemName: player.timeControlStatus == .playing ? "pause.fill" : "play.fill"
        )
        configuration.baseBackgroundColor = UIColor.black.withAlphaComponent(0.5)
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: 14,
            leading: 18,
            bottom: 14,
            trailing: 18
        )
        playPauseButton.configuration = configuration
        playPauseButton.accessibilityLabel = player.timeControlStatus == .playing
            ? "Pause video preview"
            : "Play video preview"
    }

    private func updateCommitButtonConfiguration() {
        var configuration = UIButton.Configuration.filled()
        configuration.title = isCommitting
            ? "Setting Display Frame..."
            : "Use Current Frame"
        configuration.showsActivityIndicator = isCommitting
        configuration.cornerStyle = .large
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: 14,
            leading: 18,
            bottom: 14,
            trailing: 18
        )
        setDisplayFrameButton.configuration = configuration
        setDisplayFrameButton.isEnabled = isCommitting == false
    }

    private func clampedTimeSeconds(_ timeSeconds: Double) -> Double {
        CanvasVideoTimelineViewport.clampedTimeSeconds(
            timeSeconds,
            durationSeconds: editorContext.durationSeconds
        )
    }

    private var isPreviewInteracting: Bool {
        activeInteractionSources.isEmpty == false
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

    private func handleTimelineStripLoadResult(
        _ result: Result<CanvasVideoTimelineStrip, Error>,
        generation: Int
    ) {
        guard generation == timelineLoadGeneration else {
            return
        }

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

    private func presentError(title: String, message: String) {
        let alertController = UIAlertController(
            title: title,
            message: message,
            preferredStyle: .alert
        )
        alertController.addAction(
            UIAlertAction(title: "OK", style: .default)
        )
        present(alertController, animated: true)
    }

    @objc
    private func handleCloseButtonTap() {
        dismiss(animated: true)
    }

    @objc
    private func handlePlayPauseButtonTap() {
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
            updateTimeline: true
        )
        player.seek(
            to: CMTime(seconds: startTime, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self] _ in
            self?.player.play()
            self?.updatePlayPauseButtonConfiguration()
        }
    }

    @objc
    private func handleTimeSliderTouchDown() {
        beginPreviewInteraction(.slider)
    }

    @objc
    private func handleTimeSliderValueChanged() {
        let selectedTimeSeconds = Double(timeSlider.value)
        seekPreview(
            to: selectedTimeSeconds,
            pausePlayback: false,
            updateSlider: true,
            updateTimeline: true
        )
    }

    @objc
    private func handleTimeSliderTouchEnded() {
        endPreviewInteraction(.slider)
    }

    @objc
    private func handleSetDisplayFrameButtonTap() {
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
                dismiss(animated: true)
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

private final class iOSVideoDisplayFramePlayerView: UIView {
    override class var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }
}

private enum PreviewInteractionSource: Hashable {
    case slider
    case timeline
}

private func formatVideoDisplayFrameEditorSeconds(
    _ timeSeconds: Double
) -> String {
    String(format: "%.2fs", timeSeconds)
}
#endif
