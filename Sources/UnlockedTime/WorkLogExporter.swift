import Foundation

enum WorkLogExporter {
    static func text(
        sessions: [WorkSession],
        ptoDays: Set<String>,
        now: Date,
        calendar: Calendar = .current
    ) -> String {
        var intervalsByDay: [String: [WorkInterval]] = [:]

        for session in sessions {
            let end = min(session.end ?? now, now)
            guard end > session.start else { continue }

            var cursor = session.start
            while cursor < end {
                let dayStart = calendar.startOfDay(for: cursor)
                let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart)!
                let segmentEnd = min(end, nextDay)
                intervalsByDay[TimeSummary.dayKey(cursor, calendar: calendar), default: []]
                    .append(WorkInterval(start: cursor, end: segmentEnd))
                cursor = segmentEnd
            }
        }

        let keys = Set(intervalsByDay.keys).union(ptoDays).sorted()

        return keys.map { key in
            var parts = [key]
            if ptoDays.contains(key) {
                parts.append("PTO")
            }

            let intervals = (intervalsByDay[key] ?? []).sorted { $0.start < $1.start }
            if !intervals.isEmpty {
                parts.append(intervals.map { interval in
                    "\(clock(interval.start, dayKey: key, calendar: calendar))-\(clock(interval.end, dayKey: key, calendar: calendar))"
                }.joined(separator: "+"))
            }

            return parts.joined(separator: " ")
        }.joined(separator: "\n")
    }

    /// Midnight closing a day is written as 24:00 rather than 00:00 of the next one.
    private static func clock(_ date: Date, dayKey: String, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let hour = parts.hour ?? 0
        let minute = parts.minute ?? 0

        if hour == 0, minute == 0, TimeSummary.dayKey(date, calendar: calendar) != dayKey {
            return "24:00"
        }
        return String(format: "%02d:%02d", hour, minute)
    }
}
