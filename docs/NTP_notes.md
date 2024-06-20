<!-- -*- coding: utf-8 -*- -->

# NTP

## inspired by

- <https://www.eecis.udel.edu/~mills/exec.html>
- <https://github.com/beevik/ntp>
- <https://lettier.github.io/posts/2016-04-26-lets-make-a-ntp-client-in-c.html>

## limits

Only fields up to and including Transmit Timestamp are used further on.
Extensions are not supported (yet).

## general procedure of NTP query

1. Client creates a request.
   This request contains the current time of the local machine,
   as transmit timestamp (xmt).
2. Request struct gets packed into bytes and send to the server.
3. Server receives the packet and does its magic.
   - origin timestamp (org, T1): the transmit timestamp of the client
   - receive timestamp (rec, T2): moment of message reception
   - reference timestamp (ref): moment when server was last synced
   - transmit timestamp (xmt, T3): moment when the reply packet leaves the server
4. Client receives the reply and stores the moment when the reply
   was received (dst, T4).
5. Client can calculate round trip delay,local clock offset etc.

## on Linux

On a Linux running `timedatectl`, check via `timedatectl timesync-status`

## Specs

NTP v4 data format, <https://datatracker.ietf.org/doc/html/rfc5905>

### Packet

```text
    0                   1                   2                   3
    0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    |LI | VN  |Mode |    Stratum     |     Poll      |  Precision   |
    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    |                         Root Delay                            |
    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    |                         Root Dispersion                       |
    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    |                          Reference ID                         |
    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    |                                                               |
    +                     Reference Timestamp (64)                  +
    |                                                               |
    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    |                                                               |
    +                      Origin Timestamp (64)                    +
    |                                                               |
    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    |                                                               |
    +                      Receive Timestamp (64)                   +
    |                                                               |
    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    |                                                               |
    +                      Transmit Timestamp (64)                  +
    |                                                               |
    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    |                                                               |
    .                                                               .
    .                    Extension Field 1 (variable)               .
    .                                                               .
    |                                                               |
    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    |                                                               |
    .                                                               .
    .                    Extension Field 2 (variable)               .
    .                                                               .
    |                                                               |
    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    |                          Key Identifier                       |
    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
    |                                                               |
    |                            dgst (128)                         |
    |                                                               |
    +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

### Kiss Codes (stratum = 0, monitoring, debugging)

```text
    +------+------------------------------------------------------------+
    | Code |                           Meaning                          |
    +------+------------------------------------------------------------+
    | ACST | The association belongs to a unicast server.               |
    | AUTH | Server authentication failed.                              |
    | AUTO | Autokey sequence failed.                                   |
    | BCST | The association belongs to a broadcast server.             |
    | CRYP | Cryptographic authentication or identification failed.     |
    | DENY | Access denied by remote server.                            |
    | DROP | Lost peer in symmetric mode.                               |
    | RSTR | Access denied due to local policy.                         |
    | INIT | The association has not yet synchronized for the first     |
    |      | time.                                                      |
    | MCST | The association belongs to a dynamically discovered server.|
    | NKEY | No key found. Either the key was never installed or is     |
    |      | not trusted.                                               |
    | RATE | Rate exceeded. The server has temporarily denied access    |
    |      | because the client exceeded the rate threshold.            |
    | RMOT | Alteration of association from a remote host running       |
    |      | ntpdc.                                                     |
    | STEP | A step change in system time has occurred, but the         |
    |      | association has not yet resynchronized.                    |
    +------+------------------------------------------------------------+
```

### Globals / Boundaries

```text
    +-----------+-------+----------------------------------+
    | Name      | Value | Description                      |
    +-----------+-------+----------------------------------+
    | PORT      | 123   | NTP port number                  |
    | VERSION   | 4     | NTP version number               |
    | TOLERANCE | 15e-6 | frequency tolerance PHI (s/s)    |
    | MINPOLL   | 4     | minimum poll exponent (16 s)     |
    | MAXPOLL   | 17    | maximum poll exponent (36 h)     |
    | MAXDISP   | 16    | maximum dispersion (16 s)        |
    | MINDISP   | .005  | minimum dispersion increment (s) |
    | MAXDIST   | 1     | distance threshold (1 s)         |
    | MAXSTRAT  | 16    | maximum stratum number           |
    +-----------+-------+----------------------------------+
```
