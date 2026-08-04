import CoreGraphics
import XCTest
@testable import MyCanvas_Ver_0

@MainActor
final class CanvasRendererEditHandleVisualStateTests: XCTestCase {
    func testSingleScalableItemActivatesOnlyExactResizeIdentity() throws {
        let item = try makeRendererHandleImageItem()
        let activeIdentity = CanvasEditHandleIdentity(
            owner: .item(item.id),
            kind: .selectionResize(.topLeading)
        )
        let snapshot = makeRendererHandleSnapshot(
            items: [.image(item)],
            interactionState: CanvasInteractionState(selectedItemID: item.id),
            activeIdentity: activeIdentity
        )
        let overlay = try XCTUnwrap(snapshot.editOverlay)

        XCTAssertEqual(
            Set(overlay.handles.map(\.role)),
            Set([
                .topLeading,
                .topTrailing,
                .bottomLeading,
                .bottomTrailing
            ])
        )
        try assertOnlyRendererHandleActive(
            in: rendererEditHandles(from: snapshot),
            identity: activeIdentity
        )

        let wrongOwnerSnapshot = makeRendererHandleSnapshot(
            items: [.image(item)],
            interactionState: CanvasInteractionState(selectedItemID: item.id),
            activeIdentity: CanvasEditHandleIdentity(
                owner: .item(CanvasItemID()),
                kind: .selectionResize(.topLeading)
            )
        )
        try assertAllRendererHandlesNormal(
            rendererEditHandles(from: wrongOwnerSnapshot)
        )

        let wrongKindSnapshot = makeRendererHandleSnapshot(
            items: [.image(item)],
            interactionState: CanvasInteractionState(selectedItemID: item.id),
            activeIdentity: CanvasEditHandleIdentity(
                owner: .item(item.id),
                kind: .cropResize(.topLeading)
            )
        )
        try assertAllRendererHandlesNormal(
            rendererEditHandles(from: wrongKindSnapshot)
        )
    }

    func testAllMarkdownSelectionActivatesOnlyExactEdgeIdentity() throws {
        let firstItem = CanvasMarkdownItem(
            markdownSource: "## First",
            center: CGPoint(x: -100, y: -30),
            size: CGSize(width: 150, height: 90)
        )
        let secondItem = CanvasMarkdownItem(
            markdownSource: "## Second",
            center: CGPoint(x: 110, y: 45),
            size: CGSize(width: 180, height: 110)
        )
        let interactionState = CanvasInteractionState(
            selectedItemIDs: [firstItem.id, secondItem.id],
            primarySelectedItemID: secondItem.id
        )
        let owner = CanvasEditHandleOwner.selection(
            CanvasEditHandleSelectionIdentity(
                primaryItemID: secondItem.id,
                memberItemIDs: [firstItem.id, secondItem.id]
            )
        )
        let activeIdentity = CanvasEditHandleIdentity(
            owner: owner,
            kind: .selectionResize(.trailing)
        )
        let items: [CanvasBoardItem] = [
            .markdown(firstItem),
            .markdown(secondItem)
        ]
        let snapshot = makeRendererHandleSnapshot(
            items: items,
            interactionState: interactionState,
            activeIdentity: activeIdentity
        )
        let overlay = try XCTUnwrap(snapshot.editOverlay)

        XCTAssertEqual(
            overlay.handles.map(\.role),
            [.top, .trailing, .bottom, .leading]
        )
        try assertOnlyRendererHandleActive(
            in: rendererEditHandles(from: snapshot),
            identity: activeIdentity
        )

        let nonVisibleCornerIdentity = CanvasEditHandleIdentity(
            owner: owner,
            kind: .selectionResize(.topLeading)
        )
        let mismatchSnapshot = makeRendererHandleSnapshot(
            items: items,
            interactionState: interactionState,
            activeIdentity: nonVisibleCornerIdentity
        )
        try assertAllRendererHandlesNormal(
            rendererEditHandles(from: mismatchSnapshot)
        )
    }

    func testMixedMultiSelectionActivatesOnlyExactCornerIdentity() throws {
        let firstItem = CanvasTextItem(
            text: "first",
            center: CGPoint(x: -90, y: -25),
            size: CGSize(width: 100, height: 52)
        )
        let secondItem = CanvasTextItem(
            text: "second",
            center: CGPoint(x: 95, y: 35),
            size: CGSize(width: 120, height: 64)
        )
        let interactionState = CanvasInteractionState(
            selectedItemIDs: [firstItem.id, secondItem.id],
            primarySelectedItemID: secondItem.id
        )
        let selectionIdentity = CanvasEditHandleSelectionIdentity(
            primaryItemID: secondItem.id,
            memberItemIDs: [firstItem.id, secondItem.id]
        )
        let activeIdentity = CanvasEditHandleIdentity(
            owner: .selection(selectionIdentity),
            kind: .selectionResize(.bottomTrailing)
        )
        let items: [CanvasBoardItem] = [
            .text(firstItem),
            .text(secondItem)
        ]
        let snapshot = makeRendererHandleSnapshot(
            items: items,
            interactionState: interactionState,
            activeIdentity: activeIdentity
        )
        let overlay = try XCTUnwrap(snapshot.editOverlay)

        XCTAssertEqual(
            Set(overlay.handles.map(\.role)),
            Set([
                .topLeading,
                .topTrailing,
                .bottomLeading,
                .bottomTrailing
            ])
        )
        try assertOnlyRendererHandleActive(
            in: rendererEditHandles(from: snapshot),
            identity: activeIdentity
        )

        let incompleteOwnerSnapshot = makeRendererHandleSnapshot(
            items: items,
            interactionState: interactionState,
            activeIdentity: CanvasEditHandleIdentity(
                owner: .selection(
                    CanvasEditHandleSelectionIdentity(
                        primaryItemID: secondItem.id,
                        memberItemIDs: [secondItem.id]
                    )
                ),
                kind: .selectionResize(.bottomTrailing)
            )
        )
        try assertAllRendererHandlesNormal(
            rendererEditHandles(from: incompleteOwnerSnapshot)
        )
    }

    func testSingleRotateActivatesOnlyExactRotateIdentity() throws {
        let item = try makeRendererHandleImageItem()
        let activeIdentity = CanvasEditHandleIdentity(
            owner: .item(item.id),
            kind: .rotate
        )
        let snapshot = makeRendererHandleSnapshot(
            items: [.image(item)],
            interactionState: CanvasInteractionState(selectedItemID: item.id),
            activeIdentity: activeIdentity
        )

        try assertOnlyRendererHandleActive(
            in: rendererEditHandles(from: snapshot),
            identity: activeIdentity
        )

        let wrongOwnerSnapshot = makeRendererHandleSnapshot(
            items: [.image(item)],
            interactionState: CanvasInteractionState(selectedItemID: item.id),
            activeIdentity: CanvasEditHandleIdentity(
                owner: .item(CanvasItemID()),
                kind: .rotate
            )
        )
        try assertAllRendererHandlesNormal(
            rendererEditHandles(from: wrongOwnerSnapshot)
        )
    }

    func testMultiSelectionRotateActivatesOnlyCanonicalSelectionIdentity() throws {
        let firstItem = CanvasTextItem(
            text: "first",
            center: CGPoint(x: -85, y: -30),
            size: CGSize(width: 100, height: 50)
        )
        let secondItem = CanvasTextItem(
            text: "second",
            center: CGPoint(x: 90, y: 30),
            size: CGSize(width: 115, height: 60)
        )
        let interactionState = CanvasInteractionState(
            selectedItemIDs: [firstItem.id, secondItem.id],
            primarySelectedItemID: secondItem.id
        )
        let activeIdentity = CanvasEditHandleIdentity(
            owner: .selection(
                CanvasEditHandleSelectionIdentity(
                    primaryItemID: secondItem.id,
                    memberItemIDs: [secondItem.id, firstItem.id]
                )
            ),
            kind: .rotate
        )
        let items: [CanvasBoardItem] = [
            .text(firstItem),
            .text(secondItem)
        ]
        let snapshot = makeRendererHandleSnapshot(
            items: items,
            interactionState: interactionState,
            activeIdentity: activeIdentity
        )

        try assertOnlyRendererHandleActive(
            in: rendererEditHandles(from: snapshot),
            identity: activeIdentity
        )

        let itemOwnerSnapshot = makeRendererHandleSnapshot(
            items: items,
            interactionState: interactionState,
            activeIdentity: CanvasEditHandleIdentity(
                owner: .item(secondItem.id),
                kind: .rotate
            )
        )
        try assertAllRendererHandlesNormal(
            rendererEditHandles(from: itemOwnerSnapshot)
        )
    }

    func testInlineCropActivatesOnlyExactCropResizeIdentity() throws {
        let item = try makeRendererHandleImageItem()
        let activeIdentity = CanvasEditHandleIdentity(
            owner: .item(item.id),
            kind: .cropResize(.leading)
        )
        let snapshot = makeRendererHandleSnapshot(
            items: [.image(item)],
            interactionState: CanvasInteractionState(selectedItemID: item.id),
            activeIdentity: activeIdentity,
            inlineEditState: CanvasInlineEditState(item: item)
        )
        let overlay = try XCTUnwrap(snapshot.editOverlay)

        XCTAssertEqual(
            Set(overlay.handles.map(\.role)),
            Set([
                .topLeading,
                .top,
                .topTrailing,
                .trailing,
                .bottomTrailing,
                .bottom,
                .bottomLeading,
                .leading
            ])
        )
        try assertOnlyRendererHandleActive(
            in: rendererEditHandles(from: snapshot),
            identity: activeIdentity
        )

        let selectionKindSnapshot = makeRendererHandleSnapshot(
            items: [.image(item)],
            interactionState: CanvasInteractionState(selectedItemID: item.id),
            activeIdentity: CanvasEditHandleIdentity(
                owner: .item(item.id),
                kind: .selectionResize(.leading)
            ),
            inlineEditState: CanvasInlineEditState(item: item)
        )
        try assertAllRendererHandlesNormal(
            rendererEditHandles(from: selectionKindSnapshot)
        )
    }

    func testArrowEndpointsActivateOnlyExactStartOrEndIdentity() throws {
        let arrow = CanvasArrowItem(
            center: CGPoint(x: 20, y: -10),
            size: CGSize(width: 200, height: 80),
            rotationRadians: .pi / 9
        )
        let items: [CanvasBoardItem] = [.arrow(arrow)]
        let interactionState = CanvasInteractionState(selectedItemID: arrow.id)

        for role in CanvasArrowEndpointRole.allCases {
            let activeIdentity = CanvasEditHandleIdentity(
                owner: .item(arrow.id),
                kind: .arrowEndpoint(role)
            )
            let snapshot = makeRendererHandleSnapshot(
                items: items,
                interactionState: interactionState,
                activeIdentity: activeIdentity
            )
            let handles = try rendererEditHandles(from: snapshot)

            XCTAssertEqual(
                Set(handles.map(\.role)),
                Set([.arrowStart, .arrowEnd])
            )
            assertOnlyRendererHandleActive(
                in: handles,
                identity: activeIdentity
            )
        }

        let wrongOwnerSnapshot = makeRendererHandleSnapshot(
            items: items,
            interactionState: interactionState,
            activeIdentity: CanvasEditHandleIdentity(
                owner: .item(CanvasItemID()),
                kind: .arrowEndpoint(.start)
            )
        )
        try assertAllRendererHandlesNormal(
            rendererEditHandles(from: wrongOwnerSnapshot)
        )
    }

    func testGroupFrameResizeActivatesOnlyExactGroupIdentity() throws {
        let groupID = CanvasItemGroupID()
        let group = CanvasItemGroup(
            id: groupID,
            title: "Group",
            itemIDs: [],
            frame: CGRect(x: -130, y: -90, width: 260, height: 180)
        )
        let activeIdentity = CanvasEditHandleIdentity(
            owner: .group(groupID),
            kind: .groupFrameResize(.bottomTrailing)
        )
        let snapshot = makeRendererHandleSnapshot(
            groups: [group],
            groupInteractionState: CanvasGroupInteractionState(
                selectedGroupID: groupID
            ),
            activeIdentity: activeIdentity
        )
        let overlay = try XCTUnwrap(snapshot.groupEditOverlay)

        XCTAssertNil(snapshot.editOverlay)
        XCTAssertEqual(
            Set(overlay.handles.map(\.role)),
            Set([
                .topLeading,
                .top,
                .topTrailing,
                .trailing,
                .bottomTrailing,
                .bottom,
                .bottomLeading,
                .leading
            ])
        )
        assertOnlyRendererHandleActive(
            in: overlay.handles,
            identity: activeIdentity
        )

        let wrongKindSnapshot = makeRendererHandleSnapshot(
            groups: [group],
            groupInteractionState: CanvasGroupInteractionState(
                selectedGroupID: groupID
            ),
            activeIdentity: CanvasEditHandleIdentity(
                owner: .group(groupID),
                kind: .selectionResize(.bottomTrailing)
            )
        )
        let wrongKindOverlay = try XCTUnwrap(
            wrongKindSnapshot.groupEditOverlay
        )
        assertAllRendererHandlesNormal(wrongKindOverlay.handles)

        let wrongGroupSnapshot = makeRendererHandleSnapshot(
            groups: [group],
            groupInteractionState: CanvasGroupInteractionState(
                selectedGroupID: groupID
            ),
            activeIdentity: CanvasEditHandleIdentity(
                owner: .group(CanvasItemGroupID()),
                kind: .groupFrameResize(.bottomTrailing)
            )
        )
        let wrongGroupOverlay = try XCTUnwrap(
            wrongGroupSnapshot.groupEditOverlay
        )
        assertAllRendererHandlesNormal(wrongGroupOverlay.handles)
    }
}

private enum CanvasRendererEditHandleVisualStateTestRetainer {
    static var scenes: [CanvasScene] = []
}

@MainActor
private func makeRendererHandleSnapshot(
    items: [CanvasBoardItem] = [],
    groups: [CanvasItemGroup] = [],
    interactionState: CanvasInteractionState? = nil,
    groupInteractionState: CanvasGroupInteractionState? = nil,
    activeIdentity: CanvasEditHandleIdentity?,
    inlineEditState: CanvasInlineEditState? = nil
) -> CanvasRenderSnapshot {
    var editHandleInteractionState = CanvasEditHandleInteractionState()
    if let activeIdentity {
        _ = editHandleInteractionState.apply(.press(activeIdentity))
    }
    let scene = CanvasScene(items: items)
    CanvasRendererEditHandleVisualStateTestRetainer.scenes.append(scene)

    return CanvasRenderer().makeSnapshot(
        scene: scene,
        groups: groups,
        camera: CanvasCamera(
            center: .zero,
            zoomScale: 1,
            viewportSize: CGSize(width: 800, height: 600)
        ),
        interactionState: interactionState ?? CanvasInteractionState(),
        groupInteractionState:
            groupInteractionState ?? CanvasGroupInteractionState(),
        editHandleInteractionState: editHandleInteractionState,
        inlineEditState: inlineEditState
    )
}

@MainActor
private func rendererEditHandles(
    from snapshot: CanvasRenderSnapshot,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> [CanvasEditHandleGeometry] {
    let overlay = try XCTUnwrap(
        snapshot.editOverlay,
        file: file,
        line: line
    )
    var handles = overlay.handles
    if case let .selection(payload) = overlay.payload,
       let rotateHandle = payload.rotateAffordance?.handle
    {
        handles.append(rotateHandle)
    }
    return handles
}

@MainActor
private func assertOnlyRendererHandleActive(
    in handles: [CanvasEditHandleGeometry],
    identity: CanvasEditHandleIdentity,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(
        handles.filter { $0.visualState == .active }.map(\.identity),
        [identity],
        file: file,
        line: line
    )
    for handle in handles {
        XCTAssertEqual(
            handle.visualState,
            handle.identity == identity ? .active : .normal,
            file: file,
            line: line
        )
    }
}

@MainActor
private func assertAllRendererHandlesNormal(
    _ handles: [CanvasEditHandleGeometry],
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertTrue(
        handles.allSatisfy { $0.visualState == .normal },
        file: file,
        line: line
    )
}

@MainActor
private func makeRendererHandleImageItem() throws -> CanvasImageItem {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    guard let context = CGContext(
        data: nil,
        width: 2,
        height: 2,
        bitsPerComponent: 8,
        bytesPerRow: 8,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    ) else {
        throw CanvasRendererEditHandleVisualStateTestError
            .failedToCreateImage
    }
    context.setFillColor(
        red: 0.25,
        green: 0.55,
        blue: 0.85,
        alpha: 1
    )
    context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
    guard let image = context.makeImage() else {
        throw CanvasRendererEditHandleVisualStateTestError
            .failedToCreateImage
    }

    return CanvasImageItem(
        asset: .transientStaticImage(cgImage: image),
        center: .zero,
        size: CGSize(width: 180, height: 120)
    )
}

private enum CanvasRendererEditHandleVisualStateTestError: Error {
    case failedToCreateImage
}
