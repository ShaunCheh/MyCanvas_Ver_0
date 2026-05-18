import Foundation
import XCTest
@testable import MyCanvas_Ver_0

@MainActor
final class HandDrawingDocumentCodecTests: XCTestCase {
    func testHandDrawingDocumentCodecRoundTripsCustomDocument() throws {
        let document = makeHandDrawingTestDocument(includeEraseMask: true)

        let data = try HandDrawingDocumentCodec.makeDocumentData(for: document)
        let decodedDocument = try HandDrawingDocumentCodec.decodeDocument(from: data)

        XCTAssertEqual(decodedDocument, document)
    }

    func testHandDrawingDocumentCodecRejectsUnsupportedFormatVersion() throws {
        let document = makeHandDrawingTestDocument()
        let encodedData = try HandDrawingDocumentCodec.makeDocumentData(for: document)
        var payload = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: encodedData) as? [String: Any]
        )
        payload["formatVersion"] = HandDrawingDocument.currentFormatVersion + 1
        let mutatedData = try JSONSerialization.data(withJSONObject: payload)

        XCTAssertThrowsError(
            try HandDrawingDocumentCodec.decodeDocument(from: mutatedData)
        ) { error in
            guard
                case let HandDrawingDocumentCodecError
                    .unsupportedDocumentFormatVersion(formatVersion) = error
            else {
                return XCTFail("Expected unsupported format version error, got \(error).")
            }
            XCTAssertEqual(
                formatVersion,
                HandDrawingDocument.currentFormatVersion + 1
            )
        }
    }
}
