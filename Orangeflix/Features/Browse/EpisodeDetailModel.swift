import Foundation
import Observation

/// The data of the page of one episode: the clip page of the API and what
/// the playback answer adds (the heat map, the stored position).
@MainActor @Observable final class EpisodeDetailModel {
    let identifier: String
    private(set) var details: EpisodeDetails?
    private(set) var insights: PlaybackInsights?
    private(set) var isLoading = false
    private(set) var error: String?

    /// The state of the chapter suggestions: whether the account may write
    /// one, the revision of the chapters and its own open suggestion.
    private(set) var chapterContext: ChapterSuggestionContext?
    /// The categories a suggested chapter may carry.
    private(set) var chapterCategories: [ChapterCategory] = []
    /// Whether a suggestion is being sent.
    private(set) var isSendingChapters = false

    init(identifier: String) {
        self.identifier = identifier
    }

    /// Loads both answers side by side. The heat map is extra: without it
    /// the page stays complete.
    func load(app: AppModel, force: Bool = false) async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await app.ensureSession()
        } catch {
            if !(error is CancellationError) { self.error = error.localizedDescription }
            return
        }
        let api = app.services.api
        let identifier = identifier
        async let page = api.episodeDetails(identifier, refresh: force)
        async let extra = api.playbackInsights(identifier)
        async let chapters = api.chapterSuggestionContext(clipID: identifier)
        do {
            details = try await page
            error = nil
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
        insights = try? await extra
        chapterContext = try? await chapters
        if chapterContext != nil {
            chapterCategories = (try? await api.chapterCategories()) ?? []
        }
    }

    /// The chapters the suggestion starts from: the open suggestion of the
    /// account, else the chapters of the episode.
    var suggestedChapters: [SuggestedChapter] {
        if let open = chapterContext?.openSuggestion, !open.chapters.isEmpty {
            return open.chapters
        }
        return chapterContext?.chapters ?? []
    }

    /// Sends the chapters of the account to the server.
    func sendChapterSuggestion(app: AppModel, chapters: [SuggestedChapterBody]) async {
        guard let context = chapterContext, !isSendingChapters else { return }
        isSendingChapters = true
        defer { isSendingChapters = false }
        do {
            try await app.services.api.submitChapterSuggestion(
                clipID: identifier, revision: Int64(context.revision), chapters: chapters)
            app.show("Die Kapitel sind eingeschickt.")
            await load(app: app)
        } catch is CancellationError {
            return
        } catch {
            app.show(error.localizedDescription, error: true)
            // The chapters of the episode may have changed; read them again.
            chapterContext = try? await app.services.api.chapterSuggestionContext(clipID: identifier)
        }
    }
}

/// The pure parts of the page of an episode.
enum EpisodeDetailLogic {
    /// The address of a picture the API names with a path ("/img/faces/…").
    static func imageURL(_ path: String) -> String {
        guard !path.isEmpty, !path.hasPrefix("http") else { return path }
        return "https://massengeschmack.tv" + (path.hasPrefix("/") ? path : "/" + path)
    }

    /// The most watched places of the episode in seconds, the strongest
    /// first. Viewers fall away over the length of every episode, so a place
    /// counts by how far it rises above its neighbourhood, not by its height;
    /// the first moments, where everybody starts, are left out. Two places
    /// lie at least a tenth of the episode apart; a flat map has none.
    static func peaks(_ heatmap: [Double], duration: Int, count: Int = 3) -> [Int] {
        let total = heatmap.count
        guard total > 1, duration > 0 else { return [] }
        let reach = max(total / 20, 2)
        let start = max(total / 50, 1)
        let spacing = max(total / 10, 1)
        let rises: [(index: Int, rise: Double)] = (start..<total).map { index in
            let around = (max(0, index - reach)...min(total - 1, index + reach)).filter { $0 != index }
            let mean = around.map { heatmap[$0] }.reduce(0, +) / Double(around.count)
            return (index, heatmap[index] - mean)
        }
        var chosen: [Int] = []
        for candidate in rises.sorted(by: { $0.rise > $1.rise }) {
            // Two hundredths of the viewers are the least worth naming.
            guard chosen.count < count, candidate.rise >= 0.02 else { break }
            if chosen.allSatisfy({ abs($0 - candidate.index) >= spacing }) { chosen.append(candidate.index) }
        }
        let bucket = Double(duration) / Double(total)
        return chosen.map { Int((Double($0) * bucket).rounded()) }
    }

    /// The length of a chapter as "12 min" or "45 s".
    static func length(_ chapter: PlaybackChapter) -> String {
        let seconds = max(Int(chapter.end - chapter.start), 0)
        guard seconds > 0 else { return "" }
        return seconds >= 60 ? "\(Int((Double(seconds) / 60).rounded())) min" : "\(seconds) s"
    }
}
