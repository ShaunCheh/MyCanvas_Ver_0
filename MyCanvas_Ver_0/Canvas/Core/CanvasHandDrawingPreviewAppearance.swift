import CoreGraphics
import Foundation

enum CanvasHandDrawingPreviewAppearance {
    static let paperFillColor = CGColor(gray: 1, alpha: 1)
    static let borderColor = CGColor(
        red: 0.82,
        green: 0.84,
        blue: 0.88,
        alpha: 1
    )
    static let emptyBorderColor = CGColor(
        red: 0.68,
        green: 0.72,
        blue: 0.78,
        alpha: 1
    )
    static let borderLineWidth: CGFloat = 1
    static let cornerRadius: CGFloat = 10

    static func resolvedBorderColor(isEmpty: Bool) -> CGColor {
        isEmpty ? emptyBorderColor : borderColor
    }
}
