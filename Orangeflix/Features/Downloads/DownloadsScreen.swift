import AppKit
import SwiftUI

/// The downloads of the session (Go queue screen): one card per job with its
/// thumbnail, state, progress, speed, target file and direct inline actions.
struct DownloadsScreen: View {
    @Environment(DownloadCenter.self) private var center

    /// The job the toolbar acts on.
    @State private var selection: String?
    /// The job whose file is about to be deleted.
    @State private var deletedJob: DownloadJob?

    var body: some View {
        VStack(spacing: 0) {
            PageChrome(title: "Downloads", subtitle: subtitle) {
                if center.isRunning {
                    PillButton(title: "Alle abbrechen", symbol: "xmark", style: .glass) {
                        center.cancelAll()
                    }
                } else if hasFinishedJobs {
                    PillButton(title: "Fertige leeren", symbol: "trash", style: .glass) {
                        center.clearFinished()
                    }
                }
                MoreMenu {
                    if let job = focusedJob {
                        Button("Im Finder zeigen") { center.reveal(job) }
                            .disabled(job.file == nil)
                        Button("In Standard-App öffnen") { openFile(of: job) }
                            .disabled(job.file == nil || job.state.isActive)
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
                        .disabled(!hasFinishedJobs)
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
            Text(job.file?.path(percentEncoded: false) ?? job.displayTitle)
        }
    }

    private var hasFinishedJobs: Bool {
        center.jobs.contains { !$0.state.isActive }
    }

    /// The line under the title: the counts of the run, or the note that the
    /// download is going on.
    private var subtitle: String {
        if center.isRunning {
            let active = center.activeCount
            let speed = center.jobs.filter { $0.state == .loading }.reduce(0.0) { $0 + $1.bytesPerSecond }
            if speed > 0 {
                return "\(active) aktiv · \(DownloadFormat.bytes(Int64(speed)))/s"
            }
            return active == 1 ? "1 Download läuft …" : "\(active) Downloads laufen …"
        }
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
                    jobSection(activeJobs.isEmpty ? "Downloads" : "Abgeschlossen", jobs: finishedJobs)
                }
            }
            .padding(.horizontal, Space.page)
            .padding(.top, Space.s)
            .padding(.bottom, Space.xxl)
        }
    }

    private var activeJobs: [DownloadJob] { center.jobs.filter(\.state.isActive) }
    private var finishedJobs: [DownloadJob] { center.jobs.filter { !$0.state.isActive } }

    private func jobSection(_ title: String, jobs: [DownloadJob]) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionHeader(title: title, detail: "\(jobs.count)")
            LazyVStack(spacing: Space.s) {
                ForEach(jobs) { job in
                    DownloadJobRow(
                        job: job,
                        isSelected: job.id == selection,
                        onCancel: { center.cancel(job.id) },
                        onReveal: { center.reveal(job) },
                        onOpen: { openFile(of: job) }
                    )
                    .onTapGesture { selection = job.id }
                    .contextMenu { menu(for: job) }
                }
            }
        }
    }

    private func openFile(of job: DownloadJob) {
        guard let file = job.file else { return }
        NSWorkspace.shared.open(file)
    }

    // MARK: Menu

    @ViewBuilder private func menu(for job: DownloadJob) -> some View {
        Button("In Standard-App öffnen") { openFile(of: job) }
            .disabled(job.file == nil || job.state.isActive)
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

    /// The job the toolbar works on: the selected one, else the last job.
    private var focusedJob: DownloadJob? {
        if let selection, let job = center.jobs.first(where: { $0.id == selection }) { return job }
        return center.jobs.last
    }
}

/// One download of the list: 16:9 thumbnail, title, state pill, progress bar,
/// target file and direct inline buttons.
private struct DownloadJobRow: View {
    let job: DownloadJob
    var isSelected = false
    let onCancel: () -> Void
    let onReveal: () -> Void
    let onOpen: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: Space.l) {
            thumbnail
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    VStack(alignment: .leading, spacing: 2) {
                        if !job.displaySubtitle.isEmpty {
                            Text(job.displaySubtitle)
                                .font(AppFont.captionMedium)
                                .foregroundStyle(Palette.accentText)
                                .lineLimit(1)
                        }
                        Text(job.displayTitle)
                            .font(AppFont.heading)
                            .foregroundStyle(Palette.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                    BrandPill(
                        text: statusBadgeText,
                        color: job.state.pillColor,
                        background: job.state.pillBackground)
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

                HStack(spacing: Space.m) {
                    metrics
                    if let file = job.file {
                        Text(AppFormat.displayPath(file))
                            .font(AppFont.caption)
                            .foregroundStyle(Palette.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(file.path(percentEncoded: false))
                    }
                }

                if let message = job.message {
                    Text(message)
                        .font(AppFont.caption)
                        .foregroundStyle(Palette.danger)
                        .lineLimit(2)
                }
            }
            inlineActions
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentCard(selected: isSelected)
    }

    private var statusBadgeText: String {
        if job.state == .loading, let fraction = job.fraction {
            return "\(Int((fraction * 100).rounded())) %"
        }
        return job.state.label
    }

    private var thumbnail: some View {
        Color.clear
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .frame(width: 132)
            .overlay {
                RemoteArt(url: job.thumbnailURL, symbol: "arrow.down.circle")
            }
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: job.state.symbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white, job.state.symbolColor)
                    .padding(6)
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.inner, style: .continuous)
                    .strokeBorder(Palette.divider, lineWidth: 1)
            }
    }

    @ViewBuilder private var inlineActions: some View {
        HStack(spacing: Space.xs) {
            if job.state.isActive {
                IconAction(icon: "xmark", help: "Download abbrechen", action: onCancel)
            } else if job.file != nil {
                IconAction(icon: "play.fill", help: "Datei öffnen", action: onOpen)
                IconAction(icon: "folder", help: "Im Finder zeigen", action: onReveal)
            }
        }
    }

    /// The numbers of the job: the size, the speed and the rest of the time.
    @ViewBuilder private var metrics: some View {
        let parts = metricParts
        if !parts.isEmpty {
            HStack(spacing: Space.s) {
                ForEach(parts, id: \.self) { part in
                    Text(part)
                        .font(AppFont.digits)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
        }
    }

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
