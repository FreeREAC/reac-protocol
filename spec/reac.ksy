meta:
  id: reac
  title: Roland REAC 0x8819 frame family (downstream broadcast + upstream stagebox return)
  license: GPL-3.0-or-later
  ks-version: '0.10'
  endian: be
doc: |
  A complete REAC Ethernet frame as it appears on the wire, EtherType 0x8819,
  reverse-engineered from FreeREAC's own captures of real Roland M-200i / M-300 /
  M-5000 consoles driving real S-0808 / S-1608 / S-4000S stageboxes.

  This grammar is the FORMAL SPEC half of a three-part arrangement (see
  spec/README.md): libreac is the executable C oracle, this .ksy is the spec, and
  the parser ksc generates from it is the referee that keeps the two honest.

  # Frame geometry

  Every REAC frame — both directions — is

      14 B ethernet header
       2 B free-running u16 LITTLE-endian frame counter   (offset 14)
       2 B REAC type word                                 (offset 16)
      32 B control block                                  (offset 18..49)
       n_channels * 36 B braided s24 audio region         (offset 50)
       2 B 0xC2 0xEA end marker
     [ 2 B FCS residue — not protocol, see below ]

  so a frame is `52 + n_channels * 36` bytes:

    | direction  | width | frame | as some captures store it |
    |------------|-------|-------|---------------------------|
    | downstream |    40 |  1492 |                      1494 |
    | upstream   |     8 |   340 |                       342 |
    | upstream   |    16 |   628 |                       630 |
    | upstream   |    32 |  1204 |                      1206 |

  The right-hand column is NOT a second frame format. It is the same frame with
  two bytes of the capture's own Ethernet FCS left on the end.

  The downstream broadcast is always 40 channels and rate-INVARIANT: 12 samples
  per frame at 44.1 / 48 / 96 kHz alike, the sample rate carried by the packet
  rate (pps = rate / 12 -> 3675 / 4000 / 8000). An upstream return is the same
  shape sized to the box's own input width.

  # The +2 is Ethernet FCS residue — explained, stripped, NOT modelled

  A length of `52 + n*36 + 2` carries two bytes past the end marker. They are
  the low 16 bits of the frame's OWN Ethernet FCS (crc32 over the preceding
  bytes, little-endian), left behind by the capture path. They are not a REAC
  field, they carry no protocol meaning, and nothing may ever emit them.

  The measurement and the reasoning live in libreac <reac/reac.h> (libreac#15);
  the short form is that the identity holds for 100% of frames checked, in both
  directions and across generations, which no genuine trailer could do, and that
  the variable is the capture rig — mirroring RX and TX of one port, so a
  transiting frame is seen twice, one copy clean and one with the residue. It is
  NOT OHRCA-specific: it appears on non-OHRCA rigs and is absent on OHRCA ones.
  It is not a VLAN tag either — every frame here reads 0x8819 at offset 12, and
  a tag would sit four bytes BEFORE the ethertype, not two bytes after the end
  marker.

  ## How the grammar expresses that

  By NOT declaring a field for it. The `seq` ends at `end_marker`, so a parse of
  a residue-carrying capture consumes exactly the frame and leaves the two stray
  bytes unread at the end of the stream — tolerated, ignored, and impossible to
  emit from a serializer generated out of this grammar. A `size: 2` field, however
  it were named, would say the opposite: that the bytes belong to the format.

  What the grammar DOES keep is the length arithmetic, because every derived
  quantity depends on it. `has_fcs_residue` is a statement about the CAPTURE, not
  about the frame, and `clean_len` is libreac's one rule for both directions: a
  length of `52 + n*36 + 2` comes back reduced by 2, anything else is returned
  unchanged.

  A residue-carrying frame and a clean one therefore parse identically, field for
  field, and differ only in how many bytes are left over afterwards.

  # The audio region and the braid

  The region is described here STRUCTURALLY only — 12 time samples, each holding
  `n_channels / 2` six-byte channel-PAIR groups. The byte permutation inside a
  group is deliberately NOT expressed in Kaitai (it has no byte-permutation
  primitive, and a hand-rolled instance per channel would be a second copy of a
  layout libreac already owns). It is validated instead by the cross-check
  harness, which decodes the fixtures and compares against the PCM truth tables
  the C oracle pins. The map, for reference, is <reac/reac_braid.h>:

      group g = (s * n_ch + (ch & ~1)) * 3          # s = time sample
      even channel s24 LE (lo, mid, hi) = g+3, g+0, g+1
      odd  channel s24 LE (lo, mid, hi) = g+4, g+5, g+2

  Equivalently a 16-bit-word byte swap of the pair packed as big-endian s24.
  Confirmed independently by per-gron/reacdriver (MbufUtils), by
  norihiro/obs-h8819-source (convert_to_pcm24lep, listening-validated against a
  real M-200i) and by the FreeREAC rig goldens.

  ## One layout, both directions — and why plain LE was ever entertained

  There is ONE audio layout in REAC and it is the braid above. It holds in both
  directions and across every mixer generation; there is no per-generation
  variant, downstream or otherwise.

  UPSTREAM (box -> master) is confirmed on real captures at three widths: the
  goldens in fixtures/upstream.json are decoded by reac_upstream_decode() and by
  this grammar to the same 1056 samples, and the loud channel of the rig capture
  reads +0.998 lag-1 autocorrelation under the braid while every idle channel
  collapses to the mic noise floor.

  DOWNSTREAM (master -> fabric) is the same braid. The evidence:

    - the zoneA/zoneB goldens (one M-5000's two REAC ports, program audio) read
      coherence 0.99 / spectral flatness 0.002 braided, and noise under every
      other layout x offset;
    - obs-h8819-source decodes it as the braid and was listening-validated
      against a real M-200i, a DIFFERENT generation from the M-5000 above — so
      the two ends of the generation range are covered by independent work;
    - libreac's own encoder, reac_downstream_build(), lays down the braid, and
      since 0.5.0 reac_decode() reads it back. The library that emits the format
      and the library that reads it are finally the same library.

  ### Plain LE: a refuted reading, kept only as history

  A plain-LE sample-major reading (channel ch at time s starting at
  (s*40 + ch)*3) was once libreac's downstream default, on the strength of an
  on-rig "coherence 0.999". That reading was overturned: the coherence came from
  a mid-byte lane shift amplifying quiet BRAIDED audio 256x into a
  coherent-looking image. It is not a layout the wire ever carried.

  libreac 0.5.0 fixed reac_decode() accordingly — before the fix the library
  could not read back a frame it had just built, 0 of 480 samples agreeing with
  its own encoder (libreac#13). Plain LE survives there only as
  reac_decode_plain_le(), a DIAGNOSTIC for reading historical captures stored
  that way and for reproducing the lane shift.

  The companion speculation — that OHRCA-generation (M-5000 / M-480) gear might
  differ from the V-Mixer generation downstream — is likewise refuted, and was
  never evidence in the first place: it was an untested hypothesis raised to
  explain a discrepancy that turned out to be the lane shift. All mixers produce
  the same downstream format. Do not reopen it without a capture that
  contradicts the braid.

  What IS a real limitation of this repo: there is NO downstream fixture here.
  Every committed golden is an upstream return, so the downstream side of the
  grammar is checked only against frames libreac's own encoder built, which
  tests the envelope, the structure and agreement with the codec — not a console
  on a wire. That gap is about this repo's corpus, not about the layout; see
  spec/xcheck_c_oracle.py, which states the same boundary.

  # Checksums

  Two NESTED checksums, neither expressible in Kaitai (no fold/sum primitive):

  - OUTER, the control block: `Sum(frame[18..49]) mod 256 == 0`, the last byte of
    the block being the stamp. FILLER frames (type word 0x0000) are EXEMPT.
    `raw_block` and `block_checksum` expose the bytes for a checker to verify.
  - INNER, a DT1 record: `Sum(TAG .. CKSUM) mod 256 == 0x80`, i.e. the Roland
    Data Set 1 rule over the record only. `dt1_record.record_len` gives its span.

  Both are asserted for every checked-in fixture by spec/reac_xcheck.py.

  # The session, and its two reconnects

  A stagebox appearing on a segment is not a special case: it is a lost
  connection and a reconnect, and the frames that mark it are all in this
  grammar. The box drives it — nothing has to provoke it. Measured end to end on
  a live swap (2026-08-21, an S-1608 pulled and an S-0808 plugged in):

    peer silent past the master's hold      -> the session is over
    +3.4 s  box UNICAST upstream, its own eth_src   (`upstream` frame)
            box CONFIG ANNOUNCE, op 01 03 0x0010    (`config_announce_page`)
    +0.8 s  box JOIN burst, op 04 03 tags 0014/0016/001a  (`dt1_record`)
            box HEARTBEAT, op 01 03 0x0001
    +5.0 s  granted; the box's return carries audio

  The FIRST frame carrying the new `eth_src` is what announces the peer. There
  are two flavours, and `eth_src` alone cannot tell them apart:

  - COLD — a DIFFERENT eth_src. A new peer with its own declared geometry (see
    the port table in `config_announce_page`), so everything derived from the old
    one is void: width, fabric placement, and the receiver's channel count.
  - WARM — the SAME eth_src returning. The geometry stands, but it is still a NEW
    SESSION: the frame counter at offset 14 restarts wherever the box's does, so
    stream state keyed on the peer's identity alone silently survives into a
    session it does not belong to. A receiver that kept it read the seam as lost
    frames and reported thousands of counter gaps on a clean reconnect.

  Both are the same event with different consequences, which is why a consumer
  must key per-session state on (peer, session), never on the peer alone.

  # Anti-goals

  This grammar does NOT model the establishment FSM as STRUCTURE — a sequence of
  frames is not a layout, and Kaitai has no way to say it. The lifecycle above is
  documented rather than parsed, and it names the frame each transition is
  carried by so the sequence is at least discoverable from the spec. Also not
  modelled: the probe rotation law, the per-model fabric slot BASE (see
  `config_announce_page`), or anything that is negotiated session state rather
  than a field on the wire.
seq:
  - id: eth_dst
    size: 6
    doc: ff:ff:ff:ff:ff:ff for the master's downstream broadcast; the learned peer
      MAC for a stagebox's unicast upstream return.
  - id: eth_src
    size: 6
    doc: Roland OUI 00:40:ab on every real console and box.
  - id: ethertype
    contents: [0x88, 0x19]
    doc: REAC's registered non-IP EtherType. A VLAN-tagged capture shifts every
      offset below by 4 and is out of scope — strip the tag first.
  - id: counter
    type: u2le
    doc: |
      Free-running frame counter, LITTLE-endian (the only little-endian field in
      the frame). Increments once per frame and keeps advancing across a lost
      frame, which makes it a drop-immune rate and loss reference; it is also how
      a mirrored duplicate is recognised (two frames, one counter).
  - id: control
    size: 34
    type: typed_block
    doc: The REAC type word plus the 32-byte control block, i.e. frame[16:50].
      Parsed as one unit so the same type also parses a bare captured
      frame[16:50] window, which is the form the C goldens are stored in.
  - id: audio
    size: len_audio
    type: audio_region
  - id: end_marker
    contents: [0xC2, 0xEA]
    doc: |
      The frame ENDS here. A capture that kept two bytes of the Ethernet FCS
      leaves them past this point; the grammar deliberately declares no field for
      them, so they are read by nothing and can be emitted by nothing. See "The
      +2 is Ethernet FCS residue" in the top-level doc.
instances:
  raw_len:
    value: _io.size
    doc: The size of the buffer handed to the parser — the frame plus whatever
      the capture left on it.
  has_fcs_residue:
    value: (raw_len - 52) % 36 == 2
    doc: |
      True when the buffer is 2 bytes longer than any valid 52 + n*36 frame,
      i.e. when the capture kept the low half of the Ethernet FCS. A statement
      about the CAPTURE, not about the frame: it changes no field below, only
      how many bytes go unread after end_marker.
  clean_len:
    value: 'has_fcs_residue ? raw_len - 2 : raw_len'
    doc: libreac reac_frame_clean_len(). The actual frame length. Every length
      that is not 52 + n*36 + 2 passes through unchanged.
  num_channels:
    value: (clean_len - 52) / 36
    doc: |
      Channel width DERIVED from the frame size — REAC carries no width field in
      the audio frame. 40 is the downstream broadcast; an even 2..38 is a box's
      upstream return. This is the width the audio region is laid out at; it is
      NOT the head-amp channel space (48 slots, 0x00..0x2f), and conflating the
      two silently drops the top half of a 16-input box.
  len_audio:
    value: num_channels * 36
    doc: 36 = 12 samples x 3 bytes, per channel, at every sample rate.
  is_downstream_width:
    value: num_channels == 40
types:
  typed_block:
    doc: |
      frame[16:50]: the REAC type word plus the 32-byte control block. Also the
      standalone unit the golden corpora store, so this type is instantiable on
      its own (it touches neither _root nor _parent).
    seq:
      - id: type_word
        type: u2
        enum: frame_type
      - id: block
        size: 32
        type:
          switch-on: type_word
          cases:
            'frame_type::filler': filler_block
            'frame_type::control': control_block
            'frame_type::announce': control_block
        doc: cd ea and cf ea share the op/op_len/payload shape; only the op
          differs (cf ea is always op 0xffff). FILLER has no op at all.
    instances:
      raw_block:
        pos: 2
        size: 32
        doc: The checksummed block verbatim, for the sum-to-0 check the grammar
          cannot express.
      block_checksum:
        pos: 33
        type: u1
        doc: Stamp such that Sum(block) mod 256 == 0. Meaningless on FILLER.
      op_raw:
        pos: 2
        type: u2
        doc: frame[18:20], readable whatever the type word says. Used by
          ctrl_kind so classification never depends on the switch.
      op_len_raw:
        pos: 4
        type: u2
        doc: frame[20:22].
      dt1_model_lo:
        pos: 16
        type: u1
        doc: frame[32] — the low byte of the Roland model ID, 0x12 on a genuine
          DT1 container.
      dt1_command:
        pos: 17
        type: u1
        doc: frame[33] — the DT1/RQ1 command byte.
      dt1_tag:
        pos: 18
        type: u2
        doc: frame[34:36] — the record TAG that selects the register page.
      ctrl_kind:
        value: >-
          type_word == frame_type::filler ? ctrl_kind::filler :
          type_word == frame_type::announce ? ctrl_kind::master_announce :
          type_word != frame_type::control ? ctrl_kind::unknown_ctrl :
          op_raw == 0x0403 ? (dt1_model_lo == 0x12 and dt1_command == 0x12
            and dt1_tag == 0x0101 ? ctrl_kind::head_amp : ctrl_kind::grant) :
          op_raw == 0x0103 and op_len_raw == 0x0019 ? ctrl_kind::master_hb :
          op_raw == 0x0103 and op_len_raw == 0x0001 ? ctrl_kind::box_hb :
          (op_raw >> 8) == 0x01 ? ctrl_kind::probe :
          ctrl_kind::unknown_ctrl
        enum: ctrl_kind
        doc: |
          Frame classification, mirroring libreac's consumer reac_ctrl_parse()
          DECISION FOR DECISION so the cross-check compares like with like,
          including its two deliberate quirks:
            - op 0x0403 with any tag other than a DT1-command 0x0101 classifies
              as `grant`, not as its own kind (the cold-connect inventory tags
              0x0302 / 0x0500 / 0x0000 all land here);
            - op 0x0103 sub-pages other than chanmap (0x0019) and box heartbeat
              (0x0001) — that is, config-announce 0x0010 and the enroll group map
              0x000d — fall through to `probe`, because the consumer only tests
              the high op byte. Read `page_kind` for the real sub-page.
          `none` is never produced here: a non-REAC frame fails the ethertype
          contents check before classification.
  filler_block:
    doc: |
      Type word 0x0000: an audio-only frame, no control op, CHECKSUM-EXEMPT. The
      32 bytes are 16 two-byte descriptor slot words. Downstream, a real console
      repeats the CHECKSUM of the probe currently in force across every FILLER
      until the next probe; upstream, a box emits a constant word (0x007a on the
      S-0808/S-1608 returns, 0x00f4 on the S-4000S). The presence-flood a box
      broadcasts before it links zeroes the block entirely.
    seq:
      - id: descriptor
        type: u2
        repeat: expr
        repeat-expr: 16
  control_block:
    doc: |
      The 32 checksummed bytes at frame[18:50], for both the cd ea control
      records and the cf ea master announce: op(2) op_len(2) payload(28).
    seq:
      - id: op
        type: u2
        enum: control_op
      - id: op_len
        type: u2
        doc: |
          Big-endian, and op-specific in meaning — a length for the DT1 container
          (record_len = op_len - 0x0d) but a SUB-PAGE SELECTOR for op 0x0103 and
          a fixed constant for the rest. It is not a generic frame length.
      - id: payload
        size: 28
        type:
          switch-on: op
          cases:
            'control_op::probe': probe_payload
            'control_op::sub01': sub01_payload
            'control_op::page_0103': page_0103
            'control_op::dt1_container': dt1_record
            'control_op::announce': cfea_payload
        doc: Unmodelled ops (sub02 0x0102, the ASCII name frame 0x0401, the extra
          cold-connect 0x0402) fall through as raw bytes on purpose — their
          interiors are not decoded to a level worth pinning.
    instances:
      block_checksum:
        pos: 31
        type: u1
        doc: Sum(this 32-byte block) mod 256 == 0.
  cfea_payload:
    doc: |
      The cf ea master announce (op 0xffff, op_len 0x0100). Advertises the
      console, the fabric size and the linked box. Three real consoles differ on
      the wire in exactly two bytes — the source MAC and `console_field` — with
      every other downstream template shared.
    seq:
      - id: header
        contents: [0x01, 0x03, 0x0d, 0x01, 0x04]
      - id: master_mac
        size: 6
        doc: The console's own MAC, repeated inside the payload. Emulators MUST
          NOT reuse a real desk's MAC here — it impersonates the console.
      - id: total_slots
        type: u1
        doc: 0x28 = the 40-slot AUDIO fabric, on every console seen. Distinct from
          the 48-slot head-amp channel space.
      - id: box_in_width
        type: u1
        doc: |
          The linked box's INPUT width — 0x08 idle, and once a box links it
          tracks that box (0x10 for a 16-input S-1608, 0x08 for an S-0808). Fed
          from the box's own config-announce. A PLACEMENT CARRIER, see
          config_announce_page.
      - id: console_field
        type: u1
        doc: Console generation - 0x00 V-Mixer (M-200 / M-300), 0x01 OHRCA
          (M-5000). The same 0/1 also appears as the ENROLL console byte.
      - id: box_count
        type: u2
        doc: Enrolled boxes. 0x0000 idle -> 0x0001 once a box is granted; a
          console that leaves this at 0 while granting leaves the box blinking.
      - id: rest
        size-eos: true
        doc: Zero padding, last byte the block checksum.
  probe_payload:
    doc: |
      op 0x0100, the master's hunt/probe (op_len 0x001a). `window` is a 27-byte
      sliding view of the period-10 sequence {0,0,0,1,0,0,0,0,0,SUB}, SUB = 0x02
      while probing and 0x03 once established, the phase stepping +6 (mod 10)
      every two emissions. A box advances its own join state by tracking this
      rotation, so a master that emits only a subset of the phases leaves the box
      latched part-way. The rotation is a SEQUENCE law, not a layout, and is
      therefore documented rather than modelled.
    seq:
      - id: window
        size: 27
      - id: checksum
        type: u1
  sub01_payload:
    doc: op 0x0101, establishment handshake step 1; op 0x0102 (sub02) follows it
      about 0.68 s later and is a fixed block with no decoded interior.
    seq:
      - id: reserved
        type: u1
      - id: model_const
        type: u2
        doc: Protocol identity constant, 0x22c8 on the S-1608 family. The box's
          config-accept gate rejects a mismatch, which blocks ESTABLISHMENT (it
          has nothing to do with head-amp latching).
      - id: ident_ascii
        size: 4
        doc: ASCII "1234".
      - id: rest
        size-eos: true
  page_0103:
    doc: |
      op 0x0103 is a multiplexer whose sub-page is selected by op_len, not by a
      further opcode: 0x0019 chanmap, 0x0010 box config-announce, 0x000d enroll
      group map, 0x0001 box heartbeat.
    seq:
      - id: page
        size-eos: true
        type:
          switch-on: _parent.op_len
          cases:
            0x0019: chanmap_page
            0x0010: config_announce_page
            0x000d: enroll_group_map
    instances:
      page_kind:
        value: >-
          _parent.op_len == 0x0019 ? page_kind::chanmap :
          _parent.op_len == 0x0010 ? page_kind::config_announce :
          _parent.op_len == 0x000d ? page_kind::enroll_group_map :
          _parent.op_len == 0x0001 ? page_kind::box_heartbeat :
          page_kind::unknown_page
        enum: page_kind
  chanmap_page:
    doc: |
      op-0103 0x0019: a rotating 8-entry window over a 49-position ring — the 48
      fabric channels 0x00..0x2f plus a 0xfe wrap marker. Slots 0x00..0x27 carry
      bank 0x28 and slots 0x28..0x2f carry bank 0x38.

      The chanmap is IDENTICAL for every box on every console, so it carries NO
      per-box placement information; a study of 82 captures found the same full
      ring everywhere. It is the master's established heartbeat, nothing more.

      GROUP ANCHORS. The S-1608 firmware's per-record push consumes only entries
      where `(slot & 3) == 0`, deriving a group index `slot >> 2` and storing the
      value byte's HIGH NIBBLE — an `inventory_cell` code — into a 12-position
      map. Only 12 of the 49 ring entries reach it: slots 0x00,0x04,…,0x2c giving
      groups 0..11. The `is_group_anchor` / `group` / `cell_type` instances on
      chanmap_entry expose that derivation.

      What it yields is a CONSTANT, which is the load-bearing point: every console
      (M-200i, M-300, M-5000) and reac-pw alike write groups 0..9 = analog_input
      (nibble 2) and groups 10..11 = absent (nibble 3), for an S-0808, an S-1608
      and an S-4000S without distinction. A 32-channel box receives the same
      12-group map as an 8-channel one, so this map cannot be how a console
      selects a box's head-amp banks — it describes the MASTER's own 40-channel
      fabric (0x00..0x27 populated, 0x28..0x2f past its end).

      The 0xfe wrap marker is NOT an anchor (`0xfe & 3 == 2`), so it never reaches
      the group map; it is dispatched down a separate path.

      EVIDENCED (82-capture corpus): the ring, the 3-byte stride, the values, the
      box-independence, and that 0xfe is not an anchor.
      INFERRED (firmware image, not the wire): that these anchor nibbles are what
      the box stores as its group map.
    seq:
      - id: page_id
        type: u1
        doc: 0x01 on every observed window.
      - id: entries
        type: chanmap_entry
        repeat: expr
        repeat-expr: 8
        doc: entries[0].slot is the window cursor — that is what advances between
          consecutive frames.
      - id: rest
        size-eos: true
  chanmap_entry:
    seq:
      - id: slot
        type: u1
        doc: Fabric channel 0x00..0x2f, or 0xfe for the ring wrap marker.
      - id: bank
        type: u1
        doc: 0x28 for slots below 0x28, 0x38 for 0x28..0x2f, 0x00 on the marker.
      - id: pad
        type: u1
    instances:
      is_group_anchor:
        value: 'slot != 0xfe and (slot & 3) == 0'
        doc: |
          True on the 12 entries the box's per-record push consumes (every 4th
          fabric slot). The 0xfe wrap marker is excluded explicitly: 0xfe & 3 is
          2, so it is not an anchor and never feeds the group map.
      group:
        value: 'slot >> 2'
        doc: |
          Head-amp group index this entry anchors, 0..11, meaningful only where
          is_group_anchor. Derived from the firmware's push, not from the wire.
      cell_type:
        value: 'bank >> 4'
        enum: inventory_cell
        doc: |
          The value byte's high nibble, the code stored into the group map:
          2 analog_input for groups 0..9, 3 absent for groups 10..11, on every
          console and every box model observed.
  config_announce_page:
    doc: |
      op-0103 0x0010: the box's SETUP DECLARATION at cold connect — what the
      master enrols it from. This is the frame the fabric-slot placement decision
      is made against, so every field below is a PLACEMENT CARRIER.

      PLACEMENT IS DELIBERATELY NOT IN THIS GRAMMAR. The per-model slot base
      (an S-1608 is addressed at 0x20 while an S-0808 and an S-4000S are both at
      0x00) is NEGOTIATED SESSION STATE, not a field: no byte in any frame
      carries it. A 42-establishment, three-console, four-unit study killed every
      candidate law that could be tested — lowest-fit, top-alignment, f(console),
      f(enrolment order), f(box MAC), f(cell map), f(enroll map), f(chanmap) —
      and left three carriers that the corpus cannot separate because they are
      perfectly collinear across every row: the declared input WIDTH, the
      `selector` byte, and `unit_offset` (for which `base == unit_offset * 0x10`
      holds arithmetically on every row). Parse the carriers; do not encode a
      base. See reac-pw docs/PLACEMENT-EVIDENCE.md for the corpus, the dead
      candidates and the five-run experiment that would settle it.
    seq:
      - id: selector
        type: u1
        doc: Model family. 0x82 = the S-1608 family, 0x84 = the S-0808 and
          S-4000S family (which is then named by an ASCII name frame or by the
          family default). PLACEMENT CARRIER.
      - id: reserved
        size: 2
        doc: 00 00 on every capture.
      - id: unit_offset
        type: u1
        doc: 0x02 on the S-1608, 0x00 on the S-0808 and S-4000S. PLACEMENT
          CARRIER, and the most law-shaped of the three - base == unit_offset *
          0x10 holds on every observed row - but collinear with the other two, so
          not adopted as the law.
      - id: cells
        type: u1
        enum: inventory_cell
        repeat: expr
        repeat-expr: 12
        doc: |
          12 cells of 4 channels each = the 48-slot declaration space. Counts
          reproduce every real box exactly: S-0808 2 input + 2 output, S-1608 4 +
          2, S-4000S 8 + 2 (all three have 8 outputs). The cells are an INVENTORY
          IN DECLARATION ORDER, always starting at cell 0 — they are not a fabric
          map, and the S-1608 declares cells 0..3 yet is placed at 0x20.
      - id: rest
        size-eos: true
    instances:
      declared_in_channels:
        value: >-
          (cells[0].to_i == 2 ? 4 : 0) + (cells[1].to_i == 2 ? 4 : 0) +
          (cells[2].to_i == 2 ? 4 : 0) + (cells[3].to_i == 2 ? 4 : 0) +
          (cells[4].to_i == 2 ? 4 : 0) + (cells[5].to_i == 2 ? 4 : 0) +
          (cells[6].to_i == 2 ? 4 : 0) + (cells[7].to_i == 2 ? 4 : 0) +
          (cells[8].to_i == 2 ? 4 : 0) + (cells[9].to_i == 2 ? 4 : 0) +
          (cells[10].to_i == 2 ? 4 : 0) + (cells[11].to_i == 2 ? 4 : 0)
        doc: Declared INPUT width, 4 channels per analog-input cell. The third
          placement carrier. Kaitai has no fold, hence the unrolled sum.
      declared_out_channels:
        value: >-
          (cells[0].to_i == 1 ? 4 : 0) + (cells[1].to_i == 1 ? 4 : 0) +
          (cells[2].to_i == 1 ? 4 : 0) + (cells[3].to_i == 1 ? 4 : 0) +
          (cells[4].to_i == 1 ? 4 : 0) + (cells[5].to_i == 1 ? 4 : 0) +
          (cells[6].to_i == 1 ? 4 : 0) + (cells[7].to_i == 1 ? 4 : 0) +
          (cells[8].to_i == 1 ? 4 : 0) + (cells[9].to_i == 1 ? 4 : 0) +
          (cells[10].to_i == 1 ? 4 : 0) + (cells[11].to_i == 1 ? 4 : 0)
  enroll_group_map:
    doc: |
      op-0103 0x000d: the master's prepare-to-grant frame, emitted ONCE about
      1.6 s before the grant burst. The box must receive it to arm itself for the
      grant; without it the box stays in a cold-connect-like wait, streams but
      never heartbeats, and its status light blinks.

      The group map is a PURE FUNCTION OF WIDTH and carries no base: input groups
      (0x41) fill the input region from the FRONT, one per 8 channels, and the
      remaining groups (0xc3) fill the output region from the BACK. Byte-
      identical across M-200 / M-300 / M-5000 but for `console_field`. It is also
      not a placement carrier for another reason: most real S-1608 captures
      contain no 0x000d frame at all, yet the box is still placed at 0x20.
    seq:
      - id: selector
        type: u1
        doc: 0x10.
      - id: selector2
        type: u1
        doc: 0x04.
      - id: console_field
        type: u1
        doc: Console generation, 0x00 V-Mixer / 0x01 OHRCA — the same value cfea
          carries.
      - id: input_groups
        type: u1
        repeat: expr
        repeat-expr: 5
        doc: 0x41 per enrolled input group of 8, front-packed; 0x00 otherwise.
      - id: output_groups
        type: u1
        repeat: expr
        repeat-expr: 5
        doc: 0xc3 per non-input group, back-packed; 0x00 otherwise.
      - id: rest
        size-eos: true
    instances:
      enrolled_in_channels:
        value: >-
          (input_groups[0] == 0x41 ? 8 : 0) + (input_groups[1] == 0x41 ? 8 : 0) +
          (input_groups[2] == 0x41 ? 8 : 0) + (input_groups[3] == 0x41 ? 8 : 0) +
          (input_groups[4] == 0x41 ? 8 : 0)
        doc: The width the master is enrolling, 8 channels per input group. The
          five groups span exactly the 40-slot audio fabric.
  dt1_record:
    doc: |
      op 0x0403 is a RECORD CONTAINER, not a single opcode: it wraps a genuine
      Roland DT1 (Data Set 1) MIDI SysEx, and the TAG after the command byte
      selects what the record means. A single console emits hundreds of head-amp
      records per grant, so a joining box that reads 0x0403 as "my grant" without
      checking the tag will act on a preamp knob turn.

      DISPATCH: a genuine record is op 0x0403 AND wrapper 00 02 00 fe AND
      F0 41 ... — all three are asserted below by `contents`, which is what
      rejects the look-alikes. The look-alike to beat is the box-upstream braid,
      which carries cd ea 04 03 with the bytes 02 00 fe 00 where the wrapper
      belongs and no SysEx envelope at all.

      WORKED EXAMPLE — an S-1608 input 1 phantom-ON edit, as the leading 25 bytes
      of the frame[16:50] window (zero padding and the block checksum follow):

        cd ea 04 03 00 13 00 02 00 fe 0e f0 41 0a 00 00 12 12 01 01 20 00 01 5d f7

        cd ea        type word, control
        04 03        op, this container
        00 13        op_len -> record_len 6, data_len 3
        00 02 00 fe  wrapper
        0e           len_echo, op_len - 5
        f0 41        SysEx start + Roland manufacturer id
        0a           device id
        00 00 12     model id
        12           command, DT1 (a write)
        01 01        TAG, the head-amp page
        20 00 01     data: CH 0x20, PARAM phantom, VALUE on
        5d           inner checksum
        f7           SysEx end

      The inner sum spans the record only: 01+01+20+00+01+5d = 0x80. CH 0x20 is
      input 1 of a box based at 0x20, not channel 32 of anything.
    seq:
      - id: wrapper
        contents: [0x00, 0x02, 0x00, 0xfe]
        doc: Fixed console wrapper OUTSIDE the SysEx; part of the dispatch
          signature.
      - id: len_echo
        type: u1
        doc: SysEx payload length echo, always op_len - 5.
      - id: sysex_start
        contents: [0xF0]
      - id: roland_id
        contents: [0x41]
        doc: Roland's registered MIDI manufacturer ID.
      - id: device_id
        type: u1
        doc: Roland SysEx unit ID, 0x0a on every console seen.
      - id: model_id
        size: 3
        doc: Roland 3-byte model ID, 00 00 12 across M-200 / M-300 / M-5000.
      - id: command
        type: u1
        enum: dt_command
        doc: 0x12 DT1 (write) on an edit; 0x11 RQ1 (request) on an identity poll.
      - id: tag
        type: u2
        enum: reg_page
        doc: The high two bytes of the DT1 address — the register page.
      - id: data
        size: data_len
        type:
          switch-on: tag
          cases:
            'reg_page::head_amp': head_amp_data
            'reg_page::join_grant': join_grant_data
      - id: inner_checksum
        type: u1
        doc: Roland DT1 rule - Sum(tag .. inner_checksum) mod 256 == 0x80.
      - id: sysex_end
        contents: [0xF7]
      - id: padding
        size-eos: true
        doc: Zero fill out to the 32-byte block, last byte the block checksum.
    instances:
      record_len:
        value: _parent.op_len - 0x0d
        doc: TAG(2) + data + inner checksum(1).
      data_len:
        value: _parent.op_len - 0x10
        doc: 3 for head-amp, 4 for the join grant, 6 or 10 for identity.
  head_amp_data:
    doc: |
      TAG 0x0101 — the console's preamp command, and the ONLY three things a box
      owns on the head-amp page.
    seq:
      - id: ch
        type: u1
        doc: |
          The WIRE channel: model_base + (box_input - 1), in the 48-slot head-amp
          space 0x00..0x2f. It addresses a BOX INPUT — not a console channel
          strip, and not an audio fabric slot (that space is 40 wide). A table
          bounded by 40 silently rejects the top half of a 16-input box based at
          0x20. The base itself is session state — see config_announce_page.
      - id: param
        type: u1
        enum: head_amp_param
      - id: value
        type: u1
        doc: |
          Phantom and pad are 0x00 off / 0x01 on. SENS is 0x00..0x37, 56 steps of
          1 dB, and PAD-RELATIVE: dB = -10 - value + (pad ? 20 : 0), so pad off
          runs -10 dBu at 0x00 down to -65 dBu at 0x37 and pad on shifts the whole
          range +20 dB. The box applies the shift, not the console.
  join_grant_data:
    doc: TAG 0x0100 — the join grant. Observed as 06 00 XX 00 with XX the box's
      join state, climbing 0x01 -> 0x09 as it locks to the probe rotation.
    seq:
      - id: body
        size-eos: true
  audio_region:
    doc: |
      12 time samples of `num_channels` s24 channels in the channel-pair byte
      braid. Structural only — see the braid map in the top-level doc; the
      permutation is validated by cross-check, not by this grammar.

      One layout, both directions, every generation. The braid is confirmed
      upstream on real captures at three widths and downstream by the zoneA/zoneB
      goldens, obs-h8819's listening-validated M-200i decode and libreac's own
      encoder; the plain-LE reading it was once weighed against is refuted. See
      "One layout, both directions" in the top-level doc — and note the structure
      below (12 samples x n/2 six-byte pair groups) would be the same byte count
      in the same place either way, so it is not what carries that claim.
    seq:
      - id: time_samples
        type: time_sample
        repeat: expr
        repeat-expr: 12
        doc: 12 samples per frame at 44.1, 48 and 96 kHz alike — REAC carries the
          rate in the packet rate, never in the frame.
  time_sample:
    seq:
      - id: pair_groups
        size: 6
        repeat: expr
        repeat-expr: _parent._parent.num_channels / 2
        doc: One 6-byte group per channel PAIR (2k, 2k+1), holding both channels'
          three sample bytes interleaved by the braid.
enums:
  frame_type:
    0x0000: filler
    0xcdea: control
    0xcfea: announce
  control_op:
    0x0100: probe
    0x0101: sub01
    0x0102: sub02
    0x0103: page_0103
    0x0401: name_frame
    0x0402: extra_cold_connect
    0x0403: dt1_container
    0xffff: announce
  page_kind:
    0: unknown_page
    1: chanmap
    2: config_announce
    3: enroll_group_map
    4: box_heartbeat
  ctrl_kind:
    0: none
    1: filler
    2: probe
    3: master_hb
    4: master_announce
    5: grant
    6: head_amp
    7: box_hb
    8: unknown_ctrl
  dt_command:
    0x11: rq1_request
    0x12: dt1_set
  reg_page:
    0x0000: head_mark
    0x0100: join_grant
    0x0101: head_amp
    0x0302: box_ready
    0x0500: identity
  head_amp_param:
    0x00: phantom_48v
    0x01: pad_minus_20db
    0x02: sens
  inventory_cell:
    0x01: output
    0x02: analog_input
    0x03: absent
