import Foundation

struct CanvasInteractionState: Equatable {
    private var storedSelectedItemIDs: [CanvasItemID]
    private var storedPrimarySelectedItemID: CanvasItemID?

    var selectedItemIDs: [CanvasItemID] {
        get {
            storedSelectedItemIDs
        }
        set {
            applyNormalizedSelection(
                selectedItemIDs: newValue,
                primarySelectedItemID: storedPrimarySelectedItemID
            )
        }
    }

    var primarySelectedItemID: CanvasItemID? {
        get {
            storedPrimarySelectedItemID
        }
        set {
            applyNormalizedSelection(
                selectedItemIDs: storedSelectedItemIDs,
                primarySelectedItemID: newValue
            )
        }
    }

    // Compatibility shim while the rest of the canvas stack migrates away from
    // single-selection assumptions.
    var selectedItemID: CanvasItemID? {
        get {
            primarySelectedItemID
        }
        set {
            applyNormalizedSelection(
                selectedItemIDs: newValue.map { [$0] } ?? [],
                primarySelectedItemID: newValue
            )
        }
    }

    var hasSelection: Bool {
        storedSelectedItemIDs.isEmpty == false
    }

    var selectionCount: Int {
        storedSelectedItemIDs.count
    }

    var singleSelectedItemID: CanvasItemID? {
        selectionCount == 1 ? storedPrimarySelectedItemID : nil
    }

    init(
        selectedItemIDs: [CanvasItemID] = [],
        primarySelectedItemID: CanvasItemID? = nil
    ) {
        let normalized = normalizeCanvasSelectionState(
            selectedItemIDs: selectedItemIDs,
            primarySelectedItemID: primarySelectedItemID
        )
        storedSelectedItemIDs = normalized.selectedItemIDs
        storedPrimarySelectedItemID = normalized.primarySelectedItemID
    }

    init(selectedItemID: CanvasItemID? = nil) {
        self.init(
            selectedItemIDs: selectedItemID.map { [$0] } ?? [],
            primarySelectedItemID: selectedItemID
        )
    }

    private mutating func applyNormalizedSelection(
        selectedItemIDs: [CanvasItemID],
        primarySelectedItemID: CanvasItemID?
    ) {
        let normalized = normalizeCanvasSelectionState(
            selectedItemIDs: selectedItemIDs,
            primarySelectedItemID: primarySelectedItemID
        )
        storedSelectedItemIDs = normalized.selectedItemIDs
        storedPrimarySelectedItemID = normalized.primarySelectedItemID
    }
}

struct CanvasNormalizedSelectionState<ItemID: Hashable> {
    let selectedItemIDs: [ItemID]
    let primarySelectedItemID: ItemID?
}

func normalizeCanvasSelectionState<ItemID: Hashable>(
    selectedItemIDs: [ItemID],
    primarySelectedItemID: ItemID?
) -> CanvasNormalizedSelectionState<ItemID> {
    var normalizedSelectedItemIDs: [ItemID] = []
    var seenSelectedItemIDs = Set<ItemID>()

    for selectedItemID in selectedItemIDs {
        guard seenSelectedItemIDs.insert(selectedItemID).inserted else {
            continue
        }
        normalizedSelectedItemIDs.append(selectedItemID)
    }

    var normalizedPrimarySelectedItemID = primarySelectedItemID
    if let primarySelectedItemID {
        if seenSelectedItemIDs.insert(primarySelectedItemID).inserted {
            normalizedSelectedItemIDs.append(primarySelectedItemID)
        }
    } else if normalizedSelectedItemIDs.isEmpty == false {
        normalizedPrimarySelectedItemID = normalizedSelectedItemIDs.last
    }

    if normalizedSelectedItemIDs.isEmpty {
        normalizedPrimarySelectedItemID = nil
    }

    return CanvasNormalizedSelectionState(
        selectedItemIDs: normalizedSelectedItemIDs,
        primarySelectedItemID: normalizedPrimarySelectedItemID
    )
}
