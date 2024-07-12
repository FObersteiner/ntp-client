const std = @import("std");
const testing = std.testing;
const print = std.debug.print;
const rand = std.crypto.random;
const ntp = @import("ntplib");
const ns_per_s = 1_000_000_000;

test "period (poll)" {
    var s = ntp.periodToSeconds(17);
    try testing.expectEqual(std.math.powi(u64, 2, 17), s);
    s = ntp.periodToSeconds(0);
    try testing.expectEqual(1, s);
    s = ntp.periodToSeconds(-1);
    try testing.expectEqual(1, s);

    const ns = ntp.periodToNanos(5);
    const want = try std.math.powi(u64, 2, 5);
    try testing.expectEqual(want * ns_per_s, ns);
}

test "NTP time, set directly" {
    var t = ntp.Time{ .t = 0x0 };
    try testing.expectEqual(@as(u64, 0), t.decode());

    t = ntp.Time{ .t = 0x0000000080000000 };
    try testing.expectEqual(@as(u64, 500_000_000), t.decode());

    t = ntp.Time{ .t = 0x00000000FFFFFFFB };
    try testing.expectEqual(@as(u64, 999_999_999), t.decode());

    t.t += t.t;
    try testing.expectEqual(@as(u64, 1_999_999_998), t.decode());

    t = ntp.Time{ .t = 0x0000000180000000 };
    try testing.expectEqual(@as(u64, 1_500_000_000), t.decode());

    // 2036-02-07T06:28:16+00:00, last second of NTP era 0
    t = ntp.Time{ .t = 0xFFFFFFFFFFFFFFFB };
    try testing.expectEqual(@as(u64, 4294967295999999999), t.decode());

    // overflow:
    // t.t += (1 << 32);
}

test "NTP time encode decode" {
    try testing.expectEqual(@as(u64, ns_per_s), ntp.Time.encode(ns_per_s).decode());

    try testing.expectEqual(
        @as(u64, ns_per_s * 2 + 10),
        ntp.Time.encode(ns_per_s * 2 + 10).decode(),
    );

    const ts: u64 = @as(u64, @intCast(std.time.nanoTimestamp()));
    try testing.expectEqual(ts, ntp.Time.encode(ts).decode());
}

test "NTP time vs. Unix time" {
    var ts: i128 = 0;
    try testing.expectEqual(ntp.epoch_offset, ntp.Time.fromUnixNanos(ts).decode() / ns_per_s);

    ts = std.time.nanoTimestamp();
    try testing.expectEqual(ts, ntp.Time.fromUnixNanos(ts).toUnixNanos());

    // 2036-02-07T06:28:17+00:00 --> NTP era 1
    ts = 2085978497000000000;
    try testing.expectEqual(ts, ntp.Time.fromUnixNanos(ts).toUnixNanos());

    // 1899-12-31T23:59:59+00:00 --> NTP era -1
    ts = -2208988801000000000;
    try testing.expectEqual(ts, ntp.Time.fromUnixNanos(ts).toUnixNanos());
}

test "NTP time arithmetic" {
    try testing.expectEqual(
        @as(i64, 0),
        ntp.Time.encode(ns_per_s + 1).sub(ntp.Time.encode(ns_per_s + 1)),
    );
    try testing.expectEqual(
        @as(i64, ns_per_s),
        ntp.Time.encode(ns_per_s * 2).sub(ntp.Time.encode(ns_per_s)),
    );
    try testing.expectEqual(
        -@as(i64, ns_per_s),
        ntp.Time.encode(ns_per_s).sub(ntp.Time.encode(ns_per_s * 2)),
    );
    try testing.expectEqual(
        @as(i64, -1),
        ntp.Time.encode(ns_per_s - 1).sub(ntp.Time.encode(ns_per_s)),
    );
    try testing.expectEqual(
        @as(i64, 1),
        ntp.Time.encode(ns_per_s).sub(ntp.Time.encode(ns_per_s - 1)),
    );

    // across era bounds
    var a = ntp.Time{ .t = 0xFFFFFFFF << 32 }; // last second of era n
    var b = ntp.Time{ .t = 1 << 32 }; // first second of era n+1
    try testing.expectEqual(@as(i64, -2_000_000_000), a.sub(b));
    try testing.expectEqual(@as(i64, 2_000_000_000), b.sub(a));

    // 2024-06-07, 2044-06-07
    a, b = .{ ntp.Time.encode(3926707200000000000), ntp.Time.encode(4557859200000000000) };
    try testing.expectEqual(@as(i64, -631152000000000000), a.sub(b));
    try testing.expectEqual(@as(i64, 631152000000000000), b.sub(a));
}

test "NTP time short / 32 bits" {
    var t = ntp.TimeShort{ .t = 0x00000000 };
    try testing.expectEqual(@as(u64, 0), t.decode());

    t = ntp.TimeShort{ .t = 0x00000001 };
    try testing.expectEqual(@as(u64, 15259), t.decode());

    t = ntp.TimeShort{ .t = 0x00008000 };
    try testing.expectEqual(@as(u64, 500_000_000), t.decode());

    t = ntp.TimeShort{ .t = 0x00018000 };
    try testing.expectEqual(@as(u64, 1_500_000_000), t.decode());

    t = ntp.TimeShort{ .t = 0xffff0000 };
    try testing.expectEqual(@as(u64, 65535 * ns_per_s), t.decode());
}

test "query result - random bytes" {
    var b: [ntp.packet_len]u8 = undefined;
    var i: usize = 0;
    while (i < 1_000_000) : (i += 1) {
        rand.bytes(&b);
        const r: ntp.Result = ntp.Result.fromPacket(ntp.Packet.parse(b), ntp.Time{}, ntp.Time{});
        std.mem.doNotOptimizeAway(r);
    }
}

test "NTP packet" {
    const p = ntp.Packet.init(3);
    try testing.expectEqual(@as(i8, 32), p.precision);
    const b: [ntp.packet_len]u8 = @bitCast(p);
    try testing.expectEqual(@as(u8, 27), b[0]);
}

test "Result - delay, offset" {
    const now: u64 = @intCast(std.time.nanoTimestamp());
    var p = ntp.Packet.init(4);

    // client |  server  | client
    //   T1   ->T2  ->T3  ->T4
    //   1      0     0     3
    // => offset -2, roundtrip 2
    var T1 = ntp.Time.fromUnixNanos(now + 1 * ns_per_s);
    p.ts_rec = ntp.Time.fromUnixNanos(now).t;
    p.ts_xmt = ntp.Time.fromUnixNanos(now).t;
    var T4 = ntp.Time.fromUnixNanos(now + 3 * ns_per_s);
    var res = ntp.Result.fromPacket(p, T1, T4);
    try testing.expectEqual(@as(i64, 2 * ns_per_s), res.delay);
    try testing.expectEqual(-@as(i64, 2 * ns_per_s), res.offset);
    try testing.expectEqual(@as(i128, now - 2 * ns_per_s), res.correctTime(@as(i128, now)));

    //   0      2     2     1
    // => offset 1.5, roundtrip 1
    T1 = ntp.Time.fromUnixNanos(now);
    p.ts_rec = ntp.Time.fromUnixNanos(now + 2 * ns_per_s).t;
    p.ts_xmt = ntp.Time.fromUnixNanos(now + 2 * ns_per_s).t;
    T4 = ntp.Time.fromUnixNanos(now + 1 * ns_per_s);
    res = ntp.Result.fromPacket(p, T1, T4);
    try testing.expectEqual(@as(i64, 1 * ns_per_s), res.delay);
    try testing.expectEqual(@as(i64, 15 * ns_per_s / 10), res.offset);
    try testing.expectEqual(@as(i128, now + 15 * ns_per_s / 10), res.correctTime(@as(i128, now)));

    //   0      20     21   5
    // => offset 18, roundtrip 4
    T1 = ntp.Time.fromUnixNanos(now);
    p.ts_rec = ntp.Time.fromUnixNanos(now + 20 * ns_per_s).t;
    p.ts_xmt = ntp.Time.fromUnixNanos(now + 21 * ns_per_s).t;
    T4 = ntp.Time.fromUnixNanos(now + 5 * ns_per_s);
    res = ntp.Result.fromPacket(p, T1, T4);
    try testing.expectEqual(@as(i64, 4 * ns_per_s), res.delay);
    try testing.expectEqual(@as(i64, 18 * ns_per_s), res.offset);
    try testing.expectEqual(@as(i128, now + 18 * ns_per_s), res.correctTime(@as(i128, now)));

    //   101    102    103    105
    // => offset -0.5, roundtrip 3
    T1 = ntp.Time.fromUnixNanos(now + 101 * ns_per_s);
    p.ts_rec = ntp.Time.fromUnixNanos(now + 102 * ns_per_s).t;
    p.ts_xmt = ntp.Time.fromUnixNanos(now + 103 * ns_per_s).t;
    T4 = ntp.Time.fromUnixNanos(now + 105 * ns_per_s);
    res = ntp.Result.fromPacket(p, T1, T4);
    try testing.expectEqual(@as(i64, 3 * ns_per_s), res.delay);
    try testing.expectEqual(-@as(i64, ns_per_s / 2), res.offset);
    try testing.expectEqual(@as(i128, now - 5 * ns_per_s / 10), res.correctTime(@as(i128, now)));
}

test "Result - stratum, ref-id" {
    const now: u64 = @intCast(std.time.nanoTimestamp());
    var p = ntp.Packet.init(4);
    p.stratum = 1; // ref id is ASCII string, left-justified, 0-terminated
    p.ref_id = 5460039; // GPS\0

    const T1 = ntp.Time.fromUnixNanos(now + 1 * ns_per_s);
    p.ts_rec = ntp.Time.fromUnixNanos(now).t;
    p.ts_xmt = ntp.Time.fromUnixNanos(now).t;
    const T4 = ntp.Time.fromUnixNanos(now + 3 * ns_per_s);

    var res = ntp.Result.fromPacket(p, T1, T4);
    try testing.expect(res.refIDprintable());
    try testing.expectEqual([4]u8{ 'G', 'P', 'S', 0x0 }, res.__ref_id);

    p.ref_id = std.mem.nativeToBig(u32, 0x44524f50); // DROP
    res = ntp.Result.fromPacket(p, T1, T4);
    try testing.expect(res.refIDprintable());

    p.ref_id = 0x00000000;
    res = ntp.Result.fromPacket(p, T1, T4);
    try testing.expect(res.refIDprintable());

    p.stratum = 2;
    res = ntp.Result.fromPacket(p, T1, T4);
    try testing.expect(!res.refIDprintable());
    try testing.expectEqual([4]u8{ 0x0, 0x0, 0x0, 0x0 }, res.__ref_id);
}

test "Result - validate / flags" {
    const now: u64 = @intCast(std.time.nanoTimestamp());
    var p = ntp.Packet.init(4);
    p.stratum = 1;
    p.li_vers_mode = 0 << 6 | 3 << 3 | 4; // server mode

    const T1 = ntp.Time.fromUnixNanos(now + 1 * ns_per_s);
    p.ts_ref = ntp.Time.fromUnixNanos(now - 5 * ns_per_s).t;
    p.ts_rec = ntp.Time.fromUnixNanos(now).t;
    p.ts_xmt = ntp.Time.fromUnixNanos(now).t;
    const T4 = ntp.Time.fromUnixNanos(now + 3 * ns_per_s);
    var res = ntp.Result.fromPacket(p, T1, T4);

    var buf: [256]u8 = std.mem.zeroes([256]u8);
    var flags = res.validate(); // stratum 1 is good
    try testing.expectEqual(@intFromEnum(ntp.Result.flag_descr.OK), flags);
    _ = try ntp.Result.printFlags(flags, &buf);
    try testing.expectEqualStrings("0 (OK)", std.mem.sliceTo(buf[0..], 0));

    p.stratum = 17;
    res = ntp.Result.fromPacket(p, T1, T4);
    flags = res.validate();
    try testing.expectEqual(@intFromEnum(ntp.Result.flag_descr.stratum_too_large), flags);

    p.stratum = 1;
    //                                 v---- client !
    p.li_vers_mode = 0 << 6 | 3 << 3 | 3;
    res = ntp.Result.fromPacket(p, T1, T4);
    flags = res.validate();
    try testing.expectEqual(@intFromEnum(ntp.Result.flag_descr.incorrect_mode), flags);

    _ = try ntp.Result.printFlags(flags, &buf);
    try testing.expectEqualStrings("incorrect_mode", std.mem.sliceTo(buf[0..], 0));

    //               v---------------------- leap !
    //               v                 v---- client !
    p.li_vers_mode = 3 << 6 | 3 << 3 | 3;
    res = ntp.Result.fromPacket(p, T1, T4);
    flags = res.validate();
    _ = try ntp.Result.printFlags(flags, &buf);
    try testing.expectEqualStrings("unsynchronized_leapsecond, incorrect_mode", std.mem.sliceTo(buf[0..], 0));

    p.poll = 18;
    res = ntp.Result.fromPacket(p, T1, T4);
    flags = res.validate();
    try testing.expect(flags & @intFromEnum(ntp.Result.flag_descr.incorrect_poll_freq) > 0);
}
