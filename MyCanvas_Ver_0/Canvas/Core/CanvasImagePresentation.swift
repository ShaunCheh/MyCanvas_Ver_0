import CoreGraphics
import Foundation

// Shared image presentation keeps renderer-specific decisions separate from
// the transient crop/rotation geometry the canvas is currently previewing.
struct CanvasImagePresentation {
    let itemID: CanvasImageItemID
    let assetReference: CanvasImageAssetReference
    let assetKind: CanvasImageAssetKind
    let posterCGImage: CGImage
    let allowsAnimatedPlayback: Bool
    let logicalPixelSize: CGSize
    let zIndex: CGFloat
    let effectiveRotationRadians: CGFloat
    let effectiveCropRectNormalized: CanvasImageCropRect
    let visibleLocalFrame: CGRect
    let visibleWorldQuad: CanvasQuad
    let visibleCenter: CGPoint
    let visibleSize: CGSize
    let fullImageLocalFrame: CGRect
    let fullImageWorldQuad: CanvasQuad
    let fullImageCenter: CGPoint
    let fullImageSize: CGSize
    let isCropPreviewActive: Bool
    let isRotationPreviewActive: Bool
}
