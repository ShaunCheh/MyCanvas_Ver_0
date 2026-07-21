import QuartzCore

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

enum PlatformLayerAppearance {
    #if os(macOS)
    static func resolvedCGColor(
        _ color: NSColor,
        for appearance: NSAppearance
    ) -> CGColor {
        var resolvedColor = color.cgColor
        appearance.performAsCurrentDrawingAppearance {
            resolvedColor = color.cgColor
        }
        return resolvedColor
    }
    #elseif os(iOS)
    static func resolvedCGColor(
        _ color: UIColor,
        for traitCollection: UITraitCollection
    ) -> CGColor {
        color.resolvedColor(with: traitCollection).cgColor
    }
    #endif

    static func performWithoutAnimations(_ updates: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updates()
        CATransaction.commit()
    }
}

#if os(macOS)
final class macOSAppearanceAwareView: NSView {
    var onEffectiveAppearanceChange: (() -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onEffectiveAppearanceChange?()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onEffectiveAppearanceChange?()
    }
}
#endif
