#if os(iOS)
import AVFoundation
import UIKit

final class iOSVideoDisplayFrameEditorViewController: UIViewController {
    private let editorContext: CanvasVideoEditorContext
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
    private let setDisplayFrameButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private var previewFrames: [CanvasVideoPreviewStripFrame] = []
    private var currentPreviewTimeSeconds: Double
    private var selectedPreviewFrameIndex: Int?
    private var isScrubbing = false
    private var shouldResumePlaybackAfterScrub = false
    private var hasPerformedInitialSeek = false
    private var isCommitting = false {
        didSet {
            updateCommitButtonConfiguration()
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
        modalPresentationStyle = .fullScreen
        modalTransitionStyle = .coverVertical
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

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        configureCollectionView()
        configureButtons()
        configurePlayer()
        setupViewHierarchy()
        setupConstraints()
        applyInitialState()
        loadPreviewStrip()
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
            updateSelection: true
        )
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        pausePlayback()
    }

    private func configureCollectionView() {
        previewStripCollectionView.dataSource = self
        previewStripCollectionView.delegate = self
        previewStripCollectionView.register(
            iOSVideoDisplayFramePreviewCell.self,
            forCellWithReuseIdentifier: iOSVideoDisplayFramePreviewCell.reuseIdentifier
        )
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
        view.addSubview(previewStripCollectionView)
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

            previewStripCollectionView.topAnchor.constraint(
                equalTo: currentTimeLabel.bottomAnchor,
                constant: 20
            ),
            previewStripCollectionView.leadingAnchor.constraint(
                equalTo: playerView.leadingAnchor
            ),
            previewStripCollectionView.trailingAnchor.constraint(
                equalTo: playerView.trailingAnchor
            ),
            previewStripCollectionView.heightAnchor.constraint(equalToConstant: 92),

            previewStripLoadingIndicator.centerXAnchor.constraint(
                equalTo: previewStripCollectionView.centerXAnchor
            ),
            previewStripLoadingIndicator.centerYAnchor.constraint(
                equalTo: previewStripCollectionView.centerYAnchor
            ),
            previewStripPlaceholderLabel.centerXAnchor.constraint(
                equalTo: previewStripCollectionView.centerXAnchor
            ),
            previewStripPlaceholderLabel.centerYAnchor.constraint(
                equalTo: previewStripCollectionView.centerYAnchor
            ),
            previewStripPlaceholderLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: previewStripCollectionView.leadingAnchor,
                constant: 12
            ),
            previewStripPlaceholderLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: previewStripCollectionView.trailingAnchor,
                constant: -12
            ),

            setDisplayFrameButton.topAnchor.constraint(
                equalTo: previewStripCollectionView.bottomAnchor,
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
        currentTimeSecondsDidChange(
            currentPreviewTimeSeconds,
            updateSlider: true,
            updateSelection: false
        )
        timeSlider.maximumValue = Float(
            max(editorContext.durationSeconds, 0.001)
        )
        let hasPlayableDuration = editorContext.durationSeconds > 0
        timeSlider.isEnabled = hasPlayableDuration
        playPauseButton.isEnabled = hasPlayableDuration
        previewStripPlaceholderLabel.isHidden = false
    }

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

    private func handlePreviewStripLoadResult(
        _ result: Result<CanvasVideoPreviewStrip, Error>
    ) {
        previewStripLoadingIndicator.stopAnimating()
        switch result {
        case let .success(previewStrip):
            previewFrames = previewStrip.frames
            previewStripCollectionView.reloadData()
            previewStripPlaceholderLabel.isHidden = previewFrames.isEmpty == false
            if previewFrames.isEmpty {
                previewStripPlaceholderLabel.text = "No preview frames available."
            }
            updateSelectedPreviewFrameIndex(
                for: currentPreviewTimeSeconds,
                shouldScrollToSelection: false
            )
        case let .failure(error):
            previewFrames = []
            previewStripCollectionView.reloadData()
            previewStripPlaceholderLabel.isHidden = false
            previewStripPlaceholderLabel.text = "Unable to load preview frames."
            presentError(
                title: "Unable to Load Preview Frames",
                message: error.localizedDescription
            )
        }
    }

    private func handlePlayerTimeUpdate(_ time: CMTime) {
        guard isScrubbing == false else {
            return
        }

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
        currentTimeLabel.text = formatVideoDisplayFrameEditorSeconds(
            currentPreviewTimeSeconds
        )
        durationLabel.text = formatVideoDisplayFrameEditorSeconds(
            editorContext.durationSeconds
        )
        if updateSlider, isScrubbing == false {
            timeSlider.value = Float(currentPreviewTimeSeconds)
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
            previewStripCollectionView.reloadItems(at: indexPathsToReload)
        } else {
            previewStripCollectionView.reloadData()
        }

        if shouldScrollToSelection, let nextIndex {
            previewStripCollectionView.scrollToItem(
                at: IndexPath(item: nextIndex, section: 0),
                at: .centeredHorizontally,
                animated: true
            )
        }
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
            updateSelection: true
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
        isScrubbing = true
        shouldResumePlaybackAfterScrub = player.timeControlStatus == .playing
        pausePlayback()
    }

    @objc
    private func handleTimeSliderValueChanged() {
        let selectedTimeSeconds = Double(timeSlider.value)
        seekPreview(
            to: selectedTimeSeconds,
            pausePlayback: false,
            updateSlider: true,
            updateSelection: true
        )
    }

    @objc
    private func handleTimeSliderTouchEnded() {
        isScrubbing = false
        if shouldResumePlaybackAfterScrub {
            player.play()
            updatePlayPauseButtonConfiguration()
        }
        shouldResumePlaybackAfterScrub = false
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

extension iOSVideoDisplayFrameEditorViewController: UICollectionViewDataSource {
    func collectionView(
        _ collectionView: UICollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        previewFrames.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        guard
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: iOSVideoDisplayFramePreviewCell.reuseIdentifier,
                for: indexPath
            ) as? iOSVideoDisplayFramePreviewCell,
            previewFrames.indices.contains(indexPath.item)
        else {
            return UICollectionViewCell()
        }

        cell.apply(
            frame: previewFrames[indexPath.item],
            isHighlighted: indexPath.item == selectedPreviewFrameIndex
        )
        return cell
    }
}

extension iOSVideoDisplayFrameEditorViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(
        _ collectionView: UICollectionView,
        didSelectItemAt indexPath: IndexPath
    ) {
        guard previewFrames.indices.contains(indexPath.item) else {
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

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        CGSize(width: 92, height: collectionView.bounds.height - 8)
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

private final class iOSVideoDisplayFramePreviewCell: UICollectionViewCell {
    static let reuseIdentifier = "iOSVideoDisplayFramePreviewCell"

    private let imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 12
        return imageView
    }()
    private let timeLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(imageView)
        contentView.addSubview(timeLabel)
        contentView.layer.cornerRadius = 14
        contentView.layer.borderWidth = 1
        contentView.layer.borderColor = UIColor.separator.cgColor
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.heightAnchor.constraint(
                equalTo: contentView.heightAnchor,
                multiplier: 0.74
            ),
            timeLabel.topAnchor.constraint(
                equalTo: imageView.bottomAnchor,
                constant: 6
            ),
            timeLabel.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: 4
            ),
            timeLabel.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor,
                constant: -4
            ),
            timeLabel.bottomAnchor.constraint(
                lessThanOrEqualTo: contentView.bottomAnchor
            )
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.image = nil
        timeLabel.text = nil
    }

    func apply(
        frame: CanvasVideoPreviewStripFrame,
        isHighlighted: Bool
    ) {
        imageView.image = UIImage(cgImage: frame.cgImage)
        timeLabel.text = formatVideoDisplayFrameEditorSeconds(
            frame.timeSeconds
        )
        contentView.layer.borderWidth = isHighlighted ? 2 : 1
        contentView.layer.borderColor = isHighlighted
            ? UIColor.systemBlue.cgColor
            : UIColor.separator.cgColor
        contentView.backgroundColor = isHighlighted
            ? UIColor.systemBlue.withAlphaComponent(0.08)
            : .secondarySystemBackground
    }
}

private func formatVideoDisplayFrameEditorSeconds(
    _ timeSeconds: Double
) -> String {
    String(format: "%.2fs", timeSeconds)
}
#endif
