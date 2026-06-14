# Capturing and analysing REAC yourself

How to capture a REAC stream off the wire and decode it, plus the traps that make a
correct decoder look broken. See [wire-format.md](wire-format.md) for the schema this
relies on.

## Capture

REAC is non-IP (EtherType `0x8819`), so capture at Layer 2.

**Linux, raw socket.** Open an `AF_PACKET` `SOCK_RAW` socket with protocol
`htons(0x8819)`, resolve the interface index via `SIOCGIFINDEX`, and bind a
`sockaddr_ll` to that ifindex with `sll_protocol = htons(0x8819)`. Even bound to the
ethertype, double-check `buf[12]==0x88 && buf[13]==0x19` on each frame. Non-blocking:
treat `EAGAIN`/`EWOULDBLOCK` as "nothing ready"; on `EINTR` return so a blocking idle
listen can be stopped.

**On a router (tcpdump).**

    tcpdump -i <iface> -xx 'ether proto 0x8819'

Use `-xx`, **not** `-x` (payload-only strips the link header you need). BusyBox
`tcpdump` has no `timeout`, so background the capture and kill it. Capture on a wired
LAN / access port, **never over the same Wi-Fi hop you are measuring**.

## Validate a frame

1. length == 1492
2. ethertype `0x88 0x19`
3. end marker `0xC2 0xEA`
4. extract the LE counter from bytes 14..15

## Decode audio

De-interleave the 1440 B audio region into planar 24-bit LE PCM:

- **M-5000-class:** plain sample-major — channel `ch`, sample `s` at
  `(s*n_channels + ch)*3`.
- **obs-h8819-class:** the even/odd braid (see [wire-format.md](wire-format.md)).

Output is planar (channel 0's samples, then channel 1's, …), 3 bytes per sample.
Decode returns samples-per-channel (12) per frame.

## Sanity-check the rate

Measure packets-per-second:

- ~4000 pps → 48 kHz
- ~8000 pps → 96 kHz

Confirm the live channel count (40) to rule out any channel-halving model.

## Traps

**VLAN tag.** An 802.1Q tag can make a strict (untagged-only) decoder print
`MALFORMED` / 0 RTP, which looks exactly like a decode bug. Run a tag-stripping
analyzer first; confirm tagged-vs-buggy with:

    tcpdump -nr X.pcap -e -c3      # look for 802.1Q

**Level correctness.** A cross-decoder verify (C == Python) only proves two
implementations agree on de-interleave; it does **not** validate sample *levels*
against a known input. For that, feed a calibrated known signal (a sine at a known
dBFS, a full-scale ramp, a DC code) and read the numeric 24-bit values:

- clipping at ±`0x7FFFFF` for a −20 dBFS input → gain / scale error
- non-monotonic ramp → byte-order / justification wrong
- sign wraps → signed / unsigned error

Compare s24be vs s24le justification variants.

## Tools

- [reac-tools](https://github.com/FreeREAC) — REAC traffic analysis (loss / jitter /
  cross-mix, codec, probes) over a pcap or live.
- [reac-aes67](https://github.com/FreeREAC) — a working decoder + AES67 bridge whose
  `reac_capture` / `reac_decode` implement the mechanisms above.
- Sample captures and per-capture notes live in
  [reac-lab](https://github.com/FreeREAC/reac-lab).
