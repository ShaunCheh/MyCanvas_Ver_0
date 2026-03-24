import Foundation

struct BoardSaveSnapshot {
    let runtimeState: BoardRuntimeState
    let transientImageAssetPayloads: [CanvasImageAssetReference: CanvasTransientImageAssetPayload]

    init(
        runtimeState: BoardRuntimeState,
        transientImageAssetPayloads: [CanvasImageAssetReference: CanvasTransientImageAssetPayload] = [:]
    ) {
        self.runtimeState = runtimeState
        self.transientImageAssetPayloads = transientImageAssetPayloads
    }

    func transientImageAssetPayload(
        for assetReference: CanvasImageAssetReference
    ) -> CanvasTransientImageAssetPayload? {
        transientImageAssetPayloads[assetReference]
    }
}

final class BoardSaveCoordinator {
    private let autosaveDelay: TimeInterval
    private let logPrefix: String
    private let saveQueue: DispatchQueue
    private var pendingAutosaveWorkItem: DispatchWorkItem?

    init(
        queueLabel: String,
        logPrefix: String,
        autosaveDelay: TimeInterval = 0.35
    ) {
        self.autosaveDelay = autosaveDelay
        self.logPrefix = logPrefix
        saveQueue = DispatchQueue(label: queueLabel, qos: .utility)
    }

    func scheduleAutosave(
        snapshot: BoardSaveSnapshot,
        reason: String,
        onFailure: ((Error) -> Void)? = nil
    ) {
        cancelPendingAutosave()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }

            self.pendingAutosaveWorkItem = nil
            self.enqueueSave(snapshot: snapshot, reason: reason) { result in
                guard let onFailure else {
                    return
                }

                if case let .failure(error) = result {
                    onFailure(error)
                }
            }
        }

        pendingAutosaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + autosaveDelay, execute: workItem)
    }

    func saveImmediately(
        snapshot: BoardSaveSnapshot,
        reason: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        cancelPendingAutosave()
        enqueueSave(
            snapshot: snapshot,
            reason: reason,
            completion: completion
        )
    }

    func cancelPendingAutosave() {
        pendingAutosaveWorkItem?.cancel()
        pendingAutosaveWorkItem = nil
    }

    private func enqueueSave(
        snapshot: BoardSaveSnapshot,
        reason: String,
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        saveQueue.async { [logPrefix] in
            let result: Result<Void, Error>
            do {
                try BoardStore.saveBoard(snapshot)
                result = .success(())
            } catch {
                print("\(logPrefix) Failed to save board (\(reason)): \(error)")
                result = .failure(error)
            }

            guard let completion else {
                return
            }

            DispatchQueue.main.async {
                completion(result)
            }
        }
    }
}
