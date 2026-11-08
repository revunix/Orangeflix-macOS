import Foundation

/// A notification observer token that may be removed from any context. The
/// token of `NotificationCenter` is not `Sendable`, so it is wrapped here to
/// keep it out of a nonisolated `deinit`.
final class NotificationToken: @unchecked Sendable {
    private let token: NSObjectProtocol

    init(_ token: NSObjectProtocol) {
        self.token = token
    }

    /// Removes the observer.
    func remove() {
        NotificationCenter.default.removeObserver(token)
    }
}
