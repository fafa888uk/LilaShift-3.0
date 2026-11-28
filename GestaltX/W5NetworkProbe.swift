// SPDX-License-Identifier: GPL-3.0-only
// W5 network probe engine (LilaShift 5.0.0, Wave 1: ip-tools) —
// real network measurement for the diagnostics page: ICMP ping,
// ICMP traceroute and egress ASN / BGP information via RIPEstat.
//
// The diagnostics page previously showed only connection status
// (see DiagnosticsExpansion.swift); this file adds the actual
// measurements. Design adapted from ahmadrezaei/ip-tools (MIT,
// © 2026 Ahmad Rezaei) NetCore layer — ICMP codec, unprivileged
// datagram socket, Pinger/Tracer structure — and from
// gewill/PingKit (MIT) — actor/AsyncSequence shape, failed sends
// counted as loss, local-network privacy note. The code here is
// reimplemented for LilaShift (W5-prefixed names, LilaShift
// conventions, no `public` API surface); it is not a verbatim
// copy. Full attribution and porting scope: W5NOTICES.md.
//
// Honesty rules, enforced by the types:
//   • Every probe outcome is explicit: reply, timeout,
//     unreachable or send error. A timeout is shown as a timeout,
//     never as a made-up latency; statistics are `nil` when no
//     reply was received.
//   • A failed send after the first probe becomes an `.error`
//     sample (PingKit's rule), so a dead network surfaces as
//     packet loss instead of silently vanishing from the totals.
//   • RIPEstat data is online-only. When the request fails, the
//     caller gets `W5NetError.ripeStatOffline` and the view shows
//     the offline state; local ping/traceroute results are still
//     shown, and nothing is substituted for the missing ASN data.
//   • Unprivileged ICMP (`SOCK_DGRAM` + `IPPROTO_ICMP[V6]`)
//     needs no entitlement and no root, but whether the iOS
//     sandbox allows it on a given iOS 27.x build must be
//     verified on a real device — a socket failure is reported
//     as `.socketUnavailable`, never worked around silently.
//   • Pinging a LAN address triggers the iOS local-network
//     privacy prompt; the app's Info.plist needs
//     `NSLocalNetworkUsageDescription` for that path (coordinator
//     follow-up — this file does not touch the plist).
//
// Upstream maturity warning: ip-tools was first published
// 2026-11-25 with 1 star, and PingKit has 0 stars. Both were
// read (codec, socket, pinger, tracer, RIPEstat fixtures) and
// their test ideas re-applied here, not blindly copied; the
// pure parts (codec, statistics, RIPEstat decoding) are covered
// by W5NetworkProbeTests without any network access.
import Foundation

// MARK: - IP address

/// An IPv4 or IPv6 address: 4 or 16 bytes in network order, plus
/// the IPv6 zone (interface index) for link-local addresses.
/// Parses literals only; hostnames go through
/// `W5TargetResolver` (getaddrinfo).
struct W5IPAddress: Hashable, Sendable, Codable, CustomStringConvertible {
    enum Family: Sendable, Hashable, Codable {
        case v4
        case v6
    }

    let bytes: [UInt8]
    let scopeID: UInt32

    var family: Family { bytes.count == 4 ? .v4 : .v6 }

    /// Accepts IPv4/IPv6 literals, "[v6]" and a trailing "%zone".
    init?(_ string: String) {
        var text = string.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("["), text.hasSuffix("]") {
            text = String(text.dropFirst().dropLast())
        }
        var scope: UInt32 = 0
        if let percent = text.firstIndex(of: "%") {
            let zone = String(text[text.index(after: percent)...])
            text = String(text[..<percent])
            if let number = UInt32(zone) {
                scope = number
            } else if !zone.isEmpty {
                scope = if_nametoindex(zone)
            }
        }
        var v4 = in_addr()
        if inet_pton(AF_INET, text, &v4) == 1 {
            self.bytes = withUnsafeBytes(of: &v4) { Array($0) }
            self.scopeID = 0
            return
        }
        var v6 = in6_addr()
        if inet_pton(AF_INET6, text, &v6) == 1 {
            self.bytes = withUnsafeBytes(of: &v6) { Array($0) }
            self.scopeID = scope
            return
        }
        return nil
    }

    init?(bytes: [UInt8], scopeID: UInt32 = 0) {
        guard bytes.count == 4 || bytes.count == 16 else { return nil }
        self.bytes = bytes
        self.scopeID = bytes.count == 16 ? scopeID : 0
    }

    /// Builds an address from a `sockaddr` (getaddrinfo / recvfrom
    /// result). Returns `nil` for families other than IPv4/IPv6.
    init?(sockaddr pointer: UnsafePointer<sockaddr>) {
        switch Int32(pointer.pointee.sa_family) {
        case AF_INET:
            let address = pointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                $0.pointee.sin_addr
            }
            self.bytes = withUnsafeBytes(of: address) { Array($0) }
            self.scopeID = 0
        case AF_INET6:
            let address = pointer.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
                $0.pointee
            }
            self.bytes = withUnsafeBytes(of: address.sin6_addr) { Array($0) }
            self.scopeID = address.sin6_scope_id
        default:
            return nil
        }
    }

    /// Builds a `sockaddr_in`/`sockaddr_in6` on the stack and
    /// calls `body` with it.
    func withSockaddr<T>(_ body: (UnsafePointer<sockaddr>, socklen_t) throws -> T) rethrows -> T {
        switch family {
        case .v4:
            var sin = sockaddr_in()
            sin.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            sin.sin_family = sa_family_t(AF_INET)
            withUnsafeMutableBytes(of: &sin.sin_addr) { $0.copyBytes(from: bytes) }
            return try withUnsafePointer(to: &sin) { pointer in
                try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    try body($0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        case .v6:
            var sin6 = sockaddr_in6()
            sin6.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
            sin6.sin6_family = sa_family_t(AF_INET6)
            withUnsafeMutableBytes(of: &sin6.sin6_addr) { $0.copyBytes(from: bytes) }
            sin6.sin6_scope_id = scopeID
            return try withUnsafePointer(to: &sin6) { pointer in
                try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    try body($0, socklen_t(MemoryLayout<sockaddr_in6>.size))
                }
            }
        }
    }

    var description: String {
        var buffer = [CChar](repeating: 0, count: 64)
        let result: UnsafePointer<CChar>? = bytes.withUnsafeBytes { raw in
            inet_ntop(family == .v4 ? AF_INET : AF_INET6, raw.baseAddress, &buffer, 64)
        }
        guard let result else { return "" }
        return String(cString: result)
    }

    /// The local scope label for private / CGNAT / link-local /
    /// loopback addresses; `nil` for publicly routable ones.
    /// Private and link-local targets are looked up locally only
    /// (no RIPEstat query) and may trigger the local-network
    /// privacy prompt.
    var scopeLabel: String? {
        switch family {
        case .v4:
            let first = bytes[0]
            let second = bytes[1]
            if first == 10 || (first == 172 && (16...31).contains(second))
                || (first == 192 && second == 168) {
                return "Private"
            }
            if first == 100 && (64...127).contains(second) { return "CGNAT" }
            if first == 169 && second == 254 { return "Link-local" }
            if first == 127 { return "Loopback" }
            return nil
        case .v6:
            if bytes == [UInt8](repeating: 0, count: 15) + [1] { return "Loopback" }
            if bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80 { return "Link-local" }
            if (bytes[0] & 0xfe) == 0xfc { return "Private" }
            return nil
        }
    }

    var isPubliclyRoutable: Bool { scopeLabel == nil && !isSpecialUse }

    private var isSpecialUse: Bool {
        switch family {
        case .v4:
            return bytes[0] == 0 || bytes[0] >= 224
        case .v6:
            if bytes[0] == 0xff { return true }
            if bytes[0] == 0x20, bytes[1] == 0x01, bytes[2] == 0x0d, bytes[3] == 0xb8 { return true }
            return bytes.allSatisfy { $0 == 0 }
        }
    }

    // Codable as the textual form.
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let address = W5IPAddress(text) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid IP address"))
        }
        self = address
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

// MARK: - Errors

/// Every failure a probe can report, with a user-facing message.
/// Nothing here is a guess: the socket errno and the HTTP status
/// are carried, and the view shows them verbatim.
enum W5NetError: Error, Sendable, Hashable, LocalizedError {
    case invalidTarget(String)
    case resolutionFailed(host: String, reason: String)
    case noAddress(host: String, family: W5IPAddress.Family)
    case socketUnavailable(errno: Int32)
    case networkUnreachable(family: W5IPAddress.Family)
    case localNetworkDenied
    case sendFailed(errno: Int32)
    case ripeStatOffline(underlying: String)
    case ripeStatHTTP(status: Int)
    case ripeStatMalformed

    var errorDescription: String? {
        switch self {
        case .invalidTarget(let target):
            return L("Invalid target:") + " " + target
        case .resolutionFailed(let host, let reason):
            return L("Could not resolve") + " " + host + ": " + reason
        case .noAddress(let host, _):
            return L("No address found for") + " " + host
        case .socketUnavailable(let code):
            return L("ICMP socket unavailable (errno") + " \(code)" + L("). The iOS sandbox may block unprivileged ICMP on this version.")
        case .networkUnreachable:
            return L("Network unreachable. Check the connection or airplane mode.")
        case .localNetworkDenied:
            return L("Local network access denied. Allow local network access and try again.")
        case .sendFailed(let code):
            return L("Send failed (errno") + " \(code)" + ")."
        case .ripeStatOffline(let underlying):
            return L("RIPEstat is offline:") + " " + underlying
        case .ripeStatHTTP(let status):
            return L("RIPEstat returned HTTP") + " \(status)" + "."
        case .ripeStatMalformed:
            return L("RIPEstat returned an unexpected response.")
        }
    }
}

// MARK: - ICMP codec

/// The identifier/sequence quoted inside a Time Exceeded or
/// Destination Unreachable message, used to match an error to the
/// probe that caused it.
struct W5QuotedEcho: Sendable, Equatable {
    let identifier: UInt16
    let sequence: UInt16
}

enum W5ICMPMessage: Sendable, Equatable {
    case echoReply(identifier: UInt16, sequence: UInt16, payload: [UInt8])
    case timeExceeded(W5QuotedEcho?)
    case destinationUnreachable(code: UInt8, W5QuotedEcho?)
    case other(type: UInt8, code: UInt8)
}

/// RFC 792 (IPv4) / RFC 4443 (IPv6) echo codec. IPv4 carries its
/// own checksum; the IPv6 checksum is filled in by the kernel.
enum W5ICMPCodec {
    static func echoRequest(
        family: W5IPAddress.Family, identifier: UInt16, sequence: UInt16, payload: [UInt8]
    ) -> [UInt8] {
        var packet: [UInt8] = [
            family == .v4 ? 8 : 128, 0, 0, 0,
            UInt8(identifier >> 8), UInt8(identifier & 0xff),
            UInt8(sequence >> 8), UInt8(sequence & 0xff),
        ]
        packet.append(contentsOf: payload)
        if family == .v4 {
            let sum = checksum(packet)
            packet[2] = UInt8(sum >> 8)
            packet[3] = UInt8(sum & 0xff)
        }
        return packet
    }

    /// Strips the IPv4 header when present; returns the message
    /// plus the IPv4 TTL if available. Returns `nil` for truncated
    /// or malformed datagrams and for IPv4 messages with a bad
    /// checksum.
    static func parse(
        _ datagram: [UInt8], family: W5IPAddress.Family
    ) -> (message: W5ICMPMessage, ttl: Int?)? {
        var offset = 0
        var ttl: Int?
        if family == .v4, let first = datagram.first, first >> 4 == 4 {
            // Darwin delivers the IPv4 header on ICMP datagram sockets.
            let ihl = Int(first & 0x0f) * 4
            guard ihl >= 20, datagram.count >= ihl + 8 else { return nil }
            guard datagram[9] == 1 else { return nil }
            ttl = Int(datagram[8])
            offset = ihl
        }
        guard datagram.count - offset >= 8 else { return nil }
        let message = offset == 0 ? datagram : Array(datagram[offset...])
        let type = message[0]
        let code = message[1]
        // Darwin rewrites the quoted header inside Time Exceeded /
        // Unreachable messages before delivery, so their checksum
        // no longer verifies. Verify everything else.
        if family == .v4, type != 11, type != 3, checksum(message) != 0 { return nil }
        switch (family, type) {
        case (.v4, 0), (.v6, 129):
            let identifier = UInt16(message[4]) << 8 | UInt16(message[5])
            let sequence = UInt16(message[6]) << 8 | UInt16(message[7])
            return (
                .echoReply(identifier: identifier, sequence: sequence, payload: Array(message[8...])),
                ttl)
        case (.v4, 11), (.v6, 3):
            return (.timeExceeded(quotedEcho(message, family: family)), ttl)
        case (.v4, 3), (.v6, 1):
            return (.destinationUnreachable(code: code, quotedEcho(message, family: family)), ttl)
        default:
            return (.other(type: type, code: code), ttl)
        }
    }

    /// Extracts the identifier/sequence of the echo request quoted
    /// inside an error message.
    private static func quotedEcho(
        _ message: [UInt8], family: W5IPAddress.Family
    ) -> W5QuotedEcho? {
        let inner = 8
        guard message.count > inner else { return nil }
        let icmpStart: Int
        switch family {
        case .v4:
            guard message[inner] >> 4 == 4 else { return nil }
            let ihl = Int(message[inner] & 0x0f) * 4
            guard ihl >= 20, message.count >= inner + ihl + 8,
                message[inner + 9] == 1 else { return nil }
            icmpStart = inner + ihl
            guard message[icmpStart] == 8 else { return nil }
        case .v6:
            guard message.count >= inner + 40 + 8,
                message[inner] >> 4 == 6, message[inner + 6] == 58 else { return nil }
            icmpStart = inner + 40
            guard message[icmpStart] == 128 else { return nil }
        }
        return W5QuotedEcho(
            identifier: UInt16(message[icmpStart + 4]) << 8 | UInt16(message[icmpStart + 5]),
            sequence: UInt16(message[icmpStart + 6]) << 8 | UInt16(message[icmpStart + 7]))
    }

    /// RFC 1071 internet checksum.
    static func checksum(_ bytes: [UInt8]) -> UInt16 {
        var sum: UInt32 = 0
        var index = 0
        while index + 1 < bytes.count {
            sum += UInt32(bytes[index]) << 8 | UInt32(bytes[index + 1])
            index += 2
        }
        if index < bytes.count { sum += UInt32(bytes[index]) << 8 }
        while sum >> 16 != 0 { sum = (sum & 0xffff) + (sum >> 16) }
        return ~UInt16(sum & 0xffff)
    }
}

// MARK: - ICMP socket

/// One received datagram, parsed, with its sender and arrival time.
struct W5ICMPPacket: Sendable {
    let message: W5ICMPMessage
    let from: W5IPAddress
    let ttl: Int?
    /// Raw datagram length as received (on IPv4 this includes the
    /// IP header).
    let byteCount: Int
    let receivedAt: ContinuousClock.Instant
}

/// Unprivileged ICMP datagram socket (`SOCK_DGRAM` +
/// `IPPROTO_ICMP[V6]`), nonblocking and driven by a
/// `DispatchSourceRead` on a private serial queue. No root, no
/// entitlement. `send` sets the hop limit on the same serial
/// queue immediately before `sendto`, so a traceroute probe can
/// never go out with the wrong TTL.
final class W5ICMPSocket: @unchecked Sendable {
    private let family: W5IPAddress.Family
    private let queue = DispatchQueue(label: "com.lilashift.w5-icmp-socket")
    private let fd: Int32
    private var source: DispatchSourceRead?
    private var closed = false
    private var currentHopLimit: Int?
    private var buffer = [UInt8](repeating: 0, count: 4096)
    private let stream: AsyncStream<W5ICMPPacket>
    private let continuation: AsyncStream<W5ICMPPacket>.Continuation

    init(family: W5IPAddress.Family) throws {
        let fd = socket(
            family == .v4 ? AF_INET : AF_INET6,
            SOCK_DGRAM,
            family == .v4 ? IPPROTO_ICMP : IPPROTO_ICMPV6)
        guard fd >= 0 else { throw W5NetError.socketUnavailable(errno: errno) }
        let flags = fcntl(fd, F_GETFL)
        if flags < 0 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) < 0 {
            let captured = errno
            Darwin.close(fd)
            throw W5NetError.socketUnavailable(errno: captured)
        }
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        var receiveBuffer: Int32 = 256 * 1024
        setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &receiveBuffer, socklen_t(MemoryLayout<Int32>.size))
        self.family = family
        self.fd = fd
        (stream, continuation) = AsyncStream.makeStream(of: W5ICMPPacket.self, bufferingPolicy: .unbounded)
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.drain() }
        source.setCancelHandler { Darwin.close(fd) }
        self.source = source
        source.resume()
    }

    deinit {
        // No queue.sync here: deinit may run on (or be blocked
        // behind) the socket queue.
        if let source {
            source.cancel()
        } else if !closed {
            Darwin.close(fd)
        }
        continuation.finish()
    }

    /// Sends one datagram. Returns the send instant (measured on
    /// the socket queue, immediately before `sendto`) so the RTT
    /// does not include queueing delay.
    func send(_ bytes: [UInt8], to: W5IPAddress, hopLimit: Int? = nil) throws -> ContinuousClock.Instant {
        try queue.sync {
            guard !closed else { throw W5NetError.sendFailed(errno: EBADF) }
            if let hop = hopLimit ?? (currentHopLimit == nil ? nil : 64), hop != currentHopLimit {
                var value = Int32(hop)
                let result: Int32
                if family == .v4 {
                    result = setsockopt(fd, IPPROTO_IP, IP_TTL, &value, socklen_t(MemoryLayout<Int32>.size))
                } else {
                    result = setsockopt(fd, IPPROTO_IPV6, IPV6_UNICAST_HOPS, &value, socklen_t(MemoryLayout<Int32>.size))
                }
                if result != 0 { throw W5NetError.sendFailed(errno: errno) }
                currentHopLimit = hop
            }
            let start = ContinuousClock.now
            let sent = to.withSockaddr { address, length in
                bytes.withUnsafeBytes { raw in
                    sendto(fd, raw.baseAddress, raw.count, 0, address, length)
                }
            }
            if sent < 0 {
                let captured = errno
                switch captured {
                case ENETUNREACH, EHOSTUNREACH, ENETDOWN, EADDRNOTAVAIL, EPERM, EACCES:
                    throw Self.mapSendError(captured, target: to)
                default:
                    throw W5NetError.sendFailed(errno: captured)
                }
            }
            return start
        }
    }

    /// Single consumer. Finishes when the socket is closed.
    var packets: AsyncStream<W5ICMPPacket> { stream }

    func close() {
        queue.sync {
            guard !closed else { return }
            closed = true
            source?.cancel()
            source = nil
        }
        continuation.finish()
    }

    private func drain() {
        while !closed {
            var storage = sockaddr_storage()
            var length = socklen_t(MemoryLayout<sockaddr_storage>.size)
            let count = buffer.withUnsafeMutableBytes { raw in
                withUnsafeMutablePointer(to: &storage) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
                        recvfrom(fd, raw.baseAddress, raw.count, 0, address, &length)
                    }
                }
            }
            let now = ContinuousClock.now
            if count < 0 { return }
            guard let from = Self.address(from: storage),
                let parsed = W5ICMPCodec.parse(Array(buffer[0..<count]), family: family) else { continue }
            continuation.yield(W5ICMPPacket(
                message: parsed.message, from: from, ttl: parsed.ttl,
                byteCount: count, receivedAt: now))
        }
    }

    /// Local-network-denied only applies to private / link-local
    /// targets; elsewhere report plain unreachability.
    static func mapSendError(_ code: Int32, target: W5IPAddress) -> W5NetError {
        let local = target.scopeLabel == "Private" || target.scopeLabel == "Link-local"
        switch code {
        case EHOSTUNREACH, EPERM, EACCES:
            if local { return .localNetworkDenied }
            return .sendFailed(errno: code)
        default:
            return .networkUnreachable(family: target.family)
        }
    }

    private static func address(from storage: sockaddr_storage) -> W5IPAddress? {
        var storage = storage
        switch Int32(storage.ss_family) {
        case AF_INET:
            return withUnsafeBytes(of: &storage) { raw in
                let sin = raw.load(as: sockaddr_in.self)
                return W5IPAddress(bytes: withUnsafeBytes(of: sin.sin_addr) { Array($0) })
            }
        case AF_INET6:
            return withUnsafeBytes(of: &storage) { raw in
                let sin6 = raw.load(as: sockaddr_in6.self)
                return W5IPAddress(bytes: withUnsafeBytes(of: sin6.sin6_addr) { Array($0) })
            }
        default:
            return nil
        }
    }
}

// MARK: - Target resolution

/// Which address family to resolve: follow the system DNS
/// ordering (including DNS64 synthesis on IPv6-only NAT64
/// networks), or force one family.
enum W5AddressFamilyPreference: Sendable, Hashable {
    case automatic
    case ipv4Only
    case ipv6Only
}

/// A resolved probe target: the host as typed plus the address
/// actually probed.
struct W5ResolvedTarget: Sendable, Hashable {
    let host: String
    let address: W5IPAddress
}

/// Hostname resolution via getaddrinfo. A literal address is
/// returned as-is without a DNS lookup. This is a blocking call
/// (DNS can wait on the network): callers must run it off the
/// main actor.
enum W5TargetResolver {
    static func resolve(
        host: String, family: W5AddressFamilyPreference = .automatic
    ) throws -> [W5IPAddress] {
        let trimmed = host.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw W5NetError.invalidTarget(host) }
        if let literal = W5IPAddress(trimmed) { return [literal] }
        var hints = addrinfo()
        switch family {
        case .automatic: hints.ai_family = AF_UNSPEC
        case .ipv4Only: hints.ai_family = AF_INET
        case .ipv6Only: hints.ai_family = AF_INET6
        }
        hints.ai_socktype = SOCK_DGRAM
        var result: UnsafeMutablePointer<addrinfo>?
        let status = trimmed.withCString { hostCString in
            getaddrinfo(hostCString, nil, &hints, &result)
        }
        guard status == 0, let head = result else {
            let reason: String
            if let message = gai_strerror(status) {
                reason = String(cString: message)
            } else {
                reason = L("Unknown resolution error")
            }
            throw W5NetError.resolutionFailed(host: trimmed, reason: reason)
        }
        defer { freeaddrinfo(head) }
        var addresses: [W5IPAddress] = []
        var cursor: UnsafeMutablePointer<addrinfo>? = head
        while let node = cursor {
            if let rawAddress = node.pointee.ai_addr,
                let address = W5IPAddress(sockaddr: rawAddress),
                !addresses.contains(address) {
                addresses.append(address)
            }
            cursor = node.pointee.ai_next
        }
        guard !addresses.isEmpty else {
            let wanted: W5IPAddress.Family = family == .ipv6Only ? .v6 : .v4
            throw W5NetError.noAddress(host: trimmed, family: wanted)
        }
        return addresses
    }

    /// Resolves and returns the first address (system DNS order).
    static func resolveFirst(
        host: String, family: W5AddressFamilyPreference = .automatic
    ) throws -> W5ResolvedTarget {
        let trimmed = host.trimmingCharacters(in: .whitespaces)
        let addresses = try resolve(host: trimmed, family: family)
        guard let first = addresses.first else {
            throw W5NetError.noAddress(host: trimmed, family: .v4)
        }
        return W5ResolvedTarget(host: trimmed, address: first)
    }
}

// MARK: - Ping

/// Ping options. `count == nil` means "until stopped".
struct W5PingOptions: Codable, Hashable, Sendable {
    var count: Int? = 10
    var interval: TimeInterval = 1.0
    var timeout: TimeInterval = 2.0
    var payloadSize: Int = 56

    static let `default` = W5PingOptions()

    init() {}

    init(count: Int?, interval: TimeInterval, timeout: TimeInterval, payloadSize: Int) {
        self.count = count
        self.interval = interval
        self.timeout = timeout
        self.payloadSize = payloadSize
    }

    /// Clamps user input to safe bounds: at most 1000 probes,
    /// 0.2–60 s interval, 0.5–30 s timeout, 8–9000 byte payload.
    /// A non-positive count becomes `nil` (until stopped) only
    /// when explicitly requested; clamping never invents probes.
    func sanitized() -> W5PingOptions {
        var copy = self
        if let count {
            copy.count = min(max(count, 1), 1000)
        }
        copy.interval = min(max(interval, 0.2), 60)
        copy.timeout = min(max(timeout, 0.5), 30)
        copy.payloadSize = min(max(payloadSize, 8), 9000)
        return copy
    }
}

struct W5PingSample: Identifiable, Hashable, Sendable {
    enum Outcome: Hashable, Sendable {
        /// Reply, with round-trip time in seconds.
        case reply(rtt: TimeInterval, bytes: Int, ttl: Int?, from: W5IPAddress)
        case timeout
        case unreachable(code: UInt8, from: W5IPAddress)
        case error(W5NetError)
    }

    var id: Int { sequence }
    /// 0-based, monotonically increasing.
    let sequence: Int
    let sentAt: Date
    let outcome: Outcome

    /// The round-trip time in seconds, or `nil` when the probe
    /// did not get a reply. Timeouts are never rendered as a
    /// latency.
    var rtt: TimeInterval? {
        if case let .reply(rtt, _, _, _) = outcome { return rtt }
        return nil
    }

    var isReply: Bool { rtt != nil }
}

/// Aggregate statistics over ping samples. All latency fields are
/// `nil` when no reply was received — an all-timeout run reports
/// "no replies", never 0 ms.
struct W5PingStatistics: Hashable, Sendable {
    let sent: Int
    let received: Int

    var lossFraction: Double { sent == 0 ? 0 : 1 - Double(received) / Double(sent) }

    let min: TimeInterval?
    let avg: TimeInterval?
    let max: TimeInterval?
    let stddev: TimeInterval?
    let jitter: TimeInterval?

    init(samples: [W5PingSample]) {
        var rtts: [TimeInterval] = []
        for sample in samples {
            if case let .reply(rtt, _, _, _) = sample.outcome { rtts.append(rtt) }
        }
        sent = samples.count
        received = rtts.count
        guard !rtts.isEmpty else {
            min = nil
            avg = nil
            max = nil
            stddev = nil
            jitter = nil
            return
        }
        let mean = rtts.reduce(0, +) / Double(rtts.count)
        min = rtts.min()
        max = rtts.max()
        avg = mean
        stddev = (rtts.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(rtts.count)).squareRoot()
        if rtts.count > 1 {
            var total = 0.0
            for index in 1..<rtts.count { total += abs(rtts[index] - rtts[index - 1]) }
            jitter = total / Double(rtts.count - 1)
        } else {
            jitter = nil
        }
    }
}

protocol W5PingService: Sendable {
    /// Emits one sample per probe as its outcome becomes known;
    /// finishes after `count` probes, or runs until the consuming
    /// task is cancelled. Throws `W5NetError` for fatal setup or
    /// first-send errors.
    func ping(_ target: W5ResolvedTarget, options: W5PingOptions) -> AsyncThrowingStream<W5PingSample, Error>
}

/// ICMP echo pinger over the unprivileged socket.
///
/// Behaviour: probes go out on a fixed schedule
/// (`t0 + n * interval`). One sample is emitted per probe as soon
/// as its outcome is known (reply, timeout, unreachable or send
/// error), so samples can complete out of order when
/// `timeout > interval`. A late reply after the timeout is
/// ignored. A failure to send probe 0 (or to open the socket)
/// finishes the stream by throwing; later send failures become
/// `.error` samples, so they count as loss (PingKit's rule).
/// Cancelling the consuming task stops promptly and closes the
/// socket.
struct W5Pinger: W5PingService {
    init() {}

    func ping(_ target: W5ResolvedTarget, options: W5PingOptions) -> AsyncThrowingStream<W5PingSample, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await Self.run(target, options, continuation)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func run(
        _ target: W5ResolvedTarget, _ options: W5PingOptions,
        _ continuation: AsyncThrowingStream<W5PingSample, Error>.Continuation
    ) async throws {
        let sanitized = options.sanitized()
        let socket = try W5ICMPSocket(family: target.address.family)
        let state = W5PingState(
            identifier: UInt16.random(in: 1...UInt16.max),
            nonce: (0..<8).map { _ in UInt8.random(in: 0...255) },
            continuation: continuation)
        let clock = ContinuousClock()
        let timeout = Duration.seconds(max(sanitized.timeout, 0.05))
        let size = min(max(sanitized.payloadSize, 8), 9000)
        try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    for await packet in socket.packets { state.handle(packet) }
                }
                group.addTask {
                    while !Task.isCancelled {
                        try? await clock.sleep(for: .milliseconds(20))
                        state.expire(now: clock.now)
                    }
                }
                group.addTask {
                    let start = clock.now
                    var number = 0
                    while sanitized.count.map({ number < $0 }) ?? true {
                        try await clock.sleep(until: start + .seconds(sanitized.interval * Double(number)))
                        try Task.checkCancellation()
                        let wireSequence = UInt16(truncatingIfNeeded: number)
                        let payload = state.nonce + (0..<(size - 8)).map { UInt8(truncatingIfNeeded: $0 &+ 8) }
                        let packet = W5ICMPCodec.echoRequest(
                            family: target.address.family,
                            identifier: state.identifier, sequence: wireSequence, payload: payload)
                        let sentAt = Date()
                        do {
                            let sentInstant = try socket.send(packet, to: target.address)
                            state.sent(number, wire: wireSequence, sentAt: sentAt, instant: sentInstant, deadline: sentInstant + timeout)
                        } catch let caught as W5NetError {
                            if number == 0 { throw caught }
                            continuation.yield(W5PingSample(sequence: number, sentAt: sentAt, outcome: .error(caught)))
                        }
                        number += 1
                    }
                    while state.hasPending {
                        try await clock.sleep(for: .milliseconds(20))
                    }
                }
                defer { socket.close(); group.cancelAll() }
                _ = try await group.next()
            }
        } onCancel: {
            socket.close()
        }
    }
}

private final class W5PingState: @unchecked Sendable {
    struct Pending {
        let sequence: Int
        let sentAt: Date
        let instant: ContinuousClock.Instant
        let deadline: ContinuousClock.Instant
    }

    let identifier: UInt16
    let nonce: [UInt8]
    private let continuation: AsyncThrowingStream<W5PingSample, Error>.Continuation
    private let lock = NSLock()
    private var pending: [UInt16: Pending] = [:]

    init(identifier: UInt16, nonce: [UInt8], continuation: AsyncThrowingStream<W5PingSample, Error>.Continuation) {
        self.identifier = identifier
        self.nonce = nonce
        self.continuation = continuation
    }

    var hasPending: Bool { lock.withLock { !pending.isEmpty } }

    func sent(_ number: Int, wire: UInt16, sentAt: Date, instant: ContinuousClock.Instant, deadline: ContinuousClock.Instant) {
        lock.withLock { pending[wire] = Pending(sequence: number, sentAt: sentAt, instant: instant, deadline: deadline) }
    }

    func handle(_ packet: W5ICMPPacket) {
        lock.withLock {
            switch packet.message {
            case let .echoReply(identifier, sequence, payload):
                guard payload.count >= nonce.count,
                    Array(payload.prefix(nonce.count)) == nonce,
                    let found = pending.removeValue(forKey: sequence) else { return }
                _ = identifier
                let rtt = w5Seconds(of: packet.receivedAt - found.instant)
                continuation.yield(W5PingSample(
                    sequence: found.sequence, sentAt: found.sentAt,
                    outcome: .reply(rtt: rtt, bytes: 8 + payload.count, ttl: packet.ttl, from: packet.from)))
            case let .destinationUnreachable(code, quoted?):
                guard quoted.identifier == identifier,
                    let found = pending.removeValue(forKey: quoted.sequence) else { return }
                continuation.yield(W5PingSample(
                    sequence: found.sequence, sentAt: found.sentAt,
                    outcome: .unreachable(code: code, from: packet.from)))
            default:
                return
            }
        }
    }

    func expire(now: ContinuousClock.Instant) {
        lock.withLock {
            for (wire, found) in pending where found.deadline <= now {
                pending.removeValue(forKey: wire)
                continuation.yield(W5PingSample(sequence: found.sequence, sentAt: found.sentAt, outcome: .timeout))
            }
        }
    }
}

/// `Duration` as seconds. A file-private helper instead of an
/// extension on `Duration`, so no other file can collide with it.
private func w5Seconds(of duration: Duration) -> Double {
    let parts = duration.components
    return Double(parts.seconds) + Double(parts.attoseconds) / 1_000_000_000_000_000_000
}

// MARK: - Traceroute

struct W5TraceOptions: Codable, Hashable, Sendable {
    var maxHops: Int = 30
    var probesPerHop: Int = 3
    var timeout: TimeInterval = 2.0

    static let `default` = W5TraceOptions()

    init() {}

    init(maxHops: Int, probesPerHop: Int, timeout: TimeInterval) {
        self.maxHops = maxHops
        self.probesPerHop = probesPerHop
        self.timeout = timeout
    }

    /// Clamps user input to safe bounds: 1–64 hops, 1–5 probes
    /// per hop, 0.5–30 s timeout.
    func sanitized() -> W5TraceOptions {
        var copy = self
        copy.maxHops = min(max(maxHops, 1), 64)
        copy.probesPerHop = min(max(probesPerHop, 1), 5)
        copy.timeout = min(max(timeout, 0.5), 30)
        return copy
    }
}

enum W5ProbeResult: Hashable, Sendable {
    case timeExceeded(from: W5IPAddress, rtt: TimeInterval)
    /// Reached the target (echo reply).
    case echoReply(from: W5IPAddress, rtt: TimeInterval)
    case unreachable(from: W5IPAddress, rtt: TimeInterval, code: UInt8)
    case timeout

    var address: W5IPAddress? {
        switch self {
        case let .timeExceeded(from, _), let .echoReply(from, _), let .unreachable(from, _, _):
            return from
        case .timeout:
            return nil
        }
    }

    var rtt: TimeInterval? {
        switch self {
        case let .timeExceeded(_, rtt), let .echoReply(_, rtt), let .unreachable(_, rtt, _):
            return rtt
        case .timeout:
            return nil
        }
    }

    /// True when this probe reached the destination.
    var reachedDestination: Bool {
        if case .echoReply = self { return true }
        return false
    }
}

enum W5TraceCompletion: Hashable, Sendable {
    case reachedDestination(hops: Int)
    case unreachable(atHop: Int, code: UInt8)
    case maxHopsExceeded
}

enum W5TraceEvent: Hashable, Sendable {
    case probe(ttl: Int, index: Int, result: W5ProbeResult)
    case hopFinished(ttl: Int)
    case finished(W5TraceCompletion)
}

protocol W5TraceService: Sendable {
    func trace(_ target: W5ResolvedTarget, options: W5TraceOptions) -> AsyncThrowingStream<W5TraceEvent, Error>
}

/// ICMP echo traceroute over the unprivileged socket.
///
/// Behaviour: for each TTL, `probesPerHop` echo requests go out
/// about 10 ms apart. `.probe` events are emitted as each probe's
/// result becomes known (indices within a hop may arrive out of
/// order; a silent probe is reported as `.timeout` once its
/// timeout elapses). `.hopFinished(ttl:)` follows when every
/// probe of that hop has a result. The trace ends with
/// `.finished` when an echo reply arrives
/// (`reachedDestination`), when a destination-unreachable
/// arrives, or after `maxHops`. No DNS or ASN enrichment happens
/// here. Cancelling the consuming task stops promptly.
struct W5Tracer: W5TraceService {
    init() {}

    func trace(_ target: W5ResolvedTarget, options: W5TraceOptions) -> AsyncThrowingStream<W5TraceEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await Self.run(target, options, continuation)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func run(
        _ target: W5ResolvedTarget, _ options: W5TraceOptions,
        _ continuation: AsyncThrowingStream<W5TraceEvent, Error>.Continuation
    ) async throws {
        let sanitized = options.sanitized()
        let socket = try W5ICMPSocket(family: target.address.family)
        let state = W5TraceState(
            identifier: UInt16.random(in: 1...UInt16.max),
            nonce: (0..<8).map { _ in UInt8.random(in: 0...255) },
            continuation: continuation)
        let clock = ContinuousClock()
        let timeout = Duration.seconds(max(sanitized.timeout, 0.05))
        let probes = max(sanitized.probesPerHop, 1)
        let maxHops = min(max(sanitized.maxHops, 1), 255)
        try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    for await packet in socket.packets { state.handle(packet) }
                }
                group.addTask {
                    while !Task.isCancelled {
                        try? await clock.sleep(for: .milliseconds(10))
                        state.expire(now: clock.now)
                    }
                }
                group.addTask {
                    var wireSequence: UInt16 = 0
                    for ttl in 1...maxHops {
                        for index in 0..<probes {
                            try Task.checkCancellation()
                            wireSequence &+= 1
                            let packet = W5ICMPCodec.echoRequest(
                                family: target.address.family, identifier: state.identifier,
                                sequence: wireSequence, payload: state.nonce)
                            state.prepare(wire: wireSequence, ttl: ttl, index: index)
                            let instant = try socket.send(packet, to: target.address, hopLimit: ttl)
                            state.armed(wire: wireSequence, instant: instant, deadline: instant + timeout)
                            if index < probes - 1 { try await clock.sleep(for: .milliseconds(10)) }
                        }
                        while state.hasPending {
                            try await clock.sleep(for: .milliseconds(10))
                        }
                        if let completion = state.finishHop(ttl: ttl) {
                            continuation.yield(.finished(completion))
                            return
                        }
                    }
                    continuation.yield(.finished(.maxHopsExceeded))
                }
                defer { socket.close(); group.cancelAll() }
                _ = try await group.next()
            }
        } onCancel: {
            socket.close()
        }
    }
}

private final class W5TraceState: @unchecked Sendable {
    struct Pending {
        let ttl: Int
        let index: Int
        var instant: ContinuousClock.Instant?
        var deadline: ContinuousClock.Instant?
    }

    let identifier: UInt16
    let nonce: [UInt8]
    private let continuation: AsyncThrowingStream<W5TraceEvent, Error>.Continuation
    private let lock = NSLock()
    private var pending: [UInt16: Pending] = [:]
    private var reached = false
    private var unreachableCode: UInt8?

    init(identifier: UInt16, nonce: [UInt8], continuation: AsyncThrowingStream<W5TraceEvent, Error>.Continuation) {
        self.identifier = identifier
        self.nonce = nonce
        self.continuation = continuation
    }

    var hasPending: Bool { lock.withLock { !pending.isEmpty } }

    func prepare(wire: UInt16, ttl: Int, index: Int) {
        lock.withLock { pending[wire] = Pending(ttl: ttl, index: index) }
    }

    func armed(wire: UInt16, instant: ContinuousClock.Instant, deadline: ContinuousClock.Instant) {
        lock.withLock {
            // The reply may already have been processed (loopback),
            // in which case the entry is gone.
            pending[wire]?.instant = instant
            pending[wire]?.deadline = deadline
        }
    }

    /// Returns the completion if the trace ends at this hop.
    func finishHop(ttl: Int) -> W5TraceCompletion? {
        lock.withLock {
            continuation.yield(.hopFinished(ttl: ttl))
            if reached { return .reachedDestination(hops: ttl) }
            if let code = unreachableCode { return .unreachable(atHop: ttl, code: code) }
            return nil
        }
    }

    func handle(_ packet: W5ICMPPacket) {
        lock.withLock {
            let wire: UInt16
            switch packet.message {
            case let .echoReply(_, sequence, payload):
                guard payload.starts(with: nonce) else { return }
                wire = sequence
            case let .timeExceeded(quoted?), let .destinationUnreachable(_, quoted?):
                guard quoted.identifier == identifier else { return }
                wire = quoted.sequence
            default:
                return
            }
            guard let found = pending[wire],
                let instant = found.instant ?? Optional(packet.receivedAt) else { return }
            pending.removeValue(forKey: wire)
            let rtt = max(w5Seconds(of: packet.receivedAt - instant), 0)
            let result: W5ProbeResult
            switch packet.message {
            case .echoReply:
                reached = true
                result = .echoReply(from: packet.from, rtt: rtt)
            case .timeExceeded:
                result = .timeExceeded(from: packet.from, rtt: rtt)
            case let .destinationUnreachable(code, _):
                if unreachableCode == nil { unreachableCode = code }
                result = .unreachable(from: packet.from, rtt: rtt, code: code)
            default:
                return
            }
            continuation.yield(.probe(ttl: found.ttl, index: found.index, result: result))
        }
    }

    func expire(now: ContinuousClock.Instant) {
        lock.withLock {
            for (wire, found) in pending {
                guard let deadline = found.deadline, deadline <= now else { continue }
                pending.removeValue(forKey: wire)
                continuation.yield(.probe(ttl: found.ttl, index: found.index, result: .timeout))
            }
        }
    }
}

// MARK: - RIPEstat: egress ASN / BGP information

/// One origin AS for the egress prefix. `holder` is `nil` when
/// the as-overview lookup failed or the AS has no holder; the
/// ASN itself is still shown — a missing name is never filled
/// in with a guess.
struct W5ASOverview: Equatable, Sendable, Hashable, Codable {
    let asn: UInt32
    let holder: String?
    /// Whether the prefix is currently announced in BGP; `nil`
    /// when the lookup did not report it.
    let announced: Bool?
}

/// The egress (public) network identity, from RIPEstat only.
/// All fields come from live API responses; when the request
/// fails, no `W5EgressInfo` is produced at all.
struct W5EgressInfo: Equatable, Sendable, Hashable, Codable {
    let publicIP: String
    let prefix: String?
    let origins: [W5ASOverview]
    let fetchedAt: Date
}

/// The RIPEstat network-info response for one IP: the announced
/// prefix and its origin AS numbers.
struct W5NetworkInfo: Equatable, Sendable, Hashable {
    let prefix: String?
    let originASNs: [UInt32]
}

private struct W5RIPEstatEnvelope<Payload: Decodable>: Decodable {
    let status: String
    let data: Payload
}

private struct W5WhatsMyIPPayload: Decodable {
    let ip: String
}

private struct W5NetworkInfoPayload: Decodable {
    let prefix: String?
    let asns: [String]
}

private struct W5ASOverviewPayload: Decodable {
    let holder: String?
    let announced: Bool?
}

/// RIPEstat Data API client (https://stat.ripe.net/data).
/// Only three endpoints are used: `whats-my-ip` (the public IP
/// as the internet sees it), `network-info` (prefix + origin
/// ASNs for that IP) and `as-overview` (holder + announced for
/// one ASN). No BGP map is built: a full AS-path graph is
/// ip-tools' BGPFeature scope and is out of scope for this
/// diagnostics card; the egress ASN and its announced prefix are
/// the honest, checkable subset. The session is injected so
/// tests can substitute a stub; production uses `.shared`.
struct W5RIPEstatClient {
    static let baseURL = URL(string: "https://stat.ripe.net/data")!

    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// The public IP, then its prefix + origin ASNs, then the
    /// holder of each origin ASN (at most 4; a failed holder
    /// lookup leaves `holder == nil` for that ASN instead of
    /// failing the whole result).
    func egressInfo() async throws -> W5EgressInfo {
        let ipPayload: W5WhatsMyIPPayload = try await fetch(endpoint: "whats-my-ip/data.json", resource: nil)
        let publicIP = ipPayload.ip
        guard W5IPAddress(publicIP) != nil else { throw W5NetError.ripeStatMalformed }
        let info = try await networkInfo(for: publicIP)
        var origins: [W5ASOverview] = []
        for asn in info.originASNs.prefix(4) {
            if let overview = try? await asOverview(for: asn) {
                origins.append(overview)
            } else {
                origins.append(W5ASOverview(asn: asn, holder: nil, announced: nil))
            }
        }
        return W5EgressInfo(publicIP: publicIP, prefix: info.prefix, origins: origins, fetchedAt: Date())
    }

    /// Prefix + origin ASNs for one public IP. Private,
    /// CGNAT, link-local and other special-use addresses are
    /// refused here: RIPEstat has no routing data for them, and
    /// asking would leak a local address to a third party.
    func networkInfo(for ip: String) async throws -> W5NetworkInfo {
        guard let address = W5IPAddress(ip), address.isPubliclyRoutable else {
            throw W5NetError.ripeStatMalformed
        }
        let payload: W5NetworkInfoPayload = try await fetch(endpoint: "network-info/data.json", resource: ip)
        return Self.makeNetworkInfo(from: payload)
    }

    func asOverview(for asn: UInt32) async throws -> W5ASOverview {
        let payload: W5ASOverviewPayload = try await fetch(
            endpoint: "as-overview/data.json", resource: "AS\(asn)")
        return Self.makeASOverview(asn: asn, from: payload)
    }

    // MARK: - Decoding (test hooks)

    /// Decodes a `network-info` response body without any
    /// network access, so the mapping (empty prefix → `nil`,
    /// non-numeric ASN strings dropped) is unit-testable.
    static func decodeNetworkInfo(from data: Data) throws -> W5NetworkInfo {
        let payload: W5NetworkInfoPayload = try decode(W5NetworkInfoPayload.self, from: data)
        return makeNetworkInfo(from: payload)
    }

    /// Decodes an `as-overview` response body without any
    /// network access.
    static func decodeASOverview(asn: UInt32, from data: Data) throws -> W5ASOverview {
        let payload: W5ASOverviewPayload = try decode(W5ASOverviewPayload.self, from: data)
        return makeASOverview(asn: asn, from: payload)
    }

    /// Decodes a `whats-my-ip` response body without any network
    /// access.
    static func decodeWhatsMyIP(from data: Data) throws -> String {
        let payload: W5WhatsMyIPPayload = try decode(W5WhatsMyIPPayload.self, from: data)
        return payload.ip
    }

    private static func makeNetworkInfo(from payload: W5NetworkInfoPayload) -> W5NetworkInfo {
        let prefix = payload.prefix.flatMap { $0.isEmpty ? nil : $0 }
        var seen: Set<UInt32> = []
        let asns = payload.asns.compactMap { UInt32($0) }.filter { seen.insert($0).inserted }
        return W5NetworkInfo(prefix: prefix, originASNs: asns)
    }

    private static func makeASOverview(asn: UInt32, from payload: W5ASOverviewPayload) -> W5ASOverview {
        W5ASOverview(asn: asn, holder: payload.holder, announced: payload.announced)
    }

    private static func decode<Payload: Decodable>(_ type: Payload.Type, from data: Data) throws -> Payload {
        do {
            let envelope = try JSONDecoder().decode(W5RIPEstatEnvelope<Payload>.self, from: data)
            guard envelope.status == "ok" else { throw W5NetError.ripeStatMalformed }
            return envelope.data
        } catch let caught as W5NetError {
            throw caught
        } catch {
            throw W5NetError.ripeStatMalformed
        }
    }

    private func fetch<Payload: Decodable>(endpoint: String, resource: String?) async throws -> Payload {
        var components = URLComponents(
            url: Self.baseURL.appendingPathComponent(endpoint), resolvingAgainstBaseURL: false)
        if let resource {
            components?.queryItems = [URLQueryItem(name: "resource", value: resource)]
        }
        guard let url = components?.url else { throw W5NetError.ripeStatMalformed }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            if error is CancellationError {
                throw error
            }
            throw W5NetError.ripeStatOffline(underlying: error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw W5NetError.ripeStatMalformed }
        guard http.statusCode == 200 else { throw W5NetError.ripeStatHTTP(status: http.statusCode) }
        return try Self.decode(Payload.self, from: data)
    }
}
