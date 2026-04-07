import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum CanvasTypeIdentifierResolver {
    private static let ignoredIdentifierPrefixes = [
        "com.apple.private.photos.thumbnail."
    ]

    static func contentType(for typeIdentifier: String?) -> UTType? {
        guard let normalizedTypeIdentifier = normalizedTypeIdentifier(typeIdentifier) else {
            return nil
        }
        guard ignoredIdentifierPrefixes.contains(where: normalizedTypeIdentifier.hasPrefix) == false else {
            return nil
        }
        return UTType(normalizedTypeIdentifier)
    }

    static func resolvedIdentifier(
        preferredTypeIdentifier: String?,
        fallbackFilenameExtension: String? = nil
    ) -> String? {
        if let contentType = contentType(for: preferredTypeIdentifier) {
            return contentType.identifier
        }

        guard
            let fallbackFilenameExtension,
            fallbackFilenameExtension.isEmpty == false,
            let contentType = UTType(filenameExtension: fallbackFilenameExtension)
        else {
            return nil
        }

        return contentType.identifier
    }

    private static func normalizedTypeIdentifier(
        _ typeIdentifier: String?
    ) -> String? {
        guard let typeIdentifier = typeIdentifier?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), typeIdentifier.isEmpty == false
        else {
            return nil
        }

        return typeIdentifier
    }
}

struct CanvasImportedImageSource: Equatable {
    let data: Data
    let typeIdentifier: String?
    let filenameHint: String?

    var contentType: UTType? {
        CanvasTypeIdentifierResolver.contentType(for: typeIdentifier)
    }
}

struct CanvasImportedVideoSource: Equatable {
    let localFileURL: URL
    let typeIdentifier: String?
    let filenameHint: String?
    let shouldDeleteAfterImport: Bool

    var contentType: UTType? {
        if let contentType = CanvasTypeIdentifierResolver.contentType(
            for: typeIdentifier
        ) {
            return contentType
        }

        guard localFileURL.pathExtension.isEmpty == false else {
            return nil
        }

        return UTType(filenameExtension: localFileURL.pathExtension)
    }
}

struct CanvasAnimatedImageMetadata: Equatable {
    let frameCount: Int
    let frameDelayTimes: [TimeInterval]
    let loopCount: Int?
}

struct CanvasTransientImageAssetPayload: Equatable {
    let assetReference: CanvasImageAssetReference
    let source: CanvasImportedImageSource?
    let animatedMetadata: CanvasAnimatedImageMetadata?
}

struct CanvasTransientImageAssetRegistration {
    let asset: CanvasImageAsset
    let payload: CanvasTransientImageAssetPayload?
}

struct CanvasResolvedImportImage {
    let cgImage: CGImage
    let assetKind: CanvasImageAssetKind
    let importedSource: CanvasImportedImageSource?
    let animatedMetadata: CanvasAnimatedImageMetadata?
    let logicalPixelSize: CGSize

    init(
        cgImage: CGImage,
        assetKind: CanvasImageAssetKind = .staticImage,
        importedSource: CanvasImportedImageSource? = nil,
        animatedMetadata: CanvasAnimatedImageMetadata? = nil,
        logicalPixelSize: CGSize? = nil
    ) {
        self.cgImage = cgImage
        self.assetKind = assetKind
        self.importedSource = importedSource
        self.animatedMetadata = animatedMetadata
        self.logicalPixelSize = logicalPixelSize ?? CGSize(
            width: cgImage.width,
            height: cgImage.height
        )
    }

    init?(
        data: Data,
        typeIdentifier: String? = nil,
        filenameHint: String? = nil
    ) {
        guard
            let imageSource = CanvasGIFFrameService.makeImageSource(from: data),
            let cgImage = CanvasGIFFrameService.decodeFrame(
                at: 0,
                from: imageSource
            )
        else {
            return nil
        }

        let resolvedTypeIdentifier = Self.resolvedTypeIdentifier(
            explicitTypeIdentifier: typeIdentifier,
            imageSource: imageSource
        )
        let contentType = CanvasTypeIdentifierResolver.contentType(
            for: resolvedTypeIdentifier
        )
        let animatedMetadata = contentType?.conforms(to: .gif) == true
            ? CanvasGIFFrameService.animatedMetadata(from: imageSource)
            : nil
        let assetKind: CanvasImageAssetKind =
            contentType?.conforms(to: .gif) == true &&
            animatedMetadata != nil
            ? .animatedGIF
            : .staticImage

        self.init(
            cgImage: cgImage,
            assetKind: assetKind,
            importedSource: CanvasImportedImageSource(
                data: data,
                typeIdentifier: resolvedTypeIdentifier,
                filenameHint: filenameHint
            ),
            animatedMetadata: animatedMetadata
        )
    }

    var importedContentType: UTType? {
        importedSource?.contentType
    }

    func makeTransientImageAssetRegistration(
        assetID: UUID = UUID()
    ) -> CanvasTransientImageAssetRegistration {
        let asset = CanvasImageAsset.transientImage(
            kind: assetKind,
            cgImage: cgImage,
            logicalPixelSize: logicalPixelSize,
            assetID: assetID
        )
        let payload: CanvasTransientImageAssetPayload?
        if importedSource != nil || animatedMetadata != nil {
            payload = CanvasTransientImageAssetPayload(
                assetReference: asset.reference,
                source: importedSource,
                animatedMetadata: animatedMetadata
            )
        } else {
            payload = nil
        }

        return CanvasTransientImageAssetRegistration(
            asset: asset,
            payload: payload
        )
    }

    func makeTransientImageAsset() -> CanvasImageAsset {
        makeTransientImageAssetRegistration().asset
    }

    private static func resolvedTypeIdentifier(
        explicitTypeIdentifier: String?,
        imageSource: CGImageSource
    ) -> String? {
        if let resolvedIdentifier = CanvasTypeIdentifierResolver.resolvedIdentifier(
            preferredTypeIdentifier: explicitTypeIdentifier
        ) {
            return resolvedIdentifier
        }

        let imageSourceTypeIdentifier = CGImageSourceGetType(imageSource) as String?
        return CanvasTypeIdentifierResolver.resolvedIdentifier(
            preferredTypeIdentifier: imageSourceTypeIdentifier
        ) ?? imageSourceTypeIdentifier
    }
}

struct CanvasResolvedImportVideo {
    let source: CanvasImportedVideoSource
    let posterCGImage: CGImage
    let posterTimeSeconds: Double
    let logicalPixelSize: CGSize

    init?(
        localFileURL: URL,
        typeIdentifier: String? = nil,
        filenameHint: String? = nil,
        shouldDeleteAfterImport: Bool = false,
        posterTimeSeconds: Double = 0
    ) {
        guard let posterFrame = try? CanvasVideoFrameService.frameImage(
            from: localFileURL,
            at: posterTimeSeconds,
            quality: .posterCommit
        ) else {
            return nil
        }

        let resolvedTypeIdentifier = CanvasTypeIdentifierResolver.resolvedIdentifier(
            preferredTypeIdentifier: typeIdentifier,
            fallbackFilenameExtension: localFileURL.pathExtension
        )
        self.source = CanvasImportedVideoSource(
            localFileURL: localFileURL,
            typeIdentifier: resolvedTypeIdentifier,
            filenameHint: filenameHint,
            shouldDeleteAfterImport: shouldDeleteAfterImport
        )
        self.posterCGImage = posterFrame.cgImage
        self.posterTimeSeconds = posterFrame.actualTimeSeconds
        self.logicalPixelSize = posterFrame.logicalPixelSize
    }
}

struct CanvasImportedVideoAsset {
    let asset: CanvasImageAsset
    let videoSource: CanvasVideoSource
    let posterTimeSeconds: Double
}

enum CanvasImportItem {
    case image(CanvasResolvedImportImage)
    case video(CanvasImportedVideoAsset)
}

enum CanvasImportPlacement: Equatable {
    case cameraCenter
    case worldPoint(CGPoint)
}

enum CanvasImportLayout: Equatable {
    case automatic
    case stacked
    case staggered(stepInWorld: CGPoint)
}

struct CanvasImportRequest {
    let items: [CanvasImportItem]
    let placement: CanvasImportPlacement
    let layout: CanvasImportLayout
    let sourceDescription: String

    init(
        items: [CanvasImportItem],
        placement: CanvasImportPlacement = .cameraCenter,
        layout: CanvasImportLayout = .automatic,
        sourceDescription: String = "external source"
    ) {
        self.items = items
        self.placement = placement
        self.layout = layout
        self.sourceDescription = sourceDescription
    }

    init(
        images: [CanvasResolvedImportImage],
        placement: CanvasImportPlacement = .cameraCenter,
        layout: CanvasImportLayout = .automatic,
        sourceDescription: String = "external source"
    ) {
        self.init(
            items: images.map { .image($0) },
            placement: placement,
            layout: layout,
            sourceDescription: sourceDescription
        )
    }

    var itemCount: Int {
        items.count
    }

    var isEmpty: Bool {
        items.isEmpty
    }
}
