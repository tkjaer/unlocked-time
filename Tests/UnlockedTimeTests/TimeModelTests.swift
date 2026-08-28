import Foundation
import Testing
@testable import UnlockedTime

struct TimeModelTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    @Test func splitsSessionsAcrossMidnight() {
        let session = WorkSession(
            start: date(2026, 8, 26, 23, 0),
            end: date(2026, 8, 27, 1, 30)
        )

        let totals = TimeSummary.dailyTotals(
            sessions: [session],
            now: date(2026, 8, 27, 2, 0),
            limitMinutes: 8 * 60,
            calendar: calendar
        )

        #expect(totals.map(\.minutes) == [90, 60])
    }

    @Test func countsOpenSessionThroughNow() {
        let session = WorkSession(start: date(2026, 8, 28, 8, 15))

        let totals = TimeSummary.dailyTotals(
            sessions: [session],
            now: date(2026, 8, 28, 12, 45),
            limitMinutes: 4 * 60,
            calendar: calendar
        )

        #expect(totals[0].minutes == 270)
        #expect(totals[0].isOver)
        #expect(totals[0].overageMinutes == 30)
        #expect(totals[0].remainingMinutes == 0)
    }

    @Test func groupsISOWeeks() {
        let sessions = [
            WorkSession(start: date(2026, 8, 23, 8), end: date(2026, 8, 23, 10)),
            WorkSession(start: date(2026, 8, 24, 8), end: date(2026, 8, 24, 11))
        ]

        let totals = TimeSummary.weeklyTotals(
            sessions: sessions,
            now: date(2026, 8, 24, 12),
            limitMinutes: 40 * 60,
            calendar: calendar
        )

        #expect(totals.count == 2)
        #expect(totals.map(\.minutes) == [180, 120])
    }

    @Test func dailySeriesFillsGapsOldestFirst() {
        let sessions = [
            WorkSession(start: date(2026, 8, 26, 9), end: date(2026, 8, 26, 11)),
            WorkSession(start: date(2026, 8, 28, 8), end: date(2026, 8, 28, 9))
        ]

        let series = TimeSummary.dailySeries(
            sessions: sessions,
            now: date(2026, 8, 28, 12),
            limitMinutes: 8 * 60,
            count: 4,
            calendar: calendar
        )

        #expect(series.map(\.minutes) == [0, 120, 0, 60])
        #expect(series.first?.start == date(2026, 8, 25))
        #expect(series.last?.start == date(2026, 8, 28))
    }

    @Test func findsMomentWeeklyLimitWasReached() {
        let sessions = [
            WorkSession(start: date(2026, 8, 24, 8), end: date(2026, 8, 24, 16)),
            WorkSession(start: date(2026, 8, 25, 8), end: date(2026, 8, 25, 16))
        ]

        let crossing = TimeSummary.weeklyLimitCrossing(
            sessions: sessions,
            now: date(2026, 8, 25, 18),
            limitMinutes: 12 * 60,
            calendar: calendar
        )

        #expect(crossing == date(2026, 8, 25, 12))
    }

    @Test func noCrossingWhenUnderWeeklyLimit() {
        let sessions = [WorkSession(start: date(2026, 8, 24, 8), end: date(2026, 8, 24, 16))]

        let crossing = TimeSummary.weeklyLimitCrossing(
            sessions: sessions,
            now: date(2026, 8, 24, 18),
            limitMinutes: 40 * 60,
            calendar: calendar
        )

        #expect(crossing == nil)
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