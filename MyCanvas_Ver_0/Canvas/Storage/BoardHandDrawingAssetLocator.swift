import Foundation

struct BoardHandDrawingAssetLocator {
    let itemID: CanvasItemID

    var previewImageFilename: String {
        CanvasHandDrawingItem.defaultPreviewImageFilename(for: itemID)
    }

    var sourceDrawingFilename: String {
        CanvasHandDrawingItem.defaultSourceDrawingFilename(for: itemID)
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
    let drawingData: Data
    let previewImageData: Data

    init(
        itemID: CanvasItemID,
        drawingData: Data,
        previewImageData: Data
    ) {
        self.itemID = itemID
        self.drawingData = drawingData
        self.previewImageData = previewImageData
    }
}
