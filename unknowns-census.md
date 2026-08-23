# What we do not know about REAC — a census

Status: census, 2026-08-23. Companion to [wire-format.md](wire-format.md),
[firmware-findings.md](firmware-findings.md) and [spec/reac.ksy](spec/reac.ksy).

This file is the honest other half of the spec. The grammar and the facts schema record what
we know; this records what we do not, and — the column that makes an unknown into a task —
what evidence would settle each one.

Two kinds of debt are kept apart throughout, because mixing them is what makes a status
report useless:

- **[IS?]** we do not know what this **is**. A semantic gap. Only evidence closes it.
- **[IMPL]** we know what it is and have **not built or measured** it. An engineering gap.
  No new evidence is needed, only work.

## How the numbers here were obtained

Every frame count, source-MAC count and file count below comes from one offline pass over
the pcap corpus: 72 files under `reac-captures/`, read directly from the pcap records with
no capture tooling in the loop, capped at 250 MB per file (the four multi-gigabyte
head-amp sessions are therefore sampled, not exhausted). Nothing was transmitted, no rig
was touched, and reac-pw was not run.

Where this file says a thing is absent, a control that matches was run in the same pass and
is named. An absence from a probe that has not been shown to detect presence is not
recorded here as a finding.

## 1. The opcode table — the three-way split

Every `(op, op_len, payload[0])` triple observed across the corpus, with the number of
frames, the number of files, and the number of distinct source MACs. `payload[0]` is
`block[4]`, the byte the grammar dispatches sub-types on.

### (a) Understood and implemented

| op | op_len | pl[0] | frames | files | srcs | what it is |
|---|---|---|---|---|---|---|
| `0100` | `001a` | `00` | 252443 | 37 | 5 | scene continuation chunk — `reac.ksy:467` |
| `0101` | `0018` | `00` | 723 | 37 | 5 | scene header, declares 8904 — `reac.ksy:497` |
| `0102` | `000e` | `00` | 741 | 37 | 5 | scene final, gates the commit — `reac.ksy:530` |
| `0103` | `0019` | `01` | 15374 | 70 | 8 | chanmap, the master heartbeat — `reac.ksy:863` |
| `0103` | `0001` | `81` | 7127 | 57 | 5 | box heartbeat — `reac.ksy:860` |
| `0103` | `000d` | `10` | 63 | 19 | 5 | enroll group map — `reac.ksy:1001` |
| `0103` | `0010` | `82`/`84` | 18 / 26 | 17 / 12 | 2 / 3 | box config-announce — `reac.ksy:936` |
| `0403` | `0013` cmd `12` tag `0101` | `00` | 3759 | 31 | — | head-amp record — `reac.ksy:1177` |
| `0403` | `0014` tag `0100` | `00` | 2589 | 35 | — | join grant — `reac.ksy:1093` |
| `ffff` | `0100` | `01` | 16884 | 69 | 8 | master announce, `cf ea` — `reac.ksy:432` |

### (b) Observed but not understood

| op | op_len | pl[0] | frames | files | srcs | what we know, and what is missing |
|---|---|---|---|---|---|---|
| `0403` | `0014` | `02` | 197927 | **1** | **1** | the box's upstream return block. One distinct 32-byte value, valid checksum, and its interior is unexplained — `reac.ksy:1072`. See §3.1. **[IS?]** |
| `0403` | `0013` cmd `11` tag `0500` | `00` | 594 | 31 | — | identity request. `reg_page::identity` is named in the enum at `reac.ksy:1336` and has **no `data` case** in `dt1_record` — the payload is unparsed. **[IS?]** |
| `0403` | `0013` cmd `12` tag `0500` | `00` | 7 | 6 | — | identity write. Same gap. **[IS?]** |
| `0403` | `0016` tag `0500` | `00` | 36 | 25 | 5 | cold-connect step 3. Three distinct blocks corpus-wide, one per box model. Carried as an opaque per-model template in `libreac/include/reac/reac_ctrlblk.h:249-255`. **[IS?]** |
| `0403` | `001a` tag `0500` | `00` | 36 | 25 | 5 | cold-connect step 4. Same. **[IS?]** |
| `0403` | `0014` cmd `12` tag `0000` | `00` | 126 | 31 | — | `reg_page::head_mark`. Named in the enum, no doc, no `data` case. **[IS?]** |
| `0403` | `0013` cmd `12` tag `0302` | `00` | 28 | 25 | — | `reg_page::box_ready`. Named in the enum, no doc, no `data` case. **[IS?]** |
| `0401` | `001b` | `00` | 16 | 7 | **1** | the ASCII name frame. Deliberately unmodelled — `reac.ksy:424`. See §3.2. **[IS?]** |
| `0402` | `000d` | `00` | 16 | 7 | **1** | extra cold-connect. One distinct block ever, and it is **not** a DT1: `00 02 00 fe 08 00 00 00 00 00 00 1a f7` has no `F0` SysEx opener. Carried as `has_extra` in `libreac/include/reac/reac_ctrlblk.h:256-257`. **[IS?]** |
| `0000` | `0000` | `00` | 30 | **1** | **1** | a `cf ea` master announce with an **all-zero** 32-byte block, broadcast by the M-5000 on 1492/1494-byte downstream frames. `cfea_payload` opens with `contents: [0x01,0x03,0x0d,0x01,0x04]` (`reac.ksy:433-441`), so **the grammar cannot parse these thirty real frames**. An all-zero block also sums to zero, so the checksum "passes". **[IS?]** |

### (c) Known from firmware or an inherited source, never observed on the wire

| what | where it is claimed | corpus evidence |
|---|---|---|
| type word `ce ea` SPLIT_ANNOUNCE | `reac-tools/wireshark/reac.lua:56`; `wire-format.md:102-104` | **zero frames.** The only type words in 9.6M frames across 72 files are `0000`, `cdea`, `cfea`. Needs a real split device. **[IS?]** |
| type word `c2 ea` as a *frame type* | `wire-format.md:102-104` | zero. Only ever seen as the two-byte end marker. **[IS?]** |
| split-assignment `data[6]=0x0a`, `data[16]=0x60` | `wire-format.md:725-727` | inherited from the third-party driver, including its author's "0x04 and up seems to be fine". `0x0d` is ours and confirmed; `0x0a` is not observed anywhere. **[IS?]** |
| ASCII tag `XVSCEN` in control frames | `wire-format.md:186` | **zero.** See §4.2 — probe proven live. **[IS?]** |
| `c0 a8` (192.168) prefix stuffed into `data[]` | `wire-format.md:186`, `wire-format.md:731-732` | **zero.** See §4.2. **[IS?]** |
| box slot categories above `0x2f` (firmware reaches `0x4e`+) | `devices/S-1608/decompile/S-1608_alldecomp.c:26903,26922,26940` | no frame has ever carried a slot above `0x2f`. Dead code, or a space we have never provoked. **[IS?]** |
| scene-FSM state 3 accepting `buf[1]==0` | `reac-firmware-re/FIRMWARE-INDEX.md:38` | the wire only ever feeds it op `0102`. The `buf[1]==0` arm has no wire instance. **[IS?]** |
| ops `0104` / `0105` / `0106` | present as 16-bit constants in `S-1608_alldecomp.c` | never on the wire, and never confirmed to be opcodes at all. Low confidence, cheap to check. **[IS?]** |

**One anomaly is ours, not the protocol's.** `0103` with `op_len 001a` appears twice, in two
files, from one source MAC — `00:40:ab:00:00:01`, a synthetic address. Both files are
`reacpw-none-96k-clean__s1608-master-*`, i.e. our own master. This is a reac-pw defect, not
a REAC unknown, and it is listed here only so nobody chases it as one.

## 2. The `reac.ksy` unknown fields, broken apart

"Unknown" in the grammar covers three different situations. Separating them is the point of
this section.

### Constant everywhere — a magic or a version we have not named

| field | where | what we know | what would settle it |
|---|---|---|---|
| `unknown_0a`, 10 bytes at scene `+0x0a` | `reac.ksy:663` | `01 80 02 00 01 00 01 00 01 00` on every desk seen. **No reader located in either firmware image.** | Resolve the staging-buffer pointer arithmetic at `+0x0a` in the S-1608 image the way the bank pointers were resolved. If still no reader, promote it to "copied, never read" and stop calling it unknown. **[IS?]** |
| `map_a_arg` = `0x0004` | `reac.ksy:654`, `protocol-facts.yaml:569-574` | the commit reads it, both switch arms call the same setter, and it is `0x0004` on every capture. **What it selects is unresolved.** | Emit a scene with `map_a_arg` altered against a bench box and read back its config-announce. One frame, one box. **[IS?]** |
| `reserved_06` (2 B), `reserved_16` (4 B), `reserved_33a` (6 B), `reserved_346` (4 B), `reserved_350` (4 B) | `reac.ksy:652,675,694,703,709` | zero on every capture, no reader located | the same 128-byte-window zeroing trace that found the three tags, run at 8-byte granularity over these five runs. **[IS?]** |
| `scene_record.field_2 / _6 / _8` | `reac.ksy:755,760,762` | all records in all captures read `(cell, 0, 1, 0, 0)`; the commit copies `+2/+4/+6/+8` and pointedly not `+0` | a body with a non-constant `field_2` sent to a bench box, then read its config-announce back. **[IS?]** |
| `scene_sysp.rest` (11 B), `scene_scen.trailer` (4 B) | `reac.ksy:782,813` | the box compares only `key` and `flag` of SYSP; the rest is copied | as above. **[IS?]** |

### Varies with something, and we know with what

| field | where | what it varies with | status |
|---|---|---|---|
| `config_announce_page.selector` | `reac.ksy:955` | model family: `0x82` on both S-1608 units, `0x84` on the S-0808 **and** the S-4000S. Measured this pass: 18 frames / 2 MACs at `0x82`, 26 frames / 3 MACs at `0x84`. | the *family* is settled; **what distinguishes an S-0808 from an S-4000S inside family `0x84` is not** — see §3.2. **[IS?]** |
| `cfea_payload.console_field` | `reac.ksy:456` | `0x00` on the M-200i and M-300, `0x01` on the M-5000 | **confounded.** Every desk we own runs exactly one rate: the two V-Mixers are 48 k only, the M-5000 is 96 k only. "Generation" and "rate class" predict the whole corpus identically. `reac-captures/CAPTURE-PLAN-next.md:19`. **[IS?]** |
| the head-amp fabric BASE | `reac.ksy:1218`, `protocol-facts.yaml:755-780` | declared width — 8→`0x00`, 16→`0x20`, 32→`0x00` | **three carriers are perfectly collinear** across 42 establishments: declared width, `selector`, and `unit_offset`. `wire-format.md:465-469` names the experiment: a box declaring a width whose selector or `unit_offset` breaks the collinearity. **[IS?]** |
| `join_grant_data` climbing `0x01`→`0x09` | `reac.ksy:1093` | the establishment's progress | what advances it is unresolved; the "probe rotation" reading it was attributed to has been refuted. **[IS?]** |

### Genuinely unread, and honest about it

`peer_id_1` and `peer_id_2` (`reac.ksy:705,711`) are `ff:ff:ff:ff:ff:ff` on every capture and
the grammar says INFERRED "from position and shape alone — no reader located". `map_b`
(`reac.ksy:714`) is all zero and its length is bounded only by the next named field, so its
shape is inferred too. These three are the grammar's cleanest admissions and need no
correction — only a multi-box establishment capture, which the corpus effectively lacks.

**The `page_0103` subtype `0x80` arm.** `reac.ksy:833` records that the box's report builder
has a `0x80` arm and that "what selects it is UNEXPLAINED". No frame in the corpus carries
`payload[0] == 0x80` for any op. **[IS?]** — decompile the report builder's caller.

## 3. Facts resting on one capture or one unit

A fact established on exactly one unit is a fact with an unstated dependency: that unit's
firmware build, its serial era, its configuration. These are the ones where the dependency
is load-bearing.

### 3.1 The commonest control block on the wire has one source, and the attribution is wrong

`reac.ksy:1072-1091` documents `box_return_block` — op `0403` subtype `0x02` — as
"6,053,140 frames in one M-200i/S-0808 session ... from the box's own MAC".

Measured this pass: the block appears in **exactly one file**,
`m200-headamp-re/m200i-s0808-48k-mirror__ctl2.pcap`, from **exactly one source MAC**,
`00:40:ab:c4:80:41`.

That MAC is not the S-0808's. The S-0808 in this corpus is `00:40:ab:c4:dc:9c` — identified
independently from its own config-announce, which declares two input cells and two output
cells, eight in and eight out. So the grammar's attribution of this block to an S-0808 is
not what the wire says.

Worse, `c4:80:41` is the MAC our own software slave used to hard-code:
`reac-pw/src/reac_slave.c:93` describes the fix as putting the default "in one place instead
of a hard-coded box-colliding `0xc4:80:41`". So the emitter of the commonest control block in
the corpus is ambiguous between a real S-1608 and reac-pw. It is probably a real box — our
upstream builder emits FILLER, not `cd ea` — but "probably" is the whole finding.

**What would settle it:** one fresh capture of a known S-0808 alone on the segment, and one
of a known S-1608 alone, each long enough to carry upstream returns. Then say which box
emits it. Until then no consumer should treat this block as characteristic of any model.
**[IS?]**

### 3.2 Model naming rests on one model, one unit, eight frames

The ASCII name frame (op `0401`) appears 16 times across 7 files from **one source MAC**,
`00:40:ab:c4:dc:9c`, the single S-0808, and it carries exactly one string: `S-0808`.

An ASCII sweep over all 240288 control blocks of the 47 primary captures finds `SYSP` (641),
`SCEN` (641), `1234` (592), `AAAA` (10) and `S-0808` (8) — and **no** `S-1608`, `S-4000`,
`M-200` or `M-5000` anywhere. The probe demonstrably detects presence, four ways.

This matters because `reac.ksy:955` says family `0x84` "is then named by an ASCII name frame
or by the family default", and family `0x84` contains both the S-0808 and the S-4000S. We
have never captured the S-4000S naming itself. So a consumer distinguishing those two models
has only declared width to go on, and no evidence that a name frame would ever arrive.

**What would settle it:** a cold connect of an S-4000S with a full capture from PHY link-up,
looking for op `0401`. The corpus already holds two S-4000S coldconnects
(`matrix-m5000-s4000-unit1-coldconnect`, `matrix-m200-s4000-coldconnect`) and neither
contains a name frame; a fresh one taken from link-up rather than mid-session would decide
whether that is an absence or a truncation. **[IS?]**

### 3.3 The other single-source facts, in one list

- **The SENS 1 dB/step law.** `protocol-facts.yaml:726-740`. Measured 2026-08-23 on **one
  S-0808**, one loopback, one night, and assumed universal across the S-1608 and S-4000S.
  Settle by repeating the same loopback on an S-1608. **[IMPL]** — the method exists.
- **The SENS absolute anchor, −10 dBu at step 0.** `protocol-facts.yaml:715-724` is the one row
  in the whole schema graded INFERRED, and it says why: a loopback measures the span and not
  the endpoint. This is an inherited number, honestly labelled. Settle with the box's
  converter reference — one calibrated dBu measurement at a known step. **[IS?]**
- **`unit_offset` and the whole placement study.** Four units, three consoles, 42
  establishments — but two of the four units are S-1608s and two are S-4000Ss, so the S-0808
  row of the base table rests on **one serial**.
- **The generation flag.** One M-200i, one M-300, one M-5000. "Generation" is one physical
  desk each.
- **The two-box coexistence claim** at `wire-format.md:482` (`0x00..0x07` alongside
  `0x20..0x2f`) rests on a single capture that was a byproduct of an S-0808 establishment
  run, not a designed multi-box test. This is the single most load-bearing under-evidenced
  claim for multi-box work.

## 4. Inherited guesses wearing a fact's clothes

### 4.1 `SLAVE_ANNOUNCE1` — retire the label, and the reading under it

`reac-tools/wireshark/reac.lua:63` and `wire-format.md:116` both name the five-byte prefix
`01 03 00 10 82` as `SLAVE_ANNOUNCE1`. The label comes from a third-party macOS driver's
enum, in the half of that enum where the author numbered what he had not identified — the
adjacent entries are literally `ONE`, `TWO`, `THREE`, `FOUR`. `wire-format.md:108` grades the
whole table `[S]`, source-derived, which is honest. The trouble is what the fixed prefix
implies.

Measured this pass, over 72 files:

- `op_len` is `0x0010` on the 8-input S-0808, on both 16-input S-1608 units, **and on both
  32-input S-4000S units**. Three widths, one value. **It is a record length, not a channel
  count.** This settles a dispute our own docs have been running:
  `reac-firmware-re/REAC-PROTOCOL-CONSOLIDATED.md:132` and
  `reac-firmware-re/REAC-CONNECTION-FSM.md:87` both read it as a channel count, and
  `reac-firmware-re/HEADAMP-PROTOCOL-AUDIT-2026-07-22.md:52` reads it as a record length. The
  audit is right, and the S-4000S rows are the decisive evidence because 32 inputs cannot
  round to `0x10` under any reading.
- `payload[0]` is `0x82` on both S-1608 units and `0x84` on the S-0808 **and** both S-4000S
  units. It is the model-family selector `reac.ksy:955` already parses. It is **not** part of
  a fixed message signature.

So `0103001082` is the S-1608-family form of the config-announce, and the S-0808/S-4000S
form `0103001084` is **more common in our corpus** — 26 frames from 3 MACs against 18 from 2
— and has **no entry in either table**. A dissector keyed on the five-byte prefix silently
fails to name the commoner variant.

**Action:** delete `SLAVE_ANNOUNCE1..4` from `reac.lua` and from `wire-format.md:116-119`,
and dispatch on `(op, op_len)` with `payload[0]` read as a sub-type, the way
`reac.ksy:815-862` already does. The remaining three labels have the same defect in principle
and should go with it.

### 4.2 Two inherited claims that our corpus positively contradicts

`wire-format.md:186` says a master stuffs the ASCII tags `SYSP` and `XVSCEN`, and a `c0 a8`
(192.168) prefix repeated twice, into `data[]`. The same `c0 a8` bytes reappear at
`wire-format.md:731-732` as the trigger for the driver's slave handshake.

Over all 240288 control blocks of the primary captures: `SYSP` 641 hits in 33 files, `SCEN`
641 hits in 33 files, `1234` 592 hits — and `XVSCEN` **0**, `c0 a8` **0**. The probe is the
same byte search that found the other four, so it detects presence.

`XVSCEN` looks like a misreading of the two separate four-byte tags the grammar now names,
`SYSP` at `+0x368` and `SCEN` at `+0x37c` (`reac.ksy:766-782,784-813`). The `c0 a8` claim has no
local evidence at all and should be marked as unreproduced rather than stated.

### 4.3 The 44.1 kHz row of the facts schema claims evidence it does not have

`spec/protocol-facts.yaml:121` reads:

    evidence: EVIDENCED (corpus) — holds across 44.1k, 48k and 96k.

There is no 44.1 kHz capture. Measuring the packet rate directly from pcap timestamps across
all 72 files puts nothing in the 3500–3750 pps band; the same measurement correctly separates
six files at 96 k and eleven at 48 k, so it distinguishes rates. `reac-captures/CAPTURE-PLAN-next.md:45`
says the same independently, and `reac-firmware-re/NATIVE-REAC-DESIGN.md:277` states it
correctly — "modelled but never exercised — the 12-samples/frame packing is assumed,
unverified at that rate".

The 36-bytes-per-channel value is almost certainly right; the **evidence grade is wrong**,
and this schema's whole purpose is that a row without provenance is an unknown wearing a
fact's clothes. Corrected text: `EVIDENCED (corpus) at 48k and 96k; 44.1k is modelled, never
captured.`

Apart from this row, the schema is clean: all 93 rows carry an `evidence` key — checked by
walking the parsed YAML, not by grep — and exactly one row is graded INFERRED, honestly
(§3.3).

### 4.4 An inherited claim that has been properly re-derived, for contrast

The even/odd audio braid came from `obs-h8819-source` and `reacdriver`. It has since been
confirmed by our own lag-1 autocorrelation on rig captures, by the zoneA/zoneB goldens, and
by libreac's encoder reading back its own output (`reac.ksy:81-135`). This is what an
inherited claim looks like when it has been earned, and it is the standard the three above
fail.

Note the flip side, still in print: `reac-firmware-re/NATIVE-REAC-DESIGN.md:99` and
`reac-firmware-re/VIRTUAL-REAC-STAGEBOX.md:38` both assert plain-LE sample-major upstream and
mark it verified. `reac.ksy:100-135` refutes plain LE in both directions and explains where
the false coherence came from. Those two lines are stale.

## 5. Ranked — the ten unknowns that block the most

Ranked by what they stop us doing, not by how interesting they are.

1. **What decides the head-amp fabric base.** Blocks correct addressing of any box we have
   not measured, and therefore blocks any new model. Three carriers collinear across 42
   establishments. Settled by: one box declaring a width whose `selector` or `unit_offset`
   breaks the collinearity (`wire-format.md:465-469`). **[IS?]**
2. **Downstream multi-box slot assignment.** Blocks multi-box operation outright. The corpus
   has essentially one accidental two-box capture, and the desk-demuxes-by-MAC assumption is
   recorded as never observed with two boxes present. Settled by: a designed two-box
   establishment capture from PHY link-up, both boxes cold. **[IS?]**
3. **`console_field` — generation or rate class.** Blocks emitting a correct announce as a
   master at any rate/desk combination we have not captured, because the two readings predict
   our whole corpus identically. Settled by: one capture of an M-300 at 96 kHz, or an M-5000
   at 48 kHz (`reac-captures/CAPTURE-PLAN-next.md:21-39`). The M-300 is preferable — its MAC
   was never impersonated by reac-pw. **[IS?]**
4. **Per-rate upstream cadence.** Blocks the software stagebox at any rate but the one it was
   tuned at, and the failure mode is a master timeout. Our own docs state a fixed ~8000 fps
   and a rate-scaling law in different files. Settled by: measure the upstream frame rate of
   a real box at 48 k and at 96 k from one capture each. **[IS?]**
5. **44.1 kHz, in every respect.** Blocks any claim about the rate, and one facts row already
   claims evidence for it (§4.3). Settled by: one capture per desk family at 44.1 k. **[IMPL]**
   — nothing is unknown about how to do it.
6. **What triggers a full re-assert.** Blocks writing a master that behaves like a console:
   intervals of 46, 1011, 204, 45, 90, 90 s that did not correlate with operator activity
   (`wire-format.md:657`). It also matters for safety — re-assertion is what bounds a lost
   phantom command to one cycle. Our two documents disagree, `reac.ksy:211-212` saying the scene
   transfer never runs again for a session. Settled by: a long capture with a logged operator
   timeline beside it. **[IS?]**
7. **The fourth DROP trigger.** Blocks trusting our connection model at all, because it is
   proof the modelled trigger set is incomplete — a clean heartbeat stream was dropped with
   none of the three known triggers present. Settled by: a µs-timestamped capture of the drop
   with the box's own TX in view. **[IS?]**
8. **What invokes the S-1608's group head-amp apply.** Blocks the live defect the whole
   2026-08 effort is chasing: the bank gate itself is now understood from firmware, but what
   calls the applier is not, and twelve automated cold-connects produced bank 0 alone four
   times, bank 1 alone three times, neither five times and both never. Settled by: decompile
   `FUN_0c00bed4`'s callers — offline, no rig time. **[IS?]**
9. **The identity page, tag `0500`.** Blocks model identification from the wire, blocks the
   software stagebox from announcing what it is, and it is 594 request frames plus three
   distinct per-model reply templates we carry as opaque bytes. Settled by: decode the four
   distinct `0500` payloads against the three known models — offline corpus work. **[IS?]**
10. **The `box_return_block` interior.** 197927 frames of the commonest control block on the
    wire, one constant value, nothing in either firmware image shown to read it, and its
    emitter ambiguous (§3.1). Blocks nothing today, which is why it is tenth — but a spec
    that cannot say what its commonest block means is not finished. **[IS?]**

Below the line, and worth naming so they are not rediscovered: the `ce ea` split path (needs
hardware we do not have), the slot categories above `0x2f`, and the `0x80` report-builder arm.

## 6. What is NOT an unknown, so nobody re-opens it

- The audio braid, both directions, every generation. Refuting plain LE cost a night; it is
  settled at `reac.ksy:100-135`.
- The 96 kHz frame model `{96000, 40, 12}` at 8000 pps. Channel-halving is refuted.
- The scene body's three validated tags, and that they are a gate rather than a description.
- That head-amp records must follow the commit, never precede it.
- The three head-amp granularities: SENS and flags per channel, phantom per four, readback
  per eight.
- The scene chunk is not a probe. The "period-10 rotation with a phase step of +6" was a
  26-byte window over a 10-byte record stride.
