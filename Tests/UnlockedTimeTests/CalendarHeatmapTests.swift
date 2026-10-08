import Foundation
import Testing
@testable import UnlockedTime

struct CalendarHeatmapTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    @Test func yearEndsTodayAndStepsBackWholeYears() {
        let latest = HeatmapYear.ending(date(2026, 10, 8, 15), yearsBack: 0, calendar: calendar)
        let previous = HeatmapYear.ending(date(2026, 10, 8), yearsBack: 1, calendar: calendar)

        #expect(latest.start == date(2025, 10, 9))
        #expect(latest.end == date(2026, 10, 8))
        #expect(latest.dayCount(calendar: calendar) == 365)
        #expect(previous.start == date(2024, 10, 9))
        #expect(previous.end == date(2025, 10, 8))
        #expect(previous.dayCount(calendar: calendar) == 365)
    }

    @Test func yearsMeetWithoutGapsAcrossALeapDay() {
        let today = date(2028, 2, 29)
        let latest = HeatmapYear.ending(today, yearsBack: 0, calendar: calendar)
        let previous = HeatmapYear.ending(today, yearsBack: 1, calendar: calendar)

        #expect(latest.start == date(2027, 3, 1))
        #expect(previous.end == date(2027, 2, 28))
        #expect(latest.dayCount(calendar: calendar) == 366)
    }

    @Test func findsTheYearHoldingADate() {
        let today = date(2026, 10, 8)

        #expect(HeatmapYear.yearsBack(containing: date(2026, 10, 8, 12), today: today, calendar: calendar) == 0)
        #expect(HeatmapYear.yearsBack(containing: date(2025, 10, 9), today: today, calendar: calendar) == 0)
        #expect(HeatmapYear.yearsBack(containing: date(2025, 10, 8), today: today, calendar: calendar) == 1)
        #expect(HeatmapYear.yearsBack(containing: date(2027, 1, 1), today: today, calendar: calendar) == 0)
        #expect(HeatmapYear.yearsBack(containing: date(2011, 10, 9), today: today, calendar: calendar) == 14)
        #expect(HeatmapYear.yearsBack(containing: date(2011, 10, 8), today: today, calendar: calendar) == 15)

        for yearsBack in 0..<15 {
            let year = HeatmapYear.ending(today, yearsBack: yearsBack, calendar: calendar)
            #expect(HeatmapYear.yearsBack(containing: year.start, today: today, calendar: calendar) == yearsBack)
            #expect(HeatmapYear.yearsBack(containing: year.end, today: today, calendar: calendar) == yearsBack)
        }
    }

    @Test func weekOverlapsAYearWhenAnyOfItsDaysIsIn() {
        let year = HeatmapYear.ending(date(2026, 10, 8), yearsBack: 1, calendar: calendar)

        #expect(year.overlaps(date(2024, 10, 7), through: date(2024, 10, 13)))
        #expect(year.overlaps(date(2025, 10, 6), through: date(2025, 10, 12)))
        #expect(!year.overlaps(date(2025, 10, 13), through: date(2025, 10, 19)))
        #expect(!year.overlaps(date(2024, 9, 30), through: date(2024, 10, 6)))
    }

    @Test func slicesTheYearOutOfALongSeries() {
        let series = days(count: 5000, endingOn: date(2026, 10, 8))
        let latest = HeatmapYear.ending(date(2026, 10, 8), yearsBack: 0, calendar: calendar).days(in: series, calendar: calendar)
        let older = HeatmapYear.ending(date(2026, 10, 8), yearsBack: 3, calendar: calendar).days(in: series, calendar: calendar)

        #expect(latest.count == 365)
        #expect(latest.first?.start == date(2025, 10, 9))
        #expect(latest.last?.start == date(2026, 10, 8))
        #expect(older.first?.start == date(2022, 10, 9))
        #expect(older.last?.start == date(2023, 10, 8))
    }

    @Test func slicesOnlyRecordedDaysOfAShortHistory() {
        let series = days(count: 30, endingOn: date(2026, 10, 8))
        let year = HeatmapYear.ending(date(2026, 10, 8), yearsBack: 0, calendar: calendar)

        #expect(year.days(in: series, calendar: calendar).count == 30)
        #expect(HeatmapYear.ending(date(2026, 10, 8), yearsBack: 1, calendar: calendar).days(in: series, calendar: calendar).isEmpty)
    }

    @Test func laysOutWeeksAsColumnsFromTheFirstWeekday() {
        let series = days(count: 100, endingOn: date(2026, 10, 8))
        let year = HeatmapYear.ending(date(2026, 10, 8), yearsBack: 0, calendar: calendar)
        let layout = HeatmapLayout(days: series, year: year, calendar: calendar)

        // 9 Oct 2025 is a Thursday and ISO weeks start on Monday.
        #expect(layout.leading == 3)
        #expect(layout.columns == 53)
        #expect(layout.cells.count == 365)
        #expect(layout.cells.first == HeatmapLayout.Cell(date: date(2025, 10, 9), total: nil, column: 0, row: 3))
        #expect(layout.cells.last?.date == date(2026, 10, 8))
        #expect(layout.cells.last?.column == 52)
        #expect(layout.cells.last?.row == 3)
        #expect(layout.cell(column: 0, row: 2) == nil)
        #expect(layout.cell(column: 52, row: 4) == nil)
        #expect(layout.cell(column: 1, row: 0)?.date == date(2025, 10, 13))
        #expect(layout.weekStart(column: 0) == date(2025, 10, 6))
        #expect(layout.weekStart(column: 52) == date(2026, 10, 5))
        #expect(layout.column(containing: date(2026, 10, 8, 18)) == 52)
        #expect(layout.column(containing: date(2025, 10, 6)) == 0)
        #expect(layout.column(containing: date(2025, 10, 5)) == nil)
    }

    @Test func cellsCarryTheirDaysTotals() {
        let series = days(count: 100, endingOn: date(2026, 10, 8))
        let year = HeatmapYear.ending(date(2026, 10, 8), yearsBack: 0, calendar: calendar)
        let layout = HeatmapLayout(days: series, year: year, calendar: calendar)

        let recorded = layout.cells.filter { $0.total != nil }
        #expect(recorded.count == 100)
        #expect(recorded.allSatisfy { $0.total?.start == $0.date })
        #expect(recorded.first?.date == series.first?.start)
        #expect(layout.cells[264].total == nil)
        #expect(layout.cells[265].total == series.first)
    }

    @Test func dateMatchesPositionAcrossDaylightSaving() {
        var copenhagen = calendar
        copenhagen.timeZone = TimeZone(identifier: "Europe/Copenhagen")!
        let today = copenhagen.date(from: DateComponents(year: 2026, month: 10, day: 8))!
        let series = (0..<200).reversed().map {
            PeriodTotal(start: copenhagen.date(byAdding: .day, value: -$0, to: today)!, minutes: 0, limitMinutes: 480)
        }
        let layout = HeatmapLayout(days: series, year: .ending(today, yearsBack: 0, calendar: copenhagen), calendar: copenhagen)

        for cell in layout.cells {
            let weekday = copenhagen.component(.weekday, from: cell.date)
            #expect((weekday - copenhagen.firstWeekday + 7) % 7 == cell.row)
            #expect(copenhagen.startOfDay(for: cell.date) == cell.date)
        }
    }

    @Test func labelsMonthsWhereTheyStart() {
        let year = HeatmapYear.ending(date(2026, 10, 8), yearsBack: 0, calendar: calendar)
        let layout = HeatmapLayout(days: [], year: year, calendar: calendar)

        #expect(layout.months.count == 13)
        #expect(layout.months.first == HeatmapLayout.MonthLabel(column: 0, date: date(2025, 10, 9)))
        #expect(layout.months[1] == HeatmapLayout.MonthLabel(column: 3, date: date(2025, 11, 1)))
        #expect(layout.months.last == HeatmapLayout.MonthLabel(column: 51, date: date(2026, 10, 1)))
    }

    @Test func dropsACrampedFirstMonthLabel() {
        let year = HeatmapYear.ending(date(2026, 10, 25), yearsBack: 0, calendar: calendar)
        let layout = HeatmapLayout(days: [], year: year, calendar: calendar)

        #expect(layout.months.first?.date == date(2025, 11, 1))
        #expect(layout.months.count == 12)
    }

    @Test func labelsMondayWednesdayAndFriday() {
        #expect(HeatmapLayout.weekdayLabels(calendar: calendar).map(\.row) == [0, 2, 4])
        #expect(HeatmapLayout.weekdayLabels(calendar: calendar).map(\.title) == ["Mon", "Wed", "Fri"])

        var sundayFirst = Calendar(identifier: .gregorian)
        sundayFirst.locale = Locale(identifier: "en_US_POSIX")
        sundayFirst.firstWeekday = 1
        #expect(HeatmapLayout.weekdayLabels(calendar: sundayFirst).map(\.row) == [1, 3, 5])
    }

    @Test func intensityScalesWithQuartersOfTheLimit() {
        let levels = [0, 1, 120, 121, 240, 241, 360, 361, 480, 900].map {
            HeatmapScale.level(minutes: $0, limitMinutes: 480)
        }

        #expect(levels == [0, 1, 1, 2, 2, 3, 3, 4, 4, 4])
        #expect(HeatmapScale.level(minutes: 30, limitMinutes: 0) == 4)
        #expect(HeatmapScale.level(minutes: 0, limitMinutes: 0) == 0)
    }

    private func days(count: Int, endingOn end: Date) -> [PeriodTotal] {
        (0..<count).reversed().map {
            PeriodTotal(start: calendar.date(byAdding: .day, value: -$0, to: end)!, minutes: 60, limitMinutes: 480)
        }
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
}
