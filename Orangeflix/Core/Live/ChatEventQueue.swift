import os

/// The bounded event buffer of a chat session. It never blocks the socket
/// reader: when the interface falls behind, a status, error or poll event is
/// dropped, while a message or reaction takes the place of the oldest event,
/// so a full queue does not swallow the chat. One consumer reads it.
final class ChatEventQueue: Sendable {
    private struct State: Sendable {
        var buffer: [ChatEvent] = []
        var head = 0
        var waiter: CheckedContinuation<ChatEvent?, Never>?
        var finished = false

        var count: Int { buffer.count - head }

        mutating func popFirst() -> ChatEvent? {
            guard head < buffer.count else { return nil }
            let event = buffer[head]
            head += 1
            if head > 256 && head * 2 > buffer.count {
                buffer.removeFirst(head)
                head = 0
            }
            return event
        }
    }

    /// How many events wait at most.
    let capacity: Int
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(capacity: Int = 1024) {
        self.capacity = max(1, capacity)
    }

    /// Hands one event to the consumer without blocking.
    func push(_ event: ChatEvent) {
        let resume: (CheckedContinuation<ChatEvent?, Never>, ChatEvent)? = state.withLock { state in
            if state.finished { return nil }
            if let waiter = state.waiter {
                state.waiter = nil
                return (waiter, event)
            }
            if state.count < capacity {
                state.buffer.append(event)
                return nil
            }
            switch event {
            case .message, .reactions, .reactionChanged:
                _ = state.popFirst()
                state.buffer.append(event)
            default:
                break
            }
            return nil
        }
        if let (waiter, event) = resume { waiter.resume(returning: event) }
    }

    /// Ends the queue; the consumer reads what is left, then nil.
    func finish() {
        let waiter: CheckedContinuation<ChatEvent?, Never>? = state.withLock { state in
            state.finished = true
            defer { state.waiter = nil }
            return state.waiter
        }
        waiter?.resume(returning: nil)
    }

    /// The next event; nil once the queue is finished and empty or the
    /// reading task is cancelled.
    func next() async -> ChatEvent? {
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<ChatEvent?, Never>) in
                let immediate: ChatEvent?? = state.withLock { state in
                    if let event = state.popFirst() { return .some(event) }
                    if state.finished || Task.isCancelled { return .some(nil) }
                    // A second reader would strand the first one; it ends.
                    state.waiter?.resume(returning: nil)
                    state.waiter = continuation
                    return nil
                }
                if let immediate { continuation.resume(returning: immediate) }
            }
        } onCancel: {
            let waiter = state.withLock { state in
                defer { state.waiter = nil }
                return state.waiter
            }
            waiter?.resume(returning: nil)
        }
    }
}
