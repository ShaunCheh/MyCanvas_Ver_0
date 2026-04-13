import Foundation

// Phase 0 reserves the upstream raw-input lane for physical or system input
// facts captured on platform edges. Concrete cases arrive in later phases.
enum CanvasRawInputSource: Equatable, Sendable {}

// Shared key-chord naming stays upstream of command or transfer lowering.
struct CanvasKeyChord: Equatable, Sendable {}

// Raw input facts are not business intents and must not be added to
// CanvasInteractionIntent.
enum CanvasRawInputIntent: Equatable, Sendable {}
