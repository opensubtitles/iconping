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

    enum QuickTestState: Equatable {
        case idle
        case running(progress: Double)   // 0..1
        case finished(QuickTestResult)
    }
    @Published var quickTestState: QuickTestState = .idle
    private var testSamples: [Sample] = []
    private var testTask: Task<Void, Never>?

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
        // During a quick test, collect into the test bucket in parallel with normal stats.
        if case .running = quickTestState {
            await MainActor.run { self.testSamples.append(sample) }
        }
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

    func startQuickTest(count: Int = 30, intervalMs: Int = 200) {
        guard testTask == nil else { return }
        testTask = Task { [weak self] in
            await self?.runQuickTest(count: count, intervalMs: intervalMs)
            self?.testTask = nil
        }
    }

    func dismissQuickTest() {
        quickTestState = .idle
    }

    private func runQuickTest(count: Int, intervalMs: Int) async {
        await MainActor.run {
            self.testSamples.removeAll()
            self.quickTestState = .running(progress: 0)
        }

        let savedCfg = engineConfig
        var burstCfg = savedCfg
        burstCfg.intervalSeconds = Double(intervalMs) / 1000.0
        burstCfg.timeoutSeconds  = max(1.0, savedCfg.timeoutSeconds)
        await engine.updateConfig(burstCfg)

        let start = Date()
        let maxSec = Double(count) * Double(intervalMs) / 1000.0 + savedCfg.timeoutSeconds + 1.0
        while Date().timeIntervalSince(start) < maxSec {
            let got = await MainActor.run { self.testSamples.count }
            if got >= count { break }
            await MainActor.run {
                self.quickTestState = .running(progress: min(1.0, Double(got) / Double(count)))
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }

        await engine.updateConfig(savedCfg)

        await MainActor.run {
            let samples = Array(self.testSamples.prefix(count))
            let rttsMs = samples.compactMap { $0.rttMs }
            var jitter: Double? = nil
            if rttsMs.count >= 2 {
                var diffs: [Double] = []
                for i in 1..<rttsMs.count { diffs.append(abs(rttsMs[i] - rttsMs[i-1])) }
                jitter = diffs.reduce(0, +) / Double(diffs.count)
            }
            let result = QuickTestResult(
                sent: samples.count,
                received: rttsMs.count,
                minMs: rttsMs.min(),
                avgMs: rttsMs.isEmpty ? nil : rttsMs.reduce(0, +) / Double(rttsMs.count),
                maxMs: rttsMs.max(),
                jitterMs: jitter,
                durationSeconds: Date().timeIntervalSince(start)
            )
            self.quickTestState = .finished(result)
        }
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
