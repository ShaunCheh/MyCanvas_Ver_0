import CoreGraphics
import Foundation

enum BoardPreviewContent {
    static let animatedImagePreviewSurface: CanvasAnimatedImagePreviewSurface = .boardList

    case empty
    case geometry(BoardPreviewSeed)
    case thumbnail(CGImage, BoardPreviewSeed)

    static var animatedImagePreviewMode: CanvasAnimatedImagePreviewMode {
        CanvasImageAssetContract.current.previewMode(
            for: animatedImagePreviewSurface
        )
    }

    var isThumbnail: Bool {
        if case .thumbnail = self {
            return true
        }

        return false
    }

    var usesPosterFrameForAnimatedImages: Bool {
        Self.animatedImagePreviewMode == .posterFrameOnly
    }
}
