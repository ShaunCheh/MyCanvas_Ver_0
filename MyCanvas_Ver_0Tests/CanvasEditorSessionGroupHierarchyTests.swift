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

    func testUpdateGroupFrameAndSubtreeGeometriesMovesParentChildFramesAndSubtreeItems() throws {
        let fixture = makeGroupHierarchySubtreeMoveFixture()
        let session = fixture.session

        XCTAssertTrue(session.reconcileFrameGroupMemberships())

        let translation = CGPoint(x: 18, y: 26)
        let parentSnapshot = session.groupSubtreeGeometries(withID: fixture.parentID)

        XCTAssertTrue(
            session.updateGroupFrameAndSubtreeGeometries(
                withID: fixture.parentID,
                to: fixture.parentFrame.offsetBy(dx: translation.x, dy: translation.y),
                subtreeGeometries: translatedGroupHierarchySubtreeGeometries(
                    parentSnapshot,
                    by: translation
                ),
                reconcileMembership: false
            )
        )

        XCTAssertEqual(
            session.groupFrame(withID: fixture.parentID),
            fixture.parentFrame.offsetBy(dx: translation.x, dy: translation.y)
        )
        XCTAssertEqual(
            session.groupFrame(withID: fixture.childAID),
            fixture.childAFrame.offsetBy(dx: translation.x, dy: translation.y)
        )
        XCTAssertEqual(
            session.groupFrame(withID: fixture.childBID),
            fixture.childBFrame.offsetBy(dx: translation.x, dy: translation.y)
        )
        XCTAssertEqual(session.groupFrame(withID: fixture.siblingID), fixture.siblingFrame)
        XCTAssertEqual(
            try XCTUnwrap(session.scene.textItem(withID: fixture.childAItem.id)).center,
            fixture.childAItem.center.translated(by: translation)
        )
        XCTAssertEqual(
            try XCTUnwrap(session.scene.textItem(withID: fixture.childBItem.id)).center,
            fixture.childBItem.center.translated(by: translation)
        )
        XCTAssertEqual(
            try XCTUnwrap(session.scene.textItem(withID: fixture.parentDirectItem.id)).center,
            fixture.parentDirectItem.center.translated(by: translation)
        )
    }

    func testUpdateGroupFrameResizeKeepsChildFramesAndItemsInPlace() throws {
        let fixture = makeGroupHierarchySubtreeMoveFixture()
        let session = fixture.session

        XCTAssertTrue(session.reconcileFrameGroupMemberships())

        XCTAssertTrue(
            session.updateGroupFrame(
                withID: fixture.parentID,
                to: CGRect(x: -20, y: -10, width: 340, height: 190),
                reconcileMembership: false
            )
        )

        XCTAssertEqual(
            session.groupFrame(withID: fixture.parentID),
            CGRect(x: -20, y: -10, width: 340, height: 190)
        )
        XCTAssertEqual(session.groupFrame(withID: fixture.childAID), fixture.childAFrame)
        XCTAssertEqual(session.groupFrame(withID: fixture.childBID), fixture.childBFrame)
        XCTAssertEqual(
            try XCTUnwrap(session.scene.textItem(withID: fixture.childAItem.id)).center,
            fixture.childAItem.center
        )
        XCTAssertEqual(
            try XCTUnwrap(session.scene.textItem(withID: fixture.childBItem.id)).center,
            fixture.childBItem.center
        )
        XCTAssertEqual(
            try XCTUnwrap(session.scene.textItem(withID: fixture.parentDirectItem.id)).center,
            fixture.parentDirectItem.center
        )
    }

    func testUpdateGroupFrameAndSubtreeGeometriesMovesOnlySelectedChildSubtree() throws {
        let fixture = makeGroupHierarchySubtreeMoveFixture()
        let session = fixture.session

        XCTAssertTrue(session.reconcileFrameGroupMemberships())

        let translation = CGPoint(x: -12, y: 22)
        let childSnapshot = session.groupSubtreeGeometries(withID: fixture.childAID)

        XCTAssertTrue(
            session.updateGroupFrameAndSubtreeGeometries(
                withID: fixture.childAID,
                to: fixture.childAFrame.offsetBy(dx: translation.x, dy: translation.y),
                subtreeGeometries: translatedGroupHierarchySubtreeGeometries(
                    childSnapshot,
                    by: translation
                ),
                reconcileMembership: false
            )
        )

        XCTAssertEqual(session.groupFrame(withID: fixture.parentID), fixture.parentFrame)
        XCTAssertEqual(
            session.groupFrame(withID: fixture.childAID),
            fixture.childAFrame.offsetBy(dx: translation.x, dy: translation.y)
        )
        XCTAssertEqual(session.groupFrame(withID: fixture.childBID), fixture.childBFrame)
        XCTAssertEqual(
            try XCTUnwrap(session.scene.textItem(withID: fixture.childAItem.id)).center,
            fixture.childAItem.center.translated(by: translation)
        )
        XCTAssertEqual(
            try XCTUnwrap(session.scene.textItem(withID: fixture.childBItem.id)).center,
            fixture.childBItem.center
        )
        XCTAssertEqual(
            try XCTUnwrap(session.scene.textItem(withID: fixture.parentDirectItem.id)).center,
            fixture.parentDirectItem.center
        )
    }

    func testGroupHierarchyRowsPlaceParentBeforeChildrenWithDepth() {
        let parentID = CanvasItemGroupID()
        let childID = CanvasItemGroupID()
        let siblingID = CanvasItemGroupID()
        let child = CanvasItemGroup(id: childID, title: "A", itemIDs: [])
        let parent = CanvasItemGroup(
            id: parentID,
            title: "C",
            itemIDs: [],
            childGroupIDs: [childID]
        )
        let sibling = CanvasItemGroup(id: siblingID, title: "B", itemIDs: [])

        let rows = CanvasGroupHierarchy.rows(from: [child, parent, sibling])

        XCTAssertEqual(rows.map(\.group.id), [parentID, childID, siblingID])
        XCTAssertEqual(rows.map(\.depth), [0, 1, 0])
    }

    func testCanvasRendererOrdersParentGroupFramesBeforeChildFrames() {
        let parentID = CanvasItemGroupID()
        let childID = CanvasItemGroupID()
        let session = makeGroupHierarchyRenderOrderSession(
            parentID: parentID,
            childID: childID
        )
        let snapshot = session.makeCanvasSnapshot()

        XCTAssertEqual(snapshot.groups.map(\.id), [parentID, childID])
    }

    func testCanvasContextResolverHitsChildGroupFrameBeforeParentFrame() {
        let parentID = CanvasItemGroupID()
        let childID = CanvasItemGroupID()
        let session = makeGroupHierarchyRenderOrderSession(
            parentID: parentID,
            childID: childID
        )
        _ = session.makeCanvasSnapshot()

        let pressContext = session.resolvePointerTarget(
            at: session.camera.worldToViewport(CGPoint(x: 75, y: 75)),
            interactionMetrics: makeGroupHierarchyContextResolverMetrics()
        )

        guard case .groupFrameBody = pressContext.targetKind else {
            XCTFail("Expected child group frame body hit.")
            return
        }
        XCTAssertEqual(pressContext.targetGroupID, childID)
    }
}

private enum CanvasEditorSessionGroupHierarchyTestRetainer {
    static var sessions: [CanvasEditorSession] = []
}

private struct GroupHierarchySubtreeMoveFixture {
    let session: CanvasEditorSession
    let parentID: CanvasItemGroupID
    let childAID: CanvasItemGroupID
    let childBID: CanvasItemGroupID
    let siblingID: CanvasItemGroupID
    let parentFrame: CGRect
    let childAFrame: CGRect
    let childBFrame: CGRect
    let siblingFrame: CGRect
    let childAItem: CanvasTextItem
    let childBItem: CanvasTextItem
    let parentDirectItem: CanvasTextItem
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

private func makeGroupHierarchySubtreeMoveFixture() -> GroupHierarchySubtreeMoveFixture {
    let session = makeGroupHierarchyTestSession()
    let parentID = CanvasItemGroupID()
    let childAID = CanvasItemGroupID()
    let childBID = CanvasItemGroupID()
    let siblingID = CanvasItemGroupID()
    let parentFrame = CGRect(x: 0, y: 0, width: 280, height: 140)
    let childAFrame = CGRect(x: 20, y: 20, width: 80, height: 60)
    let childBFrame = CGRect(x: 140, y: 40, width: 80, height: 60)
    let siblingFrame = CGRect(x: 360, y: 40, width: 80, height: 60)
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
        center: CGPoint(x: 250, y: 80)
    )

    session.scene.append(childAItem)
    session.scene.append(childBItem)
    session.scene.append(parentDirectItem)
    session.groups = [
        CanvasItemGroup(
            id: childAID,
            title: "A",
            itemIDs: [],
            frame: childAFrame
        ),
        CanvasItemGroup(
            id: childBID,
            title: "B",
            itemIDs: [],
            frame: childBFrame
        ),
        CanvasItemGroup(
            id: parentID,
            title: "C",
            itemIDs: [],
            frame: parentFrame
        ),
        CanvasItemGroup(
            id: siblingID,
            title: "Sibling",
            itemIDs: [],
            frame: siblingFrame
        )
    ]

    return GroupHierarchySubtreeMoveFixture(
        session: session,
        parentID: parentID,
        childAID: childAID,
        childBID: childBID,
        siblingID: siblingID,
        parentFrame: parentFrame,
        childAFrame: childAFrame,
        childBFrame: childBFrame,
        siblingFrame: siblingFrame,
        childAItem: childAItem,
        childBItem: childBItem,
        parentDirectItem: parentDirectItem
    )
}

private func translatedGroupHierarchySubtreeGeometries(
    _ subtreeGeometries: CanvasGroupSubtreeGeometries,
    by translation: CGPoint
) -> CanvasGroupSubtreeGeometries {
    CanvasGroupSubtreeGeometries(
        descendantGroupFrames: subtreeGeometries.descendantGroupFrames.map { geometry in
            CanvasGroupFrameGeometry(
                groupID: geometry.groupID,
                frame: geometry.frame.offsetBy(dx: translation.x, dy: translation.y)
            )
        },
        itemGeometries: subtreeGeometries.itemGeometries.map { geometry in
            CanvasBoardItemGeometry(
                itemID: geometry.itemID,
                center: geometry.center.translated(by: translation),
                size: geometry.size,
                rotationRadians: geometry.rotationRadians
            )
        }
    )
}

private extension CGPoint {
    func translated(by translation: CGPoint) -> CGPoint {
        CGPoint(
            x: x + translation.x,
            y: y + translation.y
        )
    }
}

private func makeGroupHierarchyRenderOrderGroups(
    parentID: CanvasItemGroupID,
    childID: CanvasItemGroupID
) -> [CanvasItemGroup] {
    [
        CanvasItemGroup(
            id: childID,
            title: "Child",
            itemIDs: [],
            frame: CGRect(x: 50, y: 50, width: 80, height: 80)
        ),
        CanvasItemGroup(
            id: parentID,
            title: "Parent",
            itemIDs: [],
            childGroupIDs: [childID],
            frame: CGRect(x: 0, y: 0, width: 220, height: 220)
        )
    ]
}

private func makeGroupHierarchyRenderOrderSession(
    parentID: CanvasItemGroupID,
    childID: CanvasItemGroupID
) -> CanvasEditorSession {
    let session = makeGroupHierarchyTestSession()
    session.camera = makeGroupHierarchyRenderOrderCamera()
    session.groups = makeGroupHierarchyRenderOrderGroups(
        parentID: parentID,
        childID: childID
    )
    return session
}

private func makeGroupHierarchyRenderOrderCamera() -> CanvasCamera {
    CanvasCamera(
        center: CGPoint(x: 100, y: 100),
        zoomScale: 1,
        viewportSize: CGSize(width: 400, height: 400)
    )
}

private func makeGroupHierarchyContextResolverMetrics() -> CanvasContextResolverMetrics {
    CanvasContextResolverMetrics(
        selectionHandleHitTargetSize: 44,
        selectionOutlineHitTargetWidth: 8,
        cropHandleHitTargetSize: 44,
        cropOutlineHitTargetWidth: 8,
        rotateHandleHitTargetSize: 44
    )
}
