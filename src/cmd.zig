//! config struct for the flags package argument parser
const Cmd = @This();

pub const name = "ntp_client";

// defaults:
server: []const u8 = "pool.ntp.org",
port: u16 = 123,
protocol_version: u8 = 4,
all: bool = false,
src_ip: []const u8 = "0.0.0.0",
src_port: u16 = 0,
timezone: []const u8 = "UTC",

pub const descriptions = .{
    .server = "NTP server to query (default: pool.ntp.org)",
    .port = "UDP port to use for NTP query (default: 123)",
    .protocol_version = "NTP protocol version, 3 or 4 (default: 4)",
    .all = "Query all IP addresses found for a given server URL (default: false / stop after first)",
    .src_ip = "IP address to use for sending the query (default: 0.0.0.0 / auto-select)",
    .src_port = "UDP port to use for sending the query (default: 0 / any port)",
    .timezone = "Timezone to use in results display (default: UTC)",
};

pub const switches = .{
    .server = 's',
    .port = 'p',
    .protocol_version = 'v',
    .all = 'a',
    .timezone = 'z',
};
