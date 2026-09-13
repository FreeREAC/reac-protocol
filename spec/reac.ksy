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

  # The role is the geometry

  A peer's frame LENGTH says which side of the protocol it is, and it is the one
  claim on the wire that cannot be misconfigured: a master's downstream is always
  the 40-channel solution (1492 B), a stagebox's upstream its own declared width
  (S-4000S 32 ch = 1204 B, S-1608 16 ch = 628 B, S-0808 8 ch = 340 B) — all the
  same `52 + n*36`.

  This outranks the control plane. A stagebox strapped to MASTER broadcasts
  continuously, never cold-connects, and classifies as a master by every
  control-frame rule there is, while still emitting a box geometry. A master
  never joins another master, so a peer announcing itself master while emitting a
  box width is a misconfigured box to REPORT, not a master to follow. Deciding
  that from the control frames alone costs a session; the length settles it in
  one comparison.

  # The session, and its two reconnects

  A stagebox appearing on a segment is not a special case: it is a lost
  connection and a reconnect, and the frames that mark it are all in this
  grammar. The box drives it — nothing has to provoke it. Measured end to end on
  a live swap (2026-08-21, an S-1608 pulled and an S-0808 plugged in):

    peer silent past the master's hold      -> the session is over
    +3.4 s  box UNICAST upstream, its own eth_src   (`upstream` frame)
            box CONFIG ANNOUNCE, op 01 03 0x0010    (`commit_report_page`)
    +0.8 s  box JOIN burst, op 04 03 tags 0014/0016/001a  (`dt1_record`)
            box HEARTBEAT, op 01 03 0x0001
    +5.0 s  granted; the box's return carries audio

  The FIRST frame carrying the new `eth_src` is what announces the peer. There
  are two flavours, and `eth_src` alone cannot tell them apart:

  - COLD — a DIFFERENT eth_src. A new peer with its own declared geometry (see
    the port table in `commit_report_page`), so everything derived from the old
    one is void: width, fabric placement, and the receiver's channel count.
  - WARM — the SAME eth_src returning. The geometry stands, but it is still a NEW
    SESSION: the frame counter at offset 14 restarts wherever the box's does, so
    stream state keyed on the peer's identity alone silently survives into a
    session it does not belong to. A receiver that kept it read the seam as lost
    frames and reported thousands of counter gaps on a clean reconnect.

  Both are the same event with different consequences, which is why a consumer
  must key per-session state on (peer, session), never on the peer alone.

  # What the MASTER sends to enrol a box, in order

  The mirror of the section above, measured on a real M-200i driving a real
  S-1608 (m200i-s1608-48k-mirror__real-m200-s1608-coldboot, 2026-07-11) and
  anchored in the master's own transfer routine. Times are relative to the box
  falling silent.

    steady, box present  master  cfea announce at 1 Hz
                                 op 01 03 page 0x0019 at 1 Hz
                         box     op 01 03 page 0x0001 heartbeat, unicast, 1 Hz
    box goes silent      master  keeps announcing; page 0x0019 slows to ~2 s
    +7.2 s               master  THE SCENE TRANSFER: op 01 01 header,
                                 341 x op 01 00, op 01 02 final — 0.684 s
                                 then one page 0x0019
                                 and the WHOLE TRANSFER AGAIN every 2.695 s
    +17.8 s              box     op 01 03 page 0x0010 config-announce, then
                                 op 04 03 tags 0100 / 0000 / 0302, then heartbeat
                                 [AMENDED 2026-09-09: that is the GRANT, not the join.
                                  A joining box sends TWO records - 0100 JOIN then 0302
                                  BOX_READY - and the MASTER answers three: echo(0100),
                                  its OWN 0000 head_mark, echo(0302). Measured both ways:
                                  an S-0808 joining an S-1608 sent two and was answered
                                  with three; an S-1608 joining an S-0808 sent three and
                                  drew three echoes, and a replay with its second record
                                  repeated drew only two, so the master echoes one per
                                  DISTINCT record. The joining box then sends its FIRST
                                  HEARTBEAT on the very next frame, BEFORE the grant:
                                  16.1162 JOIN, 16.1164 BOX_READY, 16.1165 heartbeat,
                                  grant at 16.118.]
    +19.5 s              master  the head-amp sweep: 48 op 04 03 TAG 0101
                                 records in 0.145 s — 16 wire channels 0x20..0x2f
                                 x phantom, pad, sens
    after                master  back to 1 Hz cfea + page 0x0019; the scene
                                 transfer never runs again for this session

  THE FILLER'S CONTROL AREA CARRIES THE JOINING BOX'S STATE [added 2026-09-09]. Sixteen
  `00 xx` pairs across block[0:32], and xx moves with the enrolment:

      zero   before the config-announce            (48 frames measured)
      0x52   from the announce until the grant     (8691 frames - the whole wait)
      0x7a   once granted                          (the rest of the session)

  Replaying a granted enrolment with the 0x52 window zeroed is REFUSED by an S-1608 in
  master mode, and it is the only variant of that file which is; an S-0808 in master mode
  tolerates zeros there. There is no name for the field in this grammar yet; "requesting"
  is what the wire shows it to mean.

  A STAGEBOX ON M PAIRS WITHOUT A COURTSHIP OF ITS OWN [added 2026-09-09]. An S-0808 in
  master mode emits no `cfea` announce at all and no probe cycle - only a scene transfer and
  a ~1 Hz chanmap - and it grants a slave that finds it by flooding. An S-1608 in master mode
  DOES emit `cfea` about once a second, and the box that joined it broadcast nothing at all:
  a master that calls is not hunted. Both grant by echoing the joining box's own records.

  THE CONFIG-ANNOUNCE DECLARES THE DECLARER [added 2026-09-09]. Selector 0x80 and
  board_config_code 0 in both directions, and the port table is the sender's own inventory -
  `01 01 01 01 02 02` from an 8-input box, `02 02 02 02 01 01` from a 16-input one, each
  granted by the other. It is NOT the table of the peer being addressed.

  Two properties of that order are easy to get wrong and both are load-bearing:

  - The scene transfer is REPEATED UNTIL ANSWERED, not sent once. Four complete
    bodies here, ten in an M-300 establish capture, all at the same 2.695 s
    period and all byte-identical. It stops the moment the box announces itself.
    The period is a RETRY interval on a bounded transfer, not a free-running
    cadence, and a box joining mid-transfer must not cancel it — the box joining
    is what it is for.
  - The head-amp sweep has NO bank structure. Sixteen contiguous wire channels,
    all three parameters each, one pass. A master does not address halves of a
    box and does not repeat the sweep.

  - **The ~1.7 s between the box's declaration (+17.8 s) and the master's sweep
    (+19.5 s) is an OBSERVED GAP, not a hold the box requires.** It is easy to
    read this timeline as a mandatory settle and imitate it with a wall-clock
    timer; reac-pw did, and carried a 1.6 s dwell fitted to this capture.
    Measured against both boxes on 2026-08-30, granting a SHORT SETTLE (50 ms)
    after the box has declared and been armed establishes the session just as
    reliably, three trials each, deterministic, at full declared width:

        S-1608  16/8   1.684 s -> 0.134 s
        S-4000S 32/8   1.756 s -> 0.206 s

    This follows from the state machine rather than contradicting it: a box
    leaves COLD_CONNECT **on receipt of the master's GRANT**, not after elapsed
    time. The exchange is frame-driven, so what the desk's gap records is one
    desk's scheduling, not a protocol requirement. A wall-clock dwell is still
    the right CAP for a box that has not declared — one unit is documented as
    needing ~27 s — but it is the wrong TRIGGER for one that has.

    Not settled by that measurement: whether every firmware tolerates it (two
    were tested), and audio through the box was not measured, only the declared
    port width and the wire rate.

  # Anti-goals

  This grammar does NOT model the establishment FSM as STRUCTURE — a sequence of
  frames is not a layout, and Kaitai has no way to say it. The lifecycle above is
  documented rather than parsed, and it names the frame each transition is
  carried by so the sequence is at least discoverable from the spec. Also not
  modelled: the per-model fabric slot BASE (see
  `commit_report_page`), or anything that is negotiated session state rather
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
        doc: cd ea and cf ea share the op/rec_len/payload shape; only the op
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
        doc: |
          frame[20:22] — the record length, big-endian. Named for libreac's
          consumer, which `ctrl_kind` mirrors, and NOT for what the field is;
          `control_block.rec_len` is the same bytes under their real name.
          Keeping the old name here is deliberate: this instance exists only to
          reproduce a consumer's decisions, including the one below that keys a
          classification on a LENGTH.
      link_raw:
        pos: 2
        type: u1
        enum: reac_link
        doc: |
          frame[18] — block[0], the LINK / RECORD CLASS, readable whatever the
          type word says. Classification keys on this and never on the 16-bit
          `op`, so a class the grammar has not met still classifies as far as
          its class goes instead of falling into `unknown_ctrl`.
      seg_raw:
        pos: 3
        type: u1
        doc: frame[19] — block[1], the segment flags. Bit 0 FIRST, bit 1 LAST.
      opcode_raw:
        pos: 6
        type: u1
        doc: |
          frame[22] — block[4], the SUBTYPE, which is the record's only real
          discriminator. Reached here as well as through the payload types
          because classification must not depend on the payload switch.
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
          link_raw == reac_link::aux_s4000s ? ctrl_kind::link2 :
          link_raw == reac_link::record ? (
            (seg_raw & 3) != 3 ? ctrl_kind::record_fragment :
            (dt1_model_lo == 0x12 and dt1_command == 0x12
              and dt1_tag == 0x0101) ? ctrl_kind::head_amp :
            ctrl_kind::grant) :
          link_raw != reac_link::control ? ctrl_kind::unknown_ctrl :
          opcode_raw == 0x00 ? ctrl_kind::scene_transfer :
          opcode_raw == 0x01 ? ctrl_kind::master_hb :
          opcode_raw == 0x81 ? ctrl_kind::box_hb :
          opcode_raw == 0x10 ? ctrl_kind::group_map :
          (opcode_raw == 0x80 or opcode_raw == 0x82 or opcode_raw == 0x83
            or opcode_raw == 0x84) ? ctrl_kind::config_announce :
          ctrl_kind::unknown_ctrl
        enum: ctrl_kind
        doc: |
          Frame classification, NESTED THE WAY THE RECORD IS BUILT: link, then
          segment, then subtype. libreac's consumer `reac_ctrl_parse()` was
          rewritten against the same four-field header, so the cross-check still
          compares like with like — but it is no longer a mirror of two quirks,
          because the quirks are gone from both sides at once.

          WHAT THIS REPLACES, and what it was costing. The old expression keyed
          on the 16-bit `op` and on two LENGTHS:

            op == 0x0103 and rec_len == 0x0019  ->  master_hb
            op == 0x0103 and rec_len == 0x0001  ->  box_hb
            (op >> 8) == 0x01                   ->  scene_transfer

          so every other session record — the commit report and the enroll group
          map — fell into `scene_transfer`, and a slot-map window with fewer than
          eight entries would have done the same. Two lengths were carrying a
          discriminator's job. Keying on `opcode_raw` instead is not a
          refinement of that; it is the field the box's own reader gates on
          (`FUN_0c002e94` @0c002e94 tests block[0], block[1] and block[4], never
          a length).

          MEASURED, so the change is a partition and not a reshuffle: over the
          corpus every frame that moved came out of `scene_transfer` and landed
          in `scene_transfer`, `config_announce` or `group_map`, the three
          summing to the old bucket exactly; and every `unknown_ctrl` that moved
          became `record_fragment`. Nothing moved in any other direction. That
          is asserted in `spec/reac_xcheck.py` against both expressions, and
          libreac's own corpus run reports the same shape.

          The link-4 arm keeps the one deliberate coarseness: a single-fragment
          record whose tag is not a DT1-command 0x0101 classifies as `grant`
          rather than getting a kind per tag, so the cold-connect tags 0x0302 /
          0x0500 / 0x0000 all land there. Read `dt1_tag` for the real record.

          `link2` is FIRMWARE-ONLY: the S-4000S image builds for link 0x02 and
          no capture carries one. It is a named kind rather than `unknown_ctrl`
          so that the day one appears, it is not silently a mystery.

          `none` is never produced here: a non-REAC frame fails the ethertype
          contents check before classification.
  filler_block:
    doc: |
      Type word 0x0000: an audio-only frame, no control op, CHECKSUM-EXEMPT. The
      32 bytes are 16 two-byte descriptor slot words. Downstream, a real console
      repeats the CHECKSUM of the control frame currently in force across every
      FILLER until the next one — during an establishment that is the scene chunk
      in flight; upstream, a box emits a constant word (0x007a on the
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
      records and the cf ea master announce: op(2) rec_len(2) payload(28).
    seq:
      - id: op
        type: u2
        enum: control_op
        doc: |
          The two bytes the wire has always been read as one 16-bit "op". Both
          the firmware and the corpus say they are TWO INDEPENDENT FIELDS:

            block[0]  LINK / RECORD CLASS   see `link`
            block[1]  SEGMENT FLAGS         bit 0 = FIRST, bit 1 = LAST

          EVIDENCED (image), S-1608 `FUN_0c003398` @0c003398 — the box's own
          segmented upload, read line by line:

            *buf   = 1                      the link
            buf[4] = 0                      the subtype
            BE16(buf+5) = total             only on the first frame
            if (total < 0x19) buf[1] = 3    it all fits: FIRST|LAST
            else              buf[1] = 1    FIRST, chunk 0x18, payload at buf+7
            ...
            if (remaining < 0x1b) buf[1] = 2   LAST, chunk = remaining
            else                  buf[1] = 0   MIDDLE, chunk 0x1a, payload buf+5

          So 0x0101 / 0x0100 / 0x0102 / 0x0103 are not four ops. They are ONE
          class with the segment field reading FIRST / MIDDLE / LAST / SINGLE,
          and 0x0401 / 0x0402 / 0x0403 are the same three states on link 4. The
          receive side agrees: the box's state-2 gate is
          `buf[0]==1 && (buf[1] & 1) && buf[4]==0` — the FIRST bit — and its
          state-3 gate is `buf[1] in {0, 2}` — MIDDLE or LAST
          (`FUN_0c003aae` @0c003aae, `FUN_0c003b88` @0c003b88).

          WHAT THIS RETIRES. The wireshark dissector inherited from reacdriver
          matched the first five bytes as a STRING and named the eight it had
          seen — CONTROL_ONE..FOUR, SLAVE_ANNOUNCE1..4. Those strings run a
          class, a flag field, a LENGTH and a subtype together, so they are
          model-specific by accident: `0103001084` fell through the table as
          unknown while the byte-identical S-1608 record was labelled.

          `op` is kept as the 16-bit field because that is what every capture
          and every tool indexes on; `link`, `seg` and `opcode` below are the
          same bytes named as the firmware writes them.
      - id: rec_len
        type: u2
        doc: |
          THE RECORD LENGTH, big-endian. It is a LENGTH in every case — never a
          selector. What varies is the OFFSET IT COUNTS FROM, and that variation
          is a real protocol fact rather than an inconsistency in the reading.

            every class and subtype EXCEPT one   from block[4] INCLUSIVE
            session class, subtype 0x00          THIS FRAME'S PAYLOAD ONLY,
            (the bulk transfer)                  which begins at block[7] on a
                                                 FIRST fragment and block[5] on
                                                 any other

          Every observed value checks out against that rule:

            0x0019 = 25 = 1 subtype + 8 x 3-byte slot records   block[4..28]
            0x0010 = 16 = subtype + block[5] + [6] + [7] + 12   block[4..19]
            0x000d = 13 = subtype + block[5] + [6] + 10 bytes   block[4..16]
            0x0001 =  1 = the subtype alone, an empty body      block[4]
            0x0013 = 19 = ends exactly on the SysEx 0xF7        block[4..22]
            0x0018 = 24 = an opening scene chunk, at block[7]   (0x1f - 7)
            0x001a = 26 = a middle scene chunk, at block[5]     (0x1f - 5)
            0x000e = 14 = the closing chunk, 8880 mod 26

          THE BULK EXCEPTION IS NOT A MATTER OF OPINION, and it is worth the
          space because a sister branch read the base as 4 universally. The
          scene body is 8904 bytes and arrives as 0x18 + 341 x 0x1a + 0x0e =
          24 + 8866 + 14. Under a base of 4 the payloads would instead be 21
          (block[4],[5],[6] precede the payload at block[7]) and 25, and
          8904 - 21 - 14 = 8869 is not a multiple of 25. The transfer cannot be
          reassembled under that reading at all, which is why the box's own
          sender passes the chunk size to the length store AND to the memcpy
          that fills block+7 or block+5 (`FUN_0c003398` @0c003398). The two
          0x18 / 0x1a caps are `0x1f - 7` and `0x1f - 5`: the builder reserves
          block[31] for the checksum. `spec/reac_xcheck.py` asserts the
          reassembly arithmetic both ways so this cannot drift back.

          EVIDENCED (image): `FUN_0c002f7a` @0c002f7a is a two-byte store, high
          byte first, which is what makes this big-endian; it is called by
          `FUN_0c002c70` @0c002c70 (slot map, 0x19), `FUN_0c003c8a` @0c003c8a
          (commit report, 0x10) and `FUN_0c003fe2` @0c003fe2 (link ack, 0x01).

          This supersedes the earlier reading of 0x0103's length as "a SUB-PAGE
          SELECTOR". Each sub-page does have a distinct length, so switching on
          it happens to work, but the discriminator is `opcode` at block[4].
      - id: payload
        size: 28
        type:
          switch-on: op
          cases:
            'control_op::scene_chunk': scene_chunk_payload
            'control_op::scene_header': scene_header_payload
            'control_op::scene_final': scene_final_payload
            'control_op::page_0103': page_0103
            'control_op::dt1_container': container_0403
            'control_op::announce': cfea_payload
            'control_op::dt1_first_fragment': record_fragment
            'control_op::dt1_last_fragment': record_fragment
        doc: |
          The three link-4 ops share one payload shape. 0x0403 is a record that
          fits in one frame; 0x0401 and 0x0402 are the FIRST and LAST fragments
          of a record that does not — see `record_fragment`.
    instances:
      block_checksum:
        pos: 31
        type: u1
        doc: Sum(this 32-byte block) mod 256 == 0.
      link:
        pos: 0
        type: u1
        enum: reac_link
        doc: |
          block[0]. Which logical link inside the REAC control plane the frame
          belongs to. EVIDENCED (image): every builder in both box images writes
          this byte as a literal before anything else — `*buf = 1` in
          `FUN_0c003398` @0c003398 and `FUN_0c002c70` @0c002c70 (S-1608),
          `*buf = 2` in `FUN_0c0128b8` @0c0128b8 (S-4000S only).
      seg:
        pos: 1
        type: u1
        doc: block[1]. Two flag bits; read `seg_kind`.
      seg_is_first:
        value: '(seg & 1) != 0'
        doc: bit 0. The frame opens a transfer and carries its declared total.
      seg_is_last:
        value: '(seg & 2) != 0'
        doc: bit 1. The frame closes a transfer.
      seg_kind:
        value: 'seg & 3'
        enum: seg_state
        doc: |
          The two bits together. 3 (both set) is a complete message in one
          frame, which is what every chanmap, heartbeat, declaration and
          single-frame record is.
      opcode:
        pos: 4
        type: u1
        doc: |
          block[4]. THE OPCODE — on link 1, the field that says what the message
          is; see `link1_opcode`. The grammar reaches it a second time as
          `page_0103.subtype`, because for a long time it was read as a reserved
          byte on a scene frame and as a subtype selector on an 0x0103.

          On link 4 this byte is 0x00 on every frame in the corpus and is the
          first byte of the record wrapper `00 02 00 fe`.
      opcode_link1:
        value: opcode
        enum: link1_opcode
        doc: The same byte with the link-1 opcode names attached. Meaningless
          when `link` is not `control`.
      record_class:
        value: link.to_i
        doc: The sister branch's name for `link` — 0x01 session, 0x04
          parameter. One byte, one meaning; kept as an alias so a reader
          coming from either vocabulary lands on the same field.
  cfea_payload:
    doc: |
      The cf ea master announce (op 0xffff, rec_len 0x0100). Advertises the
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
          commit_report_page.
      - id: console_field
        type: u1
        doc: |
          The PACE CODE the box follows - 0x00 = 48 kHz, 0x01 = 96 kHz,
          0x02 = 44.1 kHz. Measured across three consoles: 0x00 on the M-200
          and M-300 at 48 kHz (30+ files, hundreds of announces); 0x01 on
          the M-5000 at 96 kHz and on an S-1608 in master mode pacing
          96 kHz; 0x02 on the M-200 at 44.1 kHz (144 announces in one
          session, one more in another). A box obeys the BYTE, not the
          cadence: an S-4000S driven at 3675 frames/s with this byte at
          0x00 returned 4000 frames/s (48 kHz). The ENROLL console byte
          and the scene body's `revision` (+0x14) carry the same three
          values — see `revision` in `scene_body` — though the ENROLL byte
          has not itself been captured through a box enrolment at
          44.1 kHz.

          THE ANNOUNCE PROPOSES; THE SCENE DECIDES. This byte is broadcast at
          1 Hz and a box may act on it, but it is not where a box's rate class
          settles - `revision` is (see scene_body). EVIDENCED (rig, 2026-08-29):
          reac-pw announced 0x01 here at 8000 pps while pushing an M-200i-derived
          scene whose revision read 0x0000, and an S-1608 (firmware 2.200) held
          48 kHz through every attempt - a runtime assertion, a daemon cold boot
          at 96 kHz, and a box power-cycle into an already-running 96 kHz stream.
          Making the scene agree moved it to 96 kHz immediately and cleanly.

          ENFORCEMENT IS FIRMWARE-DEPENDENT, and the two boxes only look
          contradictory until the model above is applied. EVIDENCED (rig): an
          S-0808 (firmware 1.003) follows this byte alone, scene revision
          notwithstanding — tool- and rig-verified 2026-08-26
          (reac-captures analysis/rate_field_hunt.py over box-at-48k vs
          box-at-96k: the box's own frames are byte-identical across rates, so
          this box encodes no rate and just follows the master). An S-1608
          (firmware 2.200) requires the scene to agree, per the EVIDENCED
          paragraph above. One rule covers both: propose in the announce,
          record in the scene, stamp the record with `revision`.

          THE BYTE TRACKS THE PACE, NOT THE CONSOLE MODEL: the same M-200
          has been captured writing 0x00 at 48 kHz and 0x02 at 44.1 kHz, and
          an M-5000 and an S-1608 acting as master both write 0x01 at
          96 kHz — one console reaching two values, and two different
          consoles reaching the same value, rules out reading this byte as
          a console identifier.
      - id: box_count
        type: u2
        doc: Enrolled boxes. 0x0000 idle -> 0x0001 once a box is granted; a
          console that leaves this at 0 while granting leaves the box blinking.
      - id: rest
        size-eos: true
        doc: Zero padding, last byte the block checksum.
  scene_chunk_payload:
    doc: |
      op 0x0100 — a CONTINUATION CHUNK of the master's scene transfer, 26 bytes
      of `scene_body` (see that type). rec_len carries the chunk length, 0x001a.

      EVIDENCED (image, M-200i + M-480, byte-identical routine): the master
      writes block[1] = 0 for a continuation, stores the chunk length big-endian
      at block[2:4], and memcpy's the chunk to block[5]. EVIDENCED (corpus): every
      one of the ten distinct op-0100 payloads in `fixtures/control.json` is a
      literal 26-byte slice of the recovered 8904-byte body, at an offset of
      24 + 26k; a random 26-byte control is not.

      THIS IS NOT A PROBE. It was read as one for a year, and the "period-10
      rotation with a phase step of +6 and a sub-state byte of 0x02 or 0x03" was
      the scene's own 10-byte `scene_record` stride seen through a 26-byte
      window: 26 mod 10 = 6, and gcd(26,10) = 2 leaves exactly the five even
      phases the corpus catalogued. The "sub-state" is the record's
      `inventory_cell` — 0x02 where the chunk lands in the desk's declared analog
      inputs, 0x03 where it lands in the absent tail — not a master state. A
      master that "emits only a subset of the phases" is a master that truncates
      the transfer, which is the real defect the phase-counting was detecting.
    seq:
      - id: chunk_reserved
        type: u1
        doc: block[4], zero. The box refuses the frame unless it is zero.
      - id: chunk
        size: 26
        doc: block[5:31] — scene_body[24 + 26*k .. +26] for the k-th chunk.
      - id: checksum
        type: u1
  scene_header_payload:
    doc: |
      op 0x0101 — the FIRST phase of the scene transfer. Declares the total and
      carries the body's first 24 bytes. Its payload starts two bytes later than
      a continuation's: the total occupies block[5:7], so the body begins at
      block[7], not block[5].

      EVIDENCED (image): `movi20 #0x22c8` then a big-endian 16-bit store to
      block[5]; the box gates on it (`if (declared_total != 8904) refuse`) before
      staging 24 bytes from block[7].
    seq:
      - id: header_reserved
        type: u1
        doc: block[4], zero.
      - id: scene_total_len
        type: u2
        doc: |
          block[5:7] — the TOTAL length of the scene body that follows, 0x22c8 =
          8904 on every desk generation seen.

          EVIDENCED both. This was previously named `model_const` and documented
          as "a protocol identity constant, 0x22c8 on the S-1608 family". The
          firmware says otherwise on both sides and the firmware wins: it is a
          length, it is the MASTER's, and it is hardcoded before the master knows
          what box is attached. It is 8904 because the body is
          0x37c + 8 + 800*10 + 4 — the SCEN block's own arithmetic, which the box
          carries independently as a record count of 800.
      - id: body_head
        size: 24
        doc: block[7:31] — scene_body[0:24], which is why a capture of this frame
          alone shows the ASCII "1234" that opens the body.
      - id: checksum
        type: u1
  scene_final_payload:
    doc: |
      op 0x0102 — the LAST chunk, and the phase the box's commit is gated on.
      rec_len is 0x000e = 14 = 8880 mod 26, so it is a length like any other
      chunk's, not a fixed block.

      EVIDENCED (image): the master sets block[1] = 2 when the remaining count
      has fallen to 26 or below; the box's reassembler accepts block[1] in {0, 2}
      and finishes on 2 with remaining reaching zero, which is what enters the
      state-4 commit. A transfer that never delivers this frame leaves the box in
      reassembly for the life of the link, with head-amp staged and never active.
    seq:
      - id: final_reserved
        type: u1
      - id: chunk
        size-eos: true
        doc: block[5:5+rec_len] — the tail of the body, 14 bytes, then padding
          to the block end. Sized to end-of-stream rather than to rec_len so a
          short or padded final frame still parses; read rec_len for the true
          count.
  scene_body:
    doc: |
      THE SCENE — the 8904-byte body the three ops above carry, reassembled as
      `scene_header.body_head` + each `scene_chunk.chunk` in emission order +
      `scene_final.chunk`. It is NOT a frame, so nothing in `seq` reaches it;
      parse it from a recovered body (reac-pw tools/recover-scene.py).

      It is a property of the DESK, not of the box: an M-300 sends the same bytes
      to an S-1608 and to an S-0808, and the only bytes that differ between an
      M-200i's and an M-300's are the four low bytes of `master_id`.

      # Evidence classes used below

      EVIDENCED (image) — read out of a firmware image, as a resolved pointer, a
      literal-pool word or an instruction operand. EVIDENCED (corpus) — measured
      over the capture set. EVIDENCED (executed trace) — observed by running the
      box's own code over real capture data in an SH-2A interpreter. INFERRED —
      everything else, and it says so.

      # Endianness

      Fields here are LITTLE-endian, against the frame's big-endian everywhere
      else. EVIDENCED (image): the box is an SH-4 in little-endian mode and reads
      these with native `*(short *)` loads, so LE is what the desk must write for
      the box to agree — and every value reads as a small number that way and as
      a large one the other.

      # What the box does with it

      Every offset below is a pointer resolved out of the S-1608's own literal
      pool against one staging base, and every one lands on a boundary the wire
      body shows independently. The box stages the whole body into one buffer,
      then its state-4 commit reads `unit_map_select`, publishes `revision`,
      promotes all 80 slots into its LIVE head-amp table, copies 6 bytes of
      `master_id`, installs the map, pushes twelve groups, and emits the
      `01 03 00 10` report.

      Two things follow that an emitter must get right. The commit writes the
      SAME (0, 1, 0, 0) into all eighty slots, so **a scene body cannot address an
      individual channel**. And it overwrites the very table an op-0403 head-amp
      record writes directly, so **records must FOLLOW the commit, never precede
      it** — see `head_amp_data`.

      # What is the console's, and what is the format

      Across 27 real-desk bodies — three desk generations, four box models — 8 of
      the 8904 bytes vary and 8896 are constant. Two of the four varying runs are
      fields; two are M-5000 padding that changes between that desk's own runs.

        +0x014      1 B   `revision`, a rate class: 0 at 48 kHz, 1 at 96 kHz,
                          2 at 44.1 kHz (n=1 for the 44.1 kHz reading)
        +0x343..345 3 B   the low half of `master_id`
        +0x366..367 2 B   M-5000 only, uninitialised
        +0x22c6..7  2 B   M-5000 only, uninitialised

      So an emitter fills in `master_id` and `revision` and copies the rest. A
      body built from this layout alone, with no template bytes, reproduces a real
      M-200i's and a real M-300's exactly.

      # What the box VALIDATES, and what it does not

      The commit checks **three four-byte tags and nothing else**: `magic` at
      +0x000, `sysp.tag` at +0x368 and `scen.tag` at +0x37c. Fail any one and it
      promotes nothing and replies nothing, while the transfer still looks
      complete from the wire. EVIDENCED (executed trace): the box's own task loop
      run over real capture data, with the body zeroed in 128-byte windows —
      exactly 2 of the 70 windows break the commit, and they are windows 0 and 6,
      the only two that contain a tag. That independently reproduces the field map
      above, which was built from resolved pointers rather than from execution.

      **The tags are a GATE, not a description of what the box uses.** Measured on
      real hardware: a body of zeros carrying only the three tags PASSES the
      commit — the box accepts the transfer and replies — and leaves it reporting
      `model=unknown` with ZERO capture ports, where the recovered body gives
      `model=s1608` with sixteen. So the box reads far more of the 8904 than it
      checks, and the parts it reads without checking are the ones that decide
      what it thinks it is.

      Read that before concluding the unvalidated 8892 bytes are free. They are
      not: a wrong value outside the tags is not rejected, it is accepted and
      acted on. An emitter should REPRODUCE the constant this grammar describes,
      not improvise it — and the two fields at +0x14 and +0x340 are the only ones
      it should be filling in at all.

      # What it does NOT carry

      No per-channel values of any kind. All 880 records in every real body read
      (cell, 0, 1, 0, 0), and the commit's copy of fields +2..+8 moves constants.
      `slots` is the DECLARATION table, not a head-amp staging table. Head-amp
      values travel entirely on the op-0403 TAG 0x0101 sweep, where consecutive
      channels do carry different sens values. The scene's job in enrolment is to
      be COMPLETED, not to be filled in: the box's commit is unconditional over
      all 80 slots and is the only unconditional promoter of its head-amp state.
    seq:
      - id: magic
        contents: [0x31, 0x32, 0x33, 0x34]
        doc: ASCII "1234". EVIDENCED both.
      - id: unit_map_select
        type: u2le
        doc: |
          +0x04. Selects which of two maps the commit applies: 1 takes
          `map_a_arg`, anything else takes `map_b`. EVIDENCED both — the box
          branches on it at commit, and the wire reads 0x0001 on every desk
          generation and against every box.
      - id: reserved_06
        size: 2
      - id: map_a_arg
        type: u2le
        doc: +0x08. The value the commit passes on when `unit_map_select` is 1.
          EVIDENCED (image) that it is read there; 0x0004 on every capture. What
          it selects is UNRESOLVED.

          Both arms of the switch call the SAME setter and differ only in which
          field they read from (EVIDENCED, executed trace), so this is one action
          with two sources, not two behaviours.
      - id: unknown_0a
        size: 10
        doc: +0x0a..+0x13. Constant across every desk seen (01 80 02 00 01 00 01
          00 01 00). No reader located in either image. UNRESOLVED.
      - id: revision
        type: u2le
        doc: |
          +0x14. The box caches this and compares it before it will re-read the
          three sub-objects: a body whose revision differs is treated as changed
          without any further comparison. EVIDENCED both — the compare is in the
          image, and it is one of the non-padding bytes that differ across desks.

          SO IT IS THE VERSION STAMP ON THE DESK'S RECORD, and the only way any
          scene change reaches a box that has already cached one. A master that
          holds it CONSTANT can never revise what it declared, whatever else it
          sends. EVIDENCED (rig, 2026-08-29, S-1608 firmware 2.200): pinned to
          0x0001 the box took 96 kHz and then LATCHED there - neither a console
          assertion back to 48 kHz nor a daemon cold boot at `--rate 48000`
          moved it, because the value never changed and the box never re-read.
          Derived from the announced pace code instead (0x00 at 48 kHz,
          0x01 at 96 kHz) the same box followed the console in both
          directions: 8004 pps against our 8004 at 96 kHz and 4002/4002 at
          48 kHz, no wire-pace mismatch, drift -3.6 ppm, zero discards.

          IT IS A RATE CLASS THAT TRACKS THE MASTER'S PACE, NOT THE CONSOLE
          MODEL: a real M-200
          writes `revision = 0x0002` in a scene header captured while
          mastering at 44.1 kHz — the same M-200, same MAC, writes
          `revision = 0x0000` at 48 kHz in 1,550 other scene headers, and an
          M-5000 writes `revision = 0x0001` at 96 kHz, as does an S-1608 in
          master mode pacing 96 kHz. So `revision` reads 0 at 48 kHz, 1 at
          96 kHz and 2 at 44.1 kHz.

          THE n=1 CAVEAT IS LIFTED. Three complete 8904-byte bodies recovered
          from an M-200 mastering at 44.1 kHz all read `revision = 0x0002` and
          are byte-identical to each other; diffed against a body from the SAME
          console MAC at 48 kHz they differ in exactly ONE byte of 8904, and it
          is this one. Everything else — `master_id`, both tag blocks, all 880
          records — is the same at both rates. EVIDENCED (corpus, 2026-09-13,
          `reac-captures m200-enrol-441k-2026-09-13/analysis.md`).
      - id: reserved_16
        size: 4
      - id: slots
        type: scene_record
        repeat: expr
        repeat-expr: 80
        doc: |
          +0x1a, 800 bytes. EVIDENCED both: the box memcmp's exactly 800 bytes
          here and its commit loop copies 80 records at a stride of 10.

          The first 48 records are the same 48-slot declaration space the box
          declares back in `commit_report_page`: the commit walks twelve cells
          at a stride of 0x28 — four records each — and pushes record[4i].cell
          into its cell table. So the desk declares its inventory to the box in
          exactly the vocabulary the box declares its own. An M-200i sends eight
          cells of `analog_input` and four of `absent`: 32 declared inputs.

          What records 48..79 are for is UNRESOLVED — the commit copies them, no
          reader has been located, and they read `absent` on every capture.
      - id: reserved_33a
        size: 6
      - id: master_id
        size: 6
        doc: |
          +0x340. The desk's own MAC, and the six bytes the commit copies into
          the box's live master-id slot. EVIDENCED both: the pool pointer resolves
          to staging + 0x340, and the four low bytes are the ONLY difference
          between an M-200i's scene and an M-300's.
      - id: reserved_346
        size: 4
      - id: peer_id_1
        size: 6
        doc: +0x34a. ff:ff:ff:ff:ff:ff on every capture. INFERRED that it is a
          peer slot, from position and shape alone — no reader located.
      - id: reserved_350
        size: 4
      - id: peer_id_2
        size: 6
        doc: +0x354. As peer_id_1. INFERRED.
      - id: map_b
        size: 14
        doc: +0x35a. The value the commit passes on when `unit_map_select` is NOT
          1. EVIDENCED (image) that the commit reads here; its length is bounded
          only by the next named field, and the SHAPE is INFERRED. It is all
          zero on every CONSOLE capture; an S-1608 in master mode writes
          `33 08` at +0x360 and `47 01` at +0x364, so the field is used and the
          shape stays open (corpus, 2026-09-13,
          `reac-captures box-to-box-2026-09-13`).
      - id: sysp
        type: scene_sysp
        doc: +0x368.
      - id: scen
        type: scene_scen
        doc: +0x37c.
  scene_record:
    doc: |
      The 10-byte record the scene uses in both its tables. EVIDENCED (image):
      the commit copies fields at +2, +4, +6 and +8 from staging to live and
      pointedly does NOT copy +0, which is instead read by the twelve-cell loop.

      Every record in every capture reads (cell, 0, 1, 0, 0), so the scene does
      NOT carry per-channel head-amp values — those arrive separately as op-0403
      TAG 0x0101 records. The commit is the GATE that makes staged head-amp
      active, not the payload that sets it.
    seq:
      - id: cell
        type: u2le
        enum: inventory_cell
        doc: |
          +0. NOT promoted by the commit; read by the twelve-group loop from every
          fourth record. Two readings of what it means, and the grammar does not
          choose between them:

          - a PHANTOM GROUP marker — EVIDENCED (executed trace) that the loop it
            feeds drives the phantom groups, and phantom is per group of four,
            which is exactly this stride;
          - an INVENTORY CELL in the same vocabulary as
            `commit_report_page.cells` — INFERRED, from the values coinciding
            (0x02 analog input, 0x03 absent) and the twelve-by-four grouping
            coinciding.

          They may be the same thing seen from two ends. Nothing in either image
          names it, so the enum here is a convenience and not a claim.
      - id: field_2
        type: u2le
      - id: field_4
        type: u2le
        doc: 0x0001 in every record of every capture.
      - id: field_6
        type: u2le
      - id: field_8
        type: u2le
  scene_sysp:
    doc: |
      +0x368, 20 bytes — the desk's SYSTEM sub-object. EVIDENCED both: the tag is
      one of only three ASCII runs in the whole body and sits exactly at the
      offset the box's change-detector hard-codes. That detector compares just two
      cells of it, `key` and `flag`.
    seq:
      - id: tag
        contents: [0x53, 0x59, 0x53, 0x50]
      - id: version
        type: u2le
        doc: 0x0001 on every capture.
      - id: key
        type: u2le
        doc: +6. One of the two cells the box compares. EVIDENCED (image).
      - id: flag
        type: u1
        doc: +8. The other. EVIDENCED (image).
      - id: rest
        size: 11
        doc: |
          +9, 11 bytes. Zero on every console. ITS LAST TWO BYTES ARE WHERE
          `XVSCEN` COMES FROM: at body +0x37a an S-1608 in master mode writes
          `59 56`, and `scen.tag` begins at +0x37c, so an ASCII scan of that
          body returns the six-character run `YVSCEN`. There is no six-byte tag
          — the run is two bytes of this field abutting the four-byte `SCEN`,
          and the box's commit gates on `SCEN` at +0x37c. The old notes'
          `XVSCEN` (0x58 0x56 ...) is that run read one bit off, or the same
          field carrying a different value on another device. EVIDENCED
          (corpus, 2026-09-13, `reac-captures box-to-box-2026-09-13`, two
          complete 8904-byte bodies, byte-identical).
  scene_scen:
    doc: |
      +0x37c to the end — the desk's SCENE sub-object, and the bulk of the body.
      EVIDENCED both: the tag sits at the offset the box hard-codes, the box
      compares `key` and then memcmp's `entries` at a length of its own record
      count times ten, and that count resolves out of the image as 800.

      The body's total length is this block's arithmetic and nothing else:
      0x37c + 8 + 800*10 + 4 = 0x22c8 = 8904. The number the master hardcodes and
      the box gates on is the size of this structure, not a magic constant.
    seq:
      - id: tag
        contents: [0x53, 0x43, 0x45, 0x4e]
      - id: version
        type: u2le
        doc: 0x0001 on every capture.
      - id: key
        type: u2le
        doc: +6. Compared by the box before it looks at `entries`.
      - id: entries
        type: scene_record
        repeat: expr
        repeat-expr: 800
        doc: |
          8000 bytes. Same record shape as `slots` — the box memcmp's it at a
          stride of ten — but reached through a different sink, so the two are
          not the same table. Every entry reads `absent` on every capture, which
          is what an empty scene should look like; nothing here has been seen
          populated, so what an entry MEANS is UNRESOLVED.
      - id: trailer
        size: 4
  page_0103:
    doc: |
      op 0x0103 is class 1 carried whole in one frame — both fragment bits set.
      Its ONE discriminator is `payload[0]`, block[4], the byte a scene frame
      requires to be zero:

        0x00  a scene fragment
        0x01  the master's SLOT MAP, eight 3-byte records a frame
        0x10  the master's enroll group map
        0x81  the box's link-check ack
        0x80 0x82 0x83 0x84  the box's state-4 COMMIT REPORT

      Bit 7 marks a box reply. That is why `01 03 00 10` and a head-amp block
      share a high byte without being the same message.

      THIS DOC USED TO SAY op 0x0103 HAD TWO DISCRIMINATORS, the second being
      `rec_len`. It does not. rec_len is `rec_len`, a plain record byte count on
      every op (see `control_block.rec_len`), and 0x0019 / 0x0010 / 0x000d /
      0x0001 are the four subtypes' current sizes, not selectors.

      It also called subtype 0x01 "head-amp". The box's reader FUN_0c002e94
      gates it on block[0]==1, block[1]==3, block[4]==1 and hands each 3-byte
      record to FUN_0c002d42, the SLOT ingest. Each record is
      {slot, cell+flags, sens} — so it is the channel map AND it carries
      head-amp sensitivity, and the old two names were each half of it.

      THE 0x80 ARM IS NO LONGER UNEXPLAINED. S-1608 FUN_0c003c8a picks between
      two literal-pool bytes on a link-state test: 0x82 from DAT_0c00401c when
      FUN_0c00f9f2 returns 1, 0x80 from DAT_0c00401e otherwise, and the same
      branch decides whether payload[3] carries the board-configuration code or
      a zero. S-4000 has the identical shape with its own pair, 0x84
      (DAT_0c013750) and 0x83 (DAT_0c013752). So the literal is per-model and
      per-link-state, and matching it is a bug: an S-0808 and an S-4000S both
      send 0x84 where an S-1608 sends 0x82. Match `is_reply`.

      The enroll group map (0x10) is only ever a REPLY — its builder is
      pool-referenced from exactly one word, inside the master's state-3 wait —
      so it follows a 0x83 or 0x84 announce and never a 0x80 or 0x82. Its ten
      bytes take three values only: 0x00, 0x41, 0xc3. EVIDENCED (image).
    seq:
      - id: page
        size-eos: true
        type:
          switch-on: subtype
          cases:
            0x01: chanmap_page
            0x10: enroll_group_map
            0x80: commit_report_page
            0x82: commit_report_page
            0x83: commit_report_page
            0x84: commit_report_page
        doc: |
          SWITCHED ON THE SUBTYPE, which is what the box's own reader does.
          This used to switch on `rec_len`, and it parsed the corpus only
          because each subtype happens to have one size today — a slot-map
          window with fewer than eight entries would have fallen through
          silently. The four commit-report arms are the two model-specific
          literal pairs, not four meanings; see `selector`.
    instances:
      subtype:
        pos: 0
        type: u1
        doc: |
          block[4], the first byte of this payload, and the record's ONLY
          discriminator. 0x00 scene, 0x01 the master's slot map, 0x10 the
          enroll group map, 0x81 the box's link-check ack, 0x80/0x82/0x83/0x84
          the box's state-4 commit report. Bit 7 set means the record is
          travelling BOX -> MASTER.
      is_reply:
        value: '(subtype & 0x80) != 0'
        doc: The direction bit. Match this rather than a literal — a consumer
          that matches 0x82 sees an S-1608 and misses an S-0808.
      page_kind:
        value: >-
          subtype == 0x01 ? page_kind::chanmap :
          (subtype & 0xf0) == 0x80 and subtype != 0x81 ? page_kind::commit_report :
          subtype == 0x10 ? page_kind::enroll_group_map :
          subtype == 0x81 ? page_kind::box_heartbeat :
          page_kind::unknown_page
        enum: page_kind
        doc: Derived from the subtype. It used to be derived from `rec_len`,
          which is a length and cannot classify anything.
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
    doc: |
      A three-byte record: `{slot, flags, value}`. It is the SAME record shape
      in both directions, and the box's own transmitter is the inverse of its
      receiver, field for field.

      EVIDENCED (image), S-1608 `FUN_0c002bb2` @0c002bb2 building a record from
      the per-slot table at `DAT_0c002e70` (resolves to 0x0c0cf85a) with a
      10-byte stride:

        rec[0] = slot
        rec[1] = (cell << 4 & 0xf0)
               | (tbl[slot*10 + 4] & 1) << 3
               | (tbl[slot*10 + 8] & 1) << 2
               | (tbl[slot*10 + 6] & 1) << 1
        rec[2] = (u8) tbl[slot*10 + 2]

      and `FUN_0c002d42` @0c002d42 applying one, writing exactly those four
      cells back. The mask 0xf0 is `DAT_0c002d7c`, read out of the image, so
      the cell code really is a full four bits.

      THE THIRD BYTE IS NOT PADDING. It is the per-slot VALUE, and the cell it
      writes — table + 2 — is the same cell the box's own gain path reads:
      `FUN_0c007fbc` @0c007fbc copies `table[+2]` into its actuation shadow and
      passes it to `FUN_0c007e6a` @0c007e6a, the SENS setter. The record and the
      head-amp DT1 record therefore reach one table by two routes.

      CORROBORATED: over 183 872 chanmap records in 72 captures the value byte
      is 0x00 every single time and the flags byte takes only 0x28 and 0x38 on
      real slots — but every one of those captures has a CONSOLE as the master.
      No console has ever been seen to put a value in this record.

      A BOX MASTER DOES. An S-1608 in M mode writes flags 0x18 (72), 0x28 (144),
      0x30 (151) and 0x38 (72) on its own op-0x01 sweeps, with value 0x20 on 151
      of 448 records, and the S-4000S enrolled to it echoes the same bytes back
      in its op-0x81 replies. Control in the same pass: an M-200 driving that
      same S-4000S writes 0x28/0x38 and value 0x00, 288 of 288. The capability
      both box images carry is exercised — by a box master, never by a desk.
      Note 0x30 clears bit 3, a combination no console emits. EVIDENCED
      (corpus, 2026-09-13, `reac-captures box-to-box-2026-09-13`).
    seq:
      - id: slot
        type: u1
        doc: |
          Fabric channel 0x00..0x2f, or one of two record ids that are not
          channels: 0xfe (`DAT_0c002d7e`, `DAT_0c002e6e`) and 0xff
          (`DAT_0c002d80`), both read out of the image rather than inferred.
      - id: cell_and_flags
        type: u1
        doc: |
          HIGH NIBBLE the inventory cell for the group this slot anchors, LOW
          NIBBLE three per-slot booleans. 0x28 for slots below 0x28 and 0x38 for
          0x28..0x2f is the corpus's constant, and it decomposes as cell 2
          (analog input) or 3 (absent) with bit 3 set on every slot.

          It was called `bank` here, which named the observed byte rather than
          its fields. The box's ingest FUN_0c002d42 splits it: the high nibble
          reaches the group map only where (slot & 3) == 0, and bits 3, 2 and 1
          go to the slot's active-table fields +4, +8 and +6 respectively.
          WHICH BOOLEAN IS WHICH IS NOT IN THE IMAGE — the firmware routes them
          to GPIO pin banks without naming them, exactly as for head_amp_data's
          param.
      - id: sens
        type: u1
        doc: |
          The slot's SENS step. It was called `pad`, which was a guess. The
          ingest writes this byte into active-table field +2, and field +2 is
          what the head-amp apply FUN_0c007fbc hands to FUN_0c007e6a, the SENS
          gain-table lookup. Same axis and same units as head_amp_data.value
          for param `sens`. EVIDENCED (image).
    instances:
      is_group_anchor:
        value: 'slot < 0x30 and (slot & 3) == 0'
        doc: |
          True on the 12 entries the box's per-record push consumes (every 4th
          fabric slot). Neither non-channel record id can qualify: the guard in
          `FUN_0c002d42` @0c002d42 is `slot < 0x30`, which is a stronger and
          more faithful statement than excluding 0xfe by hand.
      group:
        value: 'slot >> 2'
        doc: |
          Head-amp group index this entry anchors, 0..11, meaningful only where
          is_group_anchor. Derived from the firmware's push, not from the wire.
      cell_type:
        value: 'cell_and_flags >> 4'
        enum: inventory_cell
        doc: |
          The high nibble of `cell_and_flags`, the code stored into the group map:
          2 analog_input for groups 0..9, 3 absent for groups 10..11, on every
          console and every box model observed.
      flag_slot_4:
        value: '(cell_and_flags >> 3) & 1'
        doc: bit 3 -> table + 4. Set on every real slot in every capture.
      flag_slot_8:
        value: '(cell_and_flags >> 2) & 1'
        doc: bit 2 -> table + 8. Zero in every capture.
      flag_slot_6:
        value: '(cell_and_flags >> 1) & 1'
        doc: |
          bit 1 -> table + 6. Zero in every capture. Of the three, this is the
          one the S-1608's group apply carries into its shadow and never passes
          to a setter (`FUN_0c007fbc` @0c007fbc).
      is_identity_record:
        value: 'slot == 0xfe'
        doc: |
          The record id 0xfe is not a channel and not merely a wrap marker. Its
          FLAGS byte is routed somewhere no channel record goes:
          `FUN_0c002d42` @0c002d42 passes it to `FUN_0c0051c4` @0c0051c4, which
          stores it in the one-word identity cell at 0x0c080616, and to
          `FUN_0c004158` @0c004158, the 12-slot vector's header.

          That cell is what the box's change detector reads:
          `FUN_0c0045ec` @0c0045ec compares it against the value it observes and,
          on a mismatch, latches link-loss and drops the FSM to state 0 — which
          is the mechanism behind a box resetting when a new master takes over.
          Both pool slots were resolved from the image (0x0c0046bc -> 0x0c0051ba
          the getter, 0x0c0046c4 -> 0x0c0051c4 the setter).

          Reading the byte as "the master's identity" is INFERRED from that
          mechanism; the firmware names nothing. CORROBORATED: such records
          appear in every session, value always 0.

          THE FLAGS BYTE IS THE PACE CODE — the same three-valued rate class
          `cfea` block[17] and `scene_body.revision` carry. Per talker over
          108 captures / 5 295 229 REAC frames, every real device is collinear:
          M-200 `c9:cc:03` writes 0x00 in 3 178 sweeps at 48 kHz and 0x02 in 24
          at 44.1 kHz, against `cfea` pace 0x00 / 0x02 on the same MAC; M-200i,
          M-300 and two more desks write 0x00 with pace 0x00; two M-5000s write
          0x01 with pace 0x01; and an S-1608 and an S-4000S in master mode at
          96 kHz write 0x01 too — neither is an OHRCA console, which is what
          rules out a console-generation reading. Only our own stack breaks the
          line (reac-pw emits pace 0x01 with marker 0x00 in 11 sweeps), and that
          is a defect on our side. EVIDENCED (corpus, 2026-09-13,
          `reac-captures m200-enrol-441k-2026-09-13/analysis.md`).
      is_filler_record:
        value: 'slot == 0xff'
        doc: |
          The id the box's builder emits for a cursor past the sentinel
          (`DAT_0c002d80` = 0xff), all-zero body. FIRMWARE-ONLY: the cursor
          wraps at 0x30 so the branch is unreachable on that path — Ghidra says
          so independently, removing it as dead code — and no capture in the
          corpus contains one.
  commit_report_page:
    doc: |
      op-0103 subtype 0x8x: the box's STATE-4 COMMIT REPORT. It is what the
      master enrols the box from, so every field below is still a PLACEMENT
      CARRIER — but the name and the timing were both wrong here until
      2026-08-23 and the correction matters.

      IT IS NOT A COLD-CONNECT ANNOUNCE. The box runs a scene FSM (S-1608
      FUN_0c0037ee): state 2 takes the master's opening scene fragment, state 3
      reassembles the continuations, and state 4 — FUN_0c003c8a — promotes the
      staged slot table into the active one and THEN builds this record. So it
      is emitted once, at the END of the master's scene transfer, not at the
      start of the session. The corpus agrees: in
      m200-s1608-handshake-ctrl-2026-07-11 the master's scene fragments run
      9.31 s to 12.69 s and the box sends this at 14.46 s, frame 1090,
      immediately before the head-amp sweep at 14.47 s. One per establishment.

      WHY THIS MATTERED. reacdriver called the same record SLAVE_ANNOUNCE1 and
      our wireshark dissector inherited the name, so a record that means "I have
      committed your scene" read as a record that means "hello, I exist".

      PLACEMENT IS DELIBERATELY NOT IN THIS GRAMMAR. The per-model slot base
      (an S-1608 is addressed at 0x20 while an S-0808 and an S-4000S are both at
      0x00) is NEGOTIATED SESSION STATE, not a field: no byte in any frame
      carries it. A 42-establishment, three-console, four-unit study killed every
      candidate law that could be tested — lowest-fit, top-alignment, f(console),
      f(enrolment order), f(box MAC), f(cell map), f(enroll map), f(chanmap) —
      and left three carriers that the corpus cannot separate because they are
      perfectly collinear across every row: the declared input WIDTH, the
      `selector` byte, and `board_config_code` (for which `base == code * 0x10`
      holds arithmetically on every row). Parse the carriers; do not encode a
      base.

      AND THE THIRD CARRIER IS NOW THE WEAKEST OF THE THREE, not the strongest.
      It was called `unit_offset` and its arithmetic made it look like the law
      in waiting. The image says it is a board-configuration code that also
      selects which cell layout the box reports, so its collinearity with the
      declared width is a mechanism and not a coincidence — which means it
      carries no information the cells do not already carry, and cannot be the
      base. See reac-pw docs/PLACEMENT-EVIDENCE.md for the corpus, the dead
      candidates and the five-run experiment that would settle it.
    seq:
      - id: selector
        type: u1
        doc: |
          The subtype byte again, repeated as the first payload byte. Observed
          0x82 on the S-1608 and 0x84 on both the S-0808 and the S-4000S, which
          is why it reads as a model family and is used as a placement carrier.

          IT IS NOT PURELY A MODEL ID. FUN_0c003c8a picks it at run time
          between two literal-pool bytes on a link-state test — S-1608 0x82
          (DAT_0c00401c) or 0x80 (DAT_0c00401e), S-4000 0x84 (DAT_0c013750) or
          0x83 (DAT_0c013752) — and the same branch decides `board_config_code`
          below. The corpus's clean 0x82-vs-0x84 split is the models' first
          arms. Read the cells for the width; treat the selector as a hint.
          EVIDENCED (image + corpus).

          THE SECOND ARM IS 0x80 ON BOTH MODELS, and 0x83 has never reached the
          wire. An S-4000S (`00:40:ab:c4:06:80`) enrolling to an S-1608 in M
          mode with no console on the segment declares selector 0x80, twice,
          byte for byte. The SAME physical box declaring to an M-200 two hours
          earlier declares 0x84, and the two blocks differ in exactly one byte
          plus the checksum it drags (0x4c -> 0x50, the precise compensation):
          `board_config_code` is 0x00 in both arms for this model and all twelve
          cells are identical. So the second arm is one shared constant, not a
          per-model pair, and this capture cannot speak to the zeroing (the byte
          is already zero). EVIDENCED (corpus, 2026-09-13,
          `reac-captures box-to-box-2026-09-13`, t = 1789331548.347566 and
          1789331583.887980; the 0x84 row is `m200-enrol-s4000-441k-2026-09-13`
          t = 1789330642.170256).
      - id: reserved
        size: 2
        doc: 00 00 on every capture.
      - id: board_config_code
        type: u1
        doc: |
          0x02 on the S-1608, 0x00 on the S-0808 and S-4000S. It was called
          `unit_offset` and treated as the most law-shaped placement carrier,
          because base == unit_offset * 0x10 holds on every observed row. THE
          IMAGE SAYS IT IS NOT AN OFFSET.

          On the S-1608 it is FUN_0c00f6a8, which returns a cell set by
          FUN_0c00f738 to 2 or 3 depending on a board-presence read; and that
          same cell is what FUN_0c00f7f8 consults to decide WHICH cell layout to
          install — 2 gives cells {2,2,2,2,1,1,3...} and anything else gives
          {1,1,1,1,2,2,3...}. So this byte and the cells below are two views of
          one board-configuration decision, which is exactly why they look
          collinear with the width. It is also zeroed outright in the builder's
          second arm, so it is not even a stable per-model value.

          The arithmetic coincidence stands and the interpretation does not.
          EVIDENCED (image, S-1608 FUN_0c003c8a + FUN_0c00f738 + FUN_0c00f7f8).
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

      MEASURED AT WIDTH 8 AND WIDTH 32 ONLY. Every group-map frame in a large
      corpus (107 total) reduces to one of two shapes: one front-packed 0x41
      input group, 8-wide (n=95), or four, 32-wide (n=6) — each also seen with
      `console_field = 0x01` from the M-5000 (n=4, n=2). No 16-wide (S-1608)
      group-map frame has been captured — a 16-wide row is a prediction of the
      width rule above, not a measurement.
    seq:
      - id: selector
        type: u1
        doc: 0x10.
      - id: selector2
        type: u1
        doc: 0x04.
      - id: console_field
        type: u1
        doc: |
          THE PACE CODE, not a console generation — the same rate class cfea
          block[17], scene_body.revision and the chanmap 0xfe marker carry:
          0x00 at 48 kHz, 0x01 at 96 kHz, 0x02 at 44.1 kHz.

          The deciding pair is one console and one box class two bytes apart.
          M-200 c9:cc:03 enrolling a 32-input box writes
          `04 00 41 41 41 41 00 00 00 00 00 c3` at 48 kHz and
          `04 02 41 41 41 41 00 00 00 00 00 c3` at 44.1 kHz — identical in
          all eleven other bytes. 0x01 read as "OHRCA" only because the M-5000
          is the desk that runs 96 kHz; it writes 0x01 over an 8-wide map and a
          32-wide one alike. EVIDENCED (corpus, 2026-09-13:
          `reac-captures m200-enrol-s4000-441k-2026-09-13`, t = 1789330642.379775,
          one map 209.5 ms after the box's commit report; the 48 kHz rows are
          `matrix-m200-s4000-2026-07-24` and `matrix-m200-s0808-2026-07-11`).

          NO CONSOLE HAS BEEN SEEN TO SEND A GROUP MAP TO A 16-INPUT BOX. All
          108 group maps in the corpus are 8-wide or 32-wide; 22 captures whose
          only box is an S-1608 — five of them full enrolments, including a
          44.1 kHz one whose whole 30 s after the box's commit report is on file
          — carry none. The 2 x 0x41 row is a prediction of the width rule and
          may describe a frame that is never sent.
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
      group_bytes:
        pos: 3
        size: 10
        doc: |
          The same ten bytes as `input_groups` + `output_groups`, as ONE array —
          which is how the only firmware that parses this page reads them.

          EVIDENCED (image), S-4000S, the FSM arm gated on
          `buf[0]==1 && buf[1]==3 && buf[4]==0x10` with `BE16(buf[2:4]) == 0x0d`
          (S-4000_alldecomp.c around line 18066). It applies `buf[5]` and
          `buf[6]`, and then reads these ten bytes TWICE, as two packed fields:

            for i in 0..11:  setter(i, buf[(i >> 1) + 7] & 0x3f)
            for i in 0..9:   v = buf[i + 7] >> 6
                             if (v != 0 and v != 1) v = -1
                             setter(i, v, 1)

          So the low six bits are read once per PAIR of groups — one byte covers
          eight channels and lands in two four-channel group slots, `>> 1` being
          the granularity — while the top two bits are read once per byte across
          all ten, with 2 and 3 folded to -1.

          On the width-8 fixture that yields low-6 = [1,1,0,0,0,0,0,0,0,0,0,0]
          and top-2 = [1,0,0,0,0,0,-1,-1,-1,-1], which is the S-0808's two input
          groups of four marked in the first field and its one input group of
          eight marked in the second.

          The wire description above — 0x41 front-packed, 0xc3 back-packed — is a
          true statement about the bytes and this is what produces it, but the
          firmware never splits them into two arrays, and what the two code
          spaces MEAN is UNRESOLVED. Nothing in the S-1608 image parses this page
          at all: it has no `[4]==0x10` gate and no `& 0x3f` anywhere near the
          protocol code, which fits the observation that most S-1608 captures
          carry no 0x000d frame and the box is placed anyway.
      enrolled_in_channels:
        value: >-
          (input_groups[0] == 0x41 ? 8 : 0) + (input_groups[1] == 0x41 ? 8 : 0) +
          (input_groups[2] == 0x41 ? 8 : 0) + (input_groups[3] == 0x41 ? 8 : 0) +
          (input_groups[4] == 0x41 ? 8 : 0)
        doc: The width the master is enrolling, 8 channels per input group. The
          five groups span exactly the 40-slot audio fabric.
  container_0403:
    doc: |
      op 0x0403 carries TWO different things, discriminated by `payload[0]` —
      block[4], the same position that discriminates op-0103's subtypes:

        0x00  a genuine Roland DT1 record            -> dt1_record
        0x02  the BOX's upstream return block        -> box_return_block

      The 0x02 form was previously documented only as "the look-alike to beat"
      and rejected by dt1_record's `contents`. Rejecting it is right for DISPATCH
      and wrong for a grammar: the corpus holds 6.05 million of them and a spec
      that cannot parse the commonest control block on the wire is incomplete.
      It is now a named subtype, so the dispatch signature still holds and the
      bytes are still accounted for.
    seq:
      - id: body
        size-eos: true
        type:
          switch-on: subtype
          cases:
            0x00: dt1_record
            0x02: box_return_block
    instances:
      subtype:
        pos: 0
        type: u1
        doc: block[4]. 0x00 a DT1 record, 0x02 the box's upstream return block.
  identity_data:
    doc: |
      TAG 0x0500 — the IDENTITY PAGE. This is where a box says what model it is
      and what firmware it runs, and it is the record a console needs to put a
      box in a menu.

      # It is an ADDRESSED page, not a fixed struct

      Every other tag on this container carries a fixed record shape. 0x0500
      does not. The tag is only the HIGH HALF of a Roland 4-byte DT1 address;
      `addr_lo` carries the low half, and the payload is whatever lives at that
      address. So one tag covers six distinct records, and a consumer that
      reads 0x0500 as one struct gets five of them wrong.

      The exchange is a poll, at ESTABLISHMENT, and both halves are here:

        RQ1 (command 0x11), console -> broadcast
            addr_lo + ONE byte, the number of bytes wanted.
        DT1 (command 0x12), box -> console
            addr_lo + that many bytes of payload.

      WORKED EXCHANGE — m200-BIDIR-coldboot-2026-07-11, frames 3466..3479, at
      +96.985 s, one burst, immediately before the head-amp flood:

        3466  console  RQ1  05 00 00 00  size 04
        3467  console  RQ1  05 00 06 00  size 08
        3468  console  RQ1  05 00 10 00  size 11   (17)
        3469  console  RQ1  05 00 10 11  size 09
        3470  console  RQ1  05 00 11 00  size 11   (17)
        3471  console  RQ1  05 00 11 11  size 09
        3475  S-0808   DT1  05 00 00 00  01 00 00 03
        3476  S-0808   DT1  05 00 06 00  00 00 00 01 00 00 00 00
        3477  S-0808   DT1  05 00 10 00  01 "S-0808" + zero fill   (fragmented)
        3478                              ... its LAST fragment
        3479  S-0808   DT1  05 00 10 11  08

      Two things follow that a consumer must not treat as errors. **A box answers
      only the addresses it implements** — the S-1608 and the S-4000S answer
      0x0000 and 0x0600 and nothing else, and nothing in the corpus has ever
      answered 0x1100 or 0x1111. And **a reply may be SHORTER than the size
      asked for**: the S-0808 is asked for 9 bytes at 0x1011 and returns 1.

      FIRMWARE CORROBORATION for the address set. S-1608.BIN carries a
      12-byte-stride DT1 address table at file 0x53154..0x53994 (176 records:
      4-byte address, u32le, u32le byte count). Its 83 page-0x0500 entries use
      third-address-byte values 0x00..0x08 ONLY — there is no 0x10 or 0x11 —
      which is exactly why the S-1608 stays silent on the two name addresses the
      console polls. The image and the wire agree without being asked to.

      # addr_lo 0x0000 — the firmware version, one DECIMAL DIGIT per byte

      RESOLVED, and resolved against Roland's own release packages rather than
      against ourselves:

        S-0808   01 00 00 03  -> 1.003   package `s0808_sys_v1003`
        S-1608   02 02 00 00  -> 2.200   package `s1608_sys_ver2200`
        S-4000S  02 05 00 00  -> 2.500   package `s4000_sys_ver2500`

      Three models, three independent matches, four digits each. The S-1608
      image corroborates itself twice more from the inside: the boot banner at
      file 0x200 reads `ECM42 BOOT Ver.2.200`, and the boot menu's version
      literal at 0x9254 is the ASCII `2.200`.

      **So the boxes in the corpus run the firmware images this project holds.**
      That was worth ruling out: had a captured box reported a version the image
      does not carry, every firmware-derived fact in this repo would have needed
      a version stated beside it. It does not.

      # addr_lo 0x1000 / 0x1100 — the model name

      `name_kind` (1 byte, 0x01 on every observation) then a FIXED 16-byte
      NUL-padded ASCII field. 17 bytes, so the record does not fit one control
      block and arrives split — see `record_fragment`, which is the only place
      this payload is ever seen.

      0x1000 and 0x1100 are two SLOTS, polled as a pair with their 0x0011
      continuations; only the 0x10 slot has ever answered. What the second slot
      is for is UNRESOLVED.

      **Only the S-0808 implements a name at all.** The S-1608 and S-4000S never
      answer 0x1000, in any capture, so a console cannot read their model as
      text — it has to take the model from the version plus the config
      announce's declared width. That is a real limit of this page, not a gap in
      the corpus.

      # addr_lo 0x0600 — eight bytes, per-model constant, UNRESOLVED

      Stable per model and identical across the two units of each model we have
      captured:

        S-0808   00 00 00 01 00 00 00 00
        S-1608   00 00 00 02 00 03 00 02
        S-4000S  00 00 00 02 00 01 00 02

      Read as four u16be the fields are (0,1,0,0), (0,2,3,2) and (0,2,1,2). The
      second field tracks the REAC port count (S-0808 one, the others two) and
      the rest is unexplained. It is NOT a version in the 0x0000 encoding: the
      S-1608's boot version is 2.200, which would be `02 02 00 00`, and that
      appears nowhere here. The box's own boot menu names four versions — Main,
      Boot, FPGA and REAC, string table at S-1608.BIN 0x9e32..0x9eaa — so a
      further version living here is PLAUSIBLE and unproven. Left as bytes on
      purpose.

      # The negative that matters

      The two S-1608s in the corpus (`0040abc48041`, `0040abc4803b`) report
      BYTE-IDENTICAL identity pages, and so do the two S-4000Ss
      (`0040abc40680`, `0040abc408bc`). So a per-box protocol dialect does NOT
      explain the divergent bank behaviour seen between two S-1608s: on this
      page they are the same box running the same firmware.
    seq:
      - id: addr_lo
        type: u2be
        enum: identity_addr
        doc: |
          The LOW two bytes of the Roland DT1 address. The full address is
          `tag << 16 | addr_lo`, so 0x0500 plus this selects the record.
      - id: payload
        size-eos: true
        doc: |
          On an RQ1 this is a single byte, the requested length — read
          `request_size`. On a DT1 it is the record's contents, and it may be
          shorter than the RQ1 that asked for it.
    instances:
      is_request:
        value: _parent.command == dt_command::rq1_request
      is_reply:
        value: _parent.command == dt_command::dt1_set
      request_size:
        value: payload[0]
        if: is_request
        doc: Bytes the console wants from this address. 4, 8, 17 or 9.
      firmware_version:
        value: >-
          payload[0] * 1000 + payload[1] * 100 + payload[2] * 10 + payload[3]
        if: is_reply and addr_lo == identity_addr::firmware_version and
          payload.size >= 4
        doc: |
          The four payload bytes are four DECIMAL DIGITS, most significant
          first, and Roland writes the result as D.DDD. 1003 is the S-0808's
          1.003; 2200 the S-1608's 2.200; 2500 the S-4000S's 2.500. Each is the
          version of the release package the image came from.
  record_fragment:
    doc: |
      op 0x0401 and op 0x0402 — link 4 with the segment field reading FIRST and
      LAST. They were carried for a long time as two separate undecoded ops, "the
      ASCII model-name frame" and "the extra cold-connect frame some models
      send". They are ONE Roland DT1 record, split across two frames, and the
      split is the ordinary link-4 segmentation.

      # The proof, which is arithmetic and needs no firmware to check

      Both frames have the link-4 shape: the wrapper `00 02 00 fe` at block[4:8],
      a length echo at block[8], and exactly that many bytes after it. Take the
      two fragment bodies in FIRST-then-LAST order and the result is a complete,
      valid Roland SysEx:

        0x0401 body (0x16 = 22 bytes)
          f0 41 0a 00 00 12  12  05 00  10 00  01  53 2d 30 38 30 38  00 00 00 00
        0x0402 body (0x08 =  8 bytes)
          00 00 00 00 00 00  1a  f7

        F0 41           SysEx start, Roland
        0a              device id
        00 00 12        model id
        12              DT1, a write
        05 00           TAG 0x0500 — the identity page
        10 00           addr_lo — the model-name record
        01              name_kind
        53 2d 30 38 30 38   ASCII "S-0808"
        00 x 10         the rest of the fixed 16-byte name field
                        (4 zeros in the FIRST fragment, 6 in the LAST)
        1a              inner checksum
        f7              SysEx end

      The payload after `addr_lo` is 17 bytes — `name_kind` plus the 16-byte
      name — which is exactly the size the console's RQ1 for this address asks
      for. That is why this record and only this record is split: 17 bytes of
      payload do not fit the 36-byte control block. See `identity_data`.

      The Roland rule is Sum(TAG..CKSUM) mod 128 == 0. The data sums to 358,
      358 mod 128 = 102, and 128 - 102 = 26 = 0x1a — the byte that arrives in
      the SECOND fragment. A checksum that closes only across both frames is not
      a coincidence; it is what proves the two are one record.

      # What that changes

      The name frame is not "a frame that happens to hold ASCII". It is a TAG
      0x0500 identity record, the same tag the single-frame 0x0403 identity
      frames carry at rec_len 0x0016 and 0x001a, and it is longer than 26 bytes
      of body, which is the only reason it is split at all.

      A consumer must therefore reassemble link 4 the same way it reassembles
      link 1, and a consumer that reads 0x0401 alone gets a SysEx with no
      terminator and no checksum — which is exactly how it has been described
      until now.

      CORROBORATED: 18 frames of each op, in 9 captures, always as a pair, and
      only from the S-0808 family. FIRMWARE: the segmentation rule is
      `FUN_0c003398` @0c003398 (S-1608); no link-4 reassembler has been located
      in either box image, so the box's own handling of a split record is
      UNRESOLVED.
    seq:
      - id: wrapper
        contents: [0x00, 0x02, 0x00, 0xfe]
      - id: len_echo
        type: u1
        doc: Bytes of record following, and always rec_len - 5.
      - id: fragment
        size: len_echo
        doc: This frame's slice of the record. Concatenate FIRST then LAST.
      - id: padding
        size-eos: true
  box_return_block:
    doc: |
      op 0x0403 subtype 0x02 — a CONSTANT block the box repeats on its upstream
      return frames. Not a record container: there is no SysEx envelope at all,
      and the `02 00 fe` sits one byte before where a DT1 wrapper's `00 02 00 fe`
      would.

      EVIDENCED (corpus): 6,053,140 frames in one M-200i/S-0808 session carry
      exactly ONE distinct 32-byte block, from the box's own MAC, on 628- and
      630-byte upstream frames, with a valid block checksum. Its INTERIOR is
      UNEXPLAINED — the observed constant is

        04 03 00 14 02 00 fe 00 00 41 00 00  then zeros, then the checksum

      so `00 41` after the marker is documented as observed, not named. Nothing in
      either firmware image has been shown to read it.
    seq:
      - id: marker
        contents: [0x02, 0x00, 0xfe]
      - id: rest
        size-eos: true
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
        00 13        rec_len -> record_len 6, data_len 3
        00 02 00 fe  wrapper
        0e           len_echo, rec_len - 5
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
        doc: SysEx payload length echo, always rec_len - 5.
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
            'reg_page::identity': identity_data
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
        value: _parent._parent.rec_len - 0x0d
        doc: TAG(2) + data + inner checksum(1).
      data_len:
        value: _parent._parent.rec_len - 0x10
        doc: |
          3 for head-amp, 4 for the join grant. On identity it is addr_lo(2)
          plus the payload: 3 on an RQ1 or a one-byte reply, 6 for the
          firmware version, 10 for the capability block.
  head_amp_data:
    doc: |
      TAG 0x0101 — the console's preamp command, and the ONLY three things a box
      owns on the head-amp page.

      # WIRE ENCODING and HARDWARE ACTUATION are two axes, not one scale

      This doc used to list three granularities in a single column — per
      channel, per four, per eight. They do not belong on one scale: two are
      about which record carries a field, one is about how many channels a
      write switches, and a consumer reading them as one list gets whichever it
      picks wrong.

      WIRE ENCODING. This record, {CH, PARAM, VALUE}, is one channel per record
      for all three params. The per-four thing lives in the OTHER head-amp
      carrier, the slot map (op-0103 subtype 0x01): FUN_0c002d42 writes its sens
      byte and three flag bits for EVERY slot, and gates only the high nibble —
      the INVENTORY CELL — on `(slot & 3) == 0`.

      HARDWARE ACTUATION. Per channel, for phantom, pad and sens alike.
      FUN_0c007fbc(bank, group) sets its cursor to `group << 3` and loops eight
      times, and each iteration passes its own within-bank index and that slot's
      own value to FUN_0c00ac1e, FUN_0c00ac96 and FUN_0c007e6a. Eight is the
      preamp BANK width and the loop's batch size — the writers take
      (bank, 0..7), two banks covering an S-1608's sixteen inputs — and nothing
      is switched eight channels at a time.

      "PHANTOM IS PER FOUR" IS THEREFORE DISPUTED. The image holds exactly one
      channel-indexed `(x & 3) == 0` test, it is FUN_0c002d42's inventory-cell
      gate, and it is not on this record's path. The claim's grade is an
      executed trace, so it stands in protocol-facts.yaml unchanged with the
      conflict and the discriminating experiment recorded beside it — send
      phantom to 0x24 and to 0x25 and read the box's re-broadcast back. Do not
      generate a per-four sweep from this doc until that runs.

      TWO GRANULARITIES, NOT THREE. The readback nibble is not a third axis:
      FUN_0c007fbc's caller was recovered on 2026-08-23 (a function Ghidra never
      disassembled — clean prologue past the previous function's rts, absent
      from the 1395-entry map, reached by a plain bsr), and it confirms the loop
      shifts by 3 and iterates exactly 8, so group g covers [g*8, g*8+8) and
      `g == ch >> 3` — the readback nibble's own index. So the list is: PER
      CHANNEL (actuation) and PER EIGHT (refresh and readback banking).

      BANK IS A SEPARATE AXIS FROM GROUP, and our docs have used the two words
      loosely. GROUP is 0..9 and equals `ch >> 3`; it selects which eight
      channels' DATA, an eight-slot window of the 80-slot active table. BANK
      selects which eight PHYSICAL PREAMPS receive it, and is not a subdivision
      of channel space. FUN_0c007fbc takes both because they are independent.

      # A record writes the ACTIVE table, and the commit overwrites it

      There is no head-amp staging table. A record writes the box's live table
      directly, at the same base the scene commit overwrites in full for all 80
      slots. EVIDENCED (executed trace).

      **So records must FOLLOW the commit, never precede it.** A record sent
      before the commit is erased by it, silently: the bytes are right, the
      checksums are right, the box acknowledges, and the value is gone. Emit the
      scene transfer, wait for the box's `01 03 00 10`, then sweep.

      # One pass, no banks

      Every real desk sweep is ONE contiguous pass over the box's full declared
      width, every channel getting all three parameters: 24 records for an
      S-0808, 48 for an S-1608, 96 for an S-4000S, at about 3.2 ms a record. No
      desk addresses a bank, splits a sweep or repeats one. EVIDENCED (corpus),
      31 of 47 captures, three desk generations agreeing on the same box.
    seq:
      - id: ch
        type: u1
        doc: |
          The WIRE channel: model_base + (box_input - 1), in the 48-slot head-amp
          space 0x00..0x2f. It addresses a BOX INPUT — not a console channel
          strip, and not an audio fabric slot (that space is 40 wide). A table
          bounded by 40 silently rejects the top half of a 16-input box based at
          0x20. The base itself is session state — see commit_report_page.
      - id: param
        type: u1
        enum: head_amp_param
        doc: |
          WHICH BIT IS PHANTOM AND WHICH IS PAD IS OUR NAME, NOT THE FIRMWARE'S.
          The firmware acts on them without naming them; the mapping comes from
          the corpus and from the rig. EVIDENCED (corpus), explicitly NOT
          EVIDENCED (image).
      - id: value
        type: u1
        doc: |
          Phantom and pad are 0x00 off / 0x01 on. SENS is 0x00..0x37, 56 steps of
          1 dB, and PAD-RELATIVE: dB = -10 - value + (pad ? 20 : 0), so pad off
          runs -10 dBu at 0x00 down to -65 dBu at 0x37 and pad on shifts the whole
          range +20 dB. The box applies the shift, not the console.

          MEASURED, at last — this doc stated the linear law flatly and a third
          party would reasonably have built a client from it, but nothing behind
          it had ever been swept. libreac meanwhile carried a firmware-derived
          curve spanning 48.75 dB in which three pairs of steps delivered
          IDENTICAL gain, so the two expressions of this protocol disagreed by
          6 dB at the top of the travel and by the very shape of the function.

          AND THE FIRMWARE HOLDS THE CURVE AS A TABLE. S-1608.BIN at 0x0c0327a0
          and S-0808.BIN at file offset 0x45ec8 (a raw byte match only — there
          is no S-0808 decompilation) carry the same 56 two-byte
          entries, read by FUN_0c007e30, which clamps the step to 0x37 — so
          0x37 is the top of the travel by construction, not by observation.
          The two bytes are a two-bit coarse analog range and a serial fine
          gain code, not decibels. The fine code steps by exactly 2 for every
          SENS step throughout, and the coarse range changes at three places
          only: between steps 0x07/0x08, 0x17/0x18 and 0x27/0x28. So the law is
          uniform by construction everywhere except at three known indices, and
          the ranges begin at 0, 8, 24 and 40 — each break placed exactly where
          the fine field runs out, which is a design that intends them to abut.
          The full table is printed in protocol-facts.yaml's headamp_sens
          group. It settles the SHAPE; the decibel per fine code is an analog
          value and is not in any image.

          Settled 2026-08-23 on an S-0808 with output 1 cabled to input 1, so the
          source is an electrical loopback of a known digital level rather than a
          microphone: all 56 steps at three overlapping generator levels, span
          54.60 dB against the 55.00 this law implies, slope 0.988 dB/step, and
          each of the three predicted duplicate pairs stepping ~1 dB under A/B/A
          alternation against drift controls ten times smaller. The curve is
          declared once in protocol-facts.yaml's `headamp_sens` group and this
          doc is cross-checked against it.

          One caveat a consumer should carry: a loopback measures the SPAN
          exactly but not the absolute dBu of either endpoint, which needs the
          box's own converter reference. The -10 at step 0 is inherited, not
          measured; the -65 is that plus the measured span.
  join_grant_data:
    doc: TAG 0x0100 — the join grant. Observed as 06 00 XX 00 with XX odd-valued.
      A master only ever emits XX = 0x01. Box-side echoes of this record also
      carry 0x03, 0x05, 0x09, 0x0b and 0x0d — all odd, but wider than the
      0x01..0x09 range once assumed, and 0x07 never occurs. What advances XX
      between these box-side values is UNRESOLVED — it is not modelled here.
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
  reac_link:
    1: control
    2: aux_s4000s
    4: record
    255: announce_link
  seg_state:
    0: middle
    1: first
    2: last
    3: single
  link1_opcode:
    0x00: bulk_transfer
    0x01: chanmap
    0x10: group_map
    0x80: declaration_80
    0x81: heartbeat_reply
    0x82: declaration_82
    0x84: declaration_84
  control_op:
    0x0100: scene_chunk
    0x0101: scene_header
    0x0102: scene_final
    0x0103: page_0103
    0x0401: dt1_first_fragment
    0x0402: dt1_last_fragment
    0x0403: dt1_container
    0xffff: announce
  page_kind:
    0: unknown_page
    1: chanmap
    2: commit_report
    3: enroll_group_map
    4: box_heartbeat
  ctrl_kind:
    0: none
    1: filler
    2: scene_transfer
    3: master_hb
    4: master_announce
    5: grant
    6: head_amp
    7: box_hb
    8: unknown_ctrl
    9: config_announce
    10: group_map
    11: record_fragment
    12: link2
  dt_command:
    0x11: rq1_request
    0x12: dt1_set
  # identity_addr — the low half of the four-byte DT1 address on page 0x0500.
  # Named from what each record was MEASURED to carry. `model_name_slot_b` and
  # the two `_ext` rows have never been answered by any box in the corpus and
  # are named from the console's poll alone. See type `identity_data`.
  identity_addr:
    0x0000: firmware_version
    0x0600: capability_block
    0x1000: model_name
    0x1011: model_name_ext
    0x1100: model_name_slot_b
    0x1111: model_name_slot_b_ext
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
