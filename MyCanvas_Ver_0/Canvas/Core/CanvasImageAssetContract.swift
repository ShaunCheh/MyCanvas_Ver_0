import Foundation

// Phase 0 freezes the animated-image semantics before the storage/render
// refactor starts so later stages read from one shared contract instead of
// hard-coding GIF behavior in multiple layers.
enum CanvasAnimatedImagePlaybackMode: Equatable {
    case autoplayWhenVisible
}

enum CanvasAnimatedImagePreviewSurface: Equatable {
    case boardList
    case persistedThumbnail
    case miniMap
    case placeholder
}

enum CanvasAnimatedImagePreviewMode: Equatable {
    case posterFrameOnly
}

enum CanvasImageEditPolicy: Equatable {
    case geometryOnlyNonDestructiveCrop
}

enum CanvasImageDuplicationMode: Equatable {
    case shareUnderlyingAssetReference
}

enum CanvasAnimatedImageHistoryMode: Equatable {
    case trackDocumentStateExcludingPlaybackProgress
}

struct CanvasImageAssetContract: Equatable {
    let playbackMode: CanvasAnimatedImagePlaybackMode
    let editPolicy: CanvasImageEditPolicy
    let duplicationMode: CanvasImageDuplicationMode
    let historyMode: CanvasAnimatedImageHistoryMode
    let targetDocumentFormatVersion: Int

    static let current = CanvasImageAssetContract(
        playbackMode: .autoplayWhenVisible,
        editPolicy: .geometryOnlyNonDestructiveCrop,
        duplicationMode: .shareUnderlyingAssetReference,
        historyMode: .trackDocumentStateExcludingPlaybackProgress,
        targetDocumentFormatVersion: 4
    )

    func previewMode(
        for surface: CanvasAnimatedImagePreviewSurface
    ) -> CanvasAnimatedImagePreviewMode {
        switch surface {
        case .boardList,
             .persistedThumbnail,
             .miniMap,
             .placeholder:
            return .posterFrameOnly
        }
    }

    var shouldAutoplayAnimatedImagesOnCanvas: Bool {
        playbackMode == .autoplayWhenVisible
    }

    var keepsEditsInGeometryLayer: Bool {
        editPolicy == .geometryOnlyNonDestructiveCrop
    }

    var duplicatesShareUnderlyingAssetReference: Bool {
        duplicationMode == .shareUnderlyingAssetReference
    }

    var excludesPlaybackProgressFromHistory: Bool {
        historyMode == .trackDocumentStateExcludingPlaybackProgress
    }
}
