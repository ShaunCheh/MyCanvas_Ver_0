enum CanvasEditHandleVisualState: Hashable, Sendable {
    case normal
    case active
}

enum CanvasEditHandleInteractionPhase: Hashable, Sendable {
    case inactive
    case pressed(CanvasEditHandleIdentity)
    case dragging(CanvasEditHandleIdentity)

    var activeIdentity: CanvasEditHandleIdentity? {
        switch self {
        case .inactive:
            return nil
        case let .pressed(identity), let .dragging(identity):
            return identity
        }
    }
}

enum CanvasEditHandleInteractionEvent: Hashable, Sendable {
    case press(CanvasEditHandleIdentity?)
    case beginDragging(expectedIdentity: CanvasEditHandleIdentity)
    case end
    case cancel
}

struct CanvasEditHandleInteractionTransition: Hashable, Sendable {
    let previousPhase: CanvasEditHandleInteractionPhase
    let currentPhase: CanvasEditHandleInteractionPhase

    var didChangeState: Bool {
        previousPhase != currentPhase
    }

    var didChangeVisualState: Bool {
        previousPhase.activeIdentity != currentPhase.activeIdentity
    }
}

struct CanvasEditHandleInteractionState: Hashable, Sendable {
    private(set) var phase: CanvasEditHandleInteractionPhase = .inactive

    var activeIdentity: CanvasEditHandleIdentity? {
        phase.activeIdentity
    }

    func visualState(
        for identity: CanvasEditHandleIdentity
    ) -> CanvasEditHandleVisualState {
        activeIdentity == identity ? .active : .normal
    }

    @discardableResult
    mutating func apply(
        _ event: CanvasEditHandleInteractionEvent
    ) -> CanvasEditHandleInteractionTransition {
        let previousPhase = phase
        phase = nextPhase(for: event)
        return CanvasEditHandleInteractionTransition(
            previousPhase: previousPhase,
            currentPhase: phase
        )
    }

    private func nextPhase(
        for event: CanvasEditHandleInteractionEvent
    ) -> CanvasEditHandleInteractionPhase {
        switch event {
        case let .press(identity):
            guard let identity else {
                return .inactive
            }
            guard activeIdentity != identity else {
                return phase
            }
            return .pressed(identity)

        case let .beginDragging(expectedIdentity):
            switch phase {
            case let .pressed(identity) where identity == expectedIdentity:
                return .dragging(identity)
            case let .dragging(identity) where identity == expectedIdentity:
                return phase
            case .inactive, .pressed, .dragging:
                return phase
            }

        case .end, .cancel:
            return .inactive
        }
    }
}
