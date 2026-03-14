#if os(macOS)
import AppKit

final class macOSBoardListViewController: NSViewController {
    var onOpenCanvas: (() -> Void)?

    private let titleLabel: NSTextField = {
        let label = NSTextField(labelWithString: "Board List")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 28, weight: .semibold)
        label.textColor = .labelColor
        label.alignment = .center
        return label
    }()

    private let selectFolderButton: NSButton = {
        let button = NSButton(title: "Select Folder", target: nil, action: nil)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .rounded
        return button
    }()

    private let openCanvasButton: NSButton = {
        let button = NSButton(title: "Open Canvas", target: nil, action: nil)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .rounded
        return button
    }()

    private let bookmarkStatusLabel: NSTextField = {
        let label = NSTextField(wrappingLabelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.maximumNumberOfLines = 0
        return label
    }()

    private let subtitleLabel: NSTextField = {
        let label = NSTextField(labelWithString: "Select a storage folder, then open the canvas.")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 16)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        return label
    }()

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViewHierarchy()
        setupConstraints()
        setupActions()
        refreshBookmarkStatus()
    }

    private func setupViewHierarchy() {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
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
        selectFolderButton.target = self
        selectFolderButton.action = #selector(handleSelectFolderButtonClick)
        openCanvasButton.target = self
        openCanvasButton.action = #selector(handleOpenCanvasButtonClick)
    }

    private func refreshBookmarkStatus() {
        let bookmarkText = FolderBookmarkStore.statusText()
        do {
            let boardCount = try BoardStore.listBoards().count
            bookmarkStatusLabel.stringValue = "\(bookmarkText)\n\nBoards available: \(boardCount)"
        } catch FolderBookmarkStoreError.missingBookmarkData {
            bookmarkStatusLabel.stringValue = bookmarkText
        } catch {
            bookmarkStatusLabel.stringValue = "\(bookmarkText)\n\nStorage error: \(error.localizedDescription)"
        }
    }

    @objc
    private func handleSelectFolderButtonClick() {
        do {
            guard let bookmarkData = try FilePickerManager.selectFolder() else {
                return
            }

            FolderBookmarkStore.save(bookmarkData)
            print("[FolderBookmark][macOS] Saved bookmark data bytes=\(bookmarkData.count)")
            refreshBookmarkStatus()
        } catch {
            print("[FolderBookmark][macOS] Failed to create bookmark: \(error)")
            presentSelectionError(error)
        }
    }

    @objc
    private func handleOpenCanvasButtonClick() {
        onOpenCanvas?()
    }

    private func presentSelectionError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Unable to Save Folder Bookmark"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")

        if let window = view.window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}
#endif
