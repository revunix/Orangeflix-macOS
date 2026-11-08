import CoreGraphics
import Foundation

/// Frame calculations shared by startup, temporary widening and the return
/// from Live. Growing a window keeps its top-left corner, not its centre.
enum MainWindowFrameLogic {
    static func resizing(_ frame: CGRect, to size: CGSize, in visible: CGRect?) -> CGRect {
        fitting(CGRect(x: frame.minX, y: frame.maxY - size.height,
                       width: size.width, height: size.height), in: visible)
    }

    static func fitting(_ frame: CGRect, in visible: CGRect?) -> CGRect {
        guard let visible else { return frame }
        let width = min(frame.width, visible.width)
        let height = min(frame.height, visible.height)
        return CGRect(x: min(max(frame.minX, visible.minX), visible.maxX - width),
                      y: min(max(frame.maxY - height, visible.minY), visible.maxY - height),
                      width: width, height: height)
    }
}
