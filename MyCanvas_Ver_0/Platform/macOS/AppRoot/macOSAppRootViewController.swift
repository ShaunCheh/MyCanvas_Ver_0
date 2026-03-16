#if os(macOS)
import AppKit

final class macOSAppRootViewController: NSViewController {
    private let launchCoordinator: AppLaunchCoordinator
    private var currentViewController: NSViewController?

    var currentCanvasViewController: macOSViewController? {
        currentViewController as? macOSViewController
    }

    init(launchCoordinator: AppLaunchCoordinator = AppLaunchCoordinator()) {
        self.launchCoordinator = launchCoordinator
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func loadView() {
        let rootView = NSView()
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        view = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        display(launchCoordinator.initialDestination())
    }

    func display(_ destination: AppLaunchDestination) {
        let viewController = makeViewController(for: destination)
        setCurrentViewController(viewController)
    }

    private func makeViewController(for destination: AppLaunchDestination) -> NSViewController {
        switch destination {
        case .boardList:
            let viewController = macOSBoardListViewController()
            viewController.onOpenCanvas = { [weak self] in
                self?.display(.canvas)
            }
            return viewController
        case .canvas:
            return macOSViewController()
        }
    }

    private func setCurrentViewController(_ viewController: NSViewController) {
        if let currentViewController {
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

        currentViewController = viewController
    }
}
#endif
