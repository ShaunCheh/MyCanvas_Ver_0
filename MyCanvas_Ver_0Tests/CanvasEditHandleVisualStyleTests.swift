import CoreGraphics
import XCTest
@testable import MyCanvas_Ver_0

@MainActor
final class CanvasEditHandleVisualStyleTests: XCTestCase {
    func testSelectionFamiliesKeepBlueStrokeWhenActive() throws {
        let selectionKinds: [CanvasEditHandleKind] = [
            .selectionResize(.topLeading),
            .rotate,
            .arrowEndpoint(.start),
            .groupFrameResize(.bottomTrailing)
        ]

        for kind in selectionKinds {
            let normalStyle = CanvasEditHandleVisualStyleResolver.resolve(
                kind: kind,
                visualState: .normal
            )
            let activeStyle = CanvasEditHandleVisualStyleResolver.resolve(
                kind: kind,
                visualState: .active
            )

            try assertColor(
                normalStyle.fillColor,
                red: 1,
                green: 1,
                blue: 1,
                alpha: 1
            )
            try assertColor(
                normalStyle.strokeColor,
                red: 0,
                green: 122.0 / 255.0,
                blue: 1,
                alpha: 1
            )
            try assertColor(
                activeStyle.fillColor,
                red: 0,
                green: 122.0 / 255.0,
                blue: 1,
                alpha: 1
            )
            try assertColor(
                activeStyle.strokeColor,
                red: 0,
                green: 122.0 / 255.0,
                blue: 1,
                alpha: 1
            )
        }
    }

    func testCropKeepsOrangeStrokeWhenActive() throws {
        let normalStyle = CanvasEditHandleVisualStyleResolver.resolve(
            kind: .cropResize(.leading),
            visualState: .normal
        )
        let activeStyle = CanvasEditHandleVisualStyleResolver.resolve(
            kind: .cropResize(.leading),
            visualState: .active
        )

        try assertColor(
            normalStyle.fillColor,
            red: 1,
            green: 1,
            blue: 1,
            alpha: 1
        )
        try assertColor(
            normalStyle.strokeColor,
            red: 1,
            green: 149.0 / 255.0,
            blue: 0,
            alpha: 1
        )
        try assertColor(
            activeStyle.fillColor,
            red: 1,
            green: 149.0 / 255.0,
            blue: 0,
            alpha: 1
        )
        try assertColor(
            activeStyle.strokeColor,
            red: 1,
            green: 149.0 / 255.0,
            blue: 0,
            alpha: 1
        )
    }

    func testGeometryResolverUsesIdentityKindAndVisualState() throws {
        let itemID = CanvasItemID()
        let handle = CanvasEditHandleGeometry(
            identity: CanvasEditHandleIdentity(
                owner: .item(itemID),
                kind: .cropResize(.trailing)
            ),
            role: .trailing,
            screenCenter: .zero,
            screenRotationRadians: 0,
            visualState: .active
        )

        let style = CanvasEditHandleVisualStyleResolver.resolve(for: handle)

        try assertColor(
            style.fillColor,
            red: 1,
            green: 149.0 / 255.0,
            blue: 0,
            alpha: 1
        )
        try assertColor(
            style.strokeColor,
            red: 1,
            green: 149.0 / 255.0,
            blue: 0,
            alpha: 1
        )
    }

    private func assertColor(
        _ color: CGColor,
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat,
        alpha: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let components = try XCTUnwrap(
            color.components,
            file: file,
            line: line
        )
        let rgbaComponents: [CGFloat]
        switch components.count {
        case 2:
            rgbaComponents = [
                components[0],
                components[0],
                components[0],
                components[1]
            ]
        case 4:
            rgbaComponents = components
        default:
            XCTFail(
                "Expected grayscale-alpha or RGBA components, got \(components)",
                file: file,
                line: line
            )
            return
        }

        XCTAssertEqual(rgbaComponents[0], red, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(rgbaComponents[1], green, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(rgbaComponents[2], blue, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(rgbaComponents[3], alpha, accuracy: 0.0001, file: file, line: line)
    }
}
