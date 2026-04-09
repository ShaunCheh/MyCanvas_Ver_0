import Foundation

struct BoardCatalogItem {
    let document: BoardDocument
    let persistedThumbnailURL: URL
    let assetsDirectoryURL: URL
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

    var contentUpdatedAt: Date {
        document.contentUpdatedAt
    }

    var viewStateUpdatedAt: Date {
        document.viewStateUpdatedAt
    }

    var updatedAt: Date {
        contentUpdatedAt
    }

    var summary: BoardSummary {
        document.summary
    }

    var revisionToken: String {
        "\(boardID.uuidString)-\(contentUpdatedAt.timeIntervalSince1970)"
    }
}
