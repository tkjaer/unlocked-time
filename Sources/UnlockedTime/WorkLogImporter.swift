import Foundation

struct ImportResult: Equatable, Sendable {
    let importedCount: Int
    let skippedCount: Int
}

struct ParsedWorkLog: Equatable, Sendable {
    var sessions: [WorkSession] = []
    var ptoDays: Set<String> = []
}

enum WorkLogImporter {
    static func parse(_ text: String, calendar: Calendar = .current) throws -> ParsedWorkLog {
        var sessions: [WorkSession] = []
        var ptoDays: Set<String> = []

        for (offset, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            let lineNumber = offset + 1
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }

            var tokens = line.split(whereSeparator: { $0.isWhitespace })
            let dayStart = try day(String(tokens.removeFirst()), calendar: calendar, lineNumber: lineNumber)

            var isPTO = false
            if let marker = tokens.first, marker.uppercased() == "PTO" {
                isPTO = true
                ptoDays.insert(TimeSummary.dayKey(dayStart, calendar: calendar))
                tokens.removeFirst()
            }

            guard tokens.count <= 1 else {
                throw importError(lineNumber, "expected YYYY-MM-DD [PTO] [HH:MM-HH:MM]")
            }

            guard let intervalField = tokens.first else {
                if isPTO { continue }
                throw importError(lineNumber, "expected YYYY-MM-DD [PTO] [HH:MM-HH:MM]")
            }

            for rawInterval in intervalField.split(separator: "+") {
                let times = rawInterval.split(separator: "-", omittingEmptySubsequences: false)
                guard times.count == 2, !times[0].isEmpty, !times[1].isEmpty else {
                    throw importError(lineNumber, "only completed intervals can be imported")
                }

                let start = try instant(String(times[0]), on: dayStart, calendar: calendar, lineNumber: lineNumber)
                let end = try instant(String(times[1]), on: dayStart, calendar: calendar, lineNumber: lineNumber)
                guard end > start else {
                    throw importError(lineNumber, "interval must end after it starts")
                }
                sessions.append(WorkSession(start: start, end: end))
            }
        }

        return ParsedWorkLog(sessions: sessions, ptoDays: ptoDays)
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

    private static func day(_ value: String, calendar: Calendar, lineNumber: Int) throws -> Date {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard
            parts.count == 3,
            (1...12).contains(parts[1]),
            (1...31).contains(parts[2]),
            let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        else {
            throw importError(lineNumber, "invalid date \(value)")
        }
        return date
    }

    /// `24:00` is accepted so a session running to midnight can be written without losing a minute.
    private static func instant(
        _ value: String,
        on dayStart: Date,
        calendar: Calendar,
        lineNumber: Int
    ) throws -> Date {
        let parts = value.split(separator: ":")
        guard
            parts.count == 2,
            let hour = Int(parts[0]),
            let minute = Int(parts[1]),
            (0...24).contains(hour),
            (0...59).contains(minute),
            !(hour == 24 && minute > 0),
            let date = calendar.date(byAdding: DateComponents(hour: hour, minute: minute), to: dayStart)
        else {
            throw importError(lineNumber, "invalid time \(value)")
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