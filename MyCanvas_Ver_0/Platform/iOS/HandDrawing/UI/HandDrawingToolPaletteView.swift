#if os(iOS)
import UIKit

final class HandDrawingToolPaletteView: UIView {
    fileprivate enum Layout {
        static let sectionSpacing: CGFloat = 12
        static let itemSpacing: CGFloat = 8
        static let cornerRadius: CGFloat = 18
        static let colorSwatchSize: CGFloat = 30
    }

    var onSelectTool: ((HandDrawingEditorTool) -> Void)?
    var onSelectColor: ((HandDrawingColor) -> Void)?
    var onSelectLineWidth: ((CGFloat) -> Void)?
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    var onDeselectSelection: (() -> Void)?

    private let rootStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = Layout.sectionSpacing
        return stackView
    }()
    private let toolStackView = HandDrawingToolPaletteView.makeHorizontalStack()
    private let colorStackView = HandDrawingToolPaletteView.makeHorizontalStack()
    private let lineWidthStackView = HandDrawingToolPaletteView.makeHorizontalStack()
    private let historyStackView = HandDrawingToolPaletteView.makeHorizontalStack()
    private let brushButton = HandDrawingToolPaletteView.makeActionButton(title: "Brush")
    private let eraserButton = HandDrawingToolPaletteView.makeActionButton(title: "Eraser")
    private let lassoButton = HandDrawingToolPaletteView.makeActionButton(title: "Lasso")
    private let deselectButton = HandDrawingToolPaletteView.makeActionButton(title: "Deselect")
    private let undoButton = HandDrawingToolPaletteView.makeActionButton(title: "Undo")
    private let redoButton = HandDrawingToolPaletteView.makeActionButton(title: "Redo")

    private var colorButtons: [ColorSwatchButton] = []
    private var lineWidthButtons: [UIButton] = []
    private var currentColors: [HandDrawingColor] = []
    private var currentLineWidths: [CGFloat] = []

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

    func apply(state: HandDrawingToolPaletteState) {
        rebuildColorButtonsIfNeeded(colors: state.availableColors)
        rebuildLineWidthButtonsIfNeeded(lineWidths: state.availableLineWidths)
        updateToolButtonSelection(
            brushButton,
            isSelected: state.selectedTool == .brush,
            isEnabled: state.isBrushEnabled
        )
        updateToolButtonSelection(
            eraserButton,
            isSelected: state.selectedTool == .pixelEraser,
            isEnabled: state.isPixelEraserEnabled
        )
        updateToolButtonSelection(
            lassoButton,
            isSelected: state.selectedTool == .lasso,
            isEnabled: state.isLassoEnabled
        )
        updateToolButtonSelection(
            deselectButton,
            isSelected: false,
            isEnabled: state.canDeselectSelection
        )
        undoButton.isEnabled = state.canUndo
        redoButton.isEnabled = state.canRedo

        for (index, colorButton) in colorButtons.enumerated() {
            guard currentColors.indices.contains(index) else {
                continue
            }
            colorButton.isSelected = currentColors[index] == state.selectedColor
        }

        for (index, button) in lineWidthButtons.enumerated() {
            guard currentLineWidths.indices.contains(index) else {
                continue
            }
            button.isSelected = currentLineWidths[index] == state.selectedLineWidth
            button.configurationUpdateHandler?(button)
        }
    }

    private func setupViewHierarchy() {
        addSubview(rootStackView)
        [brushButton, eraserButton, lassoButton].forEach(toolStackView.addArrangedSubview)
        [deselectButton, undoButton, redoButton].forEach(historyStackView.addArrangedSubview)
        [toolStackView, colorStackView, lineWidthStackView, historyStackView]
            .forEach(rootStackView.addArrangedSubview)
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            rootStackView.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            rootStackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            rootStackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            rootStackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14)
        ])
    }

    private func bindActions() {
        brushButton.addTarget(
            self,
            action: #selector(handleBrushButtonTap),
            for: .touchUpInside
        )
        eraserButton.addTarget(
            self,
            action: #selector(handleEraserButtonTap),
            for: .touchUpInside
        )
        lassoButton.addTarget(
            self,
            action: #selector(handleLassoButtonTap),
            for: .touchUpInside
        )
        deselectButton.addTarget(
            self,
            action: #selector(handleDeselectButtonTap),
            for: .touchUpInside
        )
        undoButton.addTarget(
            self,
            action: #selector(handleUndoButtonTap),
            for: .touchUpInside
        )
        redoButton.addTarget(
            self,
            action: #selector(handleRedoButtonTap),
            for: .touchUpInside
        )
    }

    private func rebuildColorButtonsIfNeeded(colors: [HandDrawingColor]) {
        guard colors != currentColors else {
            return
        }
        currentColors = colors
        colorButtons.forEach { button in
            colorStackView.removeArrangedSubview(button)
            button.removeFromSuperview()
        }
        colorButtons = colors.map { color in
            let button = ColorSwatchButton(color: color)
            button.addTarget(
                self,
                action: #selector(handleColorButtonTap(_:)),
                for: .touchUpInside
            )
            colorStackView.addArrangedSubview(button)
            return button
        }
    }

    private func rebuildLineWidthButtonsIfNeeded(lineWidths: [CGFloat]) {
        guard lineWidths != currentLineWidths else {
            return
        }
        currentLineWidths = lineWidths
        lineWidthButtons.forEach { button in
            lineWidthStackView.removeArrangedSubview(button)
            button.removeFromSuperview()
        }
        lineWidthButtons = lineWidths.map { lineWidth in
            let button = Self.makeActionButton(title: "\(Int(lineWidth.rounded()))")
            button.configurationUpdateHandler = { button in
                var configuration = button.configuration ?? UIButton.Configuration.tinted()
                configuration.baseBackgroundColor = button.isSelected
                    ? .systemBlue
                    : .tertiarySystemBackground
                configuration.baseForegroundColor = button.isSelected
                    ? .white
                    : .label
                button.configuration = configuration
            }
            button.addAction(
                UIAction { [weak self] _ in
                    self?.onSelectLineWidth?(lineWidth)
                },
                for: .touchUpInside
            )
            lineWidthStackView.addArrangedSubview(button)
            return button
        }
    }

    private func updateToolButtonSelection(
        _ button: UIButton,
        isSelected: Bool,
        isEnabled: Bool
    ) {
        button.isEnabled = isEnabled
        var configuration = button.configuration ?? UIButton.Configuration.tinted()
        configuration.baseBackgroundColor = isSelected
            ? .systemBlue
            : .tertiarySystemBackground
        configuration.baseForegroundColor = isSelected
            ? .white
            : .label
        button.configuration = configuration
        button.alpha = isEnabled ? 1 : 0.5
    }

    @objc
    private func handleBrushButtonTap() {
        onSelectTool?(.brush)
    }

    @objc
    private func handleEraserButtonTap() {
        onSelectTool?(.pixelEraser)
    }

    @objc
    private func handleLassoButtonTap() {
        onSelectTool?(.lasso)
    }

    @objc
    private func handleDeselectButtonTap() {
        onDeselectSelection?()
    }

    @objc
    private func handleUndoButtonTap() {
        onUndo?()
    }

    @objc
    private func handleRedoButtonTap() {
        onRedo?()
    }

    @objc
    private func handleColorButtonTap(_ sender: ColorSwatchButton) {
        onSelectColor?(sender.color)
    }

    private static func makeHorizontalStack() -> UIStackView {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = Layout.itemSpacing
        stackView.alignment = .center
        return stackView
    }

    private static func makeActionButton(title: String) -> UIButton {
        var configuration = UIButton.Configuration.tinted()
        configuration.title = title
        configuration.cornerStyle = .medium
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.configuration = configuration
        return button
    }
}

private final class ColorSwatchButton: UIButton {
    let color: HandDrawingColor

    override var isSelected: Bool {
        didSet {
            updateAppearance()
        }
    }

    init(color: HandDrawingColor) {
        self.color = color
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = HandDrawingToolPaletteView.Layout.colorSwatchSize / 2
        layer.cornerCurve = .continuous
        layer.borderWidth = 2
        backgroundColor = UIColor(handDrawingColor: color)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: HandDrawingToolPaletteView.Layout.colorSwatchSize),
            heightAnchor.constraint(equalToConstant: HandDrawingToolPaletteView.Layout.colorSwatchSize)
        ])
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func updateAppearance() {
        layer.borderColor = isSelected
            ? UIColor.systemBlue.cgColor
            : UIColor.separator.cgColor
        layer.borderWidth = isSelected ? 3 : 1.5
    }
}
#endif
