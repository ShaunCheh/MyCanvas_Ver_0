enum CanvasTransferItem {
    case image(CanvasResolvedImportImage)
}

struct CanvasTransferRequest {
    let items: [CanvasTransferItem]
    let placement: CanvasImportPlacement
    let layout: CanvasImportLayout
    let sourceDescription: String

    init(
        items: [CanvasTransferItem],
        placement: CanvasImportPlacement = .cameraCenter,
        layout: CanvasImportLayout = .automatic,
        sourceDescription: String = "external source"
    ) {
        self.items = items
        self.placement = placement
        self.layout = layout
        self.sourceDescription = sourceDescription
    }

    init(
        images: [CanvasResolvedImportImage],
        placement: CanvasImportPlacement = .cameraCenter,
        layout: CanvasImportLayout = .automatic,
        sourceDescription: String = "external source"
    ) {
        self.init(
            items: images.map { .image($0) },
            placement: placement,
            layout: layout,
            sourceDescription: sourceDescription
        )
    }

    var itemCount: Int {
        items.count
    }

    var isEmpty: Bool {
        items.isEmpty
    }
}
