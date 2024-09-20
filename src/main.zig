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

const CliFlags = @import("cliflags.zig");
const ntp = @import("ntp.zig");
const pprint = @import("prettyprint.zig");

// ------------------------------------------------------------------------------------
const timeout_sec: isize = 5; // wait-for-reply timeout
const mtu: usize = 1024; // buffer size for transmission
const ip_default = "0::0"; // default to IPv6
// ------------------------------------------------------------------------------------

pub fn main() !void {
    // var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // const allocator = gpa.allocator();
    // defer _ = gpa.deinit();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // for Windows compatibility: feed an allocator for args parsing
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    const cliflags = flags.parseOrExit(&args, "ntp_client", CliFlags, .{});

    const proto_vers: u8 = cliflags.protocol_version;
    if (proto_vers < 3 or proto_vers > 4) {
        return errprintln("invalid protocol version: {d}", .{proto_vers});
    }
    if (cliflags.interval != null and cliflags.all) {
        return errprintln("cannot query all servers repeatedly", .{});
    }
    if (cliflags.interval) |interval| {
        if (interval > 60 * 60 * 4 or interval < 2)
            return errprintln("interval must be in range [2s..4h], got {d}s", .{interval});
    }

    var tz: Timezone = Timezone.UTC;
    defer tz.deinit();
    if (!std.mem.eql(u8, cliflags.timezone, "UTC")) {
        if (std.mem.eql(u8, cliflags.timezone, "local")) {
            tz = try Timezone.tzLocal(allocator);
        } else {
            tz = Timezone.fromTzdata(
                cliflags.timezone,
                allocator,
            ) catch Timezone.UTC;
        }
    }

    // --- prepare connection ---------------------------------------------------------

    // resolve hostname
    const addrlist = net.getAddressList(allocator, cliflags.server, cliflags.dst_port) catch {
        return errprintln("invalid hostname '{s}'", .{cliflags.server});
    };
    defer addrlist.deinit();

    // only use default IPv4 if user specified to use IPv4 without setting a specific src IP:
    const src_ip = if (cliflags.ipv4 and std.mem.eql(u8, ip_default, cliflags.src_ip))
        "0.0.0.0" // any available IPv4
    else
        cliflags.src_ip;

    // from where to send the query.
    // Zig std docs: to handle IPv6 link-local unix addresses,
    //               it is recommended to use `resolveIp` instead.
    const src_addr = try std.net.Address.parseIp(src_ip, cliflags.src_port);

    const sock = try posix.socket(
        src_addr.any.family,
        // CLOEXEC not strictly needed here; see open(2) man page.
        posix.SOCK.DGRAM | posix.SOCK.CLOEXEC,
        posix.IPPROTO.UDP,
    );
    try posix.bind(sock, &src_addr.any, src_addr.getOsSockLen());
    defer posix.close(sock);

    if (timeout_sec != 0) { // make this configurable ? ...0 would mean no timeout
        try posix.setsockopt(
            sock,
            posix.SOL.SOCKET,
            posix.SO.RCVTIMEO,
            &std.mem.toBytes(posix.timespec{ .sec = timeout_sec, .nsec = 0 }), // zig 0.13 : .tv_sec, .tv_nsec
        );
    }

    // --- query server(s) ------------------------------------------------------------

    var buf: [mtu]u8 = std.mem.zeroes([mtu]u8);

    repeat: while (true) {
        iter_addrs: for (addrlist.addrs, 0..) |dst, i| {
            const result: ntp.Result = sample_ntp(
                &sock,
                &src_addr,
                &dst,
                &buf,
                proto_vers,
            ) catch |err| switch (err) {
                error.AddressFamilyMismatch => {
                    errprintln(
                        "Error: IP address family mismatch for server at {any} (src: {s}, dst: {s})",
                        .{ dst, inet_family(src_addr.any.family), inet_family(dst.any.family) },
                    );
                    if (i < addrlist.addrs.len - 1) errprintln("Try next server...", .{});
                    continue :iter_addrs; // continue to iterate addresses, even if -a is not set
                },
                error.WouldBlock => {
                    errprintln("Error: connection timed out", .{});
                    if (i < addrlist.addrs.len - 1) errprintln("Try next server...", .{});
                    continue :iter_addrs; // continue to iterate addresses, even if -a is not set
                },
                else => |e| return e,
            };

            if (cliflags.json) {
                try pprint.json(io.getStdOut().writer(), result, cliflags.server, dst);
            } else {
                try pprint.humanfriendly(io.getStdOut().writer(), result, &tz, cliflags.server, dst);
            }

            if (!cliflags.all) break :iter_addrs;
        } // end loop 'iter_addrs'
        if (cliflags.interval) |interval| {
            std.time.sleep(interval * std.time.ns_per_s);
        } else break :repeat;
    } // end loop 'repeat'
}

// --- helpers ------------------------------------------------------------------------

/// Sample an NTP server at 'dst' from given socket and source address.
/// Result gets written to the buffer 'buf'.
fn sample_ntp(sock: *const posix.socket_t, src: *const net.Address, dst: *const net.Address, buf: []u8, protocol_version: u8) !ntp.Result {

    // Check src and dst addr if families match (both posix.AF.INET/v4 or posix.AF.INET6/v6).
    if (src.any.family != dst.any.family) return error.AddressFamilyMismatch;

    var dst_addr_sock: posix.sockaddr = undefined; // must not use dst.any
    var dst_addr_len: posix.socklen_t = dst.getOsSockLen();
    ntp.Packet.initToBuffer(protocol_version, buf);
    const T1: ntp.Time = ntp.Time.fromUnixNanos(@as(u64, @intCast(std.time.nanoTimestamp())));
    _ = try posix.sendto(
        sock.*,
        buf[0..ntp.packet_len],
        0,
        &dst.any,
        dst_addr_len,
    );
    const n_recv: usize = try posix.recvfrom(
        sock.*,
        buf[0..],
        0,
        &dst_addr_sock,
        &dst_addr_len,
    );
    const T4: ntp.Time = ntp.Time.fromUnixNanos(@as(u64, @intCast(std.time.nanoTimestamp())));
    if (n_recv != ntp.packet_len) return error.invalidLength;

    return ntp.Result.fromPacket(ntp.Packet.parse(buf[0..ntp.packet_len].*), T1, T4);
}

/// Print an error to stderr.
fn errprintln(comptime fmt: []const u8, args: anytype) void {
    const stderr = io.getStdErr().writer();
    nosuspend stderr.print(fmt ++ "\n", args) catch return;
}

/// Turn AF flags into an appropriate text representation.
fn inet_family(family: u16) []const u8 {
    const result = switch (family) {
        posix.AF.INET => "IPv4",
        posix.AF.INET6 => "IPv6",
        else => "unknown",
    };
    return result;
}
