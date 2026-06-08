import Foundation

/// Rolling-window + lifetime statistics over a stream of `Sample`s.
public struct StatsAggregator: Sendable {

    public struct Snapshot: Sendable, Equatable {
        public var rttLastMs: Double?
        public var rttMinMs:  Double?
        public var rttAvgMs:  Double?
        public var rttMaxMs:  Double?
        public var jitterMs:  Double?
        public var lossPercent: Double
        public var uptimePercent: Double
        public var sent: Int
        public var received: Int
        public var lost: Int
        public var windowSize: Int
        public var since: Date

        public static let empty = Snapshot(
            rttLastMs: nil, rttMinMs: nil, rttAvgMs: nil, rttMaxMs: nil,
            jitterMs: nil, lossPercent: 0, uptimePercent: 0,
            sent: 0, received: 0, lost: 0, windowSize: 0, since: Date()
        )
    }

    public var windowCapacity: Int
    private var window: [Sample] = []
    private(set) public var lifetimeSent = 0
    private(set) public var lifetimeReceived = 0
    private(set) public var lifetimeLost = 0
    private(set) public var since = Date()
    // For uptime: count of samples in "up or slow" buckets vs "down".
    private(set) public var lifetimeUp = 0
    private(set) public var lifetimeDown = 0

    public init(windowCapacity: Int = 60) {
        self.windowCapacity = max(1, windowCapacity)
    }

    public mutating func ingest(_ sample: Sample, state: ConnectivityState) {
        lifetimeSent += 1
        if sample.isSuccess { lifetimeReceived += 1 } else { lifetimeLost += 1 }
        if state == .down { lifetimeDown += 1 } else if state == .up || state == .slow { lifetimeUp += 1 }

        window.append(sample)
        if window.count > windowCapacity {
            window.removeFirst(window.count - windowCapacity)
        }
    }

    public mutating func resize(windowCapacity: Int) {
        self.windowCapacity = max(1, windowCapacity)
        if window.count > self.windowCapacity {
            window.removeFirst(window.count - self.windowCapacity)
        }
    }

    public mutating func reset() {
        window.removeAll(keepingCapacity: true)
        lifetimeSent = 0
        lifetimeReceived = 0
        lifetimeLost = 0
        lifetimeUp = 0
        lifetimeDown = 0
        since = Date()
    }

    public func snapshot() -> Snapshot {
        let rttsMs: [Double] = window.compactMap { $0.rttMs }
        let lastMs = window.last?.rttMs
        let minMs = rttsMs.min()
        let maxMs = rttsMs.max()
        let avgMs = rttsMs.isEmpty ? nil : rttsMs.reduce(0, +) / Double(rttsMs.count)

        var jitter: Double? = nil
        if rttsMs.count >= 2 {
            var diffs: [Double] = []
            diffs.reserveCapacity(rttsMs.count - 1)
            for i in 1..<rttsMs.count {
                diffs.append(abs(rttsMs[i] - rttsMs[i-1]))
            }
            jitter = diffs.reduce(0, +) / Double(diffs.count)
        }

        let windowSize = window.count
        let lossWindow = window.filter { !$0.isSuccess }.count
        let lossPct = windowSize == 0 ? 0 : (Double(lossWindow) / Double(windowSize)) * 100.0

        let upDenom = lifetimeUp + lifetimeDown
        let uptime = upDenom == 0 ? 0 : (Double(lifetimeUp) / Double(upDenom)) * 100.0

        return Snapshot(
            rttLastMs: lastMs,
            rttMinMs: minMs,
            rttAvgMs: avgMs,
            rttMaxMs: maxMs,
            jitterMs: jitter,
            lossPercent: lossPct,
            uptimePercent: uptime,
            sent: lifetimeSent,
            received: lifetimeReceived,
            lost: lifetimeLost,
            windowSize: windowSize,
            since: since
        )
    }

    public func windowSamples() -> [Sample] { window }
}
