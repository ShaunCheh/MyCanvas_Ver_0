import Foundation

struct CanvasEditHandleSelectionIdentity: Hashable, Sendable {
    let primaryItemID: CanvasItemID
    let memberItemIDs: Set<CanvasItemID>

    init<MemberIDs: Sequence>(
        primaryItemID: CanvasItemID,
        memberItemIDs: MemberIDs
    ) where MemberIDs.Element == CanvasItemID {
        self.primaryItemID = primaryItemID
        var normalizedMemberItemIDs = Set(memberItemIDs)
        normalizedMemberItemIDs.insert(primaryItemID)
        self.memberItemIDs = normalizedMemberItemIDs
    }
}

enum CanvasEditHandleOwner: Hashable, Sendable {
    case item(CanvasItemID)
    case selection(CanvasEditHandleSelectionIdentity)
    case group(CanvasItemGroupID)
}

enum CanvasEditHandleKind: Hashable, Sendable {
    case selectionResize(CanvasSelectionHandleRole)
    case cropResize(CanvasCropHandleRole)
    case rotate
    case arrowEndpoint(CanvasArrowEndpointRole)
    case groupFrameResize(CanvasSelectionHandleRole)
}

struct CanvasEditHandleIdentity: Hashable, Sendable {
    let owner: CanvasEditHandleOwner
    let kind: CanvasEditHandleKind
}
