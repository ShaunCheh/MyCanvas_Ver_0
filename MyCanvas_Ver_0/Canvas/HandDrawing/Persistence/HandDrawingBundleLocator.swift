import Foundation

struct HandDrawingBundleLocator {
    static let handDrawingsDirectoryName = "handdrawings"
    static let bundleFileExtension = "handdraw"
    static let manifestFilename = "manifest.json"
    static let documentFilename = "document.hdraw"
    static let previewFilename = "preview.png"

    let documentID: HandDrawingDocumentID

    var bundleDirectoryName: String {
        "\(documentID.uuidString).\(Self.bundleFileExtension)"
    }

    var previewImageRelativePath: String {
        [
            Self.handDrawingsDirectoryName,
            bundleDirectoryName,
            Self.previewFilename
        ].joined(separator: "/")
    }

    var sourceDrawingRelativePath: String {
        [
            Self.handDrawingsDirectoryName,
            bundleDirectoryName,
            Self.documentFilename
        ].joined(separator: "/")
    }

    var manifestRelativePath: String {
        [
            Self.handDrawingsDirectoryName,
            bundleDirectoryName,
            Self.manifestFilename
        ].joined(separator: "/")
    }

    static func handDrawingsDirectoryURL(in boardDirectoryURL: URL) -> URL {
        boardDirectoryURL.appendingPathComponent(
            handDrawingsDirectoryName,
            isDirectory: true
        )
    }

    func handDrawingsDirectoryURL(in boardDirectoryURL: URL) -> URL {
        Self.handDrawingsDirectoryURL(in: boardDirectoryURL)
    }

    func bundleDirectoryURL(in boardDirectoryURL: URL) -> URL {
        handDrawingsDirectoryURL(in: boardDirectoryURL).appendingPathComponent(
            bundleDirectoryName,
            isDirectory: true
        )
    }

    func manifestURL(in boardDirectoryURL: URL) -> URL {
        bundleDirectoryURL(in: boardDirectoryURL).appendingPathComponent(
            Self.manifestFilename
        )
    }

    func documentURL(in boardDirectoryURL: URL) -> URL {
        bundleDirectoryURL(in: boardDirectoryURL).appendingPathComponent(
            Self.documentFilename
        )
    }

    func previewImageURL(in boardDirectoryURL: URL) -> URL {
        bundleDirectoryURL(in: boardDirectoryURL).appendingPathComponent(
            Self.previewFilename
        )
    }
}
