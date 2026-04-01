#if os(macOS)
import AppKit

final class macOSVideoDisplayFrameEditorViewController: NSViewController {
    private let editorContext: CanvasVideoEditorContext
    private let titleLabel: NSTextField = {
        let label = NSTextField(labelWithString: "Set Display Frame")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 24, weight: .semibold)
        return label
    }()
    private let detailLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 13, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        return label
    }()
    private let closeButton: NSButton = {
        let button = NSButton(title: "Done", target: nil, action: nil)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.controlSize = .large
        return button
    }()

    init(editorContext: CanvasVideoEditorContext) {
        self.editorContext = editorContext
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = CGSize(width: 520, height: 240)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        detailLabel.stringValue =
            "Video item: \(editorContext.itemID.uuidString)\n" +
            "Source video: \(editorContext.sourceVideoFilename)\n" +
            "Current poster: \(editorContext.currentPosterFilename)\n" +
            "Poster time: \(formatVideoDisplayFrameEditorSeconds(editorContext.currentPosterTimeSeconds))\n" +
            "Duration: \(formatVideoDisplayFrameEditorSeconds(editorContext.durationSeconds))\n" +
            "Video size: \(Int(editorContext.naturalPixelSize.width)) x \(Int(editorContext.naturalPixelSize.height))\n" +
            "The shared frame extraction and poster persistence services are ready. The full platform UI will be added in the next phase."
        closeButton.target = self
        closeButton.action = #selector(handleCloseButtonClick)

        view.addSubview(titleLabel)
        view.addSubview(detailLabel)
        view.addSubview(closeButton)
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 28),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            closeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 18),
            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24)
        ])
    }

    @objc
    private func handleCloseButtonClick() {
        dismiss(self)
    }
}

private func formatVideoDisplayFrameEditorSeconds(
    _ timeSeconds: Double
) -> String {
    String(format: "%.2fs", timeSeconds)
}
#endif
