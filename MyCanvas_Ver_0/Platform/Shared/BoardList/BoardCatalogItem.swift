import Foundation

struct BoardCatalogItem {
    let document: BoardDocument
    let previewSeed: BoardPreviewSeed

    var boardID: UUID {
        document.boardID
    }

    var title: String {
        document.title
    }

    var createdAt: Date {
        document.createdAt
    }

    var updatedAt: Date {
        document.updatedAt
    }

    var summary: BoardSummary {
        document.summary
    }

    var revisionToken: String {
        "\(boardID.uuidString)-\(updatedAt.timeIntervalSince1970)"
    }
}
