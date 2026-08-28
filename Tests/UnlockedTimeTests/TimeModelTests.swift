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

    @Test func marksPTODaysInDailySeries() {
        let series = TimeSummary.dailySeries(
            sessions: [],
            now: date(2026, 8, 28, 12),
            limitMinutes: 8 * 60,
            count: 3,
            ptoDays: [TimeSummary.dayKey(date(2026, 8, 27), calendar: calendar)],
            calendar: calendar
        )

        #expect(series.map(\.isPTO) == [false, true, false])
    }

    @Test func weekCountsAsPTOOnlyWhenEveryDayMarked() {
        let weekStart = date(2026, 8, 24)
        var keys = Set((0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: weekStart)
                .map { TimeSummary.dayKey($0, calendar: calendar) }
        })

        let whole = TimeSummary.weeklySeries(
            sessions: [],
            now: date(2026, 8, 28, 12),
            limitMinutes: 40 * 60,
            count: 1,
            ptoDays: keys,
            calendar: calendar
        )
        #expect(whole[0].isPTO)

        keys.remove(TimeSummary.dayKey(date(2026, 8, 26), calendar: calendar))
        let partial = TimeSummary.weeklySeries(
            sessions: [],
            now: date(2026, 8, 28, 12),
            limitMinutes: 40 * 60,
            count: 1,
            ptoDays: keys,
            calendar: calendar
        )
        #expect(!partial[0].isPTO)
    }

    @Test func listsIntervalsClippedToTheDay() {
        let sessions = [
            WorkSession(start: date(2026, 8, 26, 23, 0), end: date(2026, 8, 27, 1, 30)),
            WorkSession(start: date(2026, 8, 27, 9, 0), end: date(2026, 8, 27, 11, 15)),
            WorkSession(start: date(2026, 8, 28, 8, 0), end: date(2026, 8, 28, 9, 0))
        ]

        let intervals = TimeSummary.intervals(
            sessions: sessions,
            on: date(2026, 8, 27),
            now: date(2026, 8, 28, 12),
            calendar: calendar
        )

        #expect(intervals.count == 2)
        #expect(intervals[0].start == date(2026, 8, 27))
        #expect(intervals[0].end == date(2026, 8, 27, 1, 30))
        #expect(intervals.map(\.minutes) == [90, 135])
    }

    @Test func listsSevenDaysOfAGivenWeek() {
        let sessions = [WorkSession(start: date(2026, 8, 25, 8), end: date(2026, 8, 25, 10))]

        let days = TimeSummary.daysInWeek(
            sessions: sessions,
            weekStart: date(2026, 8, 24),
            now: date(2026, 8, 28, 12),
            limitMinutes: 8 * 60,
            calendar: calendar
        )

        #expect(days.count == 7)
        #expect(days.first?.start == date(2026, 8, 24))
        #expect(days.last?.start == date(2026, 8, 30))
        #expect(days[1].minutes == 120)
    }

    @Test func dayKeyRoundTrips() {
        let day = date(2026, 7, 6)
        let key = TimeSummary.dayKey(day, calendar: calendar)

        #expect(key == "2026-07-06")
        #expect(TimeSummary.date(fromDayKey: key, calendar: calendar) == day)
    }

    @Test func onlyWeekdayPTOReducesTheWeeklyLimit() {
        let keys: Set<String> = [
            TimeSummary.dayKey(date(2026, 8, 25), calendar: calendar),
            TimeSummary.dayKey(date(2026, 8, 29), calendar: calendar)
        ]

        let limit = TimeSummary.weeklyLimit(
            base: 40 * 60,
            weekStart: date(2026, 8, 24),
            ptoDays: keys,
            ptoDayMinutes: 450,
            enabled: true,
            calendar: calendar
        )

        #expect(limit == 40 * 60 - 450)
    }

    @Test func reducedWeeklyLimitStopsAtZero() {
        let keys = Set((0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: date(2026, 8, 24))
                .map { TimeSummary.dayKey($0, calendar: calendar) }
        })

        let limit = TimeSummary.weeklyLimit(
            base: 20 * 60,
            weekStart: date(2026, 8, 24),
            ptoDays: keys,
            ptoDayMinutes: 8 * 60,
            enabled: true,
            calendar: calendar
        )

        #expect(limit == 0)
    }

    @Test func weeklyLimitIsUntouchedWhenDisabled() {
        let keys: Set<String> = [TimeSummary.dayKey(date(2026, 8, 25), calendar: calendar)]

        let limit = TimeSummary.weeklyLimit(
            base: 40 * 60,
            weekStart: date(2026, 8, 24),
            ptoDays: keys,
            ptoDayMinutes: 450,
            enabled: false,
            calendar: calendar
        )

        #expect(limit == 40 * 60)
    }

    @Test func weeklySeriesCarriesTheReducedLimit() {
        let keys: Set<String> = [TimeSummary.dayKey(date(2026, 8, 25), calendar: calendar)]

        let series = TimeSummary.weeklySeries(
            sessions: [],
            now: date(2026, 8, 28, 12),
            limitMinutes: 40 * 60,
            count: 1,
            ptoDays: keys,
            ptoDayMinutes: 450,
            reducesLimitForPTO: true,
            calendar: calendar
        )

        #expect(series[0].limitMinutes == 40 * 60 - 450)
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