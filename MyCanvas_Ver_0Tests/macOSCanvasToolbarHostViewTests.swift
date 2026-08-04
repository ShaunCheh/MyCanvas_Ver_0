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
}
#endif
