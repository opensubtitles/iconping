import Foundation

/// HTTPS download + upload bandwidth tester against Cloudflare's public
/// `__down` / `__up` endpoints. Each phase is time-bounded; chunked progress
/// is reported on the main actor while the transfer runs.
///
/// Empirically established Cloudflare limits (2026):
///   GET  /__down?bytes=N  → HTTP 403 for N >= 100,000,000
///   POST /__up            → no explicit cap; server consumes any body
public final class SpeedTester: NSObject, URLSessionDataDelegate, URLSessionTaskDelegate, @unchecked Sendable {

    public enum Phase: String, Sendable, Equatable {
        case download
        case upload
    }

    public struct Progress: Sendable {
        public let phase: Phase
        public let bytes: Int
        public let mbpsLive: Double
        public let elapsedSeconds: Double
    }

    public static let downloadURL = URL(string: "https://speed.cloudflare.com/__down?bytes=90000000")!
    public static let uploadURL   = URL(string: "https://speed.cloudflare.com/__up")!
    public static let serverHost  = "speed.cloudflare.com"

    /// 50 MB of zeros (created once, reused across uploads). For typical
    /// residential uplinks the time cap fires long before this is consumed.
    public static let uploadBody: Data = Data(count: 50_000_000)

    private let timeLimit: TimeInterval
    private let onProgress: (@MainActor (Progress) -> Void)?

    private var phase: Phase = .download
    private var bytesObserved: Int = 0
    private var startTime: Date = Date()
    private var lastReport: Date = Date()
    private var session: URLSession?
    private var continuation: CheckedContinuation<PhaseResult, Never>?
    private var cancelled = false

    public init(timeLimit: TimeInterval = 8.0, onProgress: (@MainActor (Progress) -> Void)? = nil) {
        self.timeLimit = timeLimit
        self.onProgress = onProgress
    }

    /// Runs the download phase. Streams bytes via dataTask delegate, cancels
    /// either when `timeLimit` elapses or when the server closes the connection.
    public func runDownload() async -> PhaseResult {
        await startPhase(.download) { session in
            var req = URLRequest(url: Self.downloadURL)
            req.httpMethod = "GET"
            return session.dataTask(with: req)
        }
    }

    /// Runs the upload phase. POSTs `uploadBody` and tracks didSendBodyData
    /// progress. Cancels at `timeLimit` even mid-upload.
    public func runUpload() async -> PhaseResult {
        await startPhase(.upload) { session in
            var req = URLRequest(url: Self.uploadURL)
            req.httpMethod = "POST"
            req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            return session.uploadTask(with: req, from: Self.uploadBody)
        }
    }

    /// Cancel whichever phase is currently running.
    public func stop() {
        cancelled = true
        session?.invalidateAndCancel()
    }

    // MARK: - Phase plumbing

    private func startPhase(_ phase: Phase, taskBuilder: @escaping (URLSession) -> URLSessionTask) async -> PhaseResult {
        await withCheckedContinuation { (cont: CheckedContinuation<PhaseResult, Never>) in
            self.continuation = cont
            self.phase = phase
            self.bytesObserved = 0
            self.startTime = Date()
            self.lastReport = self.startTime
            self.cancelled = false

            let config = URLSessionConfiguration.ephemeral
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            config.timeoutIntervalForRequest  = timeLimit + 5
            config.timeoutIntervalForResource = timeLimit + 15
            config.httpAdditionalHeaders = ["User-Agent": "IconPing/1.0 (speed-test)"]
            let s = URLSession(configuration: config, delegate: self, delegateQueue: nil)
            self.session = s

            taskBuilder(s).resume()
        }
    }

    private func reportProgress() {
        let now = Date()
        if now.timeIntervalSince(lastReport) <= 0.1 { return }
        lastReport = now
        let elapsed = now.timeIntervalSince(startTime)
        let mbpsLive = elapsed > 0 ? Double(bytesObserved) * 8.0 / (elapsed * 1_000_000) : 0
        let snap = Progress(phase: phase, bytes: bytesObserved, mbpsLive: mbpsLive, elapsedSeconds: elapsed)
        Task { @MainActor [weak self] in
            self?.onProgress?(snap)
        }
    }

    private func enforceTimeLimit(_ task: URLSessionTask) {
        if Date().timeIntervalSince(startTime) >= timeLimit {
            cancelled = false  // natural test end, not a user cancel
            task.cancel()
        }
    }

    // MARK: - Download progress (URLSessionDataDelegate)

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                           didReceive response: URLResponse,
                           completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            NSLog("IconPing speedtest: server returned HTTP \(http.statusCode) for \(phase.rawValue)")
            cancelled = false
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        bytesObserved += data.count
        reportProgress()
        enforceTimeLimit(dataTask)
    }

    // MARK: - Upload progress (URLSessionTaskDelegate)

    public func urlSession(_ session: URLSession, task: URLSessionTask,
                           didSendBodyData bytesSent: Int64,
                           totalBytesSent: Int64,
                           totalBytesExpectedToSend: Int64) {
        bytesObserved = Int(totalBytesSent)
        reportProgress()
        enforceTimeLimit(task)
    }

    // MARK: - Phase completion

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let elapsed = Date().timeIntervalSince(startTime)
        let mbps = elapsed > 0 ? Double(bytesObserved) * 8.0 / (elapsed * 1_000_000) : 0

        var realError: String? = nil
        if let nsError = error as NSError? {
            if nsError.code == NSURLErrorCancelled {
                realError = cancelled ? "Cancelled" : nil
            } else {
                realError = nsError.localizedDescription
                NSLog("IconPing speedtest \(phase.rawValue): URLSession error code=\(nsError.code) msg=\(nsError.localizedDescription)")
            }
        }

        let result = PhaseResult(
            mbps: mbps,
            bytes: bytesObserved,
            durationSeconds: elapsed,
            errorDescription: realError
        )
        continuation?.resume(returning: result)
        continuation = nil
        session.invalidateAndCancel()
        self.session = nil
    }
}
