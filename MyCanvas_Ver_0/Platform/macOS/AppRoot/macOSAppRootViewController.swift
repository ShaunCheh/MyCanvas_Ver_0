#if os(macOS)
import AppKit

final class macOSAppRootViewController: NSViewController {
    private let launchCoordinator: AppLaunchCoordinator
    private var currentViewController: NSViewController?
    private var currentBoardListCanvasTransitionContext: BoardListCanvasTransitionContext?
    private var transitionPhase: macOSBoardListCanvasTransitionPhase = .idle
    private var activeTransitionSession: macOSBoardListCanvasTransitionSession?
    private let overlayHostView: NSView = {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        return view
    }()
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
        let rootView = macOSAppearanceAwareView()
        rootView.wantsLayer = true
        rootView.onEffectiveAppearanceChange = { [weak self] in
            self?.updateAppearance()
        }
        view = rootView
        updateAppearance()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        print(
            "[Canvas macOS][AppRoot] " +
            "action=viewDidLoad " +
            "rootViewBounds=\(describeAppRootRect(view.bounds)) " +
            "rootViewFrame=\(describeAppRootRect(view.frame))"
        )
        setupTransitionInfrastructure()
        display(launchCoordinator.initialDestination())
    }

    private func updateAppearance() {
        let appearance = view.effectiveAppearance
        PlatformLayerAppearance.performWithoutAnimations {
            view.layer?.backgroundColor = PlatformLayerAppearance.resolvedCGColor(
                .windowBackgroundColor,
                for: appearance
            )
        }
        activeTransitionSession?.carrier.updateAppearance(appearance)
    }

    func display(_ destination: AppLaunchDestination) {
        discardActiveTransitionIfNeeded()
        print(
            "[Canvas macOS][AppRoot] " +
            "action=display " +
            "destination=\(describeAppRootDestination(destination)) " +
            "rootViewBounds=\(describeAppRootRect(view.bounds)) " +
            "rootViewFrame=\(describeAppRootRect(view.frame)) " +
            "currentViewController=\(describeAppRootViewController(currentViewController))"
        )
        let viewController = makeViewController(for: destination)
        setCurrentViewControllerImmediately(viewController)
        transitionPhase = steadyPhase(for: destination)
        deactivateTransitionOverlay()
    }

    private func makeViewController(for destination: AppLaunchDestination) -> NSViewController {
        switch destination {
        case .boardList:
            return makeBoardListViewController()
        case let .canvas(launchContext):
            return makeCanvasViewController(for: launchContext)
        }
    }

    private func configureBoardListViewController(
        _ viewController: macOSBoardListViewController
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
        let carrier = macOSBoardListCanvasTransitionCarrierFactory.makeCarrier(
            preferredKind: request.preferredCarrierKind
        )
        let session = macOSBoardListCanvasTransitionSession(
            context: request.transitionContext,
            carrier: carrier,
            sourceViewController: sourceViewController,
            destinationViewController: destinationViewController
        )

        activeTransitionSession = session
        transitionPhase = .opening
        setTransitionInteractionFrozen(true, for: sourceViewController)
        setTransitionInteractionFrozen(true, for: destinationViewController)
        activateTransitionOverlay()
        carrier.install(in: overlayHostView)
        mountViewController(destinationViewController, hidden: true)
        view.layoutSubtreeIfNeeded()
        carrier.prepareTransition(
            with: session.context,
            sourceViewController: sourceViewController,
            destinationViewController: destinationViewController
        )
        carrier.animateTransition { [weak self] in
            self?.completeOpeningTransition(sessionID: session.id)
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
        setTransitionInteractionFrozen(false, for: session.sourceViewController)
        setTransitionInteractionFrozen(false, for: destinationViewController)
        currentViewController = destinationViewController
        session.carrier.completeTransition()
        activeTransitionSession = nil
        transitionPhase = .steadyCanvas
        deactivateTransitionOverlay()
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
        let carrier = macOSBoardListCanvasTransitionCarrierFactory.makeCarrier(
            preferredKind: request.preferredCarrierKind
        )
        let session = macOSBoardListCanvasTransitionSession(
            context: request.transitionContext,
            carrier: carrier,
            sourceViewController: sourceViewController,
            destinationViewController: destinationViewController
        )

        activeTransitionSession = session
        transitionPhase = .closing
        setTransitionInteractionFrozen(true, for: sourceViewController)
        setTransitionInteractionFrozen(true, for: destinationViewController)
        activateTransitionOverlay()
        carrier.install(in: overlayHostView)
        mountViewController(destinationViewController, hidden: true)
        destinationViewController.prepareForDisplay()
        view.layoutSubtreeIfNeeded()
        carrier.prepareTransition(
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
        session.carrier.animateTransition { [weak self] in
            self?.completeClosingTransition(sessionID: sessionID)
        }
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
        setTransitionInteractionFrozen(false, for: session.sourceViewController)
        setTransitionInteractionFrozen(false, for: destinationViewController)
        currentViewController = destinationViewController
        session.carrier.completeTransition()
        activeTransitionSession = nil
        transitionPhase = .steadyBoardList
        deactivateTransitionOverlay()
    }

    private func makeBoardListViewController() -> macOSBoardListViewController {
        boardListViewController.prepareForDisplay()
        return boardListViewController
    }

    private func makeCanvasViewController(
        for launchContext: CanvasLaunchContext
    ) -> macOSViewController {
        let viewController = macOSViewController()
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
        deactivateTransitionOverlay()
    }

    private func setCurrentViewControllerImmediately(
        _ viewController: NSViewController
    ) {
        if let currentViewController,
           currentViewController !== viewController {
            unmountViewController(currentViewController)
        }

        mountViewController(viewController, hidden: false)
        setTransitionInteractionFrozen(false, for: viewController)
        currentViewController = viewController
    }

    private func mountViewController(
        _ viewController: NSViewController,
        hidden: Bool
    ) {
        if viewController.parent !== self {
            addChild(viewController)
            viewController.view.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(
                viewController.view,
                positioned: .below,
                relativeTo: overlayHostView
            )
            NSLayoutConstraint.activate([
                viewController.view.topAnchor.constraint(equalTo: view.topAnchor),
                viewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                viewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                viewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
        } else if viewController.view.superview == nil {
            view.addSubview(
                viewController.view,
                positioned: .below,
                relativeTo: overlayHostView
            )
        } else {
            view.addSubview(
                viewController.view,
                positioned: .below,
                relativeTo: overlayHostView
            )
        }

        viewController.view.isHidden = hidden
        view.addSubview(
            overlayHostView,
            positioned: .above,
            relativeTo: viewController.view
        )
    }

    private func unmountViewController(_ viewController: NSViewController) {
        guard viewController.parent === self else {
            return
        }

        viewController.view.removeFromSuperview()
        viewController.removeFromParent()
    }

    private func discardActiveTransitionIfNeeded() {
        guard let session = activeTransitionSession else {
            return
        }

        session.carrier.cancelTransition()
        setTransitionInteractionFrozen(false, for: session.sourceViewController)
        setTransitionInteractionFrozen(false, for: session.destinationViewController)
        if let destinationViewController = session.destinationViewController,
           destinationViewController !== currentViewController {
            unmountViewController(destinationViewController)
        }
        currentViewController?.view.isHidden = false
        activeTransitionSession = nil
        transitionPhase = steadyPhase(for: currentViewController)
        deactivateTransitionOverlay()
    }

    private func activateTransitionOverlay() {
        overlayHostView.isHidden = false
    }

    private func deactivateTransitionOverlay() {
        overlayHostView.isHidden = true
    }

    private func setTransitionInteractionFrozen(
        _ isFrozen: Bool,
        for viewController: NSViewController?
    ) {
        (viewController as? any macOSBoardListCanvasTransitionInteractionControlling)?
            .setTransitionInteractionFrozen(isFrozen)
    }

    private func steadyPhase(
        for destination: AppLaunchDestination
    ) -> macOSBoardListCanvasTransitionPhase {
        switch destination {
        case .boardList:
            return .steadyBoardList
        case .canvas:
            return .steadyCanvas
        }
    }

    private func steadyPhase(
        for viewController: NSViewController?
    ) -> macOSBoardListCanvasTransitionPhase {
        switch viewController {
        case is macOSBoardListViewController:
            return .steadyBoardList
        case is macOSViewController:
            return .steadyCanvas
        default:
            return .idle
        }
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
