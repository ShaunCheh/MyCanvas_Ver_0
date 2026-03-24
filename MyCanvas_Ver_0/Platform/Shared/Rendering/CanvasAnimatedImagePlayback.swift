import Foundation
import ImageIO
import QuartzCore

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

final class CanvasAnimationTicker {
    static let defaultInterval: TimeInterval = 1.0 / 60.0

    var onTick: ((TimeInterval) -> Void)?

    private let interval: TimeInterval
    private var timer: Timer?
    private var lastTimestamp: CFTimeInterval?

    init(interval: TimeInterval = defaultInterval) {
        self.interval = interval
    }

    func startIfNeeded() {
        guard timer == nil else {
            return
        }

        lastTimestamp = CACurrentMediaTime()
        let timer = Timer(
            timeInterval: interval,
            repeats: true
        ) { [weak self] _ in
            self?.handleTick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        lastTimestamp = nil
    }

    private func handleTick() {
        let now = CACurrentMediaTime()
        let elapsedTime: TimeInterval
        if let lastTimestamp {
            elapsedTime = min(max(now - lastTimestamp, 0), 0.25)
        } else {
            elapsedTime = 0
        }
        lastTimestamp = now
        onTick?(elapsedTime)
    }

    deinit {
        stop()
    }
}

final class CanvasGIFPlaybackRegistry {
    typealias SourceResolver = (CanvasImageAssetReference) -> CanvasAnimatedImagePlaybackSource?

    private let resolveSource: SourceResolver
    private let ticker: CanvasAnimationTicker

    private var visibleBindingsByItemID: [CanvasItemID: CanvasAnimatedImagePlaybackBinding] = [:]
    private var controllersByAssetReference: [CanvasImageAssetReference: CanvasGIFPlaybackController] = [:]
    private var isPlaybackEnabled = false

    init(
        resolveSource: @escaping SourceResolver,
        ticker: CanvasAnimationTicker = CanvasAnimationTicker()
    ) {
        self.resolveSource = resolveSource
        self.ticker = ticker
        self.ticker.onTick = { [weak self] elapsedTime in
            self?.handleTick(elapsedTime: elapsedTime)
        }
    }

    func reconcileVisibleBindings(_ bindings: [CanvasAnimatedImagePlaybackBinding]) {
        let incomingBindingsByItemID = Dictionary(
            uniqueKeysWithValues: bindings.map { ($0.itemID, $0) }
        )

        let removedItemIDs = Set(visibleBindingsByItemID.keys).subtracting(
            incomingBindingsByItemID.keys
        )
        for itemID in removedItemIDs {
            guard let binding = visibleBindingsByItemID.removeValue(forKey: itemID) else {
                continue
            }
            unbind(binding)
        }

        for binding in bindings {
            if let existingBinding = visibleBindingsByItemID[binding.itemID],
               existingBinding.displayContract.assetReference != binding.displayContract.assetReference
            {
                unbind(existingBinding)
            }

            visibleBindingsByItemID[binding.itemID] = binding

            guard binding.displayContract.isAnimatedAsset else {
                binding.layer.restorePosterFrameIfNeeded(
                    for: binding.displayContract.assetReference
                )
                continue
            }

            if isPlaybackEnabled {
                bind(binding)
            } else {
                binding.layer.restorePosterFrameIfNeeded(
                    for: binding.displayContract.assetReference
                )
            }
        }

        updateTickerState()
    }

    func setPlaybackEnabled(_ enabled: Bool) {
        guard isPlaybackEnabled != enabled else {
            return
        }

        isPlaybackEnabled = enabled
        if enabled {
            activateVisibleBindings()
        } else {
            deactivatePlayback()
        }
        updateTickerState()
    }

    func invalidate() {
        setPlaybackEnabled(false)
        visibleBindingsByItemID.removeAll()
    }

    private func activateVisibleBindings() {
        for binding in visibleBindingsByItemID.values {
            guard binding.displayContract.isAnimatedAsset else {
                binding.layer.restorePosterFrameIfNeeded(
                    for: binding.displayContract.assetReference
                )
                continue
            }
            bind(binding)
        }
    }

    private func deactivatePlayback() {
        ticker.stop()
        for controller in controllersByAssetReference.values {
            controller.unbindAll()
        }
        controllersByAssetReference.removeAll()
    }

    private func bind(_ binding: CanvasAnimatedImagePlaybackBinding) {
        let assetReference = binding.displayContract.assetReference
        let controller: CanvasGIFPlaybackController
        if let existingController = controllersByAssetReference[assetReference] {
            controller = existingController
        } else {
            guard
                let source = resolveSource(assetReference),
                let newController = CanvasGIFPlaybackController(source: source)
            else {
                binding.layer.restorePosterFrameIfNeeded(for: assetReference)
                return
            }
            controllersByAssetReference[assetReference] = newController
            controller = newController
        }

        controller.bind(binding)
    }

    private func unbind(_ binding: CanvasAnimatedImagePlaybackBinding) {
        let assetReference = binding.displayContract.assetReference
        guard let controller = controllersByAssetReference[assetReference] else {
            binding.layer.restorePosterFrameIfNeeded(for: assetReference)
            return
        }

        controller.unbind(itemID: binding.itemID)
        if controller.hasBindings == false {
            controllersByAssetReference.removeValue(forKey: assetReference)
        }
    }

    private func handleTick(elapsedTime: TimeInterval) {
        guard elapsedTime > 0 else {
            return
        }

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
    let assetReference: CanvasImageAssetReference

    private let imageSource: CGImageSource
    private let frameCount: Int
    private let frameDelayTimes: [TimeInterval]
    private let loopCount: Int?

    private var boundLayersByItemID: [CanvasItemID: CanvasImageLayer] = [:]
    private var currentFrameIndex = 0
    private var currentPlaybackFrame: CGImage?
    private var accumulatedFrameTime: TimeInterval = 0
    private var completedLoopCount = 0
    private var isFinished = false

    init?(source: CanvasAnimatedImagePlaybackSource) {
        guard
            let imageSource = CGImageSourceCreateWithData(source.data as CFData, nil)
        else {
            return nil
        }

        let frameCount = CGImageSourceGetCount(imageSource)
        guard frameCount > 1 else {
            return nil
        }

        let metadata = Self.makePlaybackMetadata(
            from: source.animatedMetadata,
            imageSource: imageSource,
            frameCount: frameCount
        )

        assetReference = source.assetReference
        self.imageSource = imageSource
        self.frameCount = frameCount
        frameDelayTimes = metadata.frameDelayTimes
        loopCount = metadata.loopCount
    }

    var hasBindings: Bool {
        boundLayersByItemID.isEmpty == false
    }

    var needsTicks: Bool {
        hasBindings && isFinished == false
    }

    func bind(_ binding: CanvasAnimatedImagePlaybackBinding) {
        boundLayersByItemID[binding.itemID] = binding.layer
        applyCurrentFrame(to: binding.layer)
    }

    func unbind(itemID: CanvasItemID) {
        guard let layer = boundLayersByItemID.removeValue(forKey: itemID) else {
            return
        }

        layer.restorePosterFrameIfNeeded(for: assetReference)
    }

    func unbindAll() {
        for layer in boundLayersByItemID.values {
            layer.restorePosterFrameIfNeeded(for: assetReference)
        }
        boundLayersByItemID.removeAll()
    }

    func tick(elapsedTime: TimeInterval) {
        guard
            hasBindings,
            isFinished == false
        else {
            return
        }

        var remainingTime = elapsedTime
        while remainingTime > 0, isFinished == false {
            let currentDelay = delayTime(forFrameAt: currentFrameIndex)
            let remainingDelay = max(currentDelay - accumulatedFrameTime, 0)

            if remainingTime < remainingDelay {
                accumulatedFrameTime += remainingTime
                remainingTime = 0
            } else {
                remainingTime -= remainingDelay
                accumulatedFrameTime = 0
                advanceFrameIfNeeded()
            }
        }
    }

    private func applyCurrentFrame(to layer: CanvasImageLayer) {
        if let currentPlaybackFrame {
            layer.displayPlaybackFrame(currentPlaybackFrame, for: assetReference)
        } else {
            layer.restorePosterFrameIfNeeded(for: assetReference)
        }
    }

    private func advanceFrameIfNeeded() {
        let lastFrameIndex = frameCount - 1
        if currentFrameIndex >= lastFrameIndex {
            if shouldLoopAfterCurrentCycle {
                completedLoopCount += 1
                currentFrameIndex = 0
                currentPlaybackFrame = nil
                restorePosterFrameOnAllBoundLayers()
            } else {
                isFinished = true
            }
            return
        }

        let nextFrameIndex = currentFrameIndex + 1
        guard let frameImage = decodeFrame(at: nextFrameIndex) else {
            return
        }

        currentFrameIndex = nextFrameIndex
        currentPlaybackFrame = frameImage
        displayPlaybackFrameOnAllBoundLayers(frameImage)
    }

    private var shouldLoopAfterCurrentCycle: Bool {
        guard let loopCount, loopCount > 0 else {
            return true
        }

        return completedLoopCount + 1 < loopCount
    }

    private func delayTime(forFrameAt frameIndex: Int) -> TimeInterval {
        guard frameDelayTimes.indices.contains(frameIndex) else {
            return 0.1
        }

        return frameDelayTimes[frameIndex]
    }

    private func decodeFrame(at frameIndex: Int) -> CGImage? {
        let options = [
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary
        return CGImageSourceCreateImageAtIndex(
            imageSource,
            frameIndex,
            options
        )
    }

    private func displayPlaybackFrameOnAllBoundLayers(_ cgImage: CGImage) {
        for layer in boundLayersByItemID.values {
            layer.displayPlaybackFrame(cgImage, for: assetReference)
        }
    }

    private func restorePosterFrameOnAllBoundLayers() {
        for layer in boundLayersByItemID.values {
            layer.restorePosterFrameIfNeeded(for: assetReference)
        }
    }

    private static func makePlaybackMetadata(
        from importedMetadata: CanvasAnimatedImageMetadata?,
        imageSource: CGImageSource,
        frameCount: Int
    ) -> CanvasAnimatedImageMetadata {
        let frameDelayTimes: [TimeInterval]
        if let importedMetadata,
           importedMetadata.frameCount == frameCount,
           importedMetadata.frameDelayTimes.count == frameCount
        {
            frameDelayTimes = importedMetadata.frameDelayTimes
        } else {
            frameDelayTimes = (0..<frameCount).map { frameIndex in
                frameDelay(forFrameAt: frameIndex, imageSource: imageSource)
            }
        }

        let loopCount = importedMetadata?.loopCount ?? gifLoopCount(
            from: imageSource
        )

        return CanvasAnimatedImageMetadata(
            frameCount: frameCount,
            frameDelayTimes: frameDelayTimes,
            loopCount: loopCount
        )
    }

    private static func gifLoopCount(from imageSource: CGImageSource) -> Int? {
        let properties = CGImageSourceCopyProperties(
            imageSource,
            nil
        ) as? [CFString: Any]
        let gifProperties = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        return gifProperties?[kCGImagePropertyGIFLoopCount] as? Int
    }

    private static func frameDelay(
        forFrameAt frameIndex: Int,
        imageSource: CGImageSource
    ) -> TimeInterval {
        let properties = CGImageSourceCopyPropertiesAtIndex(
            imageSource,
            frameIndex,
            nil
        ) as? [CFString: Any]
        let gifProperties = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        let unclampedDelay = gifProperties?[kCGImagePropertyGIFUnclampedDelayTime] as? Double
        let clampedDelay = gifProperties?[kCGImagePropertyGIFDelayTime] as? Double
        let rawDelay = unclampedDelay ?? clampedDelay ?? 0.1
        guard rawDelay.isFinite, rawDelay > 0.011 else {
            return 0.1
        }

        return rawDelay
    }
}
