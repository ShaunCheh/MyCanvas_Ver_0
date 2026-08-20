import XCTest
@testable import MyCanvas_Ver_0

final class CanvasRefreshFrameCoalescerTests: XCTestCase {
    func testMultipleRequestsScheduleOnceAndKeepLatestReason() {
        var coalescer = CanvasRefreshFrameCoalescer()

        XCTAssertTrue(
            coalescer.request(reason: "first", generation: 4)
        )
        XCTAssertFalse(
            coalescer.request(reason: "latest", generation: 4)
        )
        XCTAssertEqual(
            coalescer.takePending(currentGeneration: 4),
            CanvasRefreshFrameCoalescer.Pending(
                reason: "latest",
                generation: 4
            )
        )
        XCTAssertNil(coalescer.pending)
    }

    func testGenerationMismatchDropsStalePendingRefresh() {
        var coalescer = CanvasRefreshFrameCoalescer()
        _ = coalescer.request(reason: "old board", generation: 7)

        XCTAssertNil(coalescer.takePending(currentGeneration: 8))
        XCTAssertNil(coalescer.pending)
    }

    func testCancelClearsPendingAndAllowsNewSchedule() {
        var coalescer = CanvasRefreshFrameCoalescer()
        _ = coalescer.request(reason: "pending", generation: 1)

        coalescer.cancel()

        XCTAssertNil(coalescer.pending)
        XCTAssertTrue(
            coalescer.request(reason: "replacement", generation: 1)
        )
    }
}
