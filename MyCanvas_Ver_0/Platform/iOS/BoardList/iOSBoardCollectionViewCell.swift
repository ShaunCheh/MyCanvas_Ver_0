#if os(iOS)
import UIKit

final class iOSBoardCollectionViewCell: UICollectionViewCell {
    static let reuseIdentifier = "iOSBoardCollectionViewCell"

    private let previewView = iOSBoardPreviewView()
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .label
        label.numberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
        return label
    }()

    private var gridConstraints: [NSLayoutConstraint] = []
    private var listConstraints: [NSLayoutConstraint] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
        setupConstraints()
        applyDisplayMode(.grid)
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
        titleLabel.text = nil
        previewView.apply(content: .empty)
    }

    func configure(
        with item: BoardCatalogItem,
        previewContent: BoardPreviewContent,
        displayMode: BoardListDisplayMode
    ) {
        titleLabel.text = item.title
        previewView.apply(content: previewContent)
        applyDisplayMode(displayMode)
    }

    private func setupView() {
        contentView.layer.cornerRadius = 12
        contentView.layer.masksToBounds = true

        previewView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(previewView)
        contentView.addSubview(titleLabel)
    }

    private func setupConstraints() {
        gridConstraints = [
            previewView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            previewView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            previewView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            previewView.heightAnchor.constraint(equalToConstant: 120),
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
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ]
    }

    private func applyDisplayMode(_ displayMode: BoardListDisplayMode) {
        NSLayoutConstraint.deactivate(gridConstraints + listConstraints)

        switch displayMode {
        case .grid:
            titleLabel.textAlignment = .center
            NSLayoutConstraint.activate(gridConstraints)
        case .list:
            titleLabel.textAlignment = .left
            NSLayoutConstraint.activate(listConstraints)
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
}
#endif
