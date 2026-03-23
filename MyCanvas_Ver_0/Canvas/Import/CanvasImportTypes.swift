import CoreGraphics

struct CanvasResolvedImportImage {
    let cgImage: CGImage

    init(cgImage: CGImage) {
        self.cgImage = cgImage
    }
}

enum CanvasImportPlacement: Equatable {
    case cameraCenter
    case worldPoint(CGPoint)
}

enum CanvasImportLayout: Equatable {
    case automatic
    case stacked
    case staggered(stepInWorld: CGPoint)
}

struct CanvasImportRequest {
    let images: [CanvasResolvedImportImage]
    let placement: CanvasImportPlacement
    let layout: CanvasImportLayout
    let sourceDescription: String

    init(
        images: [CanvasResolvedImportImage],
        placement: CanvasImportPlacement = .cameraCenter,
        layout: CanvasImportLayout = .automatic,
        sourceDescription: String = "external source"
    ) {
        self.images = images
        self.placement = placement
        self.layout = layout
        self.sourceDescription = sourceDescription
    }

    var imageCount: Int {
        images.count
    }

    var isEmpty: Bool {
        images.isEmpty
    }
}
