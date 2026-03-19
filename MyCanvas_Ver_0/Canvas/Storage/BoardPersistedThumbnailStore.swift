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
            let imageSource = CGImageSourceCreateWithData(
                thumbnailData as CFData,
                nil
            )
        else {
            throw BoardPersistedThumbnailStoreError.invalidPersistedThumbnail
        }

        let decodeMaxPixelSize = max(maxPixelSize, 64)
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: decodeMaxPixelSize
        ]
        if let thumbnail = CGImageSourceCreateThumbnailAtIndex(
            imageSource,
            0,
            thumbnailOptions as CFDictionary
        ) {
            return thumbnail
        }

        let imageOptions: [CFString: Any] = [
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard
            let image = CGImageSourceCreateImageAtIndex(
                imageSource,
                0,
                imageOptions as CFDictionary
            )
        else {
            throw BoardPersistedThumbnailStoreError.invalidPersistedThumbnail
        }

        return image
    }

    static func writeThumbnail(
        _ image: CGImage,
        to boardDirectoryURL: URL
    ) throws {
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
}
