import CoreGraphics
import Foundation

enum BoardPreviewContent {
    case empty
    case geometry(BoardPreviewSeed)
    case thumbnail(CGImage)
}
