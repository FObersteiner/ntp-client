const std = @import("std");
const ntp = @import("ntp.zig");
const zdt = @import("zdt");
const Datetime = zdt.Datetime;
const Timezone = zdt.Timezone;
const Resolution = zdt.Duration.Resolution;

const ns_per_s: u64 = 1_000_000_000;

// TODO : add JSON output

// pretty-print an npt-results struct
pub fn pprint_result(writer: anytype, ntpr: ntp.Result, tz: ?*Timezone) !void {
    const prc: u64 = ntp.NtpTime.precisionToNanos(ntpr.precision);
    const theat_f: f64 = @as(f64, @floatFromInt(ntpr.theta)) / @as(f64, ns_per_s);
    const delta_f: f64 = @as(f64, @floatFromInt(ntpr.delta)) / @as(f64, ns_per_s);
    const lamda_f: f64 = @as(f64, @floatFromInt(ntpr.lambda)) / @as(f64, ns_per_s);
    var z: *Timezone = if (tz == null) @constCast(&Timezone.UTC) else tz.?;

    try writer.print(
        \\NPT query result:
        \\---
        \\LI={d} VN={d} Mode={d} Stratum={d} Poll={d} Precision={d} ({d} ns)
        \\ref_id: {d}
        \\root_delay: {d} ns, root_dispersion: {d} ns
        \\=> syncronization distance: {d} s
        \\---
        \\Server last synced  : {s}
        \\T1, packet created  : {s}
        \\T2, server received : {s}
        \\T3, server replied  : {s}
        \\T4, reply received  : {s}
        \\(timezone displayed : {s})
        \\---
        \\offset to timserver: {d:.6} s ({d} ns) 
        \\round-trip delay:    {d:.6} s ({d} ns)
        \\---
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
            ntpr.root_delay,
            ntpr.root_dispersion,
            lamda_f,
            try Datetime.fromUnix(ntpr.ts_ref, Resolution.nanosecond, z.*),
            try Datetime.fromUnix(ntpr.ts_org, Resolution.nanosecond, z.*),
            try Datetime.fromUnix(ntpr.ts_rec, Resolution.nanosecond, z.*),
            try Datetime.fromUnix(ntpr.ts_xmt, Resolution.nanosecond, z.*),
            try Datetime.fromUnix(ntpr.ts_processed, Resolution.nanosecond, z.*),
            z.name(),
            theat_f,
            ntpr.theta,
            delta_f,
            ntpr.delta,
        },
    );
}
