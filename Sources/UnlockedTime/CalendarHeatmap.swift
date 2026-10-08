import SwiftUI

enum TrendStyle: String, CaseIterable, Identifiable {
    case chart
    case calendar

    var id: String { rawValue }
    var title: String { self == .chart ? "Chart" : "Calendar" }
}

/// Twelve months of days ending on `end`. Years step back from today a whole year at a time, so
/// they never overlap and every recorded day falls in exactly one.
struct HeatmapYear: Equatable {
    let start: Date
    let end: Date
    let yearsBack: Int

    static func ending(_ today: Date, yearsBack: Int, calendar: Calendar = .current) -> HeatmapYear {
        let today = calendar.startOfDay(for: today)
        let end = calendar.date(byAdding: .year, value: -yearsBack, to: today)!
        let yearBefore = calendar.date(byAdding: .year, value: -(yearsBack + 1), to: today)!
        let start = calendar.date(byAdding: .day, value: 1, to: yearBefore)!
        return HeatmapYear(start: start, end: end, yearsBack: yearsBack)
    }

    /// How many years back from today the year holding `date` is. Dates after today count as today.
    static func yearsBack(containing date: Date, today: Date, calendar: Calendar = .current) -> Int {
        let day = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: today)
        guard day < today else { return 0 }

        let whole = calendar.dateComponents([.year], from: day, to: today).year ?? 0
        var candidate = max(0, whole - 1)
        while !ending(today, yearsBack: candidate, calendar: calendar).contains(day) {
            candidate += 1
        }
        return candidate
    }

    func dayCount(calendar: Calendar) -> Int { Self.days(from: start, to: end, calendar: calendar) + 1 }

    func contains(_ date: Date) -> Bool { date >= start && date <= end }

    /// True when any day from `first` through `last` is in the year.
    func overlaps(_ first: Date, through last: Date) -> Bool { first <= end && last >= start }

    /// The year's days in a continuous daily series, found by position rather than by search.
    func days(in series: [PeriodTotal], calendar: Calendar = .current) -> ArraySlice<PeriodTotal> {
        guard let first = series.first else { return [] }
        let offset = Self.days(from: first.start, to: start, calendar: calendar)
        let lower = min(max(offset, 0), series.count)
        let upper = min(max(offset + dayCount(calendar: calendar), 0), series.count)
        return series[lower..<upper]
    }

    var title: String {
        guard yearsBack > 0 else { return "Past year" }
        let calendar = Calendar.current
        let first = calendar.component(.year, from: start)
        let last = calendar.component(.year, from: end)
        return first == last ? "\(first)" : "\(first)–\(String(format: "%02d", last % 100))"
    }

    static func days(from start: Date, to end: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }
}

/// Where each day of a heatmap year sits: one column per week, one row per weekday, with the
/// week starting on the calendar's first weekday.
struct HeatmapLayout {
    struct Cell: Equatable {
        let date: Date
        let total: PeriodTotal?
        let column: Int
        let row: Int
    }

    struct MonthLabel: Equatable {
        let column: Int
        let date: Date
    }

    let year: HeatmapYear
    let cells: [Cell]
    let columns: Int
    /// Blank cells before the year's first day in the first column.
    let leading: Int
    let months: [MonthLabel]
    private let gridStart: Date
    private let calendar: Calendar

    init(days series: [PeriodTotal], year: HeatmapYear, calendar: Calendar = .current) {
        self.year = year
        self.calendar = calendar

        let leading = (calendar.component(.weekday, from: year.start) - calendar.firstWeekday + 7) % 7
        let count = year.dayCount(calendar: calendar)
        self.leading = leading
        columns = (leading + count + 6) / 7
        gridStart = calendar.date(byAdding: .day, value: -leading, to: year.start)!

        // Series days already carry their dates, so only days outside the recorded history
        // need calendar maths.
        let slice = year.days(in: series, calendar: calendar)
        let sliceOffset = slice.first.map { HeatmapYear.days(from: year.start, to: $0.start, calendar: calendar) } ?? 0
        cells = (0..<count).map { index in
            let position = leading + index
            let sliceIndex = index - sliceOffset
            let total = sliceIndex >= 0 && sliceIndex < slice.count
                ? slice[slice.startIndex + sliceIndex]
                : nil
            let date = total?.start ?? calendar.date(byAdding: .day, value: index, to: year.start)!
            return Cell(date: date, total: total, column: position / 7, row: position % 7)
        }

        let firstMonth = calendar.dateInterval(of: .month, for: year.start)!.start
        var months: [MonthLabel] = []
        for step in 0...12 {
            let first = calendar.date(byAdding: .month, value: step, to: firstMonth)!
            guard first <= year.end else { break }
            if first < year.start {
                months.append(MonthLabel(column: 0, date: year.start))
            } else {
                let index = HeatmapYear.days(from: year.start, to: first, calendar: calendar)
                months.append(MonthLabel(column: (leading + index) / 7, date: first))
            }
        }
        // A partial first month keeps its label only when there is room before the next one.
        if months.count > 1, months[0].date == year.start, year.start != firstMonth,
           months[1].column - months[0].column < 3 {
            months.removeFirst()
        }
        self.months = months
    }

    func cell(column: Int, row: Int) -> Cell? {
        let index = column * 7 + row - leading
        return cells.indices.contains(index) ? cells[index] : nil
    }

    func weekStart(column: Int) -> Date {
        calendar.date(byAdding: .day, value: column * 7, to: gridStart)!
    }

    func column(containing date: Date) -> Int? {
        let index = HeatmapYear.days(from: gridStart, to: calendar.startOfDay(for: date), calendar: calendar)
        guard index >= 0 else { return nil }
        let column = index / 7
        return column < columns ? column : nil
    }

    /// Rows labelled Mon, Wed and Fri, wherever the week starts.
    static func weekdayLabels(calendar: Calendar = .current) -> [(row: Int, title: String)] {
        (0..<7).compactMap { row in
            let weekday = (calendar.firstWeekday - 1 + row) % 7 + 1
            guard [2, 4, 6].contains(weekday) else { return nil }
            return (row, calendar.shortWeekdaySymbols[weekday - 1])
        }
    }
}

enum HeatmapScale {
    static let levels = 4

    /// 0 for no time, then quarters of the daily limit. Time over the limit is shown in red instead.
    static func level(minutes: Int, limitMinutes: Int) -> Int {
        guard minutes > 0 else { return 0 }
        guard limitMinutes > 0 else { return levels }
        let level = (minutes * levels + limitMinutes - 1) / limitMinutes
        return min(max(level, 1), levels)
    }

    static func color(level: Int) -> Color {
        switch level {
        case 0: Color.secondary.opacity(0.14)
        case 1: Color.accentColor.opacity(0.3)
        case 2: Color.accentColor.opacity(0.5)
        case 3: Color.accentColor.opacity(0.75)
        default: Color.accentColor
        }
    }

    static let overLevels = 4

    /// 0 when not over, then up to 30 minutes, up to an hour, up to two hours, and more over.
    static func overLevel(overageMinutes: Int) -> Int {
        switch overageMinutes {
        case ...0: 0
        case ...30: 1
        case ...60: 2
        case ...120: 3
        default: 4
        }
    }

    /// Reds at rising strength, ending almost black so the worst days stand out.
    static func overColor(level: Int) -> Color {
        switch level {
        case ...1: Color.red.opacity(0.35)
        case 2: Color.red.opacity(0.65)
        case 3: Color.red
        default: Color(.sRGB, red: 0x4A / 255, green: 0x0A / 255, blue: 0x0A / 255)
        }
    }

    /// The near-black deepest red vanishes on a dark background, so in dark mode it gets a red
    /// edge. Clear in light mode.
    static let deepestOutline = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor.systemRed.withAlphaComponent(0.9)
            : .clear
    })

    static let pto = Color.gray.opacity(0.55)
}

/// A year of days as a GitHub-style contribution grid.
struct CalendarHeatmap: View {
    let layout: HeatmapLayout
    let period: HistoryPeriod
    var selectedStart: Date?
    var onSelect: (Date) -> Void

    static let cellSize: CGFloat = 11
    static let spacing: CGFloat = 3
    private var pitch: CGFloat { Self.cellSize + Self.spacing }
    private var calendar: Calendar { .current }

    var body: some View {
        let selectedColumn = period == .weeks ? selectedStart.flatMap(layout.column(containing:)) : nil
        let selectedDay = period == .days ? selectedStart.map(calendar.startOfDay(for:)) : nil

        HStack(alignment: .top, spacing: 5) {
            ZStack(alignment: .topTrailing) {
                ForEach(HeatmapLayout.weekdayLabels(calendar: calendar), id: \.row) { label in
                    Text(label.title)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .frame(height: Self.cellSize)
                        .offset(y: 14 + CGFloat(label.row) * pitch)
                }
            }
            .frame(width: 24, alignment: .trailing)

            VStack(alignment: .leading, spacing: 3) {
                ZStack(alignment: .topLeading) {
                    ForEach(layout.months, id: \.column) { month in
                        Text(monthTitle(month.date))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .fixedSize()
                            .offset(x: CGFloat(month.column) * pitch)
                    }
                }
                .frame(width: CGFloat(layout.columns) * pitch, height: 11, alignment: .topLeading)

                HStack(spacing: Self.spacing) {
                    ForEach(0..<layout.columns, id: \.self) { column in
                        VStack(spacing: Self.spacing) {
                            ForEach(0..<7, id: \.self) { row in
                                cellView(layout.cell(column: column, row: row), selectedDay: selectedDay, inSelectedWeek: column == selectedColumn)
                            }
                        }
                        .padding(1.5)
                        .overlay {
                            if column == selectedColumn {
                                RoundedRectangle(cornerRadius: 3.5)
                                    .strokeBorder(Color.primary.opacity(0.8), lineWidth: 1.5)
                            }
                        }
                        .padding(-1.5)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func cellView(_ cell: HeatmapLayout.Cell?, selectedDay: Date?, inSelectedWeek: Bool) -> some View {
        if let cell {
            let isSelected = selectedDay == cell.date
            let text = helpText(for: cell)
            Button {
                select(cell)
            } label: {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color(for: cell))
                    .frame(width: Self.cellSize, height: Self.cellSize)
                    .overlay {
                        if overLevel(for: cell) == HeatmapScale.overLevels {
                            RoundedRectangle(cornerRadius: 2)
                                .strokeBorder(HeatmapScale.deepestOutline, lineWidth: 1)
                        }
                    }
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 2.5)
                                .strokeBorder(Color.primary.opacity(0.85), lineWidth: 1.5)
                                .padding(-1.5)
                        }
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(text)
            .accessibilityLabel(text)
            .accessibilityAddTraits(isSelected || inSelectedWeek ? .isSelected : [])
        } else {
            Color.clear.frame(width: Self.cellSize, height: Self.cellSize)
        }
    }

    private func color(for cell: HeatmapLayout.Cell) -> Color {
        guard let total = cell.total else { return HeatmapScale.color(level: 0) }
        if total.isOver { return HeatmapScale.overColor(level: overLevel(for: cell)) }
        if total.isPTO { return HeatmapScale.pto }
        return HeatmapScale.color(level: HeatmapScale.level(minutes: total.minutes, limitMinutes: total.limitMinutes))
    }

    private func overLevel(for cell: HeatmapLayout.Cell) -> Int {
        guard let total = cell.total, total.isOver else { return 0 }
        return HeatmapScale.overLevel(overageMinutes: total.overageMinutes)
    }

    private func helpText(for cell: HeatmapLayout.Cell) -> String {
        let date = cell.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
        guard let total = cell.total else { return "\(date): no time tracked" }
        var text = "\(date): \(formatMinutes(total.minutes))"
        if total.isOver { text += ", \(formatMinutes(total.overageMinutes)) over the limit" }
        if total.isPTO { text += ", PTO" }
        return text
    }

    private func select(_ cell: HeatmapLayout.Cell) {
        switch period {
        case .days: onSelect(cell.date)
        case .weeks: onSelect(layout.weekStart(column: cell.column))
        }
    }

    private func monthTitle(_ date: Date) -> String {
        calendar.component(.month, from: date) == 1
            ? date.formatted(.dateTime.year())
            : date.formatted(.dateTime.month(.abbreviated))
    }
}

/// "Less ▢▢▢▢▢ More", then the four over-limit reds and the PTO colour.
struct HeatmapLegend: View {
    let limitMinutes: Int

    var body: some View {
        HStack(spacing: 3) {
            Text("Less")
            ForEach(0...HeatmapScale.levels, id: \.self) { level in
                swatch(HeatmapScale.color(level: level))
            }
            Text("More")
                .padding(.trailing, 8)
            Text("Over the \(formatMinutes(limitMinutes)) limit by")
                .padding(.trailing, 2)
            ForEach(Array(zip(1...HeatmapScale.overLevels, ["≤30m", "≤1h", "≤2h", ">2h"])), id: \.0) { level, title in
                swatch(HeatmapScale.overColor(level: level))
                    .overlay {
                        if level == HeatmapScale.overLevels {
                            RoundedRectangle(cornerRadius: 1.5)
                                .strokeBorder(HeatmapScale.deepestOutline, lineWidth: 1)
                        }
                    }
                Text(title)
                    .padding(.trailing, 4)
            }
            Spacer().frame(width: 4)
            swatch(HeatmapScale.pto)
            Text("PTO")
        }
    }

    private func swatch(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(color)
            .frame(width: 8, height: 8)
    }
}
