import Charts
import SwiftUI

/// Gridlines on whole hours. Charts' automatic ticks are round in minutes, which put lines at
/// odd times such as 16h 40m.
enum HourAxis {
    static let steps = [1, 2, 4, 5, 10, 20, 25, 50, 100, 200, 500]

    /// Tick positions in minutes, from zero up to `upperMinutes`, with at most `maxTicks` above zero.
    static func ticks(upTo upperMinutes: Double, maxTicks: Int = 3) -> [Double] {
        let hours = upperMinutes / 60
        let step = steps.first { hours / Double($0) < Double(maxTicks + 1) } ?? steps.last!
        return stride(from: 0, through: upperMinutes, by: Double(step * 60)).map { $0 }
    }
}

struct ChartZoom: Equatable, Sendable {
    let count: Int
    let title: String
}

extension HistoryPeriod {
    private var zoomPresets: [ChartZoom] {
        switch self {
        case .days:
            [
                ChartZoom(count: 7, title: "1 week"),
                ChartZoom(count: 14, title: "2 weeks"),
                ChartZoom(count: 30, title: "1 month"),
                ChartZoom(count: 91, title: "3 months"),
                ChartZoom(count: 182, title: "6 months"),
                ChartZoom(count: 365, title: "1 year")
            ]
        case .weeks:
            [
                ChartZoom(count: 8, title: "8 weeks"),
                ChartZoom(count: 13, title: "3 months"),
                ChartZoom(count: 26, title: "6 months"),
                ChartZoom(count: 52, title: "1 year"),
                ChartZoom(count: 104, title: "2 years"),
                ChartZoom(count: 260, title: "5 years"),
                ChartZoom(count: 520, title: "10 years")
            ]
        }
    }

    /// Closest first. The widest step shows all of `available`, up to a year of days or ten
    /// years of weeks, where bars are already about two points wide. Older history is reached by
    /// scrolling.
    func zoomLevels(available: Int) -> [ChartZoom] {
        let presets = zoomPresets
        var levels = presets.filter { $0.count < available }
        guard !levels.isEmpty else { return [presets[0]] }

        if let widest = presets.last, available > widest.count {
            return levels
        }
        let title = presets.first { $0.count == available }?.title ?? "All"
        levels.append(ChartZoom(count: available, title: title))
        return levels
    }

    /// Periods in the trailing average drawn when zoomed out.
    var averageWindow: Int { self == .days ? 7 : 4 }

    func includesInAverage(_ total: PeriodTotal, calendar: Calendar = .current) -> Bool {
        self == .weeks || (!calendar.isDateInWeekend(total.start) && !total.isPTO)
    }
}

/// The visible slice of a scrollable chart, as calendar periods rather than raw seconds.
struct ChartWindow {
    let series: [PeriodTotal]
    let period: HistoryPeriod
    let length: Int
    var calendar = Calendar.current

    var unit: Calendar.Component { period.chartUnit }
    var unitSeconds: TimeInterval { period == .days ? 86_400 : 604_800 }
    var visibleSeconds: TimeInterval { Double(length) * unitSeconds }

    var domain: ClosedRange<Date> {
        guard let first = series.first, let last = series.last else {
            let now = Date()
            return now...now
        }
        return first.start...add(1, to: last.start)
    }

    func add(_ periods: Int, to date: Date) -> Date {
        calendar.date(byAdding: unit, value: periods, to: date)!
    }

    func periodStart(for date: Date) -> Date {
        switch period {
        case .days: calendar.startOfDay(for: date)
        case .weeks: calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        }
    }

    /// Leading edge that keeps the window inside the data.
    func clamp(_ start: Date) -> Date {
        let lower = domain.lowerBound
        let upper = max(lower, add(-length, to: domain.upperBound))
        return min(max(start, lower), upper)
    }

    /// A period counts as shown once its middle is on screen, so a half-scrolled bar counts once.
    func isVisible(_ date: Date, from start: Date) -> Bool {
        let middle = periodStart(for: date).addingTimeInterval(unitSeconds / 2)
        return middle >= start && middle < add(length, to: start)
    }

    func visible(from start: Date) -> [PeriodTotal] {
        // Series entries already start their period, so plain comparisons do; this runs per bar.
        let end = add(length, to: start)
        return series.filter {
            let middle = $0.start.addingTimeInterval(unitSeconds / 2)
            return middle >= start && middle < end
        }
    }

    /// The periods worth drawing: the visible ones plus a window either side, so scrolling never
    /// reaches an undrawn bar however long the history is.
    func rendered(around start: Date) -> [PeriodTotal] {
        let from = add(-length, to: start)
        let to = add(2 * length, to: start)
        return series.filter { $0.start >= from && $0.start < to }
    }

    /// The latest periods, or the selection as the rightmost bar when it is older than that.
    func initialStart(showing selection: Date?) -> Date {
        let latest = clamp(add(-length, to: domain.upperBound))
        guard let selection else { return latest }
        return start(showing: selection, from: latest)
    }

    /// Leaves the window alone when `date` is already shown, otherwise ends the window on it.
    func start(showing date: Date, from current: Date) -> Date {
        guard !isVisible(date, from: current) else { return current }
        return clamp(add(-(length - 1), to: periodStart(for: date)))
    }

    /// Keeps the anchor at the same relative position when it is on screen, otherwise keeps the
    /// right edge, so zooming out from the present stays on the present.
    func start(zoomingFrom current: Date, oldLength: Int, anchor: Date?) -> Date {
        let old = ChartWindow(series: series, period: period, length: oldLength, calendar: calendar)
        let current = periodStart(for: current.addingTimeInterval(unitSeconds / 2))

        if let anchor, old.isVisible(anchor, from: current) {
            let anchorStart = periodStart(for: anchor)
            let offset = periods(from: current, to: anchorStart)
            let fraction = Double(offset) / Double(max(oldLength, 1))
            let newOffset = Int(fraction * Double(length))
            return clamp(add(-newOffset, to: anchorStart))
        }

        return clamp(add(-length, to: old.add(oldLength, to: current)))
    }

    /// Where a scroll comes to rest, in points from the leading edge of the scrolled content:
    /// the nearest period start, or the very end when that is nearer, so the latest period is
    /// always reachable. Works from the domain rather than from the chart's own value lookup,
    /// which can be a hair short of a period start at the end, or still use the previous
    /// period's scale just after switching between days and weeks.
    func restingOffset(proposed: Double, contentWidth: Double, containerWidth: Double) -> Double {
        let maxOffset = max(0, contentWidth - containerWidth)
        let span = domain.upperBound.timeIntervalSince(domain.lowerBound)
        guard contentWidth > 0, span > 0 else { return 0 }

        let pointsPerSecond = contentWidth / span
        let proposed = min(max(proposed, 0), maxOffset)
        let date = domain.lowerBound.addingTimeInterval(proposed / pointsPerSecond)
        let start = periodStart(for: date)

        let candidates = [start, add(1, to: start)]
            .map { $0.timeIntervalSince(domain.lowerBound) * pointsPerSecond }
            .filter { $0 >= 0 && $0 < maxOffset } + [0, maxOffset]
        return candidates.min { abs($0 - proposed) < abs($1 - proposed) } ?? 0
    }

    private func periods(from start: Date, to end: Date) -> Int {
        switch period {
        case .days: calendar.dateComponents([.day], from: start, to: end).day ?? 0
        case .weeks: calendar.dateComponents([.weekOfYear], from: start, to: end).weekOfYear ?? 0
        }
    }
}

/// Snaps scrolling to whole days or weeks, using `ChartWindow.restingOffset`.
struct PeriodScrollTargetBehavior: ChartScrollTargetBehavior {
    let window: ChartWindow

    func updateTarget(_ target: inout ScrollTarget, context: ChartScrollTargetBehaviorContext) {
        target.rect.origin.x = window.restingOffset(
            proposed: target.rect.origin.x,
            contentWidth: context.contentSize.width,
            containerWidth: context.containerSize.width
        )
    }
}

/// The History window's trend card: a chart that scrolls through all history and zooms between
/// fixed spans, or a calendar of a year of days.
struct HistoryChart: View {
    let series: [PeriodTotal]
    /// The daily series, in Weeks mode too. Only needed, and only built, for the calendar.
    let days: [PeriodTotal]
    let period: HistoryPeriod
    let ptoDays: Set<String>
    var selectedStart: Date?
    @Binding var style: TrendStyle
    var onSelect: (Date) -> Void

    @State private var zoomSteps: [HistoryPeriod: Int] = [:]
    @State private var scrollStart: Date
    @State private var tapped: Date?
    @State private var pinchBase: CGFloat = 1
    @State private var yearsBack = 0

    private var calendar: Calendar { .current }

    init(
        series: [PeriodTotal],
        days: [PeriodTotal],
        period: HistoryPeriod,
        ptoDays: Set<String>,
        selectedStart: Date?,
        style: Binding<TrendStyle>,
        onSelect: @escaping (Date) -> Void
    ) {
        self.series = series
        self.days = days
        self.period = period
        self.ptoDays = ptoDays
        self.selectedStart = selectedStart
        _style = style
        self.onSelect = onSelect

        let length = period.zoomLevels(available: series.count)[0].count
        let window = ChartWindow(series: series, period: period, length: length)
        _scrollStart = State(initialValue: window.initialStart(showing: selectedStart))
    }

    private var levels: [ChartZoom] { period.zoomLevels(available: series.count) }
    private var zoomIndex: Int { min(zoomSteps[period] ?? 0, levels.count - 1) }
    private var zoom: ChartZoom { levels[zoomIndex] }
    private var window: ChartWindow { ChartWindow(series: series, period: period, length: zoom.count) }
    private var visible: [PeriodTotal] { window.visible(from: scrollStart) }
    private var showsAverage: Bool { zoom.count > 20 }
    private var inProgress: Date? { series.last?.start }

    /// PTO only lowers a weekly limit, so the highest one is the usual limit.
    private var limitMinutes: Int { series.map(\.limitMinutes).max() ?? 0 }

    /// Fixed across scrolling and zooming, so the height of a bar always means the same.
    private var upperBound: Double {
        max(Double(max(series.map(\.minutes).max() ?? 0, limitMinutes)) * 1.18, 60)
    }

    private var rendered: [PeriodTotal] { window.rendered(around: scrollStart) }

    /// Worked out from the periods just before the drawn ones too, so the line starts correct.
    private var averages: [PeriodAverage] {
        guard showsAverage, let first = rendered.first, let last = rendered.last else { return [] }
        let from = window.add(-period.averageWindow, to: first.start)
        let source = series.dropLast().filter { $0.start >= from && $0.start <= last.start }
        return TimeSummary.rollingAverage(Array(source), window: period.averageWindow) {
            period.includesInAverage($0, calendar: calendar)
        }
        .filter { $0.start >= first.start }
    }

    // The calendar always shows days, so its summary is of days in Weeks mode too.
    private var isCalendar: Bool { style == .calendar }
    private var summaryPeriod: HistoryPeriod { isCalendar ? .days : period }

    private var today: Date { days.last?.start ?? calendar.startOfDay(for: Date()) }

    private var oldestYearsBack: Int {
        days.first.map { HeatmapYear.yearsBack(containing: $0.start, today: today, calendar: calendar) } ?? 0
    }

    private var heatmapYear: HeatmapYear {
        HeatmapYear.ending(today, yearsBack: min(max(yearsBack, 0), oldestYearsBack), calendar: calendar)
    }

    private var summary: RangeSummary {
        let totals = isCalendar ? Array(heatmapYear.days(in: days, calendar: calendar)) : visible
        return TimeSummary.rangeSummary(totals, inProgress: isCalendar ? days.last?.start : inProgress) {
            summaryPeriod.includesInAverage($0, calendar: calendar)
        }
    }

    private var visiblePTODays: Int {
        if isCalendar {
            let year = heatmapYear
            let end = calendar.date(byAdding: .day, value: 1, to: year.end) ?? year.end
            return TimeSummary.ptoDayCount(ptoDays, from: year.start, to: end)
        }
        guard let first = visible.first, let last = visible.last else { return 0 }
        return TimeSummary.ptoDayCount(ptoDays, from: first.start, to: window.add(1, to: last.start))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if isCalendar {
                CalendarHeatmap(
                    layout: HeatmapLayout(days: days, year: heatmapYear, calendar: calendar),
                    period: period,
                    selectedStart: selectedStart,
                    onSelect: onSelect
                )
                .frame(height: 112)
            } else {
                chart
            }
            summaryRow

            HStack {
                if isCalendar {
                    HeatmapLegend(limitMinutes: days.last?.limitMinutes ?? 0)
                    Spacer(minLength: 8)
                    Text(period == .days ? "Click a day to select it." : "Click a day to select its week.")
                } else {
                    Text(caption)
                    Spacer(minLength: 8)
                    Text("Scroll to go back. Pinch or press ⌘+ and ⌘− to zoom.")
                }
            }
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
        }
        .padding(11)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
        .onChange(of: selectedStart) { _, selection in
            guard let selection else { return }
            scrollStart = window.start(showing: selection, from: scrollStart)
            if isCalendar {
                yearsBack = yearsBack(showing: selection)
            }
        }
        .onChange(of: style) { _, style in
            guard style == .calendar else { return }
            yearsBack = selectedStart.map(yearsBack(showing:)) ?? 0
        }
        .onChange(of: period) {
            scrollStart = window.initialStart(showing: selectedStart)
        }
        .onChange(of: tapped) { _, date in
            guard let date else { return }
            tapped = nil
            if let match = series.first(where: {
                calendar.isDate($0.start, equalTo: date, toGranularity: period.chartUnit)
            }) {
                onSelect(match.start)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Trend")
                .font(.system(size: 12, weight: .semibold))
            Text(rangeText)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            Spacer()

            if isCalendar {
                yearControls
            } else {
                zoomControls
            }

            Picker("Style", selection: $style) {
                ForEach(TrendStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 130)
            .help("Show the trend as a chart or as a calendar of days")
        }
    }

    private var yearControls: some View {
        HStack(spacing: 2) {
            Button {
                yearsBack = heatmapYear.yearsBack + 1
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(heatmapYear.yearsBack >= oldestYearsBack)
            .help("Previous year")

            Text(heatmapYear.title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(minWidth: 56)

            Button {
                yearsBack = heatmapYear.yearsBack - 1
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(heatmapYear.yearsBack == 0)
            .help("Next year")
        }
        .buttonStyle(.borderless)
    }

    private var zoomControls: some View {
        HStack(spacing: 2) {
            Button(action: zoomOut) {
                Image(systemName: "minus.magnifyingglass")
            }
            .disabled(zoomIndex == levels.count - 1)
            .keyboardShortcut("-", modifiers: .command)
            .help("Zoom out (⌘−)")

            Text(zoom.title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(minWidth: 56)

            Button(action: zoomIn) {
                Image(systemName: "plus.magnifyingglass")
            }
            .disabled(zoomIndex == 0)
            .keyboardShortcut("+", modifiers: .command)
            .help("Zoom in (⌘+)")
        }
        .buttonStyle(.borderless)
        // ⌘+ is ⌘= without Shift on layouts such as US English.
        .background {
            Button("", action: zoomIn)
                .keyboardShortcut("=", modifiers: .command)
                .disabled(zoomIndex == 0)
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var chart: some View {
        Chart {
            ForEach(rendered) { total in
                BarMark(
                    x: .value("Period", total.start, unit: window.unit),
                    y: .value("Minutes", Double(total.minutes)),
                    width: .ratio(0.55)
                )
                .cornerRadius(zoom.count > 60 ? 1 : 3)
                .foregroundStyle(barStyle(for: total))
            }

            RuleMark(y: .value("Limit", Double(limitMinutes)))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(Color.secondary.opacity(0.55))

            ForEach(rendered.filter { $0.isPTO && $0.minutes == 0 }) { total in
                BarMark(
                    x: .value("Period", total.start, unit: window.unit),
                    yStart: .value("From", 0.0),
                    yEnd: .value("To", upperBound * 0.04),
                    width: .ratio(0.55)
                )
                .cornerRadius(zoom.count > 60 ? 1 : 2)
                .foregroundStyle(Color.secondary.opacity(0.45))
            }

            ForEach(averages) { point in
                LineMark(
                    x: .value("Period", point.start, unit: window.unit),
                    y: .value("Average", Double(point.minutes)),
                    series: .value("Series", "Average")
                )
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                .foregroundStyle(Color.primary.opacity(0.6))
            }
        }
        .chartXScale(domain: window.domain)
        .chartYScale(domain: 0...upperBound)
        .chartScrollableAxes(.horizontal)
        .chartXVisibleDomain(length: window.visibleSeconds)
        .chartScrollPosition(x: $scrollStart)
        .chartScrollTargetBehavior(PeriodScrollTargetBehavior(window: window))
        .chartYAxis {
            AxisMarks(position: .leading, values: HourAxis.ticks(upTo: upperBound)) { value in
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
            AxisMarks(values: .stride(by: axis.component, count: axis.count)) { value in
                AxisValueLabel(centered: axis.isCentered) {
                    if let date = value.as(Date.self) {
                        Text(axisLabel(for: date))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartXSelection(value: $tapped)
        .chartGesture { proxy in
            SpatialTapGesture().onEnded { value in
                proxy.selectXValue(at: value.location.x)
            }
        }
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    let ratio = value.magnification / pinchBase
                    if ratio > 1.25 {
                        zoomIn()
                        pinchBase = value.magnification
                    } else if ratio < 0.8 {
                        zoomOut()
                        pinchBase = value.magnification
                    }
                }
                .onEnded { _ in pinchBase = 1 }
        )
        .frame(height: 112)
    }

    private var summaryRow: some View {
        HStack(spacing: 18) {
            stat("Total", formatMinutes(summary.totalMinutes))
            stat(summaryPeriod == .days ? "Average day" : "Average week", formatMinutes(summary.averageMinutes))
                .help(
                    summaryPeriod == .days
                        ? "Average of the workdays in view with tracked time, leaving out weekends, PTO and today."
                        : "Average of the weeks in view with tracked time, leaving out the current one."
                )
            stat(
                "Over limit",
                "\(summary.periodsOver) of \(summary.periodCount)",
                isAlert: summary.periodsOver > 0
            )
            .help(
                summaryPeriod == .days
                    ? "Completed workdays over the limit, leaving out weekends, PTO and today."
                    : "Completed weeks with tracked time over the limit, leaving out the current week."
            )
            stat("Overage", formatMinutes(summary.overageMinutes), isAlert: summary.overageMinutes > 0)
            stat("PTO", visiblePTODays == 1 ? "1 day" : "\(visiblePTODays) days")
            Spacer(minLength: 0)
        }
    }

    private func stat(_ label: String, _ value: String, isAlert: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(isAlert ? Color.red : Color.primary)
        }
    }

    private var caption: String {
        let unit = period == .days ? "day" : "week"
        var parts = ["Dashed line marks the \(formatMinutes(limitMinutes)) \(period == .days ? "daily" : "weekly") limit."]
        if visible.contains(where: \.isPTO) {
            parts.append("Grey marks PTO.")
        }
        if showsAverage {
            let subject = period == .days ? "workdays" : "weeks"
            parts.append("The line is a \(period.averageWindow)-\(unit) average of \(subject) with tracked time.")
        }
        return parts.joined(separator: " ")
    }

    private var rangeText: String {
        if isCalendar {
            let year = heatmapYear
            return (year.start..<year.end).formatted(.interval.day().month(.abbreviated).year())
        }
        guard let first = visible.first, let last = visible.last else { return "" }
        let end = calendar.date(byAdding: .day, value: -1, to: window.add(1, to: last.start)) ?? last.start
        return (first.start..<max(end, first.start)).formatted(
            .interval.day().month(.abbreviated).year()
        )
    }

    private var axis: (component: Calendar.Component, count: Int, isCentered: Bool, style: AxisStyle) {
        let days = zoom.count * (period == .days ? 1 : 7)
        switch (period, days) {
        case (.days, ...14): return (.day, 1, true, .dayNumber)
        case (.days, ...31): return (.weekOfYear, 1, false, .dayAndMonth)
        case (.days, ...91): return (.weekOfYear, 2, false, .dayAndMonth)
        case (.weeks, ...91): return (.weekOfYear, 1, true, .week)
        default:
            let months = Double(days) / 30.4
            let count = [1, 2, 3, 6, 12].first { months / Double($0) <= 12 } ?? 12
            return (.month, count, false, .month)
        }
    }

    private enum AxisStyle {
        case dayNumber, dayAndMonth, week, month
    }

    private func axisLabel(for date: Date) -> String {
        switch axis.style {
        case .dayNumber:
            date.formatted(.dateTime.day())
        case .dayAndMonth:
            date.formatted(.dateTime.day().month(.abbreviated))
        case .week:
            "W\(calendar.component(.weekOfYear, from: date))"
        case .month:
            calendar.component(.month, from: date) == 1
                ? date.formatted(.dateTime.year())
                : date.formatted(.dateTime.month(.abbreviated))
        }
    }

    private func barStyle(for total: PeriodTotal) -> AnyShapeStyle {
        let base = total.isOver ? Color.red : Color.accentColor
        return AnyShapeStyle(base.opacity(isHighlighted(total) ? 1 : 0.4).gradient)
    }

    /// Matched by calendar period rather than exact instant, so a selection cannot miss by seconds.
    private func isHighlighted(_ total: PeriodTotal) -> Bool {
        guard let selectedStart else { return total.start == series.last?.start }
        return calendar.isDate(total.start, equalTo: selectedStart, toGranularity: period.chartUnit)
    }

    /// Keeps the year when it already shows the selected day or any day of the selected week.
    private func yearsBack(showing selection: Date) -> Int {
        let first = calendar.startOfDay(for: selection)
        let last = period == .weeks ? calendar.date(byAdding: .day, value: 6, to: first) ?? first : first
        let year = heatmapYear
        if year.overlaps(first, through: last) { return year.yearsBack }
        return HeatmapYear.yearsBack(containing: min(last, today), today: today, calendar: calendar)
    }

    private func zoomIn() { setZoom(zoomIndex - 1) }
    private func zoomOut() { setZoom(zoomIndex + 1) }

    private func setZoom(_ index: Int) {
        let index = min(max(index, 0), levels.count - 1)
        guard index != zoomIndex else { return }
        let next = ChartWindow(series: series, period: period, length: levels[index].count)
        scrollStart = next.start(zoomingFrom: scrollStart, oldLength: zoom.count, anchor: selectedStart)
        zoomSteps[period] = index
    }
}
