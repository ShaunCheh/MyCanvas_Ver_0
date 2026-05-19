import CoreGraphics
import Foundation

struct SelectionAccessoryActionDescriptor: Equatable {
    let title: String
    let systemImageName: String
    let isEnabled: Bool
    let isActive: Bool

    init(
        title: String,
        systemImageName: String,
        isEnabled: Bool,
        isActive: Bool
    ) {
        self.title = title
        self.systemImageName = systemImageName
        self.isEnabled = isEnabled
        self.isActive = isActive
    }

    init(commandDescriptor: CanvasCommandDescriptor) {
        self.init(
            title: commandDescriptor.title,
            systemImageName: commandDescriptor.systemImageName,
            isEnabled: commandDescriptor.isEnabled,
            isActive: commandDescriptor.isActive
        )
    }
}

struct SelectionAccessoryActionState: Equatable {
    let commandID: CanvasCommandID
    let descriptor: SelectionAccessoryActionDescriptor
}

struct SelectionAccessoryState: Equatable {
    let itemID: CanvasItemID
    let anchorRect: CGRect
    let actionStates: [SelectionAccessoryActionState]

    init(
        itemID: CanvasItemID,
        anchorRect: CGRect,
        actionStates: [SelectionAccessoryActionState]
    ) {
        self.itemID = itemID
        self.anchorRect = CanvasChromeLayoutGeometry.sanitizedRect(anchorRect) ?? .zero
        self.actionStates = actionStates
    }

    var isEmpty: Bool {
        actionStates.isEmpty || anchorRect.isEmpty
    }

    static func markdown(
        itemID: CanvasItemID,
        anchorRect: CGRect,
        editDescriptor: CanvasCommandDescriptor,
        decreaseDescriptor: CanvasCommandDescriptor,
        increaseDescriptor: CanvasCommandDescriptor
    ) -> SelectionAccessoryState {
        SelectionAccessoryState(
            itemID: itemID,
            anchorRect: anchorRect,
            actionStates: [
                SelectionAccessoryActionState(
                    commandID: editDescriptor.id,
                    descriptor: SelectionAccessoryActionDescriptor(
                        commandDescriptor: editDescriptor
                    )
                ),
                SelectionAccessoryActionState(
                    commandID: decreaseDescriptor.id,
                    descriptor: SelectionAccessoryActionDescriptor(
                        commandDescriptor: decreaseDescriptor
                    )
                ),
                SelectionAccessoryActionState(
                    commandID: increaseDescriptor.id,
                    descriptor: SelectionAccessoryActionDescriptor(
                        commandDescriptor: increaseDescriptor
                    )
                )
            ]
        )
    }
}
