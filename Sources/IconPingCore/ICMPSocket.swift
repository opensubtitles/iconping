import Foundation
import Darwin

/// Unprivileged datagram ICMP socket (no root, sandbox-compatible with
/// `com.apple.security.network.client`).
///
/// One socket per address family. Replies are matched by sequence number.
public final class ICMPSocket: @unchecked Sendable {

    public enum SocketError: Error, CustomStringConvertible {
        case create(Int32)
        case send(Int32)
        case receive(Int32)
        case bind(Int32)
        case resolution(String)

        public var description: String {
            switch self {
            case .create(let e):     return "socket() failed: errno=\(e) (\(errnoString(e)))"
            case .send(let e):       return "sendto() failed: errno=\(e) (\(errnoString(e)))"
            case .receive(let e):    return "recvfrom() failed: errno=\(e) (\(errnoString(e)))"
            case .bind(let e):       return "bind() failed: errno=\(e) (\(errnoString(e)))"
            case .resolution(let h): return "getaddrinfo() failed for host \(h)"
            }
        }
    }

    public let family: ICMPPacket.Family
    public let address: sockaddr_storage
    public let addressLength: socklen_t
    public let displayAddress: String
    private let fd: Int32

    public init(family: ICMPPacket.Family, address: sockaddr_storage, addressLength: socklen_t, displayAddress: String) throws {
        self.family = family
        self.address = address
        self.addressLength = addressLength
        self.displayAddress = displayAddress

        let domain: Int32 = (family == .v4) ? AF_INET : AF_INET6
        let proto:  Int32 = (family == .v4) ? Int32(IPPROTO_ICMP) : Int32(IPPROTO_ICMPV6)
        let fd = socket(domain, SOCK_DGRAM, proto)
        if fd < 0 {
            throw SocketError.create(errno)
        }
        self.fd = fd

        // small recv timeout so blocking recvfrom doesn't hang forever on shutdown
        var tv = timeval(tv_sec: 0, tv_usec: 200_000)
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    }

    deinit { close(fd) }

    public func send(_ packet: Data) throws {
        var addr = address
        let sent = packet.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> ssize_t in
            withUnsafePointer(to: &addr) { sptr in
                sptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saptr in
                    sendto(fd, raw.baseAddress, raw.count, 0, saptr, addressLength)
                }
            }
        }
        if sent < 0 {
            throw SocketError.send(errno)
        }
    }

    /// Blocking receive with the short socket timeout configured in init.
    /// Returns nil on timeout, throws on real error.
    public func receive(maxBytes: Int = 4096) throws -> Data? {
        var buffer = [UInt8](repeating: 0, count: maxBytes)
        var fromAddr = sockaddr_storage()
        var fromLen = socklen_t(MemoryLayout<sockaddr_storage>.size)
        let n: ssize_t = buffer.withUnsafeMutableBufferPointer { bptr in
            withUnsafeMutablePointer(to: &fromAddr) { saptr in
                saptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { addrPtr in
                    recvfrom(fd, bptr.baseAddress, bptr.count, 0, addrPtr, &fromLen)
                }
            }
        }
        if n < 0 {
            let e = errno
            if e == EAGAIN || e == EWOULDBLOCK { return nil }
            throw SocketError.receive(e)
        }
        return Data(buffer.prefix(Int(n)))
    }
}

/// Resolve a hostname (or numeric IP) into a sockaddr for the requested family.
public func resolveHost(_ host: String, preference: IPVersionPreference) throws -> (family: ICMPPacket.Family, addr: sockaddr_storage, len: socklen_t, display: String) {

    var hints = addrinfo(
        ai_flags: AI_ADDRCONFIG,
        ai_family: AF_UNSPEC,
        ai_socktype: SOCK_DGRAM,
        ai_protocol: 0,
        ai_addrlen: 0,
        ai_canonname: nil,
        ai_addr: nil,
        ai_next: nil
    )
    switch preference {
    case .ipv4: hints.ai_family = AF_INET
    case .ipv6: hints.ai_family = AF_INET6
    case .auto: hints.ai_family = AF_UNSPEC
    }

    var result: UnsafeMutablePointer<addrinfo>?
    let rc = getaddrinfo(host, nil, &hints, &result)
    if rc != 0 || result == nil {
        throw ICMPSocket.SocketError.resolution(host)
    }
    defer { freeaddrinfo(result) }

    // auto: prefer v4 first (per spec); else first match.
    var preferred: UnsafeMutablePointer<addrinfo>? = nil
    var fallback:  UnsafeMutablePointer<addrinfo>? = nil
    var ptr = result
    while let p = ptr {
        if preference == .auto {
            if p.pointee.ai_family == AF_INET && preferred == nil { preferred = p }
            if p.pointee.ai_family == AF_INET6 && fallback == nil { fallback = p }
        } else {
            preferred = p
            break
        }
        ptr = p.pointee.ai_next
    }
    guard let chosen = preferred ?? fallback else {
        throw ICMPSocket.SocketError.resolution(host)
    }

    var storage = sockaddr_storage()
    memcpy(&storage, chosen.pointee.ai_addr, Int(chosen.pointee.ai_addrlen))
    let len = chosen.pointee.ai_addrlen
    let family: ICMPPacket.Family = (chosen.pointee.ai_family == AF_INET) ? .v4 : .v6

    // Display address
    var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
    let display: String = buffer.withUnsafeMutableBufferPointer { bptr in
        withUnsafePointer(to: &storage) { sptr -> String in
            sptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saptr in
                _ = getnameinfo(saptr, len, bptr.baseAddress, socklen_t(bptr.count), nil, 0, NI_NUMERICHOST)
                return String(cString: bptr.baseAddress!)
            }
        }
    }

    return (family, storage, len, display)
}

private func errnoString(_ e: Int32) -> String {
    String(cString: strerror(e))
}
