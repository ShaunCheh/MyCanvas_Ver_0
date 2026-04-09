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
        if let trace = request.debugTrace {
            logOpeningTransitionTrace(
                trace,
                phase: "handleCanvasOpenRequest",
                extra:
                    "targetBoardID=\(request.transitionContext.targetBoardID?.uuidString ?? "nil") " +
                    "preferredCarrierKind=\(describeCarrierKind(request.preferredCarrierKind))"
            )
        }
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

        if let trace = request.debugTrace {
            logOpeningTransitionTrace(
                trace,
                phase: "beginOpeningTransition",
                extra:
                    "targetBoardID=\(request.transitionContext.targetBoardID?.uuidString ?? "nil") " +
                    "preferredCarrierKind=\(describeCarrierKind(request.preferredCarrierKind))"
            )
        }

        let sourceViewController = currentViewController ?? boardListViewController
        let destinationViewController = makeCanvasViewController(
            for: request.launchContext
        )
        mountViewController(destinationViewController, hidden: true)
        view.layoutIfNeeded()
        let liveCanvasRequirements = resolveLiveCanvasCarrierRequirements(
            from: destinationViewController,
            preferredKind: request.preferredCarrierKind,
            transitionPhase: "opening",
            providerRole: "destination",
            debugTrace: request.debugTrace
        )
        let carrier = iOSBoardListCanvasTransitionCarrierFactory.makeCarrier(
            preferredKind: request.preferredCarrierKind,
            liveCanvasRequirements: liveCanvasRequirements,
            debugTrace: request.debugTrace
        )
        logCarrierSelectionTraceIfNeeded(
            request.debugTrace,
            transitionPhase: "opening",
            requestedKind: request.preferredCarrierKind,
            resolvedKind: carrier.kind,
            hasLiveCanvasRequirements: liveCanvasRequirements != nil
        )
        let session = iOSBoardListCanvasTransitionSession(
            context: request.transitionContext,
            carrier: carrier,
            sourceViewController: sourceViewController,
            destinationViewController: destinationViewController,
            debugTrace: request.debugTrace
        )

        activeTransitionSession = session
        transitionPhase = .opening
        setTransitionInteractionFrozen(true, for: sourceViewController)
        setTransitionInteractionFrozen(true, for: destinationViewController)
        activateTransitionOverlay()
        carrier.install(in: overlayHostView)
        let carrierPreparationStart = BoardListCanvasTransitionDebugLogger.now()
        carrier.prepareTransition(
            with: session.context,
            sourceViewController: sourceViewController,
            destinationViewController: destinationViewController
        )
        if let trace = session.debugTrace {
            logOpeningTransitionTrace(
                trace,
                phase: "carrierPrepareFinished",
                localDuration: BoardListCanvasTransitionDebugLogger.now() - carrierPreparationStart,
                extra: "carrierKind=\(describeCarrierKind(carrier.kind))"
            )
        }
        session.openingAnimationStartedAt = BoardListCanvasTransitionDebugLogger.now()
        if let trace = session.debugTrace {
            logOpeningTransitionTrace(
                trace,
                phase: "carrierAnimateBegin",
                extra: "carrierKind=\(describeCarrierKind(carrier.kind))"
            )
        }
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
        if let trace = session.debugTrace {
            let animationDuration = session.openingAnimationStartedAt.map {
                BoardListCanvasTransitionDebugLogger.now() - $0
            }
            let animationDurationSummary = animationDuration.map {
                BoardListCanvasTransitionDebugLogger.durationString($0)
            } ?? "nil"
            logOpeningTransitionTrace(
                trace,
                phase: "completeOpeningTransition",
                localDuration: animationDuration,
                extra:
                    "carrierKind=\(describeCarrierKind(session.carrier.kind)) " +
                    "animationDuration=\(animationDurationSummary)"
            )
        }
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
        mountViewController(destinationViewController, hidden: true)
        view.layoutIfNeeded()
        let liveCanvasRequirements = resolveLiveCanvasCarrierRequirements(
            from: sourceViewController,
            preferredKind: request.preferredCarrierKind,
            transitionPhase: "closing",
            providerRole: "source",
            debugTrace: request.debugTrace
        )
        let carrier = iOSBoardListCanvasTransitionCarrierFactory.makeCarrier(
            preferredKind: request.preferredCarrierKind,
            liveCanvasRequirements: liveCanvasRequirements,
            debugTrace: request.debugTrace
        )
        logCarrierSelectionTraceIfNeeded(
            request.debugTrace,
            transitionPhase: "closing",
            requestedKind: request.preferredCarrierKind,
            resolvedKind: carrier.kind,
            hasLiveCanvasRequirements: liveCanvasRequirements != nil
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

    private func resolveLiveCanvasCarrierRequirements(
        from viewController: UIViewController?,
        preferredKind: BoardListCanvasTransitionCarrierKind,
        transitionPhase: String,
        providerRole: String,
        debugTrace: BoardListCanvasTransitionDebugTrace?
    ) -> iOSLiveCanvasCarrierRequirements? {
        guard let viewController else {
            logLiveCanvasCarrierFallbackIfNeeded(
                preferredKind: preferredKind,
                transitionPhase: transitionPhase,
                reason: "\(providerRole)ViewControllerMissing",
                debugTrace: debugTrace
            )
            return nil
        }

        viewController.loadViewIfNeeded()
        viewController.view.layoutIfNeeded()

        guard let provider = viewController as? CanvasTransitionLiveContentProviding else {
            logLiveCanvasCarrierFallbackIfNeeded(
                preferredKind: preferredKind,
                transitionPhase: transitionPhase,
                reason: "\(providerRole)ProviderMissing",
                debugTrace: debugTrace
            )
            return nil
        }

        if preferredKind == .liveCanvas, let debugTrace {
            logTransitionTrace(
                debugTrace,
                phase: "liveRequirementsReady",
                extra:
                    "transitionPhase=\(transitionPhase) " +
                    "providerRole=\(providerRole)"
            )
        }

        return iOSLiveCanvasCarrierRequirements(
            canvasViewProvider: { [weak provider] in
                provider?.transitionCanvasViewportView
            },
            canvasContainerViewProvider: { [weak provider] in
                provider?.transitionCanvasHostView
            },
            isTransitionChromeHidden: { [weak provider] in
                provider?.isTransitionChromeHidden ?? false
            },
            setTransitionChromeHidden: { [weak provider] isHidden in
                provider?.setTransitionChromeHidden(isHidden)
            }
        )
    }

    private func logLiveCanvasCarrierFallbackIfNeeded(
        preferredKind: BoardListCanvasTransitionCarrierKind,
        transitionPhase: String,
        reason: String,
        debugTrace: BoardListCanvasTransitionDebugTrace?
    ) {
        guard preferredKind == .liveCanvas else {
            return
        }

        print(
            "[BoardListCanvasTransition][iOS][AppRoot] " +
                "phase=liveCanvasCarrierFallback " +
                "transitionPhase=\(transitionPhase) " +
                "reason=\(reason)"
        )
        if let debugTrace {
            logTransitionTrace(
                debugTrace,
                phase: "liveFallbackTriggered",
                extra:
                    "transitionPhase=\(transitionPhase) " +
                    "source=appRootRequirements " +
                    "reason=\(reason)"
            )
        }
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

        if let trace = session.debugTrace {
            logTransitionTrace(
                trace,
                phase: "discardActiveTransition",
                extra:
                    "transitionPhase=\(transitionPhase.rawValue) " +
                    "carrierKind=\(describeCarrierKind(session.carrier.kind))"
            )
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

    private func logTransitionTrace(
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

    private func logOpeningTransitionTrace(
        _ trace: BoardListCanvasTransitionDebugTrace,
        phase: String,
        localDuration: TimeInterval? = nil,
        extra: String = ""
    ) {
        logTransitionTrace(
            trace,
            phase: phase,
            localDuration: localDuration,
            extra: extra
        )
    }

    private func logCarrierSelectionTraceIfNeeded(
        _ trace: BoardListCanvasTransitionDebugTrace?,
        transitionPhase: String,
        requestedKind: BoardListCanvasTransitionCarrierKind,
        resolvedKind: BoardListCanvasTransitionCarrierKind,
        hasLiveCanvasRequirements: Bool
    ) {
        guard let trace else {
            return
        }

        logTransitionTrace(
            trace,
            phase: "carrierSelected",
            extra:
                "transitionPhase=\(transitionPhase) " +
                "requestedKind=\(describeCarrierKind(requestedKind)) " +
                "resolvedKind=\(describeCarrierKind(resolvedKind)) " +
                "hasLiveCanvasRequirements=\(hasLiveCanvasRequirements)"
        )
    }

    private func logClosingTransitionTrace(
        _ trace: BoardListCanvasTransitionDebugTrace,
        phase: String,
        localDuration: TimeInterval? = nil,
        extra: String = ""
    ) {
        logTransitionTrace(
            trace,
            phase: phase,
            localDuration: localDuration,
            extra: extra
        )
    }

    private func describeCarrierKind(
        _ carrierKind: BoardListCanvasTransitionCarrierKind
    ) -> String {
        switch carrierKind {
        case .snapshotShell:
            return "snapshotShell"
        case .liveCanvas:
            return "liveCanvas"
        }
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
