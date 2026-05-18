import Foundation

#if canImport(UIKit)
import UIKit
typealias HandDrawingPlatformColor = UIColor
#elseif canImport(AppKit)
import AppKit
typealias HandDrawingPlatformColor = NSColor
#endif

#if canImport(UIKit) || canImport(AppKit)
extension HandDrawingColor {
    init(platformColor: HandDrawingPlatformColor) {
        #if canImport(UIKit)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        let resolvedColor = platformColor.resolvedColor(with: .current)
        if resolvedColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            self.init(
                red: Double(red),
                green: Double(green),
                blue: Double(blue),
                alpha: Double(alpha)
            )
        } else if let convertedColor = resolvedColor.cgColor.converted(
            to: CGColorSpaceCreateDeviceRGB(),
            intent: .defaultIntent,
            options: nil
        ), let components = convertedColor.components, components.count >= 4 {
            self.init(
                red: Double(components[0]),
                green: Double(components[1]),
                blue: Double(components[2]),
                alpha: Double(components[3])
            )
        } else {
            self = .black
        }
        #else
        let resolvedColor = platformColor.usingColorSpace(.deviceRGB) ?? .black
        self.init(
            red: Double(resolvedColor.redComponent),
            green: Double(resolvedColor.greenComponent),
            blue: Double(resolvedColor.blueComponent),
            alpha: Double(resolvedColor.alphaComponent)
        )
        #endif
    }
}

#if canImport(UIKit)
extension UIColor {
    convenience init(handDrawingColor: HandDrawingColor) {
        self.init(
            red: CGFloat(handDrawingColor.red),
            green: CGFloat(handDrawingColor.green),
            blue: CGFloat(handDrawingColor.blue),
            alpha: CGFloat(handDrawingColor.alpha)
        )
    }
}
#elseif canImport(AppKit)
extension NSColor {
    convenience init(handDrawingColor: HandDrawingColor) {
        self.init(
            red: CGFloat(handDrawingColor.red),
            green: CGFloat(handDrawingColor.green),
            blue: CGFloat(handDrawingColor.blue),
            alpha: CGFloat(handDrawingColor.alpha)
        )
    }
}
#endif
#endif
