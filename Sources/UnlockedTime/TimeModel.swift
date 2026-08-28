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
    var dailyLimitMinutes: Int
    var weeklyLimitMinutes: Int
    var pausesWhenIdle: Bool
    var idleThresholdMinutes: Int

    init(
        dailyLimitMinutes: Int = 8 * 60,
        weeklyLimitMinutes: Int = 40 * 60,
        pausesWhenIdle: Bool = true,
        idleThresholdMinutes: Int = 10
    ) {
        self.dailyLimitMinutes = dailyLimitMinutes
        self.weeklyLimitMinutes = weeklyLimitMinutes
        self.pausesWhenIdle = pausesWhenIdle
        self.idleThresholdMinutes = idleThresholdMinutes
    }

    /// Files written before a field existed must still load, so every key falls back to its default.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = TrackingSettings()
        dailyLimitMinutes = try container.decodeIfPresent(Int.self, forKey: .dailyLimitMinutes)
            ?? defaults.dailyLimitMinutes
        weeklyLimitMinutes = try container.decodeIfPresent(Int.self, forKey: .weeklyLimitMinutes)
            ?? defaults.weeklyLimitMinutes
        pausesWhenIdle = try container.decodeIfPresent(Bool.self, forKey: .pausesWhenIdle)
            ?? defaults.pausesWhenIdle
        idleThresholdMinutes = try container.decodeIfPresent(Int.self, forKey: .idleThresholdMinutes)
            ?? defaults.idleThresholdMinutes
    }
}

struct PeriodTotal: Identifiable, Equatable, Sendable {
    let start: Date
    let minutes: Int
    let limitMinutes: Int
    var isPTO = false

    var id: Date { start }
    var overageMinutes: Int { max(0, minutes - limitMinutes) }
    var remainingMinutes: Int { max(0, limitMinutes - minutes) }
    var isOver: Bool { minutes > limitMinutes }
}

struct WorkInterval: Identifiable, Equatable, Sendable {
    let start: Date
    let end: Date

    var id: Date { start }
    var minutes: Int { Int(end.timeIntervalSince(start) / 60) }
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
        ptoDays: Set<String> = [],
        calendar: Calendar = .current
    ) -> [PeriodTotal] {
        series(
            totals: dailyTotals(sessions: sessions, now: now, limitMinutes: limitMinutes, calendar: calendar),
            anchor: calendar.startOfDay(for: now),
            component: .day,
            count: count,
            limitMinutes: limitMinutes,
            calendar: calendar,
            isPTO: { ptoDays.contains(dayKey($0, calendar: calendar)) }
        )
    }

    static func weeklySeries(
        sessions: [WorkSession],
        now: Date,
        limitMinutes: Int,
        count: Int,
        ptoDays: Set<String> = [],
        calendar: Calendar = .current
    ) -> [PeriodTotal] {
        series(
            totals: weeklyTotals(sessions: sessions, now: now, limitMinutes: limitMinutes, calendar: calendar),
            anchor: calendar.dateInterval(of: .weekOfYear, for: now)!.start,
            component: .weekOfYear,
            count: count,
            limitMinutes: limitMinutes,
            calendar: calendar,
            isPTO: { weekIsPTO(weekStart: $0, ptoDays: ptoDays, calendar: calendar) }
        )
    }

    /// Calendar day identity, so a marked day cannot drift with time zone or daylight saving changes.
    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func date(fromDayKey key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// The seven days of the week containing `weekStart`, oldest first.
    static func daysInWeek(
        sessions: [WorkSession],
        weekStart: Date,
        now: Date,
        limitMinutes: Int,
        ptoDays: Set<String> = [],
        calendar: Calendar = .current
    ) -> [PeriodTotal] {
        let anchor = calendar.date(byAdding: .day, value: 6, to: weekStart)!
        return series(
            totals: dailyTotals(sessions: sessions, now: now, limitMinutes: limitMinutes, calendar: calendar),
            anchor: anchor,
            component: .day,
            count: 7,
            limitMinutes: limitMinutes,
            calendar: calendar,
            isPTO: { ptoDays.contains(dayKey($0, calendar: calendar)) }
        )
    }

    /// Worked stretches on a single day, clipped to that day and ordered.
    static func intervals(
        sessions: [WorkSession],
        on day: Date,
        now: Date,
        calendar: Calendar = .current
    ) -> [WorkInterval] {
        let dayStart = calendar.startOfDay(for: day)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!

        return sessions.compactMap { session in
            let start = max(session.start, dayStart)
            let end = min(session.end ?? now, dayEnd)
            return end > start ? WorkInterval(start: start, end: end) : nil
        }.sorted { $0.start < $1.start }
    }

    static func weekIsPTO(weekStart: Date, ptoDays: Set<String>, calendar: Calendar = .current) -> Bool {
        guard !ptoDays.isEmpty else { return false }
        return (0..<7).allSatisfy { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: weekStart) else { return false }
            return ptoDays.contains(dayKey(day, calendar: calendar))
        }
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
        calendar: Calendar,
        isPTO: (Date) -> Bool
    ) -> [PeriodTotal] {
        var minutesByStart: [Date: Int] = [:]

        for total in totals {
            minutesByStart[total.start] = total.minutes
        }

        return (0..<max(count, 0)).reversed().map { offset in
            let start = calendar.date(byAdding: component, value: -offset, to: anchor)!
            return PeriodTotal(
                start: start,
                minutes: minutesByStart[start] ?? 0,
                limitMinutes: limitMinutes,
                isPTO: isPTO(start)
            )
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