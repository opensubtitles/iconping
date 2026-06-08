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

/// Result of one phase (download or upload) of a bandwidth speed test.
public struct PhaseResult: Sendable, Equatable {
    public let mbps: Double
    public let bytes: Int
    public let durationSeconds: Double
    public let errorDescription: String?

    public init(mbps: Double, bytes: Int, durationSeconds: Double, errorDescription: String? = nil) {
        self.mbps = mbps
        self.bytes = bytes
        self.durationSeconds = durationSeconds
        self.errorDescription = errorDescription
    }

    public static let pending = PhaseResult(mbps: 0, bytes: 0, durationSeconds: 0, errorDescription: nil)

    public var megabytes: Double { Double(bytes) / (1024.0 * 1024.0) }
}

/// Full speed-test result combining a download phase and an upload phase.
public struct SpeedTestResult: Sendable, Equatable {
    public let download: PhaseResult
    public let upload: PhaseResult
    public let serverHost: String

    public init(download: PhaseResult, upload: PhaseResult, serverHost: String) {
        self.download = download
        self.upload = upload
        self.serverHost = serverHost
    }

    public enum Verdict: String, Sendable {
        case excellent, good, fair, poor, broken
    }

    /// Verdict is keyed off the *download* number — that's what people mean by
    /// "fast internet" colloquially. Upload number is shown but doesn't drive
    /// the color/icon.
    public var verdict: Verdict {
        if download.errorDescription != nil { return .broken }
        let m = download.mbps
        if m < 1     { return .broken }
        if m >= 100  { return .excellent }
        if m >= 25   { return .good }
        if m >= 5    { return .fair }
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
