#if os(macOS)
import AppKit

private func boardListSelectionTraceTimestamp() -> String {
    String(format: "%.3f", ProcessInfo.processInfo.systemUptime)
}

final class macOSBoardCollectionItem: NSCollectionViewItem, NSTextFieldDelegate {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("macOSBoardCollectionItem")

    typealias MoreActionsHandler = (UUID, CGRect, NSView) -> Void
    typealias RenameSubmitHandler = (UUID, String) -> Void
    typealias RenameCancelHandler = (UUID) -> Void

    private enum PresentationStyle {
        case boardGrid
        case boardList
        case placeholderGrid
        case placeholderList
    }

    private enum TitleEditEndDisposition {
        case unspecified
        case commit
        case cancel
    }

    private enum TitleEditTiming {
        static let initialFocusDelay: TimeInterval = 0.12
        static let refocusDelay: TimeInterval = 0.05
        static let stabilizationDelay: TimeInterval = 0.18
        static let maximumUnexpectedEndRetries = 1
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
    private let titleTextField: NSTextField = {
        let textField = NSTextField(string: "")
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.font = .systemFont(ofSize: 14, weight: .medium)
        textField.textColor = .labelColor
        textField.isHidden = true
        textField.lineBreakMode = .byTruncatingTail
        textField.maximumNumberOfLines = 1
        textField.usesSingleLineMode = true
        return textField
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
    private var onRenameSubmitted: RenameSubmitHandler?
    private var onRenameCancelled: RenameCancelHandler?
    private var currentPresentationStyle: PresentationStyle = .boardGrid
    private var isTitleEditingActive = false
    private var didHandleCurrentTitleEditEnd = false
    private var pendingTitleEditEndDisposition: TitleEditEndDisposition = .unspecified
    private var titleEditFocusRequestID = 0
    private var isAwaitingInitialFocusStabilization = false
    private var unexpectedInitialEndRetryCount = 0

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
        if isTitleEditingActive || representedBoardID != nil {
            logRenameTrace("prepareForReuse")
        }
        invalidateTitleEditingFocusRequests()
        cancelThumbnailRequest()
        representedEntryID = nil
        representedBoardID = nil
        representedTitle = nil
        representedDisplayMode = nil
        representedRevisionToken = nil
        titleLabel.stringValue = ""
        titleLabel.isHidden = false
        titleTextField.stringValue = ""
        titleTextField.isHidden = true
        previewView.isHidden = false
        placeholderIconView.isHidden = true
        moreButton.isHidden = true
        onMoreActionsRequested = nil
        onRenameSubmitted = nil
        onRenameCancelled = nil
        currentPresentationStyle = .boardGrid
        isTitleEditingActive = false
        didHandleCurrentTitleEditEnd = false
        pendingTitleEditEndDisposition = .unspecified
        unexpectedInitialEndRetryCount = 0
        previewView.apply(content: .empty)
    }

    func configure(
        with entry: BoardListEntry,
        previewContent: BoardPreviewContent,
        displayMode: BoardListDisplayMode,
        isEditingTitle: Bool = false,
        onMoreActionsRequested: MoreActionsHandler? = nil,
        onRenameSubmitted: RenameSubmitHandler? = nil,
        onRenameCancelled: RenameCancelHandler? = nil
    ) {
        cancelThumbnailRequest()
        representedEntryID = entry.id
        representedBoardID = entry.boardID
        representedTitle = entry.title
        representedDisplayMode = displayMode
        representedRevisionToken = entry.revisionToken
        self.onMoreActionsRequested = onMoreActionsRequested
        self.onRenameSubmitted = onRenameSubmitted
        self.onRenameCancelled = onRenameCancelled
        invalidateTitleEditingFocusRequests()
        isTitleEditingActive = isEditingTitle
        didHandleCurrentTitleEditEnd = false
        pendingTitleEditEndDisposition = .unspecified
        unexpectedInitialEndRetryCount = 0
        titleLabel.stringValue = entry.title
        titleTextField.stringValue = entry.title
        previewView.apply(content: previewContent)
        applyPresentation(
            for: entry,
            displayMode: displayMode
        )
        view.layoutSubtreeIfNeeded()
        logRenameTrace(
            "configure",
            extra:
                "displayMode=\(displayMode.title) " +
                "isEditingTitle=\(isEditingTitle)"
        )
    }

    func beginTitleEditing() {
        guard
            isTitleEditingActive,
            titleTextField.isHidden == false
        else {
            return
        }

        didHandleCurrentTitleEditEnd = false
        pendingTitleEditEndDisposition = .unspecified
        unexpectedInitialEndRetryCount = 0
        scheduleTitleEditingFocus(
            delay: TitleEditTiming.initialFocusDelay,
            reason: "initial"
        )
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
        titleTextField.translatesAutoresizingMaskIntoConstraints = false
        moreButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(previewView)
        view.addSubview(placeholderIconView)
        view.addSubview(titleLabel)
        view.addSubview(titleTextField)
        view.addSubview(moreButton)
        titleTextField.delegate = self
        moreButton.target = self
        moreButton.action = #selector(handleMoreButtonClick(_:))
    }

    private func setupConstraints() {
        gridConstraints = [
            previewView.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            previewView.heightAnchor.constraint(equalToConstant: 120),
            titleLabel.topAnchor.constraint(equalTo: previewView.bottomAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: moreButton.leadingAnchor, constant: -8),
            titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -12),
            moreButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            moreButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            moreButton.widthAnchor.constraint(equalToConstant: 32),
            moreButton.heightAnchor.constraint(equalToConstant: 32),
            titleTextField.topAnchor.constraint(equalTo: previewView.bottomAnchor, constant: 8),
            titleTextField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            titleTextField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            titleTextField.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -12)
        ]

        listConstraints = [
            previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            previewView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            previewView.widthAnchor.constraint(equalToConstant: 72),
            previewView.heightAnchor.constraint(equalToConstant: 72),
            titleLabel.leadingAnchor.constraint(equalTo: previewView.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: moreButton.leadingAnchor, constant: -8),
            titleLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            titleTextField.leadingAnchor.constraint(equalTo: previewView.trailingAnchor, constant: 12),
            titleTextField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            titleTextField.centerYAnchor.constraint(equalTo: view.centerYAnchor),
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
        currentPresentationStyle = presentationStyle
        NSLayoutConstraint.deactivate(
            gridConstraints +
                listConstraints +
                placeholderGridConstraints +
                placeholderListConstraints
        )

        previewView.isHidden = false
        placeholderIconView.isHidden = true
        moreButton.isHidden = true
        titleLabel.isHidden = false
        titleTextField.isHidden = true

        switch presentationStyle {
        case .boardGrid:
            titleLabel.alignment = .left
            titleTextField.alignment = .left
            moreButton.isHidden = false
            NSLayoutConstraint.activate(gridConstraints)
        case .boardList:
            titleLabel.alignment = .left
            titleTextField.alignment = .left
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

        applyTitleEditingAppearance()
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

    private func applyTitleEditingAppearance() {
        let isEditablePresentation: Bool
        switch currentPresentationStyle {
        case .boardGrid, .boardList:
            isEditablePresentation = true
        case .placeholderGrid, .placeholderList:
            isEditablePresentation = false
        }

        let shouldShowTitleEditor = isTitleEditingActive && isEditablePresentation
        titleLabel.isHidden = shouldShowTitleEditor
        titleTextField.isHidden = !shouldShowTitleEditor
        logRenameTrace(
            "applyTitleEditingAppearance",
            extra: "shouldShowTitleEditor=\(shouldShowTitleEditor)"
        )

        if shouldShowTitleEditor {
            moreButton.isHidden = true
            titleTextField.stringValue = representedTitle ?? ""
            return
        }

        moreButton.isHidden = onMoreActionsRequested == nil
    }

    private func commitTitleEditIfNeeded() {
        guard
            isTitleEditingActive,
            didHandleCurrentTitleEditEnd == false,
            let representedBoardID
        else {
            logRenameTrace("commitTitleEditIgnored")
            return
        }

        invalidateTitleEditingFocusRequests()
        didHandleCurrentTitleEditEnd = true
        logRenameTrace("commitTitleEdit")
        onRenameSubmitted?(representedBoardID, titleTextField.stringValue)
    }

    private func cancelTitleEditIfNeeded() {
        guard
            isTitleEditingActive,
            didHandleCurrentTitleEditEnd == false,
            let representedBoardID
        else {
            logRenameTrace("cancelTitleEditIgnored")
            return
        }

        invalidateTitleEditingFocusRequests()
        didHandleCurrentTitleEditEnd = true
        logRenameTrace("cancelTitleEdit")
        onRenameCancelled?(representedBoardID)
    }

    private func scheduleTitleEditingFocus(
        delay: TimeInterval,
        reason: String
    ) {
        titleEditFocusRequestID += 1
        let requestID = titleEditFocusRequestID
        isAwaitingInitialFocusStabilization = true
        pendingTitleEditEndDisposition = .unspecified
        logRenameTrace(
            "scheduleTitleEditingFocus",
            extra:
                "requestID=\(requestID) " +
                "delay=\(String(format: "%.2f", delay)) " +
                "reason=\(reason)"
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard
                let self,
                self.titleEditFocusRequestID == requestID,
                self.isTitleEditingActive,
                self.titleTextField.isHidden == false
            else {
                self?.logRenameTrace(
                    "scheduleTitleEditingFocusAborted",
                    extra:
                        "requestID=\(requestID) " +
                        "reason=\(reason)"
                )
                return
            }

            self.logRenameTrace(
                "performTitleEditingFocus",
                extra:
                    "requestID=\(requestID) " +
                    "reason=\(reason)"
            )
            self.view.window?.makeFirstResponder(self.titleTextField)

            DispatchQueue.main.async { [weak self] in
                guard
                    let self,
                    self.titleEditFocusRequestID == requestID
                else {
                    return
                }

                (self.view.window?.fieldEditor(true, for: self.titleTextField) as? NSTextView)?
                    .selectAll(nil)
            }
        }
    }

    private func scheduleRefocusAfterUnexpectedInitialEnd() {
        logRenameTrace(
            "scheduleRefocusAfterUnexpectedInitialEnd",
            extra: "retryCount=\(unexpectedInitialEndRetryCount)"
        )
        scheduleTitleEditingFocus(
            delay: TitleEditTiming.refocusDelay,
            reason: "unexpectedInitialEnd"
        )
    }

    private func invalidateTitleEditingFocusRequests() {
        titleEditFocusRequestID += 1
        isAwaitingInitialFocusStabilization = false
    }

    private func logRenameTrace(_ phase: String, extra: String = "") {
        let extraSuffix = extra.isEmpty ? "" : " \(extra)"
        let isFirstResponder = view.window?.firstResponder === titleTextField
        print(
            "[BoardList][macOS][RenameTrace][Item] " +
                "t=\(boardListSelectionTraceTimestamp()) " +
                "phase=\(phase) " +
                "boardID=\(representedBoardID?.uuidString ?? "nil") " +
                "representedTitle=\"\(representedTitle ?? "")\" " +
                "textFieldText=\"\(titleTextField.stringValue)\" " +
                "editing=\(isTitleEditingActive) " +
                "textFieldHidden=\(titleTextField.isHidden) " +
                "isFirstResponder=\(isFirstResponder) " +
                "isAwaitingInitialFocusStabilization=\(isAwaitingInitialFocusStabilization)" +
                extraSuffix
        )
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

    func controlTextDidBeginEditing(_ obj: Notification) {
        guard obj.object as AnyObject? === titleTextField else {
            return
        }

        let requestID = titleEditFocusRequestID
        logRenameTrace("controlTextDidBeginEditing", extra: "requestID=\(requestID)")
        DispatchQueue.main.asyncAfter(deadline: .now() + TitleEditTiming.stabilizationDelay) { [weak self] in
            guard
                let self,
                self.titleEditFocusRequestID == requestID,
                self.isTitleEditingActive
            else {
                return
            }

            self.isAwaitingInitialFocusStabilization = false
            self.logRenameTrace(
                "titleEditingFocusStabilized",
                extra: "requestID=\(requestID)"
            )
        }
    }

    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            logRenameTrace("doCommandInsertNewline")
            pendingTitleEditEndDisposition = .commit
            view.window?.makeFirstResponder(nil)
            return true
        }

        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            logRenameTrace("doCommandCancelOperation")
            pendingTitleEditEndDisposition = .cancel
            view.window?.makeFirstResponder(nil)
            return true
        }

        return false
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard obj.object as AnyObject? === titleTextField else {
            return
        }

        let disposition = pendingTitleEditEndDisposition
        pendingTitleEditEndDisposition = .unspecified
        logRenameTrace("controlTextDidEndEditing", extra: "disposition=\(String(describing: disposition))")

        switch disposition {
        case .commit:
            commitTitleEditIfNeeded()
        case .unspecified:
            if isAwaitingInitialFocusStabilization,
               unexpectedInitialEndRetryCount < TitleEditTiming.maximumUnexpectedEndRetries {
                unexpectedInitialEndRetryCount += 1
                logRenameTrace(
                    "controlTextDidEndEditingIgnoredDuringStabilization",
                    extra: "retryCount=\(unexpectedInitialEndRetryCount)"
                )
                scheduleRefocusAfterUnexpectedInitialEnd()
                return
            }

            commitTitleEditIfNeeded()
        case .cancel:
            cancelTitleEditIfNeeded()
        }
    }
}
#endif
