import Foundation

/// One-shot HTTPS download bandwidth test. Streams from a known speed-test
/// endpoint (default: Cloudflare's `__down`), tallies bytes via a
/// URLSessionDataDelegate (chunked, not byte-at-a-time), and either runs to
/// completion or cancels after `timeLimitSeconds`. Throttled progress callbacks
/// on the main actor while it runs.
///
/// Cloudflare's endpoint is unauthenticated, anycast-routed, and serves the
/// requested byte count from the nearest PoP — appropriate for a quick check.
public final class SpeedTester: NSObject, URLSessionDataDelegate, @unchecked Sendable {

    public enum Server: Sendable {
        case cloudflare
        case custom(url: URL, host: String)

        var url: URL {
            switch self {
            case .cloudflare:
                // Cloudflare's __down endpoint rejects (HTTP 403) any request
                // asking for >= 100,000,000 bytes. We use 90 MB so the time
                // limit (default 8s) is what bounds the actual data transferred,
                // not the ceiling — even on gigabit links the test is
                // duration-limited rather than size-limited.
                return URL(string: "https://speed.cloudflare.com/__down?bytes=90000000")!
            case .custom(let url, _): return url
            }
        }
        var host: String {
            switch self {
            case .cloudflare:      return "speed.cloudflare.com"
            case .custom(_, let h): return h
            }
        }
    }

    public struct Progress: Sendable {
        public let bytesReceived: Int
        public let mbpsLive: Double
        public let elapsedSeconds: Double
    }

    private let timeLimit: TimeInterval
    private let onProgress: (@MainActor (Progress) -> Void)?

    private var bytesReceived: Int = 0
    private var startTime: Date = Date()
    private var lastReport: Date = Date()
    private var session: URLSession?
    private var continuation: CheckedContinuation<SpeedTestResult, Never>?
    private var serverHost: String = ""
    private var cancelled = false

    public init(timeLimit: TimeInterval = 8.0, onProgress: (@MainActor (Progress) -> Void)? = nil) {
        self.timeLimit = timeLimit
        self.onProgress = onProgress
    }

    /// Runs the test once. Returns whatever bytes were transferred when the
    /// timer expired or the connection closed naturally. Never throws — errors
    /// surface as `result.errorDescription` and a `.broken` verdict.
    public func run(server: Server = .cloudflare) async -> SpeedTestResult {
        await withCheckedContinuation { (cont: CheckedContinuation<SpeedTestResult, Never>) in
            self.continuation = cont
            self.serverHost = server.host
            self.startTime = Date()
            self.lastReport = self.startTime
            self.bytesReceived = 0
            self.cancelled = false

            let config = URLSessionConfiguration.ephemeral
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            config.timeoutIntervalForRequest = timeLimit + 5
            config.timeoutIntervalForResource = timeLimit + 10
            config.httpAdditionalHeaders = ["User-Agent": "IconPing/1.0 (speed-test)"]
            let s = URLSession(configuration: config, delegate: self, delegateQueue: nil)
            self.session = s

            var req = URLRequest(url: server.url)
            req.httpMethod = "GET"
            s.dataTask(with: req).resume()
        }
    }

    /// Mid-test cancel.
    public func stop() {
        cancelled = true
        session?.invalidateAndCancel()
    }

    // MARK: - URLSessionDataDelegate

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                           didReceive response: URLResponse,
                           completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        // Surface a non-2xx response as a fatal error and cancel the transfer.
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            NSLog("IconPing speedtest: server returned HTTP \(http.statusCode)")
            cancelled = false
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        bytesReceived += data.count
        let now = Date()
        let elapsed = now.timeIntervalSince(startTime)

        // Throttle progress callbacks to ~10 Hz
        if now.timeIntervalSince(lastReport) > 0.1 {
            lastReport = now
            let mbpsLive = elapsed > 0 ? Double(bytesReceived) * 8.0 / (elapsed * 1_000_000) : 0
            let snap = Progress(bytesReceived: bytesReceived, mbpsLive: mbpsLive, elapsedSeconds: elapsed)
            Task { @MainActor [weak self] in
                self?.onProgress?(snap)
            }
        }

        if elapsed >= timeLimit {
            cancelled = false  // not a user cancel — natural test end
            dataTask.cancel()
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let elapsed = Date().timeIntervalSince(startTime)
        let mbps = elapsed > 0 ? Double(bytesReceived) * 8.0 / (elapsed * 1_000_000) : 0

        // Treat our own time-limit cancellation as a clean finish.
        var realError: String? = nil
        if let nsError = error as NSError? {
            if nsError.code == NSURLErrorCancelled {
                realError = cancelled ? "Cancelled" : nil
            } else {
                realError = nsError.localizedDescription
                NSLog("IconPing speedtest: URLSession error code=\(nsError.code) domain=\(nsError.domain) msg=\(nsError.localizedDescription) userInfo=\(nsError.userInfo)")
            }
        }
        if bytesReceived == 0 && realError == nil {
            NSLog("IconPing speedtest: completed with zero bytes, no error — likely empty response")
        }

        let result = SpeedTestResult(
            mbps: mbps,
            bytesReceived: bytesReceived,
            durationSeconds: elapsed,
            serverHost: serverHost,
            errorDescription: realError
        )
        continuation?.resume(returning: result)
        continuation = nil
        session.invalidateAndCancel()
        self.session = nil
    }
}
