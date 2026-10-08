import Foundation
import Testing
@testable import UnlockedTime

struct HistoryChartTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    @Test func zoomStopsAtTheWholeHistory() {
        #expect(HistoryPeriod.weeks.zoomLevels(available: 8).map(\.count) == [8])
        #expect(HistoryPeriod.weeks.zoomLevels(available: 20).map(\.count) == [8, 13, 20])
        #expect(HistoryPeriod.weeks.zoomLevels(available: 20).last?.title == "All")
        #expect(HistoryPeriod.weeks.zoomLevels(available: 52).last?.title == "1 year")
        #expect(HistoryPeriod.weeks.zoomLevels(available: 300).map(\.count) == [8, 13, 26, 52, 104, 260, 300])
        #expect(HistoryPeriod.weeks.zoomLevels(available: 2000).map(\.count) == [8, 13, 26, 52, 104, 260, 520])
    }

    @Test func dayZoomStopsAtAYear() {
        #expect(HistoryPeriod.days.zoomLevels(available: 7).map(\.count) == [7])
        #expect(HistoryPeriod.days.zoomLevels(available: 40).map(\.count) == [7, 14, 30, 40])
        #expect(HistoryPeriod.days.zoomLevels(available: 2000).map(\.count) == [7, 14, 30, 91, 182, 365])
    }

    @Test func startsOnTheLatestPeriods() {
        let window = days(count: 30, length: 7)

        #expect(window.initialStart(showing: nil) == date(2026, 8, 22))
        #expect(window.visible(from: date(2026, 8, 22)).count == 7)
        #expect(window.visible(from: date(2026, 8, 22)).last?.start == date(2026, 8, 28))
    }

    @Test func scrollsToAnOlderSelectionAsTheRightmostBar() {
        let window = days(count: 30, length: 7)
        let start = window.start(showing: date(2026, 8, 10, 15), from: date(2026, 8, 22))

        #expect(start == date(2026, 8, 4))
        #expect(window.visible(from: start).last?.start == date(2026, 8, 10))
    }

    @Test func drawsOnlyAroundTheVisibleWindow() {
        let window = days(count: 5000, length: 7)
        let rendered = window.rendered(around: date(2026, 8, 1))

        #expect(rendered.count == 21)
        #expect(rendered.first?.start == date(2026, 7, 25))
        #expect(rendered.last?.start == date(2026, 8, 14))
    }

    @Test func reachesTheOldestPeriodOfALongHistory() {
        let window = days(count: 5000, length: 365)
        let oldest = window.series[0].start
        let start = window.start(showing: oldest, from: window.initialStart(showing: nil))

        #expect(start == oldest)
        #expect(window.visible(from: start).first?.start == oldest)
        #expect(window.rendered(around: start).contains { $0.start == oldest })
    }

    @Test func leavesTheWindowAloneWhenTheSelectionIsShown() {
        let window = days(count: 30, length: 7)

        #expect(window.start(showing: date(2026, 8, 24), from: date(2026, 8, 22)) == date(2026, 8, 22))
    }

    @Test func neverScrollsPastTheData() {
        let window = days(count: 30, length: 7)

        #expect(window.clamp(date(2026, 1, 1)) == date(2026, 7, 30))
        #expect(window.clamp(date(2026, 12, 1)) == date(2026, 8, 22))
        #expect(days(count: 7, length: 30).clamp(date(2026, 8, 25)) == date(2026, 8, 22))
    }

    @Test func zoomingOutFromThePresentKeepsThePresent() {
        let wide = days(count: 90, length: 30)
        let start = wide.start(zoomingFrom: date(2026, 8, 22), oldLength: 7, anchor: nil)

        #expect(wide.visible(from: start).last?.start == date(2026, 8, 28))
        #expect(wide.visible(from: start).count == 30)
    }

    @Test func zoomingKeepsTheSelectionInPlace() {
        let narrow = days(count: 90, length: 7)
        let start = narrow.start(zoomingFrom: date(2026, 7, 29), oldLength: 30, anchor: date(2026, 8, 13))

        #expect(narrow.visible(from: start).contains { $0.start == date(2026, 8, 13) })
        #expect(start == date(2026, 8, 10))
    }

    @Test func weeksScrollByWholeWeeks() {
        let series = (0..<30).reversed().map {
            PeriodTotal(
                start: calendar.date(byAdding: .weekOfYear, value: -$0, to: date(2026, 8, 24))!,
                minutes: 0,
                limitMinutes: 2400
            )
        }
        let window = ChartWindow(series: series, period: .weeks, length: 8, calendar: calendar)

        #expect(window.initialStart(showing: nil) == date(2026, 7, 6))
        #expect(window.start(showing: date(2026, 5, 6), from: date(2026, 7, 6)) == date(2026, 3, 16))
    }

    @Test func weeksComeToRestOnWholeWeeksAndTheEnd() {
        let series = (0..<30).reversed().map {
            PeriodTotal(
                start: calendar.date(byAdding: .weekOfYear, value: -$0, to: date(2026, 8, 24))!,
                minutes: 0,
                limitMinutes: 2400
            )
        }
        let window = ChartWindow(series: series, period: .weeks, length: 8, calendar: calendar)
        let week = 100.5
        let rest = { window.restingOffset(proposed: $0, contentWidth: 30 * week, containerWidth: 8 * week) }
        let end = 22 * week

        // A hair short of the end must not fall back a whole week.
        #expect(rest(end - 1e-9) == end)
        #expect(rest(end - 0.4 * week) == end)
        #expect(rest(end + 50) == end)
        #expect(rest(end - 0.6 * week) == 21 * week)
        #expect(rest(1.4 * week) == week)
        #expect(rest(1.6 * week) == 2 * week)
        #expect(rest(-20) == 0)
        #expect(window.restingOffset(proposed: 30, contentWidth: 500, containerWidth: 804) == 0)
    }

    @Test func daysComeToRestOnWholeDaysAndTheEnd() {
        let window = days(count: 60, length: 7)
        let day = 804.0 / 7
        let rest = { window.restingOffset(proposed: $0, contentWidth: 60 * day, containerWidth: 804) }
        let end = 53 * day

        #expect(abs(rest(end - 1e-6) - end) < 1e-9)
        #expect(abs(rest(3.4 * day) - 3 * day) < 1e-9)
        #expect(abs(rest(3.6 * day) - 4 * day) < 1e-9)
    }

    @Test func reachesTheEndWhenADaylightSavingChangeIsShown() {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "Europe/Copenhagen")!
        let last = calendar.date(from: DateComponents(year: 2026, month: 10, day: 30))!
        let series = (0..<10).reversed().map {
            PeriodTotal(start: calendar.date(byAdding: .day, value: -$0, to: last)!, minutes: 0, limitMinutes: 480)
        }
        let window = ChartWindow(series: series, period: .days, length: 7, calendar: calendar)
        // Clocks go back on 25 October, so the last seven days' worth of seconds starts at 01:00, not midnight.
        let pointsPerSecond = 804.0 / (7 * 86_400)
        let contentWidth = (10 * 86_400 + 3_600) * pointsPerSecond
        let end = contentWidth - 804

        #expect(abs(window.restingOffset(proposed: end - 1, contentWidth: contentWidth, containerWidth: 804) - end) < 1e-9)
    }

    @Test func summarisesTheRangeWithoutTheCurrentPeriodInTheAverage() {
        let totals = [
            PeriodTotal(start: date(2026, 8, 3), minutes: 2700, limitMinutes: 2400),
            PeriodTotal(start: date(2026, 8, 10), minutes: 0, limitMinutes: 2400, isPTO: true),
            PeriodTotal(start: date(2026, 8, 17), minutes: 2100, limitMinutes: 2400),
            PeriodTotal(start: date(2026, 8, 24), minutes: 600, limitMinutes: 2400)
        ]

        let summary = TimeSummary.rangeSummary(totals, inProgress: date(2026, 8, 24))

        #expect(summary.totalMinutes == 5400)
        #expect(summary.periodCount == 4)
        #expect(summary.periodsOver == 1)
        #expect(summary.overageMinutes == 300)
        #expect(summary.averageMinutes == 2400)
    }

    @Test func dailyAverageExcludesWorkedWeekendsAndPTO() {
        let totals = [
            PeriodTotal(start: date(2026, 8, 7), minutes: 420, limitMinutes: 420),
            PeriodTotal(start: date(2026, 8, 8), minutes: 60, limitMinutes: 420),
            PeriodTotal(start: date(2026, 8, 10), minutes: 120, limitMinutes: 420, isPTO: true),
            PeriodTotal(start: date(2026, 8, 11), minutes: 480, limitMinutes: 420),
            PeriodTotal(start: date(2026, 8, 12), minutes: 0, limitMinutes: 420),
            PeriodTotal(start: date(2026, 8, 13), minutes: 600, limitMinutes: 420)
        ]

        let summary = TimeSummary.rangeSummary(
            totals,
            inProgress: date(2026, 8, 13),
            countOnlyWorkedPeriods: true
        ) {
            HistoryPeriod.days.includesInAverage($0, calendar: calendar)
        }

        #expect(summary.totalMinutes == 1680)
        #expect(summary.periodCount == 2)
        #expect(summary.periodsOver == 1)
        #expect(summary.overageMinutes == 240)
        #expect(summary.averageMinutes == 450)
    }

    @Test func rollingAverageSkipsPeriodsWithoutTime() {
        let totals = [60, 0, 120, 0, 0, 0, 240].enumerated().map { offset, minutes in
            PeriodTotal(start: date(2026, 8, 1 + offset), minutes: minutes, limitMinutes: 480)
        }

        let averages = TimeSummary.rollingAverage(totals, window: 3)

        #expect(averages.map(\.minutes) == [60, 60, 90, 120, 120, 240])
        #expect(averages.map(\.start) == [1, 2, 3, 4, 5, 7].map { date(2026, 8, $0) })
    }

    @Test func dailyRollingAverageExcludesWorkedWeekendsAndPTO() {
        let totals = [
            PeriodTotal(start: date(2026, 8, 7), minutes: 420, limitMinutes: 420),
            PeriodTotal(start: date(2026, 8, 8), minutes: 60, limitMinutes: 420),
            PeriodTotal(start: date(2026, 8, 10), minutes: 120, limitMinutes: 420, isPTO: true),
            PeriodTotal(start: date(2026, 8, 11), minutes: 480, limitMinutes: 420)
        ]

        let averages = TimeSummary.rollingAverage(totals, window: 7) {
            HistoryPeriod.days.includesInAverage($0, calendar: calendar)
        }

        #expect(averages.last?.minutes == 450)
    }

    @Test func countsPTODaysInARange() {
        let pto: Set<String> = ["2026-08-09", "2026-08-10", "2026-08-16", "2026-08-17"]

        #expect(TimeSummary.ptoDayCount(pto, from: date(2026, 8, 10), to: date(2026, 8, 17), calendar: calendar) == 2)
    }

    @Test func hourAxisUsesWholeHours() {
        #expect(HourAxis.ticks(upTo: 762) == [0, 240, 480, 720])
        #expect(HourAxis.ticks(upTo: 2958) == [0, 1200, 2400])
        #expect(HourAxis.ticks(upTo: 60) == [0, 60])
        #expect(HourAxis.ticks(upTo: 150) == [0, 60, 120])
        #expect(HourAxis.ticks(upTo: 600 * 60) == [0, 12_000, 24_000, 36_000])
    }

    private func days(count: Int, length: Int) -> ChartWindow {
        let series = (0..<count).reversed().map {
            PeriodTotal(
                start: calendar.date(byAdding: .day, value: -$0, to: date(2026, 8, 28))!,
                minutes: 0,
                limitMinutes: 480
            )
        }
        return ChartWindow(series: series, period: .days, length: length, calendar: calendar)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
}
