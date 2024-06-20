<!-- -*- coding: utf-8 -*- -->

# NTP Client

Command line app to query an NTP server, to verify your OS clock setting.

- [on Codeberg](https://codeberg.org/FObersteiner/ntp_client)
- [on github](https://github.com/FObersteiner/ntp-client)

```text
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

```shell
zig build run -- -z Europe/Berlin
```

```text
---***---
Server name: "pool.ntp.org"
Server address: "144.91.116.85:123"
---
LI=0 VN=4 Mode=4 Stratum=2 Poll=0 (0 s) Precision=-25 (29 ns)
ref_id: 2284619087
root_delay: 3555 us, root_dispersion: 61 us
---
Server last synced  : 2024-06-20T17:27:37.417288141+02:00
T1, packet created  : 2024-06-20T17:27:43.078412820+02:00
T2, server received : 2024-06-20T17:27:43.114188101+02:00
T3, server replied  : 2024-06-20T17:27:43.116242943+02:00
T4, reply received  : 2024-06-20T17:27:43.157438264+02:00
(timezone displayed: Europe/Berlin)
---
Offset to timserver: -0.003 s (-2711 us)
Round-trip delay:    0.077 s (76970 us)
---***---
```

## Compatibility and Requirements

Developed & tested on Linux. Windows should work (build.zig links libc for this), Mac OS might work (can't test this)

## Zig version

This package is developed with Zig `0.14.0-dev`, might not compile with older versions. As of 2024-06-15, Zig-0.12 and Zig-0.13 (both stable) should work.

## Dependencies

- [flags](https://github.com/n0s4/flags) for command line argument parsing
- [zdt](https://codeberg.org/FObersteiner/zdt) to display timestamps as UTC or timezone-local datetimes

## License

MIT. See the LICENSE file in the root directory of the repository.
