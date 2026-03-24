#if os(iOS)
import ImageIO
import PhotosUI
import UniformTypeIdentifiers
import UIKit

enum iOSCanvasImportAdapter {
    static func transferRequest(
        from results: [PHPickerResult],
        sourceDescription: String,
        placement: CanvasImportPlacement = .cameraCenter,
        layout: CanvasImportLayout = .automatic
    ) async -> CanvasTransferRequest? {
        let resolvedImages = await resolvedImages(
            from: results.map(\.itemProvider)
        )

        return makeTransferRequest(
            from: resolvedImages,
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
        let imageProviders = pasteboard.itemProviders.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.image.identifier)
        }
        if imageProviders.isEmpty == false {
            let resolvedImages = await resolvedImages(from: imageProviders)
            if resolvedImages.isEmpty == false {
                return makeTransferRequest(
                    from: resolvedImages,
                    sourceDescription: sourceDescription,
                    placement: placement,
                    layout: layout
                )
            }
        }

        guard
            let image = pasteboard.image,
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

    static func transferRequest(
        from dropSession: UIDropSession,
        sourceDescription: String,
        placement: CanvasImportPlacement = .cameraCenter,
        layout: CanvasImportLayout = .automatic
    ) async -> CanvasTransferRequest? {
        let resolvedImages = await resolvedImages(
            from: dropSession.items.map(\.itemProvider)
        )

        return makeTransferRequest(
            from: resolvedImages,
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
            $0.hasItemConformingToTypeIdentifier(UTType.image.identifier)
        }
    }

    static func canResolveTransfer(
        from dropSession: UIDropSession
    ) -> Bool {
        dropSession.hasItemsConforming(
            toTypeIdentifiers: [UTType.image.identifier]
        )
    }

    private static func resolvedImages(
        from itemProviders: [NSItemProvider]
    ) async -> [CanvasResolvedImportImage] {
        var resolvedImages: [CanvasResolvedImportImage] = []
        resolvedImages.reserveCapacity(itemProviders.count)

        for itemProvider in itemProviders {
            guard
                let resolvedImage = await resolvedImage(
                    from: itemProvider
                )
            else {
                continue
            }

            resolvedImages.append(resolvedImage)
        }

        return resolvedImages
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
                UTType(importedAs: $0).conforms(to: .image)
        }
        if let specificImageTypeIdentifier {
            return specificImageTypeIdentifier
        }

        guard itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else {
            return nil
        }

        return UTType.image.identifier
    }
}
#endif
