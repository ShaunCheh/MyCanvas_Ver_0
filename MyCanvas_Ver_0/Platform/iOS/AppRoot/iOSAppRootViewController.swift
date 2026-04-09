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
        deactivateTransitionOverlay()
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
        if let trace = request.debugTrace {
            logClosingTransitionTrace(
                trace,
                phase: "handleCanvasReturnRequest",
                extra:
                    "boardID=\(request.boardID?.uuidString ?? "nil") " +
                    "requiresPersistence=\(request.requiresBoardPersistence)"
            )
        }
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
        setTransitionInteractionFrozen(true, for: sourceViewController)
        setTransitionInteractionFrozen(true, for: destinationViewController)
        activateTransitionOverlay()
        carrier.install(in: overlayHostView)
        mountViewController(destinationViewController, hidden: true)
        view.layoutIfNeeded()
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
        let carrier = iOSBoardListCanvasTransitionCarrierFactory.makeCarrier(
            preferredKind: request.preferredCarrierKind
        )
        let session = iOSBoardListCanvasTransitionSession(
            context: request.transitionContext,
            carrier: carrier,
            sourceViewController: sourceViewController,
            destinationViewController: destinationViewController,
            debugTrace: request.debugTrace
        )

        activeTransitionSession = session
        transitionPhase = .closing
        setTransitionInteractionFrozen(true, for: sourceViewController)
        setTransitionInteractionFrozen(true, for: destinationViewController)
        activateTransitionOverlay()
        carrier.install(in: overlayHostView)
        mountViewController(destinationViewController, hidden: true)
        destinationViewController.setClosingTransitionTimingTrace(session.debugTrace)

        if let trace = session.debugTrace {
            logClosingTransitionTrace(
                trace,
                phase: "beginClosingTransition",
                extra: "targetBoardID=\(request.transitionContext.targetBoardID?.uuidString ?? "nil")"
            )
        }

        let carrierPreparationStart = BoardListCanvasTransitionDebugLogger.now()
        view.layoutIfNeeded()
        carrier.prepareTransition(
            with: session.context,
            sourceViewController: sourceViewController,
            destinationViewController: destinationViewController
        )
        if let trace = session.debugTrace {
            logClosingTransitionTrace(
                trace,
                phase: "carrierPrepareFinished",
                localDuration: BoardListCanvasTransitionDebugLogger.now() - carrierPreparationStart
            )
        }

        let targetBoardID = request.transitionContext.targetBoardID
        session.closingTargetGeometryRequestedAt = BoardListCanvasTransitionDebugLogger.now()
        if let trace = session.debugTrace {
            logClosingTransitionTrace(
                trace,
                phase: "requestTargetGeometry",
                extra: "targetBoardID=\(targetBoardID?.uuidString ?? "nil")"
            )
        }
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

        let geometryResolvedAt = BoardListCanvasTransitionDebugLogger.now()
        session.closingTargetGeometryResolvedAt = geometryResolvedAt
        updateCurrentTransitionTargetGeometry(
            geometry,
            expectedBoardID: expectedBoardID
        )
        session.context.targetGeometry = geometry
        session.carrier.updateTransitionContext(session.context)
        if let trace = session.debugTrace {
            let targetResolutionDuration = session.closingTargetGeometryRequestedAt.map {
                geometryResolvedAt - $0
            }
            logClosingTransitionTrace(
                trace,
                phase: "targetGeometryResolved",
                localDuration: targetResolutionDuration,
                extra:
                    "hasCardRect=\(geometry.cardRect != nil) " +
                    "hasFocusRect=\(geometry.focusRect != nil) " +
                    "expectedBoardID=\(expectedBoardID?.uuidString ?? "nil")"
            )
        }

        session.closingAnimationStartedAt = BoardListCanvasTransitionDebugLogger.now()
        if let trace = session.debugTrace {
            let backButtonToCarrierAnimate = session.closingAnimationStartedAt.map {
                $0 - trace.startedAtUptime
            }
            let requestTargetGeometryToResolved: TimeInterval? = {
                guard
                    let requestedAt = session.closingTargetGeometryRequestedAt,
                    let resolvedAt = session.closingTargetGeometryResolvedAt
                else {
                    return nil
                }

                return resolvedAt - requestedAt
            }()
            let backButtonToCarrierAnimateSummary = backButtonToCarrierAnimate.map {
                BoardListCanvasTransitionDebugLogger.durationString($0)
            } ?? "nil"
            let requestTargetGeometryToResolvedSummary = requestTargetGeometryToResolved.map {
                BoardListCanvasTransitionDebugLogger.durationString($0)
            } ?? "nil"
            logClosingTransitionTrace(
                trace,
                phase: "carrierAnimateBegin",
                extra:
                    "hasCardRect=\(geometry.cardRect != nil) " +
                    "hasFocusRect=\(geometry.focusRect != nil) " +
                    "backButtonToCarrierAnimate=\(backButtonToCarrierAnimateSummary) " +
                    "requestTargetGeometryToResolved=\(requestTargetGeometryToResolvedSummary)"
            )
        }
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
        (destinationViewController as? iOSBoardListViewController)?
            .setClosingTransitionTimingTrace(nil)
        setTransitionInteractionFrozen(false, for: session.sourceViewController)
        setTransitionInteractionFrozen(false, for: destinationViewController)
        currentViewController = destinationViewController
        session.carrier.completeTransition()
        if let trace = session.debugTrace {
            let animationDuration = session.closingAnimationStartedAt.map {
                BoardListCanvasTransitionDebugLogger.now() - $0
            }
            let backButtonToCarrierAnimate = session.closingAnimationStartedAt.map {
                $0 - trace.startedAtUptime
            }
            let requestTargetGeometryToResolved: TimeInterval? = {
                guard
                    let requestedAt = session.closingTargetGeometryRequestedAt,
                    let resolvedAt = session.closingTargetGeometryResolvedAt
                else {
                    return nil
                }

                return resolvedAt - requestedAt
            }()
            let backButtonToCarrierAnimateSummary = backButtonToCarrierAnimate.map {
                BoardListCanvasTransitionDebugLogger.durationString($0)
            } ?? "nil"
            let requestTargetGeometryToResolvedSummary = requestTargetGeometryToResolved.map {
                BoardListCanvasTransitionDebugLogger.durationString($0)
            } ?? "nil"
            let animationDurationSummary = animationDuration.map {
                BoardListCanvasTransitionDebugLogger.durationString($0)
            } ?? "nil"
            logClosingTransitionTrace(
                trace,
                phase: "completeClosingTransition",
                localDuration: animationDuration,
                extra:
                    "backButtonToCarrierAnimate=\(backButtonToCarrierAnimateSummary) " +
                    "requestTargetGeometryToResolved=\(requestTargetGeometryToResolvedSummary) " +
                    "animationDuration=\(animationDurationSummary)"
            )
        }
        activeTransitionSession = nil
        transitionPhase = .steadyBoardList
        deactivateTransitionOverlay()
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
        deactivateTransitionOverlay()
    }

    private func setCurrentViewControllerImmediately(
        _ viewController: UIViewController
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
        if let boardListViewController = session.destinationViewController as? iOSBoardListViewController {
            boardListViewController.setClosingTransitionTimingTrace(nil)
        }
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
        overlayHostView.isUserInteractionEnabled = true
        view.bringSubviewToFront(overlayHostView)
    }

    private func deactivateTransitionOverlay() {
        overlayHostView.isUserInteractionEnabled = false
        overlayHostView.isHidden = true
    }

    private func setTransitionInteractionFrozen(
        _ isFrozen: Bool,
        for viewController: UIViewController?
    ) {
        (viewController as? any iOSBoardListCanvasTransitionInteractionControlling)?
            .setTransitionInteractionFrozen(isFrozen)
    }

    private func logClosingTransitionTrace(
        _ trace: BoardListCanvasTransitionDebugTrace,
        phase: String,
        localDuration: TimeInterval? = nil,
        extra: String = ""
    ) {
        BoardListCanvasTransitionDebugLogger.log(
            platform: "iOS",
            component: "AppRoot",
            trace: trace,
            phase: phase,
            localDuration: localDuration,
            extra: extra
        )
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
