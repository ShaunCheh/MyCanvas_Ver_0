#if os(macOS)
import AppKit
import Foundation

enum macOSCanvasPasteboardPayloadResolver {
    private static let fileURLReadingOptions: [NSPasteboard.ReadingOptionKey: Any] = [
        .urlReadingFileURLsOnly: true
    ]

    static func resolvedPayload(
        from pasteboard: NSPasteboard,
        sourceDescription: String,
        placement: CanvasImportPlacement = .cameraCenter,
        layout: CanvasImportLayout = .automatic
    ) -> CanvasPastePayload? {
        if let transferRequest = macOSCanvasImportAdapter.transferRequest(
            from: pasteboard,
            sourceDescription: sourceDescription,
            placement: placement,
            layout: layout
        ) {
            return .media(transferRequest)
        }

        // Finder copies can expose both file URLs and path strings. If the file
        // URL is not importable media, avoid reinterpreting the path string as
        // markdown content.
        guard
            containsFileURLs(from: pasteboard) == false,
            let text = resolvedMarkdownText(from: pasteboard)
        else {
            return nil
        }

        return .markdownText(text)
    }

    static func canResolvePayload(
        from pasteboard: NSPasteboard
    ) -> Bool {
        if macOSCanvasImportAdapter.canResolveTransfer(from: pasteboard) {
            return true
        }

        guard containsFileURLs(from: pasteboard) == false else {
            return false
        }

        return resolvedMarkdownText(from: pasteboard) != nil
    }

    private static func resolvedMarkdownText(
        from pasteboard: NSPasteboard
    ) -> String? {
        let text =
            (pasteboard.readObjects(
                forClasses: [NSString.self],
                options: nil
            ) as? [NSString])?.first as String? ??
            pasteboard.string(forType: .string)

        guard
            let text,
            text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        else {
            return nil
        }

        return text
    }

    private static func containsFileURLs(
        from pasteboard: NSPasteboard
    ) -> Bool {
        let objects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: fileURLReadingOptions
        ) as? [NSURL] ?? []
        return objects.isEmpty == false
    }
}
#endif
