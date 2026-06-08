import Foundation
import Darwin

/// Owns the ICMP socket, schedules echo requests, correlates replies, and
/// emits a stream of `Sample` values. Designed to be driven by a single
/// observer (the app's main view model).
public actor PingEngine {

    public private(set) var config: EngineConfig
    private var continuation: AsyncStream<Sample>.Continuation?
    private var stream: AsyncStream<Sample>!

    private var socket: ICMPSocket?
    private var resolvedAddress: String = "-"
    private var family: ICMPPacket.Family = .v4
    private var seq: UInt16 = 0
    private var paused = false
    private var pendingSends: [UInt16: (sentAt: Date, sentMono: DispatchTime)] = [:]
    private var runTask: Task<Void, Never>?
    private var recvTask: Task<Void, Never>?

    public init(config: EngineConfig = EngineConfig()) {
        self.config = config
        var c: AsyncStream<Sample>.Continuation!
        self.stream = AsyncStream { cont in
            c = cont
        }
        self.continuation = c
    }

    public func samples() -> AsyncStream<Sample> { stream }

    public func updateConfig(_ new: EngineConfig) async {
        let needsRebind = (new.targetHost != config.targetHost) || (new.ipPreference != config.ipPreference)
        config = new
        if needsRebind {
            rebind()
        }
    }

    public func setPaused(_ paused: Bool) {
        self.paused = paused
    }

    public func isPaused() -> Bool { paused }

    public func start() {
        guard runTask == nil else { return }
        rebind()
        runTask = Task { [weak self] in
            await self?.runLoop()
        }
        recvTask = Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    public func stop() {
        runTask?.cancel()
        recvTask?.cancel()
        runTask = nil
        recvTask = nil
        socket = nil
    }

    // MARK: - internals

    private func rebind() {
        socket = nil
        pendingSends.removeAll(keepingCapacity: true)
        do {
            let (fam, addr, len, display) = try resolveHost(config.targetHost, preference: config.ipPreference)
            self.family = fam
            self.resolvedAddress = display
            self.socket = try ICMPSocket(family: fam, address: addr, addressLength: len, displayAddress: display)
        } catch {
            self.socket = nil
            self.resolvedAddress = "unresolved"
            // emit a one-shot DNS-failure sample
            let s = Sample(
                seq: 0,
                sentAt: Date(),
                rttSeconds: nil,
                status: .dnsFailure,
                resolvedAddress: nil,
                ipVersion: config.ipPreference
            )
            continuation?.yield(s)
        }
    }

    private func runLoop() async {
        while !Task.isCancelled {
            if paused || socket == nil {
                try? await Task.sleep(nanoseconds: UInt64(config.intervalSeconds * 1_000_000_000))
                if socket == nil && !paused { rebind() }
                continue
            }
            await tick()
            try? await Task.sleep(nanoseconds: UInt64(config.intervalSeconds * 1_000_000_000))
        }
    }

    private func tick() async {
        guard let sock = socket else { return }
        seq &+= 1
        let mySeq = seq
        let now = Date()
        let mono = DispatchTime.now()
        pendingSends[mySeq] = (now, mono)

        let packet = ICMPPacket.encodeEchoRequest(
            family: family,
            identifier: 0,
            sequence: mySeq,
            payloadBytes: config.payloadBytes
        )
        do {
            try sock.send(packet)
        } catch {
            pendingSends.removeValue(forKey: mySeq)
            let s = Sample(
                seq: mySeq, sentAt: now, rttSeconds: nil,
                status: .socketError, resolvedAddress: resolvedAddress, ipVersion: ipVersionOf(family: family)
            )
            continuation?.yield(s)
            // attempt to rebind so we recover from transient socket errors
            rebind()
            return
        }

        // schedule timeout check
        let timeoutNs = UInt64(config.timeoutSeconds * 1_000_000_000)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: timeoutNs)
            await self?.expire(seq: mySeq)
        }
    }

    private func expire(seq: UInt16) {
        guard let pending = pendingSends.removeValue(forKey: seq) else { return }
        let s = Sample(
            seq: seq,
            sentAt: pending.sentAt,
            rttSeconds: nil,
            status: .lost,
            resolvedAddress: resolvedAddress,
            ipVersion: ipVersionOf(family: family)
        )
        continuation?.yield(s)
    }

    private func receiveLoop() async {
        while !Task.isCancelled {
            guard let sock = socket else {
                try? await Task.sleep(nanoseconds: 250_000_000)
                continue
            }
            do {
                if let data = try sock.receive() {
                    handleReceived(data)
                } else {
                    // socket timeout — yield to scheduler
                    await Task.yield()
                }
            } catch {
                // transient socket error; brief backoff
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    private func handleReceived(_ data: Data) {
        guard let reply = ICMPPacket.decodeReply(family: family, data: data) else { return }
        let expectedType: UInt8 = (family == .v4) ? ICMPPacket.echoReplyV4 : ICMPPacket.echoReplyV6
        guard reply.type == expectedType, reply.code == 0 else { return }
        guard let pending = pendingSends.removeValue(forKey: reply.sequence) else { return }
        let nowMono = DispatchTime.now()
        let elapsedNs = nowMono.uptimeNanoseconds &- pending.sentMono.uptimeNanoseconds
        let rtt = Double(elapsedNs) / 1_000_000_000.0
        let s = Sample(
            seq: reply.sequence,
            sentAt: pending.sentAt,
            rttSeconds: rtt,
            status: .received,
            resolvedAddress: resolvedAddress,
            ipVersion: ipVersionOf(family: family)
        )
        continuation?.yield(s)
    }

    private func ipVersionOf(family: ICMPPacket.Family) -> IPVersionPreference {
        family == .v4 ? .ipv4 : .ipv6
    }

    public func currentResolvedAddress() -> String { resolvedAddress }
    public func currentFamily() -> ICMPPacket.Family { family }
}
