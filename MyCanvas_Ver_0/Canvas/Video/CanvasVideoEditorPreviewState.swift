import Foundation

enum CanvasVideoEditorPreviewInteractionSource: Hashable {
    case slider
    case timeline
}

enum CanvasVideoEditorPlaybackIntent: Equatable {
    case none
    case pause
    case resume
}

struct CanvasVideoEditorPreviewSnapshot: Equatable {
    static let posterSelectionToleranceSeconds = max(
        1.0 / 30.0,
        CanvasVideoTimelineMath.frameBoundaryEpsilonSeconds * 2
    )

    let currentTimeSeconds: Double
    let posterTimeSeconds: Double
    let durationSeconds: Double
    let activeInteractionSources: Set<CanvasVideoEditorPreviewInteractionSource>

    var isInteracting: Bool {
        activeInteractionSources.isEmpty == false
    }

    var shouldAcceptPlayerTimeUpdates: Bool {
        isInteracting == false
    }

    var shouldAutoFollowPlayhead: Bool {
        isInteracting == false
    }

    var isCurrentPosterSelected: Bool {
        abs(currentTimeSeconds - posterTimeSeconds)
            <= Self.posterSelectionToleranceSeconds
    }

    func isInteracting(
        with source: CanvasVideoEditorPreviewInteractionSource
    ) -> Bool {
        activeInteractionSources.contains(source)
    }
}

struct CanvasVideoEditorPreviewState {
    private(set) var currentTimeSeconds: Double
    private(set) var posterTimeSeconds: Double
    private(set) var durationSeconds: Double
    private(set) var activeInteractionSources: Set<
        CanvasVideoEditorPreviewInteractionSource
    > = []
    private(set) var shouldResumePlaybackAfterInteraction = false

    init(
        currentTimeSeconds: Double,
        posterTimeSeconds: Double,
        durationSeconds: Double
    ) {
        let sanitizedDurationSeconds = CanvasVideoTimelineMath
            .sanitizedDurationSeconds(durationSeconds)
        self.durationSeconds = sanitizedDurationSeconds
        self.posterTimeSeconds = CanvasVideoTimelineMath.clampedTimeSeconds(
            posterTimeSeconds,
            durationSeconds: sanitizedDurationSeconds
        )
        self.currentTimeSeconds = CanvasVideoTimelineMath.clampedTimeSeconds(
            currentTimeSeconds,
            durationSeconds: sanitizedDurationSeconds
        )
    }

    var snapshot: CanvasVideoEditorPreviewSnapshot {
        CanvasVideoEditorPreviewSnapshot(
            currentTimeSeconds: currentTimeSeconds,
            posterTimeSeconds: posterTimeSeconds,
            durationSeconds: durationSeconds,
            activeInteractionSources: activeInteractionSources
        )
    }

    mutating func setCurrentTimeSeconds(_ timeSeconds: Double) {
        currentTimeSeconds = CanvasVideoTimelineMath.clampedTimeSeconds(
            timeSeconds,
            durationSeconds: durationSeconds
        )
    }

    mutating func setPosterTimeSeconds(_ posterTimeSeconds: Double) {
        self.posterTimeSeconds = CanvasVideoTimelineMath.clampedTimeSeconds(
            posterTimeSeconds,
            durationSeconds: durationSeconds
        )
    }

    mutating func beginInteraction(
        _ source: CanvasVideoEditorPreviewInteractionSource,
        wasPlaying: Bool
    ) -> CanvasVideoEditorPlaybackIntent {
        let insertionResult = activeInteractionSources.insert(source)
        guard insertionResult.inserted else {
            return .none
        }
        guard activeInteractionSources.count == 1 else {
            return .none
        }

        shouldResumePlaybackAfterInteraction = wasPlaying
        return .pause
    }

    mutating func endInteraction(
        _ source: CanvasVideoEditorPreviewInteractionSource
    ) -> CanvasVideoEditorPlaybackIntent {
        guard activeInteractionSources.remove(source) != nil else {
            return .none
        }
        guard activeInteractionSources.isEmpty else {
            return .none
        }

        defer {
            shouldResumePlaybackAfterInteraction = false
        }
        return shouldResumePlaybackAfterInteraction ? .resume : .none
    }
}
