import Foundation

// Shared routing splits one raw input fact into an indicator event and an
// optional downstream interaction intent.
struct CanvasInputRoutingResult: Equatable, Sendable {
    let indicatorEvent: CanvasInputIndicatorEvent?
    let interactionIntent: CanvasInteractionIntent?

    init(
        indicatorEvent: CanvasInputIndicatorEvent? = nil,
        interactionIntent: CanvasInteractionIntent? = nil
    ) {
        self.indicatorEvent = indicatorEvent
        self.interactionIntent = interactionIntent
    }

    var isEmpty: Bool {
        indicatorEvent == nil && interactionIntent == nil
    }

    var debugSummary: String {
        let indicatorDebugName = indicatorEvent?.debugName ?? "nil"
        let interactionDebugName = interactionIntent?.debugName ?? "nil"
        return "indicator=\(indicatorDebugName) interaction=\(interactionDebugName)"
    }
}
