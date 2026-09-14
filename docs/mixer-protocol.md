# The REAC mixer protocol

How a Roland V-Mixer / M-series console (the master) and a stagebox (the box) talk to
each other over REAC, and when — the protocol as the master side needs it: what a
console sends, in what order, and what a box does in reply. The full field-by-field
grammar is [`spec/reac.ksy`](../spec/reac.ksy); this is its narrative companion,
restricted to the control plane. For the audio region's own byte layout see
[wire-format.md](../wire-format.md).

## 1. The frame and the cadence

Every REAC frame, either direction, has the same shape: a 14-byte Ethernet header, a
2-byte free-running frame counter, a 2-byte type word, a 32-byte control block, an
audio region sized to the sender's channel count, and a 2-byte end marker
(`0xC2 0xEA`). So a frame is `52 + n_channels * 36` bytes, where 36 is 12 samples of a
3-byte sample, per channel.

The master's downstream broadcast always carries 40 channels — the whole audio
fabric — regardless of how many boxes are attached or how wide they are: 1492 bytes.
A box's upstream return is sized to its own declared input width: 340 bytes for an
8-input box, 628 for 16, 1204 for 32.

The audio region is rate-invariant: it always holds 12 time samples per frame, at
every sample rate. What changes with rate is the frame RATE itself — REAC carries the
sample rate in how often it sends a frame, never in the frame's contents:

| sample rate | frames per second |
|---|---|
| 44.1 kHz | 3675 |
| 48 kHz | 4000 |
| 96 kHz | 8000 |

The 2-byte counter at offset 14 is little-endian — the one little-endian field in an
otherwise big-endian frame — free-running, and increments on every frame including a
lost one, which makes it a drop-immune loss and rate reference and lets a receiver
recognise a mirrored duplicate (two frames sharing one counter value).

Some capture paths append two extra bytes after the end marker. They are the low 16
bits of the frame's own Ethernet FCS, left behind by a mirroring capture rig; they
carry no protocol meaning, are not part of any REAC field, and a conforming sender
never emits them.

## 2. Roles

A REAC segment has exactly one master and one or more boxes slaved to it. Which
physical device holds which role is not always "console = master, box = slave" — a
box can master its own segment (§9) — but a segment never has two masters, and a
frame's own LENGTH is a stronger tell than its control block: the master's downstream
is always the 40-channel, 1492-byte solution, and a box's upstream is its own
declared width. A device broadcasting a box-sized frame is a box whatever its
control frames claim.

The master announces a pace code once a second in its `cf ea` announce (§3): a
single byte reading 0x00 for 48 kHz, 0x01 for 96 kHz, or 0x02 for 44.1 kHz. A box
follows this byte, but how strictly is firmware-dependent — one box family tracks the
byte alone, another will not move until the scene transfer's own rate field agrees
with it too (see §7's `revision` field, which is where a box's rate class actually
settles, not the announce).

## 3. The master's downstream

Once linked, a master emits, continuously, in both the unlinked (hunting) and linked
states:

- **The `cf ea` announce**, about once a second. Its payload carries the console's own
  MAC (repeated inside the payload — an emulator must never reuse a real desk's MAC
  here, since doing so impersonates that desk), the total audio-fabric width (0x28 =
  40, on every console), the linked box's input width, the pace code (§2), and an
  enrolled-box count that reads 0x0000 idle and steps to 0x0001 once a box is
  granted. A console that grants a box but leaves this count at zero leaves the box's
  own status light blinking rather than solid.
- **The channel-map sweep**, about once a second for a full rotation: 49 windows, each
  advertising 8 consecutive positions of a ring that spans the 48-slot head-amp
  channel space (0x00..0x2f) plus a trailing section-marker position. This is NOT the
  40-slot audio fabric — it is the head-amp/chanmap space, a different and wider
  numbering (see §6).
- **Filler**, on every slot none of the above occupies: a frame whose type word is
  0x0000, carrying nothing in its control block and exempt from the control-block
  checksum, so the pacer has somewhere to put audio when there is no control message
  due.

Two further messages are event-driven rather than continuous: the enrolment
prepare-frame and the grant sweep, both covered in §4.

## 4. Enrolment

A box's arrival on a segment is not a special case handled once at startup — it is
the same sequence whether the box is cold-booting or reconnecting after a cable pull,
and the box drives it; the master does not have to provoke it.

**The box's side, in order:**

1. **Flood.** On PHY link-up the box broadcasts FILLER at the wire rate to announce
   its presence — bounded, lasting on the order of a second, then it stops
   broadcasting and goes unicast-only. A box joining a master that already announces
   itself may skip straight to the next step; the flood is how a box finds a master
   that is silent.
2. **Cold-connect.** The box unicasts a short burst of `cd ea 04 03` DT1 records to
   the master on a retry grid, interleaved with unicast audio filler, until granted.
   The records declare the box's own join state (tag 0x0100) and readiness (tag
   0x0302).
3. **Config-announce.** The box sends its own inventory declaration, once — op
   `01 03`, page 0x10. This is the box's state-4 commit report, not a greeting: on a
   box running a scene FSM it fires only once its own scene commit has completed
   (§7), so it lands at the END of the exchange that provisions it, not the start of
   the session. Its payload names twelve 4-channel inventory cells (`output`,
   `analog_input`, or `absent`) that give the box's declared input and output width.
4. **Heartbeat.** The box's own ~1 Hz `01 03 0001` heartbeat begins on the very next
   frame after its join burst — before the grant has landed.

**The master answers each distinct cold-connect record it receives with its own `cd ea
04 03` record: an echo of the box's record, plus a head-mark record (tag 0x0000) of
its own.** This is a pure per-record relay, one echo per distinct record, and the
master does not wait to have seen every record before answering the first. That echo,
taken together, is the grant.

Two further downstream messages complete a box's provisioning:

- **The enrolment prepare-frame**, op `01 03` page 0x000d, sent once ahead of the
  grant sweep. Its payload is a pure function of the box's declared width: up to five
  8-channel groups, input groups marked front-packed and non-input (output) groups
  marked back-packed, spanning the 40-slot audio fabric. A box that never receives
  this frame can still be placed — several real desks omit it for some box models —
  but where it is sent, the box needs it to arm itself for the grant that follows; a
  box that never sees it can stream but never reach its own established heartbeat.
- **The grant sweep**, the master's structured per-channel enrolment burst
  immediately after the join exchange: one contiguous pass over every allocated
  head-amp channel with real phantom/pad/sensitivity values (see §6), plus a fixed
  six-record block that is byte-identical regardless of the box's width. Sweep length
  is `8 + width * 3` control frames — 32 for an 8-input box, 56 for 16, 104 for 32.

**Establishment states, named as the reference implementation names them** (the
master and the box run mirror-image state machines — the same lifecycle, roles
swapped):

```
 MASTER                              BOX
 ────────────────────────────────────────────────────────
 IDLE                                PHY_DOWN
   |                                   | (link up)
 PROBING  <───────────────────────  FLOOD_ANNOUNCE
   | (validated join received)        | (flood ends)
 GRANTING ────── grant echoed ────>  COLDCONNECT
   | (grant fully delivered)          | (grant received)
 ESTABLISHED <── box heartbeat ───  TX_MUTE
   |                                  | (settle dwell elapses)
   |                                ESTABLISHED
```

**Established** means: the box unicasts continuous audio plus its ~1 Hz heartbeat; the
master continues its full downstream cadence (announce, chanmap, and the master's own
periodic heartbeat page) and, on the box side, treats the box's own heartbeat's
arrival as definitive confirmation the box is locked. Both sides hold this state
behind a link-check budget that reloads on every frame received from the peer, so a
momentary glitch does not tear the link down.

What drops it, on the master's side: the peer's link-check budget draining with
nothing received (peer gone), an explicit disconnect — the box's own heartbeat
carrying a zero selector instead of its usual established one (BYE) — a join arriving
from a different MAC than the one currently latched (MAC change, which re-grants the
new box), a grant window expiring with no box unicast ever arriving (grant timeout),
or a box that latched onto the segment but never sent a config-announce, leaving
nothing to enrol it from (box unknown). On the box's side the same shape holds in
reverse: an explicit drop, the peer going silent past its own link-check budget, or
the peer's own MAC changing underneath it.

## 5. The box's upstream

Once established, the box unicasts continuously to the master's learned MAC address
— never broadcast — at its own declared width: 8, 16 or 32 channels, in frames of
340, 628 or 1204 bytes respectively. Riding the same unicast stream is the box's own
~1 Hz heartbeat, `01 03 0001` with an established-state selector — the signal the
master reads as "I am locked," symmetric to what a box waits for from a real master
during its own establishment.

## 6. Head-amp control

A head-amp record is the console's preamp command: a Roland DT1 (Data Set 1) SysEx
record, `{CH, PARAM, VALUE}`, wrapped in a DT1 container (op `04 03`) under DT1 tag
0x0101. The wrapper carries the usual Roland envelope — `F0 41 0a`, the model ID,
the DT1 command byte, the tag, the record, an inner checksum such that
`Sum(tag..checksum) mod 256 == 0x80`, and `F7` — and the outer 32-byte control block
carries the usual sum-to-zero block checksum around it.

**The three parameters, one wire channel per record, one record per parameter:**

| param | meaning | value |
|---|---|---|
| 0x00 | phantom (+48 V) | 0 or 1 |
| 0x01 | pad (−20 dB) | 0 or 1 |
| 0x02 | sensitivity | 0x00..0x37, a flat 1 dB per step |

The sensitivity law is `sensitivity_dBu = -10 - value + (pad ? 20 : 0)`: 56 steps,
−10 dBu at step 0 down to −65 dBu at step 0x37 with the pad off, the pad shifting the
whole travel up by 20 dB. This is a sensitivity — the input level that reaches full
scale — not a gain, so it runs the opposite way from a gain control: the hottest
setting is the most negative number.

**The wire channel (`CH`) is not a console channel strip and not an audio-fabric
slot.** It is `base + (box_input - 1)`, addressed in the head-amp/chanmap
space — 48 wide, 0x00..0x2f — which is a different, wider numbering than the 40-slot
audio fabric a downstream frame actually carries. The base is the box's own
config-announce `block[7]` × 0x10 — a GPIO chassis strap the box reads before its
RTOS starts and announces, not session state a master negotiates: an S-0808 or an
S-4000S straps 0x00, an S-1608 straps 0x02 (base 0x20).

**Each change is one record, sent on the transient.** A single write of an absolute
value self-commits — there is no separate commit message, and no acknowledgement
record on the wire. A record must be sent AFTER the box's scene commit (§7), never
before: the scene commit overwrites the box's whole active head-amp table in one
pass, so a head-amp record sent ahead of it is silently erased — the bytes are
right, the checksums are right, and the value is simply gone.

**Head-amp is write-only.** A box never re-broadcasts its own head-amp state, to the
master or to anyone else, so there is no readback and nothing to query and compare
against on this page. The only mechanism that restores a box's head-amp state after
it drops off the segment — a power cycle included — is a full re-push: one
contiguous pass over every allocated channel, all three parameters, real values, sent
once immediately after establishment (about 24 records for an 8-input box, 48 for 16,
96 for 32). No bank structure and no split sweep: one pass, in order, over the box's
whole declared width.

## 7. Scene transfer and the chanmap

**The scene transfer** is the master's periodic push of the box's whole
configuration — an 8904-byte body — split across three record types: a header (op
`01 01`) declaring the total length and carrying the body's first 24 bytes, a run of
continuation chunks (op `01 00`, 26 bytes of body each), and a final chunk (op
`01 02`, the last 14 bytes). The whole transfer repeats at a steady interval until the
box's own config-announce shows it landed — a retry on a bounded transfer, not a
free-running cadence — and a box joining mid-transfer does not cancel it.

The body's fields are little-endian, against the frame's big-endian everywhere else.
Three 4-byte tags gate the box's commit — an opening magic, and two further tags
deep in the body — and failing any one of them means the box promotes nothing and
replies nothing, while the transfer still looks complete on the wire. Passing the
three tags is enough for the box to commit even where the rest of the body is wrong,
so the unchecked bytes are not free to get wrong either: they are read and acted on,
just not validated. Among the fields the box reads is `revision` — the same pace
code as the `cf ea` byte (0x00 at 48 kHz, 0x01 at 96 kHz, 0x02 at 44.1 kHz) — which
is what actually settles a box's rate-class expectation; the `cf ea` pace code (§2)
only proposes a rate, and a box whose firmware insists on agreement holds its prior
rate until `revision` matches.

The commit also has a real consequence for placement and for head-amp: it writes the
same values into all eighty of the box's head-amp table slots in one pass, so a scene
body cannot address an individual channel's head-amp state — only an op-0403 record
can (§6) — and it is why a head-amp record must follow the commit rather than precede
it.

**The box's config-announce** (§4, op `01 03` page 0x10) is what the master enrols the
box from. Its payload declares twelve 4-channel inventory cells — `output`,
`analog_input`, or `absent` — which sum to the box's declared input and output
widths, plus a selector byte and a board-configuration byte that correlate with the
box's model family without being a model ID in the strict sense.

**The chanmap sweep** (§3, op `01 03` page 0x0019) advertises the master's 48-slot
head-amp/chanmap space, 8 positions per frame, a full rotation every 49 frames at
about 1 Hz. Each 3-byte entry is `{slot, flags, value}`; the value byte shares the
same sensitivity axis as an op-0403 head-amp record's `sens` parameter, but no real
console has ever been observed writing a non-zero value there — the field exists in
every box's firmware and nothing on the wire exercises it.

## 8. Trunk VLANs

REAC frames carry no VLAN awareness of their own — the frame's ethertype sits
directly at offset 12, and a VLAN tag, where one is present, sits four bytes earlier
and shifts every offset in this document by four. A trunk link multiplexing several
REAC segments does so by tagging each segment's frames with a distinct 802.1Q VLAN
ID: one segment per tag, each with its own master, its own boxes, and its own
independent run of the whole protocol above. A device serving a trunk strips the tag
before reading the frame and keeps each VID's traffic as a wholly separate segment —
nothing about establishment, enrolment or head-amp control changes per VLAN; the tag
only selects which segment a frame belongs to.

## 9. A stagebox on M

A stagebox's REAC-mode switch — S / SP / M — is read once, at boot, and never again;
moving it on a running box changes nothing until the next power cycle. S is the
ordinary case: the box enrols with whatever masters the segment, as described above.

On M, the box masters its own segment rather than behaving as a slave — but it is
not a console. It runs no probe cycle of its own — one box family announces a
`cf ea` about once a second, another announces nothing at all — and when a slave
finds it and sends its own cold-connect burst, the box on M answers exactly as a
desk does: it echoes each distinct record the joining box sent, plus its own
head-mark record, and that echo is the grant. A box on M can therefore be joined by
a slave, but it can never itself be enrolled by a console, since it never runs the
cold-connect side of the exchange.

A box on M holds no rate field of its own and has no rate switch. An S-1608 in M
mode paces 96 kHz: measured after it had run at 48 kHz as a desk's slave, and again
after a power cycle, so its master-mode rate is not the rate it was last slaved at. A box with an uplink instead re-drives the clock it recovers from that
uplink out through its own outputs — clock-slave on the uplink side, master on the
output side — the mechanism the SP (split) position exists for: one box's I/O
shared between two consoles.

A box on M sends no head-amp sweep, no identity requests and no group map to a slave
that joins it: the whole grant is the three records the slave declared, echoed back
(`box-to-box-2026-09-13`, an S-1608 on M enrolling an S-4000S twice, against 56 or
104 records from a console enrolling the same boxes). That is the purpose of the M
position: the box runs a segment on its own with no console on it, and its head-amps
are configured out of band, through the box's serial port by Roland's remote-control
software, while any program on the wire takes the audio as it is. Head-amp control
over a box on M does not exist on the REAC wire, so a surface shows those controls as
unavailable, never as broken.

## 10. Control-block kinds, by their two-byte tags

The type word at frame offset 16 selects the top-level frame kind:

| type word | kind |
|---|---|
| 0x0000 | FILLER — audio, no control payload, checksum-exempt |
| 0xcdea | CONTROL — the control multiplex below |
| 0xcfea | ANNOUNCE — the master's periodic announce (§3) |

Under CONTROL, the two-byte op selects the record:

| op | name | carries |
|---|---|---|
| 0x0100 | scene_chunk | a scene-transfer continuation chunk (§7) |
| 0x0101 | scene_header | the scene transfer's first frame, declares the total (§7) |
| 0x0102 | scene_final | the scene transfer's last chunk (§7) |
| 0x0103 | page_0103 | a single-frame page, further dispatched on a subtype byte |
| 0x0401 | dt1_first_fragment | the first half of a split DT1 record |
| 0x0402 | dt1_last_fragment | the second half of a split DT1 record |
| 0x0403 | dt1_container | a DT1 record — join/grant tags, head-amp, or the box's own upstream marker |
| 0xffff | announce | the master's `cf ea` page |

`page_0103`'s own subtype byte selects among:

| subtype | page |
|---|---|
| 0x00 | the scene-transfer ops above (link class, not this subtype directly) |
| 0x01 | chanmap sweep (§7) |
| 0x10 | the enrolment prepare-frame / group map (§4) |
| 0x80 / 0x82 / 0x83 / 0x84 | the box's config-announce / commit report (§4, §7), selector varies by model family |
| 0x81 | the box's own ~1 Hz heartbeat (§5) |

A `dt1_container` (op 0x0403) carries a Roland DT1 record whose TAG selects the
register page:

| tag | page | carries |
|---|---|---|
| 0x0000 | head_mark | the master's own record in a join exchange (§4) |
| 0x0100 | join_grant | the box's join declaration, echoed by the master as its grant (§4) |
| 0x0101 | head_amp | `{CH, PARAM, VALUE}` — a preamp command (§6) |
| 0x0302 | box_ready | the box's readiness declaration in a join burst (§4) |
| 0x0500 | identity | an addressed poll/reply — firmware version, model name, REAC protocol version |

And a head-amp record's own PARAM byte:

| param | control |
|---|---|
| 0x00 | phantom (+48 V) |
| 0x01 | pad (−20 dB) |
| 0x02 | sensitivity step |

---

Provenance: these facts were verified against real Roland M-200 and M-5000 consoles
and real S-0808, S-1608 and S-4000S stageboxes.
