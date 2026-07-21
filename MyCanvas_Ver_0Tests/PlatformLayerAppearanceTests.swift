#if os(macOS)
import AppKit
import XCTest
@testable import MyCanvas_Ver_0

final class PlatformLayerAppearanceTests: XCTestCase {
    func testWindowBackgroundResolvesAgainstProvidedAppearance() throws {
        let lightAppearance = try XCTUnwrap(NSAppearance(named: .aqua))
        let darkAppearance = try XCTUnwrap(NSAppearance(named: .darkAqua))

        let lightColor = PlatformLayerAppearance.resolvedCGColor(
            .windowBackgroundColor,
            for: lightAppearance
        )
        let darkColor = PlatformLayerAppearance.resolvedCGColor(
            .windowBackgroundColor,
            for: darkAppearance
        )

        XCTAssertGreaterThan(
            try brightness(of: lightColor),
            try brightness(of: darkColor)
        )
    }

    func testResolvedColorPreservesRequestedAlpha() throws {
        let appearance = try XCTUnwrap(NSAppearance(named: .darkAqua))
        let color = PlatformLayerAppearance.resolvedCGColor(
            NSColor.separatorColor.withAlphaComponent(0.24),
            for: appearance
        )

        XCTAssertEqual(color.alpha, 0.24, accuracy: 0.001)
    }

    private func brightness(of color: CGColor) throws -> CGFloat {
        let convertedColor = try XCTUnwrap(
            NSColor(cgColor: color)?.usingColorSpace(.deviceRGB)
        )
        return convertedColor.brightnessComponent
    }
}
#endif
