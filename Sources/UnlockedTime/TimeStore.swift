import Foundation

struct StoredTimeData: Codable, Equatable, Sendable {
    var sessions: [WorkSession] = []
    var settings = TrackingSettings()
    var lastHeartbeat: Date?
}

struct TimeStore: Sendable {
    let fileURL: URL

    static func applicationSupport() throws -> TimeStore {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appending(path: "UnlockedTime", directoryHint: .isDirectory)
        return TimeStore(fileURL: directory.appending(path: "history.json"))
    }

    func load() throws -> StoredTimeData {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return StoredTimeData()
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(StoredTimeData.self, from: Data(contentsOf: fileURL))
    }

    func save(_ data: StoredTimeData) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(data).write(to: fileURL, options: .atomic)
    }
}