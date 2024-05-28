// Copyright © 2024 Florian Obersteiner <f.obersteiner@posteo.de>
// License: see LICENSE in the root directory of the repo.
//
// ~~~ NTP query CLI ~~~
//
const std = @import("std");
const io = std.io;
const net = std.net;
const posix = std.posix;
const sleep = std.time.sleep;
const flags = @import("flags");
const zdt = @import("zdt");
const Datetime = zdt.Datetime;
const Timezone = zdt.Timezone;
const Resolution = zdt.Duration.Resolution;
const Cmd = @import("cmd.zig");
const ntp = @import("ntp.zig");
const pprint = @import("prettyprint.zig").pprint_result;

test {
    _ = ntp;
}

//-----------------------------------------------------------------------------
const mtu: usize = 1024; // buffer size for transmission
const ms: u64 = 1_000_000;
const await_reply_period = 1000 * ms;
const timeout = 3000 * ms;
//-----------------------------------------------------------------------------

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

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

    // ------------------------------------------------------------------------

    // resolve hostname
    const addrlist = net.getAddressList(allocator, cli.flags.server, port) catch {
        return errprintln("invalid hostname '{s}'", .{cli.flags.server});
    };
    defer addrlist.deinit();
    if (addrlist.canon_name) |n| println("Query server: {s}", .{n});

    // from where to send the query
    const addr_src = try std.net.Address.parseIp(cli.flags.src_ip, cli.flags.src_port);
    const sock = try posix.socket(
        posix.AF.INET,
        // Notes on flags:
        // NONBLOCK is used to create timeout behavior.
        // CLOEXEC not strictly needed here; see open(2) man page.
        posix.SOCK.DGRAM | posix.SOCK.NONBLOCK | posix.SOCK.CLOEXEC,
        posix.IPPROTO.UDP,
    );
    try posix.bind(sock, &addr_src.any, addr_src.getOsSockLen());
    defer posix.close(sock);
    // NOTE : since this is a one-shot program, we would not have to close the socket.
    // The OS could clean up for us.

    var buf: [mtu]u8 = std.mem.zeroes([mtu]u8);

    iter_addrs: for (addrlist.addrs) |dst| {
        var dst_addr_sock = dst.any;
        var dst_addr_len: posix.socklen_t = dst.getOsSockLen();

        // TODO : move send request / await reply logic to a separate function?
        // send the query to the server...
        ntp.Packet.intiToBuffer(proto_vers, true, &buf);
        // const n_sent = try posix.sendto(
        _ = try posix.sendto(
            sock,
            buf[0..ntp.packet_len],
            0,
            &dst_addr_sock,
            dst_addr_len,
        );

        var n_recv: usize = 0;
        var elapsed: usize = 0;

        sleep(ms * 100); // try to avoid reaching 'sleep' in the timed_repeat loop
        timed_repeat: while (true) {
            // wait for reply...
            if (posix.recvfrom(
                sock,
                buf[0..],
                0,
                &dst_addr_sock,
                &dst_addr_len,
            )) |n| {
                n_recv = n;
            } else |err| switch (err) {
                error.WouldBlock => println("wait for reply...", .{}),
                else => return err,
            }
            if (n_recv > 0) break :timed_repeat;
            if (elapsed >= timeout) return posix.ReadError.ConnectionTimedOut;
            sleep(await_reply_period);
            elapsed += await_reply_period;
        }

        if (n_recv != ntp.packet_len) {
            println("invalid reply length, try next server.", .{});
            continue :iter_addrs;
        }

        const result: ntp.Result = ntp.Packet.analyze(buf[0..ntp.packet_len].*);
        println("Server name: {s}", .{cli.flags.server});
        println("Server address: {any}", .{dst});
        println("---", .{});

        try pprint(io.getStdOut().writer(), result, &tz);

        if (!cli.flags.all) break :iter_addrs;
    }
}

//-----------------------------------------------------------------------------

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
