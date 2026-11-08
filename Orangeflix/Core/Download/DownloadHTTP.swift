import Foundation

/// Parsing of the HTTP headers the downloader relies on (port of the
/// helpers at the end of downloader.go).
enum DownloadHeaders {
    /// The first byte of a Content-Range header ("bytes 100-199/200" → 100).
    static func rangeStart(_ header: String) -> Int64? {
        guard let marker = header.range(of: "bytes ") else { return nil }
        let rest = header[marker.upperBound...]
        guard let dash = rest.firstIndex(of: "-") else { return nil }
        return Int64(rest[..<dash].trimmingCharacters(in: .whitespaces))
    }

    /// The total size of a Content-Range header ("bytes 0-9/10" → 10).
    static func rangeTotal(_ header: String) -> Int64? {
        guard let slash = header.firstIndex(of: "/") else { return nil }
        let rest = header[header.index(after: slash)...].trimmingCharacters(in: .whitespaces)
        let total = rest.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? rest
        return Int64(total.trimmingCharacters(in: .whitespaces))
    }

    /// The size of the whole file, 0 when the server does not announce it.
    /// A partial answer only carries the length of the rest, so the total is
    /// taken from the content range.
    static func contentLength(_ response: HTTPURLResponse) -> Int64 {
        if response.statusCode == 206,
           let range = response.value(forHTTPHeaderField: "Content-Range"),
           let total = rangeTotal(range) {
            return total
        }
        if let raw = response.value(forHTTPHeaderField: "Content-Length"),
           let length = Int64(raw.trimmingCharacters(in: .whitespaces)), length > 0 {
            return length
        }
        return response.expectedContentLength > 0 ? response.expectedContentLength : 0
    }

    /// The checksum the server announces (Content-MD5, else X-Md5) as
    /// lowercase hex; accepts 32 hex digits or base64 of 16 bytes.
    static func expectedChecksum(_ response: HTTPURLResponse) -> String {
        var raw = response.value(forHTTPHeaderField: "Content-MD5") ?? ""
        if raw.isEmpty { raw = response.value(forHTTPHeaderField: "X-Md5") ?? "" }
        return normalizedChecksum(raw)
    }

    /// Normalizes a hex or base64 MD5 to lowercase hex; "" when invalid.
    static func normalizedChecksum(_ value: String) -> String {
        let raw = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return "" }
        if raw.utf8.count == 32, raw.utf8.allSatisfy({ isHexDigit($0) }) {
            return raw.lowercased()
        }
        if let decoded = Data(base64Encoded: raw), decoded.count == 16 {
            return hex(decoded)
        }
        return ""
    }

    static func hex<D: Sequence>(_ bytes: D) -> String where D.Element == UInt8 {
        let digits = Array("0123456789abcdef".utf8)
        var out = [UInt8]()
        for byte in bytes {
            out.append(digits[Int(byte >> 4)])
            out.append(digits[Int(byte & 0x0F)])
        }
        return String(decoding: out, as: UTF8.self)
    }

    private static func isHexDigit(_ c: UInt8) -> Bool {
        (c >= 48 && c <= 57) || (c >= 65 && c <= 70) || (c >= 97 && c <= 102)
    }
}

/// One piece of a running transfer.
enum DownloadChunk: Sendable {
    case response(HTTPURLResponse)
    case data(Data)
}

/// Task delegate that turns one URLSession data task into an async stream of
/// chunks. It applies backpressure: when more than `highWater` bytes wait
/// for the consumer the task is suspended (the socket stops being read) and
/// resumed below `lowWater`, so a slow consumer (speed cap) never buffers
/// the whole file in memory. It also enforces the redirect limit of Go
/// (`MaxRedirects`) and drops the Authorization header on redirects to
/// another host, like Go's client.
final class DownloadTransfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    /// Redirects that are followed (Go fails when 5 requests were made).
    static let maxRedirects = 5
    private static let highWater = 8 << 20
    private static let lowWater = 2 << 20

    let chunks: AsyncThrowingStream<DownloadChunk, any Error>
    private let continuation: AsyncThrowingStream<DownloadChunk, any Error>.Continuation
    private let lock = NSLock()
    private var task: URLSessionDataTask?
    private var buffered = 0
    private var suspended = false
    private var requests = 1
    private var failure: DownloadError?
    private let originalHost: String?

    init(request: URLRequest, session: URLSession) {
        (chunks, continuation) = AsyncThrowingStream.makeStream(of: DownloadChunk.self, throwing: (any Error).self)
        originalHost = request.url?.host()?.lowercased()
        super.init()
        let task = session.dataTask(with: request)
        task.delegate = self
        self.task = task
        continuation.onTermination = { [weak self] _ in self?.cancel() }
        task.resume()
    }

    /// The reason the transfer was stopped by the downloader itself (stall
    /// or redirect limit), nil for a failure of the connection.
    var stopReason: DownloadError? {
        lock.withLock { failure }
    }

    /// Stops the transfer with a reason (the stall watchdog uses it).
    func stop(_ reason: DownloadError) {
        let task = lock.withLock { () -> URLSessionDataTask? in
            if failure == nil { failure = reason }
            return self.task
        }
        task?.cancel()
    }

    func cancel() {
        let task = lock.withLock { self.task }
        task?.cancel()
    }

    /// The consumer processed `count` bytes.
    func consumed(_ count: Int) {
        let resume = lock.withLock { () -> URLSessionDataTask? in
            buffered -= count
            guard suspended, buffered < Self.lowWater else { return nil }
            suspended = false
            return task
        }
        resume?.resume()
    }

    // MARK: URLSessionDataDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse else {
            continuation.finish(throwing: DownloadError.transport("keine HTTP-Antwort"))
            completionHandler(.cancel)
            return
        }
        continuation.yield(.response(http))
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let suspend = lock.withLock { () -> Bool in
            buffered += data.count
            guard !suspended, buffered > Self.highWater else { return false }
            suspended = true
            return true
        }
        continuation.yield(.data(data))
        if suspend { dataTask.suspend() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        let allowed = lock.withLock { () -> Bool in
            if requests >= Self.maxRedirects {
                if failure == nil { failure = .tooManyRedirects }
                return false
            }
            requests += 1
            return true
        }
        guard allowed else {
            completionHandler(nil)
            task.cancel()
            return
        }
        var next = request
        if let host = request.url?.host()?.lowercased(), let original = originalHost,
           host != original, !host.hasSuffix("." + original) {
            next.setValue(nil, forHTTPHeaderField: "Authorization")
        }
        completionHandler(next)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        lock.withLock { self.task = nil }
        if let error {
            continuation.finish(throwing: error)
        } else {
            continuation.finish()
        }
    }
}
