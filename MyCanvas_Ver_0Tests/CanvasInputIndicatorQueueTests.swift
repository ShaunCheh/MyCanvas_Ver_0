import CoreGraphics
import XCTest
@testable import MyCanvas_Ver_0

@MainActor
final class CanvasInputIndicatorQueueTests: XCTestCase {
    func testEnqueueKeepsNewestVisibleItems() {
        let queue = CanvasInputIndicatorQueue(
            configuration: .init(
                maximumVisibleItems: 2,
                itemLifetime: 10,
                fadeOutDuration: 1,
                refreshInterval: 0.1
            )
        )
        let start = Date(timeIntervalSince1970: 1_000)

        _ = queue.enqueue(.action(.tap), now: start)
        _ = queue.enqueue(.action(.scroll), now: start.addingTimeInterval(0.1))
        let snapshot = queue.enqueue(
            .action(.rightClick),
            now: start.addingTimeInterval(0.2)
        )

        XCTAssertEqual(snapshot.items.map(\.event), [.action(.scroll), .action(.rightClick)])
    }

    func testSnapshotPurgesExpiredEntries() {
        let queue = CanvasInputIndicatorQueue(
            configuration: .init(
                maximumVisibleItems: 3,
                itemLifetime: 1,
                fadeOutDuration: 0.2,
                refreshInterval: 0.1
            )
        )
        let start = Date(timeIntervalSince1970: 2_000)

        _ = queue.enqueue(.action(.tap), now: start)
        let snapshot = queue.snapshot(asOf: start.addingTimeInterval(1.1))

        XCTAssertTrue(snapshot.isEmpty)
        XCTAssertFalse(queue.hasEntries)
    }

    func testSnapshotUsesStackOpacityForOlderEntries() {
        let queue = CanvasInputIndicatorQueue(
            configuration: .init(
                maximumVisibleItems: 3,
                itemLifetime: 10,
                fadeOutDuration: 1,
                refreshInterval: 0.1,
                newestOpacity: 1,
                stackOpacityStep: 0.2,
                minimumOpacity: 0.1
            )
        )
        let start = Date(timeIntervalSince1970: 3_000)

        _ = queue.enqueue(.action(.tap), now: start)
        let snapshot = queue.enqueue(
            .action(.scroll),
            now: start.addingTimeInterval(0.1)
        )

        XCTAssertEqual(snapshot.items.count, 2)
        XCTAssertEqual(snapshot.items[0].opacity, CGFloat(0.8), accuracy: 0.0001)
        XCTAssertEqual(snapshot.items[1].opacity, CGFloat(1), accuracy: 0.0001)
    }

    func testSnapshotAppliesFadeOutNearLifetimeEnd() {
        let queue = CanvasInputIndicatorQueue(
            configuration: .init(
                maximumVisibleItems: 1,
                itemLifetime: 4,
                fadeOutDuration: 1,
                refreshInterval: 0.1,
                newestOpacity: 1,
                stackOpacityStep: 0.2,
                minimumOpacity: 0.1
            )
        )
        let start = Date(timeIntervalSince1970: 4_000)

        _ = queue.enqueue(.action(.tap), now: start)
        let snapshot = queue.snapshot(asOf: start.addingTimeInterval(3.5))

        XCTAssertEqual(snapshot.items.count, 1)
        XCTAssertEqual(snapshot.items[0].opacity, CGFloat(0.5), accuracy: 0.0001)
    }
}
