#if os(iOS)
import Foundation
import UIKit

enum iOSBoardListCanvasTransitionPhase: String {
    case idle
    case opening
    case steadyCanvas
    case closing
    case steadyBoardList
}

protocol iOSBoardListCanvasTransitionInteractionControlling: AnyObject {
    func setTransitionInteractionFrozen(_ isFrozen: Bool)
}

final class iOSBoardListCanvasTransitionSession {
    let id = UUID()
    var context: BoardListCanvasTransitionContext
    let carrier: any iOSBoardListCanvasTransitionCarrying
    weak var sourceViewController: UIViewController?
    weak var destinationViewController: UIViewController?
    let debugTrace: BoardListCanvasTransitionDebugTrace?
    var closingTargetGeometryRequestedAt: TimeInterval?
    var closingAnimationStartedAt: TimeInterval?

    init(
        context: BoardListCanvasTransitionContext,
        carrier: any iOSBoardListCanvasTransitionCarrying,
        sourceViewController: UIViewController?,
        destinationViewController: UIViewController?,
        debugTrace: BoardListCanvasTransitionDebugTrace? = nil
    ) {
        self.context = context
        self.carrier = carrier
        self.sourceViewController = sourceViewController
        self.destinationViewController = destinationViewController
        self.debugTrace = debugTrace
    }
}
#endif
