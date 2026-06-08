import Foundation

public enum ConnectivityState: String, Sendable, Codable, CaseIterable {
    case unknown
    case up
    case slow
    case down

    public var localizationKey: String {
        switch self {
        case .unknown: return "status.unknown"
        case .up:      return "status.ok"
        case .slow:    return "status.slow"
        case .down:    return "status.down"
        }
    }
}

public enum IPVersionPreference: String, Sendable, Codable, CaseIterable {
    case auto
    case ipv4
    case ipv6
}

public enum SampleStatus: String, Sendable, Codable {
    case received
    case lost
    case dnsFailure
    case noRoute
    case socketError
}

public struct Sample: Sendable, Codable, Identifiable {
    public let id: UUID
    public let seq: UInt16
    public let sentAt: Date
    public let rttSeconds: Double?
    public let status: SampleStatus
    public let resolvedAddress: String?
    public let ipVersion: IPVersionPreference

    public init(
        id: UUID = UUID(),
        seq: UInt16,
        sentAt: Date,
        rttSeconds: Double?,
        status: SampleStatus,
        resolvedAddress: String?,
        ipVersion: IPVersionPreference
    ) {
        self.id = id
        self.seq = seq
        self.sentAt = sentAt
        self.rttSeconds = rttSeconds
        self.status = status
        self.resolvedAddress = resolvedAddress
        self.ipVersion = ipVersion
    }

    public var rttMs: Double? {
        rttSeconds.map { $0 * 1000.0 }
    }

    public var isSuccess: Bool {
        status == .received && rttSeconds != nil
    }
}

public struct EngineConfig: Sendable, Equatable {
    public var targetHost: String
    public var ipPreference: IPVersionPreference
    public var intervalSeconds: Double
    public var timeoutSeconds: Double
    public var payloadBytes: Int

    public init(
        targetHost: String = "1.1.1.1",
        ipPreference: IPVersionPreference = .auto,
        intervalSeconds: Double = 1.0,
        timeoutSeconds: Double = 2.0,
        payloadBytes: Int = 56
    ) {
        self.targetHost = targetHost
        self.ipPreference = ipPreference
        self.intervalSeconds = intervalSeconds
        self.timeoutSeconds = timeoutSeconds
        self.payloadBytes = payloadBytes
    }
}

public struct ThresholdConfig: Sendable, Equatable {
    public var latencyWarnMs: Double
    public var failureDebounce: Int
    public var recoveryDebounce: Int
    public var rollingWindow: Int
    public var simpleMode: Bool

    public init(
        latencyWarnMs: Double = 300,
        failureDebounce: Int = 2,
        recoveryDebounce: Int = 1,
        rollingWindow: Int = 60,
        simpleMode: Bool = false
    ) {
        self.latencyWarnMs = latencyWarnMs
        self.failureDebounce = failureDebounce
        self.recoveryDebounce = recoveryDebounce
        self.rollingWindow = rollingWindow
        self.simpleMode = simpleMode
    }
}

public struct Preset: Sendable, Equatable {
    public let nameKey: String
    public let engine: EngineConfig
    public let thresholds: ThresholdConfig

    public static let `default` = Preset(
        nameKey: "preset.default",
        engine: EngineConfig(),
        thresholds: ThresholdConfig()
    )

    public static let satellite = Preset(
        nameKey: "preset.satellite",
        engine: EngineConfig(
            targetHost: "1.1.1.1",
            ipPreference: .auto,
            intervalSeconds: 1.0,
            timeoutSeconds: 5.0,
            payloadBytes: 56
        ),
        thresholds: ThresholdConfig(
            latencyWarnMs: 600,
            failureDebounce: 3,
            recoveryDebounce: 1,
            rollingWindow: 60,
            simpleMode: false
        )
    )

    public static let lan = Preset(
        nameKey: "preset.lan",
        engine: EngineConfig(
            targetHost: "1.1.1.1",
            ipPreference: .auto,
            intervalSeconds: 1.0,
            timeoutSeconds: 1.0,
            payloadBytes: 56
        ),
        thresholds: ThresholdConfig(
            latencyWarnMs: 80,
            failureDebounce: 2,
            recoveryDebounce: 1,
            rollingWindow: 60,
            simpleMode: false
        )
    )

    public static let all: [Preset] = [.default, .satellite, .lan]
}

public struct QuickTestResult: Sendable, Equatable {
    public let sent: Int
    public let received: Int
    public let minMs: Double?
    public let avgMs: Double?
    public let maxMs: Double?
    public let jitterMs: Double?
    public let durationSeconds: Double

    public init(sent: Int, received: Int, minMs: Double?, avgMs: Double?, maxMs: Double?, jitterMs: Double?, durationSeconds: Double) {
        self.sent = sent
        self.received = received
        self.minMs = minMs
        self.avgMs = avgMs
        self.maxMs = maxMs
        self.jitterMs = jitterMs
        self.durationSeconds = durationSeconds
    }

    public var lossPercent: Double {
        guard sent > 0 else { return 0 }
        return Double(sent - received) / Double(sent) * 100.0
    }

    public enum Verdict: String, Sendable {
        case excellent, good, fair, poor, broken
    }

    public var verdict: Verdict {
        if received == 0 { return .broken }
        if lossPercent >= 10 { return .poor }
        guard let avg = avgMs else { return .poor }
        if lossPercent == 0 && avg < 50  && (jitterMs ?? 0) < 10  { return .excellent }
        if lossPercent < 2  && avg < 150 && (jitterMs ?? 0) < 50  { return .good }
        if lossPercent < 5  && avg < 300                           { return .fair }
        return .poor
    }
}

public struct StateTransition: Sendable, Identifiable {
    public let id: UUID
    public let at: Date
    public let from: ConnectivityState
    public let to: ConnectivityState
    public let note: String?

    public init(id: UUID = UUID(), at: Date, from: ConnectivityState, to: ConnectivityState, note: String? = nil) {
        self.id = id
        self.at = at
        self.from = from
        self.to = to
        self.note = note
    }
}
