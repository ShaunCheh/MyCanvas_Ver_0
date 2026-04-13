#if os(iOS)
import UIKit

enum iOSCanvasTextEditorObservedShortcut {
    case copy
    case paste
    case undo
    case redo
}

final class iOSCanvasTextEditorOverlayView: UIView {
    private enum Layout {
        static let cornerRadius: CGFloat = 18
        static let horizontalInset: CGFloat = 12
        static let verticalInset: CGFloat = 10
        static let shadowOpacity: Float = 0.12
        static let shadowRadius: CGFloat = 10
        static let shadowOffset = CGSize(width: 0, height: 4)
    }

    private let backgroundView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .secondarySystemBackground.withAlphaComponent(0.96)
        view.layer.cornerRadius = Layout.cornerRadius
        view.layer.cornerCurve = .continuous
        view.layer.borderWidth = 1
        view.layer.borderColor = UIColor.separator.withAlphaComponent(0.24).cgColor
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = Layout.shadowOpacity
        view.layer.shadowRadius = Layout.shadowRadius
        view.layer.shadowOffset = Layout.shadowOffset
        return view
    }()

    let textView: iOSCanvasInputObservingTextView = {
        let textView = iOSCanvasInputObservingTextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.backgroundColor = .clear
        textView.font = .systemFont(ofSize: 17)
        textView.textColor = .label
        textView.tintColor = .systemBlue
        textView.autocorrectionType = .yes
        textView.autocapitalizationType = .sentences
        textView.spellCheckingType = .yes
        textView.keyboardDismissMode = .interactive
        textView.textContainerInset = UIEdgeInsets(
            top: 8,
            left: 4,
            bottom: 8,
            right: 4
        )
        textView.accessibilityLabel = "Text editor"
        return textView
    }()

    var onObservedShortcut: ((iOSCanvasTextEditorObservedShortcut) -> Void)? {
        get { textView.onObservedShortcut }
        set { textView.onObservedShortcut = newValue }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        isOpaque = false
        isHidden = true
        addSubview(backgroundView)
        addSubview(textView)
        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
            textView.topAnchor.constraint(equalTo: topAnchor, constant: Layout.verticalInset),
            textView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Layout.horizontalInset),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Layout.horizontalInset),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Layout.verticalInset)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hitView = super.hitTest(point, with: event)
        return hitView === self ? nil : hitView
    }

    func apply(text: String) {
        if textView.text != text {
            textView.text = text
        }
    }
}

final class iOSCanvasInputObservingTextView: UITextView {
    private struct CommandSignature: Hashable {
        let input: String?
        let modifierFlagsRawValue: UIKeyModifierFlags.RawValue

        init(_ command: UIKeyCommand) {
            input = command.input
            modifierFlagsRawValue = command.modifierFlags.rawValue
        }
    }

    var onObservedShortcut: ((iOSCanvasTextEditorObservedShortcut) -> Void)?

    override var keyCommands: [UIKeyCommand]? {
        let observedCommands = [
            makeObservedKeyCommand(
                input: "c",
                modifierFlags: [.command],
                action: #selector(handleObservedCopyKeyCommand(_:)),
                discoverabilityTitle: "Copy"
            ),
            makeObservedKeyCommand(
                input: "v",
                modifierFlags: [.command],
                action: #selector(handleObservedPasteKeyCommand(_:)),
                discoverabilityTitle: "Paste"
            ),
            makeObservedKeyCommand(
                input: "z",
                modifierFlags: [.command],
                action: #selector(handleObservedUndoKeyCommand(_:)),
                discoverabilityTitle: "Undo"
            ),
            makeObservedKeyCommand(
                input: "z",
                modifierFlags: [.command, .shift],
                action: #selector(handleObservedRedoKeyCommand(_:)),
                discoverabilityTitle: "Redo"
            )
        ]

        let observedSignatures = Set(observedCommands.map(CommandSignature.init))
        let inheritedCommands = (super.keyCommands ?? []).filter { command in
            observedSignatures.contains(CommandSignature(command)) == false
        }
        return observedCommands + inheritedCommands
    }

    private func makeObservedKeyCommand(
        input: String,
        modifierFlags: UIKeyModifierFlags,
        action: Selector,
        discoverabilityTitle: String
    ) -> UIKeyCommand {
        let command = UIKeyCommand(
            input: input,
            modifierFlags: modifierFlags,
            action: action
        )
        command.discoverabilityTitle = discoverabilityTitle
        return command
    }

    @objc
    private func handleObservedCopyKeyCommand(_ sender: UIKeyCommand) {
        onObservedShortcut?(.copy)
        copy(sender)
    }

    @objc
    private func handleObservedPasteKeyCommand(_ sender: UIKeyCommand) {
        onObservedShortcut?(.paste)
        paste(sender)
    }

    @objc
    private func handleObservedUndoKeyCommand(_ sender: UIKeyCommand) {
        onObservedShortcut?(.undo)
        undoManager?.undo()
    }

    @objc
    private func handleObservedRedoKeyCommand(_ sender: UIKeyCommand) {
        onObservedShortcut?(.redo)
        undoManager?.redo()
    }
}
#endif
