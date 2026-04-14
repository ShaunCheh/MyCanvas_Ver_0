import UniformTypeIdentifiers
import UIKit

enum ShareExtensionImageResolver {
    static func resolveImages(
        from extensionContext: NSExtensionContext?
    ) async -> [CanvasResolvedImportImage] {
        let inputItems = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        var resolvedImages: [CanvasResolvedImportImage] = []

        for inputItem in inputItems {
            for itemProvider in inputItem.attachments ?? [] {
                guard let resolvedImage = await resolvedImage(from: itemProvider) else {
                    continue
                }

                resolvedImages.append(resolvedImage)
            }
        }

        return resolvedImages
    }

    private static func resolvedImage(
        from itemProvider: NSItemProvider
    ) async -> CanvasResolvedImportImage? {
        guard itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else {
            return nil
        }

        for typeIdentifier in preferredImageTypeIdentifiers(from: itemProvider) {
            guard
                let data = await loadImageData(
                    from: itemProvider,
                    typeIdentifier: typeIdentifier
                ),
                let resolvedImage = CanvasResolvedImportImage(
                    data: data,
                    typeIdentifier: typeIdentifier,
                    filenameHint: itemProvider.suggestedName
                )
            else {
                continue
            }

            return resolvedImage
        }

        return nil
    }

    private static func preferredImageTypeIdentifiers(
        from itemProvider: NSItemProvider
    ) -> [String] {
        var typeIdentifiers: [String] = []

        if let specificImageTypeIdentifier = itemProvider.registeredTypeIdentifiers.first(
            where: { typeIdentifier in
                typeIdentifier != UTType.image.identifier &&
                    CanvasTypeIdentifierResolver.contentType(for: typeIdentifier)?
                    .conforms(to: .image) == true
            }
        ) {
            typeIdentifiers.append(specificImageTypeIdentifier)
        }

        if typeIdentifiers.contains(UTType.image.identifier) == false {
            typeIdentifiers.append(UTType.image.identifier)
        }

        return typeIdentifiers
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
}
