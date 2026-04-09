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
        liveCanvasRequirements: iOSLiveCanvasCarrierRequirements? = nil
    ) -> any iOSBoardListCanvasTransitionCarrying {
        switch preferredKind {
        case .snapshotShell:
            return iOSSnapshotShellCarrier()
        case .liveCanvas:
            guard let liveCanvasRequirements else {
                return iOSSnapshotShellCarrier()
            }
            return iOSLiveCanvasCarrier(
                requirements: liveCanvasRequirements
            )
        }
    }
}

final class iOSLiveCanvasCarrier: iOSBoardListCanvasTransitionCarrying {
    private enum Strategy {
        case liveOpening
        case snapshotFallback
    }

    private static let openingPreviewCornerRadius: CGFloat = 10

    private let requirements: iOSLiveCanvasCarrierRequirements
    private let snapshotFallbackCarrier: iOSSnapshotShellCarrier

    private weak var overlayHostView: UIView?
    private weak var sourceViewController: UIViewController?
    private weak var destinationViewController: UIViewController?
    private weak var liveCanvasHostView: UIView?

    private var currentContext: BoardListCanvasTransitionContext?
    private var liveCanvasView: UIView?
    private var liveContainerView: UIView?
    private var liveTargetFrame: CGRect?
    private var liveStrategy: Strategy = .snapshotFallback
    private var originalChromeHiddenState: Bool?
    private var isCanvasMountedInOverlay = false

    init(
        requirements: iOSLiveCanvasCarrierRequirements,
        snapshotFallbackCarrier: iOSSnapshotShellCarrier = iOSSnapshotShellCarrier()
    ) {
        self.requirements = requirements
        self.snapshotFallbackCarrier = snapshotFallbackCarrier
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
        cleanupLiveOpeningArtifacts(
            restoreCanvasToHost: true,
            restoreChromeVisibility: true
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
                snapshotFallbackCarrier.prepareTransition(
                    with: context,
                    sourceViewController: sourceViewController,
                    destinationViewController: destinationViewController
                )
                return
            }

            liveStrategy = .liveOpening
        case .closing:
            logLiveOpeningFallback(reason: "closingLiveNotImplemented")
            snapshotFallbackCarrier.prepareTransition(
                with: context,
                sourceViewController: sourceViewController,
                destinationViewController: destinationViewController
            )
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
        case (.opening, .snapshotFallback), (.closing, _):
            snapshotFallbackCarrier.animateTransition(completion: completion)
        }
    }

    func updateTransitionContext(_ context: BoardListCanvasTransitionContext) {
        currentContext = context
        guard liveStrategy == .snapshotFallback else {
            return
        }
        snapshotFallbackCarrier.updateTransitionContext(context)
    }

    func completeTransition() {
        switch liveStrategy {
        case .liveOpening:
            cleanupLiveOpeningArtifacts(
                restoreCanvasToHost: true,
                restoreChromeVisibility: true
            )
        case .snapshotFallback:
            snapshotFallbackCarrier.completeTransition()
            cleanupLiveOpeningArtifacts(
                restoreCanvasToHost: false,
                restoreChromeVisibility: false
            )
        }
    }

    func cancelTransition() {
        switch liveStrategy {
        case .liveOpening:
            cleanupLiveOpeningArtifacts(
                restoreCanvasToHost: true,
                restoreChromeVisibility: true
            )
        case .snapshotFallback:
            snapshotFallbackCarrier.cancelTransition()
            cleanupLiveOpeningArtifacts(
                restoreCanvasToHost: false,
                restoreChromeVisibility: false
            )
        }
    }

    private func prepareOpeningLiveTransition(
        with context: BoardListCanvasTransitionContext,
        sourceViewController: UIViewController?,
        destinationViewController: UIViewController?
    ) -> Bool {
        guard let overlayHostView else {
            logLiveOpeningFallback(reason: "overlayHostViewMissing")
            return false
        }
        guard let sourceViewController else {
            logLiveOpeningFallback(reason: "sourceViewControllerMissing")
            return false
        }
        guard let destinationViewController else {
            logLiveOpeningFallback(reason: "destinationViewControllerMissing")
            return false
        }
        guard let sourceFocusRect = context.sourceGeometry.focusRect else {
            logLiveOpeningFallback(reason: "sourceFocusRectMissing")
            return false
        }
        guard let liveCanvasView = requirements.canvasViewProvider() else {
            logLiveOpeningFallback(reason: "destinationCanvasViewMissing")
            return false
        }
        guard let liveCanvasHostView = requirements.canvasContainerViewProvider() else {
            logLiveOpeningFallback(reason: "destinationCanvasHostViewMissing")
            return false
        }
        guard liveCanvasView.isDescendant(of: liveCanvasHostView) else {
            logLiveOpeningFallback(reason: "destinationCanvasViewNotHosted")
            return false
        }

        overlayHostView.layoutIfNeeded()
        sourceViewController.view.layoutIfNeeded()
        destinationViewController.loadViewIfNeeded()
        destinationViewController.view.layoutIfNeeded()
        liveCanvasHostView.layoutIfNeeded()

        let sourceFrame = overlayHostView.convert(
            sourceFocusRect,
            from: sourceViewController.view
        ).standardized
        let targetFrame = overlayHostView.convert(
            liveCanvasHostView.bounds,
            from: liveCanvasHostView
        ).standardized
        guard sourceFrame.isEmpty == false else {
            logLiveOpeningFallback(reason: "sourceFrameInvalid")
            return false
        }
        guard targetFrame.isEmpty == false else {
            logLiveOpeningFallback(reason: "targetFrameInvalid")
            return false
        }

        originalChromeHiddenState = requirements.isTransitionChromeHidden()
        requirements.setTransitionChromeHidden(true)

        let liveContainerView = UIView(frame: targetFrame)
        liveContainerView.backgroundColor = .clear
        liveContainerView.isUserInteractionEnabled = false
        liveContainerView.clipsToBounds = true
        liveContainerView.layer.cornerRadius = openingCornerRadius(
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

        attachLiveCanvasViewToOverlay(
            liveCanvasView,
            containerView: liveContainerView
        )
        overlayHostView.addSubview(liveContainerView)

        self.liveCanvasView = liveCanvasView
        self.liveCanvasHostView = liveCanvasHostView
        self.liveContainerView = liveContainerView
        self.liveTargetFrame = targetFrame
        isCanvasMountedInOverlay = true

        logLiveOpeningEvent(
            phase: "prepareFinished",
            extra:
                "sourceFrame=\(describe(rect: sourceFrame)) " +
                "targetFrame=\(describe(rect: targetFrame))"
        )
        return true
    }

    private func animateLiveOpeningTransition(completion: @escaping () -> Void) {
        guard
            let liveContainerView,
            let liveTargetFrame
        else {
            logLiveOpeningFallback(reason: "liveContainerUnavailable")
            destinationViewController?.view.isHidden = false
            destinationViewController?.view.alpha = 1
            restoreLiveCanvasToHostIfNeeded()
            restoreChromeVisibilityIfNeeded(animated: false) {
                completion()
            }
            return
        }

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

    private func performLiveOpeningHandoff(completion: @escaping () -> Void) {
        destinationViewController?.view.isHidden = false
        destinationViewController?.view.alpha = 1
        destinationViewController?.view.superview?.layoutIfNeeded()

        restoreLiveCanvasToHostIfNeeded()
        liveContainerView?.removeFromSuperview()
        liveContainerView = nil
        liveTargetFrame = nil

        logLiveOpeningEvent(phase: "handoffBegin")
        restoreChromeVisibilityIfNeeded(animated: true) { [weak self] in
            self?.logLiveOpeningEvent(phase: "handoffFinished")
            completion()
        }
    }

    private func attachLiveCanvasViewToOverlay(
        _ liveCanvasView: UIView,
        containerView: UIView
    ) {
        liveCanvasView.removeFromSuperview()
        liveCanvasView.translatesAutoresizingMaskIntoConstraints = true
        liveCanvasView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        liveCanvasView.frame = containerView.bounds
        containerView.addSubview(liveCanvasView)
    }

    private func restoreLiveCanvasToHostIfNeeded() {
        guard
            isCanvasMountedInOverlay,
            let liveCanvasView,
            let liveCanvasHostView
        else {
            return
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

    private func cleanupLiveOpeningArtifacts(
        restoreCanvasToHost: Bool,
        restoreChromeVisibility: Bool
    ) {
        if restoreCanvasToHost {
            restoreLiveCanvasToHostIfNeeded()
        }
        liveContainerView?.removeFromSuperview()
        liveContainerView = nil
        liveTargetFrame = nil

        if restoreChromeVisibility {
            restoreChromeVisibilityIfNeeded(animated: false) {}
        } else {
            originalChromeHiddenState = nil
        }

        liveCanvasView = nil
        liveCanvasHostView = nil
        currentContext = nil
        sourceViewController = nil
        destinationViewController = nil
        liveStrategy = .snapshotFallback
        isCanvasMountedInOverlay = false
    }

    private func openingCornerRadius(for sourceFrame: CGRect) -> CGFloat {
        min(
            Self.openingPreviewCornerRadius,
            min(sourceFrame.width, sourceFrame.height) / 2
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

    private func logLiveOpeningFallback(reason: String) {
        print(
            "[BoardListCanvasTransition][iOS][LiveCarrier] " +
                "phase=openingLiveFallback " +
                "reason=\(reason)"
        )
    }

    private func logLiveOpeningEvent(
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
