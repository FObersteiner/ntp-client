//! NTP client library
const std = @import("std");
const mem = std.mem;
const rand = std.crypto.random;
const print = std.debug.print;
const testing = std.testing;
const assert = std.debug.assert;

const ns_per_s: u64 = 1_000_000_000;
const s_per_ntp_era: u64 = 1 << 32;
const u64_max: u64 = 0xFFFFFFFFFFFFFFFF;

/// NTP packet has 48 bytes if extension and key / digest fields are excluded
pub const packet_len: usize = 48;

// min/max constants see <https://datatracker.ietf.org/doc/html/rfc5905#section-7.2>

pub const max_stratum: u8 = 16;

// TODO : where is this applicable ?
pub const max_dispersion: u64 = 16; // [s]

/// [s]; ref. root distance (dispersion + delay/2)
pub const max_dist: u64 = 1;

/// [s]; server must have synced in last x seconds
pub const max_refclock_age: i64 = 1024;

/// 36 h
pub const max_poll: i8 = 17;

/// 16 s - ignored in result check
pub const min_poll: i8 = 4;

/// Offset between the Unix epoch and the NTP epoch, era zero, in seconds
pub const epoch_offset: u32 = 2_208_988_800;

/// The current NTP era, 0 = [1900-01-01T00:00:00Z..2036-02-07T06:28:15Z]
pub const ntp_era: i8 = 0;

pub const client_mode: u8 = 3;
pub const server_mode: u8 = 4;

/// NTP precision and poll interval come as period of log2 seconds
pub fn periodToNanos(p: i8) u64 {
    if (p > 63) return u64_max;
    if (p < -63) return 0;
    if (p > 0) return ns_per_s << @as(u6, @intCast(p));
    if (p < 0) return ns_per_s >> @as(u6, @intCast(-p));
    return ns_per_s;
}

pub fn periodToSeconds(p: i8) u64 {
    if (p > 63) return u64_max;
    if (p > 0) return @as(u64, 1) << @as(u6, @intCast(p));
    // ignore negative input (ceil period); cannot represent sub-second period
    return 1;
}

/// Time (duration, to be precise) since epoch.
/// - 32 bits seconds: ~ 136 years per era (64 bits would be ~ 5.8e10 years)
/// - 32 bits fraction: precision is ~ 2.3e-10 s (64 bits would be ~ 5.4e-20 s)
/// - total nanoseconds: ~ 2^62
///
/// In an NTP packet, this represents a duration since the NTP epoch.
/// Era 0 starts at zero hours on 1900-01-01.
///
pub const Time = struct {
    t: u64 = 0, // upper 32 bits: seconds, lower 32 bits: fraction
    era: i8 = ntp_era, // this is only used for Unix time input / output

    /// from value as received in NTP packet.
    pub fn fromRaw(raw: u64) Time {
        return .{ .t = raw };
    }

    /// from nanoseconds since epoch in current era
    pub fn encode(nanos: u64) Time {
        const sec: u64 = @truncate(@divFloor(nanos, ns_per_s));
        const nsec: u64 = @intCast(@rem(nanos, ns_per_s));
        const frac: u32 = @truncate((nsec << 32) / ns_per_s);
        return .{ .t = @as(u64, @intCast(sec << 32)) + frac };
    }

    /// to nanoseconds since epoch in current era
    pub fn decode(self: Time) u64 {
        const sec: u64 = (self.t >> 32);
        const nsec = frac_to_nsec(self.t & 0xFFFFFFFF);
        return sec * ns_per_s + nsec;
    }

    //  Addition is not permitted by NTP since might overflow.

    /// NTP time subtraction which works across era bounds;
    /// works as long as the absolute difference between A and B is < 2^(n-1) (~68 years for n=32).
    pub fn sub(this: Time, other: Time) i64 {
        const a_sec: u32 = @truncate(this.t >> 32);
        const a_nsec = frac_to_nsec(this.t & 0xFFFFFFFF);
        const b_sec: u32 = @truncate(other.t >> 32);
        const b_nsec = frac_to_nsec(other.t & 0xFFFFFFFF);
        const offset: i32 = @bitCast(a_sec +% (~b_sec +% 1));
        return @as(i64, offset) * ns_per_s + (@as(i64, @intCast(a_nsec)) - @as(i64, @intCast(b_nsec)));
    }

    /// nanoseconds since the Unix epoch to NTP time since
    /// the NTP epoch / era 0.
    /// Cannot handle time before 1970-01-01 / negative Unix time.
    pub fn fromUnixNanos(nanos: i128) Time {
        // TODO : consider ntp era
        var result: Time = .{ .era = @intCast(@divFloor(@divFloor(nanos, ns_per_s) + epoch_offset, s_per_ntp_era)) };
        var ntp_nanos: i128 = @as(i128, nanos) + ns_per_s * epoch_offset;
        ntp_nanos -= result.era * @as(i128, ns_per_s * s_per_ntp_era);
        result.t = Time.encode(@intCast(ntp_nanos)).t;
        return result;
    }

    /// NTP time since epoch / era 0 to nanoseconds since the Unix epoch
    pub fn toUnixNanos(time: Time) i128 {
        // TODO : consider ntp era
        const era_offset: i128 = time.era * @as(i128, s_per_ntp_era * ns_per_s);
        const epoch_offset_ns: i128 = @as(i128, epoch_offset) * @as(i128, ns_per_s);
        return @as(i128, @intCast(time.decode())) - epoch_offset_ns + era_offset;
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

/// Duration with lower resolution and smaller range
pub const TimeShort = struct {
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
    pub fn decode(ts: TimeShort) u64 {
        const nanos: u64 = @as(u64, ts.t >> 16) * ns_per_s;
        const frac: u64 = @as(u64, ts.t & 0xFFFF) * ns_per_s;
        const nsec = if (@as(u16, @truncate(frac)) > 0x8000) (frac >> 16) + 1 else frac >> 16;
        return nanos + nsec;
    }
};

/// Struct equivalent of the NTP packet definition.
/// Byte order is considered if a Packet instance is serialized to bytes
/// or parsed from bytes. Bytes representation is big endian (network).
pub const Packet = packed struct {
    li_vers_mode: u8, // 2 bits leap second indicator, 3 bits protocol version, 3 bits mode
    stratum: u8 = 0,
    poll: i8 = 0,
    precision: i8 = 0x20,
    root_delay: u32 = 0,
    root_dispersion: u32 = 0,
    ref_id: u32 = 0,
    ts_ref: u64 = 0,
    ts_org: u64 = 0,
    ts_rec: u64 = 0,
    ts_xmt: u64 = 0,
    // extension field #1
    // extension field #2
    // key identifier
    // digest

    /// Create a client mode NTP packet to query the time from a server.
    /// Random bytes are used as client transmit timestamp (xmt),
    /// see <https://www.ietf.org/archive/id/draft-ietf-ntp-data-minimization-04.txt>.
    /// For a single query, the poll interval should be 0.
    pub fn init(version: u8) Packet {
        var b: [8]u8 = undefined;
        rand.bytes(&b);
        return .{
            .li_vers_mode = 0 << 6 | version << 3 | client_mode,
            .ts_xmt = @bitCast(b),
        };
    }

    /// Create an NTP packet and fill it into a bytes buffer.
    /// 'buf' must be sufficiently large to store ntp.packet_len bytes.
    /// Considers endianess; fields > 1 byte are in big endian byte order.
    pub fn initToBuffer(version: u8, buf: []u8) void {
        assert(buf.len >= packet_len);
        var p: Packet = Packet.init(version);
        p.ts_xmt = mem.nativeToBig(u64, p.ts_xmt);
        const ntp_bytes: [packet_len]u8 = @bitCast(p);
        mem.copyForwards(u8, buf, ntp_bytes[0..]);
    }

    /// Parse bytes of the reply received from the server.
    /// Adjusts for byte order.
    /// ref_id is NOT byte-swapped even if native is little-endian.
    pub fn parse(bytes: [packet_len]u8) Packet {
        var p: Packet = @bitCast(bytes);
        p.root_delay = mem.bigToNative(u32, p.root_delay);
        p.root_dispersion = mem.bigToNative(u32, p.root_dispersion);
        p.ts_ref = mem.bigToNative(u64, p.ts_ref);
        p.ts_org = mem.bigToNative(u64, p.ts_org);
        p.ts_rec = mem.bigToNative(u64, p.ts_rec);
        p.ts_xmt = mem.bigToNative(u64, p.ts_xmt);
        return p;
    }
};

/// Analyze an NTP packet received from a server.
pub const Result = struct {
    leap_indicator: u2 = 0,
    version: u3 = 0,
    mode: u3 = 0,
    stratum: u8 = 0,
    poll: i8 = 0, // log2 seconds
    poll_period: i32 = 0,
    precision: i8 = 0, // log2 seconds
    precision_ns: u64 = 0,
    root_delay: u64 = 0,
    root_delay_client: u64 = 0,
    root_dispersion: u64 = 0,
    ref_id: u32 = 0,
    __ref_id: [4]u8 = undefined,

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

    /// offset in ns of the local machine vs. the server
    offset: i64 = 0,
    /// round-trip delay in ns (network)
    delay: i64 = 0,
    // TODO : inter-arrival jitter (RFC 3550)
    ia_jitter: f64 = 0,
    /// dispersion / clock error estimate in ns
    disp: u64 = 0,

    /// results from a server reply packet.
    /// client org and rec times must be provided by the caller.
    pub fn fromPacket(p: Packet, T1: Time, T4: Time) Result {
        var result = Result{};
        result.leap_indicator = @truncate((p.li_vers_mode >> 6) & 3);
        result.version = @truncate((p.li_vers_mode >> 3) & 0x7);
        result.mode = @truncate(p.li_vers_mode & 7);
        result.stratum = p.stratum;
        result.precision = p.precision;
        result.poll = p.poll;
        result.ref_id = p.ref_id;
        result.root_dispersion = TimeShort.fromRaw(p.root_dispersion).decode();
        result.root_delay = TimeShort.fromRaw(p.root_delay).decode();

        result.Tref = Time.fromRaw(p.ts_ref);
        result.T1 = T1;
        result.T2 = Time.fromRaw(p.ts_rec);
        result.T3 = Time.fromRaw(p.ts_xmt);
        result.T4 = T4;

        // poll interval comes as log2 seconds and should be 4...17 or 0
        result.poll_period = switch (p.poll) {
            0 => 0, // unspecified
            1...17 => @intCast(periodToSeconds(p.poll)),
            else => -1,
        };
        result.precision_ns = periodToNanos(result.precision);

        // offset = T(B) - T(A) = 1/2 * [(T2-T1) + (T3-T4)]
        result.offset = @divFloor((result.T2.sub(result.T1) + result.T3.sub(result.T4)), 2);

        // roundtrip delay = T(ABA) = (T4-T1) - (T3-T2)
        result.delay = result.T4.sub(result.T1) - result.T3.sub(result.T2);

        // Client delay to the root, as sum of delay to timeserver and timeserver root delay.
        // Client delay might be negative in edge case of very close proximity to server.
        const delay_normalized: u64 = if (result.delay < 0) 0 else @intCast(result.delay);
        result.root_delay_client = result.root_delay + delay_normalized;

        // from RFC5905: For packet stratum 0 (unspecified or invalid), this
        // is a four-character ASCII [RFC1345] string, called the "kiss code",
        // used for debugging and monitoring purposes.  For stratum 1 (reference
        // clock), this is a four-octet, left-justified, zero-padded ASCII
        // string assigned to the reference clock.
        result.__ref_id = std.mem.zeroes([4]u8);
        if (result.refIDprintable()) {
            result.__ref_id = @bitCast(result.ref_id);
        }

        return result;
    }

    /// current time in nanoseconds since the Unix epoch corrected by offset reported
    /// by NTP server.
    pub fn correctTime(result: Result, uncorrected: i128) i128 {
        return uncorrected + result.offset;
    }

    // TODO : stratum 0 --> Kiss of Death --> check code
    /// ref_id might be a 4-letter ASCII string.
    /// Only applicable if stratum 0 (kiss code) or stratum 1.
    pub fn refIDprintable(result: Result) bool {
        if (result.stratum >= 2) return false;
        const data: [4]u8 = @bitCast(result.ref_id);
        for (data) |c| {
            if ((c < ' ' or c > '~') and c != 0) return false;
        }
        return true;
    }

    /// NTP query result flagging
    /// bit | meaning
    /// ----|------------------
    ///  0  | there is an unsynchronized leapsecond
    ///  1  | incorrect NTP version, must be 3 or 4
    ///  2  | mode in received packet is not server-mode
    ///  3  | stratum is too large (> 16)
    ///  4  | poll frequency incorrect
    ///  5  | sync distance of server too large (> 16s)
    ///  6  | server last synced long ago
    ///  7  | client send time after client receive time
    ///  8  | server send time after server receive time
    ///  9  | round-trip time must be positive
    pub const result_flag = enum(u32) {
        OK = 0,
        unsynchronized_leapsecond = 1,
        incorrect_version = (1 << 1),
        incorrect_mode = (1 << 2),
        stratum_too_large = (1 << 3),
        incorrect_poll_freq = (1 << 4),
        server_sync_dist_too_large = (1 << 5),
        server_sync_outdated = (1 << 6),
        client_send_after_receive = (1 << 7),
        server_send_after_receive = (1 << 8),
        negative_rtt = (1 << 9),
    };

    pub fn printFlags(flags: u32, buf: []u8) !void {
        if (flags == 0) {
            _ = try std.fmt.bufPrint(buf, "0 (OK)", .{});
            return;
        }
        var idx: usize = 0;
        for (std.enums.values(result_flag)) |v| {
            const prefix = if (idx > 0) ", " else "";
            if ((@intFromEnum(v) & flags) > 0) {
                const s = try std.fmt.bufPrint(buf[idx..], "{s}{s}", .{ prefix, @tagName(v) });
                idx += s.len;
            }
        }
    }

    /// Validate result from an NTP query. Returns a set of flags as a u32.
    /// A result of zero means OK. If a bit is set, something is wrong.
    /// See 'result_flag'.
    pub fn validate(result: Result) u32 {
        var flags: u32 = @intFromEnum(result_flag.OK);

        // # 0 - unsynchronized leapsecond
        if (result.leap_indicator == 3)
            flags |= @intFromEnum(result_flag.unsynchronized_leapsecond);

        // # 1 - version not 3 or 4
        if (result.version > 4 or result.version < 3)
            flags |= @intFromEnum(result_flag.incorrect_version);

        // # 2 - mode not server-mode
        if (result.mode != server_mode)
            flags |= @intFromEnum(result_flag.incorrect_mode);

        // # 3 - stratum > max_stratum
        if (result.stratum > max_stratum)
            flags |= @intFromEnum(result_flag.stratum_too_large);

        // # 4 - incorrect_poll_freq = (1 << 4),
        // Note: RFC5905 specifies a min poll of 4, we ignore this deliberately
        if (result.poll > max_poll)
            flags |= @intFromEnum(result_flag.incorrect_poll_freq);

        // # 5 - sync distance of the server;
        // Note: root_dispersion and _delay as found in the NTP packet only refer to the
        //       server. To get the actual root distance, the client's delay / dispersion
        //       to the root would have to be used.
        if ((result.root_dispersion +| result.root_delay / 2) > max_dist * ns_per_s)
            flags |= @intFromEnum(result_flag.server_sync_dist_too_large);

        // # 6 - server_sync_outdated = (1 << 6),
        if (result.T2.sub(result.Tref) > 1024 * ns_per_s)
            flags |= @intFromEnum(result_flag.server_sync_outdated);

        // # 8 - T1>T4: cannot receive before send
        // Note: #1 this is incorrect across an NTP era boundary
        //       #2 this might be incorrect due to poor clock resolution / accuracy
        if (result.T1.decode() > result.T4.decode())
            flags |= @intFromEnum(result_flag.client_send_after_receive);

        // # 9 - T2>T3: cannot receive before send
        // Note: #1 this is incorrect across an NTP era boundary
        //       #2 this might be incorrect due to poor clock resolution / accuracy
        if (result.T2.decode() > result.T3.decode())
            flags |= @intFromEnum(result_flag.server_send_after_receive);

        // # 10 - round-trip time must not be negative
        if (result.delay < 0)
            flags |= @intFromEnum(result_flag.negative_rtt);

        // TODO : ?
        // pub const max_dispersion: u64 = 16; // [s]

        return flags;
    }
};
