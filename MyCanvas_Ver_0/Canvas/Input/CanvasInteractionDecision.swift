import Foundation

struct CanvasInteractionEnvironment: Equatable, Sendable {
    let workspaceMode: CanvasWorkspaceMode
    let isTransitionInteractionFrozen: Bool

    // Shared policy consumers outside controller-local capture can normalize to
    // workspace mode only and leave transition freeze at the controller edge.
    static func workspaceModeOnly(
        workspaceMode: CanvasWorkspaceMode
    ) -> CanvasInteractionEnvironment {
        CanvasInteractionEnvironment(
            workspaceMode: workspaceMode,
            isTransitionInteractionFrozen: false
        )
    }

    // Command lane does not own controller-local freeze state, so phase4 only
    // normalizes workspace mode here and keeps transition freeze upstream.
    static func commandLane(
        workspaceMode: CanvasWorkspaceMode
    ) -> CanvasInteractionEnvironment {
        workspaceModeOnly(workspaceMode: workspaceMode)
    }
}

enum CanvasInteractionBlockReason: Equatable, Sendable {
    case readingMode
    case transitionInteractionFrozen
}

enum CanvasInteractionFeedbackHint: Equatable, Sendable {
    case shakeWorkspaceModeButton
}

enum CanvasInteractionDecision: Equatable, Sendable {
    case allow
    case block(
        reason: CanvasInteractionBlockReason,
        feedback: CanvasInteractionFeedbackHint?
    )
}
