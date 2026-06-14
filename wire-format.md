# REAC wire format

The on-wire schema of REAC, derived from packet captures plus three GPL-3.0
reverse-engineered codebases (`per-gron/reacdriver`, `norihiro/obs-h8819-source`,
`norihiro/reaccapture`) and our own decoder. Facts are tagged **[V]** verified on
our captures, **[S]** from upstream RE source, **[?]** inferred/pending.

## Overview

REAC is a proprietary **synchronous Layer-2** audio-over-Ethernet transport. One
**master** (a V-Mixer console) clocks the whole fabric; **slaves** (stageboxes)
lock to it; a **split** receiver listens passively. Up to **40 channels** per REAC
connection, 24-bit, at 44.1 / 48 / 96 kHz, over a single Cat5e run.

## Physical / link layer

- **100BASE-TX** (Fast Ethernet, full-duplex), Cat5e / RJ-45 — not 10 Mbit, not
  gigabit at the link layer.
- **EtherType `0x8819`** (non-IP). The capture filter is literally
  `ether proto 0x8819`.
- 40 channels of 24-bit at 96 kHz is ~92 Mbit/s — about filling one 100BASE-TX
  link. Roland publishes 0.375 ms protocol latency at 96 kHz (= 3 × 125 µs packet
  slots) and recommends unmanaged 100BASE-TX switches for splitting.

## Frame geometry (the schema) [V][S]

A fixed **1492-byte** Ethernet frame: 50 B non-audio header + 1440 B audio + 2 B
end marker. The audio block is constant (rate-invariant); only the packet *rate*
changes with sample rate.

| offset | size | field | notes |
|---|---|---|---|
| 0 | 6 | dst MAC | `ff:ff:ff:ff:ff:ff` = master→fabric (broadcast output); unicast to master MAC = slave→master (input) |
| 6 | 6 | src MAC | Roland OUI `00:40:ab` |
| 12 | 2 | EtherType | const `0x88 0x19` |
| 14 | 2 | counter | u16 LE, +1 per frame, wraps at 2¹⁶; `counter = b[14] | b[15]<<8` |
| 16 | 2 | type | byte-pair frame type (registry below) |
| 18 | 32 | data | opaque control/handshake metadata; `data[31]` is a checksum; layout depends on type |
| 50 | 1440 | audio | 40 ch × 12 samp × 3 B, carried in **every** frame type incl. FILLER |
| 1490 | 2 | end | const `0xC2 0xEA` end marker |

The packet header (bytes 14..49) is exactly `{counter[2]; type[2]; data[32]}` =
36 bytes.

**Frame validation.** A receiver validates a frame by: (1) EtherType `0x8819`;
(2) `0xC2 0xEA` at the tail; (3) minimum length (header + end marker);
(4) checksum over `data[]`. FILLER frames are exempt from the checksum check.

## Sequence counter [V]

16-bit **little-endian** at offset 14, +1 per frame, 16-bit wrap. The master sets
the counter on every outgoing packet from a monotonic counter.

Loss detection: `skipped = (counter - last - 1) & 0xFFFF`.

## Roles and addressing [V][S]

- **Master** (V-Mixer) owns the clock and broadcasts output frames to
  `ff:ff:ff:ff:ff:ff`.
- **Slave** (stagebox) unicasts its input frames to the master MAC and locks to the
  master clock, learning the master MAC from the handshake.
- **Split** is a passive listener that periodically unicasts a `SPLIT_ANNOUNCE`
  (~1 s) but carries no audio. A pure passive tap can skip the announce entirely
  and still decode the broadcast audio — this is why a bridge can decode without
  participating.

OUI is `00:40:ab`; the open-source driver's stand-in device MAC is
`00:40:ab:c4:80:f6`; a real master's MAC is carried in `MASTER_ANNOUNCE`. A
per-device descriptor `{addr[6]; in_channels; out_channels}` is exchanged in the
handshake.

**REAC carries no zone or port id on the wire** — zone/port selection is an
external concern (switch / VLAN topology), not a protocol field.

## Frame-type registry — `type[2]` [V][S]

| type | name | notes |
|---|---|---|
| `0x00 0x00` | FILLER | carries audio; receivers skip the checksum on this type |
| `0xcd 0xea` | CONTROL | sub-typed by the first 5 `data[]` bytes |
| `0xcf 0xea` | MASTER_ANNOUNCE | |
| `0xce 0xea` | SPLIT_ANNOUNCE | |

There is **no distinct "audio" frame type** — audio rides in every frame, including
FILLER. The master interleaves FILLER frames with periodic CONTROL / ANNOUNCE
frames while continuously filling the audio region.

### CONTROL sub-types — `data[0..4]` prefix [S]

| prefix | name |
|---|---|
| `01 00 00 1a 00` | CONTROL_PACKET_TYPE_ONE |
| `01 02 00 0e 00` | CONTROL_PACKET_TYPE_TWO |
| `01 03 00 19 01` | CONTROL_PACKET_TYPE_THREE |
| `01 01 00 18 00` | CONTROL_PACKET_TYPE_FOUR |
| `01 03 00 10 82` | SLAVE_ANNOUNCE1 |
| `04 03 00 14 00` | SLAVE_ANNOUNCE2 |
| `04 03 00 13 00` | SLAVE_ANNOUNCE3 |
| `01 03 00 01 81` | SLAVE_ANNOUNCE4 |

The remaining `data[5..31]` carry the sub-type payload plus checksum.

## The `data[32]` block — checksum (fully specified) [V]

8-bit modular checksum over the 32 `data[]` bytes.

- **Verify:** `sum = (Σ data[0..31]) mod 256`; valid iff `sum == 0`.
- **Apply:** `s = (Σ data[0..30]) mod 256`; `data[31] = (256 - s) & 0xFF`
  (two's-complement negation, so the full 32-byte sum is 0 mod 256).
- FILLER frames are exempt.

## MasterAnnouncePacket — type `0xcf 0xea` [V][S]

Overlaid on `data[]`: `{unknown1[9]; address[6]; inChannels; outChannels;
unknown2[4]}`.

| data | field | notes |
|---|---|---|
| 0..8 | unknown1[9] | master emits `ff ff 01 00 01 03 0d 01 04`. `data[6]` is the discriminator: `0x0d` = first/primary announce (carries channel counts); `0x0a` = the second announce confirming a split's identity (form `ff ff 01 00 01 03 0a 02 02`) |
| 9..14 | address[6] | the master's MAC |
| 15 | inChannels | master in-channel count |
| 16 | outChannels | master out-channel count |
| 17..20 | unknown2[4] | `01 <split?> 01 00`: `data[17]=0x01`; `data[18]=0x01` only immediately after a split-announce-response was just sent, else `0x00`; `data[19]=0x01`; `data[20]=0x00` |

A receiver recovers the master from `data[6]==0x0D` (master announce),
MAC = `data[9..14]`, in = `data[15]`, out = `data[16]`. A master also connected to a
slave doubles the advertised channel counts.

## Audio de-interleave — two device families [V][S]

Audio is 40 ch × 12 samp × 3 B = 1440 B. Two distinct in-payload byte layouts exist
across Roland generations:

1. **obs-h8819 even/odd braid** (`convert_to_pcm24lep`): per channel,
   `base = (ch & ~1)*3` and stride 120 (= n_channels × 3); even ch →
   `[sptr[3], sptr[0], sptr[1]]`, odd ch → `[sptr[4], sptr[5], sptr[2]]`, treated as
   24-bit little-endian. Faithful to the device obs-h8819 targets. **[S]**
2. **Plain LE sample-major** (the M-5000): channel `ch` / time-sample `s` starts at
   `(s*n_channels + ch)*3`, a straight 3-byte copy. **[V]** — decoding a live M-5000
   stream the plain way is coherent (coherence ~0.999); the obs-h8819 braid scrambles
   the same payload into noise.

REAC's wire endianness (24-bit LE) is common across devices, but the in-payload
channel-pair byte ordering is **not** identical across generations. `reaccapture`
additionally ships big-endian and 16-bit truncation variants of the same
de-interleave; s24le is the verified justification at 48 kHz.

## Channel-info block (in the CONTROL stream) [S][?]

The master's CONTROL stream carries a channel-info block: one 3-byte record per
channel `[channel#, type-flags, gain]`, packed 8 records per CONTROL frame, rotating
channel numbers modulo 49. The block terminator is the channel-number byte `0xfe`
written at the rotation index for channel 48 (paired with flag byte `0x01`) — i.e.
`channel# = 0xfe` is the terminator, not "flag `0x01` = terminator".

Other states stuff the interface MAC, a `0xc0 0xa8` (= 192.168) address prefix
repeated twice, and ASCII tags `SYSP` (`53 59 53 50`) and `XVSCEN`
(`58 56 53 43 45 4e`) into `data[]`. This region is incompletely understood; treat
`data[5..30]` of CONTROL frames as partial beyond the 5-byte prefix and the
channel-info block. (The `0xc0 0xa8` bytes are a protocol fact — what a master stuffs
into CONTROL frames — not anyone's network address.)

## Sample rates and packet rate (SETTLED) [V]

The frame is rate-invariant (always 40 ch × 12 samp × 3 B = 1440 B). Sample rate is
set by the **packet rate**: `pps = rate / 12`, `samples_per_pkt = 12`.

| rate | pps | slot | status |
|---|---|---|---|
| 44.1 kHz | 3675 | 272 µs | [?] not yet exercised on our rig |
| 48 kHz | 4000 | 250 µs | [V] measured ~4000 pps |
| 96 kHz | 8000 | 125 µs | [V] settled — double-pps, same 1492 B / 40-ch frame |

**96 kHz model settled.** The on-rig 96 kHz stream measured ~8000 pps carrying the
same 1492 B / 40-channel frame (double-pps model `{96000, 40, 12}`), matching
`reacdriver`'s constants (`SAMPLES_PER_PACKET=12`, `PACKETS_PER_SECOND=8000`,
`MAX_CHANNEL_COUNT=40`). The rejected channel-halving model `{96000, 20, 24}` would
have been ~4000 pps / 20 ch; both the measured pps and the channel count refuted it.
Payload growth was already ruled out (the 48 kHz frame fills ~99% of the 1500 MTU and
REAC is 100BASE-TX, so it adds packets, never enlarges them). A "24 tracks @96k"
figure in a Roland recorder manual is a storage limit, not a wire constraint.

## Clocking [V][S]

One sample-clock master; the whole fabric locks to it; mismatched rates → no audio.
The receiver is a **hardware clock slave with no jitter buffer** — it recovers word
clock from packet arrival cadence (the master timer fires every `1e9 / pps` ns). This
is why raw REAC tolerates Wi-Fi / jitter poorly, and why an AES67 bridge must add the
de-jitter layer the REAC slave lacks.

Connection is declared lost after **1000 ms** without a sized audio packet. At the
transport layer, "connected" is declared purely by **packet length**, independent of
the announce handshake: the first frame whose length equals a full audio frame flips
`connected = true`. This is exactly why a passive tap connects without any handshake.

## Handshakes [S]

Audio is a continuous broadcast stream (no per-packet request/response). Connection
setup is a call/answer exchange in `data[32]`, driven by the periodic
`MASTER_ANNOUNCE` (re-announced ~once/second).

### Split handshake (fully specified)

1. `NOT_INITIATED` → on `MASTER_ANNOUNCE` with `data[6]==0x0d`: store master MAC +
   in/out channels → `GOT_MASTER_ANNOUNCE`.
2. send `SPLIT_ANNOUNCE` (`0xce 0xea`) `data[0..8] = 01 00 7f 00 01 03 08 43 05` +
   our MAC → `SENT_FIRST_ANNOUNCE`.
3. on `MASTER_ANNOUNCE` with `data[6]==0x0a` whose address == our MAC: read
   `splitIdentifier = data[16]` → `GOT_SECOND_MASTER_ANNOUNCE`.
4. send `SPLIT_ANNOUNCE` `data[0..8] = 01 00 <id> 00 01 03 08 42 05` + our MAC →
   `CONNECTED`.
5. keep-alive `SPLIT_ANNOUNCE` `01 00 <id> 00 01 03 02 41 05`, every announce
   checksummed; disconnect if no packet seen since last announce.

The master accepts a split by capturing the split's MAC from `data[9..14]` and
replying inside a `MASTER_ANNOUNCE` with a split-announce response: `data[6]=0x0a`,
`data[9..14]` = the split's MAC, `data[15]=0x00`, `data[16]=0x60` (the assigned split
identifier the split later echoes in its `data[2]`; "0x04 and up seems to be fine").

### Slave handshake (partial in the driver)

1. `NOT_INITIATED` → waits for `CONTROL_PACKET_TYPE_ONE` with `data[29]==0xc0`,
   `data[30]==0xa8`, then another with `data[5]==0x01`, `data[6]==0x01` and
   `data[7..12]==data[17..22]`: stores master MAC from `data[7..12]` →
   `GOT_MAC_ADDRESS_INFO`.
2. emits FILLER; on `CONTROL_PACKET_TYPE_THREE` → `SENDING_INITIAL_ANNOUNCE` (times
   out back after 2 s).
3. sends 5 CONTROL frames each prefixed with `SLAVE_ANNOUNCE1..4` + a fixed 19-byte
   handshake body, unicast to the master MAC → `HAS_SENT_ANNOUNCE`.
4. emits FILLER keep-alive.

The upstream driver marks the slave path incomplete; full master↔slave completion has
since been observed live (see [firmware-findings.md](firmware-findings.md), slave
establishment).

## Upstream (stagebox→master) audio layout — measured [V][?]

A single REAC port is bidirectional; one tap captures both halves. Stagebox **INPUT**
channels travel toward the mixer as raw, pre-patch PCM (the mixer's internal patch
decides routing after they cross REAC). Stagebox **OUTPUT** channels travel from
mixer to box carrying whatever the mixer routed to each slot (post-routing).

The upstream return frame is unicast to the master MAC, ~628 B at 96 kHz = ~49–52 B
header + 576 B audio + trailer (576 = 16 ch × 3 B × 12 samples). **Plain 24-bit LE,
sample-major** — identical packing to the verified M-5000 downstream; the injected
tone decodes clean reading 3 consecutive LE bytes, confirming the obs-h8819 braid does
not apply upstream.

The audio is intact on the wire (every tone decoded clean) but the channel **MAP** is
scrambled — the wire does **not** carry input N → channel N. The scramble is
FPGA-owned, rate-independent, and not caused by loss / jitter or by a byte-transparent
re-pacer. Single-tone sweeps could not pin the exact map (a smooth sine reads high
autocorrelation across a plateau of adjacent bytes); resolving it needs distinct
simultaneous tones, one frequency per input. **The exact map is OPEN.** 48 kHz is
inferred: 8000 fps fixed, samples/frame scale with rate (96k→12, 48k→6), so 48 kHz
audio = 16 ch × 3 B × 6 = 288 B, frame ~342 B; same plain LE packing; same
rate-independent scramble.

Distinguishing source / direction from the wire alone: **source MAC** → which
device/port (OUI `00:40:ab`); **dest MAC** → direction/role (mixer→box OUTPUT frames
are broadcast `ff:ff:ff:ff:ff:ff`, box→mixer INPUT frames are unicast to the console
MAC); **802.1Q VLAN tag** → which REAC port/zone in a multi-zone trunk. **Not**
derivable from the wire: which physical jack or patch point a slot maps to — the frame
carries positional slots, no labels (resolve via a labelled-tone probe or the
remote-control query in [firmware-findings.md](firmware-findings.md)).

## Bandwidth / link budget

- **48 kHz:** 40 ch × 24 bit × 48 kHz ≈ 46 Mbit/s audio (~48–60 Mbit/s with framing)
  — comfortably under 100BASE-TX.
- **96 kHz double-pps:** ~92–97 Mbit/s — about saturating 100BASE-TX.

Payload growth is ruled out: REAC adds **packets**, not bytes-per-packet.
