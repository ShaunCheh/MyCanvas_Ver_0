import Foundation

enum CoordinatedFileIO {
    static func ensureDirectory(
        at url: URL,
        fileManager: FileManager = .default
    ) throws {
        try coordinateWriting(at: url, options: .forMerging) { coordinatedURL in
            try fileManager.createDirectory(
                at: coordinatedURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
    }

    static func contentsOfDirectory(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey] = [.isDirectoryKey],
        options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles],
        fileManager: FileManager = .default
    ) throws -> [URL] {
        guard fileManager.fileExists(atPath: url.path) else {
            return []
        }

        return try coordinateReading(at: url) { coordinatedURL in
            try fileManager.contentsOfDirectory(
                at: coordinatedURL,
                includingPropertiesForKeys: keys,
                options: options
            )
        }
    }

    static func readData(
        at url: URL,
        fileManager: FileManager = .default
    ) throws -> Data {
        guard fileManager.fileExists(atPath: url.path) else {
            throw CocoaError(.fileReadNoSuchFile)
        }

        return try coordinateReading(at: url) { coordinatedURL in
            try Data(contentsOf: coordinatedURL)
        }
    }

    static func modificationDate(
        at url: URL,
        fileManager: FileManager = .default
    ) throws -> Date? {
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        return try coordinateReading(at: url) { coordinatedURL in
            try coordinatedURL
                .resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
        }
    }

    static func writeData(
        _ data: Data,
        to url: URL,
        fileManager: FileManager = .default
    ) throws {
        try ensureDirectory(at: url.deletingLastPathComponent(), fileManager: fileManager)
        try coordinateWriting(at: url) { coordinatedURL in
            try data.write(to: coordinatedURL, options: .atomic)
        }
    }

    static func removeItemIfExists(
        at url: URL,
        fileManager: FileManager = .default
    ) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }

        try coordinateWriting(at: url, options: .forDeleting) { coordinatedURL in
            try fileManager.removeItem(at: coordinatedURL)
        }
    }

    private static func coordinateReading<T>(
        at url: URL,
        accessor: (URL) throws -> T
    ) throws -> T {
        var coordinationError: NSError?
        var result: Result<T, Error>?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            result = Result {
                try accessor(coordinatedURL)
            }
        }

        if let coordinationError {
            throw coordinationError
        }

        guard let result else {
            throw CocoaError(.fileReadUnknown)
        }

        return try result.get()
    }

    private static func coordinateWriting<T>(
        at url: URL,
        options: NSFileCoordinator.WritingOptions = [],
        accessor: (URL) throws -> T
    ) throws -> T {
        var coordinationError: NSError?
        var result: Result<T, Error>?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(writingItemAt: url, options: options, error: &coordinationError) { coordinatedURL in
            result = Result {
                try accessor(coordinatedURL)
            }
        }

        if let coordinationError {
            throw coordinationError
        }

        guard let result else {
            throw CocoaError(.fileWriteUnknown)
        }

        return try result.get()
    }
}
