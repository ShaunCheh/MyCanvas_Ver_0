import CoreGraphics
import Foundation

enum CanvasInlineEditMode: Equatable {
    case crop
    case rotate
}

struct CanvasInlineCropSession {
    var draftCropRectNormalized: CanvasImageCropRect
}

struct CanvasInlineRotateSession {
    var draftRotationRadians: CGFloat
}

enum CanvasInlineEditSession {
    case crop(CanvasInlineCropSession)
    case rotate(CanvasInlineRotateSession)

    var mode: CanvasInlineEditMode {
        switch self {
        case .crop:
            return .crop
        case .rotate:
            return .rotate
        }
    }
}

// This transient editing state is intentionally kept out of BoardRuntimeState /
// board.json so inline crop and rotate drafts never become persisted document data.
struct CanvasInlineEditState {
    let itemID: CanvasImageItemID
    var session: CanvasInlineEditSession

    var mode: CanvasInlineEditMode {
        session.mode
    }

    var cropSession: CanvasInlineCropSession? {
        guard case let .crop(cropSession) = session else {
            return nil
        }

        return cropSession
    }

    var rotateSession: CanvasInlineRotateSession? {
        guard case let .rotate(rotateSession) = session else {
            return nil
        }

        return rotateSession
    }

    var draftCropRectNormalized: CanvasImageCropRect {
        get {
            guard case let .crop(cropSession) = session else {
                preconditionFailure("Crop draft accessed outside crop inline session.")
            }

            return cropSession.draftCropRectNormalized
        }
        set {
            guard case let .crop(existingSession) = session else {
                preconditionFailure("Crop draft updated outside crop inline session.")
            }

            var cropSession = existingSession
            cropSession.draftCropRectNormalized = newValue
            session = .crop(cropSession)
        }
    }

    var draftRotationRadians: CGFloat {
        get {
            guard case let .rotate(rotateSession) = session else {
                preconditionFailure("Rotation draft accessed outside rotate inline session.")
            }

            return rotateSession.draftRotationRadians
        }
        set {
            guard case let .rotate(existingSession) = session else {
                preconditionFailure("Rotation draft updated outside rotate inline session.")
            }

            var rotateSession = existingSession
            rotateSession.draftRotationRadians = newValue
            session = .rotate(rotateSession)
        }
    }

    init(
        itemID: CanvasImageItemID,
        mode: CanvasInlineEditMode,
        draftCropRectNormalized: CanvasImageCropRect = .fullImage,
        draftRotationRadians: CGFloat = 0
    ) {
        self.itemID = itemID
        switch mode {
        case .crop:
            self.session = .crop(
                CanvasInlineCropSession(
                    draftCropRectNormalized: draftCropRectNormalized
                )
            )
        case .rotate:
            self.session = .rotate(
                CanvasInlineRotateSession(
                    draftRotationRadians: draftRotationRadians
                )
            )
        }
    }

    init(
        itemID: CanvasImageItemID,
        session: CanvasInlineEditSession
    ) {
        self.itemID = itemID
        self.session = session
    }

    init(
        item: CanvasImageItem,
        mode: CanvasInlineEditMode
    ) {
        self.init(
            itemID: item.id,
            mode: mode,
            draftCropRectNormalized: item.cropRectNormalized,
            draftRotationRadians: item.rotationRadians
        )
    }
}
