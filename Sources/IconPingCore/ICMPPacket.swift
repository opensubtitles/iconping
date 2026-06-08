import Foundation

/// ICMP echo packet encode/decode for IPv4 (type 8/0) and IPv6 (type 128/129).
///
/// Note on datagram-ICMP sockets (`SOCK_DGRAM`):
/// - The kernel rewrites the `identifier` to a value tied to the socket's local port
///   and computes the checksum for both v4 and v6. So we still emit a checksum field
///   of zero (kernel fills it) and we do NOT match replies on identifier — we match
///   on sequence number, and validate by comparing the payload signature.
/// - See: SimplePing reference implementation, and `man 4 icmp` on macOS.
public enum ICMPPacket {

    public enum Family { case v4, v6 }

    public static let echoRequestV4: UInt8 = 8
    public static let echoReplyV4:   UInt8 = 0
    public static let echoRequestV6: UInt8 = 128
    public static let echoReplyV6:   UInt8 = 129

    public static let headerSize = 8
    public static let signature: [UInt8] = Array("ICONPING".utf8)
    /// Payload layout (so we can correlate replies even if the kernel rewrites
    /// the ICMP-header sequence field, which has been observed on recent macOS):
    ///   [0..<8]:   "ICONPING" magic
    ///   [8..<12]:  session ID (UInt32 BE)        — unique per PingEngine instance
    ///   [12..<14]: app sequence (UInt16 BE)      — what we actually correlate on
    ///   [14...]:   padding
    public static let payloadHeaderSize = 14

    /// Build an echo-request packet. Identifier is ignored by the datagram kernel but
    /// included for completeness. Payload starts with the signature + session ID +
    /// app sequence so we can correlate replies via the echoed-back payload instead
    /// of the ICMP header sequence (which some kernels rewrite).
    public static func encodeEchoRequest(
        family: Family,
        identifier: UInt16,
        sequence: UInt16,
        sessionID: UInt32,
        payloadBytes: Int
    ) -> Data {
        let type: UInt8 = (family == .v4) ? echoRequestV4 : echoRequestV6
        let code: UInt8 = 0
        let checksum: UInt16 = 0 // kernel fills

        var data = Data(capacity: headerSize + payloadBytes)
        data.append(type)
        data.append(code)
        data.appendBigEndian(checksum)
        data.appendBigEndian(identifier)
        data.appendBigEndian(sequence)

        // payload
        let toWrite = max(payloadBytes, payloadHeaderSize)
        // [0..<8] signature
        data.append(contentsOf: signature)
        // [8..<12] sessionID BE
        let sidBE = sessionID.bigEndian
        withUnsafeBytes(of: sidBE) { data.append(contentsOf: $0) }
        // [12..<14] app sequence BE
        let seqBE = sequence.bigEndian
        withUnsafeBytes(of: seqBE) { data.append(contentsOf: $0) }
        // remaining padding
        for i in payloadHeaderSize..<toWrite {
            data.append(UInt8(truncatingIfNeeded: i))
        }

        // For IPv4 we set the checksum field defensively (kernel will overwrite, but
        // some paths historically misbehave if it's left 0). For IPv6 the kernel
        // requires checksum to be 0 on send — leave it.
        if family == .v4 {
            let cs = checksum16(data)
            data[2] = UInt8(truncatingIfNeeded: cs >> 8)
            data[3] = UInt8(truncatingIfNeeded: cs)
        }

        return data
    }

    public struct DecodedReply: Sendable, Equatable {
        public let type: UInt8
        public let code: UInt8
        public let identifier: UInt16
        public let sequence: UInt16
        public let payload: Data
    }

    /// Pull the session ID and our app-sequence out of a reply's payload. Returns
    /// nil if the payload is too short or doesn't carry our magic — i.e. the
    /// packet didn't originate from this app.
    public static func parsePayload(_ payload: Data) -> (sessionID: UInt32, appSeq: UInt16)? {
        guard payload.count >= payloadHeaderSize else { return nil }
        let sigBytes = Array(payload.prefix(signature.count))
        guard sigBytes == signature else { return nil }
        let start = payload.startIndex
        let sid: UInt32 =
            (UInt32(payload[start + 8])  << 24) |
            (UInt32(payload[start + 9])  << 16) |
            (UInt32(payload[start + 10]) << 8)  |
             UInt32(payload[start + 11])
        let seq: UInt16 =
            (UInt16(payload[start + 12]) << 8) |
             UInt16(payload[start + 13])
        return (sid, seq)
    }

    /// Decode an echo reply. For IPv4 datagram sockets the kernel typically strips
    /// the IP header before delivering; in case it doesn't, we detect & skip it.
    public static func decodeReply(family: Family, data: Data) -> DecodedReply? {
        var bytes = data
        if family == .v4 && bytes.count >= 20 {
            // IPv4 header may be present. First nibble = version (4), second = IHL.
            let firstByte = bytes[bytes.startIndex]
            if (firstByte >> 4) == 4 {
                let ihl = Int(firstByte & 0x0F) * 4
                if ihl >= 20 && bytes.count >= ihl + headerSize {
                    bytes = bytes.subdata(in: (bytes.startIndex + ihl)..<bytes.endIndex)
                }
            }
        }
        guard bytes.count >= headerSize else { return nil }
        let type = bytes[bytes.startIndex]
        let code = bytes[bytes.startIndex + 1]
        let id   = bytes.readBigEndianUInt16(at: bytes.startIndex + 4)
        let seq  = bytes.readBigEndianUInt16(at: bytes.startIndex + 6)
        let payload = (bytes.count > bytes.startIndex + headerSize)
            ? bytes.subdata(in: (bytes.startIndex + headerSize)..<bytes.endIndex)
            : Data()
        return DecodedReply(type: type, code: code, identifier: id, sequence: seq, payload: payload)
    }

    /// Standard BSD 16-bit ones-complement checksum.
    public static func checksum16(_ data: Data) -> UInt16 {
        var sum: UInt32 = 0
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let p = raw.bindMemory(to: UInt8.self)
            var i = 0
            while i + 1 < p.count {
                let word = (UInt32(p[i]) << 8) | UInt32(p[i+1])
                sum &+= word
                i += 2
            }
            if i < p.count {
                sum &+= (UInt32(p[i]) << 8)
            }
        }
        while (sum >> 16) != 0 {
            sum = (sum & 0xFFFF) &+ (sum >> 16)
        }
        return ~UInt16(truncatingIfNeeded: sum)
    }
}

extension Data {
    mutating func appendBigEndian(_ value: UInt16) {
        append(UInt8(truncatingIfNeeded: value >> 8))
        append(UInt8(truncatingIfNeeded: value))
    }

    func readBigEndianUInt16(at offset: Int) -> UInt16 {
        let hi = UInt16(self[offset])
        let lo = UInt16(self[offset + 1])
        return (hi << 8) | lo
    }
}
