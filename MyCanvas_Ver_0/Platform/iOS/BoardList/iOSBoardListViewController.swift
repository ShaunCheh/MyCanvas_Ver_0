#if os(iOS)
import UIKit

final class iOSBoardListViewController: UIViewController {
    private let folderPicker = FolderPicker()

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
        label.text = "Placeholder scene for a future board list."
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
            bookmarkStatusLabel.topAnchor.constraint(equalTo: selectFolderButton.bottomAnchor, constant: 12),
            bookmarkStatusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            bookmarkStatusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            bookmarkStatusLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24)
        ])
    }

    private func setupActions() {
        selectFolderButton.addTarget(self, action: #selector(handleSelectFolderButtonTap), for: .touchUpInside)
    }

    private func refreshBookmarkStatus() {
        bookmarkStatusLabel.text = FolderBookmarkStore.statusText()
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
