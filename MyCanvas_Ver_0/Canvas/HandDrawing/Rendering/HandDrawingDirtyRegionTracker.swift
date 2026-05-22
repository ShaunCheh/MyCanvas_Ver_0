import CoreGraphics
import Foundation

struct HandDrawingDirtyRegionTracker {
    private(set) var dirtyRegion: CGRect?

    mutating func markDirty(
        _ rect: CGRect?,
        padding: CGFloat = 0
    ) {
        guard let rect, rect.isNull == false, rect.isEmpty == false else {
            return
        }
        let resolvedPadding = max(padding, 0)
        let expandedRect = rect
            .insetBy(dx: -resolvedPadding, dy: -resolvedPadding)
            .standardized
            .integral
        dirtyRegion = dirtyRegion?.union(expandedRect) ?? expandedRect
    }

    mutating func consumeDirtyRegion() -> CGRect? {
        defer {
            dirtyRegion = nil
        }
        return dirtyRegion
    }

    mutating func reset() {
        dirtyRegion = nil
    }
}
