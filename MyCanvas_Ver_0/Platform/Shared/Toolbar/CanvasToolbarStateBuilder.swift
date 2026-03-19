import Foundation

struct CanvasToolbarStateBuilder {
    private let commandCatalog = CanvasCommandCatalog()

    func cropItemState(session: CanvasEditorSession) -> CanvasToolbarItemState {
        let descriptor = commandCatalog.descriptor(
            for: .crop,
            session: session
        )
        return cropItemState(from: descriptor)
    }

    func cropItemState(from descriptor: CanvasCommandDescriptor) -> CanvasToolbarItemState {
        CanvasToolbarItemState(
            id: .crop,
            systemImageName: descriptor.systemImageName,
            isEnabled: descriptor.isEnabled,
            isActive: descriptor.isActive,
            accessibilityLabel: descriptor.title == "Done" ? "Done cropping" : "Crop",
            visualRole: descriptor.isActive ? .warning : .accent
        )
    }

    func saveItemState(saveState: CanvasSaveState) -> CanvasToolbarItemState {
        CanvasToolbarItemState(
            id: .save,
            systemImageName: saveState.systemImageName,
            isEnabled: saveState.isEnabled,
            accessibilityLabel: "Save board",
            accessibilityValue: saveState.accessibilityValue,
            visualRole: saveState.visualRole
        )
    }
}
