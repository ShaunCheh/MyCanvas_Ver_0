import CoreGraphics
import Foundation

enum CanvasToolbarMeasurement {
    static func measuredContentSize(
        forMeasuredStackSize stackSize: CGSize
    ) -> CGSize {
        CanvasChromeLayoutGeometry.sanitizedSize(
            CGSize(
                width: stackSize.width + (CanvasToolbarChromeMetrics.horizontalInset * 2),
                height: stackSize.height + (CanvasToolbarChromeMetrics.verticalInset * 2)
            )
        )
    }
}
