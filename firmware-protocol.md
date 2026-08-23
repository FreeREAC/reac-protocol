# The protocol as the firmware states it

`wire-format.md` describes REAC as it appears on the wire. This document describes it as the
**device firmware itself states it**: the classes the code is built out of, the messages its
receive dispatch will accept, the state machine that accepts them, and the table layouts it
reads and writes. A capture can only show what somebody happened to send. A dispatch arm is
the protocol's own inventory, and it lists messages nobody on this rig has ever sent.

Every row carries a **provenance**: the image, the function symbol, and the address. A claim
without one does not belong here.

Every row also carries a **corroboration** state, and the two are deliberately separate:

| tag | meaning |
|---|---|
| **CORROBORATED** | the firmware handles it AND the capture corpus contains it |
| **FIRMWARE-ONLY** | the firmware handles it and no capture in the corpus has ever carried it — a capability we did not know we had |
| **CORPUS-ONLY** | seen on the wire, no handler located in any image we hold |

## The images

| device | role | image | board | version | REAC control plane recovered? |
|---|---|---|---|---|---|
| S-1608 | 16-in stagebox | `S-1608.BIN`, 546688 B, SH-4 LE, image base `0x0BFE0000` | ECM42 | `s1608_sys_ver2200`, boot banner `ECM42 BOOT Ver.2.200 02/19/2010 09:30:00` | **yes — the reference box image** |
| S-4000S | 32-in stagebox | `S-4000.BIN`, 497152 B, SH-4 LE | ECM25 | `s4000_sys_ver2500`, `ECM25 BOOT Ver.2.500 01/31/2012 10:30:00` | yes |
| S-0808 | 8-in stagebox | `S-0808.BIN`, 524288 B | ECM52 | `s0808_sys_v1003`, banner `Digital Snake(S-0808) Boot Setup Menu` | **no** — the image is packed differently; it carries ZERO `C[A-Z]…` class strings against the others' 100 and 104, and no decompile exists, so nothing below is read out of it |

The image spans `0x0BFE0000`..`0x0C065780`. Addresses above that — `0x0c08xxxx` vtables,
`0x0c0cxxxx` state tables, `0x0c12xxxx` class flags — are RAM, and are only ever reached
through a pointer stored in the image.

## The names are the firmware's own

The S-1608 and S-4000S images carry a class registry in `.rodata`. Each record is 16 bytes,
and what is READ OUT of it is: word 0 is the constant `0x0c036510` on every record, word 1 is
a pointer to a plain-ASCII class name inside the image, word 2 is a distinct RAM address that
increments by one per consecutive record, and word 3 is a RAM address above the image end.
The reading of words 2 and 3 as a per-class flag byte and a vtable is INFERRED from that
shape; only the names are read. That is enough, because **the protocol's own vocabulary
survives in the binary** and nothing below needs an invented name. The S-1608 and S-4000S
sets are identical but for four AES/EBU classes only the S-4000S carries.

The records carry no resolvable base-class pointer, so the hierarchies below are INFERRED
from the names and from the records' adjacency, not read from a type descriptor.

| firmware name | registry record | name string | what it is |
|---|---|---|---|
| `CReacMsgParser` | `0x0c035474` | `0x0c033d84` | the REAC receive dispatch, base class |
| `CMasterReacMsgParser` | `0x0c035484` | `0x0c033d94` | the dispatch in MASTER role |
| `CSlave1ReacMsgParser` | `0x0c035494` | `0x0c033dac` | the dispatch in SLAVE role — the role a stagebox runs |
| `CMsgParser` | `0x0c0353d8` | `0x0c033d1c` | parser base above both |
| `CReacMsg` | `0x0c034b9c` | `0x0c032c18` | a REAC control message |
| `CReacRecMsg` | `0x0c034bac` | `0x0c032c24` | a REAC **record** message — the `op 0403` DT1 container |
| `CLinkCheckMsg` | `0x0c034f70` | `0x0c032f5c` | the link check — the heartbeat both directions carry |
| `CDevInfoMsg` | `0x0c035358` | `0x0c033ca8` | the device-info message — the box's own declaration |
| `CReacTDataMsg` | `0x0c035218` | `0x0c033b74` | transfer-data message |
| `CReacTDataKikiMsg` | `0x0c034df8` | `0x0c032e3c` | transfer-data, **kiki** (機器, "equipment") — the per-device variant |
| `CReacTDataRecMsg` | `0x0c034ea8` | `0x0c032ed4` | transfer-data carrying records |
| `CReacTDataPrgTxMsg` | `0x0c035248` | `0x0c033bac` | transfer-data carrying a **program** (firmware) transmit |
| `CReacTDataMsgOverGData` | `0x0c035258` | `0x0c033bc0` | transfer-data layered over "GData" |
| `CReacTDataRecMsgOverGData` | `0x0c035268` | `0x0c033bd8` | as above, records |
| `CReacPrgMsg` / `CReacPrgMsgIF` | `0x0c035180` / `0x0c034de8` | `0x0c033b10` / `0x0c032e2c` | REAC **program update** message and its interface |
| `CTDataParser` | `0x0c034e08` | `0x0c032e50` | transfer-data parser base |
| `CTDataKikiMsgParser` | — | `0x0c032e60` | device-variant parser |
| `CSplitTDataKikiMsgParser` | — | `0x0c032e74` | the same parser in **split** role |
| `CTDataRecMsgParser` | — | `0x0c032e90` | record parser |
| `CTDataPrgMsgParser` | — | `0x0c032ea4` | program-update parser |
| `CDataBitMap` | `0x0c034ec4` | `0x0c032ee8` | a bitmap — the per-slot present bits are one |
| `CMacAdrs` | `0x0c035028` | `0x0c0330ec` | a MAC address |
| `CMsgBase` | many | `0x0c032cc4` | message base class |

Three things follow from the names alone, before a single function is read.

**REAC has three roles, not two.** `CReacMsgParser` has exactly two subclasses in a stagebox
image — `CMasterReacMsgParser` and `CSlave1ReacMsgParser` — and the serial-side family beside
it has three: `CMasterSciMsgParser`, `CSlave1SciMsgParser`, `CSplitSciMsgParser`. `Split` is a
first-class role in the firmware's own vocabulary, and `Slave1` is numbered, which is what a
protocol that expects a `Slave2` looks like.

**A stagebox carries the MASTER parser too.** `CMasterReacMsgParser` is present in the S-1608
and S-4000S images. Whatever else that means, the master side of this protocol is not absent
from the box.

**Firmware update travels over REAC.** `CReacPrgMsg`, `CReacPrgMsgIF`, `CTDataPrgMsgParser`
and `CReacTDataPrgTxMsg` are a program-transport family, and the S-4000S boot menu spells it
out in plain text: `2. REAC Program update(XMODEM)` and `6. REAC Program update(MIDI)`. None
of it appears in any capture we hold.

Other firmware-carried strings worth having in one place: the RTOS task and mailbox names
`REAC TData Tx Task`, `REAC TD Tx MailBox`, `ADBoard Tx MailBox`, `Remote-RX Task`,
`Remote-TX Task`, `RemoteUpdate Task`, `Genarate-RX Task`, `Genarate-TX Task` (the
misspelling is the firmware's); the version probe `REAC version: ` with its failure line
`REAC version: Can't find version info.`; and the manufacturer banner `REAC - Roland ED`.

The scene body's three ASCII tags are literals in the box image as well as on the wire:
`1234` at file `0x523fc`, `SYSP` at `0x52764`, `SCEN` at `0x52df8` — which is the box side of
the three-tag gate `wire-format.md` describes.

## Corroboration — what the corpus actually carries

Counted over every `.pcap` in the FreeREAC capture corpus — 72 files, 43 018 309 frames, of
which 43 018 308 are REAC: 6 907 318 control frames and 36 110 990 FILLER. Keyed on
`(type word, op, op_len, block[4])`. Those totals are the positive control: a zero in this
table is a real zero and not a scan that could not match.

| type | op | op_len | block[4] | frames | files |
|---|---|---|---|---|---|
| `cdea` | `0100` | `001a` | `00` | 772 556 | 41 |
| `cdea` | `0101` | `0018` | `00` | 2 211 | 41 |
| `cdea` | `0102` | `000e` | `00` | 2 269 | 41 |
| `cdea` | `0103` | `0001` | `81` | 10 217 | 57 |
| `cdea` | `0103` | `000d` | `10` | 103 | 21 |
| `cdea` | `0103` | `0010` | `82` | 259 | 20 |
| `cdea` | `0103` | `0010` | `84` | 44 | 14 |
| `cdea` | `0103` | `0019` | `01` | 22 984 | 70 |
| `cdea` | `0103` | `001a` | `00` | 2 | 2 |
| `cdea` | `0401` | `001b` | `00` | 18 | 9 |
| `cdea` | `0402` | `000d` | `00` | 18 | 9 |
| `cdea` | `0403` | `0013` | `00` | 11 042 | 45 |
| `cdea` | `0403` | `0014` | `00` | 3 044 | 43 |
| `cdea` | `0403` | `0014` | `02` | 6 053 140 | 1 |
| `cdea` | `0403` | `0016` | `00` | 272 | 30 |
| `cdea` | `0403` | `001a` | `00` | 272 | 30 |
| `cfea` | `0000` | `0000` | `00` | 30 | 1 |
| `cfea` | `ffff` | `0100` | `01` | 28 837 | 69 |

Three rows are worth reading twice.

`cdea 0403 0014` with `block[4] == 0x02` — the box's constant upstream return block — is 88% of
all control traffic in the corpus and comes from ONE session. It is a single distinct 32-byte
block repeated six million times. Nothing in either box image has been shown to read it.

`cdea 0103 001a` appears twice in the whole corpus, in two `reacpw-…` captures. That is our own
master emitting an `op_len` no console sends and no page in the grammar claims.

`cfea 0000 0000` with an all-zero block appears 30 times in one capture: an announce type word
carrying no op at all.

## The control block's header

Every builder in both box images lays down the same four header fields before anything else.
EVIDENCED (image), read line for line out of `FUN_0c003398` @0c003398 — the S-1608's own
segmented upload:

```
*buf   = 1                        block[0] = the link
buf[4] = 0                        block[4] = the opcode
BE16(buf+5) = total               only on a first frame
if (total < 0x19) buf[1] = 3      it all fits: FIRST | LAST
else              buf[1] = 1      FIRST, chunk 0x18, payload at buf+7
...
if (remaining < 0x1b) buf[1] = 2  LAST,   chunk = remaining
else                  buf[1] = 0  MIDDLE, chunk 0x1a, payload at buf+5
```

| offset | width | field | what it is |
|---|---|---|---|
| block[0] | u8 | link | 1 the stagebox control link, 2 an S-4000S-only second link, 4 the record link |
| block[1] | u8 | segment | bit 0 FIRST, bit 1 LAST. 3 = a complete message in one frame |
| block[2:4] | u16 BE | length | see the base table below |
| block[4] | u8 | opcode | what the message is |
| block[31] | u8 | checksum | `-Sum(block[0..30])`, `FUN_0c007646` @0c007646 |

**So there are not seven scene-and-record ops.** `0x0101 / 0x0100 / 0x0102 / 0x0103` are one
transfer on link 1 reading FIRST / MIDDLE / LAST / SINGLE, and `0x0401 / 0x0402 / 0x0403` are the
same three states on link 4. The receive side agrees: the box's state-2 gate is
`buf[0]==1 && (buf[1] & 1) && buf[4]==0` — the FIRST bit — and its state-3 gate is
`buf[1] in {0,2}` — MIDDLE or LAST (`FUN_0c003aae` @0c003aae, `FUN_0c003b88` @0c003b88).

`block[2:4]` is a LENGTH in every case, never a selector. What varies is its base:

| family | base | check |
|---|---|---|
| link 1, opcode 0 (bulk) | this frame's payload bytes only | 0x18 = 24 = 31 − 7, 0x1a = 26 = 31 − 5 |
| link 1, any other opcode | block[4] inclusive | 0x19 = 25 = 1 + 8×3 chanmap records |
| link 4 | block[4] inclusive | 0x13 = 19 lands exactly on the SysEx `F7` |

The two bulk caps are `0x1f − 7` and `0x1f − 5`: the builders reserve block[31] for the checksum.
That closes self-consistently against `FUN_0c007646`.

This supersedes the reading of op-0103's `op_len` as a sub-page selector. Each sub-page does have
a distinct length, so switching on it happens to work; the discriminator is the opcode at
block[4] and the length is a consequence of the body.

## Message inventory

Every arm below was found in a receive dispatch or a transmit builder. `FW-ONLY` means the
firmware handles or emits it and no capture in the 72-file corpus contains one.

### Link 1 — the stagebox control link

| opcode | wire op / len | meaning | handler | state | corroboration |
|---|---|---|---|---|---|
| `0x00` | `0101 0018` FIRST | bulk transfer, first frame; declares the total at block[5:7] and carries 24 bytes | `FUN_0c003aae` @0c003aae | state 2 | 2 211 frames |
| `0x00` | `0100 001a` MIDDLE | bulk continuation, 26 bytes at block[5] | `FUN_0c003b88` @0c003b88 | state 3 | 772 556 frames |
| `0x00` | `0102 000e` LAST | bulk final; completing the transfer is what enters the commit | `FUN_0c003b88` @0c003b88 | state 3 | 2 269 frames |
| `0x01` | `0103 0019` | the slot-record window — eight `{slot, flags, value}` records | `FUN_0c002e94` @0c002e94 → `FUN_0c002d42` @0c002d42 | any | 22 984 frames |
| `0x10` | `0103 000d` | group map, ten bytes read as twelve 6-bit and ten 2-bit fields | S-4000S FSM case 3, gate at `[4]==0x10` | S-4000S state 2 | 103 frames. **The S-1608 image has no handler for it at all** |
| `0x80` | `0103 0010` | the box's declaration, alternate arm; `[7]` forced to 0 | built by `FUN_0c003c8a` @0c003c8a, parsed by `FUN_0c00350a` @0c00350a | state 4 emits, state 3 parses | **FW-ONLY** — the S-1608 emits it when `FUN_0c00f9f2` @0c00f9f2 returns 0, and no capture has one |
| `0x81` | `0103 0001` | the heartbeat reply — opcode only, zero body | built by `FUN_0c003fe2` @0c003fe2, parsed by `FUN_0c003676` @0c003676 | state 7 | 10 217 frames |
| `0x82` | `0103 0010` | the box's declaration | `FUN_0c003c8a` @0c003c8a / `FUN_0c00350a` @0c00350a | state 4 / state 3 | 259 frames, S-1608 family |
| `0x84` | `0103 0010` | the same message with the other constant | — | — | 44 frames, S-0808 and S-4000S. **No S-1608 code emits it** |
| `0x01` | — | the keepalive poll the box answers with `0x81` | `FUN_0c004026` @0c004026 | state 7 | seen as the master's `0103 0019` cadence |

The declaration is a **symmetric exchange, not a one-way announcement**: `FUN_0c003c8a` builds
exactly the message `FUN_0c00350a` parses, and the `0x82`-versus-`0x80` distinction is carried
into the device as a single boolean, `FUN_0c00f99e(buf[4] == 0x82)`.

### Link 4 — the record link

| wire op / len | segment | meaning | corroboration |
|---|---|---|---|
| `0403 0013` | SINGLE | a DT1 record that fits one frame — head-amp (tag 0x0101), box-ready (0x0302) | 11 042 |
| `0403 0014` | SINGLE | join/cold-connect state (tag 0x0100) | 3 044 |
| `0403 0016` / `0403 001a` | SINGLE | identity (tag 0x0500), 6- and 10-byte bodies | 272 each |
| `0403 0014` `[4]=0x02` | SINGLE | the box's constant upstream return block — one distinct block, repeated | 6 053 140 in ONE session. Nothing in either box image has been shown to read it |
| `0401 001b` | FIRST | the opening fragment of a DT1 record too long for one frame | 18 |
| `0402 000d` | LAST | that record's closing fragment, carrying the checksum and the `F7` | 18 |

**`0401` and `0402` are one record.** The two fragment bodies concatenate into a complete Roland
SysEx whose inner checksum closes only across both frames — 358 mod 128 = 102, and 128 − 102 =
0x1a, the byte that arrives in the second fragment. It is a TAG 0x0500 identity record carrying
the ASCII model name, and it is split for the ordinary reason: it does not fit. The grammar
models both as `record_fragment` and `reac_xcheck.py` reassembles them and checks the checksum.

### Link 2 — an S-4000S-only link, present and inert

`FUN_0c006b08` (hand-decoded; Ghidra never disassembled 0x0C006830–0x0C006FCA) dispatches on
`buf[0]`. On `buf[0]==0x02 && buf[1]==0x03` it length-checks, reads a signed BE16 at block[6:8]
and routes subtypes `0x62`, `0x63` and `0x64` to `FUN_0c004740`, `FUN_0c004746` and
`FUN_0c00474c` — all three of which are `mov r4,r2 ; rts ; nop`, **empty stubs**. So in
ver2200 these messages are parsed, validated and thrown away. `0x64` is reachable only when the
`FUN_0c00297c` predicate is false. FW-ONLY and OBSERVED-IN-DISPATCH-BUT-UNEXPLAINED.

The S-4000S image builds for this link where the S-1608 has no code for it: `FUN_0c0128b8`
@0c0128b8, `FUN_0c01291a` @0c01291a and `FUN_0c01297c` @0c01297c emit
`{2, 3, 0, 4, opcode, 0, hi, lo}`.

### Two more dispatchers on the same channel, both unexplained

`FUN_0c006b08` also takes `buf[0]==0x04` into `FUN_0c00cd26` @0c00cd26, which re-validates the
selector against a `.rodata` byte, requires `len == buf[8] + 5`, and pushes `buf[8]` bytes one at
a time from block[9] through a virtual method. And `buf[0]==0x06` into `FUN_0c014a42` @0c014a42,
which copies the whole 32-byte block, checksum included, with no field discrimination.
`FUN_0c015d56` @0c015d56 dispatches on `buf[4]` against three bytes of the same `.rodata` table.
All three: OBSERVED-IN-DISPATCH-BUT-UNEXPLAINED, and all FW-ONLY.

That `.rodata` table sits at 0x0C033AD8, immediately after the string `REAC - Roland ED`, and
reads `01 00 02 01 02 03 04 05 06` then u32 `4`, `1`, `0xFE`, `5`. Code references its individual
bytes by address rather than as immediates, which is why grepping for opcode literals finds
nothing.

## The box state machine

`FUN_0c0037ee` @0c0037ee is not a tick handler. It is the body of an RTOS task the firmware names
**`IP658 Main Task`**, which dispatches on a role selector `FUN_0c00f6b4` @0c00f6b4 (resolved from
the pool slot at 0x0c00543c) — role 0, role 1 and a third arm — and then loops
`switch(state); dly_tsk(1);` forever. **One step per millisecond.** Timeouts are counted by a
second task, `IP658 Timer Task`, which decrements once per 10 ms, so a countdown of 100 is one
second, 600 is six and 1000 is ten.

The three roles are the same three the class registry names — `CReacMsgParser` with
`CMasterReacMsgParser` and `CSlave1ReacMsgParser` beside it — and the same three the M-400
console's RTTI spells as `CReacManager` with `CMasterReacManager`, `CSlaveReacManager` and
`CSplitReacManager`. Role 1 runs the machine below.

| state | what it does | accepts | goes to | on failure |
|---|---|---|---|---|
| 0 | reset and teardown, @0c003800: disarm the countdown, enable the port; if the link-lost latch is set, take the port down, wait 2 s, fill the 6-byte identity with 0xFF (`FUN_0c003a64` @0c003a64), then clear both latches (`FUN_0c0045c4` @0c0045c4) | — | 1, unconditionally | — |
| 1 | wait for carrier, @0c003834 | — | 2 when `FUN_0c00ccf0` @0c00ccf0 reads 1; 0 if the latch is set | **no timeout** — it spins at 1 ms indefinitely |
| 2 | first bulk frame, `FUN_0c003aae` @0c003aae; resets the reassembler first | link 1, FIRST bit, opcode 0, declared total **exactly 8904**, then 24 bytes | 4 if LAST is also set, 3 otherwise | RX timeout 10 s → 0; latch → 0; any header, size or append failure → 0. No retry counter |
| 3 | continuations, `FUN_0c003b88` @0c003b88 | link 1, segment in {MIDDLE, LAST}, opcode 0, append `BE16(block[2:4])` bytes | 4 on exact completion with a LAST-marked frame | 1 s per frame and **no abort hook**, so the latch cannot break state 3; a mid-stream FIRST bit is fatal; a LAST that does not match the remaining count is fatal → 0 |
| 4 | validate and commit, `FUN_0c003c8a` @0c003c8a; the gate is `FUN_0c005be4` @0c005be4 over the three sub-blocks at +0, +0x368 and +0x37C | — | 6 if the gate passes | gate fails → 0 |
| 5 | **unreachable and empty.** `FUN_0c003fc6` @0c003fc6 is literally `return 0xFFFFFFFF;` | — | 0 | its only entry is a state-2 local that exactly one instruction in the image writes, always 0 |
| 6 | arm the watchdog, `FUN_0c003fce` @0c003fce: countdown ← 600 = 6 s | — | 7, unconditionally | — |
| 7 | **connected**, `FUN_0c004026` @0c004026 | link 1, opcode `0x01` → answer with the `0x81` heartbeat and re-arm the 6 s watchdog | stays 7 | latch → 0; opcode `0x00`, meaning the master has started a new push, **raises the latch itself** → 0; the countdown reaching 0 takes the port down, waits 2 s and refills the identity with 0xFF → 0. **Any other frame is dropped silently and does NOT re-arm the watchdog** |
| default | any state outside 0..7 | — | 0 | defensive |

The S-4000S runs the same protocol through a different shape: one 10-case switch, states 0..9,
with two states the S-1608 does not have and a tick period that is 1 ms below state 5 and 100 ms
above it. Its state 5 does real work where the S-1608's is the dead stub.

**Nothing survives a reboot.** The state cell, the reassembly buffer, the countdown and the
6-byte identity are all RAM, and the identity is refilled with 0xFF at every boot
(`FUN_0c004ff0` @0c004ff0). The one-word identity cell at 0x0c080616 reaches the save image only
in role 0: `FUN_0c0051c4` @0c0051c4 writes the shadow and fires the save flag only when
`FUN_0c00f6b4` returns 0.

### The reassembler

Buffer 0x0c0cd514, 8904 bytes; write pointer 0x0c0cd4b0; remaining counter 0x0c0cd4b4 as a u16.
`FUN_0c0039c8` @0c0039c8 resets both, `FUN_0c0039f0` @0c0039f0 copies `min(n, remaining)` and
returns whether the block fitted. It cannot overrun: a too-long block is truncated, copied, and
reported false.

The buffer's only bound is the `total == 8904` equality in state 2, and 8904 is not a magic
number — `FUN_0c002994` @0c002994 builds the box's own settings image into the same buffer out of
872 + 20 + 8010 bytes, and the flash writer writes 0x22C8. The destination base 0x0c0cd514 plus
8904 lands exactly on 0x0c0cf7dc, which is the base of the next object. The declared total fits
its allocation to the byte.

Two failure edges are worth naming because nothing else has:

- State 2 sets `remaining` from the wire **before** testing the total, so a rejected frame leaves
  it non-zero. Harmless only because every path back re-runs the reset.
- A frame carrying FIRST and LAST together with a total of 8904 takes state 2 **straight to the
  commit with 24 of 8904 bytes filled** and stale buffer behind them. Nothing in state 4 re-checks
  the remaining count. Only the master's good behaviour prevents it.

### New-master detection

`FUN_0c0045ec` @0c0045ec: if the latch is clear, read the stored identity through the pool slot at
0x0c0046bc — which resolves to `FUN_0c0051ba` @0c0051ba — and compare it against the observed
byte. On a mismatch it sets the latch, adopts the new value through 0x0c0046c4 →
`FUN_0c0051c4` @0c0051c4, and raises link-lost. It **resets nothing**; only state 0 clears the
latches, and it does so after the full two-second teardown precisely because the latch is set.

The observed byte arrives in the chanmap's `0xfe` record — see the struct layout below.

## Struct layouts

### The per-slot table

Base `DAT_0c002e70`, which resolves in the image to **0x0c0cf85a**. Stride 10 bytes, 0x50 records
long, of which only 0x00..0x2f are addressable from the wire.

| offset | width | written from | read back into | actuated by |
|---|---|---|---|---|
| +0 | u16 | scene init only | the S-4000S reports it as the record's high nibble; the S-1608 re-queries a getter instead | — |
| +2 | u16 | the record's VALUE byte, whole | the record's VALUE byte | `FUN_0c007e6a` @0c007e6a, the SENS path |
| +4 | u16 | `(flags >> 3) & 1` | flags bit 3 | `*DAT_0c008264` |
| +6 | u16 | `(flags >> 1) & 1` | flags bit 1 | **nothing** — shadowed and never passed to a setter |
| +8 | u16 | `(flags >> 2) & 1` | flags bit 2 | `PTR_FUN_0c008260` |

`FUN_0c007fbc` @0c007fbc walks a group and permutes on the way into an 8-byte actuation shadow:
`shadow[+0] ← table[+8]`, `shadow[+2] ← table[+4]`, `shadow[+4] ← table[+6]`,
`shadow[+6] ← table[+2]`. That permutation is identical in both box images.

### The chanmap record

Three bytes, `{slot, flags, value}`, built by `FUN_0c002bb2` @0c002bb2 and applied by
`FUN_0c002d42` @0c002d42:

```
rec[0] = slot
rec[1] = (cell << 4 & 0xf0)                 <- mask read out of the image at DAT_0c002d7c
       | (tbl[slot*10 + 4] & 1) << 3
       | (tbl[slot*10 + 8] & 1) << 2
       | (tbl[slot*10 + 6] & 1) << 1
rec[2] = (u8) tbl[slot*10 + 2]
```

Three record ids are not channels, and all three constants were read out of the image rather than
inferred:

| id | pool slot | value read | what the box does with it |
|---|---|---|---|
| `< 0x30` | — | — | a slot record |
| `0xfe` | `DAT_0c002d7e`, `DAT_0c002e6e` | 0x00fe | passes the FLAGS byte to `FUN_0c0051c4` @0c0051c4 — the one-word identity cell at 0x0c080616 — and to `FUN_0c004158` @0c004158, the 12-slot vector header |
| `0xff` | `DAT_0c002d80` | 0x00ff | an all-zero filler record. **FW-ONLY** — the cursor wraps at 0x30 so the branch is unreachable, and Ghidra removes it as dead code independently |

### Granularities, with the shift shown

| shift | stride | what it divides |
|---|---|---|
| `slot * 10` | 10 bytes | the per-slot table record |
| `slot >> 2` | 4 slots | one codec group; 12 groups span the 48 slots |
| `flags >> 4` | 4 bits | the inventory cell code, masked with 0xf0 |
| `flags >> 3 / >> 2 / >> 1`, each `& 1` | 1 bit | the three per-slot flags |
| `index * 0x28` | 40 bytes | four records — the commit samples every fourth |
| `i * 2`, `i < 0xc` | 2 bytes | the 12-entry u16 vector at 0x0c0cf80e |
| `i * 0x20`, wrap at 0x1f | 32 bytes | the outbound block ring at 0x0c0cfbd0, 32 entries |
| `group << 3` (S-1608) / `group * 4` (S-4000S) | 8 / 4 slots | the codec driver's group — the ONLY cardinality that differs between the two boxes |

### The ring cursor

`FUN_0c002bb2` @0c002bb2 is driven by a cursor that runs **0, 1, …, 0x2f, 0x30, then 0** — 49
indices, with 0x30 itself emitted as the `0xfe` record. The wrap test is
`if (0x30 < i + 1) *ctr = 0`. The existing note that it "rotates 0..0x2f and wraps at a 0x30
sentinel" is half right: it wraps at 0x30, but 0x30 is a record, not just a boundary. Because 49
is not a multiple of 8, consecutive frames start at 0, 8, 16, 24, 32, 40, 48, 7, 15, … and the
full cycle is 49 frames.

## What the firmware contradicts

| our previous reading | what the firmware says | where |
|---|---|---|
| Seven separate control ops | Two links and a two-bit segment field | `FUN_0c003398` @0c003398 |
| op-0103's `op_len` is a sub-page selector | It is a length; the discriminator is the opcode at block[4] | every builder; 25 = 1 + 8×3 |
| `0x0401` is "the ASCII name frame", `0x0402` is "the extra cold-connect frame" | They are the FIRST and LAST fragments of ONE DT1 record, and its checksum closes only across both | proved arithmetically from the corpus |
| The chanmap entry's third byte is padding | It is the per-slot VALUE, and it writes the cell the gain path reads | `FUN_0c002bb2` @0c002bb2, `FUN_0c007fbc` @0c007fbc |
| The `0xfe` entry is a wrap marker with a zero bank byte | Its FLAGS byte feeds the box's identity cell and its change detector, and it carries 0x00 or 0x01 in the corpus | `FUN_0c002d42` @0c002d42 → `FUN_0c0051c4` @0c0051c4 |
| The cursor rotates 0..0x2f and wraps at a 0x30 sentinel | 0x30 IS emitted, as the `0xfe` record; the ring is 49 long | `FUN_0c002bb2` @0c002bb2 |
| The chanmap's per-anchor push is "phantom, 4 ch/group" | What is pushed is the record's HIGH NIBBLE, an inventory-cell code, not a flag bit | `FUN_0c002d42` @0c002d42 |
| The master images contain no REAC control plane | The M-400 image carries `CMasterReacManager`, a `REAC.c` compilation unit, and master arbitration text | see below |
| M-400 is little-endian at base 0x08B60000 | `SuperH:BE:32:SH-2` at 0x8C000000, and the pointer at 0x8c0cc45c only resolves big-endian | `M-400_run.log` |
| The 0x000d group map is five input-group bytes front-packed and five output-group bytes back-packed | The one firmware that parses it reads ten bytes as TWO PACKED FIELDS — low six bits once per pair of groups, top two bits once per byte with 2 and 3 folded to −1 | S-4000S, the arm gated on `[4]==0x10` |
| `FUN_0c0045de` is the link-lost poll | Its whole body is `return *0x0c080608;` — a getter for a latch that other code raises | `FUN_0c0045de` @0c0045de |
| `FUN_0c003a64` zeroes the six-byte identity | It fills it with **0xFF** (`DAT_0c003b82` = 0x00ff, read out of the image). An all-zero identity and an all-0xFF one are different wire facts | `FUN_0c003a64` @0c003a64 |

## The master side

The claim that the console images hold no REAC control plane was made about a partial look and it
is wrong. Three of the four master exports are ~97% unrecovered — M-480, M-300 and M-200i
exported 281, 262 and 272 functions where M-400 exported 8 561 — which is why the searches came
back empty.

M-400 carries it. Its RTTI decodes cleanly to `CReacManager` with `CMasterReacManager`
(typeinfo 0x8c45ae94, vtable 0x8c45adfc), `CSlaveReacManager` and `CSplitReacManager` — the
**three roles**, one manager class each, matching the box images' three-way parser split. Per-port
task classes confirm **two REAC ports, A and B**: `CReacATxTask` / `CReacBTxTask`,
`CReacARxTask` / `CReacBRxTask`. There is a compilation unit literally named `REAC.c`, and
`FUN_8c0cbc98` prints `REAC %c's master is running on %skHz.` followed by
`Do you want to set the sampling frequency to %skHz?.` — a console detecting a foreign master on
a port and offering to match its rate.

Two constraints are checkable against the committed export:

- **The rate table has four entries.** `FUN_8c0cbf70` indexes it with `(param & 3) * 4`, and it
  accepts **only indices 0 and 2** — the other two take a `Wrong sampling frequency` path.
- **The device table has eighteen entries, 0..0x11, with 0x12 as the not-found sentinel**
  (`FUN_8c0ccfe2` @8c0ccfe2). `FUN_8c0ccecc` @8c0ccecc partitions those ids three ways:
  0..5 keep their own id as a device class; {6, 7, 10, 11, 15} take class 0; {8, 9, 12, 13, 14, 16}
  take class 4; 17 takes class 0 with no name; anything else takes 0xff. Names are a 16-byte field
  (`FUN_8c0cce0c` @8c0cce0c copies 0x10 bytes) — the same width as the string `REAC - Roland ED`.

**The id-to-name binding is NOT reproducible from anything committed.** It was read from
`sec_0006003c_code.bin`, the unpacked RSFF section Ghidra loaded, which lives outside the
repository; `M-400.PRG` is packed and contains none of the strings. The partition above and both
cardinalities are checkable; the eighteen names are not, so they are not written down here and
they are not in `protocol-facts.yaml`. Committing that section binary, or an extracted table
fixture, is what would close it.

No site in the recovered 5.8 MB writes a table index into a message buffer or compares one against
a received byte, so this is a console-side identity table and not a wire field. One caveat bounds
that negative: all nine `CMasterReacManager` virtual functions are absent from the export — they
are reached only through vtable dispatch, so recursive-descent analysis never created them — and
one caller of the model-id setter falls inside exactly one of those holes. The message-building
path is the code that could not be searched.

## Method, and one trap worth passing on

The obvious discriminators do not work. `0x8819`, the `C2 EA` end marker and every frame length
return **zero hits in the S-1608 image**, which is known-good. The reason is structural:
`FUN_0c007646` @0c007646 packs the 32-byte block into 16-bit words and writes them to a single
memory-mapped register, then sets a trigger. Ethertype, end marker and frame length are applied by
the FPGA and appear in no firmware image, box or console. A search for them cannot distinguish a
console with no REAC code from a console with all of it.

Every absence claim in this document was made only after the same search found a known-present
control. The scan that located the undocumented dispatchers first used a wrong instruction mask
and returned zero hits — indistinguishable from "there is nothing there" — and was re-run against
the known site at 0x0C002EB2 until it reported presence before any absence was believed.


## How this was validated

The grammar is not a description here; it is a parser, and it was run.

- **214 524 whole frames** — not control windows, entire frames including the audio region and
  the end marker — from **all 72 captures** in the FreeREAC corpus, parsed by the
  `kaitai-struct-compiler` output of `spec/reac.ksy` with **zero failures**. All four frame
  widths appear (1492, 1204, 628, 340) and all eight `ctrl_kind` values are exercised.
- **423 distinct control blocks**, the complete set of distinct `frame[16:50]` windows in the
  corpus, parsed with zero failures, with every new instance forced.
- The harness carries a **negative control** in the same run: a truncated non-REAC buffer must
  be rejected, and a corrupted DT1 wrapper must be rejected. Both are.
- `spec/reac_xcheck.py` and `spec/facts_xcheck.py` go from 277 to **328 assertions**, and the
  new ones were **sabotage-verified**: swapping the FIRST bit for the LAST bit in the grammar
  turns four tests red, shortening the DT1 checksum span by one byte turns the reassembly test
  red, and changing the ring length from 49 to 50 turns the derived-fact ratchet red.

One trap the corpus set for the harness, worth passing on. Several of these captures were taken
with a snaplen — 64, 128, 200 and 400 bytes — and a truncated frame's length can land on
`52 + 36n` by coincidence. Reading `caplen` without `origlen` therefore produced 3 200 apparent
grammar failures that were nothing of the kind. The scan compares the two and skips 3 327 846
truncated records; every remaining frame parses.
