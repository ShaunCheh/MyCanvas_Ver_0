#if os(iOS)
import UIKit

final class iOSVideoDisplayFrameEditorViewController: UIViewController {
    private let editorContext: CanvasVideoEditorContext
    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 28, weight: .semibold)
        label.text = "Set Display Frame"
        return label
    }()
    private let detailLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 15, weight: .regular)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        return label
    }()
    private let closeButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        var configuration = UIButton.Configuration.filled()
        configuration.title = "Done"
        configuration.cornerStyle = .capsule
        button.configuration = configuration
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

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        detailLabel.text =
            "Video item: \(editorContext.itemID.uuidString)\n" +
            "Source video: \(editorContext.sourceVideoFilename)\n" +
            "Current poster: \(editorContext.currentPosterFilename)\n" +
            "Poster time: \(formatVideoDisplayFrameEditorSeconds(editorContext.currentPosterTimeSeconds))\n" +
            "Duration: \(formatVideoDisplayFrameEditorSeconds(editorContext.durationSeconds))\n" +
            "Video size: \(Int(editorContext.naturalPixelSize.width)) x \(Int(editorContext.naturalPixelSize.height))\n" +
            "The shared frame extraction and poster persistence services are ready. The full platform UI will be added in the next phase."
        closeButton.addTarget(
            self,
            action: #selector(handleCloseButtonTap),
            for: .touchUpInside
        )

        view.addSubview(titleLabel)
        view.addSubview(detailLabel)
        view.addSubview(closeButton)
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor,
                constant: 32
            ),
            titleLabel.leadingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.leadingAnchor,
                constant: 24
            ),
            titleLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: closeButton.leadingAnchor,
                constant: -16
            ),
            closeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            closeButton.trailingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.trailingAnchor,
                constant: -24
            ),
            detailLabel.topAnchor.constraint(
                equalTo: titleLabel.bottomAnchor,
                constant: 20
            ),
            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.trailingAnchor,
                constant: -24
            )
        ])
    }

    @objc
    private func handleCloseButtonTap() {
        dismiss(animated: true)
    }
}

private func formatVideoDisplayFrameEditorSeconds(
    _ timeSeconds: Double
) -> String {
    String(format: "%.2fs", timeSeconds)
}
#endif
