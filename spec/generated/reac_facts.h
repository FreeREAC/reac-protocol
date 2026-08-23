// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Pau Aliagas <linuxnow@gmail.com>
//
// GENERATED FILE - DO NOT EDIT.
//
// Source:    spec/protocol-facts.yaml   (in FreeREAC/reac-protocol)
// Generator: spec/gen-facts.py
//
// Edit the schema and regenerate. A hand-edit here is erased by the next run
// and, worse, is invisible to the cross-check that keeps reac.ksy and libreac
// agreeing - which is the whole reason this file is generated.

#ifndef REAC_FACTS_H
#define REAC_FACTS_H

/* ---- Frame geometry ------------------------------------------------------------
 * A REAC frame is a fixed L2 header, a control block, an audio region of
 * whole 36-byte channels, and a two-byte end marker. Every length in the
 * protocol is 52 + n*36 for some channel count n, and that one law is what
 * lets a parser recover the width from the size — REAC carries no width
 * field in an audio frame.
 *
 * The 52 is 50 bytes of header plus the 2-byte end marker. A capture may
 * carry two more bytes of Ethernet FCS residue; they are residue, not a
 * field, and are stripped before any of this arithmetic runs.
 */
/* REAC's registered non-IP EtherType. [EVIDENCED (corpus) — every frame in 72
 * captures.]
 */
#define REAC_ETHERTYPE                  0x8819

/* 14 eth + 2 counter + 2 type word + 32 control block. [EVIDENCED (corpus).] */
#define REAC_L2_HEADER_LEN              50

/* Where the audio region starts. Same number as the header length, and it is
 * the same fact. [EVIDENCED (corpus) — a golden offset scan decodes real desk
 * program as noise at every other offset.]
 */
#define REAC_AUDIO_OFFSET               50

/* u16 LITTLE-endian free-running sequence counter, against the big-endian
 * everything else. [EVIDENCED (corpus).]
 */
#define REAC_HDR_COUNTER_OFF            14

/* The non-audio bytes of any frame — 50 header + 2 end marker. The 52 in `52
 * + n*36`. [EVIDENCED (corpus).]
 */
#define REAC_FRAME_OVERHEAD             52

/* 12 samples x 3 bytes, per channel, at EVERY sample rate. The 36 in `52 +
 * n*36`. [EVIDENCED (corpus) — holds across 44.1k, 48k and 96k.]
 */
#define REAC_BYTES_PER_CHANNEL          36

/* Samples per channel per frame. The RATE is the packet rate; the frame does
 * not change shape with it. [EVIDENCED (corpus).]
 */
#define REAC_SAMPLES_PER_PKT            12

/* Bytes per sample per channel — 24-bit. [EVIDENCED (corpus).] */
#define REAC_RESOLUTION                 3

/* The downstream audio fabric, 40 slots. NOT the head-amp channel space,
 * which is 48 wide; conflating the two was a real bug. [EVIDENCED (corpus).]
 */
#define REAC_MAX_CHANNELS               40

/* The fixed downstream broadcast — 52 + 40*36. [EVIDENCED (corpus).] */
#define REAC_FRAME_BYTES                1492

/* 40 ch x 12 samples x 3 B. [EVIDENCED (corpus).] */
#define REAC_AUDIO_BYTES                1440

/* The two bytes a mirrored/SPAN capture leaves on the end of a frame.
 * EXPLAINED, STRIPPED, NEVER MODELLED — and load-bearing twice: it is
 * how mirrored duplicates are told apart (by GEOMETRY, never by
 * comparing bytes), and a truncated capture whose residue happens to
 * fit makes a short frame look like a legal narrower one.
 *   [EVIDENCED (corpus).]
 */
#define REAC_FCS_RESIDUE                2

/* First byte of the two-byte end marker. [EVIDENCED (corpus).] */
#define REAC_END_MARKER_0               0xc2

/* Second byte of the end marker. [EVIDENCED (corpus).] */
#define REAC_END_MARKER_1               0xea

/* ---- The 32-byte control block and its two checksums ---------------------------
 * Every non-FILLER frame carries a 32-byte control block at frame[18:50],
 * whose last byte is a checksum over the block. A FILLER frame (type word
 * 0x0000) carries audio there instead and is checksum-exempt.
 *
 * There are TWO checksum rules and they differ. The block sums to 0 mod 256.
 * A nested record inside it — the Roland DT1 head-amp record and its
 * relatives — sums to 0x80. The record's is stamped FIRST: a record fixed up
 * after the block is stamped invalidates the block, which is a real bug this
 * ordering exists to prevent.
 */
/* Frame offset of the control block. [EVIDENCED (corpus).] */
#define REAC_CTRL_BLOCK_OFF             18

/* One past the end — and therefore the audio offset. [EVIDENCED (corpus).] */
#define REAC_CTRL_BLOCK_END             50

/* The checksummed span. [EVIDENCED (corpus).] */
#define REAC_CTRL_BLOCK_LEN             32

/* The checksum byte, last of the block. Block-relative 31. [EVIDENCED
 * (corpus).]
 */
#define REAC_CTRL_CKSUM_OFF             49

/* The same byte, block-relative — what a caller stamping a bare 32-byte block
 * indexes. [EVIDENCED (corpus).]
 */
#define REAC_CTRL_CKSUM_OFF_IN_BLOCK    31

/* Sum(block[0..31]) mod 256 must equal this. [EVIDENCED (corpus) — every
 * control frame in the corpus.]
 */
#define REAC_CTRL_BLOCK_SUM             0x00

/* Sum(record TAG..CKSUM) mod 256 must equal this. The Roland DT1 rule, and
 * NOT the block rule. [EVIDENCED (corpus).]
 */
#define REAC_CTRL_RECORD_SUM            0x80

/* Frame offset of the type word — the start of the [16:50] window the goldens
 * store and the C tests use. [EVIDENCED (corpus).]
 */
#define REAC_TYPED_BLOCK_OFF            16

/* Type word (2) + control block (32). [EVIDENCED (corpus).] */
#define REAC_TYPED_BLOCK_LEN            34

/* ---- Type-word codes -----------------------------------------------------------
 * The two bytes at frame[16:18].
 */
/* Audio-only, no control op, checksum-exempt. [EVIDENCED (corpus).] */
#define REAC_TYPE_FILLER                0x0000

/* A control record. [EVIDENCED (corpus).] */
#define REAC_TYPE_CONTROL               0xcdea

/* The master announce. Same block shape, op always 0xffff. [EVIDENCED
 * (corpus).]
 */
#define REAC_TYPE_ANNOUNCE              0xcfea

/* ---- Control ops ---------------------------------------------------------------
 * The two bytes at block[0:2].
 */
/* A continuation chunk of the scene transfer. [EVIDENCED (image + corpus).] */
#define REAC_OP_SCENE_CHUNK             0x0100

/* The scene header, declaring the total. [EVIDENCED (image + corpus).] */
#define REAC_OP_SCENE_HEADER            0x0101

/* The final chunk. The box's commit is gated on it. [EVIDENCED (image +
 * corpus).]
 */
#define REAC_OP_SCENE_FINAL             0x0102

/* A multiplexer with TWO discriminators — op_len selects the sub-page,
 * payload[0] selects the subtype. [EVIDENCED (image + executed trace).]
 */
#define REAC_OP_PAGE_0103               0x0103

/* The ASCII model-name frame. [EVIDENCED (corpus).] */
#define REAC_OP_NAME_FRAME              0x0401

/* The extra cold-connect frame some models send. [EVIDENCED (corpus).] */
#define REAC_OP_EXTRA_COLD_CONNECT      0x0402

/* A record container — a Roland DT1 SysEx, or the box's upstream return
 * block. Discriminated by payload[0]. [EVIDENCED (corpus).]
 */
#define REAC_OP_DT1_CONTAINER           0x0403

/* The op a cfea announce always carries. [EVIDENCED (corpus).] */
#define REAC_OP_ANNOUNCE                0xffff

/* ---- op-0103 sub-pages and subtypes --------------------------------------------
 * op 0x0103 multiplexes on two axes at once, and reading only one of them
 * is how `01 03 00 10` and a head-amp block got taken for the same message.
 *
 * `op_len` selects the SUB-PAGE. `payload[0]` — block[4], the byte a scene
 * frame requires to be zero — is a SUBTYPE SELECTOR, not a reserved byte.
 */
/* op_len of the master's established chanmap heartbeat. [EVIDENCED (corpus).] */
#define REAC_PAGE_CHANMAP               0x0019

/* op_len of the box's setup declaration — and of the commit report.
 * [EVIDENCED (corpus).]
 */
#define REAC_PAGE_CONFIG_ANNOUNCE       0x0010

/* op_len of the master's prepare-to-grant frame. [EVIDENCED (image +
 * corpus).]
 */
#define REAC_PAGE_ENROLL_GROUP_MAP      0x000d

/* op_len of the box's heartbeat. [EVIDENCED (corpus).] */
#define REAC_PAGE_BOX_HEARTBEAT         0x0001

/* Block offset of the subtype selector — payload[0]. [EVIDENCED (executed
 * trace).]
 */
#define REAC_SUB_0103_OFF               4

/* Subtype 0 — scene. A scene frame requires this byte to be zero and the box
 * refuses the frame otherwise. [EVIDENCED (executed trace, image).]
 */
#define REAC_SUB_0103_SCENE             0x00

/* Subtype 1 — head-amp, 1 + 3k bytes of {ch, flags, sens}, eight records to a
 * frame. [EVIDENCED (executed trace, image).]
 */
#define REAC_SUB_0103_HEADAMP           0x01

/* Subtype 0x82 — the commit's report. The report builder also has a 0x80 arm;
 * what selects it is UNEXPLAINED. [EVIDENCED (executed trace, image).]
 */
#define REAC_SUB_0103_COMMIT_REPORT     0x82

/* The SAME block position discriminates op-0403's two forms. [EVIDENCED
 * (corpus).]
 */
#define REAC_SUB_0403_OFF               4

/* A genuine Roland DT1 record. [EVIDENCED (corpus).] */
#define REAC_SUB_0403_DT1_RECORD        0x00

/* The box's upstream return block — 6.05 million of them in the corpus, and
 * the look-alike a naive DT1 dispatch acts on. [EVIDENCED (corpus).]
 */
#define REAC_SUB_0403_BOX_RETURN        0x02

/* ---- The scene push ------------------------------------------------------------
 * After link-up a desk pushes its scene to the box as one bounded transfer:
 * an op-0101 header declaring the total and carrying the body's first 24
 * bytes, 341 op-0100 chunks of 26, and an op-0102 final of 14.
 *
 *   24 + 341*26 + 14 = 8904 = 0x22c8
 *
 * The three sizes and the total are ONE fact, not four: the lengths a step
 * declares are what must sum to what the header declares. A body whose
 * lengths do not sum leaves the box waiting for bytes that never come.
 *
 * The box completes reassembly ONLY on the final chunk, and completion runs
 * its state-4 commit — the sole promoter of staged head-amp into the active
 * table. A transfer that stops short leaves the box in reassembly for the
 * life of the link.
 */
/* The declared total, 0x22c8. The box gates its header on this exact value.
 * [EVIDENCED (image, both sides) — the same constant resolved out of the
 * S-1608's own image and out of the master's.]
 */
#define REAC_SCENE_BYTES                8904   /* 0x22c8 */

/* Body bytes carried by the op-0101 header, at block[7:31]. [EVIDENCED (image
 * + corpus).]
 */
#define REAC_SCENE_HEAD_BYTES           24

/* Body bytes per op-0100, at block[5:31]. Its declared op_len. [EVIDENCED
 * (image + corpus).]
 */
#define REAC_SCENE_CHUNK_BYTES          26

/* Body bytes in the op-0102 final. 8880 mod 26 — a length like any other
 * chunk's, not a fixed block. [EVIDENCED (image + corpus).]
 */
#define REAC_SCENE_TAIL_BYTES           14

/* op-0100 count for a whole body. [EVIDENCED (corpus) — measured back-to-back
 * in 0.680 s on a real M-200i driving an S-1608.]
 */
#define REAC_SCENE_CHUNKS               341

/* Header + chunks + final. [derived.] */
#define REAC_SCENE_STEPS                343

/* Block offset of the op word. [EVIDENCED (image).] */
#define REAC_SCENE_OP_OFF               0

/* Block offset of the BE payload length. [EVIDENCED (image) — a big-endian
 * 16-bit store from the same variable the master passes to the memcpy that
 * fills the payload.]
 */
#define REAC_SCENE_LEN_OFF              2

/* Block offset of the reserved/subtype byte. Zero on every scene step; the
 * box refuses the frame otherwise. [EVIDENCED (image + executed trace).]
 */
#define REAC_SCENE_SUB_OFF              4

/* Block offset of a chunk's and the final's body bytes. [EVIDENCED (image).] */
#define REAC_SCENE_CHUNK_PAY_OFF        5

/* Block offset of the header's BE declared total. The header's payload
 * therefore starts two bytes later than a continuation's. [EVIDENCED (image)
 * — `movi20]
 */
#define REAC_SCENE_HEAD_TOTAL_OFF       5

/* Block offset of the header's 24 body bytes — which is why a capture of this
 * frame alone shows the ASCII "1234" that opens the body. [EVIDENCED (image +
 * corpus).]
 */
#define REAC_SCENE_HEAD_PAY_OFF         7

/* ---- What the box validates in the body, and what it reads ---------------------
 * The commit checks THREE four-byte tags and nothing else. Fail any one and
 * it promotes nothing and replies nothing, while the transfer still looks
 * complete from the wire. Two of the three ride MIDDLE chunks, so a body
 * whose interior is wrong fails silently.
 *
 * THE TAGS ARE A GATE, NOT A DESCRIPTION OF WHAT THE BOX USES. Measured on
 * hardware: a body of zeros carrying only the three tags PASSES the commit
 * and leaves the box reporting model=unknown with ZERO capture ports, where
 * a recovered body brings it up as s1608 with 16. The unvalidated 8892 bytes
 * are not free — a wrong value there is not rejected, it is acted on.
 */
/* "1234". Rides the op-0101 header. [EVIDENCED (executed trace) — 2 of 70
 * zeroed 128-byte windows break the commit, and they are the two containing a
 * tag.]
 */
#define REAC_SCENE_TAG_ID_OFF           0x000

/* "SYSP". Rides op-0100 chunk 32. [EVIDENCED (executed trace).] */
#define REAC_SCENE_TAG_SYSP_OFF         0x368

/* "SCEN". Rides op-0100 chunk 33. [EVIDENCED (executed trace).] */
#define REAC_SCENE_TAG_SCEN_OFF         0x37c

/* The master's own MAC, INSIDE the body. On-wire identity must equal the L2
 * source, so a master replaying a recovered body substitutes its own.
 * [EVIDENCED (image + corpus).]
 */
#define REAC_SCENE_MAC_OFF              0x340

/* The generation byte — 0 on a V-Mixer desk, 1 on an M-5000. One of only two
 * fields an emitter fills in. [EVIDENCED (corpus) — 8 of 8904 bytes vary
 * across 27 real-desk bodies over three desk generations and four box
 * models.]
 */
#define REAC_SCENE_REVISION_OFF         0x014

/* The 80-slot declaration table. [EVIDENCED (image + corpus).] */
#define REAC_SCENE_SLOTS_OFF            0x01a

/* Slots the commit promotes — unconditionally, all of them, with the SAME
 * constant. A scene body therefore CANNOT address an individual channel.
 * [EVIDENCED (executed trace).]
 */
#define REAC_SCENE_SLOT_COUNT           80

/* The scene record stride. 26 mod 10 = 6 and gcd(26,10) = 2 is the whole of
 * the "period-10 probe rotation with a phase step of +6" that was read as a
 * master state for a year. [EVIDENCED (image + corpus).]
 */
#define REAC_SCENE_SLOT_BYTES           10

/* Value at +0x04 on every desk generation and against every box. The commit
 * branches on it. [EVIDENCED (image + corpus).]
 */
#define REAC_SCENE_UNIT_MAP_SELECT      0x0001

/* Value at +0x08 on every capture. What it selects is UNRESOLVED. [EVIDENCED
 * (image + corpus).]
 */
#define REAC_SCENE_MAP_A_ARG            0x0004

/* ---- Head-amp — the record, and its three granularities ------------------------
 * A head-amp record is a Roland DT1 inside op-0403: TAG 0x0101, then
 * {CH, PARAM, VALUE}. Two things about it are routinely got wrong.
 *
 * IT IS THREE GRANULARITIES UNDER ONE NAME. SENS and the flag bits are PER
 * CHANNEL. Phantom is PER GROUP OF FOUR (ch >> 2). The readback nibble is
 * PER EIGHT (ch >> 3). So only a record whose channel is a multiple of four
 * carries the phantom group byte — a record to 0x24 moves group 9, one to
 * 0x27 moves nothing — and sweeping phantom per channel writes three records
 * in four into the void. The readback nibble and the phantom command do not
 * address the same thing and must stay named apart in any API generated from
 * this.
 *
 * A RECORD WRITES THE ACTIVE TABLE, AND THE COMMIT OVERWRITES IT. There is
 * no head-amp staging table. So records must FOLLOW the commit, never
 * precede it: a record sent before it is erased, silently — the bytes are
 * right, the checksums are right, the box acknowledges, and the value is
 * gone.
 */
/* The DT1 register page for head-amp. [EVIDENCED (corpus).] */
#define REAC_HEADAMP_TAG                0x0101

/* +48V, value 0 or 1. WHICH BIT IS PHANTOM AND WHICH IS PAD IS OUR NAME, NOT
 * THE FIRMWARE'S — the mapping comes from the corpus and the rig, explicitly
 * NOT from the image. [EVIDENCED (corpus + rig).]
 */
#define REAC_HEADAMP_PARAM_PHANTOM      0x00

/* -20 dB pad, value 0 or 1. [EVIDENCED (corpus + rig).] */
#define REAC_HEADAMP_PARAM_PAD          0x01

/* Sensitivity step. [EVIDENCED (corpus + rig).] */
#define REAC_HEADAMP_PARAM_SENS         0x02

/* 55 — the 56th and last entry of the box's own step table, which is exactly
 * 56 rows with no spares. [EVIDENCED (image) — a 56-entry table at 0x0c0327a0
 * in the S-1608 image, reached by both write paths, ending exactly where the
 * "V03.05" version string begins.]
 */
#define REAC_HEADAMP_SENS_MAX           0x37

/* 48 addressable wire channels, 0x00..0x2f. NOT the 40-slot audio fabric — a
 * table bounded by 40 silently rejects a 16-input box based at 0x20, so its
 * inputs 9..16 can never be given phantom, pad or sens. [EVIDENCED (corpus).]
 */
#define REAC_HEADAMP_CH_SPAN            0x30

/* SENS is per channel — ch >> 0. [EVIDENCED (executed trace).] */
#define REAC_HEADAMP_GRAN_SENS_SHIFT    0

/* The flag bits are per channel — ch >> 0. [EVIDENCED (executed trace).] */
#define REAC_HEADAMP_GRAN_FLAGS_SHIFT   0

/* Phantom is per group of FOUR — ch >> 2. [EVIDENCED (executed trace).] */
#define REAC_HEADAMP_GRAN_PHANTOM_SHIFT 2

/* The readback nibble is per EIGHT — ch >> 3. A different axis from phantom,
 * deliberately named apart. [EVIDENCED (executed trace).]
 */
#define REAC_HEADAMP_GRAN_READBACK_SHIFT 3

/* Every real desk sweep is ONE contiguous pass over the box's full declared
 * width, every channel getting all three parameters — 24 records for an
 * S-0808, 48 for an S-1608, 96 for an S-4000S. No desk addresses a bank,
 * splits a sweep or repeats one. [EVIDENCED (corpus) — 31 of 47 captures,
 * three desk generations agreeing on the same box.]
 */
#define REAC_HEADAMP_SWEEP_RECORDS_PER_CH 3

/* ---- Head-amp base per declared width ------------------------------------------
 * A head-amp record's CH is base + (box_input - 1), and the base depends on
 * the box's declared INPUT width.
 *
 * THIS IS NEGOTIATED SESSION STATE, NOT A WIRE FIELD, and that is why it
 * lives here rather than in the grammar: no byte in any frame carries it. A
 * 42-establishment, three-console, four-unit study killed every testable
 * candidate law and left three carriers — declared width, the config
 * selector, and unit_offset — perfectly collinear on every row. reac.ksy
 * parses the CARRIERS as typed fields and refuses to encode a base;
 * libreac's reac_headamp_base() returns the MEASURED table below and refuses
 * any width it has not seen, which is the same refusal expressed the other
 * way round. Both are right; neither may guess.
 */
#define REAC_PLACEMENT_ROWS 3
/* { in_ch, base } rows: */
#define REAC_PLACEMENT_TABLE { { 8, 0x00 }, { 16, 0x20 }, { 32, 0x00 } }
/* 8 -> 0x00: S-0808. [EVIDENCED (corpus) — 42 grant sweeps across 82
 * captures.]
 */
/* 16 -> 0x20: S-1608. The one width that is not zero, and the reason a
 * 40-bounded table drops half the box. [EVIDENCED (corpus).]
 */
/* 32 -> 0x00: S-4000S. Wider than the S-1608 and still based at 0 — which is
 * what kills "lowest fit" and "top alignment" as candidate laws. [EVIDENCED
 * (corpus).]
 */

/* ---- The config-announce port table --------------------------------------------
 * A box declares its own geometry: twelve cells of four channels each,
 * spanning the 48-channel fabric ring. Geometry comes from the declaration,
 * not from a hand-kept model list.
 */
/* Block-relative start of the twelve-cell table. [EVIDENCED (corpus).] */
#define REAC_PORTS_TABLE_OFF            8

/* 12 x 4 = the 48-channel fabric. [EVIDENCED (corpus).] */
#define REAC_PORTS_TABLE_SLOTS          12

/* Channels per cell. [EVIDENCED (corpus).] */
#define REAC_PORTS_CH_PER_SLOT          4

/* A 4-output group. [EVIDENCED (corpus).] */
#define REAC_PORT_SLOT_OUT              0x01

/* A 4-input group. [EVIDENCED (corpus).] */
#define REAC_PORT_SLOT_IN               0x02

/* An empty cell. A code outside {01,02,03} is a table nobody has captured —
 * REFUSE, never guess. [EVIDENCED (corpus).]
 */
#define REAC_PORT_SLOT_EMPTY            0x03

/* One per enrolled input group of 8, front-packed. [EVIDENCED (image +
 * corpus).]
 */
#define REAC_ENROLL_GROUP_IN            0x41

/* One per non-input group, back-packed. [EVIDENCED (image + corpus).] */
#define REAC_ENROLL_GROUP_OUT           0xc3

/* Five groups of 8 span exactly the 40-slot audio fabric. [EVIDENCED (image +
 * corpus).]
 */
#define REAC_ENROLL_GROUPS              5

#endif /* REAC_FACTS_H */
