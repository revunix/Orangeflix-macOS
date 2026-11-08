import SwiftUI

/// The downloads of the session (Go queue screen): one row per job with its
/// state, the progress, the speed and the target file; the actions of the
/// TUI (`o` Ordner öffnen, `y` Pfad kopieren, `x` Datei löschen) are the
/// context menu of the row.
struct DownloadsScreen: View {
    @Environment(DownloadCenter.self) private var center

    /// The job the toolbar acts on.
    @State private var selection: String?
    /// The job whose file is about to be deleted.
    @State private var deletedJob: DownloadJob?

    var body: some View {
        VStack(spacing: 0) {
            PageChrome(title: "Downloads", subtitle: subtitle) {
                    MoreMenu {
                        if let job = focusedJob {
                            Button("Im Finder zeigen") { center.reveal(job) }
                                .disabled(job.file == nil)
                            Button("Pfad kopieren") { center.copyPath(job) }
                                .disabled(job.file == nil)
                            Button("Abbrechen") { center.cancel(job.id) }
                                .disabled(!job.state.isActive)
                            Divider()
                            Button("Datei löschen …", role: .destructive) { deletedJob = job }
                                .disabled(job.file == nil)
                            Divider()
                        }
                        Button("Alle abbrechen") { center.cancelAll() }
                            .disabled(!center.isRunning)
                        Button("Liste leeren") { center.clearFinished() }
                            .disabled(!center.jobs.contains { !$0.state.isActive })
                    }
            }
            content
        }
        .navigationTitle("")
        .confirmationDialog(
            "Datei löschen?",
            isPresented: Binding(get: { deletedJob != nil }, set: { if !$0 { deletedJob = nil } }),
            presenting: deletedJob
        ) { job in
            Button("Löschen", role: .destructive) {
                deletedJob = nil
                Task { await center.deleteFile(of: job) }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: { job in
            Text(job.file?.path(percentEncoded: false) ?? job.label)
        }
    }

    /// The line under the title: the counts of the run, or the note that the
    /// download is going on.
    private var subtitle: String {
        if center.isRunning { return "Der Download läuft …" }
        if let summary = center.summary { return summary.countsLine }
        return "\(center.jobs.count) Downloads"
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        if center.jobs.isEmpty {
            emptyState
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            list
        }
    }

    /// Nothing has been downloaded yet (Go queue screen).
    private var emptyState: some View {
        EmptyState(symbol: "arrow.down.circle",
                   title: "In dieser Sitzung wurde noch nichts heruntergeladen.",
                   message: "Wähle ein Format und lade seine Folgen herunter.")
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Space.xl) {
                if !activeJobs.isEmpty {
                    jobSection("Läuft", jobs: activeJobs)
                }
                if !finishedJobs.isEmpty {
                    jobSection(activeJobs.isEmpty ? "Downloads" : "Fertig", jobs: finishedJobs)
                }
            }
            .padding(.horizontal, Space.page)
            .padding(.top, Space.s)
            .padding(.bottom, Space.xl)
        }
    }

    private var activeJobs: [DownloadJob] { center.jobs.filter(\.state.isActive) }

    private var finishedJobs: [DownloadJob] { center.jobs.filter { !$0.state.isActive } }

    private func jobSection(_ title: String, jobs: [DownloadJob]) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionHeader(title: title, detail: "\(jobs.count)")
            LazyVStack(spacing: Space.s) {
                ForEach(jobs) { job in
                    DownloadJobRow(job: job, isSelected: job.id == selection)
                        .onTapGesture { selection = job.id }
                        .contextMenu { menu(for: job) }
                }
            }
        }
    }

    // MARK: Menu

    @ViewBuilder private func menu(for job: DownloadJob) -> some View {
        Button("Im Finder zeigen") { center.reveal(job) }
            .disabled(job.file == nil)
        Button("Pfad kopieren") { center.copyPath(job) }
            .disabled(job.file == nil)
        Button("Abbrechen") { center.cancel(job.id) }
            .disabled(!job.state.isActive)
        Divider()
        Button("Datei löschen …", role: .destructive) { deletedJob = job }
            .disabled(job.file == nil)
    }

    /// The job the toolbar works on: the selected one, else the last job
    /// (the TUI works on the last job).
    private var focusedJob: DownloadJob? {
        if let selection, let job = center.jobs.first(where: { $0.id == selection }) { return job }
        return center.jobs.last
    }
}

/// One download of the list: the state, the label, the progress and the
/// target file.
private struct DownloadJobRow: View {
    let job: DownloadJob
    var isSelected = false

    var body: some View {
        HStack(alignment: .top, spacing: Space.m) {
            Image(systemName: job.state.symbolName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(job.state.symbolColor)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Text(job.label)
                        .font(AppFont.subheading)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                    BrandPill(text: job.state.label)
                }
                if let file = job.file {
                    Text(AppFormat.displayPath(file))
                        .font(AppFont.caption)
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(file.path(percentEncoded: false))
                }
                if job.state == .loading {
                    Capsule()
                        .fill(Palette.surfaceMuted)
                        .frame(height: 6)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(Palette.accent)
                                .scaleEffect(x: max(job.fraction ?? 0, 0.02), anchor: .leading)
                        }
                }
                metrics
                if let message = job.message {
                    Text(message)
                        .font(AppFont.caption)
                        .foregroundStyle(Palette.danger)
                        .lineLimit(2)
                }
            }
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentCard(selected: isSelected)
    }

    /// The numbers of the job: the size, the speed and the rest of the time.
    @ViewBuilder private var metrics: some View {
        let parts = metricParts
        if !parts.isEmpty {
            HStack(spacing: Space.m) {
                ForEach(parts, id: \.self) { part in
                    Text(part)
                        .font(AppFont.digits)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
        }
    }

    /// The numbers of the row; a finished job shows its size instead of the
    /// progress.
    private var metricParts: [String] {
        switch job.state {
        case .done:
            return job.totalSizeText.isEmpty ? [] : [job.totalSizeText]
        case .loading:
            var parts: [String] = []
            if !job.sizeText.isEmpty { parts.append(job.sizeText) }
            if !job.speedText.isEmpty { parts.append(job.speedText) }
            if !job.etaText.isEmpty { parts.append(job.etaText) }
            return parts
        case .cancelled:
            return job.sizeText.isEmpty ? [] : [job.sizeText]
        default:
            return []
        }
    }
}
