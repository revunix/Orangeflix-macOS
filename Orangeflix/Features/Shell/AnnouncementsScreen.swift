import SwiftUI

/// The announcements: a calm editorial card feed with category pills,
/// optional cover artwork, readable body text and direct actions.
struct AnnouncementsScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(AnnouncementsModel.self) private var model
    @Environment(BrowseModel.self) private var browse

    private static let feedMaxWidth: CGFloat = 780

    var body: some View {
        VStack(spacing: 0) {
            PageChrome(title: "Ankündigungen",
                       subtitle: model.items.isEmpty
                           ? nil
                           : ShellLiveHint.plural(model.items.count, "Ankündigung", "Ankündigungen")) {
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
                        .glassButtonStyle()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyState(symbol: "megaphone", title: "Keine Ankündigungen.",
                           message: "Neuigkeiten zu Sendungen und Funktionen erscheinen hier.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Space.l) {
                    ForEach(model.items, id: \.shellID) { item in
                        AnnouncementCard(
                            item: item,
                            format: item.magazineId > 0 ? browse.format(pid: item.magazineId) : nil,
                            onOpenLink: { ShellLinks.open(item.url, app: app) },
                            onOpenFormat: { format in
                                browse.formatsPath = [.episodes(pid: format.pid)]
                                app.selection = .formats
                            },
                            onCopyTitle: {
                                AppFormat.copy(item.title)
                                app.show("Kopiert.")
                            }
                        )
                    }
                }
                .frame(maxWidth: Self.feedMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Space.page)
                .padding(.top, Space.s)
                .padding(.bottom, Space.xxl)
            }
        }
    }
}

private struct AnnouncementCard: View {
    let item: Announcement
    let format: Format?
    let onOpenLink: () -> Void
    let onOpenFormat: (Format) -> Void
    let onCopyTitle: () -> Void

    private var artworkURL: String {
        let raw = item.coverImage.isEmpty ? item.image : item.coverImage
        return EpisodeDetailLogic.imageURL(raw)
    }

    private var badgeText: String {
        let raw = item.label.isEmpty ? item.shellType : item.label
        return raw.uppercased()
    }

    private var isLiveAnnouncement: Bool {
        item.type.localizedCaseInsensitiveContains("live")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !artworkURL.isEmpty {
                RemoteArt(url: artworkURL, symbol: "megaphone")
                    .frame(height: 190)
                    .frame(maxWidth: .infinity)
                    .clipped()
                Hairline()
            }

            VStack(alignment: .leading, spacing: Space.m) {
                HStack(alignment: .center, spacing: Space.s) {
                    BrandPill(
                        text: badgeText,
                        color: isLiveAnnouncement ? Palette.live : Palette.accentText,
                        background: isLiveAnnouncement ? Palette.dangerSoft : Palette.accentSoft)
                    if let format {
                        Text(format.title)
                            .font(AppFont.captionMedium)
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if !item.timeDescription.isEmpty {
                        Text(item.timeDescription)
                            .font(AppFont.caption)
                            .foregroundStyle(Palette.textTertiary)
                    }
                }

                Text(item.title)
                    .font(AppFont.displaySmall)
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)

                if !item.shellText.isEmpty {
                    Text(item.shellText)
                        .font(AppFont.body)
                        .foregroundStyle(Palette.textSecondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }

                if !item.url.isEmpty || format != nil {
                    HStack(spacing: Space.s) {
                        if !item.url.isEmpty {
                            PillButton(
                                title: item.ctaLabel.isEmpty ? "Im Browser öffnen" : item.ctaLabel,
                                symbol: "arrow.up.right",
                                style: .glass,
                                action: onOpenLink)
                        }
                        if let format {
                            PillButton(title: format.title, symbol: "tv", style: .glass) {
                                onOpenFormat(format)
                            }
                        }
                    }
                    .padding(.top, Space.xxs)
                }
            }
            .padding(Space.l)
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .contentCard(radius: Radius.card)
        .contextMenu {
            Button("Link im Browser öffnen", action: onOpenLink)
                .disabled(item.url.isEmpty)
            if let format {
                Button("Format „\(format.title)“ öffnen") { onOpenFormat(format) }
            }
            Button("Titel kopieren", action: onCopyTitle)
        }
    }
}
