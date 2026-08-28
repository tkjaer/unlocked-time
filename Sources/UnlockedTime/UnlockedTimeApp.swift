import Charts
import SwiftUI
import UniformTypeIdentifiers

@main
struct UnlockedTimeApp: App {
    @StateObject private var controller: TrackingController

    init() {
        let controller = TrackingController()
        if let optionIndex = CommandLine.arguments.firstIndex(of: "--import"),
           CommandLine.arguments.indices.contains(optionIndex + 1) {
            let path = NSString(string: CommandLine.arguments[optionIndex + 1]).expandingTildeInPath
            do {
                let result = try controller.importFile(at: URL(fileURLWithPath: path))
                print("Imported \(result.importedCount) sessions; skipped \(result.skippedCount) duplicates.")
            } catch {
                print("Import failed: \(error.localizedDescription)")
            }
        }
        _controller = StateObject(wrappedValue: controller)
    }

    var body: some Scene {
        MenuBarExtra {
            DashboardView(controller: controller)
        } label: {
            MenuBarLabel(controller: controller)
        }
        .menuBarExtraStyle(.window)

        Window("History", id: "history") {
            HistoryWindowView(controller: controller)
        }
        .defaultSize(width: 900, height: 600)
        .windowResizability(.contentSize)

        Settings {
            SettingsView(controller: controller)
        }
    }
}

private struct MenuBarLabel: View {
    @ObservedObject var controller: TrackingController

    var body: some View {
        let today = TimeSummary.dailySeries(
            sessions: controller.sessions,
            now: controller.now,
            limitMinutes: controller.settings.dailyLimitMinutes,
            count: 1
        )[0]

        Label(
            formatMinutesCompact(today.minutes),
            systemImage: today.isOver ? "exclamationmark.circle.fill" : "clock"
        )
    }
}

private struct DashboardView: View {
    @ObservedObject var controller: TrackingController
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @State private var trendPeriod = HistoryPeriod.days

    private var today: PeriodTotal {
        TimeSummary.dailySeries(
            sessions: controller.sessions,
            now: controller.now,
            limitMinutes: controller.settings.dailyLimitMinutes,
            count: 1
        )[0]
    }

    private var thisWeek: PeriodTotal {
        TimeSummary.weeklySeries(
            sessions: controller.sessions,
            now: controller.now,
            limitMinutes: controller.settings.weeklyLimitMinutes,
            count: 1,
            ptoDays: controller.ptoDays,
            ptoDayMinutes: controller.settings.ptoDayMinutes,
            reducesLimitForPTO: controller.settings.ptoReducesWeeklyLimit
        )[0]
    }

    private var trendSeries: [PeriodTotal] {
        switch trendPeriod {
        case .days:
            TimeSummary.dailySeries(
                sessions: controller.sessions,
                now: controller.now,
                limitMinutes: controller.settings.dailyLimitMinutes,
                count: HistoryPeriod.days.count,
                ptoDays: controller.ptoDays
            )
        case .weeks:
            TimeSummary.weeklySeries(
                sessions: controller.sessions,
                now: controller.now,
                limitMinutes: controller.settings.weeklyLimitMinutes,
                count: HistoryPeriod.weeks.count,
                ptoDays: controller.ptoDays,
                ptoDayMinutes: controller.settings.ptoDayMinutes,
                reducesLimitForPTO: controller.settings.ptoReducesWeeklyLimit
            )
        }
    }

    private var weeklyLimitCrossing: Date? {
        TimeSummary.weeklyLimitCrossing(
            sessions: controller.sessions,
            now: controller.now,
            limitMinutes: controller.weeklyLimit(for: controller.now)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    StatCard(title: "Today", total: today)
                    StatCard(title: "This week", total: thisWeek)
                }

                if let crossing = weeklyLimitCrossing {
                    HStack(spacing: 6) {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 8))
                        Text("Weekly limit reached \(crossing.formatted(.dateTime.weekday(.abbreviated).hour().minute()))")
                            .font(.system(size: 10))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(.red)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }

                TrendCard(
                    series: trendSeries,
                    period: trendPeriod,
                    selection: $trendPeriod
                )

                Spacer(minLength: 0)
            }
            .padding(14)

            footer
        }
        .frame(width: 400, height: 470)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(controller.isTracking ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.15))
                Image(systemName: controller.isTracking ? "clock.fill" : "pause.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(controller.isTracking ? Color.accentColor : Color.secondary)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text("Unlocked Time")
                    .font(.system(size: 13, weight: .semibold))
                Text(statusText)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                if controller.isTracking {
                    controller.stopSession()
                } else {
                    controller.startSession()
                }
            } label: {
                Image(systemName: controller.isTracking ? "pause.fill" : "play.fill")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 24, height: 24)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .background(.quaternary, in: Circle())
            .help(controller.isTracking ? "Pause tracking" : "Resume tracking")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var statusText: String {
        guard controller.isTracking, let start = controller.sessions.last(where: { $0.end == nil })?.start else {
            return controller.pausedByIdle ? "Paused while idle" : "Paused"
        }
        return "Since \(start.formatted(date: .omitted, time: .shortened))"
    }

    private var footer: some View {
        VStack(spacing: 0) {
            if let storageError = controller.storageError {
                Label(storageError, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
            }

            Divider()

            HStack {
                Button {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    openWindow(id: "history")
                } label: {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                Button {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    openSettings()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                Spacer()
                Button {
                    controller.stopSession()
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("Quit", systemImage: "power")
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
    }
}

private struct StatCard: View {
    let title: String
    let total: PeriodTotal

    private var progress: Double {
        min(Double(total.minutes) / Double(max(total.limitMinutes, 1)), 1)
    }

    private var detail: String {
        total.isOver
            ? "\(formatMinutes(total.overageMinutes)) over \(formatMinutes(total.limitMinutes))"
            : "\(formatMinutes(total.remainingMinutes)) left of \(formatMinutes(total.limitMinutes))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if total.isOver {
                    Text("OVER")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.red.opacity(0.16), in: Capsule())
                }
            }

            Text(formatMinutes(total.minutes))
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(total.isOver ? Color.red : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            ProgressView(value: progress)
                .tint(total.isOver ? Color.red : Color.accentColor)

            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct TrendCard: View {
    let series: [PeriodTotal]
    let period: HistoryPeriod
    @Binding var selection: HistoryPeriod
    var showsPicker = true
    var selectedStart: Date?
    var onSelect: ((Date) -> Void)?

    private var limitMinutes: Int { series.first?.limitMinutes ?? 0 }

    private var upperBound: Double {
        Double(max(series.map(\.minutes).max() ?? 0, limitMinutes)) * 1.18
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Trend")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if showsPicker {
                    Picker("Period", selection: $selection) {
                        ForEach(HistoryPeriod.allCases) { value in
                            Text(value.title).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(width: 124)
                }
            }

            Chart {
                ForEach(series) { total in
                    BarMark(
                        x: .value("Period", total.start, unit: period.chartUnit),
                        y: .value("Minutes", Double(total.minutes)),
                        width: .ratio(0.55)
                    )
                    .cornerRadius(3)
                    .foregroundStyle(barStyle(for: total))
                }

                RuleMark(y: .value("Limit", Double(limitMinutes)))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(Color.secondary.opacity(0.55))

                ForEach(series.filter { $0.isPTO && $0.minutes == 0 }) { total in
                    BarMark(
                        x: .value("Period", total.start, unit: period.chartUnit),
                        yStart: .value("From", 0.0),
                        yEnd: .value("To", max(upperBound, 60) * 0.04),
                        width: .ratio(0.55)
                    )
                    .cornerRadius(2)
                    .foregroundStyle(Color.secondary.opacity(0.45))
                }
            }
            .chartYScale(domain: 0...max(upperBound, 60))
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel {
                        if let minutes = value.as(Double.self) {
                            Text("\(Int(minutes) / 60)h")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: series.map(\.start)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(period.axisLabel(for: date))
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(height: 112)
            .chartOverlay { proxy in
                if onSelect != nil {
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .onTapGesture(coordinateSpace: .local) { location in
                                selectPeriod(at: location, proxy: proxy, geometry: geometry)
                            }
                    }
                }
            }

            Text(caption)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .padding(11)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }

    private var caption: String {
        let limit = "Dashed line marks the \(formatMinutes(limitMinutes)) \(period == .days ? "daily" : "weekly") limit."
        return series.contains(where: \.isPTO) ? limit + " Grey marks PTO." : limit
    }

    private func barStyle(for total: PeriodTotal) -> AnyShapeStyle {
        let base = total.isOver ? Color.red : Color.accentColor
        return AnyShapeStyle(base.opacity(isHighlighted(total) ? 1 : 0.4).gradient)
    }

    /// Matched by calendar period rather than exact instant, so a selection cannot miss by seconds.
    private func isHighlighted(_ total: PeriodTotal) -> Bool {
        guard let selectedStart else {
            return total.start == series.last?.start
        }
        return Calendar.current.isDate(
            total.start,
            equalTo: selectedStart,
            toGranularity: period == .days ? .day : .weekOfYear
        )
    }

    private func selectPeriod(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else { return }
        let x = location.x - geometry[plotFrame].origin.x
        guard let tapped: Date = proxy.value(atX: x) else { return }
        let nearest = series.min {
            abs($0.start.timeIntervalSince(tapped)) < abs($1.start.timeIntervalSince(tapped))
        }
        if let nearest {
            onSelect?(nearest.start)
        }
    }
}

struct IntervalRow: View {
    let interval: WorkInterval

    var body: some View {
        HStack(spacing: 8) {
            Text(interval.start.formatted(date: .omitted, time: .shortened))
                .monospacedDigit()
            Text("–")
                .foregroundStyle(.secondary)
            Text(interval.end.formatted(date: .omitted, time: .shortened))
                .monospacedDigit()

            Spacer()

            Text(formatMinutes(interval.minutes))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 11))
        .padding(.vertical, 6)
    }
}

struct HistoryRow: View {
    let total: PeriodTotal
    let period: HistoryPeriod
    let isCurrent: Bool
    var isSelected = false

    private var valueStyle: AnyShapeStyle {
        if total.minutes == 0 {
            return AnyShapeStyle(.tertiary)
        }
        return AnyShapeStyle(total.isOver ? Color.red : Color.primary)
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(period.label(for: total.start))
                .font(.system(size: 11, weight: isCurrent ? .semibold : .regular))
                .monospacedDigit()
                .lineLimit(1)

            if total.isPTO {
                Text("PTO")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
            }

            Spacer(minLength: 4)

            Text(formatMinutes(total.minutes))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(valueStyle)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(
            isSelected ? Color.accentColor.opacity(0.15) : Color.clear,
            in: RoundedRectangle(cornerRadius: 5)
        )
    }
}

enum HistoryPeriod: String, CaseIterable, Identifiable {
    case days
    case weeks

    var id: String { rawValue }
    var title: String { self == .days ? "Days" : "Weeks" }
    var historyTitle: String { self == .days ? "All days" : "All weeks" }
    var count: Int { self == .days ? 7 : 8 }
    var chartUnit: Calendar.Component { self == .days ? .day : .weekOfYear }

    func label(for date: Date) -> String {
        if self == .days {
            return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        }
        return "Week \(Calendar.current.component(.weekOfYear, from: date))"
    }

    func axisLabel(for date: Date) -> String {
        if self == .days {
            return date.formatted(.dateTime.day())
        }
        return "W\(Calendar.current.component(.weekOfYear, from: date))"
    }

    func ptoActionTitle(isPTO: Bool) -> String {
        switch (self, isPTO) {
        case (.days, false): "Mark as PTO"
        case (.days, true): "Clear PTO"
        case (.weeks, false): "Mark week as PTO"
        case (.weeks, true): "Clear PTO for week"
        }
    }
}

private struct LimitStepper: View {
    let title: String
    @Binding var minutes: Int
    let maxHours: Int

    private var hoursBinding: Binding<Int> {
        Binding(get: { minutes / 60 }, set: { minutes = $0 * 60 + minutes % 60 })
    }

    private var minutesBinding: Binding<Int> {
        Binding(get: { minutes % 60 }, set: { minutes = (minutes / 60) * 60 + $0 })
    }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 12) {
                Stepper(value: hoursBinding, in: 0...maxHours) {
                    Text("\(minutes / 60) h")
                        .monospacedDigit()
                }
                .fixedSize()

                Stepper(value: minutesBinding, in: 0...55, step: 5) {
                    Text(String(format: "%02d m", minutes % 60))
                        .monospacedDigit()
                }
                .fixedSize()
            }
        }
    }
}

private struct SettingsView: View {
    @ObservedObject var controller: TrackingController
    @State private var dailyLimitMinutes: Int
    @State private var weeklyLimitMinutes: Int
    @State private var isImporting = false
    @State private var importMessage: String?
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginItemError: String?
    @State private var pausesWhenIdle: Bool
    @State private var idleThresholdMinutes: Int
    @State private var ptoReducesWeeklyLimit: Bool
    @State private var ptoDayMinutes: Int

    init(controller: TrackingController) {
        self.controller = controller
        _dailyLimitMinutes = State(initialValue: controller.settings.dailyLimitMinutes)
        _weeklyLimitMinutes = State(initialValue: controller.settings.weeklyLimitMinutes)
        _pausesWhenIdle = State(initialValue: controller.settings.pausesWhenIdle)
        _idleThresholdMinutes = State(initialValue: controller.settings.idleThresholdMinutes)
        _ptoReducesWeeklyLimit = State(initialValue: controller.settings.ptoReducesWeeklyLimit)
        _ptoDayMinutes = State(initialValue: controller.settings.ptoDayMinutes)
    }

    var body: some View {
        Form {
            Section("Limits") {
                LimitStepper(title: "Daily maximum", minutes: $dailyLimitMinutes, maxHours: 24)
                LimitStepper(title: "Weekly maximum", minutes: $weeklyLimitMinutes, maxHours: 7 * 24)
                Toggle("PTO reduces weekly maximum", isOn: $ptoReducesWeeklyLimit)
                LimitStepper(title: "PTO day value", minutes: $ptoDayMinutes, maxHours: 24)
                    .disabled(!ptoReducesWeeklyLimit)
            }

            Section("Tracking") {
                Toggle("Pause when idle", isOn: $pausesWhenIdle)
                Stepper(value: $idleThresholdMinutes, in: 1...120, step: 1) {
                    LabeledContent("Idle after", value: "\(idleThresholdMinutes) min")
                }
                .disabled(!pausesWhenIdle)
            }

            Section("Startup") {
                Toggle("Start at login", isOn: $launchAtLogin)
                if let loginItemError {
                    Text(loginItemError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("History") {
                Button {
                    isImporting = true
                } label: {
                    Label("Import work log", systemImage: "square.and.arrow.down")
                }
                if let importMessage {
                    Text(importMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Text("Time is stored only on this Mac. Tracking stops when the screen locks, sleeps, or the user session becomes inactive.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 540)
        .onChange(of: dailyLimitMinutes) { _, _ in save() }
        .onChange(of: weeklyLimitMinutes) { _, _ in save() }
        .onChange(of: pausesWhenIdle) { _, _ in save() }
        .onChange(of: idleThresholdMinutes) { _, _ in save() }
        .onChange(of: ptoReducesWeeklyLimit) { _, _ in save() }
        .onChange(of: ptoDayMinutes) { _, _ in save() }
        .onChange(of: launchAtLogin) { _, isOn in
            do {
                try LoginItem.setEnabled(isOn)
                loginItemError = nil
            } catch {
                loginItemError = error.localizedDescription
                launchAtLogin = LoginItem.isEnabled
            }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.plainText]) { result in
            do {
                let url = try result.get()
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                let imported = try controller.importFile(at: url)
                importMessage = "Imported \(imported.importedCount); skipped \(imported.skippedCount) duplicates."
            } catch {
                importMessage = error.localizedDescription
            }
        }
    }

    private func save() {
        controller.updateSettings(
            dailyLimitMinutes: dailyLimitMinutes,
            weeklyLimitMinutes: weeklyLimitMinutes,
            pausesWhenIdle: pausesWhenIdle,
            idleThresholdMinutes: idleThresholdMinutes,
            ptoReducesWeeklyLimit: ptoReducesWeeklyLimit,
            ptoDayMinutes: ptoDayMinutes
        )
    }
}