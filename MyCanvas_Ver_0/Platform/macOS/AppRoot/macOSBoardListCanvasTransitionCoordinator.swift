#if os(macOS)
import AppKit
import Foundation

enum macOSBoardListCanvasTransitionPhase: String {
    case idle
    case opening
    case steadyCanvas
    case closing
    case steadyBoardList
}

final class macOSBoardListCanvasTransitionSession {
    let id = UUID()
    var context: BoardListCanvasTransitionContext
    let carrier: any macOSBoardListCanvasTransitionCarrying
    weak var sourceViewController: NSViewController?
    weak var destinationViewController: NSViewController?

    init(
        context: BoardListCanvasTransitionContext,
        carrier: any macOSBoardListCanvasTransitionCarrying,
        sourceViewController: NSViewController?,
        destinationViewController: NSViewController?
    ) {
        self.context = context
        self.carrier = carrier
        self.sourceViewController = sourceViewController
        self.destinationViewController = destinationViewController
    }
}
#endif
