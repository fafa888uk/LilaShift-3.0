// SPDX-License-Identifier: GPL-3.0-only
// Tests for the W5 network probe engine (LilaShift 5.0.0, Wave 1:
// ip-tools): ICMP codec round-trips, IP literal parsing and scope
// labels, ping statistics (including the all-timeout case, which
// must report no latency rather than 0 ms), option clamping,
// RIPEstat response decoding from recorded fixtures, and the
// W5 directory registration.
//
// Everything here runs offline: no socket is opened and no HTTP
// request is made. Live ping/traceroute/RIPEstat behaviour can
// only be verified on a real device (see records/w5-iptools.md).
import Foundation
import XCTest
@testable import GestaltX

final class W5NetworkProbeTests: XCTestCase {
    private func address(_ string: String) throws -> W5IPAddress {
        try XCTUnwrap(W5IPAddress(string))
    }

    private func replySample(sequence: Int, rtt: TimeInterval) throws -> W5PingSample {
        W5PingSample(
            sequence: sequence, sentAt: Date(),
            outcome: .reply(rtt: rtt, bytes: 64, ttl: 57, from: try address("1.1.1.1")))
    }

    private func timeoutSample(sequence: Int) -> W5PingSample {
        W5PingSample(sequence: sequence, sentAt: Date(), outcome: .timeout)
    }

    private func fixtureData(_ json: String) -> Data {
        Data(json.utf8)
    }

    // MARK: - ICMP codec

    func testEchoRequestV4HasTypeCodeIdentifierSequenceAndValidChecksum() {
        let packet = W5ICMPCodec.echoRequest(
            family: .v4, identifier: 0x1234, sequence: 7, payload: [1, 2, 3, 4])
        XCTAssertEqual(packet[0], 8)
        XCTAssertEqual(packet[1], 0)
        XCTAssertEqual(packet[4], 0x12)
        XCTAssertEqual(packet[5], 0x34)
        XCTAssertEqual(packet[6], 0)
        XCTAssertEqual(packet[7], 7)
        XCTAssertEqual(Array(packet[8...]), [1, 2, 3, 4])
        // A correctly checksummed packet verifies to zero.
        XCTAssertEqual(W5ICMPCodec.checksum(packet), 0)
    }

    func testEchoRequestV6HasType128AndZeroChecksumField() {
        let packet = W5ICMPCodec.echoRequest(
            family: .v6, identifier: 0x0001, sequence: 2, payload: [9, 9])
        XCTAssertEqual(packet[0], 128)
        XCTAssertEqual(packet[1], 0)
        XCTAssertEqual(packet[2], 0)
        XCTAssertEqual(packet[3], 0)
    }

    func testChecksumKnownValues() {
        XCTAssertEqual(W5ICMPCodec.checksum([]), 0xffff)
        XCTAssertEqual(W5ICMPCodec.checksum([0x00, 0x00]), 0xffff)
        XCTAssertEqual(W5ICMPCodec.checksum([0xff, 0xff]), 0x0000)
        XCTAssertEqual(W5ICMPCodec.checksum([0x01]), 0xfeff)
    }

    func testParseEchoReplyRoundTripV4() {
        var reply = W5ICMPCodec.echoRequest(
            family: .v4, identifier: 0x1234, sequence: 7, payload: [1, 2, 3, 4])
        reply[0] = 0
        reply[2] = 0
        reply[3] = 0
        let sum = W5ICMPCodec.checksum(reply)
        reply[2] = UInt8(sum >> 8)
        reply[3] = UInt8(sum & 0xff)
        guard let parsed = W5ICMPCodec.parse(reply, family: .v4) else {
            XCTFail("Valid echo reply must parse")
            return
        }
        XCTAssertEqual(parsed.message, .echoReply(identifier: 0x1234, sequence: 7, payload: [1, 2, 3, 4]))
        XCTAssertNil(parsed.ttl)
    }

    func testParseRejectsTruncatedDatagrams() {
        XCTAssertNil(W5ICMPCodec.parse([], family: .v4))
        XCTAssertNil(W5ICMPCodec.parse([8], family: .v4))
        XCTAssertNil(W5ICMPCodec.parse([0x45], family: .v4))
        XCTAssertNil(W5ICMPCodec.parse([8, 0, 0, 0, 0, 0, 0], family: .v6))
    }

    func testParseRejectsBadChecksumV4() {
        var reply = W5ICMPCodec.echoRequest(
            family: .v4, identifier: 0x1234, sequence: 7, payload: [1, 2, 3, 4])
        reply[0] = 0
        reply[2] = 0
        reply[3] = 0
        let sum = W5ICMPCodec.checksum(reply)
        reply[2] = UInt8(sum >> 8)
        reply[3] = UInt8(sum & 0xff)
        reply[11] ^= 0xff
        XCTAssertNil(W5ICMPCodec.parse(reply, family: .v4))
    }

    func testParseTimeExceededWithQuotedEcho() {
        let innerRequest = W5ICMPCodec.echoRequest(
            family: .v4, identifier: 0x1234, sequence: 7, payload: [1, 2, 3, 4])
        let innerHeader: [UInt8] = [
            0x45, 0, 0, 32, 0, 0, 0, 0, 1, 1, 0, 0,
            8, 8, 8, 8, 1, 1, 1, 1,
        ]
        let packet: [UInt8] = [11, 0, 0, 0, 0, 0, 0, 0] + innerHeader + innerRequest
        guard let parsed = W5ICMPCodec.parse(packet, family: .v4) else {
            XCTFail("Valid time-exceeded message must parse")
            return
        }
        XCTAssertEqual(
            parsed.message,
            .timeExceeded(W5QuotedEcho(identifier: 0x1234, sequence: 7)))
    }

    func testParseDestinationUnreachableWithQuotedEcho() {
        let innerRequest = W5ICMPCodec.echoRequest(
            family: .v4, identifier: 0x00ab, sequence: 3, payload: [])
        let innerHeader: [UInt8] = [
            0x45, 0, 0, 28, 0, 0, 0, 0, 64, 1, 0, 0,
            8, 8, 8, 8, 1, 1, 1, 1,
        ]
        let packet: [UInt8] = [3, 1, 0, 0, 0, 0, 0, 0] + innerHeader + innerRequest
        guard let parsed = W5ICMPCodec.parse(packet, family: .v4) else {
            XCTFail("Valid destination-unreachable message must parse")
            return
        }
        XCTAssertEqual(
            parsed.message,
            .destinationUnreachable(code: 1, W5QuotedEcho(identifier: 0x00ab, sequence: 3)))
    }

    func testParseOtherType() {
        let packet: [UInt8] = [13, 0, 0, 0, 0, 0, 0, 0]
        guard let parsed = W5ICMPCodec.parse(packet, family: .v4) else {
            XCTFail("Unknown type must still parse as .other")
            return
        }
        XCTAssertEqual(parsed.message, .other(type: 13, code: 0))
    }

    // MARK: - IP address

    func testIPv4LiteralRoundTrip() throws {
        let parsed = try address("8.8.8.8")
        XCTAssertEqual(parsed.family, .v4)
        XCTAssertEqual(parsed.description, "8.8.8.8")
        XCTAssertNil(parsed.scopeLabel)
        XCTAssertTrue(parsed.isPubliclyRoutable)
    }

    func testIPv6LiteralAndBracketedForm() throws {
        let plain = try address("2001:db8::1")
        XCTAssertEqual(plain.family, .v6)
        XCTAssertEqual(plain.description, "2001:db8::1")
        let bracketed = try address("[2001:db8::1]")
        XCTAssertEqual(bracketed, plain)
    }

    func testInvalidLiteralsAreNil() {
        XCTAssertNil(W5IPAddress("999.1.1.1"))
        XCTAssertNil(W5IPAddress("example.com"))
        XCTAssertNil(W5IPAddress(""))
        XCTAssertNil(W5IPAddress("1.2.3"))
    }

    func testScopeLabelsV4() throws {
        XCTAssertEqual(try address("10.0.0.1").scopeLabel, "Private")
        XCTAssertEqual(try address("172.16.0.1").scopeLabel, "Private")
        XCTAssertEqual(try address("192.168.1.1").scopeLabel, "Private")
        XCTAssertEqual(try address("100.64.0.1").scopeLabel, "CGNAT")
        XCTAssertEqual(try address("169.254.1.1").scopeLabel, "Link-local")
        XCTAssertEqual(try address("127.0.0.1").scopeLabel, "Loopback")
        XCTAssertFalse(try address("10.0.0.1").isPubliclyRoutable)
    }

    func testScopeLabelsV6() throws {
        XCTAssertEqual(try address("::1").scopeLabel, "Loopback")
        XCTAssertEqual(try address("fe80::1").scopeLabel, "Link-local")
        XCTAssertEqual(try address("fc00::1").scopeLabel, "Private")
        XCTAssertNil(try address("2606:4700:4700::1111").scopeLabel)
    }

    func testIPAddressCodableRoundTrip() throws {
        let original = try address("1.1.1.1")
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "\"1.1.1.1\"")
        let decoded = try JSONDecoder().decode(W5IPAddress.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    // MARK: - Errors

    func testErrorDescriptionsAreNonEmptyAndHonest() {
        let errors: [W5NetError] = [
            .invalidTarget(""),
            .resolutionFailed(host: "example.invalid", reason: "No such host"),
            .noAddress(host: "example.invalid", family: .v4),
            .socketUnavailable(errno: 1),
            .networkUnreachable(family: .v4),
            .localNetworkDenied,
            .sendFailed(errno: 13),
            .ripeStatOffline(underlying: "The Internet connection appears to be offline."),
            .ripeStatHTTP(status: 503),
            .ripeStatMalformed,
        ]
        for error in errors {
            let description = error.localizedDescription
            XCTAssertFalse(description.isEmpty, "\(error) must explain itself")
        }
        XCTAssertTrue(W5NetError.socketUnavailable(errno: 1).localizedDescription.contains("1"))
        XCTAssertTrue(W5NetError.ripeStatHTTP(status: 503).localizedDescription.contains("503"))
    }

    // MARK: - Resolver (literal path only — no DNS, no network)

    func testResolveLiteralBypassesDNS() throws {
        XCTAssertEqual(try W5TargetResolver.resolve(host: "1.1.1.1"), [try address("1.1.1.1")])
        XCTAssertEqual(try W5TargetResolver.resolve(host: "[2001:db8::1]"), [try address("2001:db8::1")])
    }

    func testResolveEmptyTargetThrowsInvalidTarget() {
        XCTAssertThrowsError(try W5TargetResolver.resolve(host: "   ")) { error in
            XCTAssertEqual(error as? W5NetError, .invalidTarget("   "))
        }
    }

    func testResolveFirstPreservesHost() throws {
        let target = try W5TargetResolver.resolveFirst(host: " 8.8.8.8 ")
        XCTAssertEqual(target.host, "8.8.8.8")
        XCTAssertEqual(target.address, try address("8.8.8.8"))
    }

    // MARK: - Options

    func testPingOptionsSanitizedClamps() {
        let options = W5PingOptions(count: 5000, interval: 0.01, timeout: 100, payloadSize: 1).sanitized()
        XCTAssertEqual(options.count, 1000)
        XCTAssertEqual(options.interval, 0.2, accuracy: 0.0001)
        XCTAssertEqual(options.timeout, 30, accuracy: 0.0001)
        XCTAssertEqual(options.payloadSize, 8)
        let unlimited = W5PingOptions(count: nil, interval: 1, timeout: 2, payloadSize: 56).sanitized()
        XCTAssertNil(unlimited.count)
    }

    func testTraceOptionsSanitizedClamps() {
        let options = W5TraceOptions(maxHops: 500, probesPerHop: 99, timeout: 0.01).sanitized()
        XCTAssertEqual(options.maxHops, 64)
        XCTAssertEqual(options.probesPerHop, 5)
        XCTAssertEqual(options.timeout, 0.5, accuracy: 0.0001)
    }

    func testPingOptionsCodableRoundTrip() throws {
        let original = W5PingOptions(count: 4, interval: 0.5, timeout: 1.5, payloadSize: 32)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(W5PingOptions.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    // MARK: - Ping statistics

    func testStatisticsEmpty() {
        let statistics = W5PingStatistics(samples: [])
        XCTAssertEqual(statistics.sent, 0)
        XCTAssertEqual(statistics.received, 0)
        XCTAssertEqual(statistics.lossFraction, 0)
        XCTAssertNil(statistics.min)
        XCTAssertNil(statistics.avg)
        XCTAssertNil(statistics.max)
        XCTAssertNil(statistics.stddev)
        XCTAssertNil(statistics.jitter)
    }

    func testStatisticsAllTimeoutReportsNoLatency() {
        let samples = (0..<5).map { timeoutSample(sequence: $0) }
        let statistics = W5PingStatistics(samples: samples)
        XCTAssertEqual(statistics.sent, 5)
        XCTAssertEqual(statistics.received, 0)
        XCTAssertEqual(statistics.lossFraction, 1.0)
        XCTAssertNil(statistics.min)
        XCTAssertNil(statistics.avg)
        XCTAssertNil(statistics.max)
    }

    func testStatisticsKnownRTTs() throws {
        let samples = try [
            replySample(sequence: 0, rtt: 0.010),
            replySample(sequence: 1, rtt: 0.020),
            replySample(sequence: 2, rtt: 0.030),
        ]
        let statistics = W5PingStatistics(samples: samples)
        XCTAssertEqual(statistics.sent, 3)
        XCTAssertEqual(statistics.received, 3)
        XCTAssertEqual(statistics.lossFraction, 0)
        XCTAssertEqual(statistics.min, 0.010, accuracy: 0.000_001)
        XCTAssertEqual(statistics.avg, 0.020, accuracy: 0.000_001)
        XCTAssertEqual(statistics.max, 0.030, accuracy: 0.000_001)
        XCTAssertEqual(statistics.stddev, 0.008_164_965_8, accuracy: 0.000_001)
        XCTAssertEqual(statistics.jitter, 0.010, accuracy: 0.000_001)
    }

    func testStatisticsSingleReplyHasNoJitterAndZeroStddev() throws {
        let statistics = W5PingStatistics(samples: [try replySample(sequence: 0, rtt: 0.050)])
        XCTAssertEqual(statistics.received, 1)
        XCTAssertEqual(statistics.stddev, 0, accuracy: 0.000_001)
        XCTAssertNil(statistics.jitter)
    }

    func testStatisticsMixedLoss() throws {
        let samples = try [
            replySample(sequence: 0, rtt: 0.010),
            replySample(sequence: 1, rtt: 0.020),
            replySample(sequence: 2, rtt: 0.030),
            timeoutSample(sequence: 3),
        ]
        let statistics = W5PingStatistics(samples: samples)
        XCTAssertEqual(statistics.sent, 4)
        XCTAssertEqual(statistics.received, 3)
        XCTAssertEqual(statistics.lossFraction, 0.25, accuracy: 0.000_001)
    }

    func testPingSampleRTTIsNilWithoutReply() throws {
        let reply = try replySample(sequence: 0, rtt: 0.05)
        XCTAssertEqual(reply.rtt, 0.05)
        XCTAssertTrue(reply.isReply)
        let timeout = timeoutSample(sequence: 1)
        XCTAssertNil(timeout.rtt)
        XCTAssertFalse(timeout.isReply)
    }

    // MARK: - Traceroute result helpers

    func testProbeResultHelpers() throws {
        let hop = try address("192.168.1.1")
        let answered = W5ProbeResult.timeExceeded(from: hop, rtt: 0.001)
        XCTAssertEqual(answered.address, hop)
        XCTAssertEqual(answered.rtt, 0.001)
        XCTAssertFalse(answered.reachedDestination)
        let destination = W5ProbeResult.echoReply(from: hop, rtt: 0.002)
        XCTAssertTrue(destination.reachedDestination)
        let silent = W5ProbeResult.timeout
        XCTAssertNil(silent.address)
        XCTAssertNil(silent.rtt)
        XCTAssertFalse(silent.reachedDestination)
    }

    func testTraceHopRowAddressAndDestination() throws {
        let hop = try address("192.168.1.1")
        let answered = W5TraceHopRow(ttl: 1, results: [
            0: .timeout,
            1: .echoReply(from: hop, rtt: 0.002),
        ])
        XCTAssertEqual(answered.address, hop)
        XCTAssertTrue(answered.reachedDestination)
        let silent = W5TraceHopRow(ttl: 2, results: [0: .timeout, 1: .timeout, 2: .timeout])
        XCTAssertNil(silent.address)
        XCTAssertFalse(silent.reachedDestination)
    }

    // MARK: - RIPEstat decoding (recorded fixtures, no network)

    func testNetworkInfoDecodingFromRecordedResponse() throws {
        let json = """
            {"status":"ok","data":{"asns":["13335"],"prefix":"1.1.1.0/24"}}
            """
        let info = try W5RIPEstatClient.decodeNetworkInfo(from: fixtureData(json))
        XCTAssertEqual(info.prefix, "1.1.1.0/24")
        XCTAssertEqual(info.originASNs, [13335])
    }

    func testNetworkInfoDecodingDropsBadASNsAndEmptyPrefix() throws {
        let json = """
            {"status":"ok","data":{"asns":["13335","not-a-number"],"prefix":""}}
            """
        let info = try W5RIPEstatClient.decodeNetworkInfo(from: fixtureData(json))
        XCTAssertNil(info.prefix)
        XCTAssertEqual(info.originASNs, [13335])
    }

    func testNetworkInfoDecodingRejectsErrorStatusAndMalformedJSON() {
        let errorStatus = fixtureData("{\"status\":\"error\",\"data\":{}}")
        XCTAssertThrowsError(try W5RIPEstatClient.decodeNetworkInfo(from: errorStatus)) { error in
            XCTAssertEqual(error as? W5NetError, .ripeStatMalformed)
        }
        XCTAssertThrowsError(try W5RIPEstatClient.decodeNetworkInfo(from: fixtureData("{not json"))) { error in
            XCTAssertEqual(error as? W5NetError, .ripeStatMalformed)
        }
    }

    func testASOverviewDecodingFromRecordedResponse() throws {
        let json = """
            {"status":"ok","data":{"holder":"CLOUDFLARENET - Cloudflare, Inc.","announced":true}}
            """
        let overview = try W5RIPEstatClient.decodeASOverview(asn: 13335, from: fixtureData(json))
        XCTAssertEqual(overview.asn, 13335)
        XCTAssertEqual(overview.holder, "CLOUDFLARENET - Cloudflare, Inc.")
        XCTAssertEqual(overview.announced, true)
    }

    func testWhatsMyIPDecodingFromRecordedResponse() throws {
        let json = """
            {"status":"ok","data":{"ip":"91.107.240.242"}}
            """
        let ip = try W5RIPEstatClient.decodeWhatsMyIP(from: fixtureData(json))
        XCTAssertEqual(ip, "91.107.240.242")
    }

    func testNetworkInfoRefusesPrivateIPWithoutNetwork() async {
        do {
            let info = try await W5RIPEstatClient().networkInfo(for: "192.168.1.1")
            XCTFail("Private IPs must be refused before any request, got \(info)")
        } catch let caught as W5NetError {
            XCTAssertEqual(caught, .ripeStatMalformed)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Formatting

    func testMillisecondsFormatting() {
        XCTAssertEqual(W5NetworkProbeFormatting.milliseconds(0.0123), "12.3 ms")
        XCTAssertEqual(W5NetworkProbeFormatting.milliseconds(0.001), "1.0 ms")
        XCTAssertEqual(W5NetworkProbeFormatting.milliseconds(1.5), "1500.0 ms")
    }

    // MARK: - Registration

    func testRegistrationHasThreeDiagnosticsItems() {
        let items = W5NetworkProbeRegistration.items
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(W5NetworkProbeRegistration.allIDs.count, 3)
        XCTAssertEqual(Set(items.map(\.id)), W5NetworkProbeRegistration.allIDs)
        XCTAssertEqual(items.map(\.id), ["w5.ping", "w5.traceroute", "w5.asnBgp"])
        XCTAssertEqual(items.map(\.section), ["ping", "trace", "asn"])
        for item in items {
            XCTAssertEqual(item.category, .deviceDiagnostics)
            XCTAssertEqual(item.viewType, "NetworkProbeCard")
            XCTAssertEqual(item.viewType, W5NetworkProbeRegistration.viewType)
            XCTAssertFalse(item.chineseTitle.isEmpty)
            XCTAssertFalse(item.englishTitle.isEmpty)
            XCTAssertFalse(item.description.isEmpty)
        }
    }
}
