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

/* Class 1 carried whole in one frame — the fragment field is 3, both FIRST
 * and LAST. payload[0] is the only discriminator; op_len beside it is a
 * length, not a second selector. See the control_header group. [EVIDENCED
 * (image + executed trace).]
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

/* ---- The control record header -------------------------------------------------
 * The first five bytes of every cd ea control block are four fields, and
 * until 2026-08-23 two of our artefacts treated them as one opaque opcode
 * word plus an "op-specific" number. They are not opaque and the number is
 * not op-specific.
 *
 *   block[0] class 0x01 session, 0x04 parameter
 *   block[1] fragment bit0 FIRST, bit1 LAST
 *   block[2:4] rec_len u16 BIG-ENDIAN, counted from block[4] INCLUSIVE
 *   block[4] subtype what the record is; bit7 set = a box reply
 *
 * WHERE THIS COMES FROM. S-1608.BIN, SH-2 little-endian, load base
 * 0x0BFE0000. The scene sender FUN_0c003398 writes block[1] from a
 * first/last decision and calls FUN_0c002f7a for block[2:4]; FUN_0c002f7a
 * is a two-byte store, high byte first, which is what makes rec_len
 * big-endian. The same routine is called by FUN_0c002c70 (slot map,
 * rec_len = 0x19), FUN_0c003c8a (commit report, 0x10) and FUN_0c003fe2
 * (link ack, 0x01). The reader FUN_0c002e94 gates a slot map on
 * block[0]==1, block[1]==3 and block[4]==1 — three separate fields, never a
 * string.
 *
 * THE FRAGMENT FIELD IS TWO BITS AND EXPLAINS FOUR "OPCODES". The scene
 * sender emits 1 for a full opening chunk, 0 for a full middle chunk, 2 for
 * a short closing chunk and 3 when the whole record fits in one frame. So
 * 0x0100, 0x0101, 0x0102 and 0x0103 are ONE class under four fragment
 * states, not four opcodes, and the box's reassembler agrees: its state-2
 * gate is (block[1] & 1), its state-3 gate is block[1] in {0, 2} and its
 * finish test is block[1] == 2.
 *
 * WHAT THIS RETIRES. The wireshark dissector we inherited from reacdriver
 * matched the five bytes as a STRING and gave the eight it had seen names
 * that were guesses — CONTROL_ONE..FOUR and SLAVE_ANNOUNCE1..4. Those
 * strings run a class, a flag field, a LENGTH and a subtype together, so
 * they are model-specific by accident: an S-0808 and an S-4000S send the
 * same commit report with subtype 0x84, and `0103001084` fell through the
 * table as unknown while the identical S-1608 record was labelled.
 */
/* Block offset of the record class. [EVIDENCED (image).] */
#define REAC_CTRL_CLASS_OFF             0

/* Scene transfer, slot map, commit report, link ack. [EVIDENCED (image +
 * corpus).]
 */
#define REAC_CTRL_CLASS_SESSION         0x01

/* The DT1 container — head-amp, identity, join grant, box return. [EVIDENCED
 * (image + corpus).]
 */
#define REAC_CTRL_CLASS_PARAMETER       0x04

/* Block offset of the fragment flags. [EVIDENCED (image).] */
#define REAC_CTRL_FRAG_OFF              1

/* Bit 0 — this frame opens the record. [EVIDENCED (image, S-1608 FUN_0c003398
 * + FUN_0c003aae).]
 */
#define REAC_CTRL_FRAG_FIRST            0x01

/* Bit 1 — this frame closes it. Both set is a whole record. [EVIDENCED
 * (image, S-1608 FUN_0c003398 + FUN_0c003b88).]
 */
#define REAC_CTRL_FRAG_LAST             0x02

/* Block offset of the record length, a big-endian u16. [EVIDENCED (image,
 * S-1608 FUN_0c002f7a).]
 */
#define REAC_CTRL_RECLEN_OFF            2

/* The block offset the length counts FROM, inclusive. Verified on every
 * record type in the corpus — slot map 0x19 = block[4..28], commit
 * report 0x10 = block[4..19], link ack 0x01 = block[4], enroll group
 * map 0x0d = block[4..16], DT1 0x14 = block[4..23] with the record's
 * own checksum as the last byte. Our grammar used to say this number
 * was "op-specific in meaning" and "not a generic frame length"; it is
 * a generic record length and always was.
 *   [EVIDENCED (image + corpus).]
 */
#define REAC_CTRL_RECLEN_BASE           4

/* Block offset of the subtype, the record's only discriminator. [EVIDENCED
 * (image).]
 */
#define REAC_CTRL_SUBTYPE_OFF           4

/* Payload bytes in an opening scene chunk — smaller than a middle chunk
 * because block[5:7] carries the blob total. [EVIDENCED (image, S-1608
 * FUN_0c003398).]
 */
#define REAC_CTRL_SCENE_CHUNK_FIRST     0x18

/* Payload bytes in a middle or closing scene chunk, at block[5]. [EVIDENCED
 * (image, S-1608 FUN_0c003398).]
 */
#define REAC_CTRL_SCENE_CHUNK_MIDDLE    0x1a

/* ---- The state-4 commit — what it flushes --------------------------------------
 * WHAT THE COMMIT IS. The box runs a scene FSM, S-1608 FUN_0c0037ee, over
 * one RAM cell. State 2 takes the master's opening scene fragment, state 3
 * reassembles the continuations, and state 4 is FUN_0c003c8a — the COMMIT.
 * Nothing else promotes staged state into the active table; the head-amp
 * apply FUN_0c007fbc reads the ACTIVE table and only the commit writes it
 * wholesale.
 *
 * THREE THINGS ARE TWELVE WIDE AND ONLY ONE OF THEM IS A GROUP FLUSH. This
 * was the open question and the firmware answers it: the commit touches TWO
 * of the three, and NEITHER of them is a phantom flush.
 *
 *   1. The slot table copy is EIGHTY wide, not twelve. staging 0x0c0cd52e
 *      -> active 0x0c0cf85a, fields +2 +4 +6 +8, `while (i < 0x50)`,
 *      unconditional — there is no per-slot enrolled test in the commit.
 *
 *   2. The twelve-wide loop `FUN_0c00f9aa(i, *(u16*)(staging + i*0x28))`
 *      reads field +0 of every FOURTH slot record (0x28 = four 10-byte
 *      records) and writes a 12-entry u16 array at 0x0c0f62fa. That array
 *      is the PEER INVENTORY MIRROR: what the master has declared each
 *      group of four channels to be. Its reader is FUN_0c00fa1a, which
 *      refuses to answer unless the link word is 1; its reset FUN_0c00fa58
 *      fills it with 3 = absent. The SAME array is written by the slot-map
 *      ingest FUN_0c002d42 from the high nibble of byte 1, at group anchors
 *      only. It touches no hardware.
 *
 *   3. The twelve bytes in the emitted report come from a DIFFERENT array —
 *      the box's OWN inventory, 12 records of 6 bytes at 0x0c080920, read
 *      through FUN_0c00f6ca and initialised by FUN_0c00f7f8. This is the
 *      declared inventory, and it is what reaches the wire.
 *
 * SO "THE COMMIT FLUSHES 12 PHANTOM GROUPS" IS WRONG in both halves. There
 * is no phantom in either twelve-wide structure; phantom reaches hardware
 * from the ACTIVE table through FUN_0c007fbc, in groups of EIGHT, ten of
 * them, and the commit does not call it. The two twelve-wide things the
 * commit does touch are both INVENTORY — one inbound, one outbound.
 *
 * Cross-checked on a second image: S-4000.BIN has the identical shape — the
 * 0x50-slot copy, the six-byte master id, the `i * 0x28` twelve-group loop
 * over its own staging table 0x0c0cd66a, and the same report.
 *
 * ON THE S-4000 ADDRESSES, because a base error would silently invalidate
 * these citations while leaving the conclusion right. They are quoted in the
 * address space of `devices/S-4000S/decompile/S-4000_alldecomp.c`, which is
 * 0x0C000000, and that space was CHECKED rather than assumed: all 832
 * PTR_FUN literal values in that image resolve exactly to addresses of
 * functions listed in the same decompilation. At a base of 0x0BFF0000 only
 * 20 of 832 resolve. Real code also begins at file offset 0x10 and the
 * listing's functions span file offsets 0x890..0x41e68, so there is no
 * unmapped 0x10000 prefix that would reconcile the two. File offsets, which
 * survive any re-basing: the commit at 0x13834, its literals at 0x1382c,
 * 0x13750, 0x13752.
 *
 * The RAM pointers these literals hold (0x0c0cd66a and the rest) are values
 * baked into the image and are correct as runtime addresses whatever base
 * the code is read at.
 */
/* Slots copied staging -> active by the commit, unconditionally. Eighty,
 * not forty-eight — the box's addressable channel space is 48 (the slot
 * map ingest gates slot < 0x30) but the table it lives in is 80 deep and
 * the head-amp apply walks ten groups of eight over it.
 *   [EVIDENCED (image, S-1608 FUN_0c003c8a + S-4000 same loop).]
 */
#define REAC_COMMIT_SLOT_TABLE_ENTRIES  80   /* 0x0050 */

/* Stride of the staging and active slot tables. Fields +2 sens, +4/+6/+8 the
 * three per-slot booleans; +0 is not copied and is read at four-slot stride
 * as the group's inventory cell. [EVIDENCED (image, S-1608 FUN_0c003c8a +
 * FUN_0c002d42).]
 */
#define REAC_COMMIT_SLOT_RECORD_BYTES   10

/* The granted master's identity, copied staging -> active by the commit.
 * Zeroed on link loss by FUN_0c003a64; a mismatch against the observed master
 * forces the FSM to state 0 (FUN_0c0045ec), which is why a takeover resets
 * the box's head-amp. [EVIDENCED (image).]
 */
#define REAC_COMMIT_MASTER_ID_BYTES     6

/* The head-amp hardware apply FUN_0c007fbc(bank, group) walks EIGHT
 * slots, `group << 3`, for group 0..9. This is the geometry that
 * actually reaches hardware, and it is a different axis from the
 * four-channel inventory cell. Confusing the two is how "twelve
 * phantom groups" got written down.
 *   [EVIDENCED (image, S-1608 FUN_0c007fbc).]
 */
#define REAC_HEADAMP_APPLY_GROUP_CHANNELS 8

/* Groups of eight the apply accepts, 0..9, covering the 80-slot active table.
 * [EVIDENCED (image, S-1608 FUN_0c007fbc).]
 */
#define REAC_HEADAMP_APPLY_GROUPS       10

/* ---- op-0103 sub-pages and subtypes --------------------------------------------
 * `payload[0]` — block[4], the byte a scene frame requires to be zero — is
 * the SUBTYPE SELECTOR, and it is the ONLY discriminator. That is how
 * `01 03 00 10` and a head-amp block came to be taken for one message.
 *
 * THE FOUR `PAGE_*` NUMBERS BELOW ARE LENGTHS, NOT SELECTORS, and this
 * group used to say otherwise. op_len is a plain record byte count on every
 * op — see the control_header group for the firmware that writes it. Each
 * subtype happens to have a fixed size today, so keying a parser on op_len
 * appears to work and then fails silently on the first short frame. Key on
 * the subtype; the lengths stay here because an emitter must still fill
 * op_len correctly, and they are named `LEN_` to say what they are.
 */
/* Record length of the master's slot-map window — the subtype byte plus
 * eight 3-byte slot records. S-1608 FUN_0c002c70 builds it.
 *   [EVIDENCED (corpus).]
 */
#define REAC_LEN_SUB_CHANMAP            0x0019

/* Record length of the box's state-4 commit report — the subtype byte,
 * two zero bytes, the board-configuration code, twelve inventory cells.
 * S-1608 FUN_0c003c8a builds it; S-4000 has the same shape.
 *   [EVIDENCED (corpus).]
 */
#define REAC_LEN_SUB_COMMIT_REPORT      0x0010

/* Record length of the master's prepare-to-grant frame. [EVIDENCED (image +
 * corpus).]
 */
#define REAC_LEN_SUB_ENROLL_GROUP_MAP   0x000d

/* Record length of the box's link-check ack — the subtype byte and
 * nothing else. S-1608 FUN_0c003fe2 builds it, from scene-FSM state 7.
 *   [EVIDENCED (corpus).]
 */
#define REAC_LEN_SUB_LINK_ACK           0x0001

/* Block offset of the subtype selector — payload[0]. [EVIDENCED (executed
 * trace).]
 */
#define REAC_SUB_0103_OFF               4

/* Subtype 0 — scene. A scene frame requires this byte to be zero and the box
 * refuses the frame otherwise. [EVIDENCED (executed trace, image).]
 */
#define REAC_SUB_0103_SCENE             0x00

/* Subtype 1 — the master's SLOT MAP, eight 3-byte records to a frame.
 * This group used to call it "head-amp" and reac.ksy calls the same
 * frame the chanmap; both names are half of it. The box's ingest
 * FUN_0c002d42 splits each record three ways: the high nibble of byte 1
 * is the inventory cell for the group this slot anchors and is consumed
 * only where (slot & 3) == 0; bits 3, 2 and 1 of byte 1 are three
 * per-slot booleans; byte 2 is the SENS step, and it lands in the same
 * active-table field the head-amp apply FUN_0c007fbc reads back. So it
 * IS a channel map and it DOES carry head-amp state.
 *   [EVIDENCED (image, S-1608 FUN_0c002d42 + FUN_0c002bb2).]
 */
#define REAC_SUB_0103_SLOT_MAP          0x01

/* Bit 7 of the subtype marks a record travelling BOX -> MASTER. Every
 * box-built subtype has it (0x81 the link ack, 0x80/0x82/0x83/0x84 the
 * commit report) and no master-built one does (0x00 scene, 0x01 slot
 * map, 0x10 enroll group map).
 *   [EVIDENCED (image + corpus).]
 */
#define REAC_SUB_REPLY_BIT              0x80

/* The box's link-check ack, S-1608 FUN_0c003fe2, from scene-FSM state 7. It
 * was called SLAVE_ANNOUNCE4 in the inherited dissector. [EVIDENCED (image +
 * corpus).]
 */
#define REAC_SUB_0103_LINK_ACK          0x81

/* The master's prepare-to-grant frame, once about 1.6 s before the grant
 * burst. [EVIDENCED (corpus).]
 */
#define REAC_SUB_0103_ENROLL_GROUP_MAP  0x10

/* The box's state-4 COMMIT REPORT — NOT a slave announce, which is what
 * reacdriver called it and what our dissector repeated until
 * 2026-08-23. S-1608 FUN_0c003c8a builds it after promoting staging to
 * active, and it is reached only from state 4 of the scene FSM
 * FUN_0c0037ee, i.e. after the master's scene transfer has completed.
 *
 * 0x82 IS THE S-1608'S NUMBER, NOT THE PROTOCOL'S, and a consumer must
 * not match on it. The builder picks between two model-specific
 * literals on a link-state test: S-1608 0x82 linked (DAT_0c00401c) and
 * 0x80 otherwise (DAT_0c00401e); S-4000 0x84 linked (DAT_0c013750) and
 * 0x83 otherwise (DAT_0c013752). What selects the second arm used to be
 * recorded here as UNEXPLAINED and now is not: on the S-1608 it is
 * FUN_0c00f9f2 returning something other than 1, which happens whenever
 * the peer-declared word is unset or the link word is not 1. Observed
 * on the wire: S-1608 0x82, S-0808 and S-4000S both 0x84. Match the
 * family with SUB_REPLY_BIT, not the literal.
 *   [EVIDENCED (image, S-1608 FUN_0c003c8a + S-4000 same shape; corpus, three
 *   box models).]
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

/* ---- Head-amp — the record, its wire encoding and its actuation ----------------
 * A head-amp record is a Roland DT1 inside op-0403: TAG 0x0101, then
 * {CH, PARAM, VALUE}. Two things about it are routinely got wrong.
 *
 * TWO AXES, NOT THREE GRANULARITIES. This group used to say "three
 * granularities under one name" and list per-channel, per-four and
 * per-eight side by side. Those are not three points on one scale: two of
 * them are WIRE ENCODING (which record carries a field) and one is HARDWARE
 * ACTUATION (how many channels one write switches). Reading them as one
 * list makes a consumer wrong about whichever it picks.
 *
 * AXIS 1 — WIRE ENCODING, what a record carries.
 *
 *   DT1 head-amp record {CH, PARAM, VALUE}, op-0403 TAG 0x0101
 *     PARAM 0x00 phantom, 0x01 pad, 0x02 sens — one channel per record,
 *     all three. NO per-four gate exists on this path anywhere in the
 *     image; see the DISPUTED note on HEADAMP_GRAN_PHANTOM_SHIFT.
 *
 *   SLOT MAP record {slot, cell+flags, sens}, op-0103 subtype 0x01
 *     FUN_0c002d42 writes the sens byte and the three flag bits (bits 3,
 *     2, 1) for EVERY slot, unconditionally. Only the HIGH NIBBLE is
 *     per-four: the `(slot & 3) == 0` branch hands `flags >> 4` to
 *     FUN_0c00f9aa and FUN_0c004164, the two 12-entry INVENTORY arrays.
 *     So the per-four field in this record format is the INVENTORY CELL,
 *     not a head-amp parameter.
 *
 * AXIS 2 — HARDWARE ACTUATION, what one write switches. PER CHANNEL, for
 * all three parameters. FUN_0c007fbc(bank, group) sets its cursor to
 * `group << 3` and loops EIGHT times; inside the loop, each iteration
 * passes its own within-bank index (0..7) and that slot's own value to
 * FUN_0c00ac1e (phantom), FUN_0c00ac96 (pad) and FUN_0c007e6a ->
 * FUN_0c007e30 (sens). Each channel gets its own value and its own write.
 *
 * SO THERE ARE EXACTLY TWO GRANULARITIES, NOT THREE: per channel and per
 * eight. Per channel is the ACTUATION. Per eight is the REFRESH BANKING —
 * and the readback nibble is the same eight, not a third axis. See
 * HEADAMP_BANK_CHANNELS, which is now the single row for both.
 *
 * BANK AND GROUP ARE DIFFERENT AXES AND OUR DOCS HAVE MIXED THEM UP.
 * Pinned here, once:
 *
 *   GROUP 0..9, and `group == ch >> 3`. It selects WHICH EIGHT CHANNELS'
 *          DATA — an eight-slot window of the 80-slot active table.
 *   BANK selects WHICH EIGHT PHYSICAL PREAMPS receive it. It is NOT a
 *          subdivision of channel space and it does not index the active
 *          table.
 *
 * They are independent, which is why FUN_0c007fbc takes both. At least one
 * doc has them inverted — FUN_0c012162(k) returns a GROUP 0..9 while its
 * argument k is a BANK — so anything reading either word should check it
 * against this definition rather than against neighbouring prose.
 *
 * A NOTE ON A CORRECTION MADE TO THIS FILE'S OWN CORRECTION: the firmware
 * lane's first report said phantom "reaches hardware in groups of EIGHT".
 * That read the loop bound as the actuator width and is wrong in the same
 * shape as the per-four claim it was correcting. The loop is eight long;
 * the write inside it is one channel wide.
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
 * 56 rows with no spares. What each step is WORTH in dB is the headamp_sens
 * group below; this row is only the count. [EVIDENCED (image) — a 56-entry
 * table at 0x0c0327a0 in the S-1608 image, reached by both write paths,
 * ending exactly where the "V03.05" version string begins — in the S-1608
 * image; the S-0808 copy is a byte match only. The count is what that table
 * proves; reading a gain curve off its stage structure did not survive the
 * rig.]
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

/* DISPUTED 2026-08-23, VALUE UNCHANGED PENDING ONE EXPERIMENT. Read as
 * "phantom is per group of FOUR — ch >> 2", and a consumer that trusts
 * it sweeps phantom on multiples of four only.
 *
 * THE IMAGE DOES NOT CONTAIN THIS GATE. There is exactly one
 * channel-indexed `(x & 3) == 0` test in S-1608.BIN — FUN_0c002d42, the
 * SLOT-MAP ingest — and what it gates is `flags >> 4`, the inventory
 * cell nibble, handed to the 12-entry inventory arrays at 0x0c0f62fa
 * and 0x0c0cf80e. It does not gate a head-amp parameter, and it is not
 * on the DT1 path at all. Every other `& 3` in the image is pointer
 * alignment. Meanwhile the hardware write is per channel (see
 * HEADAMP_ACTUATION_SHIFT), so there is no per-four actuator for a
 * per-four record to feed.
 *
 * The most likely history is that this number and the state diagram's
 * retracted "phantom packed 4 ch/group, group = slot >> 2" are the same
 * misreading of FUN_0c002d42, and that "a record to 0x24 moves group 9"
 * describes the inventory cell moving, not phantom.
 *
 * THE STATIC CASE STRENGTHENED ON 2026-08-23 and the row still does not
 * flip. Three things now point the same way: actuation is per channel
 * (HEADAMP_ACTUATION_SHIFT); the only channel-indexed `& 3` test in the
 * image is the inventory-cell gate; and the per-eight axis turned out to
 * be BANKING rather than actuation, so nothing on the hardware side is
 * grouped at all. That is a much better static picture than an hour ago
 * and it is still not an observation.
 *
 * NOT CHANGED HERE, because the grade below is an executed trace and
 * inference must not overwrite one however good it gets. THE ONE
 * REMAINING DISCRIMINATOR, which needs no rig: send DT1 phantom records
 * to channels 0x24 and 0x25 in turn and read the box's own re-broadcast
 * back. If 0x25 moves, this row is 0 and phantom is per channel on the
 * wire too.
 *   [DISPUTED — EVIDENCED (executed trace) against EVIDENCED (image, S-1608
 *   FUN_0c002d42 + FUN_0c007fbc). Unresolved.]
 */
#define REAC_HEADAMP_GRAN_PHANTOM_SHIFT 2

/* HARDWARE ACTUATION IS PER CHANNEL, for phantom, pad and sens alike.
 * FUN_0c007fbc's loop passes a per-channel index and that slot's own
 * value to each of the three writers on every one of its eight
 * iterations. This is the number that says what one write switches, and
 * it is the axis the three old "granularity" rows never had.
 *   [EVIDENCED (image, S-1608 FUN_0c007fbc -> FUN_0c00ac1e / FUN_0c00ac96 /
 *   FUN_0c007e6a).]
 */
#define REAC_HEADAMP_ACTUATION_SHIFT    0

/* THE PER-EIGHT GRANULARITY, and there is only one of them. This row
 * folds together what used to be two — "the hardware bank" and "the
 * readback nibble is per eight" — because they are arithmetically the
 * same thing and were being read as two independent pieces of evidence.
 *
 * FUN_0c007fbc sets its cursor to `group << 3` and loops exactly eight
 * times, so group g covers [g*8, g*8+8) and therefore `g == ch >> 3` —
 * which is the readback nibble's own index. One axis, two spellings:
 * this width 8 and HEADAMP_BANK_SHIFT's 3.
 *
 * It is a REFRESH AND READBACK banking, not an actuation width: the
 * writers take (bank, 0..7) and each of the eight iterations writes one
 * channel. Two banks of eight cover an S-1608's sixteen analog inputs.
 *   [EVIDENCED (image) — S-1608 FUN_0c007fbc for the loop and the per-channel
 *   writes; its caller, recovered 2026-08-23 from a function Ghidra never
 *   disassembled (clean prologue past the previous function's rts, absent
 *   from the 1395-entry map, reached by a plain bsr), for `group == ch >> 3`.
 *   Supersedes the earlier UNRESOLVED note that the caller could not be
 *   traced.]
 */
#define REAC_HEADAMP_BANK_CHANNELS      8

/* `ch >> 3` gives the bank/group index. THE SAME FACT AS
 * HEADAMP_BANK_CHANNELS above, spelled as a shift instead of a width —
 * consult one or the other, never both as corroboration.
 *
 * It was called HEADAMP_GRAN_READBACK_SHIFT and sat beside the bank row
 * as if the readback were a third, independent granularity. It is not:
 * the apply loop's group index and the readback nibble are the same
 * `ch >> 3` over the same 80 slots.
 *   [EVIDENCED (executed trace for the readback nibble; image for the apply
 *   loop's identical index — S-1608 FUN_0c007fbc and its caller). The two
 *   agree, which is why they are one row.]
 */
#define REAC_HEADAMP_BANK_SHIFT         3

/* Every real desk sweep is ONE contiguous pass over the box's full declared
 * width, every channel getting all three parameters — 24 records for an
 * S-0808, 48 for an S-1608, 96 for an S-4000S. No desk addresses a bank,
 * splits a sweep or repeats one. [EVIDENCED (corpus) — 31 of 47 captures,
 * three desk generations agreeing on the same box.]
 */
#define REAC_HEADAMP_SWEEP_RECORDS_PER_CH 3

/* ---- The SENS step -> sensitivity curve ----------------------------------------
 * One decibel per step, over all 56 steps, with no duplicates anywhere.
 * Sensitivity runs -10 dBu at 0x00 down to -65 dBu at 0x37 with the pad off,
 * and the pad shifts the whole travel up by 20 dB:
 *
 *   sensitivity_dBu = -10 - value + (pad ? 20 : 0)
 *
 * MEASURED 2026-08-23, S-0808, output 1 cabled to input 1 so the source is an
 * electrical loopback of a level we generated and therefore know — not a
 * microphone in a room, which is what produced the third and wildest of the
 * readings this replaces. All 56 steps at three generator levels whose ranges
 * overlap and agree to 0.05 dB where they meet. Span 54.60 dB against the
 * 55.00 a flat 1 dB implies; least-squares slope 0.988 dB/step with a maximum
 * residual of 0.44 dB, which is the size of the measurement's own scatter, so
 * the law declared here is the round decibel and not the fitted 0.988. The pad
 * measured 20.12 and 20.20 dB at two different steps — the check that this dB
 * axis is the box's own.
 *
 * THE FIRMWARE HOLDS THE CURVE AS A TABLE, and here it is. S-1608.BIN at
 * 0x0c0327a0, 56 entries of two bytes, read by FUN_0c007e30 which clamps
 * the step to 0x37 and hands the pair to the preamp writer FUN_0c00af2a.
 * In the S-1608 image the table ends exactly where the ASCII version banner
 * "V03.05" begins, which is how we know its extent is 56 and not a run of
 * padding.
 *
 * The same 112 bytes appear in S-0808.BIN at file offset 0x45ec8. THAT IS A
 * RAW BYTE MATCH AND NOTHING MORE: there is no S-0808 decompilation, the
 * image is not a code image loadable at the S-1608's base, and its own
 * pointers are a different width and order (big-endian 0x0003xxxx). The
 * banner control above does NOT apply there — S-0808 has zero padding after
 * the table, not a banner. Nothing in this group is sourced from S-0808
 * disassembly; the byte match corroborates the table's content across two
 * models and the reading of it comes from the S-1608 alone.
 *
 *   step stage fine step stage fine step stage fine step stage fine
 *   0x00 3 0x00 0x0e 2 0x0c 0x1c 1 0x08 0x2a 0 0x04
 *   0x01 3 0x02 0x0f 2 0x0e 0x1d 1 0x0a 0x2b 0 0x06
 *   0x02 3 0x04 0x10 2 0x10 0x1e 1 0x0c 0x2c 0 0x08
 *   0x03 3 0x06 0x11 2 0x12 0x1f 1 0x0e 0x2d 0 0x0a
 *   0x04 3 0x08 0x12 2 0x14 0x20 1 0x10 0x2e 0 0x0c
 *   0x05 3 0x0a 0x13 2 0x16 0x21 1 0x12 0x2f 0 0x0e
 *   0x06 3 0x0c 0x14 2 0x18 0x22 1 0x14 0x30 0 0x10
 *   0x07 3 0x0e 0x15 2 0x1a 0x23 1 0x16 0x31 0 0x12
 *   0x08 2 0x00 0x16 2 0x1c 0x24 1 0x18 0x32 0 0x14
 *   0x09 2 0x02 0x17 2 0x1e 0x25 1 0x1a 0x33 0 0x16
 *   0x0a 2 0x04 0x18 1 0x00 0x26 1 0x1c 0x34 0 0x18
 *   0x0b 2 0x06 0x19 1 0x02 0x27 1 0x1e 0x35 0 0x1a
 *   0x0c 2 0x08 0x1a 1 0x04 0x28 0 0x00 0x36 0 0x1c
 *   0x0d 2 0x0a 0x1b 1 0x06 0x29 0 0x02 0x37 0 0x1e
 *
 * HOW TO READ IT. The two bytes are not decibels — they are two hardware
 * registers. `stage` is a two-bit coarse range: FUN_0c00af2a drives it onto
 * a pair of GPIO pins per channel, so it is an analog range switch, and
 * FUN_0c007f20 compares ONLY this byte between two steps, which is a
 * "does this change need the range to move" test. `fine` is a serial gain
 * code, clamped to 0x24 by the writer, and it steps by exactly 2 for every
 * step of the SENS index, everywhere in the table with no exception.
 *
 * WHAT THE TABLE PROVES, AND WHAT IT DOES NOT. It proves the shape: the
 * step is UNIFORM within a range, so any departure from a flat law can only
 * live at the three range breaks, which fall between steps 0x07/0x08,
 * 0x17/0x18 and 0x27/0x28. It does not carry a decibel — the dB per fine
 * LSB and the dB of each range tap are analog component values, in the
 * preamp and not in the image.
 *
 * The stages begin at index 0, 8, 24 and 40, and the fine field restarts at
 * zero at each. That placement is itself a statement: a break sits exactly
 * where the fine field would run out, so the designer intended the ranges
 * to abut with no gap and no overlap. Take the fine LSB as the usual half
 * decibel and the whole table reads out as gain_dB = step, 0 through 55,
 * with the range taps at 0, 8, 24 and 40 dB. That is the round law, and the
 * table is its decomposition into two registers.
 *
 * SO THE LAW IS THE FIRMWARE'S TABLE AND 54.60 IS A MEASUREMENT OF IT. The
 * two are not rival claims about the same quantity. The deficit is 0.40 dB
 * over 55 steps against a sweep whose own maximum residual was 0.44 dB, so
 * the measurement cannot separate 54.60 from 55.00 and does not contradict
 * it. What the rig DID settle, and the table could not, is that the three
 * range breaks are continuous: A/B/A gave +0.92/+1.12, +1.36/+1.31 and
 * +0.97/+0.84 dB at exactly the three indices the table puts them at. That
 * is the firmware's structure and the rig's numbers agreeing on the same
 * three places, which is the strongest form this fact can take.
 *
 * WHAT THIS SETTLES, because it was the schema's one openly contested number.
 * Three readings were live: reac.ksy and reac-pw both spelled the flat 1 dB
 * law, which is how a number nobody had measured came to look confirmed by two
 * sources; libreac carried a 56-entry firmware curve spanning 48.75 dB whose
 * stage breaks at 8, 24 and 40 made three pairs of steps deliver IDENTICAL
 * gain, so the map was not injective and a round trip through it was a
 * different function; and a rig measurement of 1.235 dB/step, since shown to
 * be an artefact of its acoustic source.
 *
 * The twins were the discriminating test and they were run: each pair by rapid
 * A/B/A alternation, twice, at two generator levels, so residual drift shows
 * as a mismatch between the A readings.
 *
 *   7 -> 8 +0.92 and +1.12 dB drift control 0.08 / 0.10 dB
 *   23 -> 24 +1.36 and +1.31 dB drift control 0.34 / 0.15 dB
 *   39 -> 40 +0.97 and +0.84 dB drift control 0.26 / 0.08 dB
 *
 * Every pair steps by about a decibel, an order of magnitude outside its own
 * control. The firmware's four coarse stages are real; gain being continuous
 * across their breaks was an inference from that structure and it is refuted.
 *
 * THE ANCHOR, stated honestly because half of it is not measured here. A
 * loopback measures the SPAN exactly — 54.60 dB between the endpoints, which
 * is what discriminates 48.75 from 55.00 — but the absolute dBu of either
 * endpoint needs one constant this experiment cannot separate: the box's own
 * converter reference, the dBu it puts out at 0 dBFS and the dBFS its
 * sensitivity spec refers to. The loop measures their SUM. So -10 dBu at step
 * 0 is carried over unchanged from every source that already agreed on it, and
 * -65 at 0x37 is what the measured span then makes it. Raw data:
 * reac-pw docs/measurements/sens-sweep-2026-08-23-*.csv.
 */
/* Step 0x00 with the pad off, in hundredths of a dBu — the least sensitive
 * setting and the reference the whole travel hangs off. [INFERRED — agreed by
 * every prior reading and not independently measurable through a loopback,
 * which sees only this plus the box's converter reference. The SPAN below is
 * what was measured.]
 */
#define REAC_HEADAMP_SENS_REF_CDB       -1000

/* One decibel, every step, all 55 transitions. The number that was disputed,
 * and the one thing a consumer cannot get wrong quietly. [EVIDENCED (image +
 * rig). Image — the S-1608 table at 0x0c0327a0 steps
 * its fine register by exactly 2 for every SENS step with no exception,
 * so the law is uniform inside each of its four ranges and can only
 * break at three indices. Rig — the 2026-08-23 loopback sweep of all 56
 * steps, span 54.60 dB, slope 0.988, and A/B/A at each of those three
 * indices giving about a decibel against controls of 0.08 to 0.34 dB.
 * The 0.40 dB the span falls short is inside that sweep's own 0.44 dB
 * maximum residual, so it does not stand against the table.
 * ]
 */
#define REAC_HEADAMP_SENS_STEP_CDB      100

/* Entries in the firmware's SENS table, steps 0x00..0x37. The writer
 * FUN_0c007e30 clamps anything above 0x37 to 0x37, so 0x37 is the top of the
 * travel and not merely the last one observed. [EVIDENCED (image, S-1608
 * 0x0c0327a0 = file 0x527a0; the same 112 bytes at S-0808 file 0x45ec8 as a
 * raw byte match, not a disassembly — there is no S-0808 decompilation).]
 */
#define REAC_HEADAMP_SENS_STEPS         56

/* Coarse analog ranges the table selects between, driven onto two GPIO pins
 * per channel by FUN_0c00af2a. [EVIDENCED (image).]
 */
#define REAC_HEADAMP_SENS_STAGES        4

/* First step of the second range. The three breaks are the only places a
 * uniform step could fail, and the rig measured all three at about a decibel.
 * [EVIDENCED (image + rig).]
 */
#define REAC_HEADAMP_SENS_STAGE_BREAK_1 0x08

/* First step of the third range. [EVIDENCED (image + rig).] */
#define REAC_HEADAMP_SENS_STAGE_BREAK_2 0x18

/* First step of the fourth range. [EVIDENCED (image + rig).] */
#define REAC_HEADAMP_SENS_STAGE_BREAK_3 0x28

/* The pad's 20 dB, in hundredths, added to the sensitivity when it is on.
 * Independent of the step, and it earns its place here by being the one
 * number in this group whose absolute value the loopback DOES measure.
 * [EVIDENCED (rig) — 20.12 and 20.20 dB by A/B/A at steps 0x37 and 0x28,
 * against pad-off controls of 0.11 and 0.16 dB.]
 */
#define REAC_HEADAMP_PAD_CDB            2000

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
