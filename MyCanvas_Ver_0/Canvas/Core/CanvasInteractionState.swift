import Foundation

struct CanvasInteractionState {
    var selectedItemID: CanvasItemID?

    init(selectedItemID: CanvasItemID? = nil) {
        self.selectedItemID = selectedItemID
    }
}
