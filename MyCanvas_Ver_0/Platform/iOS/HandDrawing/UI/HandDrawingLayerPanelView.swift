#if os(iOS)
import UIKit

final class HandDrawingLayerPanelView: UIView {
    fileprivate enum Layout {
        static let panelInset: CGFloat = 14
        static let sectionSpacing: CGFloat = 12
        static let rowSpacing: CGFloat = 10
        static let controlSpacing: CGFloat = 6
        static let cornerRadius: CGFloat = 18
        static let controlButtonSize: CGFloat = 30
        static let maxListHeight: CGFloat = 320
    }

    var onAddLayer: (() -> Void)?
    var onSelectLayer: ((UUID) -> Void)?
    var onRequestRenameLayer: ((HandDrawingLayerPanelRowState) -> Void)?
    var onMoveLayerUp: ((UUID) -> Void)?
    var onMoveLayerDown: ((UUID) -> Void)?
    var onToggleVisibility: ((UUID) -> Void)?
    var onToggleLock: ((UUID) -> Void)?
    var onDeleteLayer: ((UUID) -> Void)?

    private let rootStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = Layout.sectionSpacing
        return stackView
    }()
    private let headerStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = Layout.sectionSpacing
        return stackView
    }()
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 18, weight: .semibold)
        label.text = "Layers"
        return label
    }()
    private let addButton = HandDrawingLayerPanelView.makeActionButton(
        title: "Add Layer",
        systemImageName: "plus"
    )
    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = true
        return scrollView
    }()
    private let rowsStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = Layout.rowSpacing
        return stackView
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = Layout.cornerRadius
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = UIColor.separator.withAlphaComponent(0.18).cgColor
        setupViewHierarchy()
        setupConstraints()
        bindActions()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(state: HandDrawingLayerPanelState) {
        addButton.isEnabled = state.canAddLayer
        addButton.alpha = state.canAddLayer ? 1 : 0.5
        rebuildRows(with: state.layers)
    }

    private func setupViewHierarchy() {
        addSubview(rootStackView)
        addSubview(scrollView)
        headerStackView.addArrangedSubview(titleLabel)
        headerStackView.addArrangedSubview(UIView())
        headerStackView.addArrangedSubview(addButton)
        rootStackView.addArrangedSubview(headerStackView)
        scrollView.addSubview(rowsStackView)
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            rootStackView.topAnchor.constraint(equalTo: topAnchor, constant: Layout.panelInset),
            rootStackView.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: Layout.panelInset
            ),
            rootStackView.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -Layout.panelInset
            ),
            scrollView.topAnchor.constraint(
                equalTo: rootStackView.bottomAnchor,
                constant: Layout.sectionSpacing
            ),
            scrollView.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: Layout.panelInset
            ),
            scrollView.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -Layout.panelInset
            ),
            scrollView.bottomAnchor.constraint(
                equalTo: bottomAnchor,
                constant: -Layout.panelInset
            ),
            scrollView.heightAnchor.constraint(
                lessThanOrEqualToConstant: Layout.maxListHeight
            ),
            rowsStackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            rowsStackView.leadingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.leadingAnchor
            ),
            rowsStackView.trailingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.trailingAnchor
            ),
            rowsStackView.bottomAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.bottomAnchor
            ),
            rowsStackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])
    }

    private func bindActions() {
        addButton.addTarget(
            self,
            action: #selector(handleAddButtonTap),
            for: .touchUpInside
        )
    }

    private func rebuildRows(with rows: [HandDrawingLayerPanelRowState]) {
        rowsStackView.arrangedSubviews.forEach { arrangedSubview in
            rowsStackView.removeArrangedSubview(arrangedSubview)
            arrangedSubview.removeFromSuperview()
        }

        for rowState in rows {
            let rowView = LayerRowView()
            rowView.apply(state: rowState)
            rowView.onSelectLayer = { [weak self] layerID in
                self?.onSelectLayer?(layerID)
            }
            rowView.onRequestRenameLayer = { [weak self] rowState in
                self?.onRequestRenameLayer?(rowState)
            }
            rowView.onMoveLayerUp = { [weak self] layerID in
                self?.onMoveLayerUp?(layerID)
            }
            rowView.onMoveLayerDown = { [weak self] layerID in
                self?.onMoveLayerDown?(layerID)
            }
            rowView.onToggleVisibility = { [weak self] layerID in
                self?.onToggleVisibility?(layerID)
            }
            rowView.onToggleLock = { [weak self] layerID in
                self?.onToggleLock?(layerID)
            }
            rowView.onDeleteLayer = { [weak self] layerID in
                self?.onDeleteLayer?(layerID)
            }
            rowsStackView.addArrangedSubview(rowView)
        }
    }

    @objc
    private func handleAddButtonTap() {
        onAddLayer?()
    }

    fileprivate static func makeActionButton(
        title: String,
        systemImageName: String
    ) -> UIButton {
        var configuration = UIButton.Configuration.tinted()
        configuration.title = title
        configuration.image = UIImage(systemName: systemImageName)
        configuration.imagePadding = 6
        configuration.cornerStyle = .medium
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.configuration = configuration
        return button
    }

    fileprivate static func makeIconButton() -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.contentInsets = .zero
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.configuration = configuration
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: Layout.controlButtonSize),
            button.heightAnchor.constraint(equalToConstant: Layout.controlButtonSize)
        ])
        return button
    }
}

private final class LayerRowView: UIView {
    var onSelectLayer: ((UUID) -> Void)?
    var onRequestRenameLayer: ((HandDrawingLayerPanelRowState) -> Void)?
    var onMoveLayerUp: ((UUID) -> Void)?
    var onMoveLayerDown: ((UUID) -> Void)?
    var onToggleVisibility: ((UUID) -> Void)?
    var onToggleLock: ((UUID) -> Void)?
    var onDeleteLayer: ((UUID) -> Void)?

    private let rowStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = HandDrawingLayerPanelView.Layout.controlSpacing
        return stackView
    }()
    private let selectButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.contentHorizontalAlignment = .leading
        return button
    }()
    private let visibilityButton = HandDrawingLayerPanelView.makeIconButton()
    private let lockButton = HandDrawingLayerPanelView.makeIconButton()
    private let renameButton = HandDrawingLayerPanelView.makeIconButton()
    private let moveUpButton = HandDrawingLayerPanelView.makeIconButton()
    private let moveDownButton = HandDrawingLayerPanelView.makeIconButton()
    private let deleteButton = HandDrawingLayerPanelView.makeIconButton()

    private var state: HandDrawingLayerPanelRowState?

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        setupViewHierarchy()
        setupConstraints()
        bindActions()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(state: HandDrawingLayerPanelRowState) {
        self.state = state

        var selectionConfiguration = UIButton.Configuration.tinted()
        selectionConfiguration.title = state.name
        selectionConfiguration.subtitle = state.subtitle
        selectionConfiguration.titleAlignment = .leading
        selectionConfiguration.image = UIImage(
            systemName: state.isActive ? "checkmark.circle.fill" : "circle"
        )
        selectionConfiguration.imagePadding = 8
        selectionConfiguration.cornerStyle = .medium
        selectionConfiguration.baseBackgroundColor = state.isActive
            ? .systemBlue
            : .tertiarySystemBackground
        selectionConfiguration.baseForegroundColor = state.isActive
            ? .white
            : .label
        selectButton.configuration = selectionConfiguration

        updateIconButton(
            visibilityButton,
            systemImageName: state.isVisible ? "eye" : "eye.slash",
            tintColor: state.isVisible ? .secondaryLabel : .systemOrange,
            isEnabled: true
        )
        updateIconButton(
            lockButton,
            systemImageName: state.isLocked ? "lock.fill" : "lock.open",
            tintColor: state.isLocked ? .systemOrange : .secondaryLabel,
            isEnabled: true
        )
        updateIconButton(
            renameButton,
            systemImageName: "pencil",
            tintColor: .secondaryLabel,
            isEnabled: true
        )
        updateIconButton(
            moveUpButton,
            systemImageName: "arrow.up",
            tintColor: .secondaryLabel,
            isEnabled: state.canMoveUp
        )
        updateIconButton(
            moveDownButton,
            systemImageName: "arrow.down",
            tintColor: .secondaryLabel,
            isEnabled: state.canMoveDown
        )
        updateIconButton(
            deleteButton,
            systemImageName: "trash",
            tintColor: .systemRed,
            isEnabled: state.canDelete
        )
    }

    private func setupViewHierarchy() {
        addSubview(rowStackView)
        [selectButton, visibilityButton, lockButton, renameButton, moveUpButton, moveDownButton, deleteButton]
            .forEach(rowStackView.addArrangedSubview)
        selectButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        selectButton.setContentHuggingPriority(.defaultLow, for: .horizontal)
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            rowStackView.topAnchor.constraint(equalTo: topAnchor),
            rowStackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            rowStackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            rowStackView.bottomAnchor.constraint(equalTo: bottomAnchor),
            selectButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
    }

    private func bindActions() {
        selectButton.addTarget(
            self,
            action: #selector(handleSelectTap),
            for: .touchUpInside
        )
        visibilityButton.addTarget(
            self,
            action: #selector(handleVisibilityTap),
            for: .touchUpInside
        )
        lockButton.addTarget(
            self,
            action: #selector(handleLockTap),
            for: .touchUpInside
        )
        renameButton.addTarget(
            self,
            action: #selector(handleRenameTap),
            for: .touchUpInside
        )
        moveUpButton.addTarget(
            self,
            action: #selector(handleMoveUpTap),
            for: .touchUpInside
        )
        moveDownButton.addTarget(
            self,
            action: #selector(handleMoveDownTap),
            for: .touchUpInside
        )
        deleteButton.addTarget(
            self,
            action: #selector(handleDeleteTap),
            for: .touchUpInside
        )
    }

    private func updateIconButton(
        _ button: UIButton,
        systemImageName: String,
        tintColor: UIColor,
        isEnabled: Bool
    ) {
        var configuration = button.configuration ?? UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: systemImageName)
        configuration.baseForegroundColor = tintColor
        button.configuration = configuration
        button.isEnabled = isEnabled
        button.alpha = isEnabled ? 1 : 0.35
    }

    @objc
    private func handleSelectTap() {
        guard let layerID = state?.id else {
            return
        }
        onSelectLayer?(layerID)
    }

    @objc
    private func handleVisibilityTap() {
        guard let layerID = state?.id else {
            return
        }
        onToggleVisibility?(layerID)
    }

    @objc
    private func handleLockTap() {
        guard let layerID = state?.id else {
            return
        }
        onToggleLock?(layerID)
    }

    @objc
    private func handleRenameTap() {
        guard let state else {
            return
        }
        onRequestRenameLayer?(state)
    }

    @objc
    private func handleMoveUpTap() {
        guard let layerID = state?.id else {
            return
        }
        onMoveLayerUp?(layerID)
    }

    @objc
    private func handleMoveDownTap() {
        guard let layerID = state?.id else {
            return
        }
        onMoveLayerDown?(layerID)
    }

    @objc
    private func handleDeleteTap() {
        guard let layerID = state?.id else {
            return
        }
        onDeleteLayer?(layerID)
    }
}
#endif
