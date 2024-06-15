<!-- -*- coding: utf-8 -*- -->

# NTP Client

Command line app to query an NTP server, to verify your OS clock setting. The original repository is hosted [on Codeberg](https://codeberg.org/FObersteiner/ntp_client).

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
  -h, --help             Show this help and exit
```

## Compatibility and Requirements

Developed & tested on Linux. Windows should work (build.zig links libc for this), Mac OS might work (can't test this)

## Zig version

This package is developed with Zig `0.14.0-dev`, might not compile with older versions. As of 2024-06-15, Zig-0.12 and Zig-0.13 (both stable) should work.

Currently works with `0.12-stable` and `master`.

## Dependencies

- [flags](https://github.com/n0s4/flags) for command line argument parsing
- [zdt](https://codeberg.org/FObersteiner/zdt) to display timestamps as UTC or timezone-local datetimes

## License

MIT. See the LICENSE file in the root directory of the repository.
