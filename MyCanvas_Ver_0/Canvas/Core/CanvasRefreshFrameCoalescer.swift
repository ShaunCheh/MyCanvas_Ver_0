struct CanvasRefreshFrameCoalescer {
    struct Pending: Equatable {
        let reason: String
        let generation: UInt64
    }

    private(set) var pending: Pending?

    mutating func request(reason: String, generation: UInt64) -> Bool {
        let needsSchedule = pending == nil
        pending = Pending(reason: reason, generation: generation)
        return needsSchedule
    }

    mutating func takePending(currentGeneration: UInt64) -> Pending? {
        defer {
            pending = nil
        }
        guard pending?.generation == currentGeneration else {
            return nil
        }
        return pending
    }

    mutating func cancel() {
        pending = nil
    }
}
