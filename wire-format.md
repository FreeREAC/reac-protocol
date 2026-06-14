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

**The wire framing and the sample clock are owned by an on-board FPGA**, not the
device CPU. **[S]** The FPGA assembles and parses the
`0x8819` Ethernet frames, generates the per-frame sample tick, and runs the
per-frame link-check counter; the CPU is handed already-parsed control messages and
runs only the high-level connection state machine on top. The practical consequence
for an outside observer: every byte-level fact in this document is something the FPGA
produces, and the connection *behaviour* in the lifecycle section is the only layer a
software node can mimic without re-implementing the framing/clock engine.

## Physical / link layer

- **100BASE-TX** (Fast Ethernet, full-duplex), Cat5e / RJ-45 — not 10 Mbit, not
  gigabit at the link layer.
- **EtherType `0x8819`** (non-IP). The capture filter is literally
  `ether proto 0x8819`.
- 40 channels of 24-bit at 96 kHz is ~92 Mbit/s — about filling one 100BASE-TX
  link. Roland publishes 0.375 ms protocol latency at 96 kHz (= 3 × 125 µs packet
  slots) and recommends unmanaged 100BASE-TX switches for splitting.

## Frame geometry (the schema) [V][S]

The master's **downstream broadcast** is a fixed **1492-byte** Ethernet frame: 50 B
non-audio header + 1440 B audio + 2 B end marker. The audio block is constant
(rate-invariant) — always 40 channels; only the packet *rate* changes with sample
rate. (A stagebox's **upstream** return is a different, smaller frame carrying the
box's own input count — see *Upstream audio layout* below.)

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
| `0xcf 0xea` | MASTER_ANNOUNCE | ~1/s; carries master MAC + in/out channel counts |
| `0xce 0xea` | SPLIT_ANNOUNCE | the passive-split path |
| `0xc2 0xea` | ENDING | the split/teardown path (distinct from the `0xC2 0xEA` end-marker role at byte 1490) |

There is **no distinct "audio" frame type** — audio rides in every frame, including
FILLER. The master interleaves FILLER frames with periodic CONTROL / ANNOUNCE
frames while continuously filling the audio region.

**What our stageboxes actually emit. [V]** A stagebox in slave mode sends only
**FILLER** (`0x00 0x00`) and **CONTROL** (`0xcd 0xea`) — zero `0xce 0xea` /
`0xc2 0xea`. The `SPLIT_ANNOUNCE` / `ENDING` types belong to the passive-split path;
a plain slave, a merge unit in slave mode, and a master's mirror output never source
them. They remain the last unmapped frame types — capturing them needs a real split
device in the chain. `MASTER_ANNOUNCE` (`0xcf 0xea`) is master-only and is likewise
never sourced by a slave.

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

## Sample rates and the audio clock

The downstream frame is **rate-invariant** — always 40 ch × 12 samples × 3 B = 1440 B
of audio. The sample rate is carried entirely in the **packet rate**, never in the
frame: `pps = rate / 12`, 12 samples per frame.

| rate | pps (downstream) | slot period | audio bandwidth | status |
|---|---|---|---|---|
| 44.1 kHz | 3675 | 272.1 µs | ~46 Mbit/s | [?] not yet exercised on our rig |
| 48 kHz | 4000 | 250.0 µs | ~46 Mbit/s | [V] measured ~4000 pps |
| 96 kHz | 8000 | 125.0 µs | ~92 Mbit/s | [V] settled — double-pps |

What changes with rate is **only the packet rate** — and therefore the inter-frame
interval (the *slot period*, `1e9 / pps` ns). The frame layout, channel count (40),
sample width (24-bit), and the 12-samples-per-frame packing are identical at every
rate, and there is **no rate field on the wire**. 44.1 and 48 kHz carry the same audio
bandwidth and differ only in slot timing; 96 kHz doubles the packet rate (and the
bandwidth), about saturating the 100BASE-TX link.

**96 kHz model settled.** The on-rig 96 kHz stream measured ~8000 pps carrying the same
1492 B / 40-channel frame (double-pps model `{96000, 40, 12}`), matching `reacdriver`'s
constants (`SAMPLES_PER_PACKET=12`, `PACKETS_PER_SECOND=8000`, `MAX_CHANNEL_COUNT=40`).
The rejected channel-halving model `{96000, 20, 24}` would have been ~4000 pps / 20 ch;
both the measured pps and the channel count refuted it. Payload growth was already ruled
out (the 48 kHz frame fills ~99% of the 1500 MTU and REAC is 100BASE-TX, so it adds
packets, never enlarges them). A "24 tracks @96k" figure in a Roland recorder manual is
a storage limit, not a wire constraint. 48 kHz is verified at ~4000 pps; 44.1 kHz (3675
pps) is the same model, not yet exercised on our rig.

### How the clock is set and recovered [V][S]

REAC has **one sample-clock master** (the console). The master emits a frame every slot
period from its own crystal — 272 µs at 44.1 kHz, 250 µs at 48 kHz, 125 µs at 96 kHz —
and that cadence *is* the fabric word clock. The slot tick is generated **in the FPGA**,
not in CPU software, which is why the device firmware shows the connection logic but not
the sample clock itself. **[S]**

The receiver is a **hardware clock slave with no jitter buffer**. It does not buffer and
resample; it recovers word clock directly from packet **arrival cadence**, advancing its
clock one slot per frame. So a stagebox tolerates almost no arrival jitter — a late frame
is a late sample. This is why raw REAC runs badly over Wi-Fi, and why a bridge or relay
across a jittery hop has to re-impose the exact cadence the slave expects.

Master and slave agree on rate implicitly: the slave locks to whatever cadence the master
sends, so a rate mismatch simply means no lock and no audio. Connection is declared lost
after **1000 ms** without a sized audio frame. At the transport layer "connected" is
declared purely by **packet length** — the first frame whose length equals a full audio
frame flips `connected = true`, independent of the announce handshake. This is exactly
why a passive tap connects without participating.

### Choosing what the master locks to — the clock-source selector [S]

Although the recovered word clock itself is FPGA-internal and never appears on the REAC
audio wire, **the master exposes a clock-source selector** that decides which reference
its own crystal/PLL follows. The selectable sources are the front-panel-visible set:

- **WORD CLOCK** (external word-clock input),
- **REAC A** / **REAC B** (slave the master's clock to either REAC port),
- **INTERNAL** (free-run from the internal oscillator — the normal "I am the master"
  mode),
- **AES** (lock to an incoming AES/EBU pair).

This selection is made over the console's **separate control protocol**, not over the
REAC audio wire — it is a routing/configuration parameter, in the same family as
"which source feeds an output slot." Picking INTERNAL makes the desk free-run and clock
the whole fabric; picking REAC A/B makes the desk *slave* to a clock arriving on a REAC
port, which is how a master can be chained to follow another fabric. The on-wire REAC
cadence is unchanged in form by the selection — only *what* the master's slot tick is
disciplined to changes.

### How a re-clocking relay adapts across rates

A de-jitter relay (see [reac-repacer](https://github.com/FreeREAC/reac-repacer)) sits
between a jittery link and the clock-slave stagebox and must hand the slave a clean
cadence. Because there is no rate field, it **measures** the rate: count REAC frames on
the wired side over a short window, divide by elapsed time → pps → `rate = pps × 12`
(~3675 → 44.1 kHz, ~4000 → 48 kHz, ~8000 → 96 kHz). It then re-emits frames at exactly
`1e9 / pps` ns spacing on a recovered, free-running clock. On a **live rate change** (the
operator switches the console 48 ↔ 96 kHz) the measured pps jumps, so the relay
re-detects and re-locks to the new period. Since the frame itself is rate-invariant, the
relay never changes how it parses or forwards a frame — only the emit period changes with
rate.

### Downstream vs upstream packet rate

The two directions packetise differently:

- **Downstream** (master → box, broadcast 1492 B): **fixed 12 samples/frame**; the packet
  rate scales with sample rate (3675 / 4000 / 8000 pps).
- **Upstream** (box → master, unicast ~628 B at 96 kHz): **fixed ~8000 fps**; the samples
  per frame scale with rate instead (12 at 96 kHz, 6 at 48 kHz → ~288 B audio). Same plain
  LE sample-major packing; the channel map is FPGA-scrambled (see the upstream section).

The slot period a stagebox slaves to is the **downstream** cadence; the upstream return
runs on its own fixed-rate packetisation.

## Handshakes [S]

Audio is a continuous broadcast stream (no per-packet request/response). Connection
setup is a call/answer exchange in `data[32]`, driven by the periodic
`MASTER_ANNOUNCE` (re-announced ~once/second).

### Connection lifecycle as wire behaviour [V][S]

Seen purely from the wire — independent of the byte-level state-machine detail below
— a slave joining a master moves through four observable phases:

1. **Link-up flood.** On PHY link-up (and only PHY link-up — not a mere data gap)
   the box **floods broadcast FILLER** (`0x00 0x00`, dst `ff:ff:ff:ff:ff:ff`) at full
   packet rate to announce its presence. This lasts on the order of a second, then it
   switches direction.
2. **Cold-connect / grant.** The box sends a short **unicast cold-connect burst** of
   CONTROL frames to the master; the master replies (on its broadcast stream) with a
   matching short **grant burst** of CONTROL frames whose payload echoes the box's
   identity. The grant lands as a ~100-frame burst (≈150 ms at 48 kHz / ≈75 ms at
   96 kHz). The instant it lands, the box **stops broadcasting and switches to
   unicast-to-master**.
3. **Config-announce.** The box sends a CONTROL frame advertising its own input count
   (its return channel map). The master and box exchange channel-map CONTROL frames to
   agree on the slot layout.
4. **Established.** Steady state is unicast FILLER/audio to the master MAC plus a
   periodic CONTROL frame (~1/s); the master holds its broadcast at the same ~1/s
   CONTROL + ~1/s `MASTER_ANNOUNCE` cadence.

**Loss tolerance is a per-frame budget.** Once established, the link is held against a
**frame-count budget of ~600 frames**. Because a frame is one sample slot, 600 frames
is **≈150 ms at 48 kHz / ≈75 ms at 96 kHz** of tolerated silence/loss before the link
is declared dead — so doubling the sample rate halves the wall-clock tolerance, which
is why a 96 kHz link is about twice as fragile over a lossy hop as a 48 kHz one. **[S]**

**A keep-alive heartbeat re-arms the budget.** The established side emits a periodic
CONTROL heartbeat (~1/s) carrying a keep-alive selector byte; each heartbeat with the
selector set **re-arms the ~600-frame budget**. The same selector cleared latches an
explicit disconnect, and a change of the peer's source MAC also forces a disconnect.
So "connected" is maintained by *both* a steady stream of sized audio frames (the
~1000 ms no-audio cutoff) **and** the periodic heartbeat re-arm; losing either tears
the link down. **[S]**

The byte-level state machines for the split and slave paths follow.

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

The upstream return frame is unicast to the master MAC and is **smaller** than the
downstream broadcast: it carries the box's *own* input count, not the fabric's
40-channel block. At 96 kHz a **16-channel** box returns ~628 B (= ~49–52 B header +
576 B audio + trailer; 576 = 16 ch × 3 B × 12 samples) and an **8-channel** box
returns ~340 B (= header + 288 B audio + trailer; 288 = 8 ch × 3 B × 12 samples).
**Plain 24-bit LE, sample-major** — identical packing to the verified M-5000
downstream; the injected tone decodes clean reading 3 consecutive LE bytes, confirming
the obs-h8819 braid does not apply upstream.

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
