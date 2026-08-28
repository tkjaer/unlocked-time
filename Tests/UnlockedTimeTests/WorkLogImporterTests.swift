import Foundation
import Testing
@testable import UnlockedTime

struct WorkLogImporterTests {
    @Test func parsesDaysAndSplitIntervals() throws {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let text = """
        2026-08-17 08:20-14:30+16:00-23:30

        # A comment
        2026-08-18 07:45-16:15
        """

        let sessions = try WorkLogImporter.parse(text, calendar: calendar)

        #expect(sessions.count == 3)
        #expect(sessions.map { Int($0.end!.timeIntervalSince($0.start) / 60) } == [370, 450, 510])
    }

    @Test func rejectsOpenIntervals() {
        #expect(throws: Error.self) {
            try WorkLogImporter.parse("2026-08-28 08:00-")
        }
    }

    @Test func mergingTwiceSkipsDuplicatesAndPreservesOpenSession() throws {
        let imported = try WorkLogImporter.parse("2026-08-28 08:00-09:00")
        let open = WorkSession(start: Date())

        let first = WorkLogImporter.merge(imported, into: [open])
        let second = WorkLogImporter.merge(imported, into: first.0)

        #expect(first.1 == ImportResult(importedCount: 1, skippedCount: 0))
        #expect(second.1 == ImportResult(importedCount: 0, skippedCount: 1))
        #expect(second.0.count == 2)
        #expect(second.0.contains(open))
    }
}