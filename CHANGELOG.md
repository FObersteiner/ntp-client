# CHANGELOG

<https://keepachangelog.com/>

Types of changes

- 'Added' for new features.
- 'Changed' for changes in existing functionality.
- 'Deprecated' for soon-to-be removed features.
- 'Removed' for now removed features.
- 'Fixed' for any bug fixes.
- 'Security' in case of vulnerabilities.

## Unreleased

## 2025-01-05, v0.0.19
### Changed

- bump dependencies

## 2024-09-05, v0.0.18

- bump zdt dependency to 0.2.1
- bump flags dependency flags to newest commit (requires zig 0.14-dev to build the ntp-client binary)

## 2024-08-04, v0.0.17

- refactor main
- enforce match of source and target address family. An IPv6 server should only be reachable if an IPv6 source address is used.
- use 'flags' package v0.6.0

## 2024-07-12, v0.0.16

- result validation / flagging
- pprinter for flags

## 2024-07-05, v0.0.15

- handle NTP era for Unix time input / output
- ntp.Packet: make init method public, buffer initialiizer method is now called initToBuffer

## 2024-06-26, v0.0.14

- use lazy dependencies so that another project can use ntp.zig without having to fetch the dependencies of this project

## 2024-06-24, v0.0.13

- use parseIp instead of resolveIp, avoids "std.net.if_nametoindex unimplemented for this OS" error on specific OS (thanks @part1zano on codeberg)
- disable autodoc feature in build.zig since unused

## 2024-06-20, v0.0.12

- add parser for ref ID (stratum 0 or 1)
- build/zon: expose ntp.zig as a library

## 2024-06-16, v0.0.11

- keep client timestamps local to client
- send random number as client xmt

## 2024-06-16, v0.0.10

- add 5 second timeout if server doesn't answer
- revise pprint to console
- more tests, some new functionality (correctTime, refIDprintable)

## 2024-06-15, v0.0.9

- dependency update

## 2024-06-14, v0.0.8

- add IPv6 support
