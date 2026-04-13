import CoreGraphics
import Foundation

struct CanvasInputIndicatorQueueConfiguration: Equatable, Sendable {
    var maximumVisibleItems: Int
    var itemLifetime: TimeInterval
    var fadeOutDuration: TimeInterval
    var refreshInterval: TimeInterval
    var newestOpacity: CGFloat
    var stackOpacityStep: CGFloat
    var minimumOpacity: CGFloat

    init(
        maximumVisibleItems: Int = 4,
        itemLifetime: TimeInterval = 2.4,
        fadeOutDuration: TimeInterval = 0.32,
        refreshInterval: TimeInterval = 1 / 12,
        newestOpacity: CGFloat = 1,
        stackOpacityStep: CGFloat = 0.18,
        minimumOpacity: CGFloat = 0.38
    ) {
        self.maximumVisibleItems = max(maximumVisibleItems, 1)
        self.itemLifetime = max(itemLifetime, 0.1)
        self.fadeOutDuration = max(
            min(fadeOutDuration, self.itemLifetime),
            0.05
        )
        self.refreshInterval = max(refreshInterval, 1 / 30)
        self.newestOpacity = min(max(newestOpacity, 0), 1)
        self.stackOpacityStep = max(stackOpacityStep, 0)
        self.minimumOpacity = min(max(minimumOpacity, 0), 1)
    }
}

struct CanvasInputIndicatorQueueSnapshotItem: Sendable {
    let id: UUID
    let event: CanvasInputIndicatorEvent
    let opacity: CGFloat
}

struct CanvasInputIndicatorQueueSnapshot: Sendable {
    let items: [CanvasInputIndicatorQueueSnapshotItem]

    init(items: [CanvasInputIndicatorQueueSnapshotItem] = []) {
        self.items = items
    }

    var isEmpty: Bool {
        items.isEmpty
    }
}

final class CanvasInputIndicatorQueue {
    private struct Entry {
        let id: UUID
        let event: CanvasInputIndicatorEvent
        let insertedAt: Date
    }

    let configuration: CanvasInputIndicatorQueueConfiguration
    private var entries: [Entry] = []

    init(
        configuration: CanvasInputIndicatorQueueConfiguration = .init()
    ) {
        self.configuration = configuration
    }

    var refreshInterval: TimeInterval {
        configuration.refreshInterval
    }

    var hasEntries: Bool {
        entries.isEmpty == false
    }

    @discardableResult
    func enqueue(
        _ event: CanvasInputIndicatorEvent,
        now: Date = Date()
    ) -> CanvasInputIndicatorQueueSnapshot {
        purgeExpiredEntries(asOf: now)
        entries.append(
            Entry(
                id: UUID(),
                event: event,
                insertedAt: now
            )
        )
        trimToVisibleCount()
        return snapshot(asOf: now)
    }

    @discardableResult
    func snapshot(
        asOf now: Date = Date()
    ) -> CanvasInputIndicatorQueueSnapshot {
        purgeExpiredEntries(asOf: now)
        let visibleEntries = Array(
            entries.suffix(configuration.maximumVisibleItems)
        )
        let items = visibleEntries.enumerated().map { index, entry in
            CanvasInputIndicatorQueueSnapshotItem(
                id: entry.id,
                event: entry.event,
                opacity: resolvedOpacity(
                    for: entry,
                    visibleIndex: index,
                    visibleCount: visibleEntries.count,
                    now: now
                )
            )
        }
        return CanvasInputIndicatorQueueSnapshot(items: items)
    }

    private func trimToVisibleCount() {
        guard entries.count > configuration.maximumVisibleItems else {
            return
        }

        entries.removeFirst(entries.count - configuration.maximumVisibleItems)
    }

    private func purgeExpiredEntries(asOf now: Date) {
        entries.removeAll { entry in
            age(of: entry, at: now) >= configuration.itemLifetime
        }
    }

    private func age(
        of entry: Entry,
        at now: Date
    ) -> TimeInterval {
        max(0, now.timeIntervalSince(entry.insertedAt))
    }

    private func resolvedOpacity(
        for entry: Entry,
        visibleIndex: Int,
        visibleCount: Int,
        now: Date
    ) -> CGFloat {
        let rankOpacity = resolvedRankOpacity(
            visibleIndex: visibleIndex,
            visibleCount: visibleCount
        )
        let lifetimeOpacity = resolvedLifetimeOpacity(
            age: age(of: entry, at: now)
        )
        return min(max(rankOpacity * lifetimeOpacity, 0), 1)
    }

    private func resolvedRankOpacity(
        visibleIndex: Int,
        visibleCount: Int
    ) -> CGFloat {
        let rankFromNewest = max(visibleCount - visibleIndex - 1, 0)
        return max(
            configuration.minimumOpacity,
            configuration.newestOpacity
                - CGFloat(rankFromNewest) * configuration.stackOpacityStep
        )
    }

    private func resolvedLifetimeOpacity(
        age: TimeInterval
    ) -> CGFloat {
        let fadeStart = max(
            configuration.itemLifetime - configuration.fadeOutDuration,
            0
        )
        guard age > fadeStart else {
            return 1
        }

        let fadeProgress = CGFloat(
            (age - fadeStart) / configuration.fadeOutDuration
        )
        return max(0, 1 - fadeProgress)
    }
}
