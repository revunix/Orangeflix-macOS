import CoreGraphics

/// The scroll rules of the chat list. They are free of the view, so the
/// tests can check them without a window.
enum LiveChatScroll {
    /// How far above the newest line the reader may stand and still count as
    /// being at the bottom.
    static let bottomTolerance: CGFloat = 24

    /// What the list does after a scroll or a change of its size.
    enum Action: Equatable {
        /// At the bottom, or nothing to scroll: the list follows again.
        case follow
        /// The reader scrolled up: the list stays where it is.
        case pause
        /// The list grew while it follows: it stays on the newest line.
        case pin
        /// Nothing to change.
        case keep
    }

    static func action(from old: ChatScrollMetrics, to new: ChatScrollMetrics, following: Bool) -> Action {
        let overflows = new.content > new.container + 1
        let distance = new.content - new.visibleMaxY
        if !overflows || distance <= bottomTolerance { return .follow }
        let sameSize = abs(new.content - old.content) < 0.5 && abs(new.container - old.container) < 0.5
        if sameSize, new.offset < old.offset - 0.5 { return .pause }
        if following, !sameSize { return .pin }
        return .keep
    }

    /// The newest `added` lines: the ones that came since the last count. The
    /// history cap can drop older lines, so never more than the list holds.
    static func fresh<Line>(_ lines: [Line], added: Int) -> ArraySlice<Line> {
        lines.suffix(max(0, min(added, lines.count)))
    }
}

/// What the chat list needs to know of its scroll position.
struct ChatScrollMetrics: Equatable {
    var offset: CGFloat
    var content: CGFloat
    var container: CGFloat
    var visibleMaxY: CGFloat
}
