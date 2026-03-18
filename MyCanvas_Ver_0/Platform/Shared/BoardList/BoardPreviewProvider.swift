import Foundation

struct BoardPreviewProvider {
    func immediatePreview(for item: BoardCatalogItem) -> BoardPreviewContent {
        .geometry(item.previewSeed)
    }
}
