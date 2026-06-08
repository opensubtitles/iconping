import Foundation
import Network

/// Thin wrapper around NWPathMonitor exposing path changes as an AsyncStream.
public final class NetworkPathMonitor: @unchecked Sendable {

    public struct Info: Sendable, Equatable {
        public var isSatisfied: Bool
        public var interfaceTypes: [String]
        public var primaryInterface: String?
        public var supportsIPv4: Bool
        public var supportsIPv6: Bool
        public var isExpensive: Bool
        public var isConstrained: Bool
    }

    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "app.iconping.network-path", qos: .utility)

    public init() {
        self.monitor = NWPathMonitor()
    }

    public func start() -> AsyncStream<Info> {
        AsyncStream { continuation in
            monitor.pathUpdateHandler = { path in
                continuation.yield(Self.snapshot(from: path))
            }
            monitor.start(queue: queue)
            continuation.onTermination = { [weak self] _ in
                self?.monitor.cancel()
            }
        }
    }

    public func currentSnapshot() -> Info {
        Self.snapshot(from: monitor.currentPath)
    }

    private static func snapshot(from path: NWPath) -> Info {
        let typesAll: [(NWInterface.InterfaceType, String)] = [
            (.wifi, "Wi-Fi"),
            (.wiredEthernet, "Ethernet"),
            (.cellular, "Cellular"),
            (.loopback, "Loopback"),
            (.other, "Other")
        ]
        var names: [String] = []
        var primary: String? = nil
        for (type, label) in typesAll {
            if path.usesInterfaceType(type) {
                names.append(label)
                if primary == nil { primary = path.availableInterfaces.first(where: { $0.type == type })?.name ?? label }
            }
        }
        return Info(
            isSatisfied: path.status == .satisfied,
            interfaceTypes: names,
            primaryInterface: primary,
            supportsIPv4: path.supportsIPv4,
            supportsIPv6: path.supportsIPv6,
            isExpensive: path.isExpensive,
            isConstrained: path.isConstrained
        )
    }
}
