#if os(iOS)
import UIKit

protocol iOSBoardListCanvasTransitionCarrying: AnyObject {
    var kind: BoardListCanvasTransitionCarrierKind { get }

    func install(in overlayHostView: UIView)
    func prepareTransition(
        with context: BoardListCanvasTransitionContext,
        sourceViewController: UIViewController?,
        destinationViewController: UIViewController?
    )
    func animateTransition(completion: @escaping () -> Void)
    func updateTransitionContext(_ context: BoardListCanvasTransitionContext)
    func completeTransition()
    func cancelTransition()
}

struct iOSLiveCanvasCarrierRequirements {
    let canvasViewProvider: () -> UIView?
    let canvasContainerViewProvider: () -> UIView?
    let isTransitionChromeHidden: () -> Bool
    let setTransitionChromeHidden: (Bool) -> Void
}

enum iOSBoardListCanvasTransitionCarrierFactory {
    static func makeCarrier(
        preferredKind: BoardListCanvasTransitionCarrierKind,
        liveCanvasRequirements: iOSLiveCanvasCarrierRequirements? = nil,
        debugTrace: BoardListCanvasTransitionDebugTrace? = nil
    ) -> any iOSBoardListCanvasTransitionCarrying {
        switch preferredKind {
        case .snapshotShell:
            return iOSSnapshotShellCarrier()
        case .liveCanvas:
            guard let liveCanvasRequirements else {
                return iOSSnapshotShellCarrier()
            }
            return iOSLiveCanvasCarrier(
                requirements: liveCanvasRequirements,
                debugTrace: debugTrace
            )
        }
    }
}

final class iOSLiveCanvasCarrier: iOSBoardListCanvasTransitionCarrying {
    private enum Strategy {
        case liveOpening
        case liveClosing
        case snapshotFallback
    }

    private enum PreferredRectSource: String {
        case focusRect
        case cardRect
    }

    private struct PreferredRectResolution {
        let rect: CGRect
        let source: PreferredRectSource
    }

    private enum LiveCanvasRestoreOutcome: String {
        case restored
        case skippedNotMounted
        case failedMissingCanvasView
        case failedMissingHostView
        case notRequired
    }

    private static let previewCornerRadius: CGFloat = 10

    private let requirements: iOSLiveCanvasCarrierRequirements
    private let snapshotFallbackCarrier: iOSSnapshotShellCarrier
    private let debugTrace: BoardListCanvasTransitionDebugTrace?

    private weak var overlayHostView: UIView?
    private weak var sourceViewController: UIViewController?
    private weak var destinationViewController: UIViewController?
    private weak var liveCanvasHostView: UIView?

    private var currentContext: BoardListCanvasTransitionContext?
    private var liveCanvasView: UIView?
    private var liveContainerView: UIView?
    private var liveTargetFrame: CGRect?
    private var liveTargetRectSource: PreferredRectSource?
    private var liveStrategy: Strategy = .snapshotFallback
    private var originalChromeHiddenState: Bool?
    private var isCanvasMountedInOverlay = false

    init(
        requirements: iOSLiveCanvasCarrierRequirements,
        snapshotFallbackCarrier: iOSSnapshotShellCarrier = iOSSnapshotShellCarrier(),
        debugTrace: BoardListCanvasTransitionDebugTrace? = nil
    ) {
        self.requirements = requirements
        self.snapshotFallbackCarrier = snapshotFallbackCarrier
        self.debugTrace = debugTrace
    }

    var kind: BoardListCanvasTransitionCarrierKind {
        .liveCanvas
    }

    func install(in overlayHostView: UIView) {
        self.overlayHostView = overlayHostView
        snapshotFallbackCarrier.install(in: overlayHostView)
    }

    func prepareTransition(
        with context: BoardListCanvasTransitionContext,
        sourceViewController: UIViewController?,
        destinationViewController: UIViewController?
    ) {
        cleanupLiveTransitionArtifacts(
            restoreCanvasToHost: true,
            restoreChromeVisibility: true,
            removeLiveCanvasFromHierarchy: false,
            clearContext: true,
            restoreTransitionPhase: nil,
            restoreTrigger: nil
        )
        snapshotFallbackCarrier.cancelTransition()

        currentContext = context
        self.sourceViewController = sourceViewController
        self.destinationViewController = destinationViewController
        liveStrategy = .snapshotFallback

        switch context.direction {
        case .opening:
            guard
                prepareOpeningLiveTransition(
                    with: context,
                    sourceViewController: sourceViewController,
                    destinationViewController: destinationViewController
                )
            else {
                prepareSnapshotFallback(
                    with: context,
                    sourceViewController: sourceViewController,
                    destinationViewController: destinationViewController
                )
                return
            }

            liveStrategy = .liveOpening
        case .closing:
            guard
                prepareClosingLiveTransition(
                    with: context,
                    sourceViewController: sourceViewController
                )
            else {
                prepareSnapshotFallback(
                    with: context,
                    sourceViewController: sourceViewController,
                    destinationViewController: destinationViewController
                )
                return
            }

            liveStrategy = .liveClosing
        }
    }

    func animateTransition(completion: @escaping () -> Void) {
        guard let context = currentContext else {
            completion()
            return
        }

        switch (context.direction, liveStrategy) {
        case (.opening, .liveOpening):
            animateLiveOpeningTransition(completion: completion)
        case (.closing, .liveClosing):
            animateLiveClosingTransition(completion: completion)
        case (.opening, .snapshotFallback), (.closing, .snapshotFallback):
            snapshotFallbackCarrier.animateTransition(completion: completion)
        default:
            completion()
        }
    }

    func updateTransitionContext(_ context: BoardListCanvasTransitionContext) {
        currentContext = context
        switch liveStrategy {
        case .liveClosing:
            let targetFrameResolution = resolveLiveClosingTargetFrame(using: context)
            liveTargetFrame = targetFrameResolution?.rect
            liveTargetRectSource = targetFrameResolution?.source
        case .snapshotFallback:
            snapshotFallbackCarrier.updateTransitionContext(context)
        case .liveOpening:
            break
        }
    }

    func completeTransition() {
        switch liveStrategy {
        case .liveOpening:
            cleanupLiveTransitionArtifacts(
                restoreCanvasToHost: false,
                restoreChromeVisibility: false,
                removeLiveCanvasFromHierarchy: false,
                clearContext: true,
                restoreTransitionPhase: nil,
                restoreTrigger: nil
            )
        case .liveClosing:
            cleanupLiveTransitionArtifacts(
                restoreCanvasToHost: false,
                restoreChromeVisibility: false,
                removeLiveCanvasFromHierarchy: true,
                clearContext: true,
                restoreTransitionPhase: nil,
                restoreTrigger: nil
            )
        case .snapshotFallback:
            snapshotFallbackCarrier.completeTransition()
            cleanupLiveTransitionArtifacts(
                restoreCanvasToHost: false,
                restoreChromeVisibility: false,
                removeLiveCanvasFromHierarchy: false,
                clearContext: true,
                restoreTransitionPhase: nil,
                restoreTrigger: nil
            )
        }
    }

    func cancelTransition() {
        switch liveStrategy {
        case .liveOpening, .liveClosing:
            let transitionPhase: String
            switch liveStrategy {
            case .liveOpening:
                transitionPhase = "opening"
            case .liveClosing:
                transitionPhase = "closing"
            case .snapshotFallback:
                transitionPhase = "snapshotFallback"
            }
            cleanupLiveTransitionArtifacts(
                restoreCanvasToHost: true,
                restoreChromeVisibility: true,
                removeLiveCanvasFromHierarchy: false,
                clearContext: true,
                restoreTransitionPhase: transitionPhase,
                restoreTrigger: "cancelTransition"
            )
        case .snapshotFallback:
            snapshotFallbackCarrier.cancelTransition()
            cleanupLiveTransitionArtifacts(
                restoreCanvasToHost: false,
                restoreChromeVisibility: false,
                removeLiveCanvasFromHierarchy: false,
                clearContext: true,
                restoreTransitionPhase: nil,
                restoreTrigger: nil
            )
        }
    }

    private func prepareOpeningLiveTransition(
        with context: BoardListCanvasTransitionContext,
        sourceViewController: UIViewController?,
        destinationViewController: UIViewController?
    ) -> Bool {
        guard let overlayHostView else {
            logLiveCarrierFallback(
                phase: "openingLiveFallback",
                reason: "overlayHostViewMissing"
            )
            return false
        }
        guard let sourceViewController else {
            logLiveCarrierFallback(
                phase: "openingLiveFallback",
                reason: "sourceViewControllerMissing"
            )
            return false
        }
        guard
            let sourceRectResolution = preferredRectResolution(
                from: context.sourceGeometry
            )
        else {
            logLiveCarrierFallback(
                phase: "openingLiveFallback",
                reason: "sourcePreferredRectMissing"
            )
            return false
        }
        guard let destinationViewController else {
            logLiveCarrierFallback(
                phase: "openingLiveFallback",
                reason: "destinationViewControllerMissing"
            )
            return false
        }
        guard let liveCanvasView = requirements.canvasViewProvider() else {
            logLiveCarrierFallback(
                phase: "openingLiveFallback",
                reason: "destinationCanvasViewMissing"
            )
            return false
        }
        guard let liveCanvasHostView = requirements.canvasContainerViewProvider() else {
            logLiveCarrierFallback(
                phase: "openingLiveFallback",
                reason: "destinationCanvasHostViewMissing"
            )
            return false
        }
        guard liveCanvasView.isDescendant(of: liveCanvasHostView) else {
            logLiveCarrierFallback(
                phase: "openingLiveFallback",
                reason: "destinationCanvasViewNotHosted"
            )
            return false
        }

        overlayHostView.layoutIfNeeded()
        sourceViewController.view.layoutIfNeeded()
        destinationViewController.loadViewIfNeeded()
        destinationViewController.view.layoutIfNeeded()
        liveCanvasHostView.layoutIfNeeded()

        let sourceFrame = overlayHostView.convert(
            sourceRectResolution.rect,
            from: sourceViewController.view
        ).standardized
        let targetFrame = overlayHostView.convert(
            liveCanvasHostView.bounds,
            from: liveCanvasHostView
        ).standardized
        guard sourceFrame.isEmpty == false else {
            logLiveCarrierFallback(
                phase: "openingLiveFallback",
                reason: "sourceFrameInvalid"
            )
            return false
        }
        guard targetFrame.isEmpty == false else {
            logLiveCarrierFallback(
                phase: "openingLiveFallback",
                reason: "targetFrameInvalid"
            )
            return false
        }

        originalChromeHiddenState = requirements.isTransitionChromeHidden()
        requirements.setTransitionChromeHidden(true)

        let liveContainerView = UIView(frame: targetFrame)
        liveContainerView.backgroundColor = .clear
        liveContainerView.isUserInteractionEnabled = false
        liveContainerView.clipsToBounds = true
        liveContainerView.layer.cornerRadius = previewCornerRadius(
            for: sourceFrame
        )
        liveContainerView.center = CGPoint(
            x: sourceFrame.midX,
            y: sourceFrame.midY
        )
        liveContainerView.transform = openingScaleTransform(
            sourceFrame: sourceFrame,
            targetFrame: targetFrame
        )

        let reparentStart = BoardListCanvasTransitionDebugLogger.now()
        attachLiveCanvasViewToContainer(
            liveCanvasView,
            containerView: liveContainerView
        )
        overlayHostView.addSubview(liveContainerView)
        let reparentDuration = BoardListCanvasTransitionDebugLogger.now() - reparentStart

        self.liveCanvasView = liveCanvasView
        self.liveCanvasHostView = liveCanvasHostView
        self.liveContainerView = liveContainerView
        self.liveTargetFrame = targetFrame
        isCanvasMountedInOverlay = true

        logLiveCarrierTrace(
            phase: "liveReparentFinished",
            localDuration: reparentDuration,
            extra:
                "transitionPhase=opening " +
                "sourceRectSource=\(sourceRectResolution.source.rawValue)"
        )
        logLiveCarrierTrace(
            phase: "livePrepareFinished",
            extra:
                "transitionPhase=opening " +
                "sourceRectSource=\(sourceRectResolution.source.rawValue)"
        )

        logLiveCarrierEvent(
            phase: "openingPrepareFinished",
            extra:
                "sourceRectSource=\(sourceRectResolution.source.rawValue) " +
                "sourceFrame=\(describe(rect: sourceFrame)) " +
                "targetFrame=\(describe(rect: targetFrame))"
        )
        return true
    }

    private func prepareClosingLiveTransition(
        with context: BoardListCanvasTransitionContext,
        sourceViewController: UIViewController?
    ) -> Bool {
        guard let overlayHostView else {
            logLiveCarrierFallback(
                phase: "closingLiveFallback",
                reason: "overlayHostViewMissing"
            )
            return false
        }
        guard let sourceViewController else {
            logLiveCarrierFallback(
                phase: "closingLiveFallback",
                reason: "sourceViewControllerMissing"
            )
            return false
        }
        guard let liveCanvasView = requirements.canvasViewProvider() else {
            logLiveCarrierFallback(
                phase: "closingLiveFallback",
                reason: "sourceCanvasViewMissing"
            )
            return false
        }
        guard let liveCanvasHostView = requirements.canvasContainerViewProvider() else {
            logLiveCarrierFallback(
                phase: "closingLiveFallback",
                reason: "sourceCanvasHostViewMissing"
            )
            return false
        }
        guard liveCanvasView.isDescendant(of: liveCanvasHostView) else {
            logLiveCarrierFallback(
                phase: "closingLiveFallback",
                reason: "sourceCanvasViewNotHosted"
            )
            return false
        }

        overlayHostView.layoutIfNeeded()
        sourceViewController.view.layoutIfNeeded()
        liveCanvasHostView.layoutIfNeeded()

        let sourceFrame = overlayHostView.convert(
            liveCanvasHostView.bounds,
            from: liveCanvasHostView
        ).standardized
        guard sourceFrame.isEmpty == false else {
            logLiveCarrierFallback(
                phase: "closingLiveFallback",
                reason: "sourceFrameInvalid"
            )
            return false
        }

        originalChromeHiddenState = requirements.isTransitionChromeHidden()
        requirements.setTransitionChromeHidden(true)

        let liveContainerView = UIView(frame: sourceFrame)
        liveContainerView.backgroundColor = .clear
        liveContainerView.isUserInteractionEnabled = false
        liveContainerView.clipsToBounds = true
        liveContainerView.layer.cornerRadius = 0

        let reparentStart = BoardListCanvasTransitionDebugLogger.now()
        attachLiveCanvasViewToContainer(
            liveCanvasView,
            containerView: liveContainerView
        )
        overlayHostView.addSubview(liveContainerView)
        let reparentDuration = BoardListCanvasTransitionDebugLogger.now() - reparentStart

        self.liveCanvasView = liveCanvasView
        self.liveCanvasHostView = liveCanvasHostView
        self.liveContainerView = liveContainerView
        let targetFrameResolution = resolveLiveClosingTargetFrame(using: context)
        self.liveTargetFrame = targetFrameResolution?.rect
        self.liveTargetRectSource = targetFrameResolution?.source
        isCanvasMountedInOverlay = true

        logLiveCarrierTrace(
            phase: "liveReparentFinished",
            localDuration: reparentDuration,
            extra:
                "transitionPhase=closing " +
                "targetRectSource=\(targetFrameResolution?.source.rawValue ?? "pending")"
        )
        logLiveCarrierTrace(
            phase: "livePrepareFinished",
            extra:
                "transitionPhase=closing " +
                "targetRectSource=\(targetFrameResolution?.source.rawValue ?? "pending")"
        )

        logLiveCarrierEvent(
            phase: "closingPrepareFinished",
            extra:
                "sourceFrame=\(describe(rect: sourceFrame)) " +
                "targetRectSource=\(targetFrameResolution?.source.rawValue ?? "pending")"
        )
        return true
    }

    private func animateLiveOpeningTransition(completion: @escaping () -> Void) {
        guard
            let liveContainerView,
            let liveTargetFrame
        else {
            logLiveCarrierFallback(
                phase: "openingLiveFallback",
                reason: "liveContainerUnavailable"
            )
            destinationViewController?.view.isHidden = false
            destinationViewController?.view.alpha = 1
            let restoreStart = BoardListCanvasTransitionDebugLogger.now()
            let restoreOutcome = restoreLiveCanvasToHostIfNeeded()
            logLiveRestoreFinished(
                transitionPhase: "opening",
                trigger: "openingAnimateFallback",
                outcome: restoreOutcome,
                localDuration: BoardListCanvasTransitionDebugLogger.now() - restoreStart
            )
            restoreChromeVisibilityIfNeeded(animated: false) {
                completion()
            }
            return
        }

        logLiveCarrierTrace(
            phase: "liveZoomBegin",
            extra:
                "transitionPhase=opening " +
                "targetFrame=\(describe(rect: liveTargetFrame))"
        )
        UIView.animate(
            withDuration: BoardListCanvasTransitionConfiguration.openingAnimation.duration,
            delay: 0,
            usingSpringWithDamping: BoardListCanvasTransitionConfiguration.openingAnimation.springDampingRatio ?? 1,
            initialSpringVelocity: BoardListCanvasTransitionConfiguration.openingAnimation.springInitialVelocity ?? 0,
            options: [
                .beginFromCurrentState,
                Self.animationOptions(
                    for: BoardListCanvasTransitionConfiguration.openingAnimation.curve
                )
            ]
        ) {
            liveContainerView.center = CGPoint(
                x: liveTargetFrame.midX,
                y: liveTargetFrame.midY
            )
            liveContainerView.transform = .identity
            liveContainerView.layer.cornerRadius = 0
        } completion: { [weak self] _ in
            self?.performLiveOpeningHandoff(completion: completion)
        }
    }

    private func animateLiveClosingTransition(completion: @escaping () -> Void) {
        guard let destinationView = destinationViewController?.view else {
            fallbackToSnapshotClosing(
                reason: "destinationViewMissing",
                completion: completion
            )
            return
        }
        destinationView.isHidden = false
        destinationView.alpha = 1
        destinationView.superview?.layoutIfNeeded()

        guard let liveContainerView else {
            fallbackToSnapshotClosing(
                reason: "liveContainerUnavailable",
                completion: completion
            )
            return
        }
        let targetFrameResolution = liveTargetFrame.map { frame in
            PreferredRectResolution(
                rect: frame,
                source: liveTargetRectSource ?? .focusRect
            )
        } ?? {
            guard let currentContext else {
                return nil
            }
            return resolveLiveClosingTargetFrame(using: currentContext)
        }()
        guard let targetFrameResolution else {
            let fallbackReason = currentContext.flatMap {
                preferredRectResolution(from: $0.targetGeometry)
            } == nil
                ? "targetPreferredRectMissing"
                : "targetFrameInvalid"
            fallbackToSnapshotClosing(
                reason: fallbackReason,
                completion: completion
            )
            return
        }

        logLiveCarrierEvent(
            phase: "closingAnimateBegin",
            extra:
                "targetRectSource=\(targetFrameResolution.source.rawValue) " +
                "targetFrame=\(describe(rect: targetFrameResolution.rect))"
        )
        logLiveCarrierTrace(
            phase: "liveZoomBegin",
            extra:
                "transitionPhase=closing " +
                "targetRectSource=\(targetFrameResolution.source.rawValue) " +
                "targetFrame=\(describe(rect: targetFrameResolution.rect))"
        )
        UIView.animate(
            withDuration: BoardListCanvasTransitionConfiguration.closingAnimation.duration,
            delay: 0,
            options: [
                .beginFromCurrentState,
                Self.animationOptions(
                    for: BoardListCanvasTransitionConfiguration.closingAnimation.curve
                )
            ]
        ) {
            liveContainerView.frame = targetFrameResolution.rect
            liveContainerView.layer.cornerRadius = self.previewCornerRadius(
                for: targetFrameResolution.rect
            )
        } completion: { [weak self] _ in
            self?.performLiveClosingHandoff(completion: completion)
        }
    }

    private func performLiveOpeningHandoff(completion: @escaping () -> Void) {
        let handoffStart = BoardListCanvasTransitionDebugLogger.now()
        destinationViewController?.view.isHidden = false
        destinationViewController?.view.alpha = 1
        destinationViewController?.view.superview?.layoutIfNeeded()

        let restoreStart = BoardListCanvasTransitionDebugLogger.now()
        let restoreOutcome = restoreLiveCanvasToHostIfNeeded()
        let restoreDuration = BoardListCanvasTransitionDebugLogger.now() - restoreStart
        logLiveRestoreFinished(
            transitionPhase: "opening",
            trigger: "openingHandoff",
            outcome: restoreOutcome,
            localDuration: restoreDuration
        )
        liveContainerView?.removeFromSuperview()
        liveContainerView = nil
        liveTargetFrame = nil

        logLiveCarrierEvent(phase: "openingHandoffBegin")
        restoreChromeVisibilityIfNeeded(animated: true) { [weak self] in
            self?.logLiveCarrierEvent(phase: "openingHandoffFinished")
            self?.logLiveCarrierTrace(
                phase: "liveHandoffFinished",
                localDuration: BoardListCanvasTransitionDebugLogger.now() - handoffStart,
                extra:
                    "transitionPhase=opening " +
                    "restoreOutcome=\(restoreOutcome.rawValue)"
            )
            completion()
        }
    }

    private func performLiveClosingHandoff(completion: @escaping () -> Void) {
        let handoffStart = BoardListCanvasTransitionDebugLogger.now()
        liveContainerView?.removeFromSuperview()
        liveContainerView = nil
        liveTargetFrame = nil
        liveTargetRectSource = nil
        isCanvasMountedInOverlay = false
        logLiveCarrierEvent(phase: "closingHandoffFinished")
        logLiveRestoreFinished(
            transitionPhase: "closing",
            trigger: "closingHandoff",
            outcome: .notRequired,
            localDuration: nil
        )
        logLiveCarrierTrace(
            phase: "liveHandoffFinished",
            localDuration: BoardListCanvasTransitionDebugLogger.now() - handoffStart,
            extra: "transitionPhase=closing restoreOutcome=notRequired"
        )
        completion()
    }

    private func prepareSnapshotFallback(
        with context: BoardListCanvasTransitionContext,
        sourceViewController: UIViewController?,
        destinationViewController: UIViewController?
    ) {
        liveStrategy = .snapshotFallback
        snapshotFallbackCarrier.prepareTransition(
            with: context,
            sourceViewController: sourceViewController,
            destinationViewController: destinationViewController
        )
    }

    private func fallbackToSnapshotClosing(
        reason: String,
        completion: @escaping () -> Void
    ) {
        guard let context = currentContext else {
            completion()
            return
        }

        logLiveCarrierFallback(
            phase: "closingLiveFallback",
            reason: reason
        )
        cleanupLiveTransitionArtifacts(
            restoreCanvasToHost: true,
            restoreChromeVisibility: true,
            removeLiveCanvasFromHierarchy: false,
            clearContext: false,
            restoreTransitionPhase: "closing",
            restoreTrigger: "snapshotFallback"
        )
        sourceViewController?.view.layoutIfNeeded()
        destinationViewController?.view.layoutIfNeeded()
        prepareSnapshotFallback(
            with: context,
            sourceViewController: sourceViewController,
            destinationViewController: destinationViewController
        )
        snapshotFallbackCarrier.animateTransition(completion: completion)
    }

    private func attachLiveCanvasViewToContainer(
        _ liveCanvasView: UIView,
        containerView: UIView
    ) {
        liveCanvasView.removeFromSuperview()
        liveCanvasView.translatesAutoresizingMaskIntoConstraints = true
        liveCanvasView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        liveCanvasView.frame = containerView.bounds
        containerView.addSubview(liveCanvasView)
    }

    private func restoreLiveCanvasToHostIfNeeded() -> LiveCanvasRestoreOutcome {
        guard isCanvasMountedInOverlay else {
            return .skippedNotMounted
        }
        guard let liveCanvasView else {
            return .failedMissingCanvasView
        }
        guard let liveCanvasHostView else {
            return .failedMissingHostView
        }

        liveCanvasView.removeFromSuperview()
        liveCanvasView.translatesAutoresizingMaskIntoConstraints = false
        liveCanvasView.autoresizingMask = []
        liveCanvasHostView.addSubview(liveCanvasView)
        NSLayoutConstraint.activate([
            liveCanvasView.topAnchor.constraint(equalTo: liveCanvasHostView.topAnchor),
            liveCanvasView.leadingAnchor.constraint(equalTo: liveCanvasHostView.leadingAnchor),
            liveCanvasView.trailingAnchor.constraint(equalTo: liveCanvasHostView.trailingAnchor),
            liveCanvasView.bottomAnchor.constraint(equalTo: liveCanvasHostView.bottomAnchor)
        ])
        liveCanvasHostView.layoutIfNeeded()
        isCanvasMountedInOverlay = false
        return .restored
    }

    private func restoreChromeVisibilityIfNeeded(
        animated: Bool,
        completion: @escaping () -> Void
    ) {
        guard let originalChromeHiddenState else {
            completion()
            return
        }

        let restoreVisibility = {
            self.requirements.setTransitionChromeHidden(originalChromeHiddenState)
        }

        if animated {
            UIView.animate(
                withDuration: BoardListCanvasTransitionConfiguration.handoffAnimation.duration,
                delay: 0,
                options: [
                    .beginFromCurrentState,
                    Self.animationOptions(
                        for: BoardListCanvasTransitionConfiguration.handoffAnimation.curve
                    )
                ]
            ) {
                restoreVisibility()
            } completion: { _ in
                self.originalChromeHiddenState = nil
                completion()
            }
            return
        }

        restoreVisibility()
        self.originalChromeHiddenState = nil
        completion()
    }

    private func cleanupLiveTransitionArtifacts(
        restoreCanvasToHost: Bool,
        restoreChromeVisibility: Bool,
        removeLiveCanvasFromHierarchy: Bool,
        clearContext: Bool,
        restoreTransitionPhase: String?,
        restoreTrigger: String?
    ) {
        if restoreCanvasToHost {
            let restoreStart = BoardListCanvasTransitionDebugLogger.now()
            let restoreOutcome = restoreLiveCanvasToHostIfNeeded()
            if let restoreTransitionPhase, let restoreTrigger {
                logLiveRestoreFinished(
                    transitionPhase: restoreTransitionPhase,
                    trigger: restoreTrigger,
                    outcome: restoreOutcome,
                    localDuration: BoardListCanvasTransitionDebugLogger.now() - restoreStart
                )
            }
        } else if removeLiveCanvasFromHierarchy {
            liveCanvasView?.removeFromSuperview()
        }

        liveContainerView?.removeFromSuperview()
        liveContainerView = nil
        liveTargetFrame = nil
        liveTargetRectSource = nil

        if restoreChromeVisibility {
            restoreChromeVisibilityIfNeeded(animated: false) {}
        } else {
            originalChromeHiddenState = nil
        }

        liveCanvasView = nil
        liveCanvasHostView = nil
        liveStrategy = .snapshotFallback
        isCanvasMountedInOverlay = false

        if clearContext {
            currentContext = nil
            sourceViewController = nil
            destinationViewController = nil
        }
    }

    private func resolveLiveClosingTargetFrame(
        using context: BoardListCanvasTransitionContext
    ) -> PreferredRectResolution? {
        guard
            let overlayHostView,
            let destinationView = destinationViewController?.view,
            let targetRectResolution = preferredRectResolution(
                from: context.targetGeometry
            )
        else {
            return nil
        }

        let convertedTargetRect = overlayHostView.convert(
            targetRectResolution.rect,
            from: destinationView
        ).standardized
        guard convertedTargetRect.isEmpty == false else {
            return nil
        }

        return PreferredRectResolution(
            rect: convertedTargetRect,
            source: targetRectResolution.source
        )
    }

    private func preferredRectResolution(
        from geometry: BoardListCanvasTransitionSourceGeometry
    ) -> PreferredRectResolution? {
        if let focusRect = geometry.focusRect {
            return PreferredRectResolution(
                rect: focusRect,
                source: .focusRect
            )
        }
        if let cardRect = geometry.cardRect {
            return PreferredRectResolution(
                rect: cardRect,
                source: .cardRect
            )
        }
        return nil
    }

    private func preferredRectResolution(
        from geometry: BoardListCanvasTransitionTargetGeometry
    ) -> PreferredRectResolution? {
        if let focusRect = geometry.focusRect {
            return PreferredRectResolution(
                rect: focusRect,
                source: .focusRect
            )
        }
        if let cardRect = geometry.cardRect {
            return PreferredRectResolution(
                rect: cardRect,
                source: .cardRect
            )
        }
        return nil
    }

    private func previewCornerRadius(for rect: CGRect) -> CGFloat {
        min(
            Self.previewCornerRadius,
            min(rect.width, rect.height) / 2
        )
    }

    private func openingScaleTransform(
        sourceFrame: CGRect,
        targetFrame: CGRect
    ) -> CGAffineTransform {
        CGAffineTransform(
            scaleX: sourceFrame.width / targetFrame.width,
            y: sourceFrame.height / targetFrame.height
        )
    }

    private static func animationOptions(
        for curve: BoardListCanvasTransitionTimingCurve
    ) -> UIView.AnimationOptions {
        switch curve {
        case .easeInOut:
            return .curveEaseInOut
        case .easeOut:
            return .curveEaseOut
        }
    }

    private func logLiveCarrierFallback(
        phase: String,
        reason: String
    ) {
        print(
            "[BoardListCanvasTransition][iOS][LiveCarrier] " +
                "phase=\(phase) " +
                "reason=\(reason)"
        )
        logLiveCarrierTrace(
            phase: "liveFallbackTriggered",
            extra:
                "carrierPhase=\(phase) " +
                "reason=\(reason)"
        )
    }

    private func logLiveCarrierEvent(
        phase: String,
        extra: String = ""
    ) {
        let extraSuffix = extra.isEmpty ? "" : " \(extra)"
        print(
            "[BoardListCanvasTransition][iOS][LiveCarrier] " +
                "phase=\(phase)" +
                extraSuffix
        )
    }

    private func logLiveCarrierTrace(
        phase: String,
        localDuration: TimeInterval? = nil,
        extra: String = ""
    ) {
        guard let debugTrace else {
            return
        }

        BoardListCanvasTransitionDebugLogger.log(
            platform: "iOS",
            component: "LiveCarrier",
            trace: debugTrace,
            phase: phase,
            localDuration: localDuration,
            extra: extra
        )
    }

    private func logLiveRestoreFinished(
        transitionPhase: String,
        trigger: String,
        outcome: LiveCanvasRestoreOutcome,
        localDuration: TimeInterval?
    ) {
        logLiveCarrierTrace(
            phase: "liveRestoreFinished",
            localDuration: localDuration,
            extra:
                "transitionPhase=\(transitionPhase) " +
                "trigger=\(trigger) " +
                "outcome=\(outcome.rawValue)"
        )
    }

    private func describe(rect: CGRect) -> String {
        let standardized = rect.standardized
        return String(
            format: "{{%.2f, %.2f}, {%.2f, %.2f}}",
            standardized.minX,
            standardized.minY,
            standardized.width,
            standardized.height
        )
    }
}

final class iOSSnapshotShellCarrier: iOSBoardListCanvasTransitionCarrying {
    private weak var overlayHostView: UIView?
    private weak var sourceViewController: UIViewController?
    private weak var destinationViewController: UIViewController?
    private var currentContext: BoardListCanvasTransitionContext?
    private var shellShadowView: UIView?
    private var shellContentView: UIView?

    var kind: BoardListCanvasTransitionCarrierKind {
        .snapshotShell
    }

    func install(in overlayHostView: UIView) {
        if self.overlayHostView !== overlayHostView {
            removeShellViews()
            self.overlayHostView = overlayHostView
        }
    }

    func prepareTransition(
        with context: BoardListCanvasTransitionContext,
        sourceViewController: UIViewController?,
        destinationViewController: UIViewController?
    ) {
        currentContext = context
        self.sourceViewController = sourceViewController
        self.destinationViewController = destinationViewController
        switch context.direction {
        case .opening:
            prepareOpeningShell(using: context)
        case .closing:
            prepareClosingShell()
        }
    }

    func animateTransition(completion: @escaping () -> Void) {
        guard let context = currentContext else {
            completion()
            return
        }

        switch context.direction {
        case .opening:
            animateOpeningTransition(completion: completion)
        case .closing:
            animateClosingTransition(completion: completion)
        }
    }

    func updateTransitionContext(_ context: BoardListCanvasTransitionContext) {
        currentContext = context
    }

    func completeTransition() {
        resetTransitionState()
    }

    func cancelTransition() {
        resetTransitionState()
    }

    private func prepareOpeningShell(using context: BoardListCanvasTransitionContext) {
        removeShellViews()
        guard
            let overlayHostView,
            let sourceViewController,
            let sourceRect = context.sourceGeometry.preferredRect
        else {
            return
        }

        overlayHostView.layoutIfNeeded()
        sourceViewController.view.layoutIfNeeded()

        let convertedSourceRect = overlayHostView.convert(
            sourceRect,
            from: sourceViewController.view
        ).standardized
        guard convertedSourceRect.isEmpty == false else {
            return
        }

        let shadowView = UIView(frame: convertedSourceRect)
        let contentView = makeShellContentView(
            frame: shadowView.bounds,
            cornerRadius: BoardListCanvasTransitionConfiguration.shellCornerRadius
        )
        configureShadow(
            for: shadowView,
            opacity: BoardListCanvasTransitionConfiguration.shellShadowOpacity
        )

        if let snapshotView = sourceViewController.view.resizableSnapshotView(
            from: sourceRect,
            afterScreenUpdates: false,
            withCapInsets: .zero
        ) {
            snapshotView.frame = contentView.bounds
            snapshotView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            contentView.addSubview(snapshotView)
        }

        shadowView.addSubview(contentView)
        overlayHostView.addSubview(shadowView)
        shellShadowView = shadowView
        shellContentView = contentView
    }

    private func prepareClosingShell() {
        removeShellViews()
        guard
            let overlayHostView,
            let sourceView = sourceViewController?.view
        else {
            return
        }

        overlayHostView.layoutIfNeeded()
        sourceView.layoutIfNeeded()
        sourceView.superview?.layoutIfNeeded()

        let fullscreenFrame = overlayHostView.bounds.standardized
        guard fullscreenFrame.isEmpty == false else {
            return
        }

        let shadowView = UIView(frame: fullscreenFrame)
        let contentView = makeShellContentView(
            frame: shadowView.bounds,
            cornerRadius: 0
        )
        configureShadow(for: shadowView, opacity: 0)

        if let snapshotView = sourceView.resizableSnapshotView(
            from: sourceView.bounds,
            afterScreenUpdates: false,
            withCapInsets: .zero
        ) {
            snapshotView.frame = contentView.bounds
            snapshotView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            contentView.addSubview(snapshotView)
        }

        shadowView.addSubview(contentView)
        overlayHostView.addSubview(shadowView)
        shellShadowView = shadowView
        shellContentView = contentView
    }

    private func animateOpeningTransition(completion: @escaping () -> Void) {
        guard
            let overlayHostView,
            let destinationView = destinationViewController?.view
        else {
            completion()
            return
        }

        overlayHostView.layoutIfNeeded()
        destinationView.superview?.layoutIfNeeded()

        guard let shellShadowView, let shellContentView else {
            destinationView.isHidden = false
            destinationView.alpha = 0
            UIView.animate(
                withDuration: BoardListCanvasTransitionConfiguration.handoffAnimation.duration,
                delay: 0,
                options: [Self.animationOptions(for: BoardListCanvasTransitionConfiguration.handoffAnimation.curve), .beginFromCurrentState]
            ) {
                destinationView.alpha = 1
            } completion: { _ in
                completion()
            }
            return
        }

        shellShadowView.isHidden = false
        let targetFrame = overlayHostView.bounds.standardized
        UIView.animate(
            withDuration: BoardListCanvasTransitionConfiguration.openingAnimation.duration,
            delay: 0,
            usingSpringWithDamping: BoardListCanvasTransitionConfiguration.openingAnimation.springDampingRatio ?? 1,
            initialSpringVelocity: BoardListCanvasTransitionConfiguration.openingAnimation.springInitialVelocity ?? 0,
            options: [.beginFromCurrentState, Self.animationOptions(for: BoardListCanvasTransitionConfiguration.openingAnimation.curve)]
        ) {
            shellShadowView.frame = targetFrame
            shellContentView.layer.cornerRadius = 0
            shellShadowView.layer.shadowOpacity = 0
        } completion: { _ in
            destinationView.isHidden = false
            destinationView.alpha = 0
            destinationView.superview?.layoutIfNeeded()
            UIView.animate(
                withDuration: BoardListCanvasTransitionConfiguration.handoffAnimation.duration,
                delay: 0,
                options: [Self.animationOptions(for: BoardListCanvasTransitionConfiguration.handoffAnimation.curve), .beginFromCurrentState]
            ) {
                destinationView.alpha = 1
                shellShadowView.alpha = 0
            } completion: { _ in
                completion()
            }
        }
    }

    private func animateClosingTransition(completion: @escaping () -> Void) {
        guard
            let overlayHostView,
            let destinationView = destinationViewController?.view
        else {
            completion()
            return
        }

        overlayHostView.layoutIfNeeded()
        destinationView.isHidden = false
        destinationView.alpha = 1
        destinationView.superview?.layoutIfNeeded()

        guard let shellShadowView, let shellContentView else {
            completion()
            return
        }

        shellShadowView.isHidden = false
        shellShadowView.alpha = 1

        let targetFrame = resolvedClosingTargetFrame(in: overlayHostView)
        let fallbackFrame = fallbackClosingFrame(in: overlayHostView)

        if let targetFrame {
            UIView.animate(
                withDuration: BoardListCanvasTransitionConfiguration.closingAnimation.duration,
                delay: 0,
                options: [.beginFromCurrentState, Self.animationOptions(for: BoardListCanvasTransitionConfiguration.closingAnimation.curve)]
            ) {
                shellShadowView.frame = targetFrame
                shellContentView.layer.cornerRadius = BoardListCanvasTransitionConfiguration.shellCornerRadius
                shellShadowView.layer.shadowOpacity = BoardListCanvasTransitionConfiguration.shellShadowOpacity
            } completion: { _ in
                UIView.animate(
                    withDuration: BoardListCanvasTransitionConfiguration.handoffAnimation.duration,
                    delay: 0,
                    options: [Self.animationOptions(for: BoardListCanvasTransitionConfiguration.handoffAnimation.curve), .beginFromCurrentState]
                ) {
                    shellShadowView.alpha = 0
                } completion: { _ in
                    completion()
                }
            }
            return
        }

        destinationView.alpha = 0
        UIView.animate(
            withDuration: BoardListCanvasTransitionConfiguration.closingAnimation.duration,
            delay: 0,
            options: [.beginFromCurrentState, Self.animationOptions(for: BoardListCanvasTransitionConfiguration.closingAnimation.curve)]
        ) {
            shellShadowView.frame = fallbackFrame
            shellContentView.layer.cornerRadius = BoardListCanvasTransitionConfiguration.shellCornerRadius
            shellShadowView.layer.shadowOpacity = BoardListCanvasTransitionConfiguration.shellShadowOpacity
            shellShadowView.alpha = 0
            destinationView.alpha = 1
        } completion: { _ in
            completion()
        }
    }

    private func resolvedClosingTargetFrame(
        in overlayHostView: UIView
    ) -> CGRect? {
        guard
            let destinationView = destinationViewController?.view,
            let targetRect = currentContext?.targetGeometry.preferredRect
        else {
            return nil
        }

        let convertedTargetRect = overlayHostView.convert(
            targetRect,
            from: destinationView
        ).standardized
        guard convertedTargetRect.isEmpty == false else {
            return nil
        }

        return convertedTargetRect
    }

    private func fallbackClosingFrame(in overlayHostView: UIView) -> CGRect {
        let bounds = overlayHostView.bounds.standardized
        let scaledWidth = bounds.width * BoardListCanvasTransitionConfiguration.fallbackClosingScale
        let scaledHeight = bounds.height * BoardListCanvasTransitionConfiguration.fallbackClosingScale
        return CGRect(
            x: bounds.midX - (scaledWidth / 2),
            y: bounds.midY - (scaledHeight / 2),
            width: scaledWidth,
            height: scaledHeight
        ).integral
    }

    private func makeShellContentView(
        frame: CGRect,
        cornerRadius: CGFloat
    ) -> UIView {
        let contentView = UIView(frame: frame)
        contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.backgroundColor = .secondarySystemBackground
        contentView.layer.cornerRadius = cornerRadius
        contentView.layer.masksToBounds = true
        return contentView
    }

    private func configureShadow(
        for shadowView: UIView,
        opacity: Float
    ) {
        shadowView.backgroundColor = .clear
        shadowView.isUserInteractionEnabled = false
        shadowView.layer.shadowColor = UIColor.black.cgColor
        shadowView.layer.shadowOpacity = opacity
        shadowView.layer.shadowRadius = BoardListCanvasTransitionConfiguration.shellShadowRadius
        shadowView.layer.shadowOffset = BoardListCanvasTransitionConfiguration.iOSShellShadowOffset
    }

    private static func animationOptions(
        for curve: BoardListCanvasTransitionTimingCurve
    ) -> UIView.AnimationOptions {
        switch curve {
        case .easeInOut:
            return .curveEaseInOut
        case .easeOut:
            return .curveEaseOut
        }
    }

    private func removeShellViews() {
        shellContentView?.removeFromSuperview()
        shellContentView = nil
        shellShadowView?.removeFromSuperview()
        shellShadowView = nil
    }

    private func resetTransitionState() {
        removeShellViews()
        currentContext = nil
        sourceViewController = nil
        destinationViewController = nil
    }
}
#endif
