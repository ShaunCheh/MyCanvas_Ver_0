import CoreGraphics
import Foundation

enum CanvasAlignmentCoordinateAxis: CaseIterable {
    case x
    case y
}

enum CanvasAlignmentGuideOrientation: CaseIterable {
    case horizontal
    case vertical
}

enum CanvasAlignmentAnchor: CaseIterable {
    case left
    case centerX
    case right
    case top
    case centerY
    case bottom

    var axis: CanvasAlignmentCoordinateAxis {
        switch self {
        case .left, .centerX, .right:
            return .x
        case .top, .centerY, .bottom:
            return .y
        }
    }

    var guideOrientation: CanvasAlignmentGuideOrientation {
        switch axis {
        case .x:
            return .vertical
        case .y:
            return .horizontal
        }
    }

    func coordinate(in rect: CGRect) -> CGFloat {
        let standardizedRect = rect.standardized
        switch self {
        case .left:
            return standardizedRect.minX
        case .centerX:
            return standardizedRect.midX
        case .right:
            return standardizedRect.maxX
        case .top:
            return standardizedRect.minY
        case .centerY:
            return standardizedRect.midY
        case .bottom:
            return standardizedRect.maxY
        }
    }
}

enum CanvasAlignmentReferenceSource: Equatable {
    case board
    case item(CanvasItemID)
}

struct CanvasAlignmentGuide: Equatable {
    let orientation: CanvasAlignmentGuideOrientation
    let worldStart: CGPoint
    let worldEnd: CGPoint
    let movingAnchor: CanvasAlignmentAnchor
    let referenceAnchor: CanvasAlignmentAnchor
    let referenceSource: CanvasAlignmentReferenceSource
}

struct CanvasAlignmentMatch: Equatable {
    let movingAnchor: CanvasAlignmentAnchor
    let referenceAnchor: CanvasAlignmentAnchor
    let referenceSource: CanvasAlignmentReferenceSource
    let referenceCoordinate: CGFloat
    let distanceInWorld: CGFloat
}

struct CanvasAlignmentAxisLock: Equatable {
    let movingAnchor: CanvasAlignmentAnchor
    let referenceAnchor: CanvasAlignmentAnchor
    let referenceSource: CanvasAlignmentReferenceSource

    var axis: CanvasAlignmentCoordinateAxis {
        movingAnchor.axis
    }

    init(
        movingAnchor: CanvasAlignmentAnchor,
        referenceAnchor: CanvasAlignmentAnchor,
        referenceSource: CanvasAlignmentReferenceSource
    ) {
        self.movingAnchor = movingAnchor
        self.referenceAnchor = referenceAnchor
        self.referenceSource = referenceSource
    }

    init(match: CanvasAlignmentMatch) {
        self.init(
            movingAnchor: match.movingAnchor,
            referenceAnchor: match.referenceAnchor,
            referenceSource: match.referenceSource
        )
    }
}

struct CanvasAlignmentLockState: Equatable {
    let xAxis: CanvasAlignmentAxisLock?
    let yAxis: CanvasAlignmentAxisLock?

    static let none = CanvasAlignmentLockState()

    init(
        xAxis: CanvasAlignmentAxisLock? = nil,
        yAxis: CanvasAlignmentAxisLock? = nil
    ) {
        self.xAxis = xAxis
        self.yAxis = yAxis
    }

    var isActive: Bool {
        xAxis != nil || yAxis != nil
    }
}

struct CanvasAlignmentSolverConfiguration: Equatable {
    let snapEnterThresholdInViewport: CGFloat
    let snapReleaseThresholdInViewport: CGFloat
    let searchPaddingInViewport: CGFloat

    init(
        snapEnterThresholdInViewport: CGFloat = 8,
        snapReleaseThresholdInViewport: CGFloat = 12,
        searchPaddingInViewport: CGFloat = 160
    ) {
        let clampedEnterThreshold = max(snapEnterThresholdInViewport, 0)
        self.snapEnterThresholdInViewport = clampedEnterThreshold
        self.snapReleaseThresholdInViewport = max(
            snapReleaseThresholdInViewport,
            clampedEnterThreshold
        )
        self.searchPaddingInViewport = max(searchPaddingInViewport, 0)
    }

    static let `default` = CanvasAlignmentSolverConfiguration()
}

struct CanvasAlignmentSolveRequest {
    let movingItemID: CanvasItemID
    let proposedCenter: CGPoint
    let scene: CanvasScene
    let boardState: CanvasBoardState?
    let camera: CanvasCamera
    let lockState: CanvasAlignmentLockState

    init(
        movingItemID: CanvasItemID,
        proposedCenter: CGPoint,
        scene: CanvasScene,
        boardState: CanvasBoardState?,
        camera: CanvasCamera,
        lockState: CanvasAlignmentLockState = .none
    ) {
        self.movingItemID = movingItemID
        self.proposedCenter = proposedCenter
        self.scene = scene
        self.boardState = boardState
        self.camera = camera
        self.lockState = lockState
    }
}

struct CanvasAlignmentSolveResult {
    let resolvedCenter: CGPoint
    let interactionState: CanvasAlignmentInteractionState?
    let lockState: CanvasAlignmentLockState

    static func passthrough(
        proposedCenter: CGPoint,
        lockState: CanvasAlignmentLockState = .none
    ) -> CanvasAlignmentSolveResult {
        CanvasAlignmentSolveResult(
            resolvedCenter: proposedCenter,
            interactionState: nil,
            lockState: lockState
        )
    }
}

// Alignment solving stays axis-aligned in v1: all snap candidates come from
// board/item world frames plus centers, not rotated quads or transformed edges.
struct CanvasAlignmentGuideSolver {
    var configuration: CanvasAlignmentSolverConfiguration = .default

    func solve(
        _ request: CanvasAlignmentSolveRequest
    ) -> CanvasAlignmentSolveResult {
        guard let movingItem = request.scene.boardItem(withID: request.movingItemID) else {
            return CanvasAlignmentSolveResult.passthrough(
                proposedCenter: request.proposedCenter,
                lockState: .none
            )
        }

        let proposedFrame = worldFrame(
            size: movingItem.size,
            centeredAt: request.proposedCenter
        )
        let searchRect = searchWorldRect(
            movingFrame: proposedFrame,
            camera: request.camera
        )
        let references = alignmentReferences(
            in: request.scene,
            boardState: request.boardState,
            searchRect: searchRect,
            excluding: request.movingItemID
        )
        guard references.isEmpty == false else {
            return CanvasAlignmentSolveResult.passthrough(
                proposedCenter: request.proposedCenter,
                lockState: .none
            )
        }

        let enterThresholdInWorld = max(
            request.camera.worldDistance(
                forViewportDistance: configuration.snapEnterThresholdInViewport
            ),
            0
        )
        let releaseThresholdInWorld = max(
            request.camera.worldDistance(
                forViewportDistance: configuration.snapReleaseThresholdInViewport
            ),
            enterThresholdInWorld
        )
        let xCandidate = bestCandidate(
            for: proposedFrame,
            axis: .x,
            references: references,
            enterThresholdInWorld: enterThresholdInWorld,
            releaseThresholdInWorld: releaseThresholdInWorld,
            previousLock: request.lockState.xAxis
        )
        let yCandidate = bestCandidate(
            for: proposedFrame,
            axis: .y,
            references: references,
            enterThresholdInWorld: enterThresholdInWorld,
            releaseThresholdInWorld: releaseThresholdInWorld,
            previousLock: request.lockState.yAxis
        )
        guard xCandidate != nil || yCandidate != nil else {
            return CanvasAlignmentSolveResult.passthrough(
                proposedCenter: request.proposedCenter,
                lockState: .none
            )
        }

        let resolvedCenter = CGPoint(
            x: request.proposedCenter.x + (xCandidate?.deltaInWorld ?? 0),
            y: request.proposedCenter.y + (yCandidate?.deltaInWorld ?? 0)
        )
        let lockState = CanvasAlignmentLockState(
            xAxis: xCandidate?.axisLock,
            yAxis: yCandidate?.axisLock
        )
        logSolveDiagnostics(
            movingItem: movingItem,
            proposedCenter: request.proposedCenter,
            resolvedCenter: resolvedCenter,
            camera: request.camera,
            enterThresholdInWorld: enterThresholdInWorld,
            releaseThresholdInWorld: releaseThresholdInWorld,
            xCandidate: xCandidate,
            yCandidate: yCandidate
        )
        let resolvedFrame = worldFrame(
            size: movingItem.size,
            centeredAt: resolvedCenter
        )
        let guides = [
            xCandidate.map { guide(for: $0, movingFrame: resolvedFrame) },
            yCandidate.map { guide(for: $0, movingFrame: resolvedFrame) }
        ].compactMap { $0 }
        let interactionState = CanvasAlignmentInteractionState(
            itemID: request.movingItemID,
            guides: guides,
            xMatch: xCandidate?.match,
            yMatch: yCandidate?.match
        )
        return CanvasAlignmentSolveResult(
            resolvedCenter: resolvedCenter,
            interactionState: interactionState.isActive ? interactionState : nil,
            lockState: lockState
        )
    }

    private func logSolveDiagnostics(
        movingItem: CanvasBoardItem,
        proposedCenter: CGPoint,
        resolvedCenter: CGPoint,
        camera: CanvasCamera,
        enterThresholdInWorld: CGFloat,
        releaseThresholdInWorld: CGFloat,
        xCandidate: CanvasAlignmentAxisCandidate?,
        yCandidate: CanvasAlignmentAxisCandidate?
    ) {
        guard canvasAlignmentDiagnosticLoggingEnabled else {
            return
        }

        let rawDeltaInWorld = CGPoint(
            x: proposedCenter.x - movingItem.center.x,
            y: proposedCenter.y - movingItem.center.y
        )
        let resolvedDeltaInWorld = CGPoint(
            x: resolvedCenter.x - movingItem.center.x,
            y: resolvedCenter.y - movingItem.center.y
        )
        let solverCorrectionInWorld = CGPoint(
            x: resolvedCenter.x - proposedCenter.x,
            y: resolvedCenter.y - proposedCenter.y
        )
        let xAxisPinned = xCandidate != nil &&
            abs(rawDeltaInWorld.x) > canvasAlignmentComparisonEpsilon &&
            abs(resolvedDeltaInWorld.x) <= canvasAlignmentComparisonEpsilon
        let yAxisPinned = yCandidate != nil &&
            abs(rawDeltaInWorld.y) > canvasAlignmentComparisonEpsilon &&
            abs(resolvedDeltaInWorld.y) <= canvasAlignmentComparisonEpsilon

        print(
            "[Canvas Alignment][Solver] " +
            "itemID=\(movingItem.id.uuidString) " +
            "centerBefore=\(describeAlignmentPoint(movingItem.center)) " +
            "rawDelta=\(describeAlignmentPoint(rawDeltaInWorld)) " +
            "proposedCenter=\(describeAlignmentPoint(proposedCenter)) " +
            "resolvedCenter=\(describeAlignmentPoint(resolvedCenter)) " +
            "resolvedDelta=\(describeAlignmentPoint(resolvedDeltaInWorld)) " +
            "solverCorrection=\(describeAlignmentPoint(solverCorrectionInWorld)) " +
            "zoom=\(formatAlignmentValue(camera.zoomScale)) " +
            "enterThresholdWorld=\(formatAlignmentValue(enterThresholdInWorld)) " +
            "releaseThresholdWorld=\(formatAlignmentValue(releaseThresholdInWorld)) " +
            "enterThresholdViewport=\(formatAlignmentValue(configuration.snapEnterThresholdInViewport)) " +
            "releaseThresholdViewport=\(formatAlignmentValue(configuration.snapReleaseThresholdInViewport)) " +
            "xMatch=\(describeAlignmentMatch(xCandidate?.match, zoomScale: camera.zoomScale)) " +
            "yMatch=\(describeAlignmentMatch(yCandidate?.match, zoomScale: camera.zoomScale)) " +
            "xAxisPinned=\(xAxisPinned) " +
            "yAxisPinned=\(yAxisPinned)"
        )
    }

    private func searchWorldRect(
        movingFrame: CGRect,
        camera: CanvasCamera
    ) -> CGRect {
        let viewportBounds = camera.viewportBounds
        guard viewportBounds.width > 0, viewportBounds.height > 0 else {
            let paddingInWorld = max(
                camera.worldDistance(
                    forViewportDistance: configuration.searchPaddingInViewport
                ),
                0
            )
            return movingFrame
                .insetBy(dx: -paddingInWorld, dy: -paddingInWorld)
                .standardized
        }

        return camera.expandedVisibleWorldRect(
            paddingInViewport: configuration.searchPaddingInViewport
        ).standardized
    }

    private func alignmentReferences(
        in scene: CanvasScene,
        boardState: CanvasBoardState?,
        searchRect: CGRect,
        excluding movingItemID: CanvasItemID
    ) -> [CanvasAlignmentReference] {
        var references = scene
            .visibleBoardItems(in: searchRect)
            .filter { $0.id != movingItemID }
            .map {
                CanvasAlignmentReference(
                    source: .item($0.id),
                    frame: $0.worldFrame.standardized
                )
            }

        if let boardState {
            references.append(
                CanvasAlignmentReference(
                    source: .board,
                    frame: boardState.worldRect.standardized
                )
            )
        }

        return references
    }

    private func bestCandidate(
        for movingFrame: CGRect,
        axis: CanvasAlignmentCoordinateAxis,
        references: [CanvasAlignmentReference],
        enterThresholdInWorld: CGFloat,
        releaseThresholdInWorld: CGFloat,
        previousLock: CanvasAlignmentAxisLock?
    ) -> CanvasAlignmentAxisCandidate? {
        if let previousLock,
           let lockedCandidate = lockedCandidate(
                for: movingFrame,
                axis: axis,
                references: references,
                previousLock: previousLock,
                releaseThresholdInWorld: releaseThresholdInWorld
           )
        {
            return lockedCandidate
        }

        return bestEnteringCandidate(
            for: movingFrame,
            axis: axis,
            references: references,
            thresholdInWorld: enterThresholdInWorld
        )
    }

    private func bestEnteringCandidate(
        for movingFrame: CGRect,
        axis: CanvasAlignmentCoordinateAxis,
        references: [CanvasAlignmentReference],
        thresholdInWorld: CGFloat
    ) -> CanvasAlignmentAxisCandidate? {
        let anchors = anchors(for: axis)
        var bestCandidate: CanvasAlignmentAxisCandidate?

        for reference in references {
            for anchor in anchors {
                let movingCoordinate = anchor.coordinate(in: movingFrame)
                let referenceCoordinate = anchor.coordinate(in: reference.frame)
                let deltaInWorld = referenceCoordinate - movingCoordinate
                let distanceInWorld = abs(deltaInWorld)
                guard distanceInWorld <= thresholdInWorld else {
                    continue
                }

                let candidate = CanvasAlignmentAxisCandidate(
                    match: CanvasAlignmentMatch(
                        movingAnchor: anchor,
                        referenceAnchor: anchor,
                        referenceSource: reference.source,
                        referenceCoordinate: referenceCoordinate,
                        distanceInWorld: distanceInWorld
                    ),
                    deltaInWorld: deltaInWorld,
                    referenceFrame: reference.frame,
                    orthogonalOverlap: orthogonalOverlap(
                        between: movingFrame,
                        and: reference.frame,
                        for: axis
                    ),
                    orthogonalCenterDistance: orthogonalCenterDistance(
                        between: movingFrame,
                        and: reference.frame,
                        for: axis
                    )
                )
                if isBetter(candidate, than: bestCandidate) {
                    bestCandidate = candidate
                }
            }
        }

        return bestCandidate
    }

    private func lockedCandidate(
        for movingFrame: CGRect,
        axis: CanvasAlignmentCoordinateAxis,
        references: [CanvasAlignmentReference],
        previousLock: CanvasAlignmentAxisLock,
        releaseThresholdInWorld: CGFloat
    ) -> CanvasAlignmentAxisCandidate? {
        guard previousLock.axis == axis else {
            return nil
        }

        guard let reference = reference(
            for: previousLock.referenceSource,
            in: references
        ) else {
            return nil
        }

        let movingCoordinate = previousLock.movingAnchor.coordinate(in: movingFrame)
        let referenceCoordinate = previousLock.referenceAnchor.coordinate(
            in: reference.frame
        )
        let deltaInWorld = referenceCoordinate - movingCoordinate
        let distanceInWorld = abs(deltaInWorld)
        guard distanceInWorld <= releaseThresholdInWorld else {
            return nil
        }

        return CanvasAlignmentAxisCandidate(
            match: CanvasAlignmentMatch(
                movingAnchor: previousLock.movingAnchor,
                referenceAnchor: previousLock.referenceAnchor,
                referenceSource: previousLock.referenceSource,
                referenceCoordinate: referenceCoordinate,
                distanceInWorld: distanceInWorld
            ),
            deltaInWorld: deltaInWorld,
            referenceFrame: reference.frame,
            orthogonalOverlap: orthogonalOverlap(
                between: movingFrame,
                and: reference.frame,
                for: axis
            ),
            orthogonalCenterDistance: orthogonalCenterDistance(
                between: movingFrame,
                and: reference.frame,
                for: axis
            )
        )
    }

    private func reference(
        for source: CanvasAlignmentReferenceSource,
        in references: [CanvasAlignmentReference]
    ) -> CanvasAlignmentReference? {
        references.first { $0.source == source }
    }

    private func guide(
        for candidate: CanvasAlignmentAxisCandidate,
        movingFrame: CGRect
    ) -> CanvasAlignmentGuide {
        let referenceFrame = candidate.referenceFrame.standardized
        switch candidate.match.movingAnchor.axis {
        case .x:
            let x = candidate.match.referenceCoordinate
            return CanvasAlignmentGuide(
                orientation: .vertical,
                worldStart: CGPoint(
                    x: x,
                    y: min(movingFrame.minY, referenceFrame.minY)
                ),
                worldEnd: CGPoint(
                    x: x,
                    y: max(movingFrame.maxY, referenceFrame.maxY)
                ),
                movingAnchor: candidate.match.movingAnchor,
                referenceAnchor: candidate.match.referenceAnchor,
                referenceSource: candidate.match.referenceSource
            )
        case .y:
            let y = candidate.match.referenceCoordinate
            return CanvasAlignmentGuide(
                orientation: .horizontal,
                worldStart: CGPoint(
                    x: min(movingFrame.minX, referenceFrame.minX),
                    y: y
                ),
                worldEnd: CGPoint(
                    x: max(movingFrame.maxX, referenceFrame.maxX),
                    y: y
                ),
                movingAnchor: candidate.match.movingAnchor,
                referenceAnchor: candidate.match.referenceAnchor,
                referenceSource: candidate.match.referenceSource
            )
        }
    }

    private func anchors(
        for axis: CanvasAlignmentCoordinateAxis
    ) -> [CanvasAlignmentAnchor] {
        switch axis {
        case .x:
            return [.left, .centerX, .right]
        case .y:
            return [.top, .centerY, .bottom]
        }
    }

    private func isBetter(
        _ candidate: CanvasAlignmentAxisCandidate,
        than currentBest: CanvasAlignmentAxisCandidate?
    ) -> Bool {
        guard let currentBest else {
            return true
        }

        if candidate.match.distanceInWorld < currentBest.match.distanceInWorld - canvasAlignmentComparisonEpsilon {
            return true
        }
        if candidate.match.distanceInWorld > currentBest.match.distanceInWorld + canvasAlignmentComparisonEpsilon {
            return false
        }

        if candidate.orthogonalOverlap > currentBest.orthogonalOverlap + canvasAlignmentComparisonEpsilon {
            return true
        }
        if candidate.orthogonalOverlap < currentBest.orthogonalOverlap - canvasAlignmentComparisonEpsilon {
            return false
        }

        if candidate.orthogonalCenterDistance < currentBest.orthogonalCenterDistance - canvasAlignmentComparisonEpsilon {
            return true
        }
        if candidate.orthogonalCenterDistance > currentBest.orthogonalCenterDistance + canvasAlignmentComparisonEpsilon {
            return false
        }

        return false
    }

    private func orthogonalOverlap(
        between lhs: CGRect,
        and rhs: CGRect,
        for axis: CanvasAlignmentCoordinateAxis
    ) -> CGFloat {
        switch axis {
        case .x:
            return overlapLength(
                lhsMinimum: lhs.minY,
                lhsMaximum: lhs.maxY,
                rhsMinimum: rhs.minY,
                rhsMaximum: rhs.maxY
            )
        case .y:
            return overlapLength(
                lhsMinimum: lhs.minX,
                lhsMaximum: lhs.maxX,
                rhsMinimum: rhs.minX,
                rhsMaximum: rhs.maxX
            )
        }
    }

    private func orthogonalCenterDistance(
        between lhs: CGRect,
        and rhs: CGRect,
        for axis: CanvasAlignmentCoordinateAxis
    ) -> CGFloat {
        switch axis {
        case .x:
            return abs(lhs.midY - rhs.midY)
        case .y:
            return abs(lhs.midX - rhs.midX)
        }
    }

    private func overlapLength(
        lhsMinimum: CGFloat,
        lhsMaximum: CGFloat,
        rhsMinimum: CGFloat,
        rhsMaximum: CGFloat
    ) -> CGFloat {
        max(0, min(lhsMaximum, rhsMaximum) - max(lhsMinimum, rhsMinimum))
    }

    private func worldFrame(
        size: CGSize,
        centeredAt center: CGPoint
    ) -> CGRect {
        CGRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        ).standardized
    }
}

private struct CanvasAlignmentReference {
    let source: CanvasAlignmentReferenceSource
    let frame: CGRect
}

private struct CanvasAlignmentAxisCandidate {
    let match: CanvasAlignmentMatch
    let deltaInWorld: CGFloat
    let referenceFrame: CGRect
    let orthogonalOverlap: CGFloat
    let orthogonalCenterDistance: CGFloat

    var axisLock: CanvasAlignmentAxisLock {
        CanvasAlignmentAxisLock(match: match)
    }
}

private let canvasAlignmentDiagnosticLoggingEnabled = false
private let canvasAlignmentComparisonEpsilon: CGFloat = 0.0001

private func describeAlignmentPoint(_ point: CGPoint) -> String {
    "{\(formatAlignmentValue(point.x)), \(formatAlignmentValue(point.y))}"
}

private func describeAlignmentMatch(
    _ match: CanvasAlignmentMatch?,
    zoomScale: CGFloat
) -> String {
    guard let match else {
        return "nil"
    }

    return
        "moving=\(String(describing: match.movingAnchor)) " +
        "reference=\(String(describing: match.referenceAnchor)) " +
        "source=\(describeAlignmentReferenceSource(match.referenceSource)) " +
        "coordinate=\(formatAlignmentValue(match.referenceCoordinate)) " +
        "distanceWorld=\(formatAlignmentValue(match.distanceInWorld)) " +
        "distanceViewport=\(formatAlignmentValue(match.distanceInWorld * zoomScale))"
}

private func describeAlignmentReferenceSource(
    _ source: CanvasAlignmentReferenceSource
) -> String {
    switch source {
    case .board:
        return "board"
    case let .item(itemID):
        return "item(\(itemID.uuidString))"
    }
}

private func formatAlignmentValue(_ value: CGFloat) -> String {
    String(format: "%.3f", Double(value))
}

extension CanvasCamera {
    func worldDistance(
        forViewportDistance viewportDistance: CGFloat
    ) -> CGFloat {
        guard zoomScale > 0 else {
            return viewportDistance
        }

        return viewportDistance / zoomScale
    }

    func expandedVisibleWorldRect(
        paddingInViewport viewportPadding: CGFloat
    ) -> CGRect {
        let paddingInWorld = worldDistance(
            forViewportDistance: max(viewportPadding, 0)
        )
        return visibleWorldRect.insetBy(
            dx: -paddingInWorld,
            dy: -paddingInWorld
        )
    }
}
