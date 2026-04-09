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
}

enum iOSBoardListCanvasTransitionCarrierFactory {
    static func makeCarrier(
        preferredKind: BoardListCanvasTransitionCarrierKind
    ) -> any iOSBoardListCanvasTransitionCarrying {
        switch preferredKind {
        case .snapshotShell:
            return iOSSnapshotShellCarrier()
        case .liveCanvas:
            // Phase 3 keeps the live carrier boundary explicit while
            // still routing through the snapshot shell implementation.
            return iOSSnapshotShellCarrier()
        }
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
            let sourceRect = context.sourceGeometry.cardRect
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
            let targetRect = currentContext?.targetGeometry.cardRect
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
