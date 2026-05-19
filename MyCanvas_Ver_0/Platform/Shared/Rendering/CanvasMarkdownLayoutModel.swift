import CoreGraphics
import Foundation

enum CanvasMarkdownDecorationKind: Equatable {
    case codeBlockPanel
}

struct CanvasMarkdownDecoration: Equatable {
    let kind: CanvasMarkdownDecorationKind
    let rect: CGRect
    let fillColor: CanvasTextColor
    let cornerRadius: CGFloat
}

struct CanvasMarkdownLayoutResult {
    let attributedText: NSAttributedString
    let contentSize: CGSize
    let decorations: [CanvasMarkdownDecoration]

    var contentHeight: CGFloat {
        contentSize.height
    }
}
