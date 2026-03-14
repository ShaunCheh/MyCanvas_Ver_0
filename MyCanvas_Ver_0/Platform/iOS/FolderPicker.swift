#if os(iOS)
import Foundation
import UniformTypeIdentifiers
import UIKit

final class FolderPicker: NSObject, UIDocumentPickerDelegate {
    typealias SelectionHandler = (Result<Data, Error>) -> Void

    private var selectionHandler: SelectionHandler?

    func present(
        from presenter: UIViewController,
        selectionHandler: @escaping SelectionHandler
    ) {
        self.selectionHandler = selectionHandler

        let pickerViewController = UIDocumentPickerViewController(
            forOpeningContentTypes: [.folder],
            asCopy: false
        )
        pickerViewController.delegate = self
        pickerViewController.allowsMultipleSelection = false
        presenter.present(pickerViewController, animated: true)
    }

    func documentPicker(
        _ controller: UIDocumentPickerViewController,
        didPickDocumentsAt urls: [URL]
    ) {
        let selectionHandler = selectionHandler
        self.selectionHandler = nil

        guard let url = urls.first else {
            return
        }

        do {
            let bookmarkData = try makeBookmarkData(for: url)
            selectionHandler?(.success(bookmarkData))
        } catch {
            selectionHandler?(.failure(error))
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        selectionHandler = nil
    }

    private func makeBookmarkData(for url: URL) throws -> Data {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        var coordinatedBookmarkData: Data?
        var bookmarkError: Error?
        var coordinationError: NSError?
        let coordinator = NSFileCoordinator()

        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            do {
                coordinatedBookmarkData = try coordinatedURL.bookmarkData(
                    options: [],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
            } catch {
                bookmarkError = error
            }
        }

        if let coordinationError {
            throw coordinationError
        }

        if let bookmarkError {
            throw bookmarkError
        }

        if let coordinatedBookmarkData {
            return coordinatedBookmarkData
        }

        throw CocoaError(.fileReadUnknown)
    }
}
#endif
