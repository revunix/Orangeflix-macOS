import Foundation
import Testing
@testable import OrangeflixLogic

@Suite("Main window frame")
struct MainWindowFrameTests {
    let screen = CGRect(x: 0, y: 0, width: 1920, height: 1200)

    @Test("widening preserves the top-left corner")
    func widening() {
        let before = CGRect(x: 100, y: 150, width: 1000, height: 1000)
        let result = MainWindowFrameLogic.resizing(before, to: CGSize(width: 1400, height: 800), in: screen)
        #expect(result.minX == before.minX)
        #expect(result.maxY == before.maxY)
    }

    @Test("returning from Live restores the saved frame without drift")
    func repeatedSwitches() {
        let saved = CGRect(x: 750, y: 100, width: 1100, height: 1000)
        for _ in 0..<20 {
            let live = MainWindowFrameLogic.resizing(saved, to: CGSize(width: 1500, height: 900), in: screen)
            #expect(live.maxX <= screen.maxX)
            #expect(MainWindowFrameLogic.fitting(saved, in: screen) == saved)
        }
    }

    @Test("a frame is brought onto a smaller or relocated display")
    func changedDisplay() {
        let visible = CGRect(x: -1440, y: 80, width: 1440, height: 900)
        let saved = CGRect(x: 750, y: 100, width: 1600, height: 1000)
        #expect(MainWindowFrameLogic.fitting(saved, in: visible) == visible)
    }

    @Test("without screen information the saved frame is unchanged")
    func noScreen() {
        let saved = CGRect(x: -100, y: 40, width: 1240, height: 1000)
        #expect(MainWindowFrameLogic.fitting(saved, in: nil) == saved)
    }
}
