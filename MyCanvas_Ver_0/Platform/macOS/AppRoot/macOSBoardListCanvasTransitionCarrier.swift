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
    private static let handoffDuration: TimeInterval = 0.14
    private static let openingCornerRadius: CGFloat = 12

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
        guard context.direction == .opening else {
            return
        }

        prepareOpeningShell(using: context)
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
            completion()
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
        shadowView.wantsLayer = true
        shadowView.layer?.backgroundColor = NSColor.clear.cgColor
        shadowView.layer?.shadowColor = NSColor.black.cgColor
        shadowView.layer?.shadowOpacity = 0.08
        shadowView.layer?.shadowRadius = 16
        shadowView.layer?.shadowOffset = CGSize(width: 0, height: -8)

        let contentView = NSView(frame: shadowView.bounds)
        contentView.autoresizingMask = [.width, .height]
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        contentView.layer?.cornerRadius = Self.openingCornerRadius
        contentView.layer?.masksToBounds = true

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
