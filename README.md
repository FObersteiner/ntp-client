# ntp_client

CLI app to query an NTP server to verify your OS clock setting.

The original repository is hosted [on Codeberg](https://codeberg.org/FObersteiner/ntp_client).

## Requirements

See `build.zig.zon`.

- [zig-clap](https://github.com/Hejsil/zig-clap) for command line argument parsing
- [zdt](https://codeberg.org/FObersteiner/zdt) to display timestamps as UTC or timezone-local datetimes
