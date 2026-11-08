import SwiftUI

/// The quality window (Go `quality.go`): the files of an episode with their
/// resolution and size; the chosen quality becomes the quality of the
/// downloads.
struct BrowseQualitySheet: View {
    let episode: Episode

    @Environment(AppModel.self) private var app
    @Environment(BrowseModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Qualität wählen")
                .font(AppFont.displaySmall)
                .foregroundStyle(Palette.textPrimary)
            Text(BrowseLogic.title(of: episode))
                .font(AppFont.body)
                .foregroundStyle(Palette.textPrimary)
            Text("Die gewählte Qualität gilt für die folgenden Downloads.")
                .font(AppFont.bodySmall)
                .foregroundStyle(Palette.textSecondary)
            content
            HStack {
                Spacer()
                Button("Schließen") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(Space.xl)
        .frame(minWidth: 420, minHeight: 260)
        .background(Palette.surfaceRaised)
        .task { await model.loadQualities(for: episode) }
    }

    @ViewBuilder private var content: some View {
        let files = model.qualityFiles(episode)
        if model.qualityLoading.contains(episode.identifier) {
            ProgressView("lade die Qualitäten …")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if files.isEmpty {
            VStack(spacing: Space.s) {
                Text("Für diese Folge sind keine Dateien bekannt.")
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
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: Space.s) {
                HStack(spacing: Space.m) {
                    Text("QUALITÄT")
                        .frame(width: 120, alignment: .leading)
                    Text("AUFLÖSUNG")
                        .frame(width: 120, alignment: .leading)
                    Text("GRÖSSE")
                }
                .font(AppFont.captionMedium)
                .foregroundStyle(Palette.textTertiary)
                Divider().overlay(Palette.divider)
                ForEach(Array(files.enumerated()), id: \.offset) { _, file in
                    Button {
                        model.selectQuality(file)
                        dismiss()
                    } label: {
                        HStack(spacing: Space.m) {
                            Text(file.desc)
                                .font(AppFont.subheading)
                                .foregroundStyle(Palette.textPrimary)
                                .frame(width: 120, alignment: .leading)
                            Text(file.dimensions.isEmpty ? "-" : file.dimensions)
                                .font(AppFont.digits)
                                .foregroundStyle(Palette.textSecondary)
                                .frame(width: 120, alignment: .leading)
                            Text(sizeText(file))
                                .font(AppFont.digits)
                                .foregroundStyle(Palette.textSecondary)
                            Spacer(minLength: Space.s)
                            Image(systemName: "checkmark")
                                .foregroundStyle(Palette.accent)
                                .opacity(isChosen(file) ? 1 : 0)
                                .frame(width: 16)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Diese Qualität für die folgenden Downloads nehmen")
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// Whether the file carries the quality that is set in the settings.
    private func isChosen(_ file: ClipFile) -> Bool {
        BrowseLogic.qualityName(file.desc) == app.settings.quality.rawValue
    }

    /// The size of the file; the audio files carry the hint of the TUI.
    private func sizeText(_ file: ClipFile) -> String {
        let size = AppFormat.bytes(file.size)
        return file.kind == "music" ? "\(size) (nur Ton)" : size
    }
}
