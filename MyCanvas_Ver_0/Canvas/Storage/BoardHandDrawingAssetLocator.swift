import CoreGraphics
import Foundation

struct BoardHandDrawingAssetLocator {
    let documentID: HandDrawingDocumentID

    var previewImageFilename: String {
        CanvasHandDrawingItem.defaultPreviewImageFilename(for: documentID)
    }

    var sourceDrawingFilename: String {
        CanvasHandDrawingItem.defaultSourceDrawingFilename(for: documentID)
    }

    var referencedAssetFilenames: Set<String> {
        [
            previewImageFilename,
            sourceDrawingFilename
        ]
    }

    func previewImageURL(in assetsDirectoryURL: URL) -> URL {
        assetsDirectoryURL.appendingPathComponent(previewImageFilename)
    }

    func sourceDrawingURL(in assetsDirectoryURL: URL) -> URL {
        assetsDirectoryURL.appendingPathComponent(sourceDrawingFilename)
    }
}

struct BoardTransientHandDrawingAssetPayload {
    let itemID: CanvasItemID
    let documentData: Data
    let previewImageData: Data?
    let previewCGImage: CGImage?

    init(
        itemID: CanvasItemID,
        documentData: Data,
        previewImageData: Data
    ) {
        self.itemID = itemID
        self.documentData = documentData
        self.previewImageData = previewImageData
        previewCGImage = nil
    }

    init(
        itemID: CanvasItemID,
        documentData: Data,
        previewCGImage: CGImage
    ) {
        self.itemID = itemID
        self.documentData = documentData
        previewImageData = nil
        self.previewCGImage = previewCGImage
    }
}
