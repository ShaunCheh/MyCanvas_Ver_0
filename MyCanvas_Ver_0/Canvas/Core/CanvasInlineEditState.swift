import CoreGraphics
import Foundation

enum CanvasInlineEditMode: Equatable {
    case crop
    case text
}

struct CanvasInlineCropSession: Equatable {
    var draftCropRectNormalized: CanvasImageCropRect
}

struct CanvasInlineTextSession: Equatable {
    var draftText: String
}

enum CanvasInlineEditSession: Equatable {
    case crop(CanvasInlineCropSession)
    case text(CanvasInlineTextSession)
}

// Keep rotation preview separate from crop-only inline edit state so selected
// items can rotate directly without entering a dedicated mode.
struct CanvasRotationPreviewState {
    let itemID: CanvasItemID
    var draftRotationRadians: CGFloat
}

// Track the active rotation gesture separately from the draft angle so later
// overlays can appear immediately when rotation starts, even before the angle
// diverges from the persisted item rotation.
struct CanvasRotationInteractionState {
    let itemID: CanvasItemID
}

// This transient editing state is intentionally kept out of BoardRuntimeState /
// board.json so inline crop/text drafts never become persisted document data.
struct CanvasInlineEditState {
    let itemID: CanvasItemID
    private var session: CanvasInlineEditSession

    var mode: CanvasInlineEditMode {
        switch session {
        case .crop:
            return .crop
        case .text:
            return .text
        }
    }

    var cropSession: CanvasInlineCropSession? {
        get {
            guard case let .crop(cropSession) = session else {
                return nil
            }
            return cropSession
        }
        set {
            guard let newValue else {
                return
            }
            session = .crop(newValue)
        }
    }

    var textSession: CanvasInlineTextSession? {
        get {
            guard case let .text(textSession) = session else {
                return nil
            }
            return textSession
        }
        set {
            guard let newValue else {
                return
            }
            session = .text(newValue)
        }
    }

    var draftCropRectNormalized: CanvasImageCropRect {
        get {
            guard case let .crop(cropSession) = session else {
                assertionFailure("Expected crop inline edit session.")
                return .fullImage
            }
            return cropSession.draftCropRectNormalized
        }
        set {
            guard case var .crop(cropSession) = session else {
                assertionFailure("Expected crop inline edit session.")
                return
            }
            cropSession.draftCropRectNormalized = newValue
            session = .crop(cropSession)
        }
    }

    var draftText: String {
        get {
            guard case let .text(textSession) = session else {
                assertionFailure("Expected text inline edit session.")
                return ""
            }
            return textSession.draftText
        }
        set {
            guard case var .text(textSession) = session else {
                assertionFailure("Expected text inline edit session.")
                return
            }
            textSession.draftText = newValue
            session = .text(textSession)
        }
    }

    init(
        itemID: CanvasImageItemID,
        mode: CanvasInlineEditMode,
        draftCropRectNormalized: CanvasImageCropRect = .fullImage
    ) {
        self.itemID = itemID
        switch mode {
        case .crop:
            session = .crop(
                CanvasInlineCropSession(
                    draftCropRectNormalized: draftCropRectNormalized
                )
            )
        case .text:
            assertionFailure("Use text-specific initializer for text inline edit state.")
            session = .text(
                CanvasInlineTextSession(draftText: "")
            )
        }
    }

    init(
        itemID: CanvasItemID,
        draftText: String
    ) {
        self.itemID = itemID
        session = .text(
            CanvasInlineTextSession(
                draftText: draftText
            )
        )
    }

    init(
        itemID: CanvasImageItemID,
        cropSession: CanvasInlineCropSession
    ) {
        self.itemID = itemID
        session = .crop(cropSession)
    }

    init(
        itemID: CanvasItemID,
        textSession: CanvasInlineTextSession
    ) {
        self.itemID = itemID
        session = .text(textSession)
    }

    init(
        item: CanvasImageItem,
        mode: CanvasInlineEditMode = .crop
    ) {
        self.init(
            itemID: item.id,
            mode: mode,
            draftCropRectNormalized: item.cropRectNormalized
        )
    }

    init(
        item: CanvasTextItem
    ) {
        self.init(
            itemID: item.id,
            draftText: item.text
        )
    }
}
