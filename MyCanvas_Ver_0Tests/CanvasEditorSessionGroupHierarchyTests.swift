import CoreGraphics
import XCTest
@testable import MyCanvas_Ver_0

@MainActor
final class CanvasEditorSessionGroupHierarchyTests: XCTestCase {
    func testDirectAndDescendantQueriesUseNormalizedGroupHierarchy() {
        let rootID = CanvasItemGroupID()
        let childID = CanvasItemGroupID()
        let grandchildID = CanvasItemGroupID()
        let directItemID = CanvasItemID()
        let childItemID = CanvasItemID()
        let grandchildItemID = CanvasItemID()
        let session = makeGroupHierarchyTestSession()
        session.groups = [
            CanvasItemGroup(
                id: rootID,
                title: "root",
                itemIDs: [directItemID],
                childGroupIDs: [childID]
            ),
            CanvasItemGroup(
                id: childID,
                title: "child",
                itemIDs: [childItemID],
                childGroupIDs: [grandchildID]
            ),
            CanvasItemGroup(
                id: grandchildID,
                title: "grandchild",
                itemIDs: [grandchildItemID]
            )
        ]

        XCTAssertEqual(session.directItemIDs(withID: rootID), [directItemID])
        XCTAssertEqual(session.directChildGroupIDs(withID: rootID), [childID])
        XCTAssertEqual(session.parentGroupID(for: childID), rootID)
        XCTAssertEqual(session.parentGroupID(for: grandchildID), childID)
        XCTAssertEqual(session.descendantGroupIDs(withID: rootID), [childID, grandchildID])
        XCTAssertEqual(
            session.descendantItemIDs(withID: rootID),
            [childItemID, grandchildItemID]
        )
    }

    func testSetChildGroupsTransfersSingleParentOwnership() {
        let firstParentID = CanvasItemGroupID()
        let secondParentID = CanvasItemGroupID()
        let childID = CanvasItemGroupID()
        let session = makeGroupHierarchyTestSession()
        session.groups = [
            CanvasItemGroup(
                id: firstParentID,
                title: "first parent",
                itemIDs: [],
                childGroupIDs: [childID]
            ),
            CanvasItemGroup(id: secondParentID, title: "second parent", itemIDs: []),
            CanvasItemGroup(id: childID, title: "child", itemIDs: [])
        ]

        XCTAssertTrue(
            session.setChildGroups(
                forGroupID: secondParentID,
                to: [childID, childID]
            )
        )

        XCTAssertEqual(session.directChildGroupIDs(withID: firstParentID), [])
        XCTAssertEqual(session.directChildGroupIDs(withID: secondParentID), [childID])
        XCTAssertEqual(session.parentGroupID(for: childID), secondParentID)
    }

    func testSetChildGroupsRejectsCycleCandidate() {
        let rootID = CanvasItemGroupID()
        let childID = CanvasItemGroupID()
        let grandchildID = CanvasItemGroupID()
        let session = makeGroupHierarchyTestSession()
        session.groups = [
            CanvasItemGroup(
                id: rootID,
                title: "root",
                itemIDs: [],
                childGroupIDs: [childID]
            ),
            CanvasItemGroup(
                id: childID,
                title: "child",
                itemIDs: [],
                childGroupIDs: [grandchildID]
            ),
            CanvasItemGroup(id: grandchildID, title: "grandchild", itemIDs: [])
        ]

        XCTAssertFalse(
            session.setChildGroups(
                forGroupID: grandchildID,
                to: [rootID]
            )
        )

        XCTAssertEqual(session.directChildGroupIDs(withID: grandchildID), [])
        XCTAssertNil(session.parentGroupID(for: rootID))
        XCTAssertEqual(session.descendantGroupIDs(withID: rootID), [childID, grandchildID])
    }

    func testNormalizeGroupHierarchyRemovesInvalidSelfDuplicateAndSecondParentReferences() {
        let firstParentID = CanvasItemGroupID()
        let secondParentID = CanvasItemGroupID()
        let childID = CanvasItemGroupID()
        let missingID = CanvasItemGroupID()
        let session = makeGroupHierarchyTestSession()
        session.groups = [
            CanvasItemGroup(
                id: firstParentID,
                title: "first parent",
                itemIDs: [],
                childGroupIDs: [
                    firstParentID,
                    missingID,
                    childID,
                    childID
                ]
            ),
            CanvasItemGroup(
                id: secondParentID,
                title: "second parent",
                itemIDs: [],
                childGroupIDs: [childID]
            ),
            CanvasItemGroup(id: childID, title: "child", itemIDs: [])
        ]

        XCTAssertTrue(session.normalizeGroupHierarchy())

        XCTAssertEqual(session.directChildGroupIDs(withID: firstParentID), [childID])
        XCTAssertEqual(session.directChildGroupIDs(withID: secondParentID), [])
        XCTAssertEqual(session.parentGroupID(for: childID), firstParentID)
    }

    func testReconcileFrameGroupMembershipsAddsContainedGroupsAsDirectChildren() {
        let childAID = CanvasItemGroupID()
        let childBID = CanvasItemGroupID()
        let parentID = CanvasItemGroupID()
        let session = makeGroupHierarchyTestSession()
        session.groups = [
            CanvasItemGroup(
                id: childAID,
                title: "A",
                itemIDs: [],
                frame: CGRect(x: 20, y: 20, width: 80, height: 60)
            ),
            CanvasItemGroup(
                id: childBID,
                title: "B",
                itemIDs: [],
                frame: CGRect(x: 140, y: 40, width: 80, height: 60)
            ),
            CanvasItemGroup(
                id: parentID,
                title: "C",
                itemIDs: [],
                frame: CGRect(x: 0, y: 0, width: 260, height: 140)
            )
        ]

        XCTAssertTrue(session.reconcileFrameGroupMemberships())

        XCTAssertEqual(session.directChildGroupIDs(withID: parentID), [childAID, childBID])
        XCTAssertEqual(session.parentGroupID(for: childAID), parentID)
        XCTAssertEqual(session.parentGroupID(for: childBID), parentID)
    }

    func testReconcileFrameGroupMembershipsDoesNotDuplicateChildItemsInParent() {
        let childAID = CanvasItemGroupID()
        let childBID = CanvasItemGroupID()
        let parentID = CanvasItemGroupID()
        let childAItem = makeGroupHierarchyTextItem(
            text: "inside A",
            center: CGPoint(x: 60, y: 50)
        )
        let childBItem = makeGroupHierarchyTextItem(
            text: "inside B",
            center: CGPoint(x: 180, y: 70)
        )
        let parentDirectItem = makeGroupHierarchyTextItem(
            text: "direct C",
            center: CGPoint(x: 240, y: 80)
        )
        let session = makeGroupHierarchyTestSession()
        session.scene.append(childAItem)
        session.scene.append(childBItem)
        session.scene.append(parentDirectItem)
        session.groups = [
            CanvasItemGroup(
                id: childAID,
                title: "A",
                itemIDs: [],
                frame: CGRect(x: 20, y: 20, width: 80, height: 60)
            ),
            CanvasItemGroup(
                id: childBID,
                title: "B",
                itemIDs: [],
                frame: CGRect(x: 140, y: 40, width: 80, height: 60)
            ),
            CanvasItemGroup(
                id: parentID,
                title: "C",
                itemIDs: [],
                frame: CGRect(x: 0, y: 0, width: 280, height: 140)
            )
        ]

        XCTAssertTrue(session.reconcileFrameGroupMemberships())

        XCTAssertEqual(
            session.directItemIDs(withID: childAID),
            [childAItem.id],
            "child A direct itemIDs"
        )
        XCTAssertEqual(
            session.directItemIDs(withID: childBID),
            [childBItem.id],
            "child B direct itemIDs"
        )
        XCTAssertEqual(
            session.directItemIDs(withID: parentID),
            [parentDirectItem.id],
            "parent C direct itemIDs"
        )
        XCTAssertEqual(
            session.descendantItemIDs(withID: parentID),
            [childAItem.id, childBItem.id],
            "parent C descendant itemIDs"
        )
    }

    func testReconcileFrameGroupMembershipsRemovesChildGroupMovedOutsideParent() {
        let childID = CanvasItemGroupID()
        let parentID = CanvasItemGroupID()
        let session = makeGroupHierarchyTestSession()
        session.groups = [
            CanvasItemGroup(
                id: childID,
                title: "A",
                itemIDs: [],
                frame: CGRect(x: 360, y: 20, width: 80, height: 60)
            ),
            CanvasItemGroup(
                id: parentID,
                title: "C",
                itemIDs: [],
                childGroupIDs: [childID],
                frame: CGRect(x: 0, y: 0, width: 260, height: 140)
            )
        ]

        XCTAssertTrue(session.reconcileFrameGroupMemberships())

        XCTAssertEqual(session.directChildGroupIDs(withID: parentID), [])
        XCTAssertNil(session.parentGroupID(for: childID))
    }
}

private enum CanvasEditorSessionGroupHierarchyTestRetainer {
    static var sessions: [CanvasEditorSession] = []
}

private func makeGroupHierarchyTestSession() -> CanvasEditorSession {
    let session = CanvasEditorSession(
        saveQueueLabel: "CanvasEditorSessionGroupHierarchyTests",
        logPrefix: "[CanvasEditorSessionGroupHierarchyTests]"
    )
    CanvasEditorSessionGroupHierarchyTestRetainer.sessions.append(session)
    return session
}

private func makeGroupHierarchyTextItem(
    text: String,
    center: CGPoint
) -> CanvasTextItem {
    CanvasTextItem(
        text: text,
        center: center,
        size: CGSize(width: 24, height: 16)
    )
}
