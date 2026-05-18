import CoreGraphics
import Foundation

enum CanvasHandDrawingEditingError: LocalizedError {
    case invalidHandDrawingItem(itemID: CanvasItemID)
    case missingBoardIdentity
    case missingSourceDrawing(itemID: CanvasItemID)
    case failedToCreateBlankPreview(paperID: String)

    var errorDescription: String? {
        switch self {
        case let .invalidHandDrawingItem(itemID):
            return "The selected item is not a valid hand drawing item: \(itemID.uuidString)"
        case .missingBoardIdentity:
            return "Unable to resolve the active board for hand drawing editing."
        case let .missingSourceDrawing(itemID):
            return "The hand drawing source asset is missing for item \(itemID.uuidString)."
        case let .failedToCreateBlankPreview(paperID):
            return "Unable to create a blank preview image for paper \(paperID)."
        }
    }
}

struct CanvasHandDrawingEditorContext {
    let itemID: CanvasItemID
    let documentID: HandDrawingDocumentID
    let paper: CanvasHandDrawingPaperSpec
    let drawingData: Data
    let isEmpty: Bool
    let storage: BoardHandDrawingStorageRecord
    let didMigrateLegacyDocument: Bool
}

struct CanvasHandDrawingEditSubmission {
    let drawingData: Data
    let previewCGImage: CGImage
    let isEmpty: Bool
    let contentRevision: UUID
}

struct CanvasHandDrawingEditCommitResult {
    let item: CanvasHandDrawingItem
    let refreshReason: String
}

enum CanvasHandDrawingPreviewAssetFactory {
    static func makeTransparentPreview(
        for paper: CanvasHandDrawingPaperSpec
    ) throws -> CGImage {
        let width = max(Int(paper.size.width.rounded(.up)), 1)
        let height = max(Int(paper.size.height.rounded(.up)), 1)
        let bitmapInfo =
            CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
        guard
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: bitmapInfo
            )
        else {
            throw CanvasHandDrawingEditingError.failedToCreateBlankPreview(
                paperID: paper.id
            )
        }

        context.clear(
            CGRect(
                x: 0,
                y: 0,
                width: width,
                height: height
            )
        )
        guard let image = context.makeImage() else {
            throw CanvasHandDrawingEditingError.failedToCreateBlankPreview(
                paperID: paper.id
            )
        }
        return image
    }
}
