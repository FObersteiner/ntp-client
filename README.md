<!-- -*- coding: utf-8 -*- -->

# NTP Client

Command line app to query an NTP server, to verify your OS clock setting.

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

NTP library (`src/ntp.zig`) can be used independently in other projects; it is exposed via this project's `build.zig` and `build.zig.zon` files. Other dependencies of the binary are lazy, i.e. they won't be fetched if you use only the library in another project.

### Usage of the binary

```sh
Usage: ntp_client [options]

Options:
  -s, --server           NTP server to query (default: pool.ntp.org)
  -p, --port             UDP port to use for NTP query (default: 123)
  -v, --protocol-version NTP protocol version, 3 or 4 (default: 4)
  -a, --all              Query all IP addresses found for a given server URL (default: false / stop after first)
  --src-ip               IP address to use for sending the query (default: 0.0.0.0 / auto-select)
  --src-port             UDP port to use for sending the query (default: 0 / any port)
  -z, --timezone         Timezone to use in results display (default: UTC)
  -j, --json             Print result as JSON
  -h, --help             Show this help and exit
```

## Demo output

```sh
zig build run -Dexe -- -z local
```

```text
---***---
Server name: "pool.ntp.org"
Server address: "185.252.140.126:123"
---
LI=0 VN=4 Mode=4 Stratum=2 Poll=0 (0 s) Precision=-25 (29 ns)
ref_id: 2355160
root_delay: 16021 us, root_dispersion: 1022 us
---
Server last synced  : 2024-07-03T16:01:24.652337151+02:00
T1, packet created  : 2024-07-03T16:15:57.183283642+02:00
T2, server received : 2024-07-03T16:15:57.201324404+02:00
T3, server replied  : 2024-07-03T16:15:57.201334367+02:00
T4, reply received  : 2024-07-03T16:15:57.208543450+02:00
(timezone displayed: Europe/Berlin)
---
Offset to timserver: 0.005 s (5415 us)
Round-trip delay:    0.025 s (25249 us)
---***---
```

## Compatibility and Requirements

Developed & tested on Linux (Debian, on an x86 machine). Windows worked last time I tested (build.zig links libc for this), Mac OS might work (can't test this).

## Zig version

This package is developed with Zig `0.14.0-dev` (master), might not compile with older versions. As of 2024-06-15, Zig-0.12 and Zig-0.13 (both stable) should work.

## Dependencies

- [flags](https://github.com/n0s4/flags) for command line argument parsing
- [zdt](https://codeberg.org/FObersteiner/zdt) to display timestamps as UTC or timezone-local datetimes

## License

MIT. See the LICENSE file in the root directory of the repository.
