enum CanvasEditHandlePointerLifecycleState: Hashable, Sendable {
    case pressed(CanvasEditHandleIdentity?)
    case draggingHandle
    case inactive
}

struct CanvasEditHandleControllerAdapter: Hashable, Sendable {
    private(set) var expectedDraggingIdentity: CanvasEditHandleIdentity?

    mutating func event(
        for pointerState: CanvasEditHandlePointerLifecycleState
    ) -> CanvasEditHandleInteractionEvent {
        switch pointerState {
        case let .pressed(identity):
            expectedDraggingIdentity = identity
            return .press(identity)

        case .draggingHandle:
            guard let expectedDraggingIdentity else {
                return .cancel
            }
            return .beginDragging(
                expectedIdentity: expectedDraggingIdentity
            )

        case .inactive:
            expectedDraggingIdentity = nil
            return .end
        }
    }
}
