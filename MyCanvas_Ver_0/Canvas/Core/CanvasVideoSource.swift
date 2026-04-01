import Foundation

struct CanvasVideoAssetReference: Equatable, Hashable {
    let filename: String

    init(filename: String) {
        self.filename = Self.sanitizedFilename(filename)
    }

    static func persisted(
        filename: String
    ) -> CanvasVideoAssetReference {
        CanvasVideoAssetReference(filename: filename)
    }

    var stableAssetFilename: String {
        filename
    }

    private static func sanitizedFilename(
        _ filename: String
    ) -> String {
        let trimmedFilename = filename.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard trimmedFilename.isEmpty == false else {
            assertionFailure("Video asset filenames must not be empty.")
            return "video.mov"
        }

        return trimmedFilename
    }
}

struct CanvasVideoSource: Equatable, Hashable {
    let assetReference: CanvasVideoAssetReference

    init(
        assetReference: CanvasVideoAssetReference
    ) {
        self.assetReference = assetReference
    }

    var sourceVideoFilename: String {
        assetReference.stableAssetFilename
    }
}
