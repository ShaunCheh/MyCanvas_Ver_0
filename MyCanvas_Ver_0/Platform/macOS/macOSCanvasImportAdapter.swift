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

    static func resolvedImages(from urls: [URL]) -> [CanvasResolvedImportImage] {
        urls.compactMap(makeResolvedImportImage(from:))
    }

    static func resolvedImages(from pasteboard: NSPasteboard) -> [CanvasResolvedImportImage] {
        let imageFileURLs = self.imageFileURLs(from: pasteboard)
        if imageFileURLs.isEmpty == false {
            return resolvedImages(from: imageFileURLs)
        }

        guard
            let image = NSImage(pasteboard: pasteboard),
            let resolvedImage = makeResolvedImportImage(from: image)
        else {
            return []
        }

        return [resolvedImage]
    }

    static func canResolveImages(from pasteboard: NSPasteboard) -> Bool {
        if imageFileURLs(from: pasteboard).isEmpty == false {
            return true
        }

        return NSImage(pasteboard: pasteboard) != nil
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
        guard
            let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
            let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
        else {
            return nil
        }

        return CanvasResolvedImportImage(cgImage: cgImage)
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

        return CanvasResolvedImportImage(cgImage: cgImage)
    }
}
#endif
