<!-- -*- coding: utf-8 -*- -->
[![Zig](https://img.shields.io/badge/-Zig-F7A41D?style=flat&logo=zig&logoColor=white)](https://ziglang.org/)  [![tests](https://github.com/FObersteiner/ntp-client/actions/workflows/run_tests.yml/badge.svg)](https://github.com/FObersteiner/ntp-client/actions/workflows/run_tests.yml)  [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://github.com/FObersteiner/ntp-client/blob/master/LICENSE)

# NTP Client

Command line app to query an [NTP](https://datatracker.ietf.org/doc/html/rfc5905) server, e.g. to verify your OS clock setting. Or get the time independent of your OS clock. Or mess with your local NTP server.

## Usage

### Building the binary

Note: `v0.0.18` and greater requires at least Zig `0.14.0-dev.1411+a670f5519` to build.

```sh
zig build -Dexe [--release=[safe|small|fast]]
# build and run, debug: zig build -Dexe run
# library tests: zig build test
```

### NTP library

Currently targets SNTP ([RFC4330](https://datatracker.ietf.org/doc/html/rfc4330)), does not implement the full NTP spec. `src/ntp.zig` can be used independently in other projects; it is exposed via this project's `build.zig` and `build.zig.zon` files. Other dependencies of the binary are lazy, i.e. they won't be fetched if you use only the library in another project.

### Usage of the binary

```sh
Usage: ntp_client [options]

Options:
  -s, --server           NTP server to query (default: pool.ntp.org)
  -v, --protocol-version NTP protocol version, 3 or 4 (default: 4)
  -4, --ipv4             use IPv4 instead of the default IPv6
  --src-ip               IP address to use for sending the query (default: 0::0 / IPv6 auto-select)
  --src-port             UDP port to use for sending the query (default: 0 / any port)
  --dst-port             UDP port of destination server (default: 123)
  -z, --timezone         Timezone to use in console output (default: UTC)
  -j, --json             Print result in JSON
  -i, --interval         Interval for repeated queries in seconds (default: null / one-shot operation)
  -a, --all              Query all IP addresses found for a given server URL (default: false / stop after first)
  -h, --help             Show this help and exit
```

## Demo output

```sh
zig build run -Dexe -- -4 -z local
```

```text
---***---
Server name: "pool.ntp.org"
Server address: "185.41.106.152:123"
---
LI=0 VN=4 Mode=4 Stratum=2 Poll=0 (0 s) Precision=-25 (29 ns)
ID: 0x6C6735C0
Server root dispersion: 518 us, root delay: 5599 us
---
Server last synced  : 2024-08-27T09:36:35.013046150+02:00
T1, packet created  : 2024-08-27T09:44:24.203294803+02:00
T2, server received : 2024-08-27T09:44:24.209060683+02:00
T3, server replied  : 2024-08-27T09:44:24.209271892+02:00
T4, reply received  : 2024-08-27T09:44:24.215617157+02:00
(timezone displayed: Europe/Berlin)
---
Offset to timserver: -0.000 s (-290 us) 
Round-trip delay:    0.012 s (12111 us)
---
Result flags: 0 (OK)
---***---
```

## Compatibility and Requirements

Developed & tested mostly on Debian Linux, on an x86 machine. Windows worked last time I tested (build.zig links libc for this), Mac OS might work (can't test this).

## Zig version

This package tracks Zig `0.14.0-dev` (master); might not compile with older versions.

## Dependencies

- [flags](https://github.com/joegm/flags) for command line argument parsing
- [zdt](https://github.com/FObersteiner/zdt) to display timestamps as timezone-local datetimes

## License

MIT. See the LICENSE file in the root directory of the repository.
