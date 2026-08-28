import Foundation

struct StoredTimeData: Codable, Equatable, Sendable {
    var sessions: [WorkSession]
    var settings: TrackingSettings
    var lastHeartbeat: Date?
    var ptoDays: Set<String>
    var notifiedDailyLimit: String?
    var notifiedWeeklyLimit: String?

    init(
        sessions: [WorkSession] = [],
        settings: TrackingSettings = TrackingSettings(),
        lastHeartbeat: Date? = nil,
        ptoDays: Set<String> = [],
        notifiedDailyLimit: String? = nil,
        notifiedWeeklyLimit: String? = nil
    ) {
        self.sessions = sessions
        self.settings = settings
        self.lastHeartbeat = lastHeartbeat
        self.ptoDays = ptoDays
        self.notifiedDailyLimit = notifiedDailyLimit
        self.notifiedWeeklyLimit = notifiedWeeklyLimit
    }

    /// Files written before a field existed must still load, so every key falls back to its default.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessions = try container.decodeIfPresent([WorkSession].self, forKey: .sessions) ?? []
        settings = try container.decodeIfPresent(TrackingSettings.self, forKey: .settings) ?? TrackingSettings()
        lastHeartbeat = try container.decodeIfPresent(Date.self, forKey: .lastHeartbeat)
        ptoDays = try container.decodeIfPresent(Set<String>.self, forKey: .ptoDays) ?? []
        notifiedDailyLimit = try container.decodeIfPresent(String.self, forKey: .notifiedDailyLimit)
        notifiedWeeklyLimit = try container.decodeIfPresent(String.self, forKey: .notifiedWeeklyLimit)
    }
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