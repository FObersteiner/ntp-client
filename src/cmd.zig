//! config struct for the flags package argument parser
const Cmd = @This();

pub const name = "ntp_client";

// defaults:
server: []const u8 = "pool.ntp.org",
protocol_version: u8 = 4,
ipv4: bool = false,
src_ip: []const u8 = "0::0",
src_port: u16 = 0,
dst_port: u16 = 123,
timezone: []const u8 = "UTC",
json: bool = false,
interval: ?u64 = null,
all: bool = false,

pub const descriptions = .{
    .server = "NTP server to query (default: pool.ntp.org)",
    .protocol_version = "NTP protocol version, 3 or 4 (default: 4)",
    .ipv4 = "use IPv4 instead of the default IPv6",
    .src_ip = "IP address to use for sending the query (default: 0::0 / IPv6 auto-select)",
    .src_port = "UDP port to use for sending the query (default: 0 / any port)",
    .dst_port = "UDP port of destination server (default: 123)",
    .timezone = "Timezone to use in console output (default: UTC)",
    .json = "Print result in JSON",
    .interval = "Interval for repeated queries in seconds (default: null / one-shot operation)",
    .all = "Query all IP addresses found for a given server URL (default: false / stop after first)",
};

pub const switches = .{
    .server = 's',
    .protocol_version = 'v',
    .timezone = 'z',
    .json = 'j',
    .interval = 'i',
    .all = 'a',
    //    .ipv4 = '4',
};
