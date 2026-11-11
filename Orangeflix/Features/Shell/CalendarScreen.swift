import SwiftUI

/// The calendar: a month grid with unified header controls and rich detail
/// popovers when clicking an entry or an overflow day.
struct CalendarScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(CalendarModel.self) private var model
    @Environment(BrowseModel.self) private var browse

    /// The entry whose popover is currently open.
    @State private var activeEntryID: String?
    /// The day whose full list popover is open when clicking "+N".
    @State private var overflowDay: Date?
    /// The first of the month that is shown.
    @State private var month = CalendarScreen.startOfMonth(Date())

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "de_DE")
        calendar.firstWeekday = 2
        return calendar
    }

    private static let weekdays = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]

    var body: some View {
        VStack(spacing: 0) {
            PageChrome(title: monthTitle, subtitle: subtitle) {
                legend
                    .padding(.trailing, Space.s)
                PillButton(title: "Heute", style: .glass) {
                    showToday()
                }
                .help("Zurück zum aktuellen Monat")
                IconAction(icon: "chevron.left", help: "Voriger Monat") { step(by: -1) }
                IconAction(icon: "chevron.right", help: "Nächster Monat") { step(by: 1) }
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

    private var subtitle: String? {
        guard !model.entries.isEmpty else { return nil }
        let inMonthCount = weeks.flatMap { $0 }
            .filter { calendar.isDate($0, equalTo: month, toGranularity: .month) }
            .reduce(0) { $0 + entries(on: $1).count }
        if inMonthCount > 0 {
            return "Kalender · \(ShellLiveHint.plural(inMonthCount, "Termin", "Termine")) in diesem Monat"
        }
        return "Kalender · \(ShellLiveHint.plural(model.entries.count, "Termin", "Termine")) insgesamt"
    }

    private var legend: some View {
        HStack(spacing: Space.m) {
            legendDot("Live", color: Palette.live)
            legendDot("Event", color: Palette.info)
            legendDot("Folge", color: Palette.accent)
        }
    }

    private func legendDot(_ title: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title)
                .font(AppFont.caption)
                .foregroundStyle(Palette.textSecondary)
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
                        .glassButtonStyle()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyState(symbol: "calendar", title: "Keine Termine in der nächsten Zeit.",
                           message: "Neue Livestreams, Events und Veröffentlichungen erscheinen hier.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            VStack(spacing: 0) {
                weekdayBar
                grid
            }
            .padding(.horizontal, Space.page)
            .padding(.bottom, Space.l)
        }
    }

    /// The names of the week; the columns line up with the days below.
    private var weekdayBar: some View {
        HStack(spacing: 0) {
            ForEach(Self.weekdays, id: \.self) { name in
                Text(name)
                    .font(AppFont.captionMedium)
                    .foregroundStyle(Palette.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 8)
            }
        }
    }

    /// Six weeks of days, the whole month inside them.
    private var grid: some View {
        GeometryReader { geo in
            let height = geo.size.height / 6
            let bars = max(1, min(3, Int((height - 34) / 21)))
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
                                activeEntryID: $activeEntryID,
                                overflowDay: $overflowDay,
                                formatLookup: { pid in pid > 0 ? browse.format(pid: pid) : nil },
                                onOpenLive: { model.openLive($0) },
                                onOpenLink: { model.openLink($0) },
                                onOpenFormat: { format in
                                    browse.formatsPath = [.episodes(pid: format.pid)]
                                    app.selection = .formats
                                },
                                onCopyTitle: { model.copyTitle($0) }
                            )
                            .frame(maxHeight: .infinity)
                            .overlay(alignment: .top) {
                                if row > 0 { Hairline() }
                            }
                            .overlay(alignment: .leading) {
                                if column > 0 { Hairline(vertical: true) }
                            }
                        }
                    }
                    .frame(height: height)
                }
            }
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
    }

    // MARK: The month

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: month)
    }

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
        activeEntryID = nil
        overflowDay = nil
    }

    private func showToday() {
        month = Self.startOfMonth(Date())
        activeEntryID = nil
        overflowDay = nil
    }

    private static func startOfMonth(_ date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "de_DE")
        let parts = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: parts) ?? date
    }
}

/// One day of the table: the number and the entries as bars, each opening a
/// detail popover on click.
private struct CalendarDayCell: View {
    let date: Date
    let showsMonth: Bool
    let isInMonth: Bool
    let isToday: Bool
    let entries: [CalendarEntry]
    let maxBars: Int
    @Binding var activeEntryID: String?
    @Binding var overflowDay: Date?
    let formatLookup: (Int) -> Format?
    let onOpenLive: (CalendarEntry) -> Void
    let onOpenLink: (CalendarEntry) -> Void
    let onOpenFormat: (Format) -> Void
    let onCopyTitle: (CalendarEntry) -> Void

    @State private var hovering = false

    private var dayNumber: String {
        let day = Calendar.current.component(.day, from: date)
        guard showsMonth else { return "\(day)" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "d. MMM"
        return formatter.string(from: date)
    }

    private var isOverflowOpen: Bool {
        guard let overflowDay else { return false }
        return Calendar.current.isDate(overflowDay, inSameDayAs: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(dayNumber)
                .font(isToday ? AppFont.digitsMedium : AppFont.bodySmall)
                .foregroundStyle(numberColor)
                .frame(minWidth: 22, minHeight: 22)
                .padding(.horizontal, isToday ? 5 : 0)
                .background {
                    if isToday { Capsule().fill(Palette.accent) }
                }
                .padding(.top, Space.xxs)

            ForEach(entries.prefix(maxBars), id: \.shellID) { entry in
                bar(entry)
            }

            if entries.count > maxBars {
                Button {
                    overflowDay = date
                } label: {
                    Text("+\(entries.count - maxBars) weitere")
                        .font(AppFont.captionMedium)
                        .foregroundStyle(Palette.accentText)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                }
                .buttonStyle(.plain)
                .popover(isPresented: Binding(
                    get: { isOverflowOpen },
                    set: { if !$0 { overflowDay = nil } }
                )) {
                    dayListPopover
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(background)
        .opacity(isInMonth ? 1 : 0.45)
        .onHover { hovering = $0 }
    }

    private func bar(_ entry: CalendarEntry) -> some View {
        let tint = color(of: entry)
        let isOpen = activeEntryID == entry.shellID
        return Button {
            activeEntryID = isOpen ? nil : entry.shellID
        } label: {
            HStack(spacing: Space.xs) {
                Circle()
                    .fill(tint)
                    .frame(width: 6, height: 6)
                if !entry.time.isEmpty {
                    Text(entry.time)
                        .font(AppFont.digits)
                        .foregroundStyle(Palette.textSecondary)
                }
                Text(entry.title)
                    .font(AppFont.captionMedium)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
                    .fill(tint.opacity(isOpen ? 0.28 : 0.16))
            )
            .overlay {
                if isOpen {
                    RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
                        .strokeBorder(tint, lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: Binding(
            get: { isOpen },
            set: { if !$0 && activeEntryID == entry.shellID { activeEntryID = nil } }
        )) {
            CalendarEntryPopover(
                entry: entry,
                tint: tint,
                format: formatLookup(entry.pid),
                onOpenLive: { activeEntryID = nil; onOpenLive(entry) },
                onOpenLink: { activeEntryID = nil; onOpenLink(entry) },
                onOpenFormat: { format in activeEntryID = nil; onOpenFormat(format) },
                onCopyTitle: { onCopyTitle(entry) }
            )
        }
        .accessibilityLabel("\(entry.time), \(entry.title)")
        .help("\(entry.time) · \(entry.title)")
        .contextMenu {
            if entry.type == "live" {
                Button("Live-Ansicht öffnen") { onOpenLive(entry) }
            }
            if let format = formatLookup(entry.pid) {
                Button("Format „\(format.title)“ öffnen") { onOpenFormat(format) }
            }
            if !entry.url.isEmpty {
                Button("Link im Browser öffnen") { onOpenLink(entry) }
            }
            Button("Titel kopieren") { onCopyTitle(entry) }
        }
    }

    private var dayListPopover: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(AppFormat.day(date))
                .font(AppFont.heading)
                .foregroundStyle(Palette.textPrimary)
            ForEach(entries, id: \.shellID) { entry in
                HStack(spacing: Space.s) {
                    Circle().fill(color(of: entry)).frame(width: 7, height: 7)
                    Text(entry.time)
                        .font(AppFont.digits)
                        .foregroundStyle(Palette.textSecondary)
                        .frame(width: 42, alignment: .leading)
                    Text(entry.title)
                        .font(AppFont.bodySmall)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: Space.s)
                    if entry.type == "live" {
                        Button("Live") { overflowDay = nil; onOpenLive(entry) }
                            .controlSize(.small)
                    } else if !entry.url.isEmpty {
                        Button("Öffnen") { overflowDay = nil; onOpenLink(entry) }
                            .controlSize(.small)
                    }
                }
            }
        }
        .padding(Space.l)
        .frame(width: 340)
    }

    private var numberColor: Color {
        if isToday { return .white }
        if isInMonth { return Palette.textPrimary }
        return Palette.textTertiary
    }

    private var background: Color {
        if isToday { return Palette.accentSoft.opacity(0.35) }
        return hovering && isInMonth ? Palette.surfaceMuted.opacity(0.6) : .clear
    }

    private func color(of entry: CalendarEntry) -> Color {
        switch entry.type {
        case "live": Palette.live
        case "event": Palette.info
        default: Palette.accent
        }
    }
}

private struct CalendarEntryPopover: View {
    let entry: CalendarEntry
    let tint: Color
    let format: Format?
    let onOpenLive: () -> Void
    let onOpenLink: () -> Void
    let onOpenFormat: (Format) -> Void
    let onCopyTitle: () -> Void

    private var summaryText: String {
        if !entry.description.isEmpty { return entry.description }
        if let liveText = entry.live?.description, !liveText.isEmpty { return liveText }
        if let eventText = entry.event?.description, !eventText.isEmpty { return eventText }
        return ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.xs) {
                BrandPill(text: entry.shellBadge, color: tint, background: tint.opacity(0.15))
                if entry.premium {
                    BrandPill(text: "PREMIUM")
                }
                if entry.event?.soldOut == true {
                    BrandPill(text: "AUSVERKAUFT", color: Palette.danger, background: Palette.dangerSoft)
                }
                Spacer(minLength: 0)
                Text([entry.date, entry.time].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(AppFont.digits)
                    .foregroundStyle(Palette.textSecondary)
            }

            Text(entry.title)
                .font(AppFont.displaySmall)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if !summaryText.isEmpty {
                Text(summaryText)
                    .font(AppFont.bodySmall)
                    .foregroundStyle(Palette.textSecondary)
                    .lineSpacing(2)
                    .lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let address = entry.event?.address, !address.isEmpty {
                Label(address, systemImage: "mappin.and.ellipse")
                    .font(AppFont.caption)
                    .foregroundStyle(Palette.textSecondary)
            }

            HStack(spacing: Space.s) {
                if entry.type == "live" {
                    PillButton(title: "Zur Live-Ansicht", symbol: "dot.radiowaves.left.and.right",
                               style: .accent, action: onOpenLive)
                } else if let format {
                    PillButton(title: format.title, symbol: "tv", style: .accent) {
                        onOpenFormat(format)
                    }
                }
                if !entry.url.isEmpty {
                    PillButton(title: "Browser", symbol: "safari", style: .glass, action: onOpenLink)
                }
                Spacer(minLength: 0)
                IconAction(icon: "doc.on.doc", help: "Titel kopieren", action: onCopyTitle)
            }
        }
        .padding(Space.l)
        .frame(width: 360)
    }
}
