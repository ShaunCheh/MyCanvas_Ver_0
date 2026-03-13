import Foundation

struct CanvasInteractionState {
    var selectedItemID: CanvasImageItemID?

    init(selectedItemID: CanvasImageItemID? = nil) {
        self.selectedItemID = selectedItemID
    }
}
