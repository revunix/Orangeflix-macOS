import CoreGraphics
import Testing
@testable import OrangeflixLogic

@Suite("Live chat scrolling")
struct LiveChatScrollTests {
    /// A list of 400 pt that shows the part from `offset` on.
    private func metrics(offset: CGFloat, content: CGFloat = 1000, container: CGFloat = 400) -> ChatScrollMetrics {
        ChatScrollMetrics(offset: offset, content: content, container: container,
                          visibleMaxY: offset + container)
    }

    @Test("a list that fits has nothing to scroll and follows")
    func shortList() {
        let short = metrics(offset: 0, content: 300, container: 400)
        #expect(LiveChatScroll.action(from: short, to: short, following: false) == .follow)
    }

    @Test("reaching the bottom lets the chat follow again")
    func bottom() {
        let old = metrics(offset: 100)
        let new = metrics(offset: 590)
        #expect(LiveChatScroll.action(from: old, to: new, following: false) == .follow)
    }

    @Test("scrolling up with the same size pauses the chat")
    func scrollUp() {
        let old = metrics(offset: 600)
        let new = metrics(offset: 300)
        #expect(LiveChatScroll.action(from: old, to: new, following: true) == .pause)
    }

    @Test("a list that grows while following stays on its newest line")
    func growingPins() {
        let old = metrics(offset: 600, content: 1000)
        let new = metrics(offset: 600, content: 1100)
        #expect(LiveChatScroll.action(from: old, to: new, following: true) == .pin)
    }

    @Test("a list that grows while the reader is up keeps its place")
    func growingKeeps() {
        let old = metrics(offset: 300, content: 1000)
        let new = metrics(offset: 300, content: 1100)
        #expect(LiveChatScroll.action(from: old, to: new, following: false) == .keep)
    }

    @Test("an offset drop with a change of size does not pause the chat")
    func resizeIsNotAScroll() {
        let old = metrics(offset: 600, content: 1000)
        let new = metrics(offset: 500, content: 1100)
        #expect(LiveChatScroll.action(from: old, to: new, following: true) == .pin)
    }

    @Test("fresh lines are the newest ones, never more than the list holds")
    func freshLines() {
        let lines = [1, 2, 3, 4, 5]
        #expect(Array(LiveChatScroll.fresh(lines, added: 2)) == [4, 5])
        #expect(Array(LiveChatScroll.fresh(lines, added: 9)) == lines)
        #expect(LiveChatScroll.fresh(lines, added: 0).isEmpty)
        #expect(LiveChatScroll.fresh(lines, added: -3).isEmpty)
    }
}
