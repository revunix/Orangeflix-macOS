import CoreGraphics
import Foundation

/// One exact hover target in the search results' coordinate space.
struct SearchPointerRegion {
    let id: UUID
    let frame: CGRect
}

enum SearchPointerLogic {
    /// Converts from the event view's local coordinates to the search's
    /// coordinate space, even when the view is offset by window chrome.
    static func position(_ local: CGPoint, in sourceFrame: CGRect) -> CGPoint {
        CGPoint(x: local.x + sourceFrame.minX, y: local.y + sourceFrame.minY)
    }

    /// Only a visible target containing the pointer may be active. If targets
    /// overlap, prefer the smaller one rather than activating both.
    static func target(at point: CGPoint?, viewport: CGRect, regions: [SearchPointerRegion]) -> UUID? {
        guard let point, !viewport.isEmpty, viewport.contains(point) else { return nil }
        return regions.filter { !$0.frame.isEmpty && $0.frame.contains(point) }
            .min { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }?.id
    }
}
