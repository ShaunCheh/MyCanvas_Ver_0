#if os(iOS)
import UIKit

final class iOSBoardCollectionViewCell: UICollectionViewCell {
    static let reuseIdentifier = "iOSBoardCollectionViewCell"

    typealias MoreActionsHandler = (UUID, CGRect, UIView) -> Void

    private enum PresentationStyle {
        case boardGrid
        case boardList
        case placeholderGrid
        case placeholderList
    }

    private let previewView = iOSBoardPreviewView()
    private let placeholderIconView: UIImageView = {
        let configuration = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        let imageView = UIImageView(
            image: UIImage(
                systemName: "plus",
                withConfiguration: configuration
            )
        )
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = .systemBlue
        imageView.isHidden = true
        return imageView
    }()
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .label
        label.numberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
        return label
    }()
    private let moreButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityLabel = "More Actions"
        button.tintColor = .secondaryLabel

        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "ellipsis")
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: 6,
            leading: 6,
            bottom: 6,
            trailing: 6
        )
        configuration.baseForegroundColor = .secondaryLabel
        button.configuration = configuration
        return button
    }()

    private var gridConstraints: [NSLayoutConstraint] = []
    private var listConstraints: [NSLayoutConstraint] = []
    private var placeholderGridConstraints: [NSLayoutConstraint] = []
    private var placeholderListConstraints: [NSLayoutConstraint] = []
    private var representedBoardID: UUID?
    private var representedRevisionToken: String?
    private var thumbnailRequestToken: BoardPreviewRequestToken?
    private var onMoreActionsRequested: MoreActionsHandler?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
        setupConstraints()
        applyPresentationStyle(.boardGrid)
        updateSelectionAppearance()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override var isSelected: Bool {
        didSet {
            updateSelectionAppearance()
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        cancelThumbnailRequest()
        representedBoardID = nil
        representedRevisionToken = nil
        titleLabel.text = nil
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
        representedBoardID = entry.boardID
        representedRevisionToken = entry.revisionToken
        titleLabel.text = entry.title
        self.onMoreActionsRequested = onMoreActionsRequested
        previewView.apply(content: previewContent)
        applyPresentation(
            for: entry,
            displayMode: displayMode
        )
        contentView.layoutIfNeeded()
    }

    func cancelThumbnailRequest() {
        thumbnailRequestToken?.cancel()
        thumbnailRequestToken = nil
    }

    func targetThumbnailPixelSize(
        for displayMode: BoardListDisplayMode
    ) -> CGSize {
        // Keep this purely calculative so display-mode transitions do not force
        // Auto Layout to solve against the previous presentation style.
        let previewSize = resolvedPreviewViewSize(for: displayMode)
        let contentsScale = window?.screen.scale ?? UIScreen.main.scale
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
        contentView.layer.cornerRadius = 12
        contentView.layer.masksToBounds = true

        previewView.translatesAutoresizingMaskIntoConstraints = false
        placeholderIconView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        moreButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(previewView)
        contentView.addSubview(placeholderIconView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(moreButton)
        contentView.bringSubviewToFront(moreButton)
        moreButton.addTarget(self, action: #selector(handleMoreButtonTap), for: .touchUpInside)
    }

    private func setupConstraints() {
        gridConstraints = [
            previewView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            previewView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            previewView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            previewView.heightAnchor.constraint(equalToConstant: 120),
            moreButton.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            moreButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            moreButton.widthAnchor.constraint(equalToConstant: 32),
            moreButton.heightAnchor.constraint(equalToConstant: 32),
            titleLabel.topAnchor.constraint(equalTo: previewView.bottomAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -12)
        ]

        listConstraints = [
            previewView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            previewView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            previewView.widthAnchor.constraint(equalToConstant: 72),
            previewView.heightAnchor.constraint(equalToConstant: 72),
            titleLabel.leadingAnchor.constraint(equalTo: previewView.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: moreButton.leadingAnchor, constant: -8),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            moreButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            moreButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            moreButton.widthAnchor.constraint(equalToConstant: 32),
            moreButton.heightAnchor.constraint(equalToConstant: 32)
        ]

        placeholderGridConstraints = [
            placeholderIconView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            placeholderIconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            placeholderIconView.widthAnchor.constraint(equalToConstant: 22),
            placeholderIconView.heightAnchor.constraint(equalToConstant: 22),
            titleLabel.topAnchor.constraint(greaterThanOrEqualTo: placeholderIconView.bottomAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            titleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ]

        placeholderListConstraints = [
            placeholderIconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            placeholderIconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            placeholderIconView.widthAnchor.constraint(equalToConstant: 22),
            placeholderIconView.heightAnchor.constraint(equalToConstant: 22),
            titleLabel.leadingAnchor.constraint(equalTo: placeholderIconView.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
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
            titleLabel.textAlignment = .center
            moreButton.isHidden = false
            NSLayoutConstraint.activate(gridConstraints)
        case .boardList:
            titleLabel.textAlignment = .left
            moreButton.isHidden = false
            NSLayoutConstraint.activate(listConstraints)
        case .placeholderGrid:
            titleLabel.textAlignment = .center
            previewView.isHidden = true
            placeholderIconView.isHidden = false
            NSLayoutConstraint.activate(placeholderGridConstraints)
        case .placeholderList:
            titleLabel.textAlignment = .left
            previewView.isHidden = true
            placeholderIconView.isHidden = false
            NSLayoutConstraint.activate(placeholderListConstraints)
        }
    }

    private func updateSelectionAppearance() {
        contentView.backgroundColor = isSelected
            ? UIColor.systemBlue.withAlphaComponent(0.14)
            : UIColor.secondarySystemBackground
        contentView.layer.borderColor = (isSelected
            ? UIColor.systemBlue
            : UIColor.separator.withAlphaComponent(0.55)).cgColor
        contentView.layer.borderWidth = isSelected ? 2 : 1
    }

    private func resolvedPreviewViewSize(
        for displayMode: BoardListDisplayMode
    ) -> CGSize {
        switch displayMode {
        case .grid:
            return CGSize(
                width: max(contentView.bounds.width - 24, 120),
                height: 120
            )
        case .list:
            return CGSize(width: 72, height: 72)
        }
    }

    @objc
    private func handleMoreButtonTap() {
        guard let representedBoardID else {
            return
        }

        let anchorRect = contentView.convert(
            moreButton.bounds,
            from: moreButton
        )
        onMoreActionsRequested?(
            representedBoardID,
            anchorRect.standardized,
            contentView
        )
    }
}
#endif
