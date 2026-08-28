import Foundation

/// Synthetic history for screenshots, so published images never contain real hours.
enum DemoData {
    static func store() throws -> TimeStore {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "UnlockedTime-demo", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: directory)

        let store = TimeStore(fileURL: directory.appending(path: "history.json"))
        try store.save(seed())
        return store
    }

    private static let shapes: [[(start: (Int, Int), end: (Int, Int))]] = [
        [((8, 30), (12, 15)), ((13, 0), (17, 45))],
        [((9, 0), (12, 0)), ((12, 45), (18, 30))],
        [((8, 0), (12, 30)), ((13, 15), (19, 0))],
        [((9, 15), (12, 0)), ((13, 0), (16, 30))],
        [((8, 45), (12, 0)), ((12, 45), (17, 30))]
    ]

    private static func seed(now: Date = Date(), calendar: Calendar = .current) -> StoredTimeData {
        let today = calendar.startOfDay(for: now)
        var sessions: [WorkSession] = []
        var ptoDays: Set<String> = []

        for offset in 1...70 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            guard !calendar.isDateInWeekend(day) else { continue }

            // Two weeks off, so PTO shows in the day list, the week list and the chart.
            if (8...12).contains(offset) || (39...43).contains(offset) {
                ptoDays.insert(TimeSummary.dayKey(day, calendar: calendar))
                continue
            }

            for block in shapes[offset % shapes.count] {
                guard
                    let start = calendar.date(bySettingHour: block.start.0, minute: block.start.1, second: 0, of: day),
                    let end = calendar.date(bySettingHour: block.end.0, minute: block.end.1, second: 0, of: day)
                else { continue }
                sessions.append(WorkSession(start: start, end: end))
            }
        }

        if let start = calendar.date(bySettingHour: 8, minute: 40, second: 0, of: today),
           let end = calendar.date(bySettingHour: 12, minute: 5, second: 0, of: today),
           end < now {
            sessions.append(WorkSession(start: start, end: end))
        }

        sessions.sort { $0.start < $1.start }

        return StoredTimeData(
            sessions: sessions,
            settings: TrackingSettings(dailyLimitMinutes: 8 * 60, weeklyLimitMinutes: 40 * 60),
            ptoDays: ptoDays
        )
    }
}
