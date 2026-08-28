import Foundation
import Testing
@testable import UnlockedTime

struct TimeStoreTests {
    @Test func roundTripsHistoryAndSettings() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TimeStore(fileURL: directory.appending(path: "history.json"))
        let expected = StoredTimeData(
            sessions: [WorkSession(start: Date(timeIntervalSince1970: 100), end: Date(timeIntervalSince1970: 200))],
            settings: TrackingSettings(dailyLimitMinutes: 420, weeklyLimitMinutes: 2_100),
            lastHeartbeat: Date(timeIntervalSince1970: 200)
        )

        try store.save(expected)
        let actual = try store.load()

        #expect(actual == expected)
    }

    @Test func missingStoreStartsEmpty() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "history.json")

        let data = try TimeStore(fileURL: url).load()

        #expect(data == StoredTimeData())
    }
}