import SwiftUI

/// The announcements (Go announcement panel and detail): a list of
/// "TYPE Title" rows and the detail of the selected one — Typ, Zeit, Text
/// and Link.
struct AnnouncementsScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(AnnouncementsModel.self) private var model

    @State private var selection: String?

    var body: some View {
        VStack(spacing: 0) {
            PageChrome(title: "Ankündigungen",
                       subtitle: model.items.isEmpty
                           ? nil
                           : ShellLiveHint.plural(model.items.count, "Ankündigung", "Ankündigungen")) {
                    IconAction(icon: "safari", help: "Link im Browser öffnen",
                               isDisabled: selectedItem?.url.isEmpty ?? true) {
                        if let item = selectedItem { ShellLinks.open(item.url, app: app) }
                    }
                    IconAction(icon: "arrow.clockwise", help: "Aktualisieren",
                               isDisabled: model.isLoading) {
                        Task { await model.load(force: true) }
                    }
            }
            content
        }
        .navigationTitle("")
        .task(id: app.accountGeneration) {
            await model.loadIfNeeded()
        }
    }

    @ViewBuilder private var content: some View {
        if model.isLoading && !model.hasLoaded {
            ProgressView("Lade Ankündigungen …")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.items.isEmpty {
            if let error = model.errorText {
                ContentUnavailableView {
                    Label("Die Ankündigungen konnten nicht geladen werden.", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Erneut versuchen") { Task { await model.load(force: true) } }
                }
            } else {
                ContentUnavailableView("Keine Ankündigungen.", systemImage: "megaphone")
            }
        } else {
            VStack(spacing: 0) {
                list
                Divider()
                detail
            }
        }
    }

    private var list: some View {
        List(selection: $selection) {
            ForEach(model.items, id: \.shellID) { item in
                HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                    Text(item.shellType)
                        .font(AppFont.captionMedium)
                        .foregroundStyle(Palette.accentText)
                        .frame(width: 72, alignment: .leading)
                    Text(item.title)
                        .font(AppFont.subheading)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                }
                .padding(.vertical, Space.xxs)
                .tag(item.shellID)
                .contextMenu {
                    Button("Link im Browser öffnen") { ShellLinks.open(item.url, app: app) }
                        .disabled(item.url.isEmpty)
                    Button("Titel kopieren") {
                        AppFormat.copy(item.title)
                        app.show("Kopiert.")
                    }
                }
            }
        }
        .frame(minHeight: 160)
    }

    @ViewBuilder private var detail: some View {
        if let item = selectedItem {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.m) {
                    Text(item.title)
                        .font(AppFont.displaySmall)
                        .foregroundStyle(Palette.textPrimary)
                    BrandDetailRow(label: "Typ", value: item.shellType)
                    if !item.timeDescription.isEmpty {
                        BrandDetailRow(label: "Zeit", value: item.timeDescription)
                    }
                    if !item.shellText.isEmpty {
                        Hairline()
                        SectionLabel(text: "Text")
                        Text(item.shellText)
                            .font(AppFont.body)
                            .foregroundStyle(Palette.textSecondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !item.url.isEmpty {
                        Hairline()
                        BrandDetailRow(label: "Link", value: item.url)
                        Button(item.url) { ShellLinks.open(item.url, app: app) }
                            .buttonStyle(.link)
                            .font(AppFont.bodySmall)
                            .lineLimit(1)
                    }
                }
                .padding(Space.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 120, idealHeight: 200)
            .background(Palette.surfaceRaised)
        } else {
            Text("Wähle eine Ankündigung.")
                .font(AppFont.bodySmall)
                .foregroundStyle(Palette.textTertiary)
                .frame(maxWidth: .infinity, minHeight: 120)
        }
    }

    private var selectedItem: Announcement? {
        guard let selection else { return nil }
        return model.items.first { $0.shellID == selection }
    }
}
