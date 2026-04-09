import CoreGraphics
import Foundation

enum BoardListCanvasTransitionTimingCurve: Hashable {
    case easeInOut
    case easeOut
}

struct BoardListCanvasTransitionAnimationConfiguration: Hashable {
    var duration: TimeInterval
    var curve: BoardListCanvasTransitionTimingCurve
    var springDampingRatio: CGFloat?
    var springInitialVelocity: CGFloat?

    init(
        duration: TimeInterval,
        curve: BoardListCanvasTransitionTimingCurve,
        springDampingRatio: CGFloat? = nil,
        springInitialVelocity: CGFloat? = nil
    ) {
        self.duration = duration
        self.curve = curve
        self.springDampingRatio = springDampingRatio
        self.springInitialVelocity = springInitialVelocity
    }
}

enum BoardListCanvasTransitionConfiguration {
    static let openingAnimation = BoardListCanvasTransitionAnimationConfiguration(
        duration: 0.38,
        curve: .easeInOut,
        springDampingRatio: 0.94,
        springInitialVelocity: 0
    )
    static let closingAnimation = BoardListCanvasTransitionAnimationConfiguration(
        duration: 0.32,
        curve: .easeInOut
    )
    static let handoffAnimation = BoardListCanvasTransitionAnimationConfiguration(
        duration: 0.14,
        curve: .easeOut
    )
    static let shellCornerRadius: CGFloat = 12
    static let shellShadowOpacity: Float = 0.08
    static let shellShadowRadius: CGFloat = 16
    static let iOSShellShadowOffset = CGSize(width: 0, height: 8)
    static let macOSShellShadowOffset = CGSize(width: 0, height: -8)
    static let fallbackClosingScale: CGFloat = 0.82
}
