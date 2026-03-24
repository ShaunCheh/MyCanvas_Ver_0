import CoreGraphics
import Foundation

enum CanvasImageAssetKind: String, Codable, Equatable, Hashable {
    case staticImage
    case animatedGIF

    var isAnimated: Bool {
        self == .animatedGIF
    }

    var preferredPersistedFileExtension: String {
        switch self {
        case .staticImage:
            return "png"
        case .animatedGIF:
            return "gif"
        }
    }

    static func inferredPersistedKind(
        from filename: String
    ) -> CanvasImageAssetKind {
        let pathExtension = URL(fileURLWithPath: filename)
            .pathExtension
            .lowercased()
        switch pathExtension {
        case "gif":
            return .animatedGIF
        default:
            return .staticImage
        }
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

    var stableAssetFilename: String {
        switch storage {
        case let .transient(assetID):
            return "\(assetID.uuidString).\(kind.preferredPersistedFileExtension)"
        case let .persisted(filename):
            return filename
        }
    }

    static func transient(
        kind: CanvasImageAssetKind,
        assetID: UUID = UUID()
    ) -> CanvasImageAssetReference {
        CanvasImageAssetReference(
            kind: kind,
            storage: .transient(assetID)
        )
    }

    static func persisted(
        kind: CanvasImageAssetKind,
        filename: String
    ) -> CanvasImageAssetReference {
        CanvasImageAssetReference(
            kind: kind,
            storage: .persisted(filename: filename)
        )
    }

    static func transientStaticImage(
        assetID: UUID = UUID()
    ) -> CanvasImageAssetReference {
        transient(kind: .staticImage, assetID: assetID)
    }

    static func transientAnimatedGIF(
        assetID: UUID = UUID()
    ) -> CanvasImageAssetReference {
        transient(kind: .animatedGIF, assetID: assetID)
    }

    static func persistedStaticImage(
        filename: String
    ) -> CanvasImageAssetReference {
        persisted(kind: .staticImage, filename: filename)
    }

    static func persistedAnimatedGIF(
        filename: String
    ) -> CanvasImageAssetReference {
        persisted(kind: .animatedGIF, filename: filename)
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

    static func transientImage(
        kind: CanvasImageAssetKind,
        cgImage: CGImage,
        logicalPixelSize: CGSize? = nil,
        assetID: UUID = UUID()
    ) -> CanvasImageAsset {
        CanvasImageAsset(
            reference: .transient(kind: kind, assetID: assetID),
            poster: CanvasImagePoster(cgImage: cgImage),
            logicalPixelSize: logicalPixelSize
        )
    }

    static func transientStaticImage(
        cgImage: CGImage,
        logicalPixelSize: CGSize? = nil,
        assetID: UUID = UUID()
    ) -> CanvasImageAsset {
        transientImage(
            kind: .staticImage,
            cgImage: cgImage,
            logicalPixelSize: logicalPixelSize,
            assetID: assetID
        )
    }

    static func transientAnimatedGIF(
        posterCGImage: CGImage,
        logicalPixelSize: CGSize? = nil,
        assetID: UUID = UUID()
    ) -> CanvasImageAsset {
        transientImage(
            kind: .animatedGIF,
            cgImage: posterCGImage,
            logicalPixelSize: logicalPixelSize,
            assetID: assetID
        )
    }

    static func persistedImage(
        kind: CanvasImageAssetKind,
        filename: String,
        cgImage: CGImage,
        logicalPixelSize: CGSize? = nil
    ) -> CanvasImageAsset {
        CanvasImageAsset(
            reference: .persisted(kind: kind, filename: filename),
            poster: CanvasImagePoster(cgImage: cgImage),
            logicalPixelSize: logicalPixelSize
        )
    }

    static func persistedStaticImage(
        filename: String,
        cgImage: CGImage,
        logicalPixelSize: CGSize? = nil
    ) -> CanvasImageAsset {
        persistedImage(
            kind: .staticImage,
            filename: filename,
            cgImage: cgImage,
            logicalPixelSize: logicalPixelSize
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
