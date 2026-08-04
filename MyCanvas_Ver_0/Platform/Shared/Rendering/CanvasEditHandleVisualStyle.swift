import CoreGraphics

struct CanvasEditHandleVisualStyle {
    let fillColor: CGColor
    let strokeColor: CGColor
}

enum CanvasEditHandleVisualStyleResolver {
    private static let neutralColor = CGColor(gray: 1, alpha: 1)
    private static let selectionAccentColor = CGColor(
        red: 0,
        green: 122.0 / 255.0,
        blue: 1,
        alpha: 1
    )
    private static let cropAccentColor = CGColor(
        red: 1,
        green: 149.0 / 255.0,
        blue: 0,
        alpha: 1
    )

    static func resolve(
        for handle: CanvasEditHandleGeometry
    ) -> CanvasEditHandleVisualStyle {
        resolve(
            kind: handle.identity.kind,
            visualState: handle.visualState
        )
    }

    static func resolve(
        kind: CanvasEditHandleKind,
        visualState: CanvasEditHandleVisualState
    ) -> CanvasEditHandleVisualStyle {
        let accentColor = accentColor(for: kind)
        switch visualState {
        case .normal:
            return CanvasEditHandleVisualStyle(
                fillColor: neutralColor,
                strokeColor: accentColor
            )
        case .active:
            return CanvasEditHandleVisualStyle(
                fillColor: accentColor,
                strokeColor: neutralColor
            )
        }
    }

    private static func accentColor(
        for kind: CanvasEditHandleKind
    ) -> CGColor {
        switch kind {
        case .cropResize:
            return cropAccentColor
        case .selectionResize,
             .rotate,
             .arrowEndpoint,
             .groupFrameResize:
            return selectionAccentColor
        }
    }
}
