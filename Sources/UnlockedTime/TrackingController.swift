import AppKit
import CoreGraphics
import Foundation

@MainActor
final class TrackingController: ObservableObject {
    @Published private(set) var data: StoredTimeData
    @Published private(set) var now = Date()
    @Published private(set) var storageError: String?
    @Published private(set) var pausedByIdle = false

    private let store: TimeStore
    private var workspaceObservers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []
    private var timer: Timer?

    init(store: TimeStore, now: Date = Date()) {
        self.store = store
        do {
            data = try store.load()
        } catch {
            data = StoredTimeData()
            storageError = error.localizedDescription
        }

        self.now = now
        recoverOpenSession(at: now)
        installObservers()

        if !Self.screenIsLocked {
            resumeOrStart(at: now)
        }

        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.heartbeat()
            }
        }
    }

    convenience init() {
        do {
            try self.init(store: TimeStore.applicationSupport())
        } catch {
            let fallback = TimeStore(fileURL: FileManager.default.temporaryDirectory.appending(path: "UnlockedTime-history.json"))
            self.init(store: fallback)
            storageError = error.localizedDescription
        }
    }

    isolated deinit {
        timer?.invalidate()
        workspaceObservers.forEach(NotificationCenter.default.removeObserver)
        distributedObservers.forEach(DistributedNotificationCenter.default().removeObserver)
    }

    var sessions: [WorkSession] { data.sessions }
    var settings: TrackingSettings { data.settings }
    var ptoDays: Set<String> { data.ptoDays }
    var isTracking: Bool { data.sessions.last?.end == nil }

    func updateSettings(
        dailyLimitMinutes: Int,
        weeklyLimitMinutes: Int,
        pausesWhenIdle: Bool,
        idleThresholdMinutes: Int,
        ptoReducesWeeklyLimit: Bool,
        ptoDayMinutes: Int
    ) {
        data.settings.dailyLimitMinutes = dailyLimitMinutes
        data.settings.weeklyLimitMinutes = weeklyLimitMinutes
        data.settings.pausesWhenIdle = pausesWhenIdle
        data.settings.idleThresholdMinutes = idleThresholdMinutes
        data.settings.ptoReducesWeeklyLimit = ptoReducesWeeklyLimit
        data.settings.ptoDayMinutes = ptoDayMinutes
        persist()
    }

    func weeklyLimit(for date: Date) -> Int {
        guard let weekStart = Calendar.current.dateInterval(of: .weekOfYear, for: date)?.start else {
            return data.settings.weeklyLimitMinutes
        }
        return TimeSummary.weeklyLimit(
            base: data.settings.weeklyLimitMinutes,
            weekStart: weekStart,
            ptoDays: data.ptoDays,
            ptoDayMinutes: data.settings.ptoDayMinutes,
            enabled: data.settings.ptoReducesWeeklyLimit
        )
    }

    func startSession(at date: Date = Date()) {
        guard !isTracking else { return }
        data.sessions.append(WorkSession(start: date))
        data.lastHeartbeat = date
        now = date
        pausedByIdle = false
        persist()
    }

    /// Restarting the app should not split a stretch of work into separate sessions.
    private func resumeOrStart(at date: Date) {
        guard
            let index = data.sessions.indices.last,
            let end = data.sessions[index].end,
            Self.canResume(lastEnd: end, now: date)
        else {
            startSession(at: date)
            return
        }

        data.sessions[index].end = nil
        data.lastHeartbeat = date
        now = date
        pausedByIdle = false
        persist()
    }

    nonisolated static func canResume(lastEnd: Date, now: Date, grace: TimeInterval = 120) -> Bool {
        let gap = now.timeIntervalSince(lastEnd)
        return gap >= 0 && gap <= grace
    }

    func stopSession(at date: Date = Date()) {
        guard let index = data.sessions.lastIndex(where: { $0.end == nil }) else { return }
        data.sessions[index].end = max(data.sessions[index].start, date)
        data.lastHeartbeat = date
        now = date
        persist()
    }

    func deleteSession(id: UUID) {
        data.sessions.removeAll { $0.id == id }
        persist()
    }

    func setPTO(_ isPTO: Bool, forDay date: Date) {
        apply(isPTO: isPTO, to: [date])
    }

    func setPTO(_ isPTO: Bool, forWeekContaining date: Date) {
        let calendar = Calendar.current
        guard let week = calendar.dateInterval(of: .weekOfYear, for: date) else { return }
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: week.start) }
        apply(isPTO: isPTO, to: days)
    }

    private func apply(isPTO: Bool, to days: [Date]) {
        for day in days {
            let key = TimeSummary.dayKey(day)
            if isPTO {
                data.ptoDays.insert(key)
            } else {
                data.ptoDays.remove(key)
            }
        }
        persist()
    }

    @discardableResult
    func importFile(at url: URL) throws -> ImportResult {
        let parsed = try WorkLogImporter.parse(String(contentsOf: url, encoding: .utf8))
        let merged = WorkLogImporter.merge(parsed.sessions, into: data.sessions)
        data.sessions = merged.0
        data.ptoDays.formUnion(parsed.ptoDays)
        persist()
        return merged.1
    }

    func exportText() -> String {
        WorkLogExporter.text(sessions: data.sessions, ptoDays: data.ptoDays, now: now)
    }

    private func recoverOpenSession(at date: Date) {
        guard let index = data.sessions.lastIndex(where: { $0.end == nil }) else { return }
        let recoveredEnd = data.lastHeartbeat ?? data.sessions[index].start
        data.sessions[index].end = min(max(data.sessions[index].start, recoveredEnd), date)
        persist()
    }

    private func heartbeat() {
        let current = Date()
        now = current

        if data.settings.pausesWhenIdle {
            let idle = Self.idleSeconds
            let threshold = TimeInterval(max(data.settings.idleThresholdMinutes, 1) * 60)

            if isTracking, idle >= threshold {
                stopSession(at: current.addingTimeInterval(-idle))
                pausedByIdle = true
                now = current
                return
            }

            if pausedByIdle, !isTracking, idle < threshold, !Self.screenIsLocked {
                startSession(at: current.addingTimeInterval(-idle))
                now = current
                return
            }
        }

        if isTracking {
            data.lastHeartbeat = current
            persist()
        }
    }

    private func persist() {
        do {
            try store.save(data)
            storageError = nil
        } catch {
            storageError = error.localizedDescription
        }
    }

    private func installObservers() {
        let center = NSWorkspace.shared.notificationCenter

        workspaceObservers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopSession() }
        })
        for name in [
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.sessionDidResignActiveNotification
        ] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.stopSession() }
            })
        }
        for name in [
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification
        ] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.startSession() }
            })
        }

        let distributedCenter = DistributedNotificationCenter.default()
        distributedObservers.append(distributedCenter.addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.stopSession() }
        })
        distributedObservers.append(distributedCenter.addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.startSession() }
        })
    }

    private static var idleSeconds: TimeInterval {
        guard let anyInput = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }

    private static var screenIsLocked: Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            return false
        }
        return session["CGSSessionScreenIsLocked"] as? Bool ?? false
    }
}