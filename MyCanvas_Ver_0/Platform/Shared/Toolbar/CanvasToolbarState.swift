import CoreGraphics
import Foundation

enum CanvasToolbarDockAlignment: String, Sendable {
    case centered
}

enum CanvasToolbarItemID: String, CaseIterable, Sendable {
    case crop
    case multiSelect
    case save
    case text
    case handDrawing
    case importMedia
    case undo
    case redo
}

enum CanvasToolbarItemVisualRole: String, Sendable {
    case neutral
    case accent
    case success
    case warning
    case danger
}

struct CanvasToolbarPlacement: Hashable, Sendable {
    var preferredEdge: CanvasToolbarDockEdge
    var dockAlignment: CanvasToolbarDockAlignment
    var offsetAlongEdge: CGFloat
    var isUserPinned: Bool

    var dockEdge: CanvasToolbarDockEdge {
        get {
            preferredEdge
        }
        set {
            preferredEdge = newValue
        }
    }

    init(
        preferredEdge: CanvasToolbarDockEdge,
        dockAlignment: CanvasToolbarDockAlignment = .centered,
        offsetAlongEdge: CGFloat = 0,
        isUserPinned: Bool = false
    ) {
        self.preferredEdge = preferredEdge
        self.dockAlignment = dockAlignment
        self.offsetAlongEdge = offsetAlongEdge
        self.isUserPinned = isUserPinned
    }

    init(
        dockEdge: CanvasToolbarDockEdge,
        dockAlignment: CanvasToolbarDockAlignment = .centered,
        offsetAlongEdge: CGFloat = 0,
        isUserPinned: Bool = false
    ) {
        self.init(
            preferredEdge: dockEdge,
            dockAlignment: dockAlignment,
            offsetAlongEdge: offsetAlongEdge,
            isUserPinned: isUserPinned
        )
    }
}

struct CanvasToolbarItemState: Hashable, Sendable {
    var id: CanvasToolbarItemID
    var systemImageName: String
    var isEnabled: Bool
    var isActive: Bool
    var accessibilityLabel: String
    var accessibilityValue: String?
    var visualRole: CanvasToolbarItemVisualRole
    var preservesVisualRoleWhenDisabled: Bool

    init(
        id: CanvasToolbarItemID,
        systemImageName: String,
        isEnabled: Bool = true,
        isActive: Bool = false,
        accessibilityLabel: String,
        accessibilityValue: String? = nil,
        visualRole: CanvasToolbarItemVisualRole = .neutral,
        preservesVisualRoleWhenDisabled: Bool = false
    ) {
        self.id = id
        self.systemImageName = systemImageName
        self.isEnabled = isEnabled
        self.isActive = isActive
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityValue = accessibilityValue
        self.visualRole = visualRole
        self.preservesVisualRoleWhenDisabled = preservesVisualRoleWhenDisabled
    }
}

struct CanvasToolbarState: Hashable, Sendable {
    var placement: CanvasToolbarPlacement
    var items: [CanvasToolbarItemState]
    var showsBackground: Bool
    var preferredAxis: CanvasToolbarAxis

    init(
        placement: CanvasToolbarPlacement,
        items: [CanvasToolbarItemState],
        showsBackground: Bool = true,
        preferredAxis: CanvasToolbarAxis? = nil
    ) {
        self.placement = placement
        self.items = items
        self.showsBackground = showsBackground
            self.preferredAxis = preferredAxis ?? placement.preferredEdge.preferredAxis
    }
}
