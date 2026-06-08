import Foundation

/// Classifies a stream of samples into a `ConnectivityState` with debounce
/// (hysteresis). Pure logic, no side effects, fully testable.
public struct StateMachine: Sendable {

    public private(set) var state: ConnectivityState = .unknown
    public private(set) var consecutiveFailures: Int = 0
    public private(set) var consecutiveSuccesses: Int = 0
    /// Consecutive samples whose RTT is at or above the slow threshold.
    public private(set) var consecutiveSlow: Int = 0
    /// Consecutive samples whose RTT is below the slow threshold.
    public private(set) var consecutiveFast: Int = 0

    /// Need this many consecutive slow / fast samples to flip the slow/up state.
    /// Larger than failureDebounce since "slow" is a softer signal than "down"
    /// and a single jittery sample shouldn't visibly change the icon.
    private let slowDebounce = 3

    public var thresholds: ThresholdConfig

    public init(thresholds: ThresholdConfig = ThresholdConfig()) {
        self.thresholds = thresholds
    }

    /// Feed one sample. Returns the resulting state, plus a transition record
    /// if the state changed. Slow/up classification uses the sample's own RTT
    /// (debounced), not a rolling average — that way one cold-start ping can't
    /// drag the icon to "slow" for the next minute.
    @discardableResult
    public mutating func ingest(sample: Sample) -> (state: ConnectivityState, transition: StateTransition?) {
        if sample.isSuccess {
            consecutiveFailures = 0
            consecutiveSuccesses += 1
            if let ms = sample.rttMs {
                if ms >= thresholds.latencyWarnMs {
                    consecutiveSlow += 1
                    consecutiveFast = 0
                } else {
                    consecutiveFast += 1
                    consecutiveSlow = 0
                }
            }
        } else {
            consecutiveSuccesses = 0
            consecutiveFailures += 1
            // A lost sample isn't a fast or slow data point — leave both counters.
        }

        let newState = classify()
        if newState != state {
            let trans = StateTransition(at: Date(), from: state, to: newState, note: nil)
            state = newState
            return (newState, trans)
        }
        return (newState, nil)
    }

    private func classify() -> ConnectivityState {
        let needFailures = max(1, thresholds.failureDebounce)
        let needRecover  = max(1, thresholds.recoveryDebounce)

        switch state {
        case .unknown:
            if consecutiveFailures >= needFailures { return .down }
            if consecutiveSuccesses >= 1 {
                return slowOrUp(isFirstTransition: true)
            }
            return .unknown

        case .up:
            if consecutiveFailures >= needFailures { return .down }
            if !thresholds.simpleMode && consecutiveSlow >= slowDebounce { return .slow }
            return .up

        case .slow:
            if consecutiveFailures >= needFailures { return .down }
            if thresholds.simpleMode { return .up }
            if consecutiveFast >= slowDebounce { return .up }
            return .slow

        case .down:
            if consecutiveSuccesses >= needRecover {
                return slowOrUp(isFirstTransition: true)
            }
            return .down
        }
    }

    private func slowOrUp(isFirstTransition: Bool) -> ConnectivityState {
        if thresholds.simpleMode { return .up }
        // On the very first transition out of unknown/down, allow a single slow
        // sample to land in .slow so the user sees the truth — but later it
        // requires the full debounce, courtesy of the .up/.slow branch above.
        if consecutiveSlow >= (isFirstTransition ? 1 : slowDebounce) { return .slow }
        return .up
    }

    /// External reset (e.g. network path change).
    public mutating func reset(to newState: ConnectivityState = .unknown) {
        state = newState
        consecutiveFailures = 0
        consecutiveSuccesses = 0
        consecutiveSlow = 0
        consecutiveFast = 0
    }
}
