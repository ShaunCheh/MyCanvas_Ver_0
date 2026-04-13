import Foundation

// Phase 0 reserves the shared handoff from raw input into indicator and
// interaction lanes. Concrete fields are intentionally deferred to phase 1.
struct CanvasInputRoutingResult: Equatable, Sendable {}
