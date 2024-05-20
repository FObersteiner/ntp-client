// Copyright © 2024 Florian Obersteiner <f.obersteiner@posteo.de>
// License: see LICENSE in the root directory of the repo.
//
// ~~~ NTP client CLI app ~~~
//
const std = @import("std");
const debug = std.debug;
const io = std.io;
const netdb = @cImport(@cInclude("netdb.h"));

const clap = @import("clap");

const zdt = @import("zdt");
const Datetime = zdt.Datetime;
const Timezone = zdt.Timezone;
const Resolution = zdt.Duration.Resolution;

const ntp = @import("ntp.zig");
test {
    _ = ntp;
}

//-----------------------------------------------------------------------------
// communication src/dst config
const src_ip = "0.0.0.0";
const src_port: u16 = 0;
const default_dst_port: u16 = 123;
const default_server: []const u8 = "pool.ntp.org";
const default_proto_vers: u8 = 4;
const mtu: usize = 1024; // buffer size for transmission
//-----------------------------------------------------------------------------
// clap
const params = clap.parseParamsComptime(
    \\-h,  --help               Display this help and exit.
    \\     --version            Output version information and exit.
    \\-p,  --port <uint16>      UDP port to use. The default is 123.
    \\-v,  --proto_vers <uint8> NTP protocol version to use. The default is 4.
    \\-z,  --timezone <str>     Timezone to display timestamps in. Use 'local' to get the current OS setting.
    \\<URL>                     URL of the server to query, e.g. pool.ntp.org.
);
const parsers = .{
    .uint8 = clap.parsers.int(u8, 0),
    .uint16 = clap.parsers.int(u16, 0),
    .str = clap.parsers.string,
    .URL = clap.parsers.string,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, parsers, .{
        .diagnostic = &diag,
        .allocator = allocator,
    }) catch |err| {
        diag.report(io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0) return clap.help(std.io.getStdOut().writer(), clap.Help, &params, .{});

    var server_url = default_server;
    if (res.positionals.len >= 1) server_url = res.positionals[0];

    var port = default_dst_port;
    if (res.args.port) |p| port = p;

    var proto_vers: u8 = default_proto_vers;
    if (res.args.proto_vers) |p| {
        if (p < 3 or p > 4) {
            return errprintln("invalid protocol version: {d}", .{p});
        }
        proto_vers = p;
    }

    var tz: Timezone = Timezone.UTC;
    defer tz.deinit();
    if (res.args.timezone) |s| {
        if (std.mem.eql(u8, s, "local")) {
            tz = try Timezone.tzLocal(allocator);
        } else {
            tz = Timezone.runtimeFromTzfile(s, Timezone.tzdb_prefix, allocator) catch Timezone.UTC;
        }
    }

    // ------------------------------------------------------------------------

    // resolve hostname. use C system library here for simplicity;
    // this could maybe be done in pure Zig as well.
    const hostent = netdb.gethostbyname(server_url.ptr);

    if (hostent == null) return errprintln("invalid server name", .{});
    // allow IPv4 only for simplicity; could be extended to work with IPv6 later.
    if (hostent.*.h_length != 4) return errprintln("no IPv4 found", .{});

    // this is the destination address, where to send the query to
    const addr_dst = std.net.Address.initIp4(hostent.*.h_addr_list.*[0..4].*, port);
    var addr_dst_sock = addr_dst.any;
    var addr_dst_sz: std.posix.socklen_t = addr_dst.getOsSockLen();
    // now we also need a source address, from where to send the query
    const addr_src = try std.net.Address.parseIp(src_ip, src_port);
    const addr_src_sock = addr_src.any;

    println("query '{s}' on {any} from {any}", .{ server_url, addr_dst, addr_src });

    const sock = try std.posix.socket(
        std.posix.AF.INET,
        std.posix.SOCK.DGRAM | std.posix.SOCK.CLOEXEC, // CLOEXEC not strictly needed here; see open(2) man page
        std.posix.IPPROTO.UDP,
    );

    // NOTE : since this is a one-shot program, we do not have to close the
    // socket. The OS can clean up for us.

    try std.posix.bind(sock, &addr_src_sock, addr_src.getOsSockLen());

    var buf: [mtu]u8 = std.mem.zeroes([mtu]u8);
    ntp.Packet.intiToBuffer(proto_vers, true, &buf);

    // send the query to the server...
    const n_sent = try std.posix.sendto(
        sock,
        buf[0..ntp.packet_len],
        0,
        &addr_dst_sock,
        addr_dst_sz,
    );
    println("sent {d} byte(s)", .{n_sent});

    // wait for reply...
    const n_recv = try std.posix.recvfrom(
        sock,
        buf[0..],
        0,
        &addr_dst_sock,
        &addr_dst_sz,
    );
    println("received {d} byte(s) from {any}", .{ n_recv, addr_dst });

    if (n_recv == ntp.packet_len) {
        const result = ntp.Packet.analyze(buf[0..ntp.packet_len].*);
        println("\n{s}\n", .{result});
        println(
            "Server sync: {s}",
            .{try Datetime.fromUnix(result.ts_ref, Resolution.nanosecond, tz)},
        );
        println(
            "T1 datetime: {s}",
            .{try Datetime.fromUnix(result.ts_org, Resolution.nanosecond, tz)},
        );
        println(
            "T2 datetime: {s}",
            .{try Datetime.fromUnix(result.ts_rec, Resolution.nanosecond, tz)},
        );
        println(
            "T3 datetime: {s}",
            .{try Datetime.fromUnix(result.ts_xmt, Resolution.nanosecond, tz)},
        );
        println(
            "T4 datetime: {s}",
            .{try Datetime.fromUnix(result.ts_processed, Resolution.nanosecond, tz)},
        );
    } else {
        return errprintln("length of reply invalid", .{});
    }
}

//-----------------------------------------------------------------------------

/// Print to stdout with trailing newline, unbuffered, and silently returning on failure.
fn println(comptime fmt: []const u8, args: anytype) void {
    const stdout = std.io.getStdOut().writer();
    nosuspend stdout.print(fmt ++ "\n", args) catch return;
}

/// Print to stderr with trailing newline, unbuffered, and silently returning on failure.
fn errprintln(comptime fmt: []const u8, args: anytype) void {
    const stderr = std.io.getStdErr().writer();
    nosuspend stderr.print(fmt ++ "\n", args) catch return;
}
