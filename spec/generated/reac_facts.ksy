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
  bytes_per_channel:
    value: 36
    doc: |
      12 samples x 3 bytes, per channel, at EVERY sample rate. The 36 in `52
      + n*36`. [EVIDENCED (corpus) — holds across 44.1k, 48k and 96k.]
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
  op_name_frame:
    value: 0x0401
    doc: |
      The ASCII model-name frame. [EVIDENCED (corpus).]
  op_extra_cold_connect:
    value: 0x0402
    doc: |
      The extra cold-connect frame some models send. [EVIDENCED (corpus).]
  op_dt1_container:
    value: 0x0403
    doc: |
      A record container — a Roland DT1 SysEx, or the box's upstream return
      block. Discriminated by payload[0]. [EVIDENCED (corpus).]
  op_announce:
    value: 0xffff
    doc: |
      The op a cfea announce always carries. [EVIDENCED (corpus).]
  # ---- The control record header ----
  ctrl_class_off:
    value: 0
    doc: |
      Block offset of the record class. [EVIDENCED (image).]
  ctrl_class_session:
    value: 0x01
    doc: |
      Scene transfer, slot map, commit report, link ack. [EVIDENCED (image +
      corpus).]
  ctrl_class_parameter:
    value: 0x04
    doc: |
      The DT1 container — head-amp, identity, join grant, box return.
      [EVIDENCED (image + corpus).]
  ctrl_frag_off:
    value: 1
    doc: |
      Block offset of the fragment flags. [EVIDENCED (image).]
  ctrl_frag_first:
    value: 0x01
    doc: |
      Bit 0 — this frame opens the record. [EVIDENCED (image, S-1608
      FUN_0c003398 + FUN_0c003aae).]
  ctrl_frag_last:
    value: 0x02
    doc: |
      Bit 1 — this frame closes it. Both set is a whole record. [EVIDENCED
      (image, S-1608 FUN_0c003398 + FUN_0c003b88).]
  ctrl_reclen_off:
    value: 2
    doc: |
      Block offset of the record length, a big-endian u16. [EVIDENCED
      (image, S-1608 FUN_0c002f7a).]
  ctrl_reclen_base:
    value: 4
    doc: |
      The block offset the length counts FROM, inclusive. Verified on every
      record type in the corpus — slot map 0x19 = block[4..28], commit
      report 0x10 = block[4..19], link ack 0x01 = block[4], enroll group
      map 0x0d = block[4..16], DT1 0x14 = block[4..23] with the record's
      own checksum as the last byte. Our grammar used to say this number
      was "op-specific in meaning" and "not a generic frame length"; it is
      a generic record length and always was.
        [EVIDENCED (image + corpus).]
  ctrl_subtype_off:
    value: 4
    doc: |
      Block offset of the subtype, the record's only discriminator.
      [EVIDENCED (image).]
  ctrl_scene_chunk_first:
    value: 0x18
    doc: |
      Payload bytes in an opening scene chunk — smaller than a middle chunk
      because block[5:7] carries the blob total. [EVIDENCED (image, S-1608
      FUN_0c003398).]
  ctrl_scene_chunk_middle:
    value: 0x1a
    doc: |
      Payload bytes in a middle or closing scene chunk, at block[5].
      [EVIDENCED (image, S-1608 FUN_0c003398).]
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
      begins. The count is what that table proves; reading a gain curve off
      its stage structure did not survive the rig.]
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
    value: 2
    doc: |
      DISPUTED 2026-08-23, VALUE UNCHANGED PENDING ONE EXPERIMENT. Read as
      "phantom is per group of FOUR — ch >> 2", and a consumer that trusts
      it sweeps phantom on multiples of four only.

      THE IMAGE DOES NOT CONTAIN THIS GATE. There is exactly one
      channel-indexed `(x & 3) == 0` test in S-1608.BIN — FUN_0c002d42, the
      SLOT-MAP ingest — and what it gates is `flags >> 4`, the inventory
      cell nibble, handed to the 12-entry inventory arrays at 0x0c0f62fa
      and 0x0c0cf80e. It does not gate a head-amp parameter, and it is not
      on the DT1 path at all. Every other `& 3` in the image is pointer
      alignment. Meanwhile the hardware write is per channel (see
      HEADAMP_ACTUATION_SHIFT), so there is no per-four actuator for a
      per-four record to feed.

      The most likely history is that this number and the state diagram's
      retracted "phantom packed 4 ch/group, group = slot >> 2" are the same
      misreading of FUN_0c002d42, and that "a record to 0x24 moves group 9"
      describes the inventory cell moving, not phantom.

      NOT CHANGED HERE, because the grade below is an executed trace and a
      static read must not silently overwrite an observation. THE
      DISCRIMINATING EXPERIMENT, which needs no rig: send DT1 phantom
      records to channels 0x24 and 0x25 in turn and read the box's own
      re-broadcast back. If 0x25 moves, this row is 0 and phantom is per
      channel on the wire too.
        [DISPUTED — EVIDENCED (executed trace) against EVIDENCED (image,
        S-1608 FUN_0c002d42 + FUN_0c007fbc). Unresolved.]
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
      The preamp bank width, and the batch size of the apply loop — NOT an
      actuation granularity. FUN_0c007fbc(bank, group) walks `group << 3`
      for eight iterations and its writers take (bank, 0..7), so two banks
      of eight cover the S-1608's sixteen analog inputs. `group` runs 0..9
      over the 80-slot active table.
        [EVIDENCED (image, S-1608 FUN_0c007fbc).]
  headamp_gran_readback_shift:
    value: 3
    doc: |
      The readback nibble is per EIGHT — ch >> 3. It coincides
      ARITHMETICALLY with the apply loop's bank index, which is also a
      `>> 3` over the same 80 slots, so "readback per eight" and "the
      hardware bank" are plausibly one fact rather than two.

      NOT ASSERTED AS ONE, because the image does not close it: there is no
      `ch >> 3` anywhere in the head-amp region of S-1608.BIN, and
      FUN_0c007fbc has NO caller in the function-only export — it is reached
      through a data-section pointer, so what drives the banking cannot be
      traced. The coincidence is real and the identification is not proven.
      THE EXPERIMENT: the same data-section pointer re-export that would
      close the enrolled-bit writer would show FUN_0c007fbc's caller and
      settle whether the readback reports these banks.
        [EVIDENCED (executed trace) for the shift; the identification with
        HEADAMP_BANK_CHANNELS is UNRESOLVED (image, caller not exported).]
  headamp_sweep_records_per_ch:
    value: 3
    doc: |
      Every real desk sweep is ONE contiguous pass over the box's full
      declared width, every channel getting all three parameters — 24
      records for an S-0808, 48 for an S-1608, 96 for an S-4000S. No desk
      addresses a bank, splits a sweep or repeats one. [EVIDENCED (corpus) —
      31 of 47 captures, three desk generations agreeing on the same box.]
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
      S-1608 0x0c0327a0 and S-0808 file 0x45ec8).]
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
