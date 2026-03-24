import CoreGraphics
import Foundation

enum CanvasImageAssetKind: String, Codable, Equatable, Hashable {
    case staticImage
    case animatedGIF

    var isAnimated: Bool {
        self == .animatedGIF
    }
}

enum CanvasImageAssetStorage: Equatable, Hashable {
    case transient(UUID)
    case persisted(filename: String)

    var persistedFilename: String? {
        guard case let .persisted(filename) = self else {
            return nil
        }

        return filename
    }
}

struct CanvasImageAssetReference: Equatable, Hashable {
    let kind: CanvasImageAssetKind
    let storage: CanvasImageAssetStorage

    static func transientStaticImage(
        assetID: UUID = UUID()
    ) -> CanvasImageAssetReference {
        CanvasImageAssetReference(
            kind: .staticImage,
            storage: .transient(assetID)
        )
    }

    static func persistedStaticImage(
        filename: String
    ) -> CanvasImageAssetReference {
        CanvasImageAssetReference(
            kind: .staticImage,
            storage: .persisted(filename: filename)
        )
    }
}

struct CanvasImagePoster {
    let cgImage: CGImage

    var pixelSize: CGSize {
        CGSize(
            width: cgImage.width,
            height: cgImage.height
        )
    }
}

struct CanvasImageAsset {
    let reference: CanvasImageAssetReference
    let poster: CanvasImagePoster
    let logicalPixelSize: CGSize

    init(
        reference: CanvasImageAssetReference,
        poster: CanvasImagePoster,
        logicalPixelSize: CGSize? = nil
    ) {
        self.reference = reference
        self.poster = poster
        self.logicalPixelSize = Self.sanitizedPixelSize(
            logicalPixelSize ?? poster.pixelSize
        )
    }

    static func transientStaticImage(
        cgImage: CGImage,
        assetID: UUID = UUID()
    ) -> CanvasImageAsset {
        CanvasImageAsset(
            reference: .transientStaticImage(assetID: assetID),
            poster: CanvasImagePoster(cgImage: cgImage)
        )
    }

    static func persistedStaticImage(
        filename: String,
        cgImage: CGImage
    ) -> CanvasImageAsset {
        CanvasImageAsset(
            reference: .persistedStaticImage(filename: filename),
            poster: CanvasImagePoster(cgImage: cgImage)
        )
    }

    var posterCGImage: CGImage {
        poster.cgImage
    }

    private static func sanitizedPixelSize(
        _ pixelSize: CGSize
    ) -> CGSize {
        CGSize(
            width: max(pixelSize.width, 1),
            height: max(pixelSize.height, 1)
        )
    }
}
