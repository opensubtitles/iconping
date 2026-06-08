import Foundation

/// Classifies a stream of samples into a `ConnectivityState` with debounce
/// (hysteresis). Pure logic, no side effects, fully testable.
public struct StateMachine: Sendable {

    public private(set) var state: ConnectivityState = .unknown
    public private(set) var consecutiveFailures: Int = 0
    public private(set) var consecutiveSuccesses: Int = 0

    public var thresholds: ThresholdConfig

    public init(thresholds: ThresholdConfig = ThresholdConfig()) {
        self.thresholds = thresholds
    }

    /// Feed one sample plus the rolling RTT average (computed elsewhere).
    /// Returns the resulting state, plus a transition record if the state changed.
    @discardableResult
    public mutating func ingest(sample: Sample, rollingAvgMs: Double?) -> (state: ConnectivityState, transition: StateTransition?) {
        if sample.isSuccess {
            consecutiveFailures = 0
            consecutiveSuccesses += 1
        } else {
            consecutiveSuccesses = 0
            consecutiveFailures += 1
        }

        let newState = classify(rollingAvgMs: rollingAvgMs)
        if newState != state {
            let trans = StateTransition(at: Date(), from: state, to: newState, note: nil)
            state = newState
            return (newState, trans)
        }
        return (newState, nil)
    }

    private func classify(rollingAvgMs: Double?) -> ConnectivityState {
        let needFailures = max(1, thresholds.failureDebounce)
        let needRecover  = max(1, thresholds.recoveryDebounce)

        switch state {
        case .unknown:
            if consecutiveFailures >= needFailures { return .down }
            if consecutiveSuccesses >= 1 {
                return slowOrUp(avg: rollingAvgMs)
            }
            return .unknown

        case .up, .slow:
            if consecutiveFailures >= needFailures { return .down }
            return slowOrUp(avg: rollingAvgMs)

        case .down:
            if consecutiveSuccesses >= needRecover {
                return slowOrUp(avg: rollingAvgMs)
            }
            return .down
        }
    }

    private func slowOrUp(avg: Double?) -> ConnectivityState {
        if thresholds.simpleMode { return .up }
        if let avg, avg >= thresholds.latencyWarnMs { return .slow }
        return .up
    }

    /// External reset (e.g. network path change).
    public mutating func reset(to newState: ConnectivityState = .unknown) {
        state = newState
        consecutiveFailures = 0
        consecutiveSuccesses = 0
    }
}
