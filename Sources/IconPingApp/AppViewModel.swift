import Foundation
import SwiftUI
import Combine
import IconPingCore

@MainActor
final class AppViewModel: ObservableObject {

    // Published UI state
    @Published var state: ConnectivityState = .unknown
    @Published var snapshot: StatsAggregator.Snapshot = .empty
    @Published var recentSamples: [Sample] = []
    @Published var pathInfo: NetworkPathMonitor.Info?
    @Published var transitions: [StateTransition] = []
    @Published var resolvedAddress: String = "-"
    @Published var ipVersionInUse: IPVersionPreference = .auto
    @Published var paused: Bool = false
    @Published var lastErrorStatus: SampleStatus? = nil

    enum SpeedTestState: Equatable {
        case idle
        case running(bytes: Int, mbpsLive: Double, elapsed: Double)
        case finished(SpeedTestResult)
    }
    @Published var speedTestState: SpeedTestState = .idle
    private var speedTester: SpeedTester?
    private var speedTask: Task<Void, Never>?

    // Settings-bound config
    @Published var engineConfig: EngineConfig
    @Published var thresholds: ThresholdConfig

    private let engine: PingEngine
    private var stateMachine = StateMachine()
    private var stats = StatsAggregator()
    private let pathMonitor = NetworkPathMonitor()
    private var consumeTask: Task<Void, Never>?
    private var pathTask: Task<Void, Never>?
    private var configBag = Set<AnyCancellable>()

    private let prefs = Preferences.shared

    init() {
        let cfg = prefs.engineConfig
        let th  = prefs.thresholds
        self.engineConfig = cfg
        self.thresholds   = th
        self.engine = PingEngine(config: cfg)
        self.stateMachine.thresholds = th
        self.stats.windowCapacity = th.rollingWindow
        observeConfig()
    }

    func start() {
        Task { [weak self] in
            guard let self else { return }
            await self.engine.start()
            let s = await self.engine.samples()
            self.consumeTask = Task { [weak self] in
                guard let self else { return }
                for await sample in s {
                    await self.handle(sample)
                }
            }
        }
        pathTask = Task { [weak self] in
            guard let self else { return }
            let stream = self.pathMonitor.start()
            for await info in stream {
                await MainActor.run {
                    self.pathInfo = info
                }
                // Reset transient state on path change
                await MainActor.run {
                    self.stateMachine.reset()
                    self.stats.reset()
                    self.recentSamples.removeAll()
                    self.appendTransition(from: self.state, to: .unknown, note: "path.changed")
                    self.state = .unknown
                }
            }
        }
    }

    func stop() {
        consumeTask?.cancel()
        pathTask?.cancel()
        Task { await engine.stop() }
    }

    private func handle(_ sample: Sample) async {
        let prev = state
        let result = stateMachine.ingest(sample: sample)

        await MainActor.run {
            self.stats.ingest(sample, state: result.state)
            self.snapshot = self.stats.snapshot()
            self.recentSamples = self.stats.windowSamples()
            self.state = result.state
            self.resolvedAddress = sample.resolvedAddress ?? self.resolvedAddress
            self.ipVersionInUse = sample.ipVersion

            // Track persistent failure types so the UI can show a useful reason.
            switch sample.status {
            case .received:
                self.lastErrorStatus = nil
            case .lost:
                // 'lost' alone is ambiguous (timeout, not a hard error) — only set
                // it when the state machine actually crossed into .down.
                if result.state == .down { self.lastErrorStatus = .lost }
            case .dnsFailure, .socketError, .noRoute:
                self.lastErrorStatus = sample.status
            }

            if let t = result.transition {
                self.transitions.insert(t, at: 0)
                if self.transitions.count > 500 { self.transitions.removeLast(self.transitions.count - 500) }

                NotificationService.shared.notifyTransition(
                    from: prev,
                    to: t.to,
                    throttleSeconds: UserDefaults.standard.integer(forKey: Preferences.Key.notifyThrottle.rawValue),
                    withSound: UserDefaults.standard.bool(forKey: Preferences.Key.notifySound.rawValue),
                    notifyDown: UserDefaults.standard.bool(forKey: Preferences.Key.notifyOnDown.rawValue),
                    notifyUp: UserDefaults.standard.bool(forKey: Preferences.Key.notifyOnUp.rawValue)
                )
            }
        }
    }

    // MARK: - actions

    func resetStats() {
        stats.reset()
        recentSamples.removeAll()
        snapshot = stats.snapshot()
        transitions.removeAll()
    }

    func startSpeedTest(timeLimit: TimeInterval = 8.0) {
        guard speedTask == nil else { return }
        let tester = SpeedTester(timeLimit: timeLimit) { [weak self] progress in
            guard let self else { return }
            self.speedTestState = .running(
                bytes: progress.bytesReceived,
                mbpsLive: progress.mbpsLive,
                elapsed: progress.elapsedSeconds
            )
        }
        self.speedTester = tester
        self.speedTestState = .running(bytes: 0, mbpsLive: 0, elapsed: 0)
        speedTask = Task { [weak self] in
            let result = await tester.run()
            await MainActor.run {
                self?.speedTestState = .finished(result)
                self?.speedTask = nil
                self?.speedTester = nil
            }
        }
    }

    func cancelSpeedTest() {
        speedTester?.stop()
    }

    func dismissSpeedTest() {
        speedTestState = .idle
    }

    func togglePause() {
        Task {
            let newPaused = !(await engine.isPaused())
            await engine.setPaused(newPaused)
            await MainActor.run { self.paused = newPaused }
        }
    }

    func applyPreset(_ preset: Preset) {
        prefs.applyPreset(preset)
        engineConfig = preset.engine
        thresholds   = preset.thresholds
    }

    // MARK: - config observation

    private func observeConfig() {
        $engineConfig
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] cfg in
                guard let self else { return }
                self.prefs.engineConfig = cfg
                Task { await self.engine.updateConfig(cfg) }
            }
            .store(in: &configBag)

        $thresholds
            .dropFirst()
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] th in
                guard let self else { return }
                self.prefs.thresholds = th
                self.stateMachine.thresholds = th
                self.stats.resize(windowCapacity: th.rollingWindow)
            }
            .store(in: &configBag)
    }

    private func appendTransition(from: ConnectivityState, to: ConnectivityState, note: String?) {
        let t = StateTransition(at: Date(), from: from, to: to, note: note)
        transitions.insert(t, at: 0)
    }
}
