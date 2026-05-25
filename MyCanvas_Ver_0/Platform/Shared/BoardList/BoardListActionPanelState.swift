import CoreGraphics
import Foundation

enum BoardListActionID: String, Hashable, Sendable {
    case rename
    case delete
}

enum BoardListActionRole: Hashable, Sendable {
    case standard
    case destructive
}

struct BoardListActionState: Hashable, Sendable {
    let id: BoardListActionID
    let title: String
    let systemImageName: String?
    let role: BoardListActionRole
    let isEnabled: Bool

    static func rename(
        isEnabled: Bool = true
    ) -> BoardListActionState {
        BoardListActionState(
            id: .rename,
            title: "Rename",
            systemImageName: "pencil",
            role: .standard,
            isEnabled: isEnabled
        )
    }

    static func delete(
        isEnabled: Bool = true
    ) -> BoardListActionState {
        BoardListActionState(
            id: .delete,
            title: "Delete",
            systemImageName: "trash",
            role: .destructive,
            isEnabled: isEnabled
        )
    }
}

struct BoardListActionPanelState: Hashable, Sendable {
    let boardID: UUID
    let layoutAnchorPoint: CGPoint
    let actionStates: [BoardListActionState]

    var isEmpty: Bool {
        actionStates.isEmpty
    }

    static func renameMenu(
        boardID: UUID,
        anchorPoint: CGPoint,
        isRenameEnabled: Bool = true,
        isDeleteEnabled: Bool = true
    ) -> BoardListActionPanelState {
        BoardListActionPanelState(
            boardID: boardID,
            layoutAnchorPoint: anchorPoint,
            actionStates: [
                .rename(isEnabled: isRenameEnabled),
                .delete(isEnabled: isDeleteEnabled)
            ]
        )
    }
}

struct BoardListActionPanelLayoutContext: Hashable, Sendable {
    var safeBounds: CGRect
    var occupiedRects: [CGRect]

    init(
        safeBounds: CGRect,
        occupiedRects: [CGRect] = []
    ) {
        self.safeBounds = BoardListActionPanelLayoutGeometry.sanitizedRect(safeBounds) ?? .zero
        self.occupiedRects = occupiedRects.compactMap {
            BoardListActionPanelLayoutGeometry.sanitizedRect($0)
        }
    }
}

struct BoardListActionPanelLayoutConfiguration: Hashable, Sendable {
    var minimumWidth: CGFloat = 164
    var maximumWidth: CGFloat = 280
    var edgeInset: CGFloat = 16
    var anchorSpacing: CGFloat = 10
    var blockerClearance: CGFloat = 8
}

struct BoardListActionPanelLayoutSolver {
    func resolvePanelFrame(
        anchorPoint: CGPoint,
        preferredSize: CGSize,
        layoutContext: BoardListActionPanelLayoutContext,
        configuration: BoardListActionPanelLayoutConfiguration = BoardListActionPanelLayoutConfiguration()
    ) -> CGRect? {
        let layoutBounds = layoutContext.safeBounds
            .standardized
            .insetBy(dx: configuration.edgeInset, dy: configuration.edgeInset)
            .standardized
        guard
            layoutBounds.width > 0,
            layoutBounds.height > 0
        else {
            return nil
        }

        let panelSize = resolvedPanelSize(
            from: preferredSize,
            within: layoutBounds.size,
            configuration: configuration
        )
        guard panelSize.width > 0, panelSize.height > 0 else {
            return nil
        }

        let blockerRects = layoutContext.occupiedRects
            .map(\.standardized)
            .filter { $0.isEmpty == false }
            .map {
                $0.insetBy(
                    dx: -configuration.blockerClearance,
                    dy: -configuration.blockerClearance
                )
            }

        var bestFrame: CGRect?
        var bestScore = CGFloat.greatestFiniteMagnitude

        for placement in Placement.allCases {
            let rawFrame = frame(
                around: anchorPoint,
                size: panelSize,
                placement: placement,
                anchorSpacing: configuration.anchorSpacing
            )
            let clampedFrame = clampedFrame(rawFrame, within: layoutBounds)
            let overlapScore = totalOverlapArea(of: clampedFrame, with: blockerRects)
            let clampScore = clampDistance(between: rawFrame, and: clampedFrame)
            let candidateScore = overlapScore * 10_000 + clampScore + placement.preferenceScore

            if overlapScore == 0, clampScore == 0 {
                return clampedFrame.standardized
            }

            if candidateScore < bestScore {
                bestScore = candidateScore
                bestFrame = clampedFrame.standardized
            }
        }

        return bestFrame
    }

    private func resolvedPanelSize(
        from preferredSize: CGSize,
        within layoutSize: CGSize,
        configuration: BoardListActionPanelLayoutConfiguration
    ) -> CGSize {
        let sanitizedSize = BoardListActionPanelLayoutGeometry.sanitizedSize(preferredSize)
        let maxWidth = min(configuration.maximumWidth, layoutSize.width)
        let width = min(
            max(max(sanitizedSize.width, configuration.minimumWidth), 0),
            maxWidth
        )
        let height = min(max(sanitizedSize.height, 0), layoutSize.height)
        return CGSize(width: width, height: height)
    }

    private func frame(
        around anchorPoint: CGPoint,
        size: CGSize,
        placement: Placement,
        anchorSpacing: CGFloat
    ) -> CGRect {
        let originX: CGFloat
        switch placement.horizontalAlignment {
        case .leading:
            originX = anchorPoint.x
        case .trailing:
            originX = anchorPoint.x - size.width
        }

        let originY: CGFloat
        switch placement.verticalAlignment {
        case .below:
            originY = anchorPoint.y + anchorSpacing
        case .above:
            originY = anchorPoint.y - anchorSpacing - size.height
        }

        return CGRect(origin: CGPoint(x: originX, y: originY), size: size)
    }

    private func clampedFrame(
        _ frame: CGRect,
        within layoutBounds: CGRect
    ) -> CGRect {
        var clampedFrame = frame.standardized
        clampedFrame.origin.x = min(
            max(clampedFrame.origin.x, layoutBounds.minX),
            layoutBounds.maxX - clampedFrame.width
        )
        clampedFrame.origin.y = min(
            max(clampedFrame.origin.y, layoutBounds.minY),
            layoutBounds.maxY - clampedFrame.height
        )
        return clampedFrame.standardized
    }

    private func clampDistance(
        between rawFrame: CGRect,
        and clampedFrame: CGRect
    ) -> CGFloat {
        abs(rawFrame.minX - clampedFrame.minX) +
            abs(rawFrame.minY - clampedFrame.minY) +
            abs(rawFrame.maxX - clampedFrame.maxX) +
            abs(rawFrame.maxY - clampedFrame.maxY)
    }

    private func totalOverlapArea(
        of frame: CGRect,
        with blockerRects: [CGRect]
    ) -> CGFloat {
        blockerRects.reduce(0) { partialResult, blockerRect in
            let intersection = frame.intersection(blockerRect)
            guard intersection.isNull == false else {
                return partialResult
            }

            return partialResult + (intersection.width * intersection.height)
        }
    }
}

private enum BoardListActionPanelLayoutGeometry {
    static func sanitizedRect(_ rect: CGRect) -> CGRect? {
        guard rect.isNull == false, rect.isInfinite == false else {
            return nil
        }

        let standardizedRect = rect.standardized
        guard
            standardizedRect.width > 0,
            standardizedRect.height > 0
        else {
            return nil
        }

        return standardizedRect
    }

    static func sanitizedSize(_ size: CGSize) -> CGSize {
        guard
            size.width.isFinite,
            size.height.isFinite
        else {
            return .zero
        }

        return CGSize(
            width: max(size.width, 0),
            height: max(size.height, 0)
        )
    }
}

private enum Placement: CaseIterable {
    case trailingBelow
    case leadingBelow
    case trailingAbove
    case leadingAbove

    var horizontalAlignment: HorizontalAlignment {
        switch self {
        case .trailingBelow, .trailingAbove:
            return .trailing
        case .leadingBelow, .leadingAbove:
            return .leading
        }
    }

    var verticalAlignment: VerticalAlignment {
        switch self {
        case .trailingBelow, .leadingBelow:
            return .below
        case .trailingAbove, .leadingAbove:
            return .above
        }
    }

    var preferenceScore: CGFloat {
        switch self {
        case .trailingBelow:
            return 0
        case .leadingBelow:
            return 1
        case .trailingAbove:
            return 2
        case .leadingAbove:
            return 3
        }
    }
}

private enum HorizontalAlignment {
    case leading
    case trailing
}

private enum VerticalAlignment {
    case above
    case below
}
