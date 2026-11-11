import SwiftUI

/// Studio-card quality selector sheet replacing the legacy 3-column TUI table.
/// Displays each file stream as a rich card with resolution badge, dimensions,
/// file size, active checkmark and a direct download trigger.
struct BrowseQualitySheet: View {
    let episode: Episode

    @Environment(AppModel.self) private var app
    @Environment(BrowseModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private let columns = [
        GridItem(.flexible(), spacing: 10, alignment: .top),
        GridItem(.flexible(), spacing: 10, alignment: .top),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            HStack(spacing: Space.m) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Palette.accentSoft)
                    Image(systemName: "sparkles.tv")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Palette.accentText)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Download-Qualität wählen")
                        .font(AppFont.displaySmall)
                        .foregroundStyle(Palette.textPrimary)
                    Text(BrowseLogic.title(of: episode))
                        .font(AppFont.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
            }

            content

            HStack {
                Text("Die gewählte Stufe wird als Standard für Downloads gespeichert.")
                    .font(AppFont.caption)
                    .foregroundStyle(Palette.textTertiary)
                Spacer(minLength: Space.m)
                Button("Schließen") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Jetzt herunterladen", systemImage: "arrow.down.circle.fill") {
                    Task { await model.downloadEpisodes([episode], of: nil) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.qualityFiles(episode).isEmpty)
            }
        }
        .padding(Space.xl)
        .frame(width: 500)
        .background(Palette.surfaceRaised)
        .task { await model.loadQualities(for: episode) }
    }

    @ViewBuilder private var content: some View {
        let files = model.qualityFiles(episode)
        if model.qualityLoading.contains(episode.identifier) {
            ProgressView("Verfügbare Qualitäten werden geladen …")
                .frame(maxWidth: .infinity, minHeight: 160)
        } else if files.isEmpty {
            VStack(spacing: Space.s) {
                Image(systemName: "film.stack")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(Palette.textTertiary)
                Text("Für diese Folge wurden keine Dateien gefunden.")
                    .font(AppFont.bodySmall)
                    .foregroundStyle(Palette.textSecondary)
                if let error = model.qualityErrors[episode.identifier] {
                    Text(error)
                        .font(AppFont.caption)
                        .foregroundStyle(Palette.danger)
                }
                Button("Erneut laden") {
                    Task { await model.loadQualities(for: episode) }
                }
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity, minHeight: 160)
        } else {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(Array(files.enumerated()), id: \.offset) { _, file in
                    qualityCard(file)
                }
            }
        }
    }

    private func qualityCard(_ file: ClipFile) -> some View {
        let selected = isChosen(file)
        let isAudio = file.kind == "music"
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)

        return Button {
            model.selectQuality(file)
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    BrandPill(
                        text: isAudio ? "Audio" : badgeLabel(for: file),
                        color: selected ? .white : Palette.accentText,
                        background: selected ? Palette.accent : Palette.accentSoft
                    )
                    Spacer(minLength: 0)
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Palette.accent)
                    }
                }

                Text(file.desc.isEmpty ? (isAudio ? "Nur Tonspur" : "Videodatei") : file.desc)
                    .font(AppFont.subheading)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if !file.dimensions.isEmpty {
                        Text(file.dimensions)
                    } else if isAudio {
                        Text("Nur Ton")
                    }
                    if !file.dimensions.isEmpty || isAudio {
                        Text("·")
                    }
                    Text(AppFormat.bytes(file.size))
                }
                .font(AppFont.digits)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
            }
            .padding(Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(selected ? Palette.accentSoft : Palette.surface))
            .overlay {
                shape.strokeBorder(selected ? Palette.accent : Palette.divider, lineWidth: selected ? 1.75 : 1)
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
    }

    private func badgeLabel(for file: ClipFile) -> String {
        let text = "\(file.desc) \(file.dimensions)".lowercased()
        if text.contains("2160") || text.contains("4k") { return "4K UHD" }
        if text.contains("1080") { return "1080p HD" }
        if text.contains("720") { return "720p HD" }
        if text.contains("540") || text.contains("480") || text.contains("360") { return "Mobil" }
        return "Video"
    }

    private func isChosen(_ file: ClipFile) -> Bool {
        BrowseLogic.qualityName(file.desc) == app.settings.quality.rawValue
    }
}
