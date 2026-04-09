import CoreGraphics
import Foundation

enum BoardListCanvasTransitionDirection: Hashable, Sendable {
    case opening
    case closing
}

enum BoardListCanvasTransitionCarrierKind: Hashable, Sendable {
    case snapshotShell
    case liveCanvas
}

enum BoardListCanvasTransitionRollout {
    static let liveCanvasRequestOverrideEnabled = true

    static var iOSRequestPreferredCarrierKind: BoardListCanvasTransitionCarrierKind {
        liveCanvasRequestOverrideEnabled ? .liveCanvas : .snapshotShell
    }
}

enum BoardListCanvasOpenSourceKind: Hashable, Sendable {
    case existingBoardCard
    case newBoardPlaceholder
}

struct BoardListCanvasOpenSource: Hashable, Sendable {
    var kind: BoardListCanvasOpenSourceKind
    var entryID: BoardListEntryID
    var boardID: UUID?
    var geometry: BoardListCanvasTransitionSourceGeometry
}

struct BoardListCanvasOpenRequest: Hashable, Sendable {
    var launchContext: CanvasLaunchContext
    var source: BoardListCanvasOpenSource
    var preferredCarrierKind: BoardListCanvasTransitionCarrierKind
    var debugTrace: BoardListCanvasTransitionDebugTrace?

    static func existingBoard(
        boardID: UUID,
        geometry: BoardListCanvasTransitionSourceGeometry = .init(),
        preferredCarrierKind: BoardListCanvasTransitionCarrierKind = .snapshotShell,
        debugTrace: BoardListCanvasTransitionDebugTrace? = nil
    ) -> Self {
        BoardListCanvasOpenRequest(
            launchContext: .existing(boardID: boardID),
            source: BoardListCanvasOpenSource(
                kind: .existingBoardCard,
                entryID: .board(boardID),
                boardID: boardID,
                geometry: geometry
            ),
            preferredCarrierKind: preferredCarrierKind,
            debugTrace: debugTrace
        )
    }

    static func newBoardPlaceholder(
        geometry: BoardListCanvasTransitionSourceGeometry = .init(),
        preferredCarrierKind: BoardListCanvasTransitionCarrierKind = .snapshotShell,
        debugTrace: BoardListCanvasTransitionDebugTrace? = nil
    ) -> Self {
        BoardListCanvasOpenRequest(
            launchContext: .newBoard,
            source: BoardListCanvasOpenSource(
                kind: .newBoardPlaceholder,
                entryID: .newBoard,
                boardID: nil,
                geometry: geometry
            ),
            preferredCarrierKind: preferredCarrierKind,
            debugTrace: debugTrace
        )
    }

    var transitionContext: BoardListCanvasTransitionContext {
        BoardListCanvasTransitionContext(
            direction: .opening,
            launchContext: launchContext,
            sourceEntryID: source.entryID,
            targetBoardID: source.boardID ?? launchContext.existingBoardID,
            sourceGeometry: source.geometry,
            targetGeometry: .init(),
            preferredCarrierKind: preferredCarrierKind
        )
    }
}

enum BoardListCanvasReturnSourceKind: Hashable, Sendable {
    case backButton
}

struct BoardListCanvasReturnRequest: Hashable, Sendable {
    var boardID: UUID?
    var launchContext: CanvasLaunchContext?
    var sourceKind: BoardListCanvasReturnSourceKind
    var targetGeometry: BoardListCanvasTransitionTargetGeometry
    var preferredCarrierKind: BoardListCanvasTransitionCarrierKind
    var requiresBoardPersistence: Bool
    var debugTrace: BoardListCanvasTransitionDebugTrace?

    static func backButton(
        boardID: UUID?,
        launchContext: CanvasLaunchContext?,
        targetGeometry: BoardListCanvasTransitionTargetGeometry = .init(),
        preferredCarrierKind: BoardListCanvasTransitionCarrierKind = .snapshotShell,
        debugTrace: BoardListCanvasTransitionDebugTrace? = nil
    ) -> Self {
        BoardListCanvasReturnRequest(
            boardID: boardID,
            launchContext: launchContext,
            sourceKind: .backButton,
            targetGeometry: targetGeometry,
            preferredCarrierKind: preferredCarrierKind,
            requiresBoardPersistence: launchContext?.requiresBoardPersistenceOnReturn ?? false,
            debugTrace: debugTrace
        )
    }

    var transitionContext: BoardListCanvasTransitionContext {
        BoardListCanvasTransitionContext(
            direction: .closing,
            launchContext: launchContext,
            sourceEntryID: nil,
            targetBoardID: boardID ?? launchContext?.existingBoardID,
            sourceGeometry: .init(),
            targetGeometry: targetGeometry,
            preferredCarrierKind: preferredCarrierKind
        )
    }
}

struct BoardListCanvasTransitionContext: Hashable, Sendable {
    var direction: BoardListCanvasTransitionDirection
    var launchContext: CanvasLaunchContext?
    var sourceEntryID: BoardListEntryID?
    var targetBoardID: UUID?
    var sourceGeometry: BoardListCanvasTransitionSourceGeometry
    var targetGeometry: BoardListCanvasTransitionTargetGeometry
    var preferredCarrierKind: BoardListCanvasTransitionCarrierKind
}
