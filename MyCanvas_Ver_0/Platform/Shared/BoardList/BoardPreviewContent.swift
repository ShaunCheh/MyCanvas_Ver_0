import CoreGraphics
import Foundation

enum BoardPreviewContent {
    case empty
    case geometry(BoardPreviewSeed)
    case thumbnail(CGImage, BoardPreviewSeed)

    var isThumbnail: Bool {
        if case .thumbnail = self {
            return true
        }

        return false
    }
}
