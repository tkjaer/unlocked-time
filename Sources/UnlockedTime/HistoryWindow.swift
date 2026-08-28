import SwiftUI

struct HistoryWindowView: View {
    @ObservedObject var controller: TrackingController
    @State private var period = HistoryPeriod.days
    @State private var selectedWeek: Date?
    @State private var selectedDay: Date? = Calendar.current.startOfDay(for: Date())

    private let columnHeight: CGFloat = 336

    private var calendar: Calendar { .current }

    private var earliest: Date? {
        let firstSession = controller.sessions.map(\.start).min()
        let firstPTO = controller.ptoDays.compactMap { TimeSummary.date(fromDayKey: $0) }.min()
        return [firstSession, firstPTO].compactMap { $0 }.min()
    }

    /// The list covers everything recorded, not just the charted window.
    private var historyCount: Int {
        guard let earliest else { return period.count }
        switch period {
        case .days:
            let days = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: earliest),
                to: calendar.startOfDay(for: controller.now)
            ).day ?? 0
            return min(max(days + 1, period.count), 3660)
        case .weeks:
            guard
                let from = calendar.dateInterval(of: .weekOfYear, for: earliest)?.start,
                let to = calendar.dateInterval(of: .weekOfYear, for: controller.now)?.start
            else { return period.count }
            let weeks = calendar.dateComponents([.weekOfYear], from: from, to: to).weekOfYear ?? 0
            return min(max(weeks + 1, period.count), 520)
        }
    }

    private var topSeries: [PeriodTotal] {
        switch period {
        case .days:
            TimeSummary.dailySeries(
                sessions: controller.sessions,
                now: controller.now,
                limitMinutes: controller.settings.dailyLimitMinutes,
                count: historyCount,
                ptoDays: controller.ptoDays
            )
        case .weeks:
            TimeSummary.weeklySeries(
                sessions: controller.sessions,
                now: controller.now,
                limitMinutes: controller.settings.weeklyLimitMinutes,
                count: historyCount,
                ptoDays: controller.ptoDays,
                ptoDayMinutes: controller.settings.ptoDayMinutes,
                reducesLimitForPTO: controller.settings.ptoReducesWeeklyLimit
            )
        }
    }

    /// Keeps the charted window anchored on the selection so it stays visible.
    private var chartSeries: [PeriodTotal] {
        let window = period.count
        let selected = period == .weeks ? weekStart : selectedDay
        let granularity: Calendar.Component = period == .days ? .day : .weekOfYear

        guard
            let selected,
            let index = topSeries.lastIndex(where: {
                calendar.isDate($0.start, equalTo: selected, toGranularity: granularity)
            })
        else {
            return Array(topSeries.suffix(window))
        }

        let end = index + 1
        return Array(topSeries[max(0, end - window)..<end])
    }

    private var weekStart: Date? {
        selectedWeek ?? calendar.dateInterval(of: .weekOfYear, for: controller.now)?.start
    }

    private var weekDays: [PeriodTotal] {
        guard let weekStart else { return [] }
        return TimeSummary.daysInWeek(
            sessions: controller.sessions,
            weekStart: weekStart,
            now: controller.now,
            limitMinutes: controller.settings.dailyLimitMinutes,
            ptoDays: controller.ptoDays
        )
    }

    private var intervals: [WorkInterval] {
        guard let selectedDay else { return [] }
        return TimeSummary.intervals(
            sessions: controller.sessions,
            on: selectedDay,
            now: controller.now
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            VStack(spacing: 12) {
                TrendCard(
                    series: chartSeries,
                    period: period,
                    selection: $period,
                    showsPicker: false,
                    selectedStart: period == .weeks ? weekStart : selectedDay,
                    onSelect: selectFromChart
                )

                HStack(alignment: .top, spacing: 12) {
                    if period == .weeks {
                        periodColumn(
                            title: HistoryPeriod.weeks.historyTitle,
                            total: nil,
                            rows: topSeries.reversed(),
                            rowPeriod: .weeks,
                            width: 230,
                            isSelected: { row in
                                weekStart.map { calendar.isDate(row.start, inSameDayAs: $0) } ?? false
                            },
                            onSelect: { row in
                                selectedWeek = row.start
                                selectedDay = nil
                            }
                        )

                        periodColumn(
                            title: weekStart.map { HistoryPeriod.weeks.label(for: $0) } ?? "Days",
                            total: weekDays.reduce(0) { $0 + $1.minutes },
                            rows: weekDays,
                            rowPeriod: .days,
                            width: 330,
                            isSelected: isSelectedDay,
                            onSelect: { selectedDay = $0.start }
                        )
                    } else {
                        periodColumn(
                            title: HistoryPeriod.days.historyTitle,
                            total: topSeries.reduce(0) { $0 + $1.minutes },
                            rows: topSeries.reversed(),
                            rowPeriod: .days,
                            width: 572,
                            isSelected: isSelectedDay,
                            onSelect: { selectedDay = $0.start }
                        )
                    }

                    sessionsColumn
                }
            }
            .padding(16)
        }
        .frame(width: 880, height: 640)
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("History")
                    .font(.system(size: 15, weight: .semibold))
                Text("Click a week to see its days, then a day to see its sessions.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("Period", selection: $period) {
                ForEach(HistoryPeriod.allCases) { value in
                    Text(value.title).tag(value)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 150)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var sessionsColumn: some View {
        HistoryColumn(
            title: selectedDay.map { HistoryPeriod.days.label(for: $0) } ?? "Sessions",
            total: selectedDay == nil ? nil : intervals.reduce(0) { $0 + $1.minutes },
            width: 264,
            height: columnHeight
        ) {
            if selectedDay == nil {
                columnHint("Select a day to see its sessions.")
            } else if intervals.isEmpty {
                columnHint("No tracked time on this day.")
            } else {
                ForEach(intervals) { interval in
                    IntervalRow(interval: interval)
                    if interval.id != intervals.last?.id {
                        Divider().opacity(0.3)
                    }
                }
            }
        }
    }

    private func periodColumn(
        title: String,
        total: Int?,
        rows: [PeriodTotal],
        rowPeriod: HistoryPeriod,
        width: CGFloat,
        isSelected: @escaping (PeriodTotal) -> Bool,
        onSelect: @escaping (PeriodTotal) -> Void
    ) -> some View {
        HistoryColumn(title: title, total: total, width: width, height: columnHeight) {
            if rows.isEmpty {
                columnHint("Nothing to show yet.")
            } else {
                ForEach(rows) { row in
                    HistoryRow(
                        total: row,
                        period: rowPeriod,
                        isCurrent: isCurrent(row, period: rowPeriod),
                        isSelected: isSelected(row)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect(row) }
                    .contextMenu {
                        Button(rowPeriod.ptoActionTitle(isPTO: row.isPTO)) {
                            if rowPeriod == .weeks {
                                controller.setPTO(!row.isPTO, forWeekContaining: row.start)
                            } else {
                                controller.setPTO(!row.isPTO, forDay: row.start)
                            }
                        }
                    }
                }
            }
        }
    }

    private func columnHint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }

    private func selectFromChart(_ start: Date) {
        switch period {
        case .weeks:
            selectedWeek = start
            selectedDay = nil
        case .days:
            selectedDay = start
        }
    }

    private func isSelectedDay(_ row: PeriodTotal) -> Bool {
        guard let selectedDay else { return false }
        return calendar.isDate(row.start, inSameDayAs: selectedDay)
    }

    private func isCurrent(_ row: PeriodTotal, period: HistoryPeriod) -> Bool {
        switch period {
        case .days: calendar.isDate(row.start, inSameDayAs: controller.now)
        case .weeks: calendar.isDate(row.start, equalTo: controller.now, toGranularity: .weekOfYear)
        }
    }
}

private struct HistoryColumn<Content: View>: View {
    let title: String
    var total: Int?
    let width: CGFloat
    let height: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)

                Spacer(minLength: 6)

                if let total {
                    Text(formatMinutes(total))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 11)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    content
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 4)
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }
}
