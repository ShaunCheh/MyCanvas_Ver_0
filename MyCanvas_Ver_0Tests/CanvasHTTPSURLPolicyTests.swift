import Foundation
import XCTest
@testable import MyCanvas_Ver_0

final class CanvasHTTPSURLPolicyTests: XCTestCase {
    func testNormalizedStringAddsHTTPSWhenSchemeIsMissing() throws {
        XCTAssertEqual(
            try CanvasHTTPSURLPolicy.normalizedString(
                from: "  example.com/docs?q=1  "
            ),
            "https://example.com/docs?q=1"
        )
    }

    func testNormalizedStringPreservesExplicitHTTPSURL() throws {
        XCTAssertEqual(
            try CanvasHTTPSURLPolicy.normalizedString(
                from: "HTTPS://Example.COM/Docs?q=1#Intro"
            ),
            "https://example.com/Docs?q=1#Intro"
        )
    }

    func testNormalizedStringSupportsHostAndPortWithoutScheme() throws {
        XCTAssertEqual(
            try CanvasHTTPSURLPolicy.normalizedString(
                from: "example.com:8443/web/app"
            ),
            "https://example.com:8443/web/app"
        )
    }

    func testNormalizedStringDoesNotTreatQuerySchemeSubstringAsExplicitScheme() throws {
        XCTAssertEqual(
            try CanvasHTTPSURLPolicy.normalizedString(
                from: "example.com/login?redirect=http://legacy.example.com"
            ),
            "https://example.com/login?redirect=http://legacy.example.com"
        )
    }

    func testHTTPURLsAreRejected() {
        assertPolicyError(
            for: "http://example.com",
            expectedError: .httpSchemeNotAllowed
        )
    }

    func testUnsupportedSchemesAreRejected() {
        assertPolicyError(
            for: "ftp://example.com",
            expectedError: .unsupportedScheme("ftp")
        )
    }

    func testEmptyInputIsRejected() {
        assertPolicyError(
            for: "  \n\t  ",
            expectedError: .emptyInput
        )
    }

    func testMissingHostIsRejected() {
        assertPolicyError(
            for: "https:///missing-host",
            expectedError: .missingHost
        )
    }

    private func assertPolicyError(
        for rawInput: String,
        expectedError: CanvasHTTPSURLPolicyError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try CanvasHTTPSURLPolicy.normalizedString(from: rawInput),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? CanvasHTTPSURLPolicyError,
                expectedError,
                file: file,
                line: line
            )
        }
    }
}
