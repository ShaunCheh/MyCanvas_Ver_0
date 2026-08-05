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

struct CanvasImportGridConfiguration: Equatable {
    let columns: Int
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    init(
        columns: Int,
        horizontalSpacing: CGFloat,
        verticalSpacing: CGFloat
    ) {
        self.columns = max(columns, 1)
        self.horizontalSpacing = max(horizontalSpacing, 0)
        self.verticalSpacing = max(verticalSpacing, 0)
    }
}

struct CanvasBatchImportLayoutConfiguration: Equatable {
    static let current = CanvasBatchImportLayoutConfiguration(
        grid: CanvasImportGridConfiguration(
            columns: 4,
            horizontalSpacing: 24,
            verticalSpacing: 24
        )
    )

    let grid: CanvasImportGridConfiguration
}

enum CanvasImportRotationPolicy: Equatable {
    case useAssetDefault
    case fixed(CGFloat)

    func resolvedRotationRadians(
        assetDefaultRadians: CGFloat = 0
    ) -> CGFloat {
        let sanitizedDefaultRadians = assetDefaultRadians.isFinite
            ? assetDefaultRadians
            : 0
        switch self {
        case .useAssetDefault:
            return sanitizedDefaultRadians
        case let .fixed(rotationRadians):
            return rotationRadians.isFinite
                ? rotationRadians
                : sanitizedDefaultRadians
        }
    }
}

struct CanvasImportPresentationTemplate: Equatable {
    let size: CGSize
    let cropRectNormalized: CanvasImageCropRect
    let rotationPolicy: CanvasImportRotationPolicy

    init(
        size: CGSize,
        cropRectNormalized: CanvasImageCropRect = .fullImage,
        rotationPolicy: CanvasImportRotationPolicy = .useAssetDefault
    ) {
        self.size = Self.sanitizedSize(size)
        self.cropRectNormalized = cropRectNormalized
        self.rotationPolicy = rotationPolicy
    }

    func resolvedRotationRadians(
        assetDefaultRadians: CGFloat = 0
    ) -> CGFloat {
        rotationPolicy.resolvedRotationRadians(
            assetDefaultRadians: assetDefaultRadians
        )
    }

    private static func sanitizedSize(_ size: CGSize) -> CGSize {
        let sanitizedWidth = size.width.isFinite ? max(size.width, 1) : 1
        let sanitizedHeight = size.height.isFinite ? max(size.height, 1) : 1
        return CGSize(
            width: sanitizedWidth,
            height: sanitizedHeight
        )
    }
}

enum CanvasImportLayout: Equatable {
    case automatic
    case stacked
    case diagonal(stepInWorld: CGPoint)
    case grid(
        columns: Int,
        horizontalSpacing: CGFloat,
        verticalSpacing: CGFloat
    )

    var gridConfiguration: CanvasImportGridConfiguration? {
        guard case let .grid(
            columns,
            horizontalSpacing,
            verticalSpacing
        ) = self
        else {
            return nil
        }

        return CanvasImportGridConfiguration(
            columns: columns,
            horizontalSpacing: horizontalSpacing,
            verticalSpacing: verticalSpacing
        )
    }
}

// Import requests stay downstream of transfer requests. They carry document-ready
// media items plus presentation metadata after lowering, not raw capture intents.
struct CanvasImportRequest {
    let items: [CanvasImportItem]
    let placement: CanvasImportPlacement
    let layout: CanvasImportLayout
    let presentationTemplate: CanvasImportPresentationTemplate?
    let sourceDescription: String

    init(
        items: [CanvasImportItem],
        placement: CanvasImportPlacement = .cameraCenter,
        layout: CanvasImportLayout = .automatic,
        presentationTemplate: CanvasImportPresentationTemplate? = nil,
        sourceDescription: String = "external source"
    ) {
        self.items = items
        self.placement = placement
        self.layout = layout
        self.presentationTemplate = presentationTemplate
        self.sourceDescription = sourceDescription
    }

    init(
        images: [CanvasResolvedImportImage],
        placement: CanvasImportPlacement = .cameraCenter,
        layout: CanvasImportLayout = .automatic,
        presentationTemplate: CanvasImportPresentationTemplate? = nil,
        sourceDescription: String = "external source"
    ) {
        self.init(
            items: images.map { .image($0) },
            placement: placement,
            layout: layout,
            presentationTemplate: presentationTemplate,
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
