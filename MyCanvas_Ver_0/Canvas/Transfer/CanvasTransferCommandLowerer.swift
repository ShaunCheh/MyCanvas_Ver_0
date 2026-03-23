enum CanvasTransferCommandLowerer {
    static func loweredCommand(
        for request: CanvasTransferRequest
    ) -> CanvasCommand? {
        guard let importRequest = loweredImportRequest(for: request) else {
            return nil
        }

        return .importImages(importRequest)
    }

    static func loweredImportRequest(
        for request: CanvasTransferRequest
    ) -> CanvasImportRequest? {
        guard request.isEmpty == false else {
            return nil
        }

        var resolvedImages: [CanvasResolvedImportImage] = []
        resolvedImages.reserveCapacity(request.itemCount)

        for item in request.items {
            switch item {
            case let .image(image):
                resolvedImages.append(image)
            }
        }

        return CanvasImportRequest(
            images: resolvedImages,
            placement: request.placement,
            layout: request.layout,
            sourceDescription: request.sourceDescription
        )
    }
}
