import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum CanvasMediaImportServiceError: LocalizedError {
    case missingBoardIDForVideoImport
    case failedToEncodeVideoPoster

    var errorDescription: String? {
        switch self {
        case .missingBoardIDForVideoImport:
            return "Unable to determine the destination board for the imported video."
        case .failedToEncodeVideoPoster:
            return "Unable to create a poster image for the imported video."
        }
    }
}

enum CanvasMediaImportService {
    static func makeImportRequest(
        from transferRequest: CanvasTransferRequest,
        boardID: UUID? = nil
    ) throws -> CanvasImportRequest? {
        guard transferRequest.isEmpty == false else {
            return nil
        }

        let temporaryVideoURLsToDelete = transferRequest.items.compactMap { item in
            guard case let .video(video) = item,
                  video.source.shouldDeleteAfterImport
            else {
                return nil
            }

            return video.source.localFileURL
        }
        var createdAssetURLs: [URL] = []

        do {
            let assetsDirectoryURL: URL?
            if transferRequest.containsVideo {
                guard let boardID else {
                    throw CanvasMediaImportServiceError.missingBoardIDForVideoImport
                }

                assetsDirectoryURL = try BoardStore.ensureAssetsDirectoryURL(
                    for: boardID
                )
            } else {
                assetsDirectoryURL = nil
            }

            var importItems: [CanvasImportItem] = []
            importItems.reserveCapacity(transferRequest.itemCount)

            for item in transferRequest.items {
                switch item {
                case let .image(image):
                    importItems.append(.image(image))
                case let .video(video):
                    guard let assetsDirectoryURL else {
                        throw CanvasMediaImportServiceError.missingBoardIDForVideoImport
                    }

                    let importedVideo = try importVideo(
                        video,
                        into: assetsDirectoryURL
                    )
                    importItems.append(.video(importedVideo.item))
                    createdAssetURLs.append(
                        contentsOf: importedVideo.createdAssetURLs
                    )
                }
            }

            cleanupTemporaryVideoURLs(temporaryVideoURLsToDelete)
            return CanvasImportRequest(
                items: importItems,
                placement: transferRequest.placement,
                layout: transferRequest.layout,
                sourceDescription: transferRequest.sourceDescription
            )
        } catch {
            cleanupImportedAssetURLs(createdAssetURLs)
            cleanupTemporaryVideoURLs(temporaryVideoURLsToDelete)
            throw error
        }
    }

    private struct ImportedVideoResult {
        let item: CanvasImportedVideoAsset
        let createdAssetURLs: [URL]
    }

    private static func importVideo(
        _ video: CanvasResolvedImportVideo,
        into assetsDirectoryURL: URL
    ) throws -> ImportedVideoResult {
        let sourceVideoFilename = makeUniqueVideoFilename(for: video.source)
        let posterImageFilename = makePosterFilename()
        let sourceVideoAssetURL = assetsDirectoryURL.appendingPathComponent(
            sourceVideoFilename
        )
        let posterImageAssetURL = assetsDirectoryURL.appendingPathComponent(
            posterImageFilename
        )

        try CoordinatedFileIO.copyItem(
            at: video.source.localFileURL,
            to: sourceVideoAssetURL
        )
        try CoordinatedFileIO.writeData(
            makePNGData(for: video.posterCGImage),
            to: posterImageAssetURL
        )

        let posterAsset = CanvasImageAsset.persistedStaticImage(
            filename: posterImageFilename,
            cgImage: video.posterCGImage,
            logicalPixelSize: video.logicalPixelSize
        )
        let videoSource = CanvasVideoSource(
            assetReference: .persisted(filename: sourceVideoFilename),
            posterTimeSeconds: video.posterTimeSeconds
        )
        return ImportedVideoResult(
            item: CanvasImportedVideoAsset(
                asset: posterAsset,
                videoSource: videoSource
            ),
            createdAssetURLs: [
                sourceVideoAssetURL,
                posterImageAssetURL
            ]
        )
    }

    private static func makeUniqueVideoFilename(
        for source: CanvasImportedVideoSource
    ) -> String {
        "\(UUID().uuidString).\(preferredVideoFileExtension(for: source))"
    }

    private static func preferredVideoFileExtension(
        for source: CanvasImportedVideoSource
    ) -> String {
        if let filenameHint = source.filenameHint,
           filenameHint.isEmpty == false
        {
            let hintExtension = URL(fileURLWithPath: filenameHint)
                .pathExtension
                .lowercased()
            if hintExtension.isEmpty == false {
                return hintExtension
            }
        }

        if let preferredFilenameExtension = source.contentType?
            .preferredFilenameExtension?
            .lowercased(),
           preferredFilenameExtension.isEmpty == false
        {
            return preferredFilenameExtension
        }

        let sourcePathExtension = source.localFileURL.pathExtension.lowercased()
        if sourcePathExtension.isEmpty == false {
            return sourcePathExtension
        }

        return "mov"
    }

    private static func makePosterFilename() -> String {
        "\(UUID().uuidString).png"
    }

    private static func makePNGData(
        for image: CGImage
    ) throws -> Data {
        let mutableData = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                mutableData,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        else {
            throw CanvasMediaImportServiceError.failedToEncodeVideoPoster
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CanvasMediaImportServiceError.failedToEncodeVideoPoster
        }

        return mutableData as Data
    }

    private static func cleanupImportedAssetURLs(
        _ assetURLs: [URL]
    ) {
        for assetURL in assetURLs.reversed() {
            try? CoordinatedFileIO.removeItemIfExists(at: assetURL)
        }
    }

    private static func cleanupTemporaryVideoURLs(
        _ temporaryVideoURLs: [URL]
    ) {
        for temporaryVideoURL in Set(temporaryVideoURLs) {
            try? FileManager.default.removeItem(at: temporaryVideoURL)
        }
    }
}
