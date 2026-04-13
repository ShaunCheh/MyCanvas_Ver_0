import CoreGraphics
import XCTest
@testable import MyCanvas_Ver_0

@MainActor
final class CanvasCommandPolicyParityTests: XCTestCase {
    private let policy = CanvasInteractionPolicy()
    private let commandCatalog = CanvasCommandCatalog()

    func testAddTextDescriptorAndExecutorMatchPolicyInEditingMode() {
        let session = makeCommandPolicyParityTestSession(workspaceMode: .editing)
        let executor = CanvasCommandExecutor(session: session)
        CanvasCommandPolicyParityTestRetainer.executors.append(executor)

        let descriptor = commandCatalog.descriptor(for: .addTextItem, session: session)
        let decision = policy.commandDecision(
            for: .addTextItem,
            workspaceMode: session.workspaceMode
        )

        XCTAssertEqual(decision, .allow)
        XCTAssertTrue(descriptor.isEnabled)
        XCTAssertFalse(descriptor.isActive)
        XCTAssertTrue(executor.canExecute(.addTextItem))
    }

    func testAddTextDescriptorAndExecutorMatchPolicyInReadingMode() {
        let session = makeCommandPolicyParityTestSession(workspaceMode: .reading)
        let executor = CanvasCommandExecutor(session: session)
        CanvasCommandPolicyParityTestRetainer.executors.append(executor)

        let descriptor = commandCatalog.descriptor(for: .addTextItem, session: session)
        let decision = policy.commandDecision(
            for: .addTextItem,
            workspaceMode: session.workspaceMode
        )

        XCTAssertEqual(decision, .block(reason: .readingMode, feedback: nil))
        XCTAssertFalse(descriptor.isEnabled)
        XCTAssertFalse(descriptor.isActive)
        XCTAssertFalse(executor.canExecute(.addTextItem))
    }

    func testCommitTextDescriptorResetsActiveStateWhenPolicyBlocksInReadingMode() {
        let session = makeCommandPolicyParityTestSession(workspaceMode: .editing)
        let executor = CanvasCommandExecutor(session: session)
        CanvasCommandPolicyParityTestRetainer.executors.append(executor)

        XCTAssertNotNil(session.addTextItem())
        session.workspaceMode = .reading

        let descriptor = commandCatalog.descriptor(
            for: .commitTextEdit,
            session: session
        )
        let decision = policy.commandDecision(
            for: .commitTextEdit,
            workspaceMode: session.workspaceMode
        )

        XCTAssertEqual(decision, .block(reason: .readingMode, feedback: nil))
        XCTAssertFalse(descriptor.isEnabled)
        XCTAssertFalse(descriptor.isActive)
        XCTAssertFalse(executor.canExecute(.commitTextEdit))
    }

    func testImportMediaExecutorMatchesPolicyInEditingMode() throws {
        let session = makeCommandPolicyParityTestSession(workspaceMode: .editing)
        let executor = CanvasCommandExecutor(session: session)
        CanvasCommandPolicyParityTestRetainer.executors.append(executor)
        let request = try makeCommandPolicyParityImportRequest()

        let decision = policy.commandDecision(
            for: .importMedia,
            workspaceMode: session.workspaceMode
        )

        XCTAssertEqual(decision, .allow)
        XCTAssertTrue(executor.canExecute(.importMedia(request)))
    }

    func testImportMediaExecutorMatchesPolicyInReadingMode() throws {
        let session = makeCommandPolicyParityTestSession(workspaceMode: .reading)
        let executor = CanvasCommandExecutor(session: session)
        CanvasCommandPolicyParityTestRetainer.executors.append(executor)
        let request = try makeCommandPolicyParityImportRequest()

        let decision = policy.commandDecision(
            for: .importMedia,
            workspaceMode: session.workspaceMode
        )

        XCTAssertEqual(decision, .block(reason: .readingMode, feedback: nil))
        XCTAssertFalse(executor.canExecute(.importMedia(request)))
    }
}

private enum CanvasCommandPolicyParityTestRetainer {
    static var sessions: [CanvasEditorSession] = []
    static var executors: [CanvasCommandExecutor] = []
}

private enum CanvasCommandPolicyParityTestError: Error {
    case invalidBitmapContext
    case invalidImage
}

private func makeCommandPolicyParityTestSession(
    workspaceMode: CanvasWorkspaceMode
) -> CanvasEditorSession {
    let session = CanvasEditorSession(
        saveQueueLabel: "CanvasCommandPolicyParityTests",
        logPrefix: "[CanvasCommandPolicyParityTests]"
    )
    session.workspaceMode = workspaceMode
    CanvasCommandPolicyParityTestRetainer.sessions.append(session)
    return session
}

private func makeCommandPolicyParityImportRequest() throws -> CanvasImportRequest {
    let image = CanvasResolvedImportImage(
        cgImage: try makeCommandPolicyParityImage(width: 24, height: 16)
    )
    return CanvasImportRequest(
        images: [image],
        sourceDescription: "command policy parity"
    )
}

private func makeCommandPolicyParityImage(
    width: Int,
    height: Int
) throws -> CGImage {
    let bitmapInfo =
        CGImageAlphaInfo.premultipliedLast.rawValue
        | CGBitmapInfo.byteOrder32Big.rawValue
    guard
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        )
    else {
        throw CanvasCommandPolicyParityTestError.invalidBitmapContext
    }

    context.setFillColor(
        CGColor(red: 0.15, green: 0.45, blue: 0.85, alpha: 1)
    )
    context.fill(
        CGRect(
            x: 0,
            y: 0,
            width: width,
            height: height
        )
    )

    guard let image = context.makeImage() else {
        throw CanvasCommandPolicyParityTestError.invalidImage
    }

    return image
}
