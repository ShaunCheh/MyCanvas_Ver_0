import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct CanvasImportedImageSource: Equatable {
    let data: Data
    let typeIdentifier: String?
    let filenameHint: String?

    var contentType: UTType? {
        guard let typeIdentifier else {
            return nil
        }

        return UTType(importedAs: typeIdentifier)
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
            let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
            let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
        else {
            return nil
        }

        let resolvedTypeIdentifier = Self.resolvedTypeIdentifier(
            explicitTypeIdentifier: typeIdentifier,
            imageSource: imageSource
        )
        let contentType = resolvedTypeIdentifier.map { UTType(importedAs: $0) }
        let animatedMetadata = Self.animatedMetadata(
            from: imageSource,
            contentType: contentType
        )
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
        if let explicitTypeIdentifier, explicitTypeIdentifier.isEmpty == false {
            return explicitTypeIdentifier
        }

        return CGImageSourceGetType(imageSource) as String?
    }

    private static func animatedMetadata(
        from imageSource: CGImageSource,
        contentType: UTType?
    ) -> CanvasAnimatedImageMetadata? {
        guard contentType?.conforms(to: .gif) == true else {
            return nil
        }

        let frameCount = CGImageSourceGetCount(imageSource)
        guard frameCount > 1 else {
            return nil
        }

        let properties = CGImageSourceCopyProperties(
            imageSource,
            nil
        ) as? [CFString: Any]
        let gifProperties = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        let loopCount = gifProperties?[kCGImagePropertyGIFLoopCount] as? Int
        let frameDelayTimes = (0..<frameCount).map { frameIndex in
            frameDelay(
                forFrameAt: frameIndex,
                imageSource: imageSource
            )
        }
        return CanvasAnimatedImageMetadata(
            frameCount: frameCount,
            frameDelayTimes: frameDelayTimes,
            loopCount: loopCount
        )
    }

    private static func frameDelay(
        forFrameAt frameIndex: Int,
        imageSource: CGImageSource
    ) -> TimeInterval {
        let properties = CGImageSourceCopyPropertiesAtIndex(
            imageSource,
            frameIndex,
            nil
        ) as? [CFString: Any]
        let gifProperties = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        let unclampedDelay = gifProperties?[kCGImagePropertyGIFUnclampedDelayTime] as? Double
        let clampedDelay = gifProperties?[kCGImagePropertyGIFDelayTime] as? Double
        let rawDelay = unclampedDelay ?? clampedDelay ?? 0.1
        guard rawDelay.isFinite, rawDelay > 0.011 else {
            return 0.1
        }

        return rawDelay
    }
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
    let images: [CanvasResolvedImportImage]
    let placement: CanvasImportPlacement
    let layout: CanvasImportLayout
    let sourceDescription: String

    init(
        images: [CanvasResolvedImportImage],
        placement: CanvasImportPlacement = .cameraCenter,
        layout: CanvasImportLayout = .automatic,
        sourceDescription: String = "external source"
    ) {
        self.images = images
        self.placement = placement
        self.layout = layout
        self.sourceDescription = sourceDescription
    }

    var imageCount: Int {
        images.count
    }

    var isEmpty: Bool {
        images.isEmpty
    }
}
