#if os(macOS)
import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum macOSCanvasImportAdapter {
    private static let mediaFileURLReadingOptions: [NSPasteboard.ReadingOptionKey: Any] = [
        .urlReadingFileURLsOnly: true,
        .urlReadingContentsConformToTypes: [
            UTType.image.identifier,
            UTType.movie.identifier,
            UTType.video.identifier
        ]
    ]

    static func transferRequest(
        from urls: [URL],
        sourceDescription: String,
        placement: CanvasImportPlacement = .cameraCenter,
        layout: CanvasImportLayout = .automatic
    ) -> CanvasTransferRequest? {
        makeTransferRequest(
            from: resolvedTransferItems(from: urls),
            sourceDescription: sourceDescription,
            placement: placement,
            layout: layout
        )
    }

    static func transferRequest(
        from pasteboard: NSPasteboard,
        sourceDescription: String,
        placement: CanvasImportPlacement = .cameraCenter,
        layout: CanvasImportLayout = .automatic
    ) -> CanvasTransferRequest? {
        let mediaFileURLs = self.mediaFileURLs(from: pasteboard)
        if mediaFileURLs.isEmpty == false {
            return transferRequest(
                from: mediaFileURLs,
                sourceDescription: sourceDescription,
                placement: placement,
                layout: layout
            )
        }

        guard
            let image = NSImage(pasteboard: pasteboard),
            let resolvedImage = makeResolvedImportImage(from: image)
        else {
            return nil
        }

        return makeTransferRequest(
            from: [.image(resolvedImage)],
            sourceDescription: sourceDescription,
            placement: placement,
            layout: layout
        )
    }

    static func canResolveTransfer(from pasteboard: NSPasteboard) -> Bool {
        if mediaFileURLs(from: pasteboard).isEmpty == false {
            return true
        }

        return NSImage(pasteboard: pasteboard) != nil
    }

    private static func resolvedTransferItems(
        from urls: [URL]
    ) -> [CanvasTransferItem] {
        urls.compactMap(makeResolvedTransferItem(from:))
    }

    private static func makeTransferRequest(
        from items: [CanvasTransferItem],
        sourceDescription: String,
        placement: CanvasImportPlacement,
        layout: CanvasImportLayout
    ) -> CanvasTransferRequest? {
        guard items.isEmpty == false else {
            return nil
        }

        return CanvasTransferRequest(
            items: items,
            placement: placement,
            layout: layout,
            sourceDescription: sourceDescription
        )
    }

    private static func mediaFileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let objects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: mediaFileURLReadingOptions
        ) as? [NSURL] ?? []
        return objects.map { $0 as URL }
    }

    private static func makeResolvedTransferItem(
        from url: URL
    ) -> CanvasTransferItem? {
        let contentType = resolvedContentType(from: url)
        if contentType?.conforms(to: .image) == true {
            guard let resolvedImage = makeResolvedImportImage(
                from: url,
                typeIdentifier: contentType?.identifier
            ) else {
                return nil
            }

            return .image(resolvedImage)
        }

        if contentType.map(isVideoContentType) == true || isLikelyVideoURL(url) {
            guard let resolvedVideo = CanvasResolvedImportVideo(
                localFileURL: url,
                typeIdentifier: contentType?.identifier,
                filenameHint: url.lastPathComponent
            ) else {
                return nil
            }

            return .video(resolvedVideo)
        }

        return nil
    }

    private static func makeResolvedImportImage(
        from url: URL,
        typeIdentifier: String?
    ) -> CanvasResolvedImportImage? {
        guard let assetData = try? Data(contentsOf: url) else {
            return nil
        }

        return CanvasResolvedImportImage(
            data: assetData,
            typeIdentifier: typeIdentifier ?? resolvedContentType(from: url)?.identifier,
            filenameHint: url.lastPathComponent
        )
    }

    private static func makeResolvedImportImage(
        from image: NSImage
    ) -> CanvasResolvedImportImage? {
        var proposedRect = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(
            forProposedRect: &proposedRect,
            context: nil,
            hints: nil
        ) else {
            return nil
        }

        if let pngData = makePNGData(from: cgImage),
           let resolvedImage = CanvasResolvedImportImage(
               data: pngData,
               typeIdentifier: UTType.png.identifier
           ) {
            return resolvedImage
        }

        return CanvasResolvedImportImage(cgImage: cgImage)
    }

    private static func resolvedContentType(
        from url: URL
    ) -> UTType? {
        if let resourceValues = try? url.resourceValues(
            forKeys: [.contentTypeKey]
        ),
           let contentType = resourceValues.contentType {
            return contentType
        }

        guard url.pathExtension.isEmpty == false else {
            return nil
        }

        return UTType(filenameExtension: url.pathExtension)
    }

    private static func isVideoContentType(
        _ contentType: UTType
    ) -> Bool {
        contentType.conforms(to: .movie) ||
            contentType.conforms(to: .video)
    }

    private static func isLikelyVideoURL(
        _ url: URL
    ) -> Bool {
        guard url.pathExtension.isEmpty == false,
              let contentType = UTType(filenameExtension: url.pathExtension)
        else {
            return false
        }

        return isVideoContentType(contentType)
    }

    private static func makePNGData(
        from cgImage: CGImage
    ) -> Data? {
        let mutableData = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                mutableData,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        else {
            return nil
        }

        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }

        return mutableData as Data
    }
}
#endif
