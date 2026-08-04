#if os(macOS)
import AppKit
import XCTest
@testable import MyCanvas_Ver_0

@MainActor
final class macOSCanvasToolbarHostViewTests: XCTestCase {
    func testVerticalButtonsUseUniformVisibleFramesAndSpacing() {
        let itemIDs: [CanvasToolbarItemID] = [
            .undo,
            .multiSelect,
            .save,
            .importMedia
        ]
        let buttonsByID = Dictionary(
            uniqueKeysWithValues: itemIDs.map { itemID in
                (itemID, NSButton())
            }
        )
        let hostView = macOSCanvasToolbarHostView()
        hostView.registerButtons(buttonsByID)
        hostView.render(
            CanvasToolbarState(
                placement: CanvasToolbarPlacement(preferredEdge: .trailing),
                items: itemIDs.map { itemID in
                    CanvasToolbarItemState(
                        id: itemID,
                        systemImageName: "circle.fill",
                        accessibilityLabel: itemID.rawValue,
                        visualRole: .accent
                    )
                }
            )
        )

        hostView.frame = CGRect(
            origin: .zero,
            size: hostView.measuredContentSize()
        )
        hostView.layoutSubtreeIfNeeded()

        let visibleButtonFrames = itemIDs.compactMap { itemID -> CGRect? in
            guard let button = buttonsByID[itemID] else {
                return nil
            }
            return hostView.convert(button.bounds, from: button)
        }
        XCTAssertEqual(visibleButtonFrames.count, itemIDs.count)

        for frame in visibleButtonFrames {
            XCTAssertEqual(
                frame.width,
                macOSCanvasToolbarChromeMetrics.buttonEdge,
                accuracy: 0.001
            )
            XCTAssertEqual(
                frame.height,
                macOSCanvasToolbarChromeMetrics.buttonEdge,
                accuracy: 0.001
            )
        }

        let verticallyOrderedFrames = visibleButtonFrames.sorted {
            $0.minY < $1.minY
        }
        for (currentFrame, nextFrame) in zip(
            verticallyOrderedFrames,
            verticallyOrderedFrames.dropFirst()
        ) {
            XCTAssertEqual(
                nextFrame.minY - currentFrame.maxY,
                macOSCanvasToolbarChromeMetrics.spacing,
                accuracy: 0.001
            )
        }
    }

    func testEnabledButtonDarkensOnHoverAndRestoresOnExit() throws {
        let button = NSButton()
        let hostView = macOSCanvasToolbarHostView()
        hostView.registerButtons([.save: button])
        hostView.render(
            CanvasToolbarState(
                placement: CanvasToolbarPlacement(preferredEdge: .trailing),
                items: [
                    CanvasToolbarItemState(
                        id: .save,
                        systemImageName: "square.and.arrow.down",
                        accessibilityLabel: "Save",
                        visualRole: .accent
                    )
                ]
            )
        )

        hostView.frame = CGRect(
            origin: .zero,
            size: hostView.measuredContentSize()
        )
        hostView.layoutSubtreeIfNeeded()

        let slot = try XCTUnwrap(button.superview)
        let regularBackgroundColor = try XCTUnwrap(slot.layer?.backgroundColor)
        let enteredEvent = try XCTUnwrap(makeToolbarHoverTestEvent(type: .mouseEntered))
        slot.mouseEntered(with: enteredEvent)
        let hoveredBackgroundColor = try XCTUnwrap(slot.layer?.backgroundColor)

        XCTAssertLessThan(
            toolbarHoverTestLuminance(hoveredBackgroundColor),
            toolbarHoverTestLuminance(regularBackgroundColor)
        )

        let exitedEvent = try XCTUnwrap(makeToolbarHoverTestEvent(type: .mouseExited))
        slot.mouseExited(with: exitedEvent)
        let restoredBackgroundColor = try XCTUnwrap(slot.layer?.backgroundColor)
        XCTAssertEqual(restoredBackgroundColor, regularBackgroundColor)
    }

    func testDisabledButtonDoesNotChangeBackgroundOnHover() throws {
        let button = NSButton()
        let hostView = macOSCanvasToolbarHostView()
        hostView.registerButtons([.undo: button])
        hostView.render(
            CanvasToolbarState(
                placement: CanvasToolbarPlacement(preferredEdge: .trailing),
                items: [
                    CanvasToolbarItemState(
                        id: .undo,
                        systemImageName: "arrow.uturn.backward",
                        isEnabled: false,
                        accessibilityLabel: "Undo",
                        visualRole: .accent
                    )
                ]
            )
        )

        hostView.frame = CGRect(
            origin: .zero,
            size: hostView.measuredContentSize()
        )
        hostView.layoutSubtreeIfNeeded()

        let slot = try XCTUnwrap(button.superview)
        let regularBackgroundColor = try XCTUnwrap(slot.layer?.backgroundColor)
        let enteredEvent = try XCTUnwrap(makeToolbarHoverTestEvent(type: .mouseEntered))
        slot.mouseEntered(with: enteredEvent)
        let hoveredBackgroundColor = try XCTUnwrap(slot.layer?.backgroundColor)

        XCTAssertEqual(hoveredBackgroundColor, regularBackgroundColor)
    }
}

private func makeToolbarHoverTestEvent(
    type: NSEvent.EventType
) -> NSEvent? {
    NSEvent.enterExitEvent(
        with: type,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        eventNumber: 0,
        trackingNumber: 0,
        userData: nil
    )
}

private func toolbarHoverTestLuminance(_ color: CGColor) -> CGFloat {
    guard let components = color.components else {
        return 0
    }
    if components.count >= 3 {
        return (components[0] * 0.2126)
            + (components[1] * 0.7152)
            + (components[2] * 0.0722)
    }
    return components[0]
}
#endif
