//! NTP client library
const std = @import("std");
const mem = std.mem;
const print = std.debug.print;
const testing = std.testing;
const assert = std.debug.assert;

const ns_per_s: u64 = 1_000_000_000;

/// NTP packet has 48 bytes if extension and key / digest fields are excluded.
pub const packet_len: usize = 48;

/// Clock error estimate; only applicable if client makes repeated calls to a server.
pub const max_disp: f32 = 16.0; // [s]

/// Too far away.
pub const max_stratum: u8 = 16;

/// Offset between the Unix epoch and the NTP epoch, era zero, in seconds.
pub const epoch_offset: u32 = 2_208_988_800;

/// NTP era. Era zero starts at zero hours on 1900-01-01 and ends 2^32 seconds later.
pub const ntp_era: u8 = 0;

pub const client_mode: u8 = 3;

/// NTP precision
pub fn precisionToNanos(prc: i8) u64 {
    if (prc > 0) return ns_per_s << @as(u6, @intCast(prc));
    if (prc < 0) return ns_per_s >> @as(u6, @intCast(-prc));
    return ns_per_s;
}

/// Time (duration, to be precise) since epoch.
/// - 32 bits seconds: ~ 136 years per era (64 bits would be ~ 5.8e10 years)
/// - 32 bits fraction: precision is ~ 2.3e-10 s (64 bits would be ~ 5.4e-20 s)
/// - total nanoseconds: ~ 2^62
///
/// In an NTP packet, this represents a duration since the NTP epoch.
/// Era 0 starts at zero hours on 1900-01-01.
///
const Time = struct {
    t: u64 = 0, // upper 32 bits: seconds, lower 32 bits: fraction

    /// from value as received in NTP packet.
    pub fn fromRaw(raw: u64) Time {
        return .{ .t = raw };
    }

    /// from nanoseconds
    pub fn encode(nanos: u64) Time {
        const sec: u64 = @truncate(@divFloor(nanos, ns_per_s));
        const nsec: u64 = @intCast(@rem(nanos, ns_per_s));
        const frac: u32 = @truncate((nsec << 32) / ns_per_s);
        return .{ .t = @as(u64, @intCast(sec << 32)) + frac };
    }

    /// to nanoseconds
    pub fn decode(self: Time) u64 {
        const sec: u64 = (self.t >> 32);
        const nsec = frac_to_nsec(self.t & 0xFFFFFFFF);
        return sec * ns_per_s + nsec;
    }

    //  NOTE : addition is not permitted by NTP since might overflow.

    /// NTP time subtraction which works across era bounds;
    /// works as long as the absolute difference between A and B is < 2^(n-1) (~68 years for n=32).
    pub fn sub(self: Time, other: Time) i64 {
        const a_sec: u32 = @truncate(self.t >> 32);
        const a_nsec = frac_to_nsec(self.t & 0xFFFFFFFF);
        const b_sec: u32 = @truncate(other.t >> 32);
        const b_nsec = frac_to_nsec(other.t & 0xFFFFFFFF);
        const offset: i32 = @bitCast(a_sec +% (~b_sec +% 1));
        return @as(i64, offset) * ns_per_s + (@as(i64, @intCast(a_nsec)) - @as(i64, @intCast(b_nsec)));
    }

    /// nanoseconds since the Unix epoch to NTP time since
    /// the NTP epoch / era 0.
    /// Cannot handle time before 1970-01-01 / negative Unix time.
    pub fn fromUnixNanos(nanos: u64) Time {
        return Time.encode(nanos + (@as(u64, epoch_offset) * @as(u64, ns_per_s)));
    }

    /// NTP time since epoch / era 0 to nanoseconds since the Unix epoch
    pub fn toUnixNanos(self: Time) i128 {
        return @as(i128, @intCast(self.decode())) - (@as(u64, epoch_offset) * @as(u64, ns_per_s));
    }

    // fraction to nanoseconds;
    // frac's lower (towards LSB) 32 bits hold the fraction from Time.t
    fn frac_to_nsec(frac: u64) u64 {
        const nsfrac: u64 = frac * ns_per_s;
        // >> N is the same as division by 2^N,
        // however we would have to ceil-divide if the nanoseconds fraction
        // fills equal to or more than 2^32 // 2
        if (@as(u32, @truncate(nsfrac)) >= 0x80000000) return (nsfrac >> 32) + 1;
        return nsfrac >> 32;
    }
};

test "Time set directly" {
    var t = Time{ .t = 0x0 };
    try testing.expectEqual(@as(u64, 0), t.decode());

    t = Time{ .t = 0x0000000080000000 };
    try testing.expectEqual(@as(u64, 500_000_000), t.decode());

    t = Time{ .t = 0x00000000FFFFFFFB };
    try testing.expectEqual(@as(u64, 999_999_999), t.decode());

    t.t += t.t;
    try testing.expectEqual(@as(u64, 1_999_999_998), t.decode());

    t = Time{ .t = 0x0000000180000000 };
    try testing.expectEqual(@as(u64, 1_500_000_000), t.decode());

    // 2036-02-07T06:28:16+00:00, last second of NTP era 0
    t = Time{ .t = 0xFFFFFFFFFFFFFFFB };
    try testing.expectEqual(@as(u64, 4294967295999999999), t.decode());

    // overflow:
    // t.t += (1 << 32);
}

test "Time arithmetic" {
    try testing.expectEqual(
        @as(i64, 0),
        Time.encode(ns_per_s + 1).sub(Time.encode(ns_per_s + 1)),
    );
    try testing.expectEqual(
        @as(i64, ns_per_s),
        Time.encode(ns_per_s * 2).sub(Time.encode(ns_per_s)),
    );
    try testing.expectEqual(
        -@as(i64, ns_per_s),
        Time.encode(ns_per_s).sub(Time.encode(ns_per_s * 2)),
    );
    try testing.expectEqual(
        @as(i64, -1),
        Time.encode(ns_per_s - 1).sub(Time.encode(ns_per_s)),
    );
    try testing.expectEqual(
        @as(i64, 1),
        Time.encode(ns_per_s).sub(Time.encode(ns_per_s - 1)),
    );

    // across era bounds
    var a = Time{ .t = 0xFFFFFFFF << 32 }; // last second of era n
    var b = Time{ .t = 1 << 32 }; // first second of era n+1
    try testing.expectEqual(@as(i64, -2_000_000_000), a.sub(b));
    try testing.expectEqual(@as(i64, 2_000_000_000), b.sub(a));

    // 2024-06-07, 2044-06-07
    a, b = .{ Time.encode(3926707200000000000), Time.encode(4557859200000000000) };
    try testing.expectEqual(@as(i64, -631152000000000000), a.sub(b));
    try testing.expectEqual(@as(i64, 631152000000000000), b.sub(a));
}

test "Time encode decode" {
    try testing.expectEqual(@as(u64, ns_per_s), Time.encode(ns_per_s).decode());

    try testing.expectEqual(
        @as(u64, ns_per_s * 2 + 10),
        Time.encode(ns_per_s * 2 + 10).decode(),
    );

    const ts: u64 = @as(u64, @intCast(std.time.nanoTimestamp()));
    try testing.expectEqual(ts, Time.encode(ts).decode());
}

test "Time Unix" {
    var ts: u64 = 0;
    try testing.expectEqual(epoch_offset, Time.fromUnixNanos(ts).decode() / ns_per_s);

    ts = @as(u64, @intCast(std.time.nanoTimestamp()));
    try testing.expectEqual(@as(i128, @intCast(ts)), Time.fromUnixNanos(ts).toUnixNanos());

    // TODO : negative input
}

/// Duration with lower resolution and smaller range
const TimeShort = struct {
    t: u32 = 0, // upper 16 bits: seconds, lower 16 bits: fraction

    /// from value as received in NTP packet.
    pub fn fromRaw(raw: u32) TimeShort {
        return .{ .t = raw };
    }

    /// from nanoseconds
    pub fn encode(nanos: u32) TimeShort {
        const sec: u32 = @truncate(@divFloor(nanos, ns_per_s));
        const nsec: u32 = @intCast(@rem(nanos, ns_per_s));
        const frac: u16 = @truncate((nsec << 16) / ns_per_s);
        return .{ .t = @as(u32, @intCast(sec << 16)) + frac };
    }

    /// to nanoseconds
    pub fn decode(self: TimeShort) u64 {
        const nanos: u64 = @as(u64, self.t >> 16) * ns_per_s;
        const frac: u64 = @as(u64, self.t & 0xFFFF) * ns_per_s;
        const nsec = if (@as(u16, @truncate(frac)) > 0x8000) (frac >> 16) + 1 else frac >> 16;
        return nanos + nsec;
    }
};

test "TimeShort" {
    var t = TimeShort{ .t = 0x00000000 };
    try testing.expectEqual(@as(u64, 0), t.decode());

    t = TimeShort{ .t = 0x00000001 };
    try testing.expectEqual(@as(u64, 15259), t.decode());

    t = TimeShort{ .t = 0x00008000 };
    try testing.expectEqual(@as(u64, 500_000_000), t.decode());

    t = TimeShort{ .t = 0x00018000 };
    try testing.expectEqual(@as(u64, 1_500_000_000), t.decode());
}

/// Struct equivalent of the NPT packet definition.
/// Byte order is considered if a Packet instance is serialized to bytes
/// or parsed from bytes. Bytes representation is big endian (network).
pub const Packet = packed struct {
    li_vers_mode: u8, // 2 bits leap second indicator, 3 bits protocol version, 3 bits mode
    stratum: u8 = 0,
    poll: u8 = 0,
    precision: i8 = 0,
    root_delay: u32 = 0,
    root_dispersion: u32 = 0,
    ref_id: u32 = 0,
    ts_ref: u64 = 0, // combines seconds and fraction
    ts_org: u64 = 0,
    ts_rec: u64 = 0,
    ts_xmt: u64 = 0,
    // extension field #1
    // extension field #2
    // key identifier
    // digest

    // Create a client mode NTP packet to query the time from a server.
    // Can directly set the transmit timestamp (xmt),
    // which will be returned as origin timestamp by the server.
    fn _init(version: u8, set_xmt: bool) Packet {
        const ts = if (set_xmt)
            Time.fromUnixNanos(@as(u64, @intCast(std.time.nanoTimestamp())))
        else
            Time{};
        return .{ .li_vers_mode = 0 << 6 | version << 3 | client_mode, .ts_xmt = ts.t };
    }

    /// Create an NTP packet and fill it into a bytes buffer.
    /// 'buf' must be sufficiently large to store ntp.packet_len bytes.
    /// Considers endianess; fields > 1 byte are in big endian byte order.
    pub fn toBytesBuffer(version: u8, set_xmt: bool, buf: []u8) void {
        assert(buf.len >= packet_len);
        var p: Packet = Packet._init(version, set_xmt);
        p.ts_xmt = mem.nativeToBig(u64, p.ts_xmt);
        const ntp_bytes: [packet_len]u8 = @bitCast(p);
        mem.copyForwards(u8, buf, ntp_bytes[0..]);
    }

    /// Parse bytes of the reply received from the server.
    /// Adjusts for byte order.
    pub fn parse(bytes: [packet_len]u8) Packet {
        var p: Packet = @bitCast(bytes);
        p.root_delay = mem.bigToNative(u32, p.root_delay);
        p.root_dispersion = mem.bigToNative(u32, p.root_dispersion);
        p.ref_id = mem.bigToNative(u32, p.ref_id);
        p.ts_ref = mem.bigToNative(u64, p.ts_ref);
        p.ts_org = mem.bigToNative(u64, p.ts_org);
        p.ts_rec = mem.bigToNative(u64, p.ts_rec);
        p.ts_xmt = mem.bigToNative(u64, p.ts_xmt);
        return p;
    }
};

test "Packet" {
    const p = Packet._init(3, true);
    const b: [packet_len]u8 = @bitCast(p);
    try testing.expectEqual(@as(u8, 27), b[0]);
}

/// Analyze an NTP packet received from a server.
pub const Result = struct {
    leap_indicator: u2 = 0,
    version: u3 = 0,
    mode: u3 = 0,
    stratum: u8 = 0,
    poll: u8 = 0,
    precision: i8 = 0,
    root_delay: u64 = 0,
    root_dispersion: u64 = 0,
    ref_id: u32 = 0,

    // Unix timestamps
    /// time when the server's clock was last updated
    Tref: Time = .{},
    /// T1, when the packet was created by client
    T1: Time = .{},
    /// T2, when the server received the request packet
    T2: Time = .{},
    /// T3, when the server sent the reply
    T3: Time = .{},
    /// T4, when the packet was received and processed
    T4: Time = .{},

    /// offset of the local machine relative to the server
    theta: i64 = 0,
    /// round-trip delay
    delta: i64 = 0,
    /// syncronization distance, i.e. error estimate of server clock
    lambda: u64 = 0,

    pub fn fromPacket(p: Packet, dst_time: i128) Result {
        var result = Result{};
        result.leap_indicator = @truncate((p.li_vers_mode >> 6) & 3);
        result.version = @truncate((p.li_vers_mode >> 3) & 0x7);
        result.mode = @truncate(p.li_vers_mode & 7);
        result.stratum = p.stratum;
        result.poll = p.poll;
        result.precision = p.precision;
        result.root_delay = TimeShort.fromRaw(p.root_delay).decode();
        result.root_dispersion = TimeShort.fromRaw(p.root_dispersion).decode();
        result.ref_id = p.ref_id;

        result.Tref = Time.fromRaw(p.ts_ref);
        result.T1 = Time.fromRaw(p.ts_org);
        result.T2 = Time.fromRaw(p.ts_rec);
        result.T3 = Time.fromRaw(p.ts_xmt);
        result.T4 = Time.fromUnixNanos(@intCast(dst_time));

        // offset / theta = T(B) - T(A) = 1/2 * [(T2-T1) + (T3-T4)]
        result.theta = @divFloor((result.T2.sub(result.T1) + result.T3.sub(result.T4)), 2);

        // roundtrip duration / delta = T(ABA) = (T4-T1) - (T3-T2)
        result.delta = result.T4.sub(result.T1) - result.T3.sub(result.T2);

        // sync distance; error estimate of server clock
        result.lambda = result.root_dispersion +| result.root_delay / 2;

        return result;
    }

    // TODO : add validate() - ref time fresh enough, stratum <= 16 etc.

};

test "Result" {
    // random bytes can be parsed and analyzed
    const rand = std.crypto.random;
    var b: [packet_len]u8 = undefined;
    var i: usize = 0;
    while (i < 1_000_000) : (i += 1) {
        rand.bytes(&b);
        const r: Result = Result.fromPacket(
            Packet.parse(b),
            std.time.nanoTimestamp(),
        );
        std.mem.doNotOptimizeAway(r);
    }

    var p = Packet._init(3, true);
    // client |  server  | client
    //   T1   ->T2  ->T3  ->T4
    //   1      0     0     3
    // => offset -2, roundtrip 2
    const now: u64 = @intCast(std.time.nanoTimestamp());
    p.ts_org = Time.fromUnixNanos(now - 2 * ns_per_s).t;
    p.ts_rec = Time.fromUnixNanos(now - 3 * ns_per_s).t;
    p.ts_xmt = Time.fromUnixNanos(now - 3 * ns_per_s).t;
    var res = Result.fromPacket(p, now);
    try testing.expectEqual(@as(i64, 2 * ns_per_s), res.delta);
    try testing.expectEqual(-@as(i64, 2 * ns_per_s), res.theta);

    //   0      2     2     1
    // => offset 1.5, roundtrip 1
    p.ts_org = Time.fromUnixNanos(now - 1 * ns_per_s).t;
    p.ts_rec = Time.fromUnixNanos(now + 1 * ns_per_s).t;
    p.ts_xmt = Time.fromUnixNanos(now + 1 * ns_per_s).t;
    res = Result.fromPacket(p, now);
    try testing.expectEqual(@as(i64, 1 * ns_per_s), res.delta);
    try testing.expectEqual(@as(i64, 15 * ns_per_s / 10), res.theta);
}
