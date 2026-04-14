import Combine
import SwiftUI

enum ShareImportError: LocalizedError {
    case unavailableSharedStore
    case missingSelectedFolder
    case noImportableImages
    case cancelled

    var errorDescription: String? {
        switch self {
        case .unavailableSharedStore:
            return "共享存储不可用，请确认 App Group 配置正确。"
        case .missingSelectedFolder:
            return "请先打开 MyCanvas 选择图板存储目录，然后再从照片分享。"
        case .noImportableImages:
            return "当前分享内容里没有可导入的图片。"
        case .cancelled:
            return "用户已取消分享导入。"
        }
    }
}

struct ShareBoardOption: Identifiable, Hashable {
    let boardID: UUID
    let title: String
    let updatedAt: Date

    var id: UUID {
        boardID
    }
}

@MainActor
final class ShareImportViewModel: ObservableObject {
    enum Destination: Hashable {
        case newBoard
        case existing(UUID)
    }

    @Published private(set) var boardOptions: [ShareBoardOption] = []
    @Published private(set) var incomingImageCount = 0
    @Published private(set) var isLoading = false
    @Published private(set) var isImporting = false
    @Published var selectedDestination: Destination = .newBoard
    @Published var errorMessage: String?

    private let extensionContext: NSExtensionContext?
    private let finishHandler: () -> Void
    private let cancelHandler: (Error) -> Void
    private var sharedUserDefaults: UserDefaults?
    private var resolvedImages: [CanvasResolvedImportImage] = []
    private var didLoad = false

    init(
        extensionContext: NSExtensionContext?,
        finishHandler: @escaping () -> Void,
        cancelHandler: @escaping (Error) -> Void
    ) {
        self.extensionContext = extensionContext
        self.finishHandler = finishHandler
        self.cancelHandler = cancelHandler
    }

    var incomingImageSummary: String {
        incomingImageCount == 1
            ? "1 张图片"
            : "\(incomingImageCount) 张图片"
    }

    var canImport: Bool {
        isLoading == false &&
            isImporting == false &&
            resolvedImages.isEmpty == false &&
            sharedUserDefaults != nil
    }

    var importButtonTitle: String {
        switch selectedDestination {
        case .newBoard:
            return "导入到新图板"
        case let .existing(boardID):
            let boardTitle = boardOptions.first(where: { $0.boardID == boardID })?.title
                ?? "已选图板"
            return "导入到“\(boardTitle)”"
        }
    }

    func loadIfNeeded() {
        guard didLoad == false else {
            return
        }

        didLoad = true
        Task {
            await load()
        }
    }

    func retry() {
        didLoad = false
        loadIfNeeded()
    }

    func cancel() {
        cancelHandler(ShareImportError.cancelled)
    }

    func importSelection() {
        guard canImport else {
            return
        }

        Task {
            await runImport()
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil

        do {
            guard let sharedUserDefaults = MyCanvasSharedAppGroup.sharedUserDefaults else {
                throw ShareImportError.unavailableSharedStore
            }

            guard FolderBookmarkStore.hasStoredBookmarkData(
                userDefaults: sharedUserDefaults
            ) else {
                throw ShareImportError.missingSelectedFolder
            }

            let resolvedImages = await ShareExtensionImageResolver.resolveImages(
                from: extensionContext
            )
            guard resolvedImages.isEmpty == false else {
                throw ShareImportError.noImportableImages
            }

            let boardSummaries = try BoardStore.listBoards(
                userDefaults: sharedUserDefaults
            )

            self.sharedUserDefaults = sharedUserDefaults
            self.resolvedImages = resolvedImages
            incomingImageCount = resolvedImages.count
            boardOptions = boardSummaries.map {
                ShareBoardOption(
                    boardID: $0.boardID,
                    title: $0.title,
                    updatedAt: $0.updatedAt
                )
            }
            selectedDestination = .newBoard
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func runImport() async {
        guard let sharedUserDefaults else {
            errorMessage = ShareImportError.unavailableSharedStore.localizedDescription
            return
        }

        isImporting = true
        errorMessage = nil

        do {
            try await importImages(userDefaults: sharedUserDefaults)
            finishHandler()
        } catch {
            errorMessage = error.localizedDescription
            isImporting = false
        }
    }

    private func importImages(
        userDefaults: UserDefaults
    ) async throws {
        let session = CanvasEditorSession(
            saveQueueLabel: "MyCanvas.ShareExtension.Save",
            logPrefix: "[BoardStore][ShareExtension]",
            userDefaults: userDefaults
        )

        let destinationBoardID: UUID?
        switch selectedDestination {
        case .newBoard:
            session.startNewBoard()
            destinationBoardID = session.currentBoardRuntimeState()?.boardID
        case let .existing(boardID):
            try session.loadBoard(id: boardID)
            destinationBoardID = boardID
        }

        let transferRequest = CanvasTransferRequest(
            images: resolvedImages,
            placement: .cameraCenter,
            layout: .automatic,
            sourceDescription: "Photos share extension"
        )
        guard let importRequest = try CanvasMediaImportService.makeImportRequest(
            from: transferRequest,
            boardID: destinationBoardID,
            userDefaults: userDefaults
        ) else {
            throw ShareImportError.noImportableImages
        }

        _ = session.appendImportedMedia(
            importRequest.items,
            placement: importRequest.placement,
            layout: importRequest.layout,
            presentationTemplate: importRequest.presentationTemplate
        )
        try await saveBoard(
            session,
            reason: "share extension import",
            createBoardIfNeeded: true
        )
    }

    private func saveBoard(
        _ session: CanvasEditorSession,
        reason: String,
        createBoardIfNeeded: Bool
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            session.saveBoardNow(
                reason: reason,
                createBoardIfNeeded: createBoardIfNeeded
            ) { result in
                continuation.resume(with: result)
            }
        }
    }
}
