#if os(macOS)
import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum macOSCanvasImportAdapter {
    private static let imageFileURLReadingOptions: [NSPasteboard.ReadingOptionKey: Any] = [
        .urlReadingFileURLsOnly: true,
        .urlReadingContentsConformToTypes: [UTType.image.identifier]
    ]

    static func transferRequest(
        from urls: [URL],
        sourceDescription: String,
        placement: CanvasImportPlacement = .cameraCenter,
        layout: CanvasImportLayout = .automatic
    ) -> CanvasTransferRequest? {
        makeTransferRequest(
            from: resolvedImages(from: urls),
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
        let imageFileURLs = self.imageFileURLs(from: pasteboard)
        if imageFileURLs.isEmpty == false {
            return transferRequest(
                from: imageFileURLs,
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
            from: [resolvedImage],
            sourceDescription: sourceDescription,
            placement: placement,
            layout: layout
        )
    }

    static func canResolveTransfer(from pasteboard: NSPasteboard) -> Bool {
        if imageFileURLs(from: pasteboard).isEmpty == false {
            return true
        }

        return NSImage(pasteboard: pasteboard) != nil
    }

    private static func resolvedImages(
        from urls: [URL]
    ) -> [CanvasResolvedImportImage] {
        urls.compactMap(makeResolvedImportImage(from:))
    }

    private static func makeTransferRequest(
        from images: [CanvasResolvedImportImage],
        sourceDescription: String,
        placement: CanvasImportPlacement,
        layout: CanvasImportLayout
    ) -> CanvasTransferRequest? {
        guard images.isEmpty == false else {
            return nil
        }

        return CanvasTransferRequest(
            images: images,
            placement: placement,
            layout: layout,
            sourceDescription: sourceDescription
        )
    }

    private static func imageFileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let objects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: imageFileURLReadingOptions
        ) as? [NSURL] ?? []
        return objects.map { $0 as URL }
    }

    private static func makeResolvedImportImage(
        from url: URL
    ) -> CanvasResolvedImportImage? {
        guard let assetData = try? Data(contentsOf: url) else {
            return nil
        }

        return CanvasResolvedImportImage(
            data: assetData,
            typeIdentifier: resolvedTypeIdentifier(from: url),
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

    private static func resolvedTypeIdentifier(
        from url: URL
    ) -> String? {
        if let resourceValues = try? url.resourceValues(
            forKeys: [.contentTypeKey]
        ),
           let contentType = resourceValues.contentType {
            return contentType.identifier
        }

        guard url.pathExtension.isEmpty == false else {
            return nil
        }

        return UTType(filenameExtension: url.pathExtension)?.identifier
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
