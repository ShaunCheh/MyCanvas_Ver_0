#if os(macOS)
import AppKit

protocol macOSBoardListCanvasTransitionCarrying: AnyObject {
    var kind: BoardListCanvasTransitionCarrierKind { get }

    func install(in overlayHostView: NSView)
    func beginTransition(
        with context: BoardListCanvasTransitionContext,
        sourceViewController: NSViewController?,
        destinationViewController: NSViewController?
    )
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
    private var shellView: NSView?

    var kind: BoardListCanvasTransitionCarrierKind {
        .snapshotShell
    }

    func install(in overlayHostView: NSView) {
        if self.overlayHostView !== overlayHostView {
            cleanupShellView()
            self.overlayHostView = overlayHostView
        }

        guard shellView == nil else {
            return
        }

        let shellView = NSView()
        shellView.translatesAutoresizingMaskIntoConstraints = false
        shellView.wantsLayer = true
        shellView.layer?.backgroundColor = NSColor.clear.cgColor
        shellView.isHidden = true
        overlayHostView.addSubview(shellView)
        NSLayoutConstraint.activate([
            shellView.topAnchor.constraint(equalTo: overlayHostView.topAnchor),
            shellView.leadingAnchor.constraint(equalTo: overlayHostView.leadingAnchor),
            shellView.trailingAnchor.constraint(equalTo: overlayHostView.trailingAnchor),
            shellView.bottomAnchor.constraint(equalTo: overlayHostView.bottomAnchor)
        ])
        self.shellView = shellView
    }

    func beginTransition(
        with context: BoardListCanvasTransitionContext,
        sourceViewController: NSViewController?,
        destinationViewController: NSViewController?
    ) {
        shellView?.isHidden = false
    }

    func updateTransitionContext(_ context: BoardListCanvasTransitionContext) {}

    func completeTransition() {
        cleanupShellView()
    }

    func cancelTransition() {
        cleanupShellView()
    }

    private func cleanupShellView() {
        shellView?.removeFromSuperview()
        shellView = nil
    }
}
#endif
