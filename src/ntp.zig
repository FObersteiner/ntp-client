// Copyright © 2024 Florian Obersteiner <f.obersteiner@posteo.de>
// License: see LICENSE in the root directory of the repo.
//
// ~~~ NTP client library ~~~
//
// NTP v4 data format, from <https://datatracker.ietf.org/doc/html/rfc5905>:
//
// 0                   1                   2                   3
// 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
// |LI | VN  |Mode |    Stratum     |     Poll      |  Precision   |
// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
// |                         Root Delay                            |
// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
// |                         Root Dispersion                       |
// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
// |                          Reference ID                         |
// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
// |                                                               |
// +                     Reference Timestamp (64)                  +
// |                                                               |
// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
// |                                                               |
// +                      Origin Timestamp (64)                    +
// |                                                               |
// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
// |                                                               |
// +                      Receive Timestamp (64)                   +
// |                                                               |
// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
// |                                                               |
// +                      Transmit Timestamp (64)                  +
// |                                                               |
// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
// |                                                               |
// .                                                               .
// .                    Extension Field 1 (variable)               .
// .                                                               .
// |                                                               |
// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
// |                                                               |
// .                                                               .
// .                    Extension Field 2 (variable)               .
// .                                                               .
// |                                                               |
// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
// |                          Key Identifier                       |
// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
// |                                                               |
// |                            dgst (128)                         |
// |                                                               |
// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
//
// NOTE : only fields up to and including Transmit Timestamp are used further on.
// Extensions are not supported.
//
const std = @import("std");
const print = std.debug.print;
const testing = std.testing;
const native_endian = @import("builtin").target.cpu.arch.endian();

/// NTP packet has 48 bytes if extension and key / digest fields are excluded.
pub const packet_len: usize = 48;

/// offset between the Unix epoch and the NTP epoch in seconds
pub const epoch_offset: u32 = 2_208_988_800;

const ns_per_s: u64 = 1_000_000_000;
const client_mode: u8 = 3;

pub const Packet = packed struct {
    li_vers_mode: u8, // 2 bits leap second indicator, 3 bits protocol version, 3 bits mode
    stratum: u8 = 0,
    poll: u8 = 0,
    precision: i8 = 0,
    root_delay: u32 = 0,
    root_dispersion: u32 = 0,
    ref_id: u32 = 0,
    ts_ref_s: u32 = 0,
    ts_ref_frac: u32 = 0,
    ts_org_s: u32 = 0,
    ts_org_frac: u32 = 0,
    ts_rec_s: u32 = 0,
    ts_rec_frac: u32 = 0,
    ts_xmt_s: u32 = 0,
    ts_xmt_frac: u32 = 0,

    /// Create a client mode NTP packet to query the time from a server.
    /// Can directly set the transmit timestamp (xmt), which will be returned as origin timestamp by the server.
    pub fn init(version: u8, set_xmt: bool) Packet {
        const ts = if (set_xmt)
            NtpTime.fromUnixNanos(std.time.nanoTimestamp())
        else
            NtpTime{ .fraction = 0, .seconds = 0 };
        return .{
            .li_vers_mode = 0 << 6 | version << 3 | client_mode,
            .ts_xmt_s = ts.seconds,
            .ts_xmt_frac = ts.fraction,
        };
    }

    /// Same as init but directly copies bytes into a buffer
    pub fn intiToBuffer(version: u8, set_xmt: bool, buf: []u8) void {
        const ntp_bytes: [packet_len]u8 = @bitCast(Packet.init(version, set_xmt));
        std.mem.copyForwards(u8, buf, ntp_bytes[0..]);
    }

    /// Parse bytes of the reply received from the server.
    pub fn parse(bytes: [packet_len]u8) Packet {
        return @bitCast(bytes);
    }

    /// Parse and analyze NTP packet data.
    pub fn analyze(bytes: [packet_len]u8) Result {
        return Result.fromPacket(parse(bytes));
    }
};

test "packet" {
    const p = Packet.init(3, true);
    var b: [packet_len]u8 = @bitCast(p);
    try testing.expectEqual(@as(u8, 27), b[0]);

    b = [packet_len]u8{ 28, 2, 0, 230, 0, 0, 0, 253, 0, 0, 0, 22, 189, 97, 54, 122, 233, 245, 195, 223, 205, 24, 8, 73, 233, 245, 196, 248, 202, 252, 152, 0, 233, 245, 196, 249, 41, 126, 163, 19, 233, 245, 196, 249, 41, 129, 54, 38 };
    const have: Packet = Packet.parse(b);
    const want: Packet = .{ .li_vers_mode = 28, .stratum = 2, .poll = 0, .precision = -26, .root_delay = 4244635648, .root_dispersion = 369098752, .ref_id = 2050384317, .ts_ref_s = 3754161641, .ts_ref_frac = 1225267405, .ts_org_s = 4173657577, .ts_org_frac = 10026186, .ts_rec_s = 4190434793, .ts_rec_frac = 329481769, .ts_xmt_s = 4190434793, .ts_xmt_frac = 641106217 };
    try testing.expect(std.meta.eql(want, have));
}

pub const NtpTime = struct {
    seconds: u32, // big endian !
    fraction: u32, // big endian !

    pub fn init(sec: u32, frac: u32) NtpTime {
        return .{ .seconds = sec, .fraction = frac };
    }

    pub fn fromUnixNanos(nanos: i128) NtpTime { // use i128 here since this is what std.time.nanoTimestamp gives use
        const _secs: i64 = @truncate(@divFloor(nanos, @as(i128, ns_per_s)) + epoch_offset);
        const secs: u32 = if (_secs < 0) 0 else @intCast(_secs);
        const nsec: u64 = @intCast(@rem(nanos, @as(i128, ns_per_s)));
        const frac: u32 = @truncate((nsec << 32) / ns_per_s);
        return .{
            .seconds = if (native_endian == .big) secs else @byteSwap(secs),
            .fraction = if (native_endian == .big) frac else @byteSwap(frac),
        };
    }

    pub fn toUnixNanos(self: NtpTime) i64 {
        const _seconds = if (native_endian == .big) self.seconds else @byteSwap(self.seconds);
        const _fraction = if (native_endian == .big) self.fraction else @byteSwap(self.fraction);
        const ns: i64 = (@as(i64, _seconds) - @as(i64, epoch_offset)) * @as(i64, ns_per_s);
        const frac: i64 = (@as(i64, _fraction) * ns_per_s);
        const nsec = if (frac >= 0x80000000) (frac >> 32) + 1 else (frac >> 32);
        return ns + nsec;
    }
};

test "ntp time struct" {
    // zero is the NTP epoch offset
    const ntpt0 = NtpTime{ .seconds = 0, .fraction = 0 };
    const unix = ntpt0.toUnixNanos();
    try testing.expectEqual(-@as(i64, epoch_offset) * ns_per_s, unix);

    const nanos = -@as(i128, epoch_offset) * ns_per_s;
    const ntpt00 = NtpTime.fromUnixNanos(nanos);
    try testing.expectEqual(@as(u32, 0), ntpt00.seconds);
    try testing.expectEqual(@as(u32, 0), ntpt00.fraction);

    // Unix time round-trip
    const t0 = std.time.nanoTimestamp();
    const ntpt = NtpTime.fromUnixNanos(t0);
    const t1 = ntpt.toUnixNanos();
    try testing.expectEqual(t0, t1);

    // one day
    var i: u32 = 86400 + epoch_offset;
    i = if (native_endian == .big) i else @byteSwap(i);
    const ntpt1 = NtpTime.init(i, 0);
    const t2 = ntpt1.toUnixNanos();
    try testing.expectEqual(@as(i64, 86400_000_000_000), t2);
}

/// Analyze an NTP packet received from a server.
pub const Result = struct {
    leap_indicator: u2 = 0,
    version: u3 = 0,
    mode: u3 = 0,
    stratum: u8 = 0,
    poll: u8 = 0,
    precision: i8 = 0,
    root_delay: u32 = 0,
    root_dispersion: u32 = 0,
    ref_id: u32 = 0,

    /// time when the server's clock was last updated
    ts_ref: i64 = 0,
    /// T1, when the packet was created by client
    ts_org: i64 = 0,
    /// T2, when the server received the request packet
    ts_rec: i64 = 0,
    /// T3, when the server sent the reply
    ts_xmt: i64 = 0,
    /// T4, when the packet was received and processed
    ts_processed: i64 = 0,
    /// offset of the local machine relative to the server
    theta: i64 = 0,
    /// round-trip delay
    delta: i64 = 0,

    pub fn fromPacket(p: Packet) Result {
        var result = Result{ .ts_processed = @truncate(std.time.nanoTimestamp()) };
        result.ts_ref = NtpTime.init(p.ts_ref_s, p.ts_ref_frac).toUnixNanos();
        result.ts_org = NtpTime.init(p.ts_org_s, p.ts_org_frac).toUnixNanos();
        result.ts_rec = NtpTime.init(p.ts_rec_s, p.ts_rec_frac).toUnixNanos();
        result.ts_xmt = NtpTime.init(p.ts_xmt_s, p.ts_xmt_frac).toUnixNanos();

        // theta = T(B) - T(A) = 1/2 * [(T2-T1) + (T3-T4)]
        result.theta = @divFloor(((result.ts_rec - result.ts_org) + (result.ts_xmt - result.ts_processed)), 2);
        // delta = T(ABA) = (T4-T1) - (T3-T2)
        result.delta = (result.ts_processed - result.ts_org) - (result.ts_xmt - result.ts_rec);

        result.leap_indicator = @truncate((p.li_vers_mode >> 6) & 3);
        result.version = @truncate((p.li_vers_mode >> 3) & 0x7);
        result.mode = @truncate(p.li_vers_mode & 7);
        result.stratum = p.stratum;
        result.poll = p.poll;
        result.precision = p.precision;
        result.root_delay = if (native_endian == .big) p.root_delay else @byteSwap(p.root_delay);
        result.root_dispersion = if (native_endian == .big) p.root_dispersion else @byteSwap(p.root_dispersion);
        result.ref_id = if (native_endian == .big) p.ref_id else @byteSwap(p.ref_id);

        return result;
    }

    pub fn format(self: Result, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        const theat_f: f64 = @as(f64, @floatFromInt(self.theta)) / @as(f64, ns_per_s);
        const delta_f: f64 = @as(f64, @floatFromInt(self.delta)) / @as(f64, ns_per_s);
        try writer.print(
            \\--- NPT query result --->
            \\leap indicator: {d}
            \\version: {d}
            \\mode: {d}
            \\stratum: {d}
            \\poll: {d}
            \\precision: {d}
            \\root_delay: {d}
            \\root_dispersion: {d}
            \\ref_id: {d}
            \\---
            \\server last synced      : {d}
            \\orgigin timestamp  (T1) : {d}
            \\reception timstamp (T2) : {d}
            \\transmit timestamp (T3) : {d}
            \\process timestamp  (T4) : {d}
            \\---
            \\offset to timserver: {d} ns ({d:.6} s)
            \\round-trip delay:    {d} ns ({d:.6} s)
            \\<---
        ,
            .{
                self.leap_indicator,
                self.version,
                self.mode,
                self.stratum,
                self.poll,
                self.precision,
                self.root_delay,
                self.root_dispersion,
                self.ref_id,
                self.ts_ref,
                self.ts_org,
                self.ts_rec,
                self.ts_xmt,
                self.ts_processed,
                self.theta,
                theat_f,
                self.delta,
                delta_f,
            },
        );
    }
};

test "query result" {
    const p = Packet.init(3, true);
    const res = Result.fromPacket(p);
    try testing.expect(res.theta <= 0);
    try testing.expect(res.delta >= 0);
    const now: i64 = @truncate(std.time.nanoTimestamp());
    try testing.expect(now >= res.ts_xmt);
}
