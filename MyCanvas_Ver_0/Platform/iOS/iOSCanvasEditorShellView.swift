#if os(iOS)
import UIKit

enum iOSCanvasEditorShellTitleAlignment {
    case centered
    case leading
}

final class iOSCanvasEditorShellView: UIView {
    private enum Layout {
        static let titleTopInset: CGFloat = 20
        static let horizontalInset: CGFloat = 24
        static let titleAccessorySpacing: CGFloat = 12
    }

    let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 28, weight: .semibold)
        return label
    }()

    let leadingButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        var configuration = UIButton.Configuration.plain()
        configuration.title = ""
        button.configuration = configuration
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        return button
    }()

    let trailingButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        return button
    }()

    let contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private var contentTopToTitleConstraint: NSLayoutConstraint!
    private var leadingButtonZeroWidthConstraint: NSLayoutConstraint!
    private var leadingButtonZeroHeightConstraint: NSLayoutConstraint!
    private var trailingButtonZeroWidthConstraint: NSLayoutConstraint!
    private var trailingButtonZeroHeightConstraint: NSLayoutConstraint!
    private var centeredTitleConstraints: [NSLayoutConstraint] = []
    private var leadingTitleConstraints: [NSLayoutConstraint] = []
    private var titleAlignment: iOSCanvasEditorShellTitleAlignment

    init(
        titleAlignment: iOSCanvasEditorShellTitleAlignment
    ) {
        self.titleAlignment = titleAlignment
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .systemBackground
        addSubview(titleLabel)
        addSubview(leadingButton)
        addSubview(trailingButton)
        addSubview(contentView)

        contentTopToTitleConstraint = contentView.topAnchor.constraint(
            equalTo: titleLabel.bottomAnchor
        )
        contentTopToTitleConstraint.priority = .defaultHigh
        leadingButtonZeroWidthConstraint = leadingButton.widthAnchor.constraint(
            equalToConstant: 0
        )
        leadingButtonZeroHeightConstraint = leadingButton.heightAnchor.constraint(
            equalToConstant: 0
        )
        trailingButtonZeroWidthConstraint = trailingButton.widthAnchor.constraint(
            equalToConstant: 0
        )
        trailingButtonZeroHeightConstraint = trailingButton.heightAnchor.constraint(
            equalToConstant: 0
        )

        let centeredTitleCenterConstraint = titleLabel.centerXAnchor.constraint(
            equalTo: safeAreaLayoutGuide.centerXAnchor
        )
        let centeredTitleLeadingConstraint = titleLabel.leadingAnchor.constraint(
            greaterThanOrEqualTo: leadingButton.trailingAnchor,
            constant: Layout.titleAccessorySpacing
        )
        let centeredTitleTrailingConstraint = titleLabel.trailingAnchor.constraint(
            lessThanOrEqualTo: trailingButton.leadingAnchor,
            constant: -Layout.titleAccessorySpacing
        )
        centeredTitleConstraints = [
            centeredTitleCenterConstraint,
            centeredTitleLeadingConstraint,
            centeredTitleTrailingConstraint
        ]

        let leadingTitleLeadingConstraint = titleLabel.leadingAnchor.constraint(
            equalTo: safeAreaLayoutGuide.leadingAnchor,
            constant: Layout.horizontalInset
        )
        let leadingTitleTrailingConstraint = titleLabel.trailingAnchor.constraint(
            lessThanOrEqualTo: trailingButton.leadingAnchor,
            constant: -Layout.titleAccessorySpacing
        )
        leadingTitleConstraints = [
            leadingTitleLeadingConstraint,
            leadingTitleTrailingConstraint
        ]

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(
                equalTo: safeAreaLayoutGuide.topAnchor,
                constant: Layout.titleTopInset
            ),
            leadingButton.leadingAnchor.constraint(
                equalTo: safeAreaLayoutGuide.leadingAnchor,
                constant: Layout.horizontalInset
            ),
            leadingButton.centerYAnchor.constraint(
                equalTo: titleLabel.centerYAnchor
            ),
            trailingButton.trailingAnchor.constraint(
                equalTo: safeAreaLayoutGuide.trailingAnchor,
                constant: -Layout.horizontalInset
            ),
            trailingButton.centerYAnchor.constraint(
                equalTo: titleLabel.centerYAnchor
            ),
            contentTopToTitleConstraint,
            contentView.topAnchor.constraint(
                greaterThanOrEqualTo: leadingButton.bottomAnchor
            ),
            contentView.topAnchor.constraint(
                greaterThanOrEqualTo: trailingButton.bottomAnchor
            ),
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        updateTitleAlignment()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configureTitle(
        _ title: String,
        alignment: iOSCanvasEditorShellTitleAlignment
    ) {
        titleLabel.text = title
        titleAlignment = alignment
        updateTitleAlignment()
    }

    func setLeadingButtonHidden(_ hidden: Bool) {
        leadingButton.isHidden = hidden
        leadingButtonZeroWidthConstraint.isActive = hidden
        leadingButtonZeroHeightConstraint.isActive = hidden
    }

    func setTrailingButtonHidden(_ hidden: Bool) {
        trailingButton.isHidden = hidden
        trailingButtonZeroWidthConstraint.isActive = hidden
        trailingButtonZeroHeightConstraint.isActive = hidden
    }

    private func updateTitleAlignment() {
        switch titleAlignment {
        case .centered:
            NSLayoutConstraint.deactivate(leadingTitleConstraints)
            NSLayoutConstraint.activate(centeredTitleConstraints)
            titleLabel.textAlignment = .center
        case .leading:
            NSLayoutConstraint.deactivate(centeredTitleConstraints)
            NSLayoutConstraint.activate(leadingTitleConstraints)
            titleLabel.textAlignment = .left
        }
    }
}
#endif
