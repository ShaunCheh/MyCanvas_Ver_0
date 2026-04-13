// Phase 0 boundary anchor for the three-lane input architecture.
//
// Raw Input Lane:
// Physical or system input facts observed by platform capture. These types must
// stay upstream of CanvasTransferRequest, CanvasImportRequest, and
// CanvasCommand.importMedia(_).
//
// Interaction Lane:
// Shared business intents and policy decisions that stay downstream of raw
// input routing. Existing CanvasInteractionIntent and CanvasInteractionPolicy
// remain the source of truth for this lane.
//
// Indicator Lane:
// Presentation-only events consumed by the future input indicator UI. This lane
// must not mutate CanvasCommand or replace business intent routing.
//
// Phase 0 non-goals:
// - No system-wide global input capture.
// - No plain text character stream or IME composition modeling.
// - No NSEvent or UIEvent leakage into shared input types.
// - No platform delivery-source details inside shared domain contracts.
enum CanvasInputBoundaryAnchor {}
