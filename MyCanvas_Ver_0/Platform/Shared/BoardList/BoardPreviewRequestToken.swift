import Foundation

final class BoardPreviewRequestToken {
    private let lock = NSLock()
    private var cancellationHandler: (() -> Void)?
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func setCancellationHandler(_ handler: @escaping () -> Void) {
        lock.lock()
        if cancelled {
            lock.unlock()
            handler()
            return
        }

        cancellationHandler = handler
        lock.unlock()
    }

    func cancel() {
        let handler: (() -> Void)?

        lock.lock()
        guard cancelled == false else {
            lock.unlock()
            return
        }

        cancelled = true
        handler = cancellationHandler
        cancellationHandler = nil
        lock.unlock()

        handler?()
    }
}
