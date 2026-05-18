import CoreGraphics
import Foundation
@testable import MyCanvas_Ver_0

func makeHandDrawingTestDocument(
    paper: HandDrawingPaper = HandDrawingPaper(
        id: "stage4-paper",
        size: CGSize(width: 120, height: 120)
    ),
    includeEraseMask: Bool = false
) -> HandDrawingDocument {
    HandDrawingDocument(
        paper: paper,
        strokes: [
            makeHandDrawingTestStroke(includeEraseMask: includeEraseMask)
        ]
    )
}

func makeHandDrawingTestStroke(
    id: UUID = UUID(),
    color: HandDrawingColor = HandDrawingColor(
        red: 0.18,
        green: 0.34,
        blue: 0.82,
        alpha: 1
    ),
    includeEraseMask: Bool = false,
    transform: HandDrawingStrokeTransform = .identity
) -> HandDrawingStroke {
    let eraseMask: [HandDrawingErasePath]
    if includeEraseMask {
        eraseMask = [
            HandDrawingErasePath(
                samplePoints: [
                    HandDrawingEraseSamplePoint(
                        point: CGPoint(x: 60, y: 60),
                        radius: 10
                    )
                ]
            )
        ]
    } else {
        eraseMask = []
    }
    return HandDrawingStroke(
        id: id,
        brush: HandDrawingBrushStyle(
            kind: .pen,
            color: color,
            baseSize: 14,
            opacity: 1
        ),
        samplePoints: [
            HandDrawingSamplePoint(
                point: CGPoint(x: 25, y: 60),
                force: 1,
                timestamp: 0
            ),
            HandDrawingSamplePoint(
                point: CGPoint(x: 60, y: 60),
                force: 1,
                timestamp: 0.1
            ),
            HandDrawingSamplePoint(
                point: CGPoint(x: 95, y: 60),
                force: 0.9,
                timestamp: 0.2
            )
        ],
        transform: transform,
        eraseMask: eraseMask
    )
}

func sampleRGBA(
    from image: CGImage,
    x: Int,
    y: Int
) -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
    let width = image.width
    let height = image.height
    precondition(x >= 0 && x < width)
    precondition(y >= 0 && y < height)
    let bitmapInfo =
        CGImageAlphaInfo.premultipliedLast.rawValue
        | CGBitmapInfo.byteOrder32Big.rawValue
    guard
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        )
    else {
        fatalError("Expected RGBA bitmap context.")
    }
    context.draw(
        image,
        in: CGRect(x: 0, y: 0, width: width, height: height)
    )
    guard let contextData = context.data else {
        fatalError("Expected RGBA bitmap bytes.")
    }
    let bytes = Data(
        bytes: contextData,
        count: width * height * 4
    )
    let bytesPerPixel = 4
    let offset = ((height - 1 - y) * width + x) * bytesPerPixel
    return (
        red: bytes[offset],
        green: bytes[offset + 1],
        blue: bytes[offset + 2],
        alpha: bytes[offset + 3]
    )
}
