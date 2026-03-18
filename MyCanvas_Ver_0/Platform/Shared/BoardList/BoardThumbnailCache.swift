import CoreGraphics
import Foundation

struct BoardThumbnailCacheKey {
    let boardID: UUID
    let revisionToken: String
    let pixelWidth: Int
    let pixelHeight: Int

    init?(
        item: BoardCatalogItem,
        targetPixelSize: CGSize
    ) {
        let normalizedPixelSize = targetPixelSize.normalizedBoardThumbnailPixelSize
        guard normalizedPixelSize.width > 0, normalizedPixelSize.height > 0 else {
            return nil
        }

        boardID = item.boardID
        revisionToken = item.revisionToken
        pixelWidth = Int(normalizedPixelSize.width)
        pixelHeight = Int(normalizedPixelSize.height)
    }

    var pixelSize: CGSize {
        CGSize(
            width: pixelWidth,
            height: pixelHeight
        )
    }

    var cacheKey: NSString {
        "\(boardID.uuidString)-\(revisionToken)-\(pixelWidth)x\(pixelHeight)" as NSString
    }
}

final class BoardThumbnailCache {
    private final class Entry {
        let image: CGImage

        init(image: CGImage) {
            self.image = image
        }
    }

    private let cache = NSCache<NSString, Entry>()

    init(countLimit: Int = 256) {
        cache.countLimit = max(countLimit, 1)
    }

    func image(for key: BoardThumbnailCacheKey) -> CGImage? {
        cache.object(forKey: key.cacheKey)?.image
    }

    func insert(
        _ image: CGImage,
        for key: BoardThumbnailCacheKey
    ) {
        let cost = max(image.width * image.height * 4, 1)
        cache.setObject(
            Entry(image: image),
            forKey: key.cacheKey,
            cost: cost
        )
    }
}

private extension CGSize {
    var normalizedBoardThumbnailPixelSize: CGSize {
        guard
            width.isFinite,
            height.isFinite,
            width > 0,
            height > 0
        else {
            return .zero
        }

        return CGSize(
            width: max(width.rounded(.up), 1),
            height: max(height.rounded(.up), 1)
        )
    }
}
