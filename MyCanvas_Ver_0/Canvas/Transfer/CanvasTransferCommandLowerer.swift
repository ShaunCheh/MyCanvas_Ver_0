enum CanvasTransferCommandLowerer {
    static func loweredCommand(
        for request: CanvasImportRequest
    ) -> CanvasCommand? {
        guard request.isEmpty == false else {
            return nil
        }

        return .importMedia(request)
    }
}
