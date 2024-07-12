const std = @import("std");
const bufPrint = std.fmt.bufPrint;
const ntp = @import("ntp.zig");
const zdt = @import("zdt");
const Datetime = zdt.Datetime;
const Timezone = zdt.Timezone;
const Resolution = zdt.Duration.Resolution;

const ns_per_s: u64 = 1_000_000_000;
const ns_per_us: u64 = 1_000;

pub fn json(
    writer: anytype,
    ntpr: ntp.Result,
    server_name: []const u8,
    server_addr: std.net.Address,
) !void {
    try writer.print(
        \\{{ 
        \\    "server_name": "{s}",
        \\    "server_address": "{any}",
        \\    "leap_indicator": {d},
        \\    "version": {d},
        \\    "mode": {d},
        \\    "stratum": {d},
        \\    "poll": {d},
        \\    "precision": {d},
        \\    "ref_id": {d},
        \\    "root_delay_ns": {d},
        \\    "root_dispersion_ns": {d},
        \\    "ts_ref": "{s}",
        \\    "T1": "{s}",
        \\    "T2": "{s}",
        \\    "T3": "{s}",
        \\    "T4": "{s}",
        \\    "offset_ns": {d},
        \\    "delay_ns": {d}
        \\}}
        \\
    ,
        .{
            server_name,
            server_addr,
            ntpr.leap_indicator,
            ntpr.version,
            ntpr.mode,
            ntpr.stratum,
            ntpr.poll,
            ntpr.precision,
            ntpr.ref_id,
            ntpr.root_delay,
            ntpr.root_dispersion,
            try Datetime.fromUnix(ntpr.Tref.toUnixNanos(), Resolution.nanosecond, Timezone.UTC),
            try Datetime.fromUnix(ntpr.T1.toUnixNanos(), Resolution.nanosecond, Timezone.UTC),
            try Datetime.fromUnix(ntpr.T2.toUnixNanos(), Resolution.nanosecond, Timezone.UTC),
            try Datetime.fromUnix(ntpr.T3.toUnixNanos(), Resolution.nanosecond, Timezone.UTC),
            try Datetime.fromUnix(ntpr.T4.toUnixNanos(), Resolution.nanosecond, Timezone.UTC),
            ntpr.offset,
            ntpr.delay,
        },
    );
}

pub fn humanfriendly(
    writer: anytype,
    ntpr: ntp.Result,
    tz: ?*Timezone,
    server_name: []const u8,
    server_addr: std.net.Address,
) !void {
    const offset_f: f64 = @as(f64, @floatFromInt(ntpr.offset)) / @as(f64, ns_per_s);
    const delay_f: f64 = @as(f64, @floatFromInt(ntpr.delay)) / @as(f64, ns_per_s);
    var z: *Timezone = if (tz == null) @constCast(&Timezone.UTC) else tz.?;

    // ref_id string looks like "0xFFFFFFFF (xxxx)"
    var refid_buf: [18]u8 = std.mem.zeroes([18]u8);
    if (ntpr.stratum < 2) {
        _ = try bufPrint(&refid_buf, "0x{X} ({s})", .{ ntpr.ref_id, ntpr.__ref_id });
    } else {
        _ = try bufPrint(&refid_buf, "0x{X}", .{ntpr.ref_id});
    }

    var flags_buf: [512]u8 = std.mem.zeroes([512]u8);
    _ = try ntp.Result.printFlags(ntpr.validate(), &flags_buf);

    try writer.print(
        \\---***---
        \\Server name: "{s}"
        \\Server address: "{any}"
        \\---
        \\LI={d} VN={d} Mode={d} Stratum={d} Poll={d} ({d} s) Precision={d} ({d} ns)
        \\ID: {s}
        \\Server root dispersion: {d} us, root delay: {d} us
        \\---
        \\Server last synced  : {s}
        \\T1, packet created  : {s}
        \\T2, server received : {s}
        \\T3, server replied  : {s}
        \\T4, reply received  : {s}
        \\(timezone displayed: {s})
        \\---
        \\Offset to timserver: {d:.3} s ({d} us) 
        \\Round-trip delay:    {d:.3} s ({d} us)
        \\---
        \\Result flags: {s}
        \\---***---
        \\
    ,
        .{
            server_name,
            server_addr,
            ntpr.leap_indicator,
            ntpr.version,
            ntpr.mode,
            ntpr.stratum,
            ntpr.poll,
            ntpr.poll_period,
            ntpr.precision,
            ntpr.precision_ns,
            refid_buf,
            ntpr.root_dispersion / ns_per_us,
            ntpr.root_delay / ns_per_us,
            try Datetime.fromUnix(ntpr.Tref.toUnixNanos(), Resolution.nanosecond, z.*),
            try Datetime.fromUnix(ntpr.T1.toUnixNanos(), Resolution.nanosecond, z.*),
            try Datetime.fromUnix(ntpr.T2.toUnixNanos(), Resolution.nanosecond, z.*),
            try Datetime.fromUnix(ntpr.T3.toUnixNanos(), Resolution.nanosecond, z.*),
            try Datetime.fromUnix(ntpr.T4.toUnixNanos(), Resolution.nanosecond, z.*),
            z.name(),
            offset_f,
            @divFloor(ntpr.offset, ns_per_us),
            delay_f,
            @divFloor(ntpr.delay, ns_per_us),
            flags_buf,
        },
    );
}
