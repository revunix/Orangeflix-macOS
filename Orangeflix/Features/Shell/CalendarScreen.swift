import SwiftUI

/// The calendar (Go calendar screen): a month as a table of days, each day
/// with its entries as colored bars. The actions of the header work on the
/// chosen entry.
struct CalendarScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(CalendarModel.self) private var model

    /// The entry the actions of the header work on.
    @State private var selection: String?
    /// The first of the month that is shown.
    @State private var month = CalendarScreen.startOfMonth(Date())

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "de_DE")
        // The week starts on Monday, as the programs of Orangeflix run it.
        calendar.firstWeekday = 2
        return calendar
    }

    private static let weekdays = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]

    var body: some View {
        VStack(spacing: 0) {
            PageChrome(title: "Kalender",
                       subtitle: model.entries.isEmpty
                           ? nil
                           : ShellLiveHint.plural(model.entries.count, "Termin", "Termine")) {
                    IconAction(icon: "dot.radiowaves.left.and.right", help: "Live-Ansicht öffnen",
                               isDisabled: selectedEntry?.type != "live") {
                        if let entry = selectedEntry { model.openLive(entry) }
                    }
                    IconAction(icon: "safari", help: "Link im Browser öffnen",
                               isDisabled: selectedEntry == nil) {
                        if let entry = selectedEntry { model.openLink(entry) }
                    }
                    IconAction(icon: "doc.on.doc", help: "Titel kopieren",
                               isDisabled: selectedEntry == nil) {
                        if let entry = selectedEntry { model.copyTitle(entry) }
                    }
                    IconAction(icon: "arrow.clockwise", help: "Aktualisieren",
                               isDisabled: model.isLoading) {
                        Task { await model.load(force: true) }
                    }
            }
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("")
        .task(id: app.accountGeneration) {
            await model.loadIfNeeded()
        }
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        if model.isLoading && !model.hasLoaded {
            ProgressView("Lade den Kalender …")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.entries.isEmpty {
            if let error = model.errorText {
                ContentUnavailableView {
                    Label("Der Kalender konnte nicht geladen werden.", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Erneut versuchen") { Task { await model.load(force: true) } }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView("Keine Termine in der nächsten Zeit.", systemImage: "calendar")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            VStack(spacing: 0) {
                monthBar
                weekdayBar
                grid
            }
            .padding(.horizontal, Space.page)
            .padding(.bottom, Space.l)
        }
    }

    /// The month, the way back to today and the two arrows.
    private var monthBar: some View {
        HStack(alignment: .center, spacing: Space.m) {
            Text(monthTitle)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Palette.textPrimary)
            Spacer(minLength: Space.m)
            HStack(spacing: Space.xs) {
                PillButton(title: "Heute", style: .glass) {
                    showToday()
                }
                .help("Zurück zu heute")
                IconAction(icon: "chevron.left", help: "Voriger Monat") { step(by: -1) }
                IconAction(icon: "chevron.right", help: "Nächster Monat") { step(by: 1) }
            }
        }
        .padding(.vertical, Space.m)
    }

    /// The names of the week; the columns line up with the days below.
    private var weekdayBar: some View {
        HStack(spacing: 0) {
            ForEach(Self.weekdays, id: \.self) { name in
                Text(name)
                    .font(AppFont.captionMedium)
                    .foregroundStyle(Palette.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 6)
            }
        }
    }

    /// Six weeks of days, the whole month inside them.
    private var grid: some View {
        GeometryReader { geo in
            let height = geo.size.height / 6
            let bars = max(1, min(3, Int((height - 34) / 19)))
            VStack(spacing: 0) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { row, week in
                    HStack(spacing: 0) {
                        ForEach(Array(week.enumerated()), id: \.offset) { column, day in
                            CalendarDayCell(
                                date: day,
                                showsMonth: calendar.component(.day, from: day) == 1,
                                isInMonth: calendar.isDate(day, equalTo: month, toGranularity: .month),
                                isToday: calendar.isDateInToday(day),
                                entries: entries(on: day),
                                maxBars: bars,
                                selection: selection,
                                onSelect: { selection = $0.shellID },
                                onOpen: open
                            )
                            .frame(maxHeight: .infinity)
                            .overlay(alignment: .top) {
                                if row > 0 {
                                    Hairline()
                                }
                            }
                            .overlay(alignment: .leading) {
                                if column > 0 {
                                    Hairline(vertical: true)
                                }
                            }
                        }
                    }
                    .frame(height: height)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: Radius.l, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
        }
    }

    // MARK: The month

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: month)
    }

    /// Six weeks from the Monday on or before the first of the month.
    private var weeks: [[Date]] {
        guard let range = calendar.range(of: .day, in: .month, for: month),
              let first = calendar.date(byAdding: .day, value: range.lowerBound - 1, to: month) else {
            return []
        }
        let weekday = calendar.component(.weekday, from: first)
        let leading = (weekday + 5) % 7
        guard let start = calendar.date(byAdding: .day, value: -leading, to: first) else { return [] }
        return (0..<6).map { week in
            (0..<7).compactMap { day in
                calendar.date(byAdding: .day, value: week * 7 + day, to: start)
            }
        }
    }

    /// The entries of the month, grouped by day and sorted by time.
    private var entriesByDay: [Date: [CalendarEntry]] {
        var map: [Date: [CalendarEntry]] = [:]
        for entry in model.entries where entry.timestamp > 0 {
            let date = calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(entry.timestamp)))
            map[date, default: []].append(entry)
        }
        for key in map.keys {
            map[key]?.sort {
                $0.time == $1.time ? $0.title < $1.title : $0.time < $1.time
            }
        }
        return map
    }

    private func entries(on date: Date) -> [CalendarEntry] {
        entriesByDay[calendar.startOfDay(for: date)] ?? []
    }

    // MARK: Navigation

    private func step(by months: Int) {
        guard let next = calendar.date(byAdding: .month, value: months, to: month) else { return }
        month = Self.startOfMonth(next)
        selection = nil
    }

    private func showToday() {
        month = Self.startOfMonth(Date())
        selection = nil
    }

    private static func startOfMonth(_ date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "de_DE")
        let parts = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: parts) ?? date
    }

    // MARK: Actions

    private var selectedEntry: CalendarEntry? {
        guard let selection else { return nil }
        return model.entries.first { $0.shellID == selection }
    }

    private func open(_ entry: CalendarEntry) {
        if entry.type == "live" {
            model.openLive(entry)
        } else {
            model.openLink(entry)
        }
    }
}

/// One day of the table: the number and the entries as bars.
private struct CalendarDayCell: View {
    let date: Date
    /// True on the first of a month: the number then names the month.
    let showsMonth: Bool
    let isInMonth: Bool
    let isToday: Bool
    let entries: [CalendarEntry]
    let maxBars: Int
    let selection: String?
    let onSelect: (CalendarEntry) -> Void
    let onOpen: (CalendarEntry) -> Void

    @State private var hovering = false

    private var dayNumber: String {
        let day = Calendar.current.component(.day, from: date)
        guard showsMonth else { return "\(day)" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "d. MMM"
        return formatter.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(dayNumber)
                .font(isToday ? AppFont.digitsMedium : AppFont.bodySmall)
                .foregroundStyle(numberColor)
                .frame(minWidth: 20, minHeight: 20)
                .padding(.horizontal, isToday ? 4 : 0)
                .background {
                    if isToday {
                        Capsule().fill(Palette.accent)
                    }
                }
                .padding(.top, Space.xxs)
            ForEach(entries.prefix(maxBars), id: \.shellID) { entry in
                bar(entry)
            }
            if entries.count > maxBars {
                Text("+\(entries.count - maxBars)")
                    .font(AppFont.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .padding(.leading, Space.xxs)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(background)
        .opacity(isInMonth ? 1 : 0.45)
        .onHover { hovering = $0 }
    }

    private func bar(_ entry: CalendarEntry) -> some View {
        Button {
            onSelect(entry)
        } label: {
            HStack(spacing: Space.xs) {
                Circle()
                    .fill(color(of: entry))
                    .frame(width: 6, height: 6)
                Text(entry.title)
                    .font(AppFont.caption)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
                .fill(color(of: entry).opacity(0.42)))
            .overlay {
                if selection == entry.shellID {
                    RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
                        .strokeBorder(color(of: entry), lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // A double click opens the entry; a single one only selects it.
        .simultaneousGesture(TapGesture(count: 2).onEnded { onOpen(entry) })
        .accessibilityLabel("\(entry.time), \(entry.title)")
        .help("\(entry.time) · \(entry.title)")
        .contextMenu {
            Button("Live-Ansicht öffnen") { onOpen(entry) }
                .disabled(entry.type != "live")
            Button("Link im Browser öffnen") { onOpen(entry) }
        }
    }

    private var numberColor: Color {
        if isToday { return .white }
        if isInMonth { return Palette.textPrimary }
        return Palette.textTertiary
    }

    private var background: Color {
        hovering && isInMonth ? Palette.surfaceMuted.opacity(0.5) : .clear
    }

    private func color(of entry: CalendarEntry) -> Color {
        switch entry.type {
        case "live": Palette.danger
        case "event": Palette.info
        default: Palette.accent
        }
    }
}
