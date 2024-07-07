//! NTP query CLI
const std = @import("std");
const io = std.io;
const net = std.net;
const posix = std.posix;

const flags = @import("flags");

const zdt = @import("zdt");
const Datetime = zdt.Datetime;
const Timezone = zdt.Timezone;
const Resolution = zdt.Duration.Resolution;

const Cmd = @import("cmd.zig");
const ntp = @import("ntp.zig");
const pprint = @import("prettyprint.zig").pprint_result;
const jsonprint = @import("prettyprint.zig").jsonprint_result;

// ------------------------------------------------------------------------------------
const timeout_sec: isize = 5; // wait-for-reply timeout
const mtu: usize = 1024; // buffer size for transmission
// ------------------------------------------------------------------------------------

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // for Windows compatibility: feed an allocator for args parsing
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    const cli = flags.parse(&args, Cmd);

    const port: u16 = cli.flags.port;
    const proto_vers: u8 = cli.flags.protocol_version;
    if (proto_vers < 3 or proto_vers > 4) {
        return errprintln("invalid protocol version: {d}", .{proto_vers});
    }

    var tz: Timezone = Timezone.UTC;
    defer tz.deinit();
    if (!std.mem.eql(u8, cli.flags.timezone, "UTC")) {
        if (std.mem.eql(u8, cli.flags.timezone, "local")) {
            tz = try Timezone.tzLocal(allocator);
        } else {
            tz = Timezone.runtimeFromTzfile(
                cli.flags.timezone,
                Timezone.tzdb_prefix,
                allocator,
            ) catch Timezone.UTC;
        }
    }

    // --- prepare connection ---------------------------------------------------------

    // resolve hostname
    const addrlist = net.getAddressList(allocator, cli.flags.server, port) catch {
        return errprintln("invalid hostname '{s}'", .{cli.flags.server});
    };
    defer addrlist.deinit();

    // from where to send the query.
    // Zig std docs: to handle IPv6 link-local unix addresses,
    //               it is recommended to use `resolveIp` instead.
    const addr_src = try std.net.Address.parseIp(cli.flags.src_ip, cli.flags.src_port);

    const sock = try posix.socket(
        addr_src.any.family,
        // CLOEXEC not strictly needed here; see open(2) man page.
        posix.SOCK.DGRAM | posix.SOCK.CLOEXEC,
        posix.IPPROTO.UDP,
    );
    try posix.bind(sock, &addr_src.any, addr_src.getOsSockLen());
    defer posix.close(sock);

    if (timeout_sec != 0) { // make this configurable ? ...0 would mean no timeout
        try posix.setsockopt(
            sock,
            posix.SOL.SOCKET,
            posix.SO.RCVTIMEO,
            &std.mem.toBytes(posix.timespec{ .tv_sec = timeout_sec, .tv_nsec = 0 }),
        );
    }

    // --- query server(s) ------------------------------------------------------------

    var buf: [mtu]u8 = std.mem.zeroes([mtu]u8);

    iter_addrs: for (addrlist.addrs, 0..) |dst, i| {
        var dst_addr_sock: posix.sockaddr = undefined; // must not use dst.any
        var dst_addr_len: posix.socklen_t = dst.getOsSockLen();

        ntp.Packet.initToBuffer(proto_vers, &buf);

        // packet created!
        const T1: ntp.Time = ntp.Time.fromUnixNanos(@as(u64, @intCast(std.time.nanoTimestamp())));

        _ = posix.sendto(
            sock,
            buf[0..ntp.packet_len],
            0,
            &dst.any,
            dst_addr_len,
        ) catch |err| switch (err) {
            error.AddressFamilyNotSupported => {
                if (dst.any.family == posix.AF.INET6) {
                    errprintln("IPv6 error, try next server.", .{});
                    continue :iter_addrs;
                }
                return err;
            },
            else => |e| return e,
        };

        const n_recv: usize = posix.recvfrom(
            sock,
            buf[0..],
            0,
            &dst_addr_sock,
            &dst_addr_len,
        ) catch |err| switch (err) {
            error.WouldBlock => {
                errprintln("Error: connection timed out", .{});
                if (i < addrlist.addrs.len - 1) errprintln("Try next server.", .{});
                continue :iter_addrs;
            },
            else => |e| return e,
        };

        // reply received!
        const T4: ntp.Time = ntp.Time.fromUnixNanos(@as(u64, @intCast(std.time.nanoTimestamp())));

        if (n_recv != ntp.packet_len) {
            errprintln("Error: invalid reply length", .{});
            if (i < addrlist.addrs.len - 1) errprintln("Try next server.", .{});
            continue :iter_addrs;
        }

        const p_result: ntp.Packet = ntp.Packet.parse(buf[0..ntp.packet_len].*);
        const result: ntp.Result = ntp.Result.fromPacket(p_result, T1, T4);

        if (cli.flags.json) {
            try jsonprint(io.getStdOut().writer(), result, cli.flags.server, dst);
        } else {
            try pprint(io.getStdOut().writer(), result, &tz, cli.flags.server, dst);
        }

        if (!cli.flags.all) break :iter_addrs;
    }
}

// --- helpers ------------------------------------------------------------------------

/// Print to stdout with trailing newline, unbuffered, and silently returning on failure.
fn println(comptime fmt: []const u8, args: anytype) void {
    const stdout = io.getStdOut().writer();
    nosuspend stdout.print(fmt ++ "\n", args) catch return;
}

/// Print to stderr with trailing newline, unbuffered, and silently returning on failure.
fn errprintln(comptime fmt: []const u8, args: anytype) void {
    const stderr = io.getStdErr().writer();
    nosuspend stderr.print(fmt ++ "\n", args) catch return;
}
