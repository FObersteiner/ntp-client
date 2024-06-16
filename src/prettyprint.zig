const std = @import("std");
const ntp = @import("ntp.zig");
const zdt = @import("zdt");
const Datetime = zdt.Datetime;
const Timezone = zdt.Timezone;
const Resolution = zdt.Duration.Resolution;

const ns_per_s: u64 = 1_000_000_000;
const ns_per_us: u64 = 1_000;

// pretty-print an ntp-results struct
pub fn pprint_result(writer: anytype, ntpr: ntp.Result, tz: ?*Timezone) !void {
    const prc: u64 = ntp.precisionToNanos(ntpr.precision);
    const offset_f: f64 = @as(f64, @floatFromInt(ntpr.offset)) / @as(f64, ns_per_s);
    const delay_f: f64 = @as(f64, @floatFromInt(ntpr.delay)) / @as(f64, ns_per_s);
    // const disp_f: f64 = @as(f64, @floatFromInt(ntpr.lambda)) / @as(f64, ns_per_s);
    var z: *Timezone = if (tz == null) @constCast(&Timezone.UTC) else tz.?;

    try writer.print(
        \\NPT query result:
        \\---***---
        \\LI={d} VN={d} Mode={d} Stratum={d} Poll={d} Precision={d} ({d} ns)
        \\ref_id: {d}
        \\root_delay: {d} us, root_dispersion: {d} us
        \\---
        \\Server last synced  : {s}
        \\T1, packet created  : {s}
        \\T2, server received : {s}
        \\T3, server replied  : {s}
        \\T4, reply received  : {s}
        \\(timezone displayed: {s})
        \\---
        \\offset to timserver: {d:.3} s ({d} us) 
        \\round-trip delay:    {d:.3} s ({d} us)
        \\---***---
        \\
    ,
        .{
            ntpr.leap_indicator,
            ntpr.version,
            ntpr.mode,
            ntpr.stratum,
            ntpr.poll,
            ntpr.precision,
            prc,
            ntpr.ref_id,
            ntpr.root_delay / ns_per_us,
            ntpr.root_dispersion / ns_per_us,
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
        },
    );
}
