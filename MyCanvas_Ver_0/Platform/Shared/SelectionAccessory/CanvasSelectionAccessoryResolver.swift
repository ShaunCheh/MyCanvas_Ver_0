import CoreGraphics
import Foundation

struct CanvasSelectionAccessoryResolver {
    struct Environment {
        let workspaceMode: CanvasWorkspaceMode
        let isTransitionInteractionFrozen: Bool
        let hasContextMenu: Bool
        let hasPresentedOverlayEditor: Bool
        let hasInlineEditPresentation: Bool
    }

    private let commandCatalog = CanvasCommandCatalog()

    func resolveState(
        session: CanvasEditorSession,
        environment: Environment,
        anchorRect: CGRect?
    ) -> SelectionAccessoryState? {
        guard
            environment.workspaceMode == .editing,
            environment.isTransitionInteractionFrozen == false,
            environment.hasContextMenu == false,
            environment.hasPresentedOverlayEditor == false,
            environment.hasInlineEditPresentation == false,
            let item = session.selectedBoardItem,
            let anchorRect,
            let sanitizedAnchorRect = CanvasChromeLayoutGeometry.sanitizedRect(
                anchorRect
            )
        else {
            return nil
        }

        switch item {
        case let .markdown(markdownItem):
            return SelectionAccessoryState.markdown(
                itemID: markdownItem.id,
                anchorRect: sanitizedAnchorRect,
                editDescriptor: commandCatalog.descriptor(
                    for: .beginMarkdownEdit,
                    session: session
                ),
                decreaseDescriptor: commandCatalog.descriptor(
                    for: .decreaseMarkdownContentSize,
                    session: session
                ),
                increaseDescriptor: commandCatalog.descriptor(
                    for: .increaseMarkdownContentSize,
                    session: session
                )
            )
        case let .arrow(arrowItem):
            return SelectionAccessoryState.arrow(
                itemID: arrowItem.id,
                anchorRect: sanitizedAnchorRect,
                decreaseDescriptor: commandCatalog.descriptor(
                    for: .decreaseArrowThickness,
                    session: session
                ),
                increaseDescriptor: commandCatalog.descriptor(
                    for: .increaseArrowThickness,
                    session: session
                )
            )
        case .image, .text, .handDrawing:
            return nil
        }
    }
}
