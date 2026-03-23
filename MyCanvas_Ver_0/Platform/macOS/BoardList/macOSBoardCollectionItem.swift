#if os(macOS)
import AppKit

private func boardListSelectionTraceTimestamp() -> String {
    String(format: "%.3f", ProcessInfo.processInfo.systemUptime)
}

final class macOSBoardCollectionItem: NSCollectionViewItem {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("macOSBoardCollectionItem")

    typealias MoreActionsHandler = (UUID, CGRect, NSView) -> Void

    private enum PresentationStyle {
        case boardGrid
        case boardList
        case placeholderGrid
        case placeholderList
    }

    private let previewView = macOSBoardPreviewView()
    private let placeholderIconView: NSImageView = {
        let configuration = NSImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        let image = NSImage(
            systemSymbolName: "plus",
            accessibilityDescription: BoardListEntry.newBoardTitle
        )?.withSymbolConfiguration(configuration)
        let imageView = NSImageView(image: image ?? NSImage())
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.contentTintColor = .controlAccentColor
        imageView.isHidden = true
        return imageView
    }()
    private let titleLabel: NSTextField = {
        let label = NSTextField(wrappingLabelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .labelColor
        label.maximumNumberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
        return label
    }()
    private let moreButton: NSButton = {
        let button = NSButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isBordered = false
        button.setButtonType(.momentaryChange)
        button.image = NSImage(
            systemSymbolName: "ellipsis",
            accessibilityDescription: "More Actions"
        )
        button.imagePosition = .imageOnly
        button.contentTintColor = .secondaryLabelColor
        button.bezelStyle = .regularSquare
        return button
    }()

    private var gridConstraints: [NSLayoutConstraint] = []
    private var listConstraints: [NSLayoutConstraint] = []
    private var placeholderGridConstraints: [NSLayoutConstraint] = []
    private var placeholderListConstraints: [NSLayoutConstraint] = []
    private var representedEntryID: BoardListEntryID?
    private var representedBoardID: UUID?
    private var representedTitle: String?
    private var representedDisplayMode: BoardListDisplayMode?
    private var representedRevisionToken: String?
    private var thumbnailRequestToken: BoardPreviewRequestToken?
    private var onMoreActionsRequested: MoreActionsHandler?

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        setupConstraints()
        applyPresentationStyle(.boardGrid)
        updateSelectionAppearance()
    }

    override var isSelected: Bool {
        didSet {
            logSelectionTrace(
                "itemIsSelectedChanged",
                extra: "oldValue=\(oldValue) newValue=\(isSelected)"
            )
            updateSelectionAppearance()
        }
    }

    override var highlightState: NSCollectionViewItem.HighlightState {
        didSet {
            logSelectionTrace(
                "itemHighlightStateChanged",
                extra:
                    "oldValue=\(describeSelectionTraceHighlightState(oldValue)) " +
                    "newValue=\(describeSelectionTraceHighlightState(highlightState))"
            )
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        cancelThumbnailRequest()
        representedEntryID = nil
        representedBoardID = nil
        representedTitle = nil
        representedDisplayMode = nil
        representedRevisionToken = nil
        titleLabel.stringValue = ""
        previewView.isHidden = false
        placeholderIconView.isHidden = true
        moreButton.isHidden = true
        onMoreActionsRequested = nil
        previewView.apply(content: .empty)
    }

    func configure(
        with entry: BoardListEntry,
        previewContent: BoardPreviewContent,
        displayMode: BoardListDisplayMode,
        onMoreActionsRequested: MoreActionsHandler? = nil
    ) {
        cancelThumbnailRequest()
        representedEntryID = entry.id
        representedBoardID = entry.boardID
        representedTitle = entry.title
        representedDisplayMode = displayMode
        representedRevisionToken = entry.revisionToken
        self.onMoreActionsRequested = onMoreActionsRequested
        titleLabel.stringValue = entry.title
        previewView.apply(content: previewContent)
        applyPresentation(
            for: entry,
            displayMode: displayMode
        )
        view.layoutSubtreeIfNeeded()
    }

    func cancelThumbnailRequest() {
        thumbnailRequestToken?.cancel()
        thumbnailRequestToken = nil
    }

    func targetThumbnailPixelSize(
        for displayMode: BoardListDisplayMode
    ) -> CGSize {
        // Do not force layout here: collection view may ask for thumbnail size
        // before this item finishes switching away from the previous mode.
        let previewSize = resolvedPreviewViewSize(for: displayMode)
        let contentsScale = view.window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 2
        return CGSize(
            width: previewSize.width * contentsScale,
            height: previewSize.height * contentsScale
        )
    }

    func requestThumbnail(
        using previewProvider: BoardPreviewProvider,
        for item: BoardCatalogItem,
        displayMode: BoardListDisplayMode
    ) {
        cancelThumbnailRequest()

        thumbnailRequestToken = previewProvider.requestThumbnail(
            for: item,
            targetPixelSize: targetThumbnailPixelSize(for: displayMode)
        ) { [weak self] previewContent in
            guard
                let self,
                let previewContent,
                self.representedBoardID == item.boardID,
                self.representedRevisionToken == item.revisionToken
            else {
                return
            }

            self.previewView.apply(content: previewContent)
        }
    }

    private func setupView() {
        view.wantsLayer = true
        view.layer?.cornerRadius = 12
        view.layer?.masksToBounds = true

        previewView.translatesAutoresizingMaskIntoConstraints = false
        placeholderIconView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        moreButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(previewView)
        view.addSubview(placeholderIconView)
        view.addSubview(titleLabel)
        view.addSubview(moreButton)
        moreButton.target = self
        moreButton.action = #selector(handleMoreButtonClick(_:))
    }

    private func setupConstraints() {
        gridConstraints = [
            previewView.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            previewView.heightAnchor.constraint(equalToConstant: 120),
            moreButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            moreButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            moreButton.widthAnchor.constraint(equalToConstant: 32),
            moreButton.heightAnchor.constraint(equalToConstant: 32),
            titleLabel.topAnchor.constraint(equalTo: previewView.bottomAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -12)
        ]

        listConstraints = [
            previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            previewView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            previewView.widthAnchor.constraint(equalToConstant: 72),
            previewView.heightAnchor.constraint(equalToConstant: 72),
            titleLabel.leadingAnchor.constraint(equalTo: previewView.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: moreButton.leadingAnchor, constant: -8),
            titleLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            moreButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            moreButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            moreButton.widthAnchor.constraint(equalToConstant: 32),
            moreButton.heightAnchor.constraint(equalToConstant: 32)
        ]

        placeholderGridConstraints = [
            placeholderIconView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            placeholderIconView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            placeholderIconView.widthAnchor.constraint(equalToConstant: 22),
            placeholderIconView.heightAnchor.constraint(equalToConstant: 22),
            titleLabel.topAnchor.constraint(greaterThanOrEqualTo: placeholderIconView.bottomAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            titleLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12)
        ]

        placeholderListConstraints = [
            placeholderIconView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            placeholderIconView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            placeholderIconView.widthAnchor.constraint(equalToConstant: 22),
            placeholderIconView.heightAnchor.constraint(equalToConstant: 22),
            titleLabel.leadingAnchor.constraint(equalTo: placeholderIconView.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            titleLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ]
    }

    private func applyPresentation(
        for entry: BoardListEntry,
        displayMode: BoardListDisplayMode
    ) {
        applyPresentationStyle(
            resolvePresentationStyle(
                for: entry,
                displayMode: displayMode
            )
        )
    }

    private func resolvePresentationStyle(
        for entry: BoardListEntry,
        displayMode: BoardListDisplayMode
    ) -> PresentationStyle {
        switch (entry.isPlaceholder, displayMode) {
        case (false, .grid):
            return .boardGrid
        case (false, .list):
            return .boardList
        case (true, .grid):
            return .placeholderGrid
        case (true, .list):
            return .placeholderList
        }
    }

    private func applyPresentationStyle(_ presentationStyle: PresentationStyle) {
        NSLayoutConstraint.deactivate(
            gridConstraints +
                listConstraints +
                placeholderGridConstraints +
                placeholderListConstraints
        )

        previewView.isHidden = false
        placeholderIconView.isHidden = true
        moreButton.isHidden = true

        switch presentationStyle {
        case .boardGrid:
            titleLabel.alignment = .center
            moreButton.isHidden = false
            NSLayoutConstraint.activate(gridConstraints)
        case .boardList:
            titleLabel.alignment = .left
            moreButton.isHidden = false
            NSLayoutConstraint.activate(listConstraints)
        case .placeholderGrid:
            titleLabel.alignment = .center
            previewView.isHidden = true
            placeholderIconView.isHidden = false
            NSLayoutConstraint.activate(placeholderGridConstraints)
        case .placeholderList:
            titleLabel.alignment = .left
            previewView.isHidden = true
            placeholderIconView.isHidden = false
            NSLayoutConstraint.activate(placeholderListConstraints)
        }
    }

    private func updateSelectionAppearance() {
        let backgroundColor = isSelected
            ? NSColor.controlAccentColor.withAlphaComponent(0.14)
            : NSColor.controlBackgroundColor.withAlphaComponent(0.85)
        let borderColor = isSelected
            ? NSColor.controlAccentColor
            : NSColor.separatorColor.withAlphaComponent(0.55)

        view.layer?.backgroundColor = backgroundColor.cgColor
        view.layer?.borderColor = borderColor.cgColor
        view.layer?.borderWidth = isSelected ? 2 : 1
    }

    private func logSelectionTrace(_ phase: String, extra: String = "") {
        let extraSuffix = extra.isEmpty ? "" : " \(extra)"
        print(
            "[BoardList][macOS][SelectionTrace] " +
                "t=\(boardListSelectionTraceTimestamp()) " +
                "phase=\(phase) " +
                "entryID=\(describeSelectionTraceEntryID(representedEntryID)) " +
                "boardID=\(representedBoardID?.uuidString ?? "nil") " +
                "title=\"\(representedTitle ?? "")\" " +
                "displayMode=\(representedDisplayMode?.title ?? "nil") " +
                "isSelected=\(isSelected) " +
                "highlightState=\(describeSelectionTraceHighlightState(highlightState))" +
                extraSuffix
        )
    }

    private func describeSelectionTraceEntryID(_ entryID: BoardListEntryID?) -> String {
        guard let entryID else {
            return "nil"
        }

        switch entryID {
        case .newBoard:
            return "newBoard"
        case let .board(boardID):
            return "board(\(boardID.uuidString))"
        }
    }

    private func describeSelectionTraceHighlightState(
        _ highlightState: NSCollectionViewItem.HighlightState
    ) -> String {
        switch highlightState {
        case .none:
            return "none"
        case .forSelection:
            return "forSelection"
        case .forDeselection:
            return "forDeselection"
        case .asDropTarget:
            return "asDropTarget"
        @unknown default:
            return "unknown"
        }
    }

    private func resolvedPreviewViewSize(
        for displayMode: BoardListDisplayMode
    ) -> CGSize {
        switch displayMode {
        case .grid:
            return CGSize(
                width: max(view.bounds.width - 24, 120),
                height: 120
            )
        case .list:
            return CGSize(width: 72, height: 72)
        }
    }

    @objc
    private func handleMoreButtonClick(_ sender: NSButton) {
        guard let representedBoardID else {
            return
        }

        let anchorRect = view.convert(
            sender.bounds,
            from: sender
        )
        onMoreActionsRequested?(
            representedBoardID,
            anchorRect.standardized,
            view
        )
    }
}
#endif
