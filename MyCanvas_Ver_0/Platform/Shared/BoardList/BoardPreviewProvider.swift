import CoreGraphics
import Foundation

final class BoardPreviewProvider {
    private let thumbnailCache: BoardThumbnailCache
    private let thumbnailRenderer: BoardThumbnailRenderer
    private let renderQueue: OperationQueue
    private let callbackQueue: DispatchQueue

    init(
        thumbnailCache: BoardThumbnailCache = BoardThumbnailCache(),
        thumbnailRenderer: BoardThumbnailRenderer = BoardThumbnailRenderer(),
        callbackQueue: DispatchQueue = .main
    ) {
        self.thumbnailCache = thumbnailCache
        self.thumbnailRenderer = thumbnailRenderer
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
            return .thumbnail(cachedImage, item.previewSeed)
        }

        do {
            if let persistedThumbnail = try loadPersistedThumbnailPreview(
                for: item,
                cacheKey: cacheKey
            ) {
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
            return requestToken
        }

        if let cachedImage = thumbnailCache.image(for: cacheKey) {
            callbackQueue.async { [weak requestToken] in
                guard let requestToken, requestToken.isCancelled == false else {
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
                    return
                }

                guard operation.isCancelled == false, requestToken.isCancelled == false else {
                    return
                }

                self.thumbnailCache.insert(renderedImage, for: cacheKey)
                self.callbackQueue.async { [weak requestToken] in
                    guard let requestToken, requestToken.isCancelled == false else {
                        return
                    }

                    completion(.thumbnail(renderedImage, item.previewSeed))
                }
            } catch BoardThumbnailRendererError.cancelled {
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
        return try thumbnailRenderer.renderThumbnail(
            for: item,
            targetPixelSize: cacheKey.pixelSize,
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
            return nil
        }

        let decodeMaxPixelSize = max(
            cacheKey.pixelWidth,
            cacheKey.pixelHeight
        )
        guard
            let persistedThumbnail = try BoardPersistedThumbnailStore.loadThumbnailIfFresh(
                at: item.persistedThumbnailURL,
                updatedAt: item.updatedAt,
                maxPixelSize: decodeMaxPixelSize
            )
        else {
            return nil
        }

        try cancellationCheck()
        return try thumbnailRenderer.renderThumbnail(
            fromPersistedThumbnail: persistedThumbnail,
            previewSeed: item.previewSeed,
            targetPixelSize: cacheKey.pixelSize,
            cancellationCheck: cancellationCheck
        )
    }
}
