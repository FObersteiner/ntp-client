<!-- -*- coding: utf-8 -*- -->

# NTP Client

Command line app to query an [NTP](https://datatracker.ietf.org/doc/html/rfc5905) server, to verify your OS clock setting.

- [on Codeberg](https://codeberg.org/FObersteiner/ntp_client)
- [on github](https://github.com/FObersteiner/ntp-client)

## Usage

### Building the binary

```sh
zig build -Dexe [--release=[safe|small|fast]]
# build and run, debug: zig build -Dexe run
# library tests: zig build test
```

### NTP library

Currently targets just SNTP ([RFC4330](https://datatracker.ietf.org/doc/html/rfc4330)). `src/ntp.zig` can be used independently in other projects; it is exposed via this project's `build.zig` and `build.zig.zon` files. Other dependencies of the binary are lazy, i.e. they won't be fetched if you use only the library in another project.

### Usage of the binary

```sh
Usage: ntp_client [options]

Options:
  -s, --server           NTP server to query (default: pool.ntp.org)
  -v, --protocol-version NTP protocol version, 3 or 4 (default: 4)
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
zig build run -Dexe -- -z local
```

```text
---***---
Server name: "pool.ntp.org"
Server address: "167.235.69.67:123"
---
LI=0 VN=4 Mode=4 Stratum=3 Poll=0 (0 s) Precision=-25 (29 ns)
ID: 0xE0928157
Server root dispersion: 1388 us, root delay: 8224 us
---
Server last synced  : 2024-07-17T21:24:24.462370132+02:00
T1, packet created  : 2024-07-17T21:31:16.304413052+02:00
T2, server received : 2024-07-17T21:31:16.296820666+02:00
T3, server replied  : 2024-07-17T21:31:16.296837443+02:00
T4, reply received  : 2024-07-17T21:31:16.323274023+02:00
(timezone displayed: Europe/Berlin)
---
Offset to timserver: -0.017 s (-17015 us)
Round-trip delay:    0.019 s (18844 us)
---
Result flags: 0 (OK)
---***---
```

## Compatibility and Requirements

Developed & tested on Linux (Debian, on an x86 machine). Windows worked last time I tested (build.zig links libc for this), Mac OS might work (can't test this).

## Zig version

This package is developed with Zig `0.14.0-dev` (master), might not compile with older versions. As of 2024-08-04, Zig-0.12 and Zig-0.13 (both stable) should work.

## Dependencies

- [flags](https://github.com/n0s4/flags) for command line argument parsing
- [zdt](https://codeberg.org/FObersteiner/zdt) to display timestamps as UTC or timezone-local datetimes

## License

MIT. See the LICENSE file in the root directory of the repository.
