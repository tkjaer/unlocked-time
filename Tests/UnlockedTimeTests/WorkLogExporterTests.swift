import Foundation
import Testing
@testable import UnlockedTime

struct WorkLogExporterTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    @Test func writesIntervalsAndPTODays() {
        let sessions = [
            WorkSession(start: date(2026, 8, 17, 8, 20), end: date(2026, 8, 17, 14, 30)),
            WorkSession(start: date(2026, 8, 17, 16, 0), end: date(2026, 8, 17, 23, 30)),
            WorkSession(start: date(2026, 8, 20, 9, 0), end: date(2026, 8, 20, 11, 0))
        ]

        let text = WorkLogExporter.text(
            sessions: sessions,
            ptoDays: ["2026-08-19", "2026-08-20"],
            now: date(2026, 8, 21),
            calendar: calendar
        )

        #expect(text == """
        2026-08-17 08:20-14:30+16:00-23:30
        2026-08-19 PTO
        2026-08-20 PTO 09:00-11:00
        """)
    }

    @Test func writesMidnightAsEndOfDay() {
        let sessions = [WorkSession(start: date(2026, 8, 26, 23, 0), end: date(2026, 8, 27, 1, 30))]

        let text = WorkLogExporter.text(
            sessions: sessions,
            ptoDays: [],
            now: date(2026, 8, 28),
            calendar: calendar
        )

        #expect(text == """
        2026-08-26 23:00-24:00
        2026-08-27 00:00-01:30
        """)
    }

    @Test func clipsAnOpenSessionToNow() {
        let sessions = [WorkSession(start: date(2026, 8, 28, 8, 0))]

        let text = WorkLogExporter.text(
            sessions: sessions,
            ptoDays: [],
            now: date(2026, 8, 28, 11, 45),
            calendar: calendar
        )

        #expect(text == "2026-08-28 08:00-11:45")
    }

    @Test func exportedTextReimportsUnchanged() throws {
        let sessions = [
            WorkSession(start: date(2026, 8, 26, 23, 0), end: date(2026, 8, 27, 1, 30)),
            WorkSession(start: date(2026, 8, 27, 9, 0), end: date(2026, 8, 27, 17, 15))
        ]
        let ptoDays: Set<String> = ["2026-08-19"]

        let text = WorkLogExporter.text(
            sessions: sessions,
            ptoDays: ptoDays,
            now: date(2026, 8, 28),
            calendar: calendar
        )
        let parsed = try WorkLogImporter.parse(text, calendar: calendar)

        #expect(parsed.ptoDays == ptoDays)
        #expect(parsed.sessions.map(\.start) == [
            date(2026, 8, 26, 23, 0),
            date(2026, 8, 27, 0, 0),
            date(2026, 8, 27, 9, 0)
        ])
        #expect(parsed.sessions.map { $0.end! } == [
            date(2026, 8, 27, 0, 0),
            date(2026, 8, 27, 1, 30),
            date(2026, 8, 27, 17, 15)
        ])
    }

    @Test func parsesPTOWithAndWithoutIntervals() throws {
        let parsed = try WorkLogImporter.parse(
            """
            2026-08-19 PTO
            2026-08-20 PTO 09:00-11:00
            """,
            calendar: calendar
        )

        #expect(parsed.ptoDays == ["2026-08-19", "2026-08-20"])
        #expect(parsed.sessions.count == 1)
        #expect(parsed.sessions[0].start == date(2026, 8, 20, 9, 0))
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }
}
