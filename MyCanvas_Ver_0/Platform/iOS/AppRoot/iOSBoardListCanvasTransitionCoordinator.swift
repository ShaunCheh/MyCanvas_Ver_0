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

final class iOSBoardListCanvasTransitionSession {
    let id = UUID()
    var context: BoardListCanvasTransitionContext
    let carrier: any iOSBoardListCanvasTransitionCarrying
    weak var sourceViewController: UIViewController?
    weak var destinationViewController: UIViewController?

    init(
        context: BoardListCanvasTransitionContext,
        carrier: any iOSBoardListCanvasTransitionCarrying,
        sourceViewController: UIViewController?,
        destinationViewController: UIViewController?
    ) {
        self.context = context
        self.carrier = carrier
        self.sourceViewController = sourceViewController
        self.destinationViewController = destinationViewController
    }
}
#endif
