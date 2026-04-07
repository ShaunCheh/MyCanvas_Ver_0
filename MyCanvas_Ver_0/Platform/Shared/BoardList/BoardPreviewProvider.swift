import CoreGraphics
import Foundation

final class BoardPreviewProvider {
    private let thumbnailCache: BoardThumbnailCache
    private let thumbnailRenderer: BoardThumbnailRenderer
    private let mediaPosterImageResolver: BoardMediaPosterImageResolver
    private let renderQueue: OperationQueue
    private let callbackQueue: DispatchQueue

    init(
        thumbnailCache: BoardThumbnailCache = BoardThumbnailCache(),
        thumbnailRenderer: BoardThumbnailRenderer = BoardThumbnailRenderer(),
        mediaPosterImageResolver: BoardMediaPosterImageResolver = BoardMediaPosterImageResolver(),
        callbackQueue: DispatchQueue = .main
    ) {
        self.thumbnailCache = thumbnailCache
        self.thumbnailRenderer = thumbnailRenderer
        self.mediaPosterImageResolver = mediaPosterImageResolver
        self.callbackQueue = callbackQueue

        let renderQueue = OperationQueue()
        renderQueue.name = "BoardPreviewProvider.renderQueue"
        renderQueue.maxConcurrentOperationCount = 2
        renderQueue.qualityOfService = .userInitiated
        self.renderQueue = renderQueue
    }

    func immediatePreview(
        for item: BoardCatalogItem,
        targetPixelSize: CGSize? = nil
    ) -> BoardPreviewContent {
        guard
            let targetPixelSize,
            let cacheKey = BoardThumbnailCacheKey(
                item: item,
                targetPixelSize: targetPixelSize
            )
        else {
            return .geometry(item.previewSeed)
        }

        if let cachedImage = thumbnailCache.image(for: cacheKey) {
            logBoardPreviewProviderDecision(
                phase: "immediatePreview",
                boardID: item.boardID,
                revisionToken: item.revisionToken,
                targetPixelSize: targetPixelSize,
                source: "cache-hit"
            )
            logBoardPreviewProviderCacheHit(
                phase: "immediatePreview-cache-hit",
                item: item,
                targetPixelSize: targetPixelSize,
                cachedImage: cachedImage,
                mediaPosterImageResolver: mediaPosterImageResolver
            )
            return .thumbnail(cachedImage, item.previewSeed)
        }

        do {
            if let persistedThumbnail = try loadPersistedThumbnailPreview(
                for: item,
                cacheKey: cacheKey
            ) {
                logBoardPreviewProviderDecision(
                    phase: "immediatePreview",
                    boardID: item.boardID,
                    revisionToken: item.revisionToken,
                    targetPixelSize: targetPixelSize,
                    source: "persisted-replay"
                )
                thumbnailCache.insert(persistedThumbnail, for: cacheKey)
                return .thumbnail(persistedThumbnail, item.previewSeed)
            }
        } catch {
            print(
                "[BoardPreviewProvider] Failed to load persisted thumbnail " +
                "boardID=\(item.boardID.uuidString) " +
                "revision=\(item.revisionToken) " +
                "error=\(error)"
            )
        }

        logBoardPreviewProviderDecision(
            phase: "immediatePreview",
            boardID: item.boardID,
            revisionToken: item.revisionToken,
            targetPixelSize: targetPixelSize,
            source: "geometry-fallback"
        )
        return .geometry(item.previewSeed)
    }

    @discardableResult
    func requestThumbnail(
        for item: BoardCatalogItem,
        targetPixelSize: CGSize,
        completion: @escaping (BoardPreviewContent?) -> Void
    ) -> BoardPreviewRequestToken {
        let requestToken = BoardPreviewRequestToken()
        guard
            let cacheKey = BoardThumbnailCacheKey(
                item: item,
                targetPixelSize: targetPixelSize
            )
        else {
            logBoardPreviewProviderDecision(
                phase: "requestThumbnail",
                boardID: item.boardID,
                revisionToken: item.revisionToken,
                targetPixelSize: targetPixelSize,
                source: "skip",
                reason: "invalid-cache-key"
            )
            return requestToken
        }

        if let cachedImage = thumbnailCache.image(for: cacheKey) {
            logBoardPreviewProviderDecision(
                phase: "requestThumbnail",
                boardID: item.boardID,
                revisionToken: item.revisionToken,
                targetPixelSize: targetPixelSize,
                source: "cache-hit"
            )
            logBoardPreviewProviderCacheHit(
                phase: "requestThumbnail-cache-hit",
                item: item,
                targetPixelSize: targetPixelSize,
                cachedImage: cachedImage,
                mediaPosterImageResolver: mediaPosterImageResolver
            )
            callbackQueue.async { [weak requestToken] in
                guard let requestToken, requestToken.isCancelled == false else {
                    logBoardPreviewProviderDecision(
                        phase: "requestThumbnail",
                        boardID: item.boardID,
                        revisionToken: item.revisionToken,
                        targetPixelSize: cacheKey.pixelSize,
                        source: "callback-drop",
                        reason: "token-cancelled-before-cache-delivery"
                    )
                    return
                }

                completion(.thumbnail(cachedImage, item.previewSeed))
            }
            return requestToken
        }

        let operation = BlockOperation()
        requestToken.setCancellationHandler {
            operation.cancel()
        }

        operation.addExecutionBlock { [weak operation] in
            guard
                let operation,
                operation.isCancelled == false,
                requestToken.isCancelled == false
            else {
                return
            }

            do {
                let cancellationCheck: () throws -> Void = {
                    if operation.isCancelled || requestToken.isCancelled {
                        throw BoardThumbnailRendererError.cancelled
                    }
                }

                guard let renderedImage = try self.loadBestAvailableThumbnail(
                    for: item,
                    cacheKey: cacheKey,
                    cancellationCheck: cancellationCheck
                ) else {
                    logBoardPreviewProviderDecision(
                        phase: "requestThumbnail",
                        boardID: item.boardID,
                        revisionToken: item.revisionToken,
                        targetPixelSize: cacheKey.pixelSize,
                        source: "render-miss",
                        reason: "load-best-available-returned-nil"
                    )
                    return
                }

                guard operation.isCancelled == false, requestToken.isCancelled == false else {
                    logBoardPreviewProviderDecision(
                        phase: "requestThumbnail",
                        boardID: item.boardID,
                        revisionToken: item.revisionToken,
                        targetPixelSize: cacheKey.pixelSize,
                        source: "callback-drop",
                        reason: "cancelled-after-render-before-delivery"
                    )
                    return
                }

                self.thumbnailCache.insert(renderedImage, for: cacheKey)
                self.callbackQueue.async { [weak requestToken] in
                    guard let requestToken, requestToken.isCancelled == false else {
                        logBoardPreviewProviderDecision(
                            phase: "requestThumbnail",
                            boardID: item.boardID,
                            revisionToken: item.revisionToken,
                            targetPixelSize: cacheKey.pixelSize,
                            source: "callback-drop",
                            reason: "token-cancelled-before-render-delivery"
                        )
                        return
                    }

                    completion(.thumbnail(renderedImage, item.previewSeed))
                }
            } catch BoardThumbnailRendererError.cancelled {
                logBoardPreviewProviderDecision(
                    phase: "requestThumbnail",
                    boardID: item.boardID,
                    revisionToken: item.revisionToken,
                    targetPixelSize: cacheKey.pixelSize,
                    source: "cancelled",
                    reason: "operation-or-token-cancelled"
                )
                return
            } catch {
                print(
                    "[BoardPreviewProvider] Failed to render thumbnail " +
                    "boardID=\(item.boardID.uuidString) " +
                    "revision=\(item.revisionToken) " +
                    "error=\(error)"
                )
            }
        }

        renderQueue.addOperation(operation)
        return requestToken
    }

    private func loadBestAvailableThumbnail(
        for item: BoardCatalogItem,
        cacheKey: BoardThumbnailCacheKey,
        cancellationCheck: () throws -> Void
    ) throws -> CGImage? {
        do {
            if let persistedThumbnail = try loadPersistedThumbnailPreview(
                for: item,
                cacheKey: cacheKey,
                cancellationCheck: cancellationCheck
            ) {
                logBoardPreviewProviderDecision(
                    phase: "loadBestAvailableThumbnail",
                    boardID: item.boardID,
                    revisionToken: item.revisionToken,
                    targetPixelSize: cacheKey.pixelSize,
                    source: "persisted-replay"
                )
                return persistedThumbnail
            }
        } catch BoardThumbnailRendererError.cancelled {
            throw BoardThumbnailRendererError.cancelled
        } catch {
            print(
                "[BoardPreviewProvider] Failed to load persisted thumbnail " +
                "boardID=\(item.boardID.uuidString) " +
                "revision=\(item.revisionToken) " +
                "error=\(error)"
            )
        }

        try cancellationCheck()
        logBoardPreviewProviderDecision(
            phase: "loadBestAvailableThumbnail",
            boardID: item.boardID,
            revisionToken: item.revisionToken,
            targetPixelSize: cacheKey.pixelSize,
            source: "fresh-render"
        )
        return try thumbnailRenderer.renderThumbnail(
            for: item,
            targetPixelSize: cacheKey.pixelSize,
            animatedImagePreviewMode: BoardPreviewContent.animatedImagePreviewMode,
            cancellationCheck: cancellationCheck
        )
    }

    private func loadPersistedThumbnailPreview(
        for item: BoardCatalogItem,
        cacheKey: BoardThumbnailCacheKey,
        cancellationCheck: () throws -> Void = {}
    ) throws -> CGImage? {
        // Older persisted thumbnails may predate text rendering support, so mixed
        // and text-only boards should be regenerated from the current document.
        guard item.document.textItemRecords.isEmpty else {
            logBoardPreviewProviderDecision(
                phase: "loadPersistedThumbnailPreview",
                boardID: item.boardID,
                revisionToken: item.revisionToken,
                targetPixelSize: cacheKey.pixelSize,
                source: "skip-persisted",
                reason: "contains-text-items"
            )
            return nil
        }

        let decodeMaxPixelSize = max(
            cacheKey.pixelWidth,
            cacheKey.pixelHeight
        )
        let persistedThumbnailResult = try BoardPersistedThumbnailStore.loadThumbnailIfFresh(
            at: item.persistedThumbnailURL,
            updatedAt: item.updatedAt,
            boardID: item.boardID,
            maxPixelSize: decodeMaxPixelSize
        )
        let persistedThumbnail: CGImage
        switch persistedThumbnailResult {
        case .image(let loadedThumbnail):
            persistedThumbnail = loadedThumbnail
        case .missingOrStale:
            logBoardPreviewProviderDecision(
                phase: "loadPersistedThumbnailPreview",
                boardID: item.boardID,
                revisionToken: item.revisionToken,
                targetPixelSize: cacheKey.pixelSize,
                source: "persisted-miss",
                reason: "missing-or-stale"
            )
            return nil
        case .formatVersionMismatch:
            logBoardPreviewProviderDecision(
                phase: "loadPersistedThumbnailPreview",
                boardID: item.boardID,
                revisionToken: item.revisionToken,
                targetPixelSize: cacheKey.pixelSize,
                source: "persisted-miss",
                reason: "format-version-mismatch"
            )
            return nil
        }

        try cancellationCheck()
        logBoardPreviewProviderDecision(
            phase: "loadPersistedThumbnailPreview",
            boardID: item.boardID,
            revisionToken: item.revisionToken,
            targetPixelSize: cacheKey.pixelSize,
            source: "persisted-hit"
        )
        return try thumbnailRenderer.renderThumbnail(
            fromPersistedThumbnail: persistedThumbnail,
            previewSeed: item.previewSeed,
            boardID: item.boardID,
            targetPixelSize: cacheKey.pixelSize,
            cancellationCheck: cancellationCheck
        )
    }
}

private func logBoardPreviewProviderCacheHit(
    phase: String,
    item: BoardCatalogItem,
    targetPixelSize: CGSize,
    cachedImage: CGImage,
    mediaPosterImageResolver: BoardMediaPosterImageResolver
) {
    logBoardThumbnailTraceImageRegions(
        phase: phase,
        mode: "provider-cache-hit",
        boardID: item.boardID,
        previewSeed: item.previewSeed,
        targetPixelSize: targetPixelSize,
        contentInset: 10,
        image: cachedImage
    )
    logBoardPreviewProviderSourceImagesIfNeeded(
        phase: phase,
        item: item,
        mediaPosterImageResolver: mediaPosterImageResolver
    )
}

private func logBoardPreviewProviderSourceImagesIfNeeded(
    phase: String,
    item: BoardCatalogItem,
    mediaPosterImageResolver: BoardMediaPosterImageResolver,
    maxImageCount: Int = 8,
    maxPixelSize: Int = 128
) {
    let imageItemRecords = item.document.imageItemRecords
    guard imageItemRecords.count <= maxImageCount else {
        print(
            "[BoardList][ThumbnailTrace][SourceImage] " +
                "phase=\(phase) " +
                "boardID=\(item.boardID.uuidString) " +
                "status=skipped " +
                "reason=image-count-exceeds-limit " +
                "imageCount=\(imageItemRecords.count)"
        )
        return
    }

    for imageItemRecord in imageItemRecords {
        let previewAssetFilename = mediaPosterImageResolver.previewAssetFilename(
            for: imageItemRecord
        )
        do {
            let image = try mediaPosterImageResolver.resolvePreviewImage(
                for: imageItemRecord,
                assetsDirectoryURL: item.assetsDirectoryURL,
                animatedImagePreviewMode: BoardPreviewContent.animatedImagePreviewMode,
                maxPixelSize: maxPixelSize
            )

            print(
                "[BoardList][ThumbnailTrace][SourceImage] " +
                    "phase=\(phase) " +
                    "boardID=\(item.boardID.uuidString) " +
                    "itemID=\(imageItemRecord.id.uuidString) " +
                    "assetFilename=\(previewAssetFilename) " +
                    "signature=\(BoardThumbnailImageSignature.describe(image))"
            )
        } catch {
            print(
                "[BoardList][ThumbnailTrace][SourceImage] " +
                    "phase=\(phase) " +
                    "boardID=\(item.boardID.uuidString) " +
                    "itemID=\(imageItemRecord.id.uuidString) " +
                    "assetFilename=\(previewAssetFilename) " +
                    "status=read-failed " +
                    "error=\(error)"
            )
        }
    }
}

private func logBoardPreviewProviderDecision(
    phase: String,
    boardID: UUID,
    revisionToken: String,
    targetPixelSize: CGSize,
    source: String,
    reason: String? = nil
) {
    var message =
        "[BoardList][ThumbnailTrace][Provider] " +
        "phase=\(phase) " +
        "boardID=\(boardID.uuidString) " +
        "revision=\(revisionToken) " +
        "targetPixelSize=\(describeBoardPreviewProviderSize(targetPixelSize)) " +
        "source=\(source)"
    if let reason {
        message += " reason=\(reason)"
    }
    print(message)
}

private func describeBoardPreviewProviderSize(_ size: CGSize) -> String {
    "{\(formatBoardPreviewProviderValue(size.width)), \(formatBoardPreviewProviderValue(size.height))}"
}

private func formatBoardPreviewProviderValue(_ value: CGFloat) -> String {
    String(format: "%.2f", Double(value))
}
