# GENERATED FILE - DO NOT EDIT.
#
# Source:    spec/protocol-facts.yaml   (in FreeREAC/reac-protocol)
# Generator: spec/gen-facts.py
#
# Edit the schema and regenerate. A hand-edit here is erased by the next run
# and, worse, is invisible to the cross-check that keeps reac.ksy and libreac
# agreeing - which is the whole reason this file is generated.

# The same constants reac.ksy's grammar and libreac's headers spell, as a
# standalone Kaitai type. It parses nothing: every constant is a value-only
# instance, so `meta: imports: [reac_facts]` makes them available by name
# without changing a byte of any grammar that imports it.
meta:
  id: reac_facts
  title: REAC protocol constants, shared by reac.ksy and libreac
  license: GPL-3.0-or-later
  endian: be
seq: []
instances:
  # ---- Frame geometry ----
  ethertype:
    value: 0x8819
    doc: |
      REAC's registered non-IP EtherType. [EVIDENCED (corpus) — every frame
      in 72 captures.]
  l2_header_len:
    value: 50
    doc: |
      14 eth + 2 counter + 2 type word + 32 control block. [EVIDENCED
      (corpus).]
  audio_offset:
    value: 50
    doc: |
      Where the audio region starts. Same number as the header length, and
      it is the same fact. [EVIDENCED (corpus) — a golden offset scan
      decodes real desk program as noise at every other offset.]
  hdr_counter_off:
    value: 14
    doc: |
      u16 LITTLE-endian free-running sequence counter, against the
      big-endian everything else. [EVIDENCED (corpus).]
  frame_overhead:
    value: 52
    doc: |
      The non-audio bytes of any frame — 50 header + 2 end marker. The 52 in
      `52 + n*36`. [EVIDENCED (corpus).]
  pace_is_the_masters:
    value: True
    doc: |
      The master sets the pace and the slaves follow it unconditionally.
      There is no
      per-rate cadence negotiation, no slave-side rate election, and no case
      in which a box
      declines a pace. So a frame rate is read off the master's clock, never
      inferred from
      a box's model or its declaration.
      Consequence for our own docs: statements of the form "the upstream
      cadence at rate R
      is X" describe what the master chose, not a property the box asserts.
        [RULED (operator, 2026-08-23). Consistent with the corpus, which
        shows one pace per
      segment and no negotiation exchange.
      ]
  rate_is_independent_of_model:
    value: True
    doc: |
      A clock rate is NOT a property of a mixer model. Any legal pace may
      run on any desk,
      and the two facts must never be derived from one another.
      This is stated because our corpus makes them look coupled: each desk
      we own has been
      run at a single rate, so model and rate are perfectly correlated in
      the captures. That
      correlation is an accident of how the rig was used, not a fact about
      the protocol, and
      anything reading a per-desk field as a rate class must justify it on
      its own evidence.
        [RULED (operator, 2026-08-23) — LAW. Not an inference from the
        corpus, and it overrides
      any correlation the corpus appears to show.
      ]
  console_field_gates_rate:
    value: True
    doc: |
      The config-announce console_field byte (cfea[19]) gates the box's
      drivable rate CLASS.
      0x00 = V-Mixer (M-200 / M-300), capped at 44.1/48 kHz; 0x01 = OHRCA
      (M-5000), which alone
      reaches 96 kHz. The box FOLLOWS the byte the master emits, so driving
      a box at 96 kHz
      REQUIRES emulating OHRCA (0x01); a V-Mixer byte holds it at 48 kHz.
      This does NOT contradict RATE_IS_INDEPENDENT_OF_MODEL — it is the
      specific,
      evidence-justified case that ruling anticipated ("anything reading a
      per-desk field as a
      rate class must justify it on its own evidence"). The rate is still
      the master's choice
      (PACE_IS_THE_MASTERS); console_field is the wire byte by which the
      master DECLARES the
      class, and the family label (V-Mixer / OHRCA) is only its name. What
      is independent of a
      mixer MODEL is a bare clock number; what gates the class is this one
      announced byte.
      44.1 kHz has NO distinct value — the field is binary — so it maps to
      0x00 and the box
      runs 48 kHz; 44.1 is a graph/RME rate, not a REAC-wire rate.
        [RIG-VERIFIED (2026-08-27): emitting 0x00 ran the live box at 48 kHz
        and 0x01 at 96 kHz,
      with a warm follow on a live change; box frames stayed byte-identical
      between the two,
      the master byte the only differing field. LOGIC: an M-5000 running its
      own box at 48 kHz
      must emit 0x00, so the byte is the rate class, not merely the console
      generation. Operator
      ruling (2026-08-27): only OHRCA drives 96 kHz; V-Mixer is 48
      kHz-limited (M-300 @ 96 k
      impossible). The 44.1 kHz mapping is DERIVED from the field being
      binary, NOT wire-
      captured — no desk at 44.1 on the wire (see BYTES_PER_CHANNEL and
      unknowns-census).
      ]
  bytes_per_channel:
    value: 36
    doc: |
      12 samples x 3 bytes, per channel, at EVERY sample rate. The 36 in `52
      + n*36`. [EVIDENCED (corpus) at 48k and 96k; RATE-INVARIANT BY
      CONSTRUCTION (12 x 3).
      44.1k is DERIVED, not observed: measuring pps straight from the pcap
      timestamps puts
      NOTHING in the 3675 band, while cleanly separating the 48k and 96k
      files. The earlier
      wording claimed corpus evidence across 44.1k and did not have it.
      ]
  samples_per_pkt:
    value: 12
    doc: |
      Samples per channel per frame. The RATE is the packet rate; the frame
      does not change shape with it. [EVIDENCED (corpus).]
  resolution:
    value: 3
    doc: |
      Bytes per sample per channel — 24-bit. [EVIDENCED (corpus).]
  max_channels:
    value: 40
    doc: |
      The downstream audio fabric, 40 slots. NOT the head-amp channel space,
      which is 48 wide; conflating the two was a real bug. [EVIDENCED
      (corpus).]
  frame_bytes:
    value: 1492
    doc: |
      The fixed downstream broadcast — 52 + 40*36. [EVIDENCED (corpus).]
  audio_bytes:
    value: 1440
    doc: |
      40 ch x 12 samples x 3 B. [EVIDENCED (corpus).]
  fcs_residue:
    value: 2
    doc: |
      The two bytes a mirrored/SPAN capture leaves on the end of a frame.
      EXPLAINED, STRIPPED, NEVER MODELLED — and load-bearing twice: it is
      how mirrored duplicates are told apart (by GEOMETRY, never by
      comparing bytes), and a truncated capture whose residue happens to
      fit makes a short frame look like a legal narrower one.
        [EVIDENCED (corpus).]
  end_marker_0:
    value: 0xc2
    doc: |
      First byte of the two-byte end marker. [EVIDENCED (corpus).]
  end_marker_1:
    value: 0xea
    doc: |
      Second byte of the end marker. [EVIDENCED (corpus).]
  # ---- The 32-byte control block and its two checksums ----
  ctrl_block_off:
    value: 18
    doc: |
      Frame offset of the control block. [EVIDENCED (corpus).]
  ctrl_block_end:
    value: 50
    doc: |
      One past the end — and therefore the audio offset. [EVIDENCED
      (corpus).]
  ctrl_block_len:
    value: 32
    doc: |
      The checksummed span. [EVIDENCED (corpus).]
  ctrl_cksum_off:
    value: 49
    doc: |
      The checksum byte, last of the block. Block-relative 31. [EVIDENCED
      (corpus).]
  ctrl_cksum_off_in_block:
    value: 31
    doc: |
      The same byte, block-relative — what a caller stamping a bare 32-byte
      block indexes. [EVIDENCED (corpus).]
  ctrl_block_sum:
    value: 0x00
    doc: |
      Sum(block[0..31]) mod 256 must equal this. [EVIDENCED (corpus) — every
      control frame in the corpus.]
  ctrl_record_sum:
    value: 0x80
    doc: |
      Sum(record TAG..CKSUM) mod 256 must equal this. The Roland DT1 rule,
      and NOT the block rule. [EVIDENCED (corpus).]
  typed_block_off:
    value: 16
    doc: |
      Frame offset of the type word — the start of the [16:50] window the
      goldens store and the C tests use. [EVIDENCED (corpus).]
  typed_block_len:
    value: 34
    doc: |
      Type word (2) + control block (32). [EVIDENCED (corpus).]
  # ---- Type-word codes ----
  type_filler:
    value: 0x0000
    doc: |
      Audio-only, no control op, checksum-exempt. [EVIDENCED (corpus).]
  type_control:
    value: 0xcdea
    doc: |
      A control record. [EVIDENCED (corpus).]
  type_announce:
    value: 0xcfea
    doc: |
      The master announce. Same block shape, op always 0xffff. [EVIDENCED
      (corpus).]
  # ---- Control ops ----
  op_scene_chunk:
    value: 0x0100
    doc: |
      A continuation chunk of the scene transfer. [EVIDENCED (image +
      corpus).]
  op_scene_header:
    value: 0x0101
    doc: |
      The scene header, declaring the total. [EVIDENCED (image + corpus).]
  op_scene_final:
    value: 0x0102
    doc: |
      The final chunk. The box's commit is gated on it. [EVIDENCED (image +
      corpus).]
  op_page_0103:
    value: 0x0103
    doc: |
      Class 1 carried whole in one frame — the fragment field is 3, both
      FIRST and LAST. payload[0] is the only discriminator; op_len beside it
      is a length, not a second selector. See the control_header group.
      [EVIDENCED (image + executed trace).]
  op_dt1_first_fragment:
    value: 0x0401
    doc: |
      Link 4 with the segment field reading FIRST — the opening fragment of
      a DT1 record too long for one frame. Previously carried as "the ASCII
      model-name frame", which is what its one observed use holds.
      [EVIDENCED (image + corpus) — the segmentation rule is FUN_0c003398
      @0c003398 (S-1608); the pairing is proved by the DT1 checksum, which
      closes only across both fragments.]
  op_dt1_last_fragment:
    value: 0x0402
    doc: |
      The same record's closing fragment, carrying the inner checksum and
      the SysEx terminator. Previously carried as "the extra cold-connect
      frame some models send". [EVIDENCED (image + corpus).]
  op_dt1_container:
    value: 0x0403
    doc: |
      A record container — a Roland DT1 SysEx, or the box's upstream return
      block. Discriminated by payload[0]. [EVIDENCED (corpus).]
  op_announce:
    value: 0xffff
    doc: |
      The op a cfea announce always carries. [EVIDENCED (corpus).]
  # ---- The control block's header, as the firmware builds it ----
  hdr_link_off:
    value: 0
    doc: |
      block[0] — the link selector. [EVIDENCED (image) — every builder
      writes it first.]
  hdr_seg_off:
    value: 1
    doc: |
      block[1] — the segment flags. [EVIDENCED (image).]
  hdr_len_off:
    value: 2
    doc: |
      block[2:4] — the big-endian length. [EVIDENCED (image).]
  hdr_opcode_off:
    value: 4
    doc: |
      block[4] — the opcode, and the base the length counts from on every
      family except a link-1 bulk transfer. [EVIDENCED (image) —
      FUN_0c002c70 @0c002c70 writes 25 for eight three-byte records at
      block[5:29], and 25 = 1 + 8*3.]
  seg_first_bit:
    value: 0x01
    doc: |
      block[1] bit 0 — the frame opens a transfer and carries its total.
      [EVIDENCED (image).]
  seg_last_bit:
    value: 0x02
    doc: |
      block[1] bit 1 — the frame closes a transfer. [EVIDENCED (image).]
  seg_single:
    value: 0x03
    doc: |
      Both bits — a complete message in one frame, which is what every
      chanmap, heartbeat, declaration and single-frame record is. [EVIDENCED
      (image + corpus).]
  link_control:
    value: 0x01
    doc: |
      The stagebox control link — the scene transfer, the chanmap, the
      heartbeat and the declarations. [EVIDENCED (image + corpus).]
  link_aux_s4000s:
    value: 0x02
    doc: |
      A second link the S-4000S image builds for and the S-1608 image has no
      code for at all. [EVIDENCED (image) — FUN_0c0128b8 @0c0128b8
      (S-4000S). NEVER OBSERVED on the wire.]
  link_record:
    value: 0x04
    doc: |
      The record link — the Roland DT1 container and its two fragments.
      [EVIDENCED (corpus).]
  seg_first_payload_off:
    value: 7
    doc: |
      A link-1 bulk FIRST frame puts its declared total at block[5:7] and
      its payload at block[7]. [EVIDENCED (image + corpus).]
  seg_cont_payload_off:
    value: 5
    doc: |
      Every other bulk frame puts its payload at block[5]. [EVIDENCED (image
      + corpus).]
  seg_first_max:
    value: 24
    doc: |
      24 — the largest first-frame chunk, and exactly 31 - 7. The builder
      reserves block[31] for the checksum. [EVIDENCED (image) — FUN_0c003398
      @0c003398.]
  seg_cont_max:
    value: 26
    doc: |
      26 — the largest continuation chunk, and exactly 31 - 5. [EVIDENCED
      (image).]
  ctrl_reclen_base:
    value: 4
    doc: |
      The block offset the length counts from, INCLUSIVE — for every class
      and subtype except one. A sister branch published this as universal;
      it is not, and the exception is the commonest record on the wire.
      See RECLEN_BULK_EXCEPTION.
        [EVIDENCED (image + corpus).]
  reclen_bulk_exception:
    value: 0x00
    doc: |
      The one subtype whose length does NOT count from block[4]: the
      session-class bulk transfer. Its length is THIS FRAGMENT'S PAYLOAD
      ONLY, at block[7] on a FIRST fragment and block[5] on any other.

      The scene body is 8904 bytes and arrives as 0x18 + 341 x 0x1a + 0x0e
      = 24 + 8866 + 14. Under a base of 4 the payloads would be 21 and 25,
      and 8904 - 21 - 14 = 8869 is not a multiple of 25 — the transfer
      cannot be reassembled under that reading at all. The box's own sender
      passes the chunk size both to the length store and to the memcpy that
      fills block+7 or block+5.
        [EVIDENCED (image, S-1608 FUN_0c003398 @0c003398) + the reassembly
        arithmetic, asserted both ways in spec/reac_xcheck.py.]
  # ---- The chanmap's three-byte record and the table it writes ----
  chanmap_rec_bytes:
    value: 3
    doc: |
      slot, flags, value. [EVIDENCED (image + corpus).]
  chanmap_recs_per_frame:
    value: 8
    doc: |
      One window of the ring per frame. [EVIDENCED (image + corpus).]
  chanmap_ring_len:
    value: 49
    doc: |
      48 slots plus the one non-channel record id, which the box's cursor
      emits as index 0x30 before wrapping to 0. [EVIDENCED (image +
      corpus).]
  slot_space:
    value: 48
    doc: |
      48 — the protocol slot space, the present-bit array length and the
      fully-enrolled sum. Identical in the S-1608 and S-4000S images, so it
      is a protocol constant and not a per-model one. [EVIDENCED (image,
      both boxes).]
  slot_record_stride:
    value: 10
    doc: |
      The per-slot table's stride, in the chanmap apply, in the scene commit
      and in the scene store alike. [EVIDENCED (image, both boxes).]
  slot_table_records:
    value: 80
    doc: |
      80 — the table is 80 records long though only the first 48 are
      addressable from the wire. [EVIDENCED (image, both boxes).]
  slot_cell_value:
    value: 2
    doc: |
      Table offset the record's VALUE byte writes — the cell the gain path
      reads. [EVIDENCED (image) — FUN_0c007fbc @0c007fbc feeds it to
      FUN_0c007e6a @0c007e6a.]
  slot_cell_flag_bit3:
    value: 4
    doc: |
      Table offset written from flags bit 3. [EVIDENCED (image).]
  slot_cell_flag_bit1:
    value: 6
    doc: |
      Table offset written from flags bit 1 — the one the group apply
      shadows and never actuates. [EVIDENCED (image).]
  slot_cell_flag_bit2:
    value: 8
    doc: |
      Table offset written from flags bit 2. [EVIDENCED (image).]
  chanmap_cell_mask:
    value: 0xf0
    doc: |
      The mask the builder ANDs with `cell << 4`, so the cell code is a full
      four bits. Read out of the image at DAT_0c002d7c. [EVIDENCED (image).]
  chanmap_id_identity:
    value: 0xfe
    doc: |
      The non-channel record whose FLAGS byte reaches the box's one-word
      identity cell and its change detector. Read out of the image at
      DAT_0c002d7e and DAT_0c002e6e. [EVIDENCED (image + corpus) — 3804 in
      the corpus.]
  chanmap_id_filler:
    value: 0xff
    doc: |
      The all-zero record the builder emits past the sentinel. Read out of
      the image at DAT_0c002d80. [EVIDENCED (image). NEVER OBSERVED — the
      cursor wraps at 0x30, so the branch is unreachable on that path.]
  # ---- The state-4 commit — what it flushes ----
  commit_slot_table_entries:
    value: 80
    doc: |
      Slots copied staging -> active by the commit, unconditionally. Eighty,
      not forty-eight — the box's addressable channel space is 48 (the slot
      map ingest gates slot < 0x30) but the table it lives in is 80 deep and
      the head-amp apply walks ten groups of eight over it.
        [EVIDENCED (image, S-1608 FUN_0c003c8a + S-4000 same loop).]
  commit_slot_record_bytes:
    value: 10
    doc: |
      Stride of the staging and active slot tables. Fields +2 sens, +4/+6/+8
      the three per-slot booleans; +0 is not copied and is read at four-slot
      stride as the group's inventory cell. [EVIDENCED (image, S-1608
      FUN_0c003c8a + FUN_0c002d42).]
  commit_master_id_bytes:
    value: 6
    doc: |
      The granted master's identity, copied staging -> active by the commit.
      Zeroed on link loss by FUN_0c003a64; a mismatch against the observed
      master forces the FSM to state 0 (FUN_0c0045ec), which is why a
      takeover resets the box's head-amp. [EVIDENCED (image).]
  headamp_apply_group_channels:
    value: 8
    doc: |
      The head-amp hardware apply FUN_0c007fbc(bank, group) walks EIGHT
      slots, `group << 3`, for group 0..9. This is the geometry that
      actually reaches hardware, and it is a different axis from the
      four-channel inventory cell. Confusing the two is how "twelve
      phantom groups" got written down.
        [EVIDENCED (image, S-1608 FUN_0c007fbc).]
  headamp_apply_groups:
    value: 10
    doc: |
      Groups of eight the apply accepts, 0..9, covering the 80-slot active
      table. [EVIDENCED (image, S-1608 FUN_0c007fbc).]
  # ---- op-0103 sub-pages and subtypes ----
  len_sub_chanmap:
    value: 0x0019
    doc: |
      Record length of the master's slot-map window — the subtype byte plus
      eight 3-byte slot records. S-1608 FUN_0c002c70 builds it.
        [EVIDENCED (corpus).]
  len_sub_commit_report:
    value: 0x0010
    doc: |
      Record length of the box's state-4 commit report — the subtype byte,
      two zero bytes, the board-configuration code, twelve inventory cells.
      S-1608 FUN_0c003c8a builds it; S-4000 has the same shape.
        [EVIDENCED (corpus).]
  len_sub_enroll_group_map:
    value: 0x000d
    doc: |
      Record length of the master's prepare-to-grant frame. [EVIDENCED
      (image + corpus).]
  len_sub_link_ack:
    value: 0x0001
    doc: |
      Record length of the box's link-check ack — the subtype byte and
      nothing else. S-1608 FUN_0c003fe2 builds it, from scene-FSM state 7.
        [EVIDENCED (corpus).]
  sub_0103_off:
    value: 4
    doc: |
      Block offset of the subtype selector — payload[0]. [EVIDENCED
      (executed trace).]
  sub_0103_scene:
    value: 0x00
    doc: |
      Subtype 0 — scene. A scene frame requires this byte to be zero and the
      box refuses the frame otherwise. [EVIDENCED (executed trace, image).]
  sub_0103_slot_map:
    value: 0x01
    doc: |
      Subtype 1 — the master's SLOT MAP, eight 3-byte records to a frame.
      This group used to call it "head-amp" and reac.ksy calls the same
      frame the chanmap; both names are half of it. The box's ingest
      FUN_0c002d42 splits each record three ways: the high nibble of byte 1
      is the inventory cell for the group this slot anchors and is consumed
      only where (slot & 3) == 0; bits 3, 2 and 1 of byte 1 are three
      per-slot booleans; byte 2 is the SENS step, and it lands in the same
      active-table field the head-amp apply FUN_0c007fbc reads back. So it
      IS a channel map and it DOES carry head-amp state.
        [EVIDENCED (image, S-1608 FUN_0c002d42 + FUN_0c002bb2).]
  sub_reply_bit:
    value: 0x80
    doc: |
      Bit 7 of the subtype marks a record travelling BOX -> MASTER. Every
      box-built subtype has it (0x81 the link ack, 0x80/0x82/0x83/0x84 the
      commit report) and no master-built one does (0x00 scene, 0x01 slot
      map, 0x10 enroll group map).
        [EVIDENCED (image + corpus).]
  sub_0103_link_ack:
    value: 0x81
    doc: |
      The box's link-check ack, S-1608 FUN_0c003fe2, from scene-FSM state 7.
      It was called SLAVE_ANNOUNCE4 in the inherited dissector. [EVIDENCED
      (image + corpus).]
  sub_0103_enroll_group_map:
    value: 0x10
    doc: |
      The master's prepare-to-grant frame, once about 1.6 s before the grant
      burst. [EVIDENCED (corpus).]
  sub_0103_commit_report:
    value: 0x82
    doc: |
      The box's state-4 COMMIT REPORT — NOT a slave announce, which is what
      reacdriver called it and what our dissector repeated until
      2026-08-23. S-1608 FUN_0c003c8a builds it after promoting staging to
      active, and it is reached only from state 4 of the scene FSM
      FUN_0c0037ee, i.e. after the master's scene transfer has completed.

      0x82 IS THE S-1608'S NUMBER, NOT THE PROTOCOL'S, and a consumer must
      not match on it. The builder picks between two model-specific
      literals on a link-state test: S-1608 0x82 linked (DAT_0c00401c) and
      0x80 otherwise (DAT_0c00401e); S-4000 0x84 linked (DAT_0c013750) and
      0x83 otherwise (DAT_0c013752). What selects the second arm used to be
      recorded here as UNEXPLAINED and now is not: on the S-1608 it is
      FUN_0c00f9f2 returning something other than 1, which happens whenever
      the peer-declared word is unset or the link word is not 1. Observed
      on the wire: S-1608 0x82, S-0808 and S-4000S both 0x84. Match the
      family with SUB_REPLY_BIT, not the literal.
        [EVIDENCED (image, S-1608 FUN_0c003c8a + S-4000 same shape; corpus,
        three box models).]
  sub_0103_declaration_alt:
    value: 0x80
    doc: |
      The commit report's OTHER subtype. FUN_0c003c8a @0c003c8a picks
      between two literal-pool bytes on a predicate, DAT_0c00401c = 0x82
      and DAT_0c00401e = 0x80, both read out of the image; the 0x80 arm
      also forces block[7] to zero. FIRMWARE-ONLY: no capture carries one,
      so what selects it (FUN_0c00f9f2 @0c00f9f2) is unresolved.
        [EVIDENCED (image). NEVER OBSERVED.]
  sub_0103_commit_report_83:
    value: 0x83
    doc: |
      The commit report as some boxes send it. Parsed by the same page; no
      S-1608 code emits it. [EVIDENCED (corpus).]
  sub_0103_commit_report_84:
    value: 0x84
    doc: |
      The commit report from the S-0808 and S-4000S family. No S-1608 code
      emits it either — the S-1608 image holds only 0x82 and 0x80.
      [EVIDENCED (corpus) — 44 frames in 14 captures.]
  sub_0403_off:
    value: 4
    doc: |
      The SAME block position discriminates op-0403's two forms. [EVIDENCED
      (corpus).]
  sub_0403_dt1_record:
    value: 0x00
    doc: |
      A genuine Roland DT1 record. [EVIDENCED (corpus).]
  sub_0403_box_return:
    value: 0x02
    doc: |
      The box's upstream return block — 6.05 million of them in the corpus,
      and the look-alike a naive DT1 dispatch acts on. [EVIDENCED (corpus).]
  # ---- DT1 record tags ----
  dt1_tag_head_mark:
    value: 0x0000
    doc: |
      The mark record a console emits around a head-amp sweep. [EVIDENCED
      (corpus).]
  dt1_tag_join_grant:
    value: 0x0100
    doc: |
      The join/cold-connect state record, body 06 00 XX 00. [EVIDENCED
      (corpus).]
  dt1_tag_head_amp:
    value: 0x0101
    doc: |
      The preamp command — {CH, PARAM, VALUE}. The only tag the classifier
      treats as its own kind. [EVIDENCED (corpus + rig).]
  dt1_tag_box_ready:
    value: 0x0302
    doc: |
      A box-state record in the cold-connect exchange. [EVIDENCED (corpus).]
  dt1_tag_identity:
    value: 0x0500
    doc: |
      The identity page — the 6- and 10-byte inventory bodies, and the ASCII
      model name carried across the 0x0401 / 0x0402 fragment pair.
      [EVIDENCED (corpus).]
  # ---- The identity page (DT1 tag 0x0500) ----
  identity_addr_lo_bytes:
    value: 2
    doc: |
      `addr_lo`, the low half of the address, opens every 0x0500 record
      body. The tag carries the high half, so the full DT1 address is four
      bytes and an emitter that writes only the tag addresses record
      0x0000 by accident.
        [EVIDENCED (corpus) — 1005 records, six distinct addr_lo.]
  identity_addr_bytes:
    value: 4
    doc: |
      The full DT1 address is four bytes — the 2-byte tag plus the 2-byte
      addr_lo that opens every 0x0500 record body. An emitter that writes
      only the tag addresses record 0x0000 by accident.
        [EVIDENCED (corpus + image) — S-1608.BIN carries a 12-byte stride
        DT1 address table at file 0x53154..0x53994, 176 records of {4-byte
        address, u32le, u32le byte count}.]
  identity_addr_firmware_version:
    value: 0x0000
    doc: |
      The system firmware version, 4 bytes, ONE DECIMAL DIGIT PER BYTE,
      most significant first, displayed by Roland as D.DDD.
        [EVIDENCED (corpus + vendor package). S-0808 01 00 00 03 = 1.003 vs
      package s0808_sys_v1003; S-1608 02 02 00 00 = 2.200 vs
      s1608_sys_ver2200; S-4000S 02 05 00 00 = 2.500 vs s4000_sys_ver2500.
      S-1608.BIN corroborates itself twice from the inside: boot banner
      `ECM42 BOOT Ver.2.200` at file 0x200 and the boot-menu version
      literal `2.200` at 0x9254. Capture
      captures/m200i-s0808-48k-mirror__m200-BIDIR-coldboot-2026-07-11.pcap
      frame 3475.
      ]
  identity_addr_capability_block:
    value: 0x0600
    doc: |
      8 bytes, constant per model and identical between the two units of
      each model captured. S-0808 00 00 00 01 00 00 00 00; S-1608
      00 00 00 02 00 03 00 02; S-4000S 00 00 00 02 00 01 00 02. As four
      u16be the second field tracks the REAC port count. The rest is
      UNRESOLVED and is deliberately left as bytes — it is NOT a version in
      the 0x0000 encoding, since the S-1608's boot version 2.200 would read
      02 02 00 00 and appears nowhere in it.
        [EVIDENCED (corpus) — 274 replies, 5 distinct boxes, 3 models.]
  identity_addr_model_name:
    value: 0x1000
    doc: |
      The model name: 1 byte name_kind (0x01 on every observation) then a
      FIXED 16-byte NUL-padded ASCII field. 17 bytes of payload do not fit
      the 36-byte control block, which is the ONLY reason any REAC record
      is fragmented — this record is the whole population of the 0x0401 /
      0x0402 pair.

      ONLY THE S-0808 IMPLEMENTS IT. The S-1608 and S-4000S never answer
      this address, so a console cannot read their model as text and must
      take it from the firmware version plus the config announce's declared
      width.
        [EVIDENCED (corpus + image). 18 fragment pairs in 9 captures, all
      S-0808, inner checksum closing only across both fragments (data sum
      358, 0x1a completes it to 0x80 mod 256). The image agrees with the
      silence: S-1608.BIN's page-0x0500 address table uses
      third-address-byte 0x00..0x08 only — there is no 0x10 or 0x11 entry.
      ]
  identity_name_field_bytes:
    value: 16
    doc: |
      The model-name field is fixed width and NUL-padded — "S-0808" plus ten
      zeros. A reader that stops at the first NUL is right; one that takes
      all 16 bytes as the name is wrong. [EVIDENCED (corpus) — 18
      reassembled records, all identical.]
  identity_rq1_size_bytes:
    value: 1
    doc: |
      An RQ1 body is addr_lo plus ONE byte, the number of bytes wanted.
      A reply MAY BE SHORTER than that: the S-0808 is asked for 9 bytes at
      0x1011 and returns 1. Short is normal, not an error.
        [EVIDENCED (corpus) — 438 RQ1 records, sizes 4, 8, 17 and 9; 19
        one-byte replies at 0x1011.]
  # ---- The scene push ----
  scene_bytes:
    value: 8904
    doc: |
      The declared total, 0x22c8. The box gates its header on this exact
      value. [EVIDENCED (image, both sides) — the same constant resolved out
      of the S-1608's own image and out of the master's.]
  scene_head_bytes:
    value: 24
    doc: |
      Body bytes carried by the op-0101 header, at block[7:31]. [EVIDENCED
      (image + corpus).]
  scene_chunk_bytes:
    value: 26
    doc: |
      Body bytes per op-0100, at block[5:31]. Its declared op_len.
      [EVIDENCED (image + corpus).]
  scene_tail_bytes:
    value: 14
    doc: |
      Body bytes in the op-0102 final. 8880 mod 26 — a length like any other
      chunk's, not a fixed block. [EVIDENCED (image + corpus).]
  scene_chunks:
    value: 341
    doc: |
      op-0100 count for a whole body. [EVIDENCED (corpus) — measured
      back-to-back in 0.680 s on a real M-200i driving an S-1608.]
  scene_steps:
    value: 343
    doc: |
      Header + chunks + final. [derived.]
  scene_op_off:
    value: 0
    doc: |
      Block offset of the op word. [EVIDENCED (image).]
  scene_len_off:
    value: 2
    doc: |
      Block offset of the BE payload length. [EVIDENCED (image) — a
      big-endian 16-bit store from the same variable the master passes to
      the memcpy that fills the payload.]
  scene_sub_off:
    value: 4
    doc: |
      Block offset of the reserved/subtype byte. Zero on every scene step;
      the box refuses the frame otherwise. [EVIDENCED (image + executed
      trace).]
  scene_chunk_pay_off:
    value: 5
    doc: |
      Block offset of a chunk's and the final's body bytes. [EVIDENCED
      (image).]
  scene_head_total_off:
    value: 5
    doc: |
      Block offset of the header's BE declared total. The header's payload
      therefore starts two bytes later than a continuation's. [EVIDENCED
      (image) — `movi20]
  scene_head_pay_off:
    value: 7
    doc: |
      Block offset of the header's 24 body bytes — which is why a capture of
      this frame alone shows the ASCII "1234" that opens the body.
      [EVIDENCED (image + corpus).]
  # ---- What the box validates in the body, and what it reads ----
  scene_tag_id_off:
    value: 0x000
    doc: |
      "1234". Rides the op-0101 header. [EVIDENCED (executed trace) — 2 of
      70 zeroed 128-byte windows break the commit, and they are the two
      containing a tag.]
  scene_tag_sysp_off:
    value: 0x368
    doc: |
      "SYSP". Rides op-0100 chunk 32. [EVIDENCED (executed trace).]
  scene_tag_scen_off:
    value: 0x37c
    doc: |
      "SCEN". Rides op-0100 chunk 33. [EVIDENCED (executed trace).]
  scene_mac_off:
    value: 0x340
    doc: |
      The master's own MAC, INSIDE the body. On-wire identity must equal the
      L2 source, so a master replaying a recovered body substitutes its own.
      [EVIDENCED (image + corpus).]
  scene_revision_off:
    value: 0x014
    doc: |
      The generation byte — 0 on a V-Mixer desk, 1 on an M-5000. One of only
      two fields an emitter fills in. [EVIDENCED (corpus) — 8 of 8904 bytes
      vary across 27 real-desk bodies over three desk generations and four
      box models.]
  scene_slots_off:
    value: 0x01a
    doc: |
      The 80-slot declaration table. [EVIDENCED (image + corpus).]
  scene_slot_count:
    value: 80
    doc: |
      Slots the commit promotes — unconditionally, all of them, with the
      SAME constant. A scene body therefore CANNOT address an individual
      channel. [EVIDENCED (executed trace).]
  scene_slot_bytes:
    value: 10
    doc: |
      The scene record stride. 26 mod 10 = 6 and gcd(26,10) = 2 is the whole
      of the "period-10 probe rotation with a phase step of +6" that was
      read as a master state for a year. [EVIDENCED (image + corpus).]
  scene_unit_map_select:
    value: 0x0001
    doc: |
      Value at +0x04 on every desk generation and against every box. The
      commit branches on it. [EVIDENCED (image + corpus).]
  scene_map_a_arg:
    value: 0x0004
    doc: |
      Value at +0x08 on every capture. What it selects is UNRESOLVED.
      [EVIDENCED (image + corpus).]
  # ---- Head-amp — the record, its wire encoding and its actuation ----
  headamp_tag:
    value: 0x0101
    doc: |
      The DT1 register page for head-amp. [EVIDENCED (corpus).]
  headamp_param_phantom:
    value: 0x00
    doc: |
      +48V, value 0 or 1. WHICH BIT IS PHANTOM AND WHICH IS PAD IS OUR NAME,
      NOT THE FIRMWARE'S — the mapping comes from the corpus and the rig,
      explicitly NOT from the image. [EVIDENCED (corpus + rig).]
  headamp_param_pad:
    value: 0x01
    doc: |
      -20 dB pad, value 0 or 1. [EVIDENCED (corpus + rig).]
  headamp_param_sens:
    value: 0x02
    doc: |
      Sensitivity step. [EVIDENCED (corpus + rig).]
  headamp_sens_max:
    value: 0x37
    doc: |
      55 — the 56th and last entry of the box's own step table, which is
      exactly 56 rows with no spares. What each step is WORTH in dB is the
      headamp_sens group below; this row is only the count. [EVIDENCED
      (image) — a 56-entry table at 0x0c0327a0 in the S-1608 image, reached
      by both write paths, ending exactly where the "V03.05" version string
      begins — in the S-1608 image; the S-0808 copy is a byte match only.
      The count is what that table proves; reading a gain curve off its
      stage structure did not survive the rig.]
  headamp_ch_span:
    value: 0x30
    doc: |
      48 addressable wire channels, 0x00..0x2f. NOT the 40-slot audio fabric
      — a table bounded by 40 silently rejects a 16-input box based at 0x20,
      so its inputs 9..16 can never be given phantom, pad or sens.
      [EVIDENCED (corpus).]
  headamp_gran_sens_shift:
    value: 0
    doc: |
      SENS is per channel — ch >> 0. [EVIDENCED (executed trace).]
  headamp_gran_flags_shift:
    value: 0
    doc: |
      The flag bits are per channel — ch >> 0. [EVIDENCED (executed trace).]
  headamp_gran_phantom_shift:
    value: 0
    doc: |
      PHANTOM IS PER CHANNEL — ch >> 0, exactly like pad and sens. This row
      read 2 and was DISPUTED; it was measured on 2026-08-23 and the 2 is
      withdrawn.

      THE MEASUREMENT. Taken on the live rig 2026-08-23 as phantom-test.pcap
      and filed as
      reacpw-s1608-48k-clean__phantom-ch24-on-off-2026-08-23.pcap in
      ~/Devel/audio/reac-captures-raw/ (it still needs a MANIFEST row and a
      distillation pass before it joins the committed corpus):
      interface enp131s0 (the S-1608 segment), ethertype 0x8819 only,
      snaplen 200, twelve seconds — idle, then phantom set TRUE on head-amp
      CH 0x24, four seconds, then phantom set FALSE on 0x24, nothing else
      touched. 0x24 is box port 5 and the first of the group of four
      0x24..0x27 that the retracted reading claimed one record covers.
      Exactly TWO head-amp records crossed the wire in those twelve seconds
      and both name CH 0x24 ALONE. 0x25, 0x26 and 0x27 never appear. Every
      frame was truncated by the snaplen, so that is a claim to check rather
      than assume: the control block is [18:50] and the record inside it
      [34:40], both inside the 200 bytes, and all 38 control blocks in the
      capture pass the block checksum while both head-amp records pass the
      nested record checksum. Truncation removed audio and nothing the
      verdict rests on.

      THE DISCRIMINATOR THIS ROW USED TO ASK FOR DOES NOT EXIST, which is
      what had kept it stuck. The old note said: write 0x24, write 0x25, and
      read the box's own RE-BROADCAST back. THERE IS NO RE-BROADCAST. The
      S-1608 sent 47122 frames in that capture with ZERO dropped — its
      16-bit frame counter steps by one across all 47121 intervals — and
      every one of them is either an audio frame, whose 16-slot descriptor
      area is a constant `00 7a` per slot and did not move a byte at either
      toggle, or one of twelve bare link-1 opcode-0x81 heartbeats whose
      32-byte block is byte-identical every time. The box volunteers no
      head-amp state whatsoever. Neither does it to a real desk: in
      m200-ch7-ON-OFF-ON-20260721-215743.pcap this same box answers an
      M-200i toggling phantom six times with nothing but its heartbeat. A
      consumer must therefore treat head-amp as WRITE-ONLY on this wire and
      keep its own model; there is nothing to query and compare against.

      SO THE ROW IS SETTLED ON THE AXIS IT ACTUALLY GOVERNS — what a SENDER
      puts on the wire, since a consumer that trusts a 2 emits phantom on
      multiples of four only. Our own master emitting one record for 0x24
      shows what OUR encoder does and nothing about Roland's law, so the
      corpus supplied the desks. Across 3651 phantom records from three desk
      generations — M-200i 00:40:ab:c9:cc:03, M-300 00:40:ab:c9:d8:5b,
      M-5000 00:40:ab:ca:15:4c — 2304 address a channel that is NOT a
      multiple of four. A full S-1608 sweep names 0x20..0x2f, all sixteen;
      an S-0808 names 0x00..0x07; an S-4000S names 0x00..0x1f. The decisive
      single case is m200-ch7-ON-OFF-ON: a real M-200i toggling ONE
      channel's phantom on and off three times, six records, every one of
      them CH 0x26. 0x26 & 3 == 2, so a desk obeying "per four" would have
      had to write 0x24 and could not have expressed that toggle at all.

      THE READING THAT LOSES, AND WHY IT WAS BELIEVED. It was "phantom is
      per group of FOUR, ch >> 2", graded EVIDENCED (executed trace). That
      grade is why the static case was never allowed to flip this row, no
      matter how strong it got: inference does not overturn an observation.
      It is overturned here by MORE observations — more desks, more records,
      and a purpose-built single-channel toggle on a channel that is not a
      group leader. The static read turns out to have been right the whole
      time: there is no per-four gate on the DT1 path anywhere in
      S-1608.BIN. The single channel-indexed `(x & 3) == 0` test in that
      image is FUN_0c002d42's, it gates `flags >> 4` into the two 12-entry
      INVENTORY arrays, and it sits on the SLOT-MAP path, not the head-amp
      path. The per-four number that is real belongs to PORTS_CH_PER_SLOT,
      the inventory cell, and the likeliest history is that a trace of the
      CELL moving was read as phantom moving. The capture is consistent with
      that: the master's slot map reported slot 0x24 after the ON and again
      after the OFF, flags 0x28 and sens 0x00 both times, and across all 48
      channel slots it recorded zero state changes in the whole twelve
      seconds. A phantom write does not touch the slot map.

      WHAT IS STILL NOT MEASURED, so nobody reads more into this than it
      says: HARDWARE ACTUATION. No capture can show whether energising 0x24
      also energises 0x25..0x27 inside the box, because the box reports
      nothing back. That axis is HEADAMP_ACTUATION_SHIFT; it reads 0 from
      the image, and confirming it needs a physical 48 V measurement on box
      inputs 6, 7 and 8 while only input 5 is written — never a soft
      indicator.
        [EVIDENCED (executed trace) —
        reacpw-s1608-48k-clean__phantom-ch24-on-off-2026-08-23.pcap (taken
        as phantom-test.pcap), enp131s0, snaplen 200 (one record for CH 0x24
        alone per toggle; the box re-broadcasts nothing, 0 dropped frames),
        together with 2304 non-group-leader phantom records from three desk
        generations in the corpus and
        m200-ch7-ON-OFF-ON-20260721-215743.pcap as the decisive
        single-channel case. OVERTURNS the earlier executed trace that read
        2, and vindicates the image read (S-1608 FUN_0c002d42 gates the
        inventory cell, not phantom).]
  headamp_actuation_shift:
    value: 0
    doc: |
      HARDWARE ACTUATION IS PER CHANNEL, for phantom, pad and sens alike.
      FUN_0c007fbc's loop passes a per-channel index and that slot's own
      value to each of the three writers on every one of its eight
      iterations. This is the number that says what one write switches, and
      it is the axis the three old "granularity" rows never had.
        [EVIDENCED (image, S-1608 FUN_0c007fbc -> FUN_0c00ac1e /
        FUN_0c00ac96 / FUN_0c007e6a).]
  headamp_bank_channels:
    value: 8
    doc: |
      THE PER-EIGHT GRANULARITY, and there is only one of them. This row
      folds together what used to be two — "the hardware bank" and "the
      readback nibble is per eight" — because they are arithmetically the
      same thing and were being read as two independent pieces of evidence.

      FUN_0c007fbc sets its cursor to `group << 3` and loops exactly eight
      times, so group g covers [g*8, g*8+8) and therefore `g == ch >> 3` —
      which is the readback nibble's own index. One axis, two spellings:
      this width 8 and HEADAMP_BANK_SHIFT's 3.

      It is a REFRESH AND READBACK banking, not an actuation width: the
      writers take (bank, 0..7) and each of the eight iterations writes one
      channel. Two banks of eight cover an S-1608's sixteen analog inputs.
        [EVIDENCED (image) — S-1608 FUN_0c007fbc for the loop and the
        per-channel writes; its caller, recovered 2026-08-23 from a function
        Ghidra never disassembled (clean prologue past the previous
        function's rts, absent from the 1395-entry map, reached by a plain
        bsr), for `group == ch >> 3`. Supersedes the earlier UNRESOLVED note
        that the caller could not be traced.]
  headamp_bank_shift:
    value: 3
    doc: |
      `ch >> 3` gives the bank/group index. THE SAME FACT AS
      HEADAMP_BANK_CHANNELS above, spelled as a shift instead of a width —
      consult one or the other, never both as corroboration.

      It was called HEADAMP_GRAN_READBACK_SHIFT and sat beside the bank row
      as if the readback were a third, independent granularity. It is not:
      the apply loop's group index and the readback nibble are the same
      `ch >> 3` over the same 80 slots.
        [EVIDENCED (executed trace for the readback nibble; image for the
        apply loop's identical index — S-1608 FUN_0c007fbc and its caller).
        The two agree, which is why they are one row.]
  headamp_sweep_records_per_ch:
    value: 3
    doc: |
      Every real desk sweep is ONE contiguous pass over the box's full
      declared width, every channel getting all three parameters — 24
      records for an S-0808, 48 for an S-1608, 96 for an S-4000S. No desk
      addresses a bank, splits a sweep or repeats one. [EVIDENCED (corpus) —
      31 of 47 captures, three desk generations agreeing on the same box.]
  headamp_base_from_config_byte7:
    value: True
    doc: |
      A box's head-amp CH base is its OWN property, announced, never
      granted. The config
      announce `01 03 00 10` carries it at buf[7], and the master addresses
      the box at
      base = buf[7] * 0x10. An 8-input and a 32-input box are BOTH addressed
      at 0x00, which
      is what rules out an allocation: nothing in the box consumes a granted
      base.
        [RESOLVED (firmware + corpus) — S-1608.BIN (SH-4 LE, base
        0x0BFE0000): FUN_0c003c8a at
      0x0c003c8a sets buf[7] = FUN_0c00f6a8() = *0x0c080918. Corroborated on
      29 captures in
      reac-captures/analysis/placement_table.csv (S-0808 0x00->0x00, S-1608
      0x02->0x20,
      S-4000S 0x00->0x00) across M-200i, M-300 and M-5000.
      ]
  headamp_base_multiplier:
    value: 0x10
    doc: |
      base = config-announce buf[7] * 0x10. Sixteen head-amp rows per strap
      step, which is
      two 8-slot groups — the same unit the box applies in.
      Exercised at exactly two points (0 and 2): firmware-grade for the
      S-1608, corpus-grade
      for the others.
        [RESOLVED (firmware + corpus) — same provenance as
        HEADAMP_BASE_FROM_CONFIG_BYTE7.
      ]
  headamp_base_is_chassis_not_grant:
    value: True
    doc: |
      A master cannot move where a head-amp write lands by granting
      differently. The box's
      fabric-row-to-preamp map is the group number FUN_0c012162 returns, and
      every input to
      it is a GPIO strap or a fitted-board inventory. Retires reac-pw's
      docs/PLACEMENT-EVIDENCE.md five-run rig experiment: declared width was
      collinear with
      the base only because a 16-in chassis always straps 2.
        [RESOLVED (firmware) — S-1608.BIN: FUN_0c0081f6 at 0x0c0081f6 reads
        *0x0c080918 and
      applies FUN_0c007fbc(bank, FUN_0c012162(k)); FUN_0c007fbc at
      0x0c007fbc indexes the
      head-amp table at 0x0c0cf85a by group*8 + i; the config record is
      built by FUN_0c0123c0
      (0x0c0123c0), called only from FUN_0c0052d4 (0x0c0052d4) with
      constants, and the group
      table at +0x78 has exactly three writers — FUN_0c0119ac, FUN_0c011bbc,
      FUN_0c011e2c —
      none of which reads a frame.
      ]
  headamp_apply_unit_slots:
    value: 8
    doc: |
      The box applies head-amp in groups of eight fabric rows, one 8-port
      board at a time,
      passing the within-group index 0..7 to the preamp. Anything reasoning
      about head-amp
      reach reasons in groups of 8 from the box's base, never per channel —
      note this is the
      APPLY unit and is a different axis from actuation, which is per
      channel.
        [RESOLVED (firmware) — S-1608.BIN: FUN_0c007fbc at 0x0c007fbc, slot
        = group << 3, eight
      iterations.
      ]
  # ---- The SENS step -> sensitivity curve ----
  headamp_sens_ref_cdb:
    value: -1000
    doc: |
      Step 0x00 with the pad off, in hundredths of a dBu — the least
      sensitive setting and the reference the whole travel hangs off.
      [INFERRED — agreed by every prior reading and not independently
      measurable through a loopback, which sees only this plus the box's
      converter reference. The SPAN below is what was measured.]
  headamp_sens_step_cdb:
    value: 100
    doc: |
      One decibel, every step, all 55 transitions. The number that was
      disputed, and the one thing a consumer cannot get wrong quietly.
      [EVIDENCED (image + rig). Image — the S-1608 table at 0x0c0327a0 steps
      its fine register by exactly 2 for every SENS step with no exception,
      so the law is uniform inside each of its four ranges and can only
      break at three indices. Rig — the 2026-08-23 loopback sweep of all 56
      steps, span 54.60 dB, slope 0.988, and A/B/A at each of those three
      indices giving about a decibel against controls of 0.08 to 0.34 dB.
      The 0.40 dB the span falls short is inside that sweep's own 0.44 dB
      maximum residual, so it does not stand against the table.
      ]
  headamp_sens_steps:
    value: 56
    doc: |
      Entries in the firmware's SENS table, steps 0x00..0x37. The writer
      FUN_0c007e30 clamps anything above 0x37 to 0x37, so 0x37 is the top of
      the travel and not merely the last one observed. [EVIDENCED (image,
      S-1608 0x0c0327a0 = file 0x527a0; the same 112 bytes at S-0808 file
      0x45ec8 as a raw byte match, not a disassembly — there is no S-0808
      decompilation).]
  headamp_sens_stages:
    value: 4
    doc: |
      Coarse analog ranges the table selects between, driven onto two GPIO
      pins per channel by FUN_0c00af2a. [EVIDENCED (image).]
  headamp_sens_stage_break_1:
    value: 0x08
    doc: |
      First step of the second range. The three breaks are the only places a
      uniform step could fail, and the rig measured all three at about a
      decibel. [EVIDENCED (image + rig).]
  headamp_sens_stage_break_2:
    value: 0x18
    doc: |
      First step of the third range. [EVIDENCED (image + rig).]
  headamp_sens_stage_break_3:
    value: 0x28
    doc: |
      First step of the fourth range. [EVIDENCED (image + rig).]
  headamp_pad_cdb:
    value: 2000
    doc: |
      The pad's 20 dB, in hundredths, added to the sensitivity when it is
      on. Independent of the step, and it earns its place here by being the
      one number in this group whose absolute value the loopback DOES
      measure. [EVIDENCED (rig) — 20.12 and 20.20 dB by A/B/A at steps 0x37
      and 0x28, against pad-off controls of 0.11 and 0.16 dB.]
  # ---- Head-amp base per declared width ----
  placement_base_in8:
    value: 0x00
    doc: |
      S-0808. [EVIDENCED (corpus) — 42 grant sweeps across 82 captures.]
  placement_base_in16:
    value: 0x20
    doc: |
      S-1608. The one width that is not zero, and the reason a 40-bounded
      table drops half the box. [EVIDENCED (corpus).]
  placement_base_in32:
    value: 0x00
    doc: |
      S-4000S. Wider than the S-1608 and still based at 0 — which is what
      kills "lowest fit" and "top alignment" as candidate laws. [EVIDENCED
      (corpus).]
  # ---- The config-announce port table ----
  ports_table_off:
    value: 8
    doc: |
      Block-relative start of the twelve-cell table. [EVIDENCED (corpus).]
  ports_table_slots:
    value: 12
    doc: |
      12 x 4 = the 48-channel fabric. [EVIDENCED (corpus).]
  ports_ch_per_slot:
    value: 4
    doc: |
      Channels per cell. [EVIDENCED (corpus).]
  port_slot_out:
    value: 0x01
    doc: |
      A 4-output group. [EVIDENCED (corpus).]
  port_slot_in:
    value: 0x02
    doc: |
      A 4-input group. [EVIDENCED (corpus).]
  port_slot_empty:
    value: 0x03
    doc: |
      An empty cell. A code outside {01,02,03} is a table nobody has
      captured — REFUSE, never guess. [EVIDENCED (corpus).]
  enroll_group_in:
    value: 0x41
    doc: |
      One per enrolled input group of 8, front-packed. [EVIDENCED (image +
      corpus).]
  enroll_group_out:
    value: 0xc3
    doc: |
      One per non-input group, back-packed. [EVIDENCED (image + corpus).]
  enroll_groups:
    value: 5
    doc: |
      Five groups of 8 span exactly the 40-slot audio fabric. [EVIDENCED
      (image + corpus).]
