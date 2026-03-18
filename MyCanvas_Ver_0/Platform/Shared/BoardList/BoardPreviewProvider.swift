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
        if let targetPixelSize,
           let cacheKey = BoardThumbnailCacheKey(
               item: item,
               targetPixelSize: targetPixelSize
           ),
           let cachedImage = thumbnailCache.image(for: cacheKey) {
            return .thumbnail(cachedImage, item.previewSeed)
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
                guard
                    let renderedImage = try self.thumbnailRenderer.renderThumbnail(
                        for: item,
                        targetPixelSize: cacheKey.pixelSize,
                        cancellationCheck: {
                            if operation.isCancelled || requestToken.isCancelled {
                                throw BoardThumbnailRendererError.cancelled
                            }
                        }
                    )
                else {
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
}
