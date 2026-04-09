#if os(iOS)
import UIKit

final class iOSAppRootViewController: UIViewController {
    private let launchCoordinator: AppLaunchCoordinator
    private var currentViewController: UIViewController?
    private var currentBoardListCanvasTransitionContext: BoardListCanvasTransitionContext?
    private var transitionPhase: iOSBoardListCanvasTransitionPhase = .idle
    private var activeTransitionSession: iOSBoardListCanvasTransitionSession?
    private let overlayHostView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }()
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
        setupTransitionInfrastructure()
        display(launchCoordinator.initialDestination())
    }

    func display(_ destination: AppLaunchDestination) {
        discardActiveTransitionIfNeeded()
        let viewController = makeViewController(for: destination)
        setCurrentViewControllerImmediately(viewController)
        transitionPhase = steadyPhase(for: destination)
    }

    private func makeViewController(for destination: AppLaunchDestination) -> UIViewController {
        switch destination {
        case .boardList:
            return makeBoardListViewController()
        case let .canvas(launchContext):
            return makeCanvasViewController(for: launchContext)
        }
    }

    private func configureBoardListViewController(
        _ viewController: iOSBoardListViewController
    ) {
        viewController.onOpenCanvas = { [weak self] request in
            self?.handleCanvasOpenRequest(request)
        }
    }

    private func handleCanvasOpenRequest(
        _ request: BoardListCanvasOpenRequest
    ) {
        currentBoardListCanvasTransitionContext = request.transitionContext
        beginOpeningTransition(with: request)
    }

    private func handleCanvasReturnRequest(
        _ request: BoardListCanvasReturnRequest
    ) {
        currentBoardListCanvasTransitionContext = request.transitionContext
        beginClosingTransition(with: request)
    }

    private func updateCurrentTransitionTargetGeometry(
        _ geometry: BoardListCanvasTransitionTargetGeometry,
        expectedBoardID: UUID?
    ) {
        guard
            var context = currentBoardListCanvasTransitionContext,
            context.direction == .closing,
            context.targetBoardID == expectedBoardID
        else {
            return
        }

        context.targetGeometry = geometry
        currentBoardListCanvasTransitionContext = context
    }

    private func beginOpeningTransition(
        with request: BoardListCanvasOpenRequest
    ) {
        guard activeTransitionSession == nil else {
            display(.canvas(request.launchContext))
            return
        }

        let sourceViewController = currentViewController ?? boardListViewController
        let destinationViewController = makeCanvasViewController(
            for: request.launchContext
        )
        let carrier = iOSBoardListCanvasTransitionCarrierFactory.makeCarrier(
            preferredKind: request.preferredCarrierKind
        )
        let session = iOSBoardListCanvasTransitionSession(
            context: request.transitionContext,
            carrier: carrier,
            sourceViewController: sourceViewController,
            destinationViewController: destinationViewController
        )

        activeTransitionSession = session
        transitionPhase = .opening
        carrier.install(in: overlayHostView)
        mountViewController(destinationViewController, hidden: true)
        carrier.beginTransition(
            with: session.context,
            sourceViewController: sourceViewController,
            destinationViewController: destinationViewController
        )

        DispatchQueue.main.async { [weak self] in
            self?.completeOpeningTransition(
                sessionID: session.id
            )
        }
    }

    private func completeOpeningTransition(sessionID: UUID) {
        guard
            transitionPhase == .opening,
            let session = activeTransitionSession,
            session.id == sessionID,
            let destinationViewController = session.destinationViewController
        else {
            return
        }

        if let sourceViewController = session.sourceViewController,
           sourceViewController !== destinationViewController {
            unmountViewController(sourceViewController)
        }
        destinationViewController.view.isHidden = false
        currentViewController = destinationViewController
        session.carrier.completeTransition()
        activeTransitionSession = nil
        transitionPhase = .steadyCanvas
    }

    private func beginClosingTransition(
        with request: BoardListCanvasReturnRequest
    ) {
        guard activeTransitionSession == nil else {
            display(.boardList)
            return
        }

        let sourceViewController = currentViewController
        let destinationViewController = boardListViewController
        let carrier = iOSBoardListCanvasTransitionCarrierFactory.makeCarrier(
            preferredKind: request.preferredCarrierKind
        )
        let session = iOSBoardListCanvasTransitionSession(
            context: request.transitionContext,
            carrier: carrier,
            sourceViewController: sourceViewController,
            destinationViewController: destinationViewController
        )

        activeTransitionSession = session
        transitionPhase = .closing
        carrier.install(in: overlayHostView)
        mountViewController(destinationViewController, hidden: true)
        destinationViewController.prepareForDisplay()
        carrier.beginTransition(
            with: session.context,
            sourceViewController: sourceViewController,
            destinationViewController: destinationViewController
        )

        let targetBoardID = request.transitionContext.targetBoardID
        destinationViewController.prepareTransitionTargetGeometry(
            for: targetBoardID
        ) { [weak self] geometry in
            self?.handleResolvedClosingTargetGeometry(
                geometry,
                sessionID: session.id,
                expectedBoardID: targetBoardID
            )
        }
    }

    private func handleResolvedClosingTargetGeometry(
        _ geometry: BoardListCanvasTransitionTargetGeometry,
        sessionID: UUID,
        expectedBoardID: UUID?
    ) {
        guard
            transitionPhase == .closing,
            let session = activeTransitionSession,
            session.id == sessionID
        else {
            return
        }

        updateCurrentTransitionTargetGeometry(
            geometry,
            expectedBoardID: expectedBoardID
        )
        session.context.targetGeometry = geometry
        session.carrier.updateTransitionContext(session.context)
        completeClosingTransition(sessionID: sessionID)
    }

    private func completeClosingTransition(sessionID: UUID) {
        guard
            transitionPhase == .closing,
            let session = activeTransitionSession,
            session.id == sessionID,
            let destinationViewController = session.destinationViewController
        else {
            return
        }

        if let sourceViewController = session.sourceViewController,
           sourceViewController !== destinationViewController {
            unmountViewController(sourceViewController)
        }
        destinationViewController.view.isHidden = false
        currentViewController = destinationViewController
        session.carrier.completeTransition()
        activeTransitionSession = nil
        transitionPhase = .steadyBoardList
    }

    private func makeBoardListViewController() -> iOSBoardListViewController {
        boardListViewController.prepareForDisplay()
        return boardListViewController
    }

    private func makeCanvasViewController(
        for launchContext: CanvasLaunchContext
    ) -> iOSViewController {
        let viewController = iOSViewController()
        viewController.launchContext = launchContext
        viewController.onReturnToBoardList = { [weak self] request in
            self?.handleCanvasReturnRequest(request)
        }
        return viewController
    }

    private func setupTransitionInfrastructure() {
        view.addSubview(overlayHostView)
        NSLayoutConstraint.activate([
            overlayHostView.topAnchor.constraint(equalTo: view.topAnchor),
            overlayHostView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlayHostView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlayHostView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setCurrentViewControllerImmediately(
        _ viewController: UIViewController
    ) {
        if let currentViewController,
           currentViewController !== viewController {
            unmountViewController(currentViewController)
        }

        mountViewController(viewController, hidden: false)
        currentViewController = viewController
    }

    private func mountViewController(
        _ viewController: UIViewController,
        hidden: Bool
    ) {
        if viewController.parent !== self {
            addChild(viewController)
            viewController.view.translatesAutoresizingMaskIntoConstraints = false
            view.insertSubview(
                viewController.view,
                belowSubview: overlayHostView
            )
            NSLayoutConstraint.activate([
                viewController.view.topAnchor.constraint(equalTo: view.topAnchor),
                viewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                viewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                viewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
            viewController.didMove(toParent: self)
        } else if viewController.view.superview == nil {
            view.insertSubview(
                viewController.view,
                belowSubview: overlayHostView
            )
        } else {
            view.insertSubview(
                viewController.view,
                belowSubview: overlayHostView
            )
        }

        viewController.view.isHidden = hidden
        view.bringSubviewToFront(overlayHostView)
    }

    private func unmountViewController(_ viewController: UIViewController) {
        guard viewController.parent === self else {
            return
        }

        viewController.willMove(toParent: nil)
        viewController.view.removeFromSuperview()
        viewController.removeFromParent()
    }

    private func discardActiveTransitionIfNeeded() {
        guard let session = activeTransitionSession else {
            return
        }

        session.carrier.cancelTransition()
        if let destinationViewController = session.destinationViewController,
           destinationViewController !== currentViewController {
            unmountViewController(destinationViewController)
        }
        currentViewController?.view.isHidden = false
        activeTransitionSession = nil
        transitionPhase = steadyPhase(for: currentViewController)
    }

    private func steadyPhase(
        for destination: AppLaunchDestination
    ) -> iOSBoardListCanvasTransitionPhase {
        switch destination {
        case .boardList:
            return .steadyBoardList
        case .canvas:
            return .steadyCanvas
        }
    }

    private func steadyPhase(
        for viewController: UIViewController?
    ) -> iOSBoardListCanvasTransitionPhase {
        switch viewController {
        case is iOSBoardListViewController:
            return .steadyBoardList
        case is iOSViewController:
            return .steadyCanvas
        default:
            return .idle
        }
    }
}
#endif
