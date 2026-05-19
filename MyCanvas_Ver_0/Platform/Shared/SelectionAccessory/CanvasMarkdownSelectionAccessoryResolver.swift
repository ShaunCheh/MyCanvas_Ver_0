import CoreGraphics
import Foundation

struct CanvasMarkdownSelectionAccessoryResolver {
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
            let item = session.selectedMarkdownItem,
            let anchorRect,
            let sanitizedAnchorRect = CanvasChromeLayoutGeometry.sanitizedRect(
                anchorRect
            )
        else {
            return nil
        }

        let editDescriptor = commandCatalog.descriptor(
            for: .beginMarkdownEdit,
            session: session
        )
        let decreaseDescriptor = commandCatalog.descriptor(
            for: .decreaseMarkdownContentSize,
            session: session
        )
        let increaseDescriptor = commandCatalog.descriptor(
            for: .increaseMarkdownContentSize,
            session: session
        )
        return SelectionAccessoryState.markdown(
            itemID: item.id,
            anchorRect: sanitizedAnchorRect,
            editDescriptor: editDescriptor,
            decreaseDescriptor: decreaseDescriptor,
            increaseDescriptor: increaseDescriptor
        )
    }
}
