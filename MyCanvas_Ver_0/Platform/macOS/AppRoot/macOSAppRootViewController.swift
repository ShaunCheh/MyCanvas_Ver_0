#if os(macOS)
import AppKit

final class macOSAppRootViewController: NSViewController {
    private let launchCoordinator: AppLaunchCoordinator
    private var currentViewController: NSViewController?
    private lazy var boardListViewController: macOSBoardListViewController = {
        let viewController = macOSBoardListViewController()
        configureBoardListViewController(viewController)
        return viewController
    }()

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
        print(
            "[Canvas macOS][AppRoot] " +
            "action=viewDidLoad " +
            "rootViewBounds=\(describeAppRootRect(view.bounds)) " +
            "rootViewFrame=\(describeAppRootRect(view.frame))"
        )
        display(launchCoordinator.initialDestination())
    }

    func display(_ destination: AppLaunchDestination) {
        print(
            "[Canvas macOS][AppRoot] " +
            "action=display " +
            "destination=\(describeAppRootDestination(destination)) " +
            "rootViewBounds=\(describeAppRootRect(view.bounds)) " +
            "rootViewFrame=\(describeAppRootRect(view.frame)) " +
            "currentViewController=\(describeAppRootViewController(currentViewController))"
        )
        let viewController = makeViewController(for: destination)
        setCurrentViewController(viewController)
    }

    private func makeViewController(for destination: AppLaunchDestination) -> NSViewController {
        switch destination {
        case .boardList:
            return boardListViewController
        case let .canvas(launchContext):
            let viewController = macOSViewController()
            viewController.launchContext = launchContext
            return viewController
        }
    }

    private func configureBoardListViewController(
        _ viewController: macOSBoardListViewController
    ) {
        viewController.onOpenBoard = { [weak self] boardID in
            self?.display(.canvas(.existing(boardID: boardID)))
        }
        viewController.onCreateBoard = { [weak self] in
            self?.display(.canvas(.newBoard))
        }
    }

    private func setCurrentViewController(_ viewController: NSViewController) {
        print(
            "[Canvas macOS][AppRoot] " +
            "action=setCurrentViewController " +
            "incoming=\(describeAppRootViewController(viewController)) " +
            "previous=\(describeAppRootViewController(currentViewController)) " +
            "rootViewBounds=\(describeAppRootRect(view.bounds)) " +
            "rootViewFrame=\(describeAppRootRect(view.frame))"
        )
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

        print(
            "[Canvas macOS][AppRoot] " +
            "action=setCurrentViewControllerCompleted " +
            "current=\(describeAppRootViewController(currentViewController)) " +
            "childViewBounds=\(describeAppRootRect(viewController.view.bounds)) " +
            "childViewFrame=\(describeAppRootRect(viewController.view.frame))"
        )
    }
}

private func describeAppRootRect(_ rect: CGRect) -> String {
    "{{\(formatAppRootValue(rect.origin.x)), \(formatAppRootValue(rect.origin.y))}, {\(formatAppRootValue(rect.size.width)), \(formatAppRootValue(rect.size.height))}}"
}

private func describeAppRootDestination(_ destination: AppLaunchDestination) -> String {
    switch destination {
    case .boardList:
        return "boardList"
    case let .canvas(launchContext):
        return "canvas.\(describeCanvasLaunchContext(launchContext))"
    }
}

private func describeCanvasLaunchContext(_ launchContext: CanvasLaunchContext) -> String {
    switch launchContext {
    case let .existing(boardID):
        return "existing(\(boardID.uuidString))"
    case .newBoard:
        return "newBoard"
    }
}

private func describeAppRootViewController(_ viewController: NSViewController?) -> String {
    guard let viewController else {
        return "nil"
    }

    return String(describing: type(of: viewController))
}

private func formatAppRootValue(_ value: CGFloat) -> String {
    String(format: "%.2f", Double(value))
}
#endif
