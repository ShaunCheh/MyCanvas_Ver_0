#if os(iOS)
import UIKit

final class iOSAppRootViewController: UIViewController {
    private let launchCoordinator: AppLaunchCoordinator
    private var currentViewController: UIViewController?
    private lazy var boardListViewController: iOSBoardListViewController = {
        let viewController = iOSBoardListViewController()
        configureBoardListViewController(viewController)
        return viewController
    }()

    init(launchCoordinator: AppLaunchCoordinator = AppLaunchCoordinator()) {
        self.launchCoordinator = launchCoordinator
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        display(launchCoordinator.initialDestination())
    }

    func display(_ destination: AppLaunchDestination) {
        let viewController = makeViewController(for: destination)
        setCurrentViewController(viewController)
    }

    private func makeViewController(for destination: AppLaunchDestination) -> UIViewController {
        switch destination {
        case .boardList:
            boardListViewController.prepareForDisplay()
            return boardListViewController
        case let .canvas(launchContext):
            let viewController = iOSViewController()
            viewController.launchContext = launchContext
            return viewController
        }
    }

    private func configureBoardListViewController(
        _ viewController: iOSBoardListViewController
    ) {
        viewController.onOpenBoard = { [weak self] boardID in
            self?.display(.canvas(.existing(boardID: boardID)))
        }
        viewController.onCreateBoard = { [weak self] in
            self?.display(.canvas(.newBoard))
        }
    }

    private func setCurrentViewController(_ viewController: UIViewController) {
        if let currentViewController {
            currentViewController.willMove(toParent: nil)
            currentViewController.view.removeFromSuperview()
            currentViewController.removeFromParent()
        }

        addChild(viewController)
        viewController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(viewController.view)

        NSLayoutConstraint.activate([
            viewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            viewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            viewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            viewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        viewController.didMove(toParent: self)
        currentViewController = viewController
    }
}
#endif
