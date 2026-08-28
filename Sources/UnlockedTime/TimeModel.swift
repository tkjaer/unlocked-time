import Foundation

struct WorkSession: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var start: Date
    var end: Date?

    init(id: UUID = UUID(), start: Date, end: Date? = nil) {
        self.id = id
        self.start = start
        self.end = end
    }
}

struct TrackingSettings: Codable, Equatable, Sendable {
    var dailyLimitMinutes = 8 * 60
    var weeklyLimitMinutes = 40 * 60
}

struct PeriodTotal: Identifiable, Equatable, Sendable {
    let start: Date
    let minutes: Int
    let limitMinutes: Int

    var id: Date { start }
    var overageMinutes: Int { max(0, minutes - limitMinutes) }
    var remainingMinutes: Int { max(0, limitMinutes - minutes) }
    var isOver: Bool { minutes > limitMinutes }
}

enum TimeSummary {
    static func dailyTotals(
        sessions: [WorkSession],
        now: Date,
        limitMinutes: Int,
        calendar: Calendar = .current
    ) -> [PeriodTotal] {
        totals(sessions: sessions, now: now, limitMinutes: limitMinutes, calendar: calendar) {
            calendar.startOfDay(for: $0)
        }
    }

    static func weeklyTotals(
        sessions: [WorkSession],
        now: Date,
        limitMinutes: Int,
        calendar: Calendar = .current
    ) -> [PeriodTotal] {
        totals(sessions: sessions, now: now, limitMinutes: limitMinutes, calendar: calendar) {
            calendar.dateInterval(of: .weekOfYear, for: $0)!.start
        }
    }

    /// Continuous oldest-to-newest periods ending at the current one, including periods without sessions.
    static func dailySeries(
        sessions: [WorkSession],
        now: Date,
        limitMinutes: Int,
        count: Int,
        calendar: Calendar = .current
    ) -> [PeriodTotal] {
        series(
            totals: dailyTotals(sessions: sessions, now: now, limitMinutes: limitMinutes, calendar: calendar),
            anchor: calendar.startOfDay(for: now),
            component: .day,
            count: count,
            limitMinutes: limitMinutes,
            calendar: calendar
        )
    }

    static func weeklySeries(
        sessions: [WorkSession],
        now: Date,
        limitMinutes: Int,
        count: Int,
        calendar: Calendar = .current
    ) -> [PeriodTotal] {
        series(
            totals: weeklyTotals(sessions: sessions, now: now, limitMinutes: limitMinutes, calendar: calendar),
            anchor: calendar.dateInterval(of: .weekOfYear, for: now)!.start,
            component: .weekOfYear,
            count: count,
            limitMinutes: limitMinutes,
            calendar: calendar
        )
    }

    /// Moment within the current week when accumulated time first reached the weekly limit.
    static func weeklyLimitCrossing(
        sessions: [WorkSession],
        now: Date,
        limitMinutes: Int,
        calendar: Calendar = .current
    ) -> Date? {
        guard limitMinutes > 0, let week = calendar.dateInterval(of: .weekOfYear, for: now) else {
            return nil
        }

        let target = TimeInterval(limitMinutes * 60)
        let segments = sessions.compactMap { session -> (start: Date, end: Date)? in
            let start = max(session.start, week.start)
            let end = min(session.end ?? now, min(week.end, now))
            return end > start ? (start, end) : nil
        }.sorted { $0.start < $1.start }

        var accumulated: TimeInterval = 0
        for segment in segments {
            let duration = segment.end.timeIntervalSince(segment.start)
            if accumulated + duration >= target {
                return segment.start.addingTimeInterval(target - accumulated)
            }
            accumulated += duration
        }

        return nil
    }

    private static func series(
        totals: [PeriodTotal],
        anchor: Date,
        component: Calendar.Component,
        count: Int,
        limitMinutes: Int,
        calendar: Calendar
    ) -> [PeriodTotal] {
        var minutesByStart: [Date: Int] = [:]

        for total in totals {
            minutesByStart[total.start] = total.minutes
        }

        return (0..<max(count, 0)).reversed().map { offset in
            let start = calendar.date(byAdding: component, value: -offset, to: anchor)!
            return PeriodTotal(start: start, minutes: minutesByStart[start] ?? 0, limitMinutes: limitMinutes)
        }
    }

    private static func totals(
        sessions: [WorkSession],
        now: Date,
        limitMinutes: Int,
        calendar: Calendar,
        periodStart: (Date) -> Date
    ) -> [PeriodTotal] {
        var secondsByPeriod: [Date: TimeInterval] = [:]

        for session in sessions {
            let sessionEnd = session.end ?? now
            guard sessionEnd > session.start else { continue }

            var cursor = session.start
            while cursor < sessionEnd {
                let start = periodStart(cursor)
                let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: cursor))!
                let segmentEnd = min(sessionEnd, nextDay)
                secondsByPeriod[start, default: 0] += segmentEnd.timeIntervalSince(cursor)
                cursor = segmentEnd
            }
        }

        return secondsByPeriod.map { start, seconds in
            PeriodTotal(start: start, minutes: Int(seconds / 60), limitMinutes: limitMinutes)
        }.sorted { $0.start > $1.start }
    }
}

func formatMinutes(_ minutes: Int) -> String {
    "\(minutes / 60)h \(String(format: "%02d", minutes % 60))m"
}

func formatMinutesCompact(_ minutes: Int) -> String {
    "\(minutes / 60)h\(String(format: "%02d", minutes % 60))"
}