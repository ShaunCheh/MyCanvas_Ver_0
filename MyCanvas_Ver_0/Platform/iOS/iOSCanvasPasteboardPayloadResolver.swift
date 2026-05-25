#if os(iOS)
import UIKit

enum iOSCanvasPasteboardPayloadResolver {
    static func resolvedPayload(
        from pasteboard: UIPasteboard,
        sourceDescription: String,
        placement: CanvasImportPlacement = .cameraCenter,
        layout: CanvasImportLayout = .automatic
    ) async -> CanvasPastePayload? {
        if let transferRequest = await iOSCanvasImportAdapter.transferRequest(
            from: pasteboard,
            sourceDescription: sourceDescription,
            placement: placement,
            layout: layout
        ) {
            return .media(transferRequest)
        }

        guard let text = resolvedMarkdownText(from: pasteboard) else {
            return nil
        }

        return .markdownText(text)
    }

    static func canResolvePayload(
        from pasteboard: UIPasteboard
    ) -> Bool {
        if iOSCanvasImportAdapter.canResolveTransfer(from: pasteboard) {
            return true
        }

        return resolvedMarkdownText(from: pasteboard) != nil
    }

    private static func resolvedMarkdownText(
        from pasteboard: UIPasteboard
    ) -> String? {
        guard pasteboard.hasStrings else {
            return nil
        }

        guard
            let text = pasteboard.strings?.first ?? pasteboard.string,
            text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        else {
            return nil
        }

        return text
    }
}
#endif
