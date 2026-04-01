#if os(iOS)
import PhotosUI
import UniformTypeIdentifiers
import UIKit

enum iOSCanvasImportAdapter {
    private static let supportedTransferTypeIdentifiers = [
        UTType.image.identifier,
        UTType.movie.identifier,
        UTType.video.identifier
    ]

    static func transferRequest(
        from results: [PHPickerResult],
        sourceDescription: String,
        placement: CanvasImportPlacement = .cameraCenter,
        layout: CanvasImportLayout = .automatic
    ) async -> CanvasTransferRequest? {
        let resolvedItems = await resolvedTransferItems(
            from: results.map(\.itemProvider)
        )

        return makeTransferRequest(
            from: resolvedItems,
            sourceDescription: sourceDescription,
            placement: placement,
            layout: layout
        )
    }

    static func transferRequest(
        from pasteboard: UIPasteboard,
        sourceDescription: String,
        placement: CanvasImportPlacement = .cameraCenter,
        layout: CanvasImportLayout = .automatic
    ) async -> CanvasTransferRequest? {
        let resolvedItems = await resolvedTransferItems(
            from: pasteboard.itemProviders
        )
        if resolvedItems.isEmpty == false {
            return makeTransferRequest(
                from: resolvedItems,
                sourceDescription: sourceDescription,
                placement: placement,
                layout: layout
            )
        }

        guard
            let image = pasteboard.image,
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

    static func transferRequest(
        from dropSession: UIDropSession,
        sourceDescription: String,
        placement: CanvasImportPlacement = .cameraCenter,
        layout: CanvasImportLayout = .automatic
    ) async -> CanvasTransferRequest? {
        let resolvedItems = await resolvedTransferItems(
            from: dropSession.items.map(\.itemProvider)
        )

        return makeTransferRequest(
            from: resolvedItems,
            sourceDescription: sourceDescription,
            placement: placement,
            layout: layout
        )
    }

    static func canResolveTransfer(
        from pasteboard: UIPasteboard
    ) -> Bool {
        if pasteboard.hasImages {
            return true
        }

        return pasteboard.itemProviders.contains {
            canResolveTransfer(from: $0)
        }
    }

    static func canResolveTransfer(
        from dropSession: UIDropSession
    ) -> Bool {
        dropSession.hasItemsConforming(
            toTypeIdentifiers: supportedTransferTypeIdentifiers
        )
    }

    private static func resolvedTransferItems(
        from itemProviders: [NSItemProvider]
    ) async -> [CanvasTransferItem] {
        var resolvedItems: [CanvasTransferItem] = []
        resolvedItems.reserveCapacity(itemProviders.count)

        for itemProvider in itemProviders {
            guard
                let resolvedItem = await resolvedTransferItem(
                    from: itemProvider
                )
            else {
                continue
            }

            resolvedItems.append(resolvedItem)
        }

        return resolvedItems
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

    private static func resolvedTransferItem(
        from itemProvider: NSItemProvider
    ) async -> CanvasTransferItem? {
        if preferredVideoTypeIdentifier(from: itemProvider) != nil {
            guard let resolvedVideo = await resolvedVideo(from: itemProvider) else {
                return nil
            }

            return .video(resolvedVideo)
        }

        if let resolvedImage = await resolvedImage(from: itemProvider) {
            return .image(resolvedImage)
        }

        return nil
    }

    private static func resolvedImage(
        from itemProvider: NSItemProvider
    ) async -> CanvasResolvedImportImage? {
        let preferredTypeIdentifier =
            preferredImageTypeIdentifier(from: itemProvider) ??
            UTType.image.identifier
        guard
            itemProvider.hasItemConformingToTypeIdentifier(
                UTType.image.identifier
            ),
            let data = await loadImageData(
                from: itemProvider,
                typeIdentifier: preferredTypeIdentifier
            ),
            let resolvedImage = CanvasResolvedImportImage(
                data: data,
                typeIdentifier: preferredTypeIdentifier,
                filenameHint: itemProvider.suggestedName
            )
        else {
            return nil
        }

        return resolvedImage
    }

    private static func resolvedVideo(
        from itemProvider: NSItemProvider
    ) async -> CanvasResolvedImportVideo? {
        guard
            let preferredTypeIdentifier = preferredVideoTypeIdentifier(
                from: itemProvider
            ),
            let ownedFileURL = await loadOwnedFileURL(
                from: itemProvider,
                typeIdentifier: preferredTypeIdentifier,
                filenameHint: itemProvider.suggestedName
            )
        else {
            return nil
        }

        return CanvasResolvedImportVideo(
            localFileURL: ownedFileURL,
            typeIdentifier: preferredTypeIdentifier,
            filenameHint: resolvedFilenameHint(
                itemProvider.suggestedName,
                typeIdentifier: preferredTypeIdentifier
            ),
            shouldDeleteAfterImport: true
        )
    }

    private static func loadImageData(
        from itemProvider: NSItemProvider,
        typeIdentifier: String
    ) async -> Data? {
        await withCheckedContinuation { continuation in
            itemProvider.loadDataRepresentation(
                forTypeIdentifier: typeIdentifier
            ) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    private static func loadOwnedFileURL(
        from itemProvider: NSItemProvider,
        typeIdentifier: String,
        filenameHint: String?
    ) async -> URL? {
        await withCheckedContinuation { continuation in
            itemProvider.loadFileRepresentation(
                forTypeIdentifier: typeIdentifier
            ) { fileURL, _ in
                guard let fileURL else {
                    continuation.resume(returning: nil)
                    return
                }

                do {
                    let ownedFileURL = try makeOwnedTemporaryCopy(
                        of: fileURL,
                        filenameHint: filenameHint,
                        typeIdentifier: typeIdentifier
                    )
                    continuation.resume(returning: ownedFileURL)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private static func makeOwnedTemporaryCopy(
        of sourceURL: URL,
        filenameHint: String?,
        typeIdentifier: String
    ) throws -> URL {
        let fileManager = FileManager.default
        let stagingDirectoryURL = fileManager.temporaryDirectory
            .appendingPathComponent(
                "CanvasImportedVideoStaging",
                isDirectory: true
            )
        try fileManager.createDirectory(
            at: stagingDirectoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let fileExtension = preferredOwnedFileExtension(
            filenameHint: filenameHint,
            typeIdentifier: typeIdentifier,
            fallbackURL: sourceURL
        )
        let stagedFileURL = stagingDirectoryURL.appendingPathComponent(
            "\(UUID().uuidString).\(fileExtension)"
        )
        try fileManager.copyItem(
            at: sourceURL,
            to: stagedFileURL
        )
        return stagedFileURL
    }

    private static func preferredOwnedFileExtension(
        filenameHint: String?,
        typeIdentifier: String,
        fallbackURL: URL
    ) -> String {
        if let filenameHint, filenameHint.isEmpty == false {
            let hintExtension = URL(fileURLWithPath: filenameHint)
                .pathExtension
                .lowercased()
            if hintExtension.isEmpty == false {
                return hintExtension
            }
        }

        let contentType = CanvasTypeIdentifierResolver.contentType(
            for: typeIdentifier
        )
        if let preferredFilenameExtension = contentType?
            .preferredFilenameExtension?
            .lowercased(),
           preferredFilenameExtension.isEmpty == false
        {
            return preferredFilenameExtension
        }

        let sourcePathExtension = fallbackURL.pathExtension.lowercased()
        if sourcePathExtension.isEmpty == false {
            return sourcePathExtension
        }

        return "mov"
    }

    private static func makeResolvedImportImage(
        from image: UIImage
    ) -> CanvasResolvedImportImage? {
        if let pngData = image.pngData(),
           let resolvedImage = CanvasResolvedImportImage(
               data: pngData,
               typeIdentifier: UTType.png.identifier
           ) {
            return resolvedImage
        }

        if let cgImage = image.cgImage {
            return CanvasResolvedImportImage(cgImage: cgImage)
        }

        let renderer = UIGraphicsImageRenderer(size: image.size)
        let renderedImage = renderer.image { _ in
            image.draw(at: .zero)
        }
        guard let cgImage = renderedImage.cgImage else {
            return nil
        }

        return CanvasResolvedImportImage(cgImage: cgImage)
    }

    private static func preferredImageTypeIdentifier(
        from itemProvider: NSItemProvider
    ) -> String? {
        let specificImageTypeIdentifier = itemProvider.registeredTypeIdentifiers.first {
            $0 != UTType.image.identifier &&
                CanvasTypeIdentifierResolver.contentType(for: $0)?
                .conforms(to: .image) == true
        }
        if let specificImageTypeIdentifier {
            return specificImageTypeIdentifier
        }

        guard itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else {
            return nil
        }

        return UTType.image.identifier
    }

    private static func preferredVideoTypeIdentifier(
        from itemProvider: NSItemProvider
    ) -> String? {
        let specificVideoTypeIdentifier = itemProvider.registeredTypeIdentifiers.first {
            guard let contentType = CanvasTypeIdentifierResolver.contentType(
                for: $0
            ) else {
                return false
            }
            return contentType.conforms(to: .movie) ||
                contentType.conforms(to: .video)
        }
        if let specificVideoTypeIdentifier {
            return specificVideoTypeIdentifier
        }

        if itemProvider.hasItemConformingToTypeIdentifier(
            UTType.movie.identifier
        ) {
            return UTType.movie.identifier
        }

        if itemProvider.hasItemConformingToTypeIdentifier(
            UTType.video.identifier
        ) {
            return UTType.video.identifier
        }

        return nil
    }

    private static func canResolveTransfer(
        from itemProvider: NSItemProvider
    ) -> Bool {
        itemProvider.hasItemConformingToTypeIdentifier(
            UTType.image.identifier
        ) || preferredVideoTypeIdentifier(from: itemProvider) != nil
    }

    private static func resolvedFilenameHint(
        _ filenameHint: String?,
        typeIdentifier: String
    ) -> String? {
        guard let filenameHint, filenameHint.isEmpty == false else {
            if let preferredFilenameExtension = CanvasTypeIdentifierResolver
                .contentType(for: typeIdentifier)?
                .preferredFilenameExtension
            {
                return "video.\(preferredFilenameExtension)"
            }

            return nil
        }

        if URL(fileURLWithPath: filenameHint).pathExtension.isEmpty == false {
            return filenameHint
        }

        if let preferredFilenameExtension = CanvasTypeIdentifierResolver
            .contentType(for: typeIdentifier)?
            .preferredFilenameExtension
        {
            return "\(filenameHint).\(preferredFilenameExtension)"
        }

        return filenameHint
    }
}
#endif
