#if os(macOS)
import AppKit

protocol macOSBoardListCanvasTransitionCarrying: AnyObject {
    var kind: BoardListCanvasTransitionCarrierKind { get }

    func install(in overlayHostView: NSView)
    func prepareTransition(
        with context: BoardListCanvasTransitionContext,
        sourceViewController: NSViewController?,
        destinationViewController: NSViewController?
    )
    func animateTransition(completion: @escaping () -> Void)
    func updateTransitionContext(_ context: BoardListCanvasTransitionContext)
    func completeTransition()
    func cancelTransition()
}

struct macOSLiveCanvasCarrierRequirements {
    let canvasViewProvider: () -> NSView?
    let canvasContainerViewProvider: () -> NSView?
}

enum macOSBoardListCanvasTransitionCarrierFactory {
    static func makeCarrier(
        preferredKind: BoardListCanvasTransitionCarrierKind
    ) -> any macOSBoardListCanvasTransitionCarrying {
        switch preferredKind {
        case .snapshotShell:
            return macOSSnapshotShellCarrier()
        case .liveCanvas:
            // Phase 3 keeps the live carrier boundary explicit while
            // still routing through the snapshot shell implementation.
            return macOSSnapshotShellCarrier()
        }
    }
}

final class macOSSnapshotShellCarrier: macOSBoardListCanvasTransitionCarrying {
    private weak var overlayHostView: NSView?
    private weak var sourceViewController: NSViewController?
    private weak var destinationViewController: NSViewController?
    private var currentContext: BoardListCanvasTransitionContext?
    private var shellShadowView: NSView?
    private var shellContentView: NSView?
    private static let openingDuration: TimeInterval = 0.38
    private static let closingDuration: TimeInterval = 0.32
    private static let handoffDuration: TimeInterval = 0.14
    private static let shellCornerRadius: CGFloat = 12
    private static let shellShadowOpacity: Float = 0.08
    private static let shellShadowRadius: CGFloat = 16
    private static let shellShadowOffset = CGSize(width: 0, height: -8)
    private static let fallbackClosingScale: CGFloat = 0.82

    var kind: BoardListCanvasTransitionCarrierKind {
        .snapshotShell
    }

    func install(in overlayHostView: NSView) {
        if self.overlayHostView !== overlayHostView {
            removeShellViews()
            self.overlayHostView = overlayHostView
        }
    }

    func prepareTransition(
        with context: BoardListCanvasTransitionContext,
        sourceViewController: NSViewController?,
        destinationViewController: NSViewController?
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

        overlayHostView.layoutSubtreeIfNeeded()
        sourceViewController.view.layoutSubtreeIfNeeded()

        let convertedSourceRect = overlayHostView.convert(
            sourceRect,
            from: sourceViewController.view
        ).standardized
        guard convertedSourceRect.isEmpty == false else {
            return
        }

        let shadowView = NSView(frame: convertedSourceRect)
        let contentView = makeShellContentView(
            frame: shadowView.bounds,
            cornerRadius: Self.shellCornerRadius
        )
        configureShadow(
            for: shadowView,
            opacity: Self.shellShadowOpacity
        )

        if let snapshotView = makeSnapshotView(
            from: sourceViewController.view,
            rect: sourceRect
        ) {
            snapshotView.frame = contentView.bounds
            snapshotView.autoresizingMask = [.width, .height]
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

        overlayHostView.layoutSubtreeIfNeeded()
        sourceView.layoutSubtreeIfNeeded()
        sourceView.superview?.layoutSubtreeIfNeeded()

        let fullscreenFrame = overlayHostView.bounds.standardized
        guard fullscreenFrame.isEmpty == false else {
            return
        }

        let shadowView = NSView(frame: fullscreenFrame)
        let contentView = makeShellContentView(
            frame: shadowView.bounds,
            cornerRadius: 0
        )
        configureShadow(for: shadowView, opacity: 0)

        if let snapshotView = makeSnapshotView(
            from: sourceView,
            rect: sourceView.bounds
        ) {
            snapshotView.frame = contentView.bounds
            snapshotView.autoresizingMask = [.width, .height]
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

        overlayHostView.layoutSubtreeIfNeeded()
        destinationView.superview?.layoutSubtreeIfNeeded()

        guard let shellShadowView else {
            destinationView.isHidden = false
            destinationView.alphaValue = 0
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.handoffDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                destinationView.animator().alphaValue = 1
            } completionHandler: {
                completion()
            }
            return
        }

        let targetFrame = overlayHostView.bounds.standardized
        shellShadowView.isHidden = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.openingDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            shellShadowView.animator().frame = targetFrame
            shellShadowView.layer?.shadowOpacity = 0
            shellContentView?.layer?.cornerRadius = 0
        } completionHandler: {
            destinationView.isHidden = false
            destinationView.alphaValue = 0
            destinationView.superview?.layoutSubtreeIfNeeded()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.handoffDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                destinationView.animator().alphaValue = 1
                shellShadowView.animator().alphaValue = 0
            } completionHandler: {
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

        overlayHostView.layoutSubtreeIfNeeded()
        destinationView.isHidden = false
        destinationView.alphaValue = 1
        destinationView.superview?.layoutSubtreeIfNeeded()

        guard let shellShadowView else {
            completion()
            return
        }

        shellShadowView.isHidden = false
        shellShadowView.alphaValue = 1

        let targetFrame = resolvedClosingTargetFrame(in: overlayHostView)
        let fallbackFrame = fallbackClosingFrame(in: overlayHostView)

        if let targetFrame {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.closingDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                shellShadowView.animator().frame = targetFrame
                shellShadowView.layer?.shadowOpacity = Self.shellShadowOpacity
                shellContentView?.layer?.cornerRadius = Self.shellCornerRadius
            } completionHandler: {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = Self.handoffDuration
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    shellShadowView.animator().alphaValue = 0
                } completionHandler: {
                    completion()
                }
            }
            return
        }

        destinationView.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.closingDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            shellShadowView.animator().frame = fallbackFrame
            shellShadowView.animator().alphaValue = 0
            shellShadowView.layer?.shadowOpacity = Self.shellShadowOpacity
            shellContentView?.layer?.cornerRadius = Self.shellCornerRadius
            destinationView.animator().alphaValue = 1
        } completionHandler: {
            completion()
        }
    }

    private func makeSnapshotView(from sourceView: NSView, rect: CGRect) -> NSImageView? {
        let clippedRect = rect.standardized.intersection(sourceView.bounds)
        guard clippedRect.isEmpty == false else {
            return nil
        }

        guard let bitmap = sourceView.bitmapImageRepForCachingDisplay(in: clippedRect) else {
            return nil
        }

        sourceView.cacheDisplay(in: clippedRect, to: bitmap)
        let image = NSImage(size: clippedRect.size)
        image.addRepresentation(bitmap)

        let imageView = NSImageView(frame: CGRect(origin: .zero, size: clippedRect.size))
        imageView.image = image
        imageView.imageScaling = .scaleAxesIndependently
        return imageView
    }

    private func resolvedClosingTargetFrame(
        in overlayHostView: NSView
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

    private func fallbackClosingFrame(in overlayHostView: NSView) -> CGRect {
        let bounds = overlayHostView.bounds.standardized
        let scaledWidth = bounds.width * Self.fallbackClosingScale
        let scaledHeight = bounds.height * Self.fallbackClosingScale
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
    ) -> NSView {
        let contentView = NSView(frame: frame)
        contentView.autoresizingMask = [.width, .height]
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        contentView.layer?.cornerRadius = cornerRadius
        contentView.layer?.masksToBounds = true
        return contentView
    }

    private func configureShadow(
        for shadowView: NSView,
        opacity: Float
    ) {
        shadowView.wantsLayer = true
        shadowView.layer?.backgroundColor = NSColor.clear.cgColor
        shadowView.layer?.shadowColor = NSColor.black.cgColor
        shadowView.layer?.shadowOpacity = opacity
        shadowView.layer?.shadowRadius = Self.shellShadowRadius
        shadowView.layer?.shadowOffset = Self.shellShadowOffset
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
