import CoreGraphics

enum CanvasWorkspacePalette {
    static let backgroundColor = CGColor(
        red: 28.0 / 255.0,
        green: 29.0 / 255.0,
        blue: 31.0 / 255.0,
        alpha: 1
    )

    static let minorGridStrokeColor = CGColor(
        red: 58.0 / 255.0,
        green: 60.0 / 255.0,
        blue: 64.0 / 255.0,
        alpha: 0.72
    )

    static let majorGridStrokeColor = CGColor(
        red: 84.0 / 255.0,
        green: 87.0 / 255.0,
        blue: 93.0 / 255.0,
        alpha: 0.9
    )

    static let boardSurfaceFillColor = CGColor(gray: 1, alpha: 1)
}
