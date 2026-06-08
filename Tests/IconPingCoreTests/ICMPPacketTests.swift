import XCTest
@testable import IconPingCore

final class ICMPPacketTests: XCTestCase {

    func testChecksumKnownVector() {
        // Two-byte vector: "12" (0x31 0x32) -> ~((0x31 << 8) | 0x32) & 0xFFFF
        XCTAssertEqual(ICMPPacket.checksum16(Data([0x31, 0x32])), UInt16(~((UInt32(0x31) << 8) | UInt32(0x32)) & 0xFFFF))

        // ICMP echo header type=8 code=0 cks=0 id=0xABCD seq=0x0001 — manually computed.
        // 0x0800 + 0x0000 + 0xABCD + 0x0001 = 0xB3CE  -> ~0xB3CE = 0x4C31
        let header = Data([
            0x08, 0x00, 0x00, 0x00,
            0xAB, 0xCD, 0x00, 0x01
        ])
        XCTAssertEqual(ICMPPacket.checksum16(header), 0x4C31)
    }

    func testEncodeDecodeRoundTripV4() {
        let pkt = ICMPPacket.encodeEchoRequest(family: .v4, identifier: 0x1234, sequence: 0x5678, payloadBytes: 32)
        XCTAssertEqual(pkt.count, 8 + 32)
        // Type 8 echo request
        XCTAssertEqual(pkt[0], 8)
        XCTAssertEqual(pkt[1], 0)

        // Decode as if we received it (no IP header prepended)
        guard let decoded = ICMPPacket.decodeReply(family: .v4, data: pkt) else {
            return XCTFail("decode failed")
        }
        XCTAssertEqual(decoded.type, 8)
        XCTAssertEqual(decoded.sequence, 0x5678)
        XCTAssertEqual(decoded.payload.count, 32)
        XCTAssertEqual(Array(decoded.payload.prefix(ICMPPacket.signature.count)), ICMPPacket.signature)
    }

    func testEncodeDecodeRoundTripV6() {
        let pkt = ICMPPacket.encodeEchoRequest(family: .v6, identifier: 0, sequence: 7, payloadBytes: 16)
        XCTAssertEqual(pkt[0], 128) // ICMPv6 echo request type
        guard let decoded = ICMPPacket.decodeReply(family: .v6, data: pkt) else {
            return XCTFail("decode failed")
        }
        XCTAssertEqual(decoded.type, 128)
        XCTAssertEqual(decoded.sequence, 7)
    }

    func testDecodeStripsIPv4Header() {
        // Build a fake IPv4 header (20 bytes IHL=5, version=4) + echo-reply packet.
        let ipHeader = Data([
            0x45, 0x00, 0x00, 0x1C, // version+IHL, tos, total length
            0x00, 0x01, 0x00, 0x00,
            0x40, 0x01, 0x00, 0x00, // ttl, proto=ICMP
            127, 0, 0, 1,
            127, 0, 0, 1
        ])
        var pkt = ipHeader
        let echo = Data([0x00, 0x00, 0x00, 0x00, 0xAA, 0xAA, 0x00, 0x42])
        pkt.append(echo)
        guard let decoded = ICMPPacket.decodeReply(family: .v4, data: pkt) else {
            return XCTFail("decode failed")
        }
        XCTAssertEqual(decoded.type, 0)
        XCTAssertEqual(decoded.sequence, 0x42)
    }
}
