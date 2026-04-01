import XCTest
@testable import MyCanvas_Ver_0

final class CanvasVideoEditorPreviewStateTests: XCTestCase {
    func testPreviewStateClampsTimeAndTracksPosterSelection() {
        var state = CanvasVideoEditorPreviewState(
            currentTimeSeconds: 99,
            posterTimeSeconds: 5,
            durationSeconds: 20
        )

        XCTAssertEqual(
            state.snapshot.currentTimeSeconds,
            CanvasVideoTimelineViewport.clampedTimeSeconds(
                99,
                durationSeconds: 20
            ),
            accuracy: 0.0001
        )
        XCTAssertFalse(state.snapshot.isCurrentPosterSelected)

        state.setCurrentTimeSeconds(5.02)
        XCTAssertTrue(state.snapshot.isCurrentPosterSelected)

        state.setCurrentTimeSeconds(5.2)
        XCTAssertFalse(state.snapshot.isCurrentPosterSelected)
    }

    func testPreviewStateBeginsAndEndsSingleInteractionWithPlaybackResume() {
        var state = CanvasVideoEditorPreviewState(
            currentTimeSeconds: 2,
            posterTimeSeconds: 1,
            durationSeconds: 10
        )

        XCTAssertEqual(
            state.beginInteraction(.slider, wasPlaying: true),
            .pause
        )
        XCTAssertFalse(state.snapshot.shouldAcceptPlayerTimeUpdates)

        XCTAssertEqual(
            state.endInteraction(.slider),
            .resume
        )
        XCTAssertTrue(state.snapshot.shouldAcceptPlayerTimeUpdates)
    }

    func testPreviewStateDoesNotResumePlaybackIfInteractionStartedWhilePaused() {
        var state = CanvasVideoEditorPreviewState(
            currentTimeSeconds: 2,
            posterTimeSeconds: 1,
            durationSeconds: 10
        )

        XCTAssertEqual(
            state.beginInteraction(.slider, wasPlaying: false),
            .pause
        )
        XCTAssertEqual(
            state.endInteraction(.slider),
            .none
        )
    }

    func testPreviewStateKeepsPlaybackSuspendedUntilAllInteractionSourcesEnd() {
        var state = CanvasVideoEditorPreviewState(
            currentTimeSeconds: 3,
            posterTimeSeconds: 1,
            durationSeconds: 10
        )

        XCTAssertEqual(
            state.beginInteraction(.slider, wasPlaying: true),
            .pause
        )
        XCTAssertEqual(
            state.beginInteraction(.timeline, wasPlaying: true),
            .none
        )
        XCTAssertFalse(state.snapshot.shouldAcceptPlayerTimeUpdates)

        XCTAssertEqual(
            state.endInteraction(.slider),
            .none
        )
        XCTAssertFalse(state.snapshot.shouldAcceptPlayerTimeUpdates)

        XCTAssertEqual(
            state.endInteraction(.timeline),
            .resume
        )
        XCTAssertTrue(state.snapshot.shouldAcceptPlayerTimeUpdates)
    }
}
