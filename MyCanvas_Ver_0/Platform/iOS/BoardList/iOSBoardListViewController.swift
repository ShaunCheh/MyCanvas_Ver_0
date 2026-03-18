#if os(iOS)
import UIKit

final class iOSBoardListViewController: UIViewController {
    private let folderPicker = FolderPicker()
    var onOpenBoard: ((UUID) -> Void)?
    var onCreateBoard: (() -> Void)?
    private var availableBoards: [BoardSummary] = []

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Board List"
        label.font = .systemFont(ofSize: 28, weight: .semibold)
        label.textColor = .label
        label.textAlignment = .center
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Select a storage folder, then open the canvas."
        label.font = .systemFont(ofSize: 16)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private let selectFolderButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        var configuration = UIButton.Configuration.filled()
        configuration.title = "Select Folder"
        configuration.cornerStyle = .medium
        button.configuration = configuration
        return button
    }()

    private let openCanvasButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        var configuration = UIButton.Configuration.tinted()
        configuration.title = "Select Folder First"
        configuration.cornerStyle = .medium
        button.configuration = configuration
        button.isEnabled = false
        return button
    }()

    private let bookmarkStatusLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViewHierarchy()
        setupConstraints()
        setupActions()
        refreshBookmarkStatus()
    }

    private func setupViewHierarchy() {
        view.backgroundColor = .systemBackground
        view.addSubview(titleLabel)
        view.addSubview(subtitleLabel)
        view.addSubview(selectFolderButton)
        view.addSubview(openCanvasButton)
        view.addSubview(bookmarkStatusLabel)
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -16),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            subtitleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            subtitleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
            selectFolderButton.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 24),
            selectFolderButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            openCanvasButton.topAnchor.constraint(equalTo: selectFolderButton.bottomAnchor, constant: 12),
            openCanvasButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            bookmarkStatusLabel.topAnchor.constraint(equalTo: openCanvasButton.bottomAnchor, constant: 12),
            bookmarkStatusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            bookmarkStatusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            bookmarkStatusLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24)
        ])
    }

    private func setupActions() {
        selectFolderButton.addTarget(self, action: #selector(handleSelectFolderButtonTap), for: .touchUpInside)
        openCanvasButton.addTarget(self, action: #selector(handleOpenCanvasButtonTap), for: .touchUpInside)
    }

    private func refreshBookmarkStatus() {
        let bookmarkText = FolderBookmarkStore.statusText()
        do {
            let boards = try BoardStore.listBoards()
            availableBoards = boards
            bookmarkStatusLabel.text = "\(bookmarkText)\n\nBoards available: \(boards.count)"
            updateOpenCanvasButtonState(hasSelectedFolder: true)
        } catch FolderBookmarkStoreError.missingBookmarkData {
            availableBoards = []
            bookmarkStatusLabel.text = bookmarkText
            updateOpenCanvasButtonState(hasSelectedFolder: false)
        } catch {
            availableBoards = []
            bookmarkStatusLabel.text = "\(bookmarkText)\n\nStorage error: \(error.localizedDescription)"
            updateOpenCanvasButtonState(hasSelectedFolder: false)
        }
    }

    private func updateOpenCanvasButtonState(hasSelectedFolder: Bool) {
        var configuration = openCanvasButton.configuration ?? UIButton.Configuration.tinted()
        if hasSelectedFolder {
            configuration.title = availableBoards.isEmpty
                ? "Create Board"
                : "Open Latest Board"
            openCanvasButton.isEnabled = true
        } else {
            configuration.title = "Select Folder First"
            openCanvasButton.isEnabled = false
        }
        openCanvasButton.configuration = configuration
    }

    @objc
    private func handleSelectFolderButtonTap() {
        folderPicker.present(from: self) { [weak self] result in
            switch result {
            case let .success(bookmarkData):
                FolderBookmarkStore.save(bookmarkData)
                print("[FolderBookmark][iOS] Saved bookmark data bytes=\(bookmarkData.count)")
                self?.refreshBookmarkStatus()
            case let .failure(error):
                print("[FolderBookmark][iOS] Failed to create bookmark: \(error)")
                self?.presentSelectionError(error)
            }
        }
    }

    @objc
    private func handleOpenCanvasButtonTap() {
        guard FolderBookmarkStore.hasStoredBookmarkData() else {
            return
        }

        if let latestBoard = availableBoards.first {
            onOpenBoard?(latestBoard.boardID)
        } else {
            onCreateBoard?()
        }
    }

    private func presentSelectionError(_ error: Error) {
        let alertController = UIAlertController(
            title: "Unable to Save Folder Bookmark",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alertController.addAction(UIAlertAction(title: "OK", style: .default))
        present(alertController, animated: true)
    }
}
#endif
