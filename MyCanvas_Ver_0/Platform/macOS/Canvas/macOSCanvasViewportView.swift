#if os(macOS)
import AppKit

final class macOSCanvasViewportView: NSView {
    private let backgroundLayer = CALayer()
    private let itemsLayer = CALayer()
    private let overlayLayer = CALayer()
    private var imageLayers: [CanvasImageItemID: CanvasImageLayer] = [:]
    private var snapshot: CanvasRenderSnapshot = .empty

    override var isFlipped: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayers()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func layout() {
        super.layout()
        updateLayerFrames()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateBackgroundAppearance()
        refreshImageLayers()
    }

    func apply(_ snapshot: CanvasRenderSnapshot) {
        self.snapshot = snapshot
        updateLayerFrames()
        refreshImageLayers()
    }

    private func setupLayers() {
        wantsLayer = true
        layer?.addSublayer(backgroundLayer)
        layer?.addSublayer(itemsLayer)
        layer?.addSublayer(overlayLayer)

        backgroundLayer.isGeometryFlipped = true
        itemsLayer.isGeometryFlipped = true
        overlayLayer.isGeometryFlipped = true

        updateBackgroundAppearance()
    }

    private func updateLayerFrames() {
        backgroundLayer.frame = bounds
        itemsLayer.frame = bounds
        overlayLayer.frame = bounds
    }

    private func updateBackgroundAppearance() {
        backgroundLayer.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    private func refreshImageLayers() {
        let incomingIDs = Set(snapshot.items.map(\.id))
        let existingIDs = Set(imageLayers.keys)

        for removedID in existingIDs.subtracting(incomingIDs) {
            imageLayers[removedID]?.removeFromSuperlayer()
            imageLayers[removedID] = nil
        }

        let contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        for item in snapshot.items {
            let imageLayer = imageLayer(for: item.id)
            imageLayer.update(with: item, contentsScale: contentsScale)
        }
    }

    private func imageLayer(for itemID: CanvasImageItemID) -> CanvasImageLayer {
        if let imageLayer = imageLayers[itemID] {
            return imageLayer
        }

        let imageLayer = CanvasImageLayer(itemID: itemID)
        itemsLayer.addSublayer(imageLayer)
        imageLayers[itemID] = imageLayer
        return imageLayer
    }
}
#endif
