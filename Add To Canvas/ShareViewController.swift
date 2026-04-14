import SwiftUI
import UIKit

final class ShareViewController: UIViewController {
    private lazy var viewModel = ShareImportViewModel(
        extensionContext: extensionContext,
        finishHandler: { [weak self] in
            self?.extensionContext?.completeRequest(
                returningItems: nil,
                completionHandler: nil
            )
        },
        cancelHandler: { [weak self] error in
            self?.extensionContext?.cancelRequest(withError: error)
        }
    )

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        preferredContentSize = CGSize(width: 0, height: 560)
        embedHostingController()
    }

    private func embedHostingController() {
        let hostingController = UIHostingController(
            rootView: ShareImportView(viewModel: viewModel)
        )
        addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        hostingController.view.backgroundColor = .clear
        view.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        hostingController.didMove(toParent: self)
    }
}
