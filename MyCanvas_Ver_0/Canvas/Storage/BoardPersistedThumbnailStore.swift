import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum BoardPersistedThumbnailStoreError: LocalizedError {
    case failedToEncodeThumbnail
    case invalidPersistedThumbnail

    var errorDescription: String? {
        switch self {
        case .failedToEncodeThumbnail:
            return "The persisted board thumbnail could not be encoded."
        case .invalidPersistedThumbnail:
            return "The persisted board thumbnail could not be decoded."
        }
    }
}

enum BoardPersistedThumbnailStore {
    static let filename = "thumbnail.png"
    static let maximumLongestSide: CGFloat = 1024
    private static let freshnessTolerance: TimeInterval = 1
    static let animatedImagePreviewSurface: CanvasAnimatedImagePreviewSurface = .persistedThumbnail

    static var animatedImagePreviewMode: CanvasAnimatedImagePreviewMode {
        CanvasImageAssetContract.current.previewMode(
            for: animatedImagePreviewSurface
        )
    }

    static var usesPosterFrameForAnimatedImages: Bool {
        animatedImagePreviewMode == .posterFrameOnly
    }

    static func thumbnailURL(
        forBoardDirectoryURL boardDirectoryURL: URL
    ) -> URL {
        boardDirectoryURL.appendingPathComponent(filename)
    }

    static func pixelSize(
        forDisplayWorldRect displayWorldRect: CGRect,
        maximumLongestSide: CGFloat = Self.maximumLongestSide
    ) -> CGSize {
        let sanitizedDisplayWorldRect = displayWorldRect.standardized
        guard
            sanitizedDisplayWorldRect.width > 0,
            sanitizedDisplayWorldRect.height > 0
        else {
            return .zero
        }

        let longestSide = max(
            sanitizedDisplayWorldRect.width,
            sanitizedDisplayWorldRect.height
        )
        let scale = max(maximumLongestSide, 1) / longestSide
        return CGSize(
            width: max((sanitizedDisplayWorldRect.width * scale).rounded(.up), 1),
            height: max((sanitizedDisplayWorldRect.height * scale).rounded(.up), 1)
        )
    }

    static func loadThumbnailIfFresh(
        at thumbnailURL: URL,
        updatedAt: Date,
        boardID: UUID? = nil,
        maxPixelSize: Int
    ) throws -> CGImage? {
        guard
            try isFreshThumbnail(
                at: thumbnailURL,
                updatedAt: updatedAt
            )
        else {
            return nil
        }

        let thumbnailData = try CoordinatedFileIO.readData(at: thumbnailURL)
        guard
            usesPosterFrameForAnimatedImages,
            let image = CanvasImagePosterFrameDecoder.decodePosterFrame(
                from: thumbnailData,
                maxPixelSize: maxPixelSize
            )
        else {
            throw BoardPersistedThumbnailStoreError.invalidPersistedThumbnail
        }

        logPersistedThumbnailImage(
            phase: "load-output",
            boardID: boardID,
            image: image,
            maxPixelSize: maxPixelSize
        )
        return image
    }

    static func writeThumbnail(
        _ image: CGImage,
        to boardDirectoryURL: URL,
        boardID: UUID? = nil
    ) throws {
        logPersistedThumbnailImage(
            phase: "write-input",
            boardID: boardID,
            image: image
        )
        let encodedImage = try makePNGData(for: image)
        try CoordinatedFileIO.writeData(
            encodedImage,
            to: thumbnailURL(forBoardDirectoryURL: boardDirectoryURL)
        )
    }

    static func removeThumbnail(
        at boardDirectoryURL: URL
    ) throws {
        try CoordinatedFileIO.removeItemIfExists(
            at: thumbnailURL(forBoardDirectoryURL: boardDirectoryURL)
        )
    }

    private static func isFreshThumbnail(
        at thumbnailURL: URL,
        updatedAt: Date
    ) throws -> Bool {
        guard
            let modificationDate = try CoordinatedFileIO.modificationDate(
                at: thumbnailURL
            )
        else {
            return false
        }

        return modificationDate.timeIntervalSince(updatedAt) >= -freshnessTolerance
    }

    private static func makePNGData(
        for image: CGImage
    ) throws -> Data {
        let mutableData = NSMutableData()
        guard
            let imageDestination = CGImageDestinationCreateWithData(
                mutableData,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        else {
            throw BoardPersistedThumbnailStoreError.failedToEncodeThumbnail
        }

        CGImageDestinationAddImage(imageDestination, image, nil)
        guard CGImageDestinationFinalize(imageDestination) else {
            throw BoardPersistedThumbnailStoreError.failedToEncodeThumbnail
        }

        return mutableData as Data
    }

    private static func logPersistedThumbnailImage(
        phase: String,
        boardID: UUID?,
        image: CGImage,
        maxPixelSize: Int? = nil
    ) {
        var message =
            "[BoardList][ThumbnailTrace][PersistedImage] " +
            "phase=\(phase) " +
            "boardID=\(boardID?.uuidString ?? "nil") " +
            "signature=\(BoardThumbnailImageSignature.describe(image))"
        if let maxPixelSize {
            message += " maxPixelSize=\(maxPixelSize)"
        }
        print(message)
    }
}

enum BoardThumbnailImageSignature {
    static func describe(_ image: CGImage) -> String {
        let sampleGridSize = CGSize(width: 3, height: 3)
        guard let pixels = makeNormalizedPixels(for: image, sampleGridSize: sampleGridSize)
        else {
            return "pixels={\(image.width), \(image.height)} sampleGrid=unavailable"
        }

        let width = Int(sampleGridSize.width)
        let topRow = describeRow(at: 0, width: width, pixels: pixels)
        let middleRow = describeRow(at: 1, width: width, pixels: pixels)
        let bottomRow = describeRow(at: 2, width: width, pixels: pixels)
        return
            "pixels={\(image.width), \(image.height)} " +
            "sampleGrid={top:[\(topRow)],mid:[\(middleRow)],bottom:[\(bottomRow)]}"
    }

    private static func makeNormalizedPixels(
        for image: CGImage,
        sampleGridSize: CGSize
    ) -> [UInt8]? {
        let width = max(Int(sampleGridSize.width), 1)
        let height = max(Int(sampleGridSize.height), 1)
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            return nil
        }

        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        let bitmapInfo =
            CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
        let didRender = pixels.withUnsafeMutableBytes { rawBuffer -> Bool in
            guard
                let baseAddress = rawBuffer.baseAddress,
                let context = CGContext(
                    data: baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: colorSpace,
                    bitmapInfo: bitmapInfo
                )
            else {
                return false
            }

            context.interpolationQuality = .none
            context.draw(
                image,
                in: CGRect(
                    x: 0,
                    y: 0,
                    width: width,
                    height: height
                )
            )
            return true
        }
        guard didRender else {
            return nil
        }
        return pixels
    }

    private static func describeRow(
        at row: Int,
        width: Int,
        pixels: [UInt8]
    ) -> String {
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        return (0..<width).map { column in
            let offset = row * bytesPerRow + column * bytesPerPixel
            return String(
                format: "%02X%02X%02X%02X",
                pixels[offset],
                pixels[offset + 1],
                pixels[offset + 2],
                pixels[offset + 3]
            )
        }.joined(separator: ",")
    }
}
