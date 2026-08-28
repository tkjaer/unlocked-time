import AppKit
import CoreGraphics
import Foundation

@MainActor
final class TrackingController: ObservableObject {
    @Published private(set) var data: StoredTimeData
    @Published private(set) var now = Date()
    @Published private(set) var storageError: String?

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
            startSession(at: now)
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
    var isTracking: Bool { data.sessions.last?.end == nil }

    func updateSettings(dailyLimitMinutes: Int, weeklyLimitMinutes: Int) {
        data.settings.dailyLimitMinutes = dailyLimitMinutes
        data.settings.weeklyLimitMinutes = weeklyLimitMinutes
        persist()
    }

    func startSession(at date: Date = Date()) {
        guard !isTracking else { return }
        data.sessions.append(WorkSession(start: date))
        data.lastHeartbeat = date
        now = date
        persist()
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

    @discardableResult
    func importFile(at url: URL) throws -> ImportResult {
        let imported = try WorkLogImporter.parse(String(contentsOf: url, encoding: .utf8))
        let merged = WorkLogImporter.merge(imported, into: data.sessions)
        data.sessions = merged.0
        persist()
        return merged.1
    }

    private func recoverOpenSession(at date: Date) {
        guard let index = data.sessions.lastIndex(where: { $0.end == nil }) else { return }
        let recoveredEnd = data.lastHeartbeat ?? data.sessions[index].start
        data.sessions[index].end = min(max(data.sessions[index].start, recoveredEnd), date)
        persist()
    }

    private func heartbeat() {
        now = Date()
        if isTracking {
            data.lastHeartbeat = now
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

    private static var screenIsLocked: Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            return false
        }
        return session["CGSSessionScreenIsLocked"] as? Bool ?? false
    }
}