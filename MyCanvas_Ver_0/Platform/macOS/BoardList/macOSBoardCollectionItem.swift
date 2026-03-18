#if os(macOS)
import AppKit

final class macOSBoardCollectionItem: NSCollectionViewItem {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("macOSBoardCollectionItem")

    private let previewView = macOSBoardPreviewView()
    private let titleLabel: NSTextField = {
        let label = NSTextField(wrappingLabelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .labelColor
        label.maximumNumberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
        return label
    }()

    private var gridConstraints: [NSLayoutConstraint] = []
    private var listConstraints: [NSLayoutConstraint] = []

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupView()
        setupConstraints()
        applyDisplayMode(.grid)
        updateSelectionAppearance()
    }

    override var isSelected: Bool {
        didSet {
            updateSelectionAppearance()
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        titleLabel.stringValue = ""
        previewView.apply(content: .empty)
    }

    func configure(
        with item: BoardCatalogItem,
        previewContent: BoardPreviewContent,
        displayMode: BoardListDisplayMode
    ) {
        titleLabel.stringValue = item.title
        previewView.apply(content: previewContent)
        applyDisplayMode(displayMode)
    }

    private func setupView() {
        view.wantsLayer = true
        view.layer?.cornerRadius = 12
        view.layer?.masksToBounds = true

        previewView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(previewView)
        view.addSubview(titleLabel)
    }

    private func setupConstraints() {
        gridConstraints = [
            previewView.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            previewView.heightAnchor.constraint(equalToConstant: 120),
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
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            titleLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ]
    }

    private func applyDisplayMode(_ displayMode: BoardListDisplayMode) {
        NSLayoutConstraint.deactivate(gridConstraints + listConstraints)

        switch displayMode {
        case .grid:
            titleLabel.alignment = .center
            NSLayoutConstraint.activate(gridConstraints)
        case .list:
            titleLabel.alignment = .left
            NSLayoutConstraint.activate(listConstraints)
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
}
#endif
