import Foundation

struct BoardListCanvasTransitionDebugTrace: Hashable, Sendable {
    var id: String
    var startedAtUptime: TimeInterval

    init(
        id: String = Self.makeID(),
        startedAtUptime: TimeInterval = BoardListCanvasTransitionDebugLogger.now()
    ) {
        self.id = id
        self.startedAtUptime = startedAtUptime
    }

    private static func makeID() -> String {
        String(UUID().uuidString.prefix(8))
    }
}

enum BoardListCanvasTransitionDebugLogger {
    static func now() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    static func timestampString(_ uptime: TimeInterval) -> String {
        String(format: "%.3f", uptime)
    }

    static func durationString(_ duration: TimeInterval) -> String {
        String(format: "%.3f", duration)
    }

    static func log(
        platform: String,
        component: String,
        trace: BoardListCanvasTransitionDebugTrace,
        phase: String,
        localDuration: TimeInterval? = nil,
        extra: String = ""
    ) {
        let currentUptime = now()
        let traceElapsed = currentUptime - trace.startedAtUptime
        let localSuffix = localDuration.map {
            " local=\(durationString($0))"
        } ?? ""
        let extraSuffix = extra.isEmpty ? "" : " \(extra)"
        print(
            "[BoardListCanvasTransition][\(platform)][\(component)] " +
                "t=\(timestampString(currentUptime)) " +
                "trace=\(trace.id) " +
                "elapsed=\(durationString(traceElapsed)) " +
                "phase=\(phase)" +
                localSuffix +
                extraSuffix
        )
    }
}
