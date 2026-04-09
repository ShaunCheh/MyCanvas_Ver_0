#if os(iOS)
import UIKit

protocol iOSBoardListCanvasTransitionCarrying: AnyObject {
    var kind: BoardListCanvasTransitionCarrierKind { get }

    func install(in overlayHostView: UIView)
    func beginTransition(
        with context: BoardListCanvasTransitionContext,
        sourceViewController: UIViewController?,
        destinationViewController: UIViewController?
    )
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
    private var shellView: UIView?

    var kind: BoardListCanvasTransitionCarrierKind {
        .snapshotShell
    }

    func install(in overlayHostView: UIView) {
        if self.overlayHostView !== overlayHostView {
            cleanupShellView()
            self.overlayHostView = overlayHostView
        }

        guard shellView == nil else {
            return
        }

        let shellView = UIView()
        shellView.translatesAutoresizingMaskIntoConstraints = false
        shellView.isUserInteractionEnabled = false
        shellView.backgroundColor = .clear
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
        sourceViewController: UIViewController?,
        destinationViewController: UIViewController?
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
