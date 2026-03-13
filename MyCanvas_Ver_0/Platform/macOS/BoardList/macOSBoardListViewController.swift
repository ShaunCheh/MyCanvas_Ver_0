#if os(macOS)
import AppKit

final class macOSBoardListViewController: NSViewController {
    private let titleLabel: NSTextField = {
        let label = NSTextField(labelWithString: "Board List")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 28, weight: .semibold)
        label.textColor = .labelColor
        label.alignment = .center
        return label
    }()

    private let subtitleLabel: NSTextField = {
        let label = NSTextField(labelWithString: "Placeholder scene for a future board list.")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 16)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        return label
    }()

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViewHierarchy()
        setupConstraints()
    }

    private func setupViewHierarchy() {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        view.addSubview(titleLabel)
        view.addSubview(subtitleLabel)
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -16),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            subtitleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
    }
}
#endif
