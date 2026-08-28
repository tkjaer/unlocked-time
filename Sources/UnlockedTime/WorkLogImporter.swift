import Foundation

struct ImportResult: Equatable, Sendable {
    let importedCount: Int
    let skippedCount: Int
}

enum WorkLogImporter {
    static func parse(_ text: String, calendar: Calendar = .current) throws -> [WorkSession] {
        var sessions: [WorkSession] = []

        for (offset, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            let lineNumber = offset + 1
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }

            let fields = line.split(whereSeparator: { $0.isWhitespace })
            guard fields.count == 2 else {
                throw importError(lineNumber, "expected YYYY-MM-DD HH:MM-HH:MM")
            }

            let date = String(fields[0])
            for rawInterval in fields[1].split(separator: "+") {
                let times = rawInterval.split(separator: "-", omittingEmptySubsequences: false)
                guard times.count == 2, !times[0].isEmpty, !times[1].isEmpty else {
                    throw importError(lineNumber, "only completed intervals can be imported")
                }

                let start = try parseDate("\(date) \(times[0])", calendar: calendar, lineNumber: lineNumber)
                let end = try parseDate("\(date) \(times[1])", calendar: calendar, lineNumber: lineNumber)
                guard end > start else {
                    throw importError(lineNumber, "interval must end after it starts")
                }
                sessions.append(WorkSession(start: start, end: end))
            }
        }

        return sessions
    }

    static func merge(_ imported: [WorkSession], into existing: [WorkSession]) -> ([WorkSession], ImportResult) {
        var sessions = existing
        var seen = Set(existing.compactMap(SessionKey.init))
        var added = 0

        for session in imported {
            guard let key = SessionKey(session) else { continue }
            if seen.insert(key).inserted {
                sessions.append(session)
                added += 1
            }
        }

        sessions.sort { $0.start < $1.start }
        return (sessions, ImportResult(importedCount: added, skippedCount: imported.count - added))
    }

    private static func parseDate(_ value: String, calendar: Calendar, lineNumber: Int) throws -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.isLenient = false
        guard let date = formatter.date(from: value) else {
            throw importError(lineNumber, "invalid date or time \(value)")
        }
        return date
    }

    private static func importError(_ line: Int, _ message: String) -> NSError {
        NSError(
            domain: "UnlockedTime.WorkLogImporter",
            code: line,
            userInfo: [NSLocalizedDescriptionKey: "Line \(line): \(message)"]
        )
    }
}

private struct SessionKey: Hashable {
    let start: Date
    let end: Date

    init?(_ session: WorkSession) {
        guard let end = session.end else { return nil }
        start = session.start
        self.end = end
    }
}