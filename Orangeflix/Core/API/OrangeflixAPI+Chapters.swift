import Foundation

/// The chapter endpoints. A viewer may write the chapters of an episode; the
/// server keeps the suggestion until it is decided.
extension OrangeflixAPI {
    /// The categories a suggested chapter may carry; `magazineID` narrows the
    /// list to one format.
    func chapterCategories(magazineID: Int = 0) async throws -> [ChapterCategory] {
        var query: [(String, String)] = []
        if magazineID > 0 { query.append(("magazineId", String(magazineID))) }
        return try await requestField("categories", as: [ChapterCategory].self, "GET",
                                      "content/chapter-categories", query: query)
    }

    /// The state that is needed to write a chapter suggestion: whether the
    /// account may write one, the revision of the chapters and the suggestion
    /// that is still open.
    func chapterSuggestionContext(clipID: String) async throws -> ChapterSuggestionContext {
        try await request(ChapterSuggestionContext.self, "GET",
                          "content/clips/" + APIHTTP.pathEscape(clipID) + "/chapter-suggestions")
    }

    /// Sends a chapter suggestion: the whole set of chapters and the revision
    /// they are based on. A second suggestion replaces the first one.
    func submitChapterSuggestion(clipID: String, revision: Int64,
                                 chapters: [SuggestedChapterBody]) async throws {
        let body = try APIJSON.encode(ChapterSuggestionBody(revision: revision, chapters: chapters))
        _ = try await requestData("POST",
                                  "content/clips/" + APIHTTP.pathEscape(clipID) + "/chapter-suggestions",
                                  body: body)
    }
}
