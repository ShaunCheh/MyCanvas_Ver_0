#if os(macOS)
import AppKit

final class macOSCanvasChromeOverlayView: NSView {
    override var isFlipped: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hitView = super.hitTest(point)
        return hitView === self ? nil : hitView
    }
}

final class macOSCanvasChromeStackView: NSStackView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hitView = super.hitTest(point)
        return hitView === self ? nil : hitView
    }
}

enum macOSCanvasChromeButtonCornerStyle {
    case fixed(CGFloat)
    case circular
}

final class macOSCanvasChromeButtonSlotView: NSView {
    let button: NSButton
    var onHoverChange: ((Bool) -> Void)?
    var cornerStyle: macOSCanvasChromeButtonCornerStyle {
        didSet {
            needsLayout = true
        }
    }
    private(set) var isHovered = false
    private var hoverTrackingArea: NSTrackingArea?

    init(
        button: NSButton,
        cornerStyle: macOSCanvasChromeButtonCornerStyle
    ) {
        self.button = button
        self.cornerStyle = cornerStyle
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        // AppKit constraints use NSButton's alignment rect, while visible
        // chrome is drawn on the full layer. A plain NSView owns geometry and
        // chrome so the button can fill the exact slot only for image drawing,
        // accessibility, and event delivery.
        button.translatesAutoresizingMaskIntoConstraints = true
        button.autoresizingMask = [.width, .height]
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor.clear.cgColor
        button.layer?.borderWidth = 0
        button.layer?.cornerRadius = 0
        addSubview(button)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func layout() {
        super.layout()
        button.frame = bounds
        switch cornerStyle {
        case let .fixed(cornerRadius):
            layer?.cornerRadius = max(cornerRadius, 0)
        case .circular:
            layer?.cornerRadius = max(
                min(bounds.width, bounds.height) / 2,
                0
            )
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [
                .mouseEnteredAndExited,
                .activeInKeyWindow,
                .inVisibleRect
            ],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        setHovered(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        setHovered(false)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            setHovered(false)
        }
    }

    private func setHovered(_ hovered: Bool) {
        guard isHovered != hovered else {
            return
        }
        isHovered = hovered
        onHoverChange?(hovered)
    }
}
#endif
