import CoreGraphics
import Foundation

struct HandDrawingDirtyRegionTracker {
    private(set) var dirtyRegion: CGRect?

    mutating func markDirty(_ rect: CGRect?) {
        guard let rect, rect.isNull == false, rect.isEmpty == false else {
            return
        }
        dirtyRegion = dirtyRegion?.union(rect) ?? rect
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
