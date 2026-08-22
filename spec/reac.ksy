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
    +19.5 s              master  the head-amp sweep: 48 op 04 03 TAG 0101
                                 records in 0.145 s — 16 wire channels 0x20..0x2f
                                 x phantom, pad, sens
    after                master  back to 1 Hz cfea + page 0x0019; the scene
                                 transfer never runs again for this session

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

  # Anti-goals

  This grammar does NOT model the establishment FSM as STRUCTURE — a sequence of
  frames is not a layout, and Kaitai has no way to say it. The lifecycle above is
  documented rather than parsed, and it names the frame each transition is
  carried by so the sequence is at least discoverable from the spec. Also not
  modelled: the per-model fabric slot BASE (see
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
          (op_raw >> 8) == 0x01 ? ctrl_kind::scene_transfer :
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
              0x000d — fall through to `scene_transfer`, because the consumer only
              tests
              the high op byte. Read `page_kind` for the real sub-page.
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
      records and the cf ea master announce: op(2) op_len(2) payload(28).
    seq:
      - id: op
        type: u2
        enum: control_op
      - id: op_len
        type: u2
        doc: |
          Big-endian, and op-specific in meaning — a length for the DT1 container
          (record_len = op_len - 0x0d), the CHUNK LENGTH for the three scene ops
          (0x0018 header / 0x001a chunk / 0x000e final), a SUB-PAGE SELECTOR for
          op 0x0103, and a fixed constant for the rest. It is not a generic frame
          length.

          EVIDENCED (image): the master writes it with a big-endian 16-bit store
          from the same variable it passes to the memcpy that fills the payload,
          and the box reads it back as the memcpy length. Our earlier reading of
          0x001a as "a fixed constant of the probe" was a coincidence of the
          scene's chunk size.
      - id: payload
        size: 28
        type:
          switch-on: op
          cases:
            'control_op::scene_chunk': scene_chunk_payload
            'control_op::scene_header': scene_header_payload
            'control_op::scene_final': scene_final_payload
            'control_op::page_0103': page_0103
            'control_op::dt1_container': dt1_record
            'control_op::announce': cfea_payload
        doc: Unmodelled ops (the ASCII name frame 0x0401, the extra cold-connect
          0x0402) fall through as raw bytes on purpose — their interiors are not
          decoded to a level worth pinning.
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
  scene_chunk_payload:
    doc: |
      op 0x0100 — a CONTINUATION CHUNK of the master's scene transfer, 26 bytes
      of `scene_body` (see that type). op_len carries the chunk length, 0x001a.

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
      op_len is 0x000e = 14 = 8880 mod 26, so it is a length like any other
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
        doc: block[5:5+op_len] — the tail of the body, 14 bytes, then padding to
          the block end. Sized to end-of-stream rather than to op_len so a short
          or padded final frame still parses; read op_len for the true count.
  scene_body:
    doc: |
      THE SCENE — the 8904-byte body the three ops above carry, reassembled as
      `scene_header.body_head` + each `scene_chunk.chunk` in emission order +
      `scene_final.chunk`. It is NOT a frame, so nothing in `seq` reaches it;
      parse it from a recovered body (reac-pw tools/recover-scene.py).

      It is a property of the DESK, not of the box: an M-300 sends the same bytes
      to an S-1608 and to an S-0808, and the only bytes that differ between an
      M-200i's and an M-300's are the four low bytes of `master_id`.

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
      copies 800 bytes of `slots` and 6 bytes of `master_id` into its live
      tables, pushes twelve `inventory_cell`s, and emits the `01 03 00 10`
      committed report. That commit is the only unconditional promoter of
      head-amp state in the box.
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
          image, and it is one of only two non-padding bytes that differ between
          a V-Mixer desk (0x0000) and an M-5000 (0x0001).
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
          declares back in `config_announce_page`: the commit walks twelve cells
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
          only by the next named field, and it is all zero on every capture, so
          the SHAPE is INFERRED.
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
        doc: +0. Not committed; read by the twelve-cell declaration loop at every
          fourth record. INFERRED that the enum is the same vocabulary as
          `config_announce_page.cells` — the values coincide (0x02 analog input,
          0x03 absent), the cell count and the four-channel grouping coincide, and
          nothing in either image names it.
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
      join state, climbing 0x01 -> 0x09 over the establishment. The climb was
      read as the box "locking to the probe rotation"; there is no probe and no
      rotation, so what advances it is UNRESOLVED — it is not modelled here.
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
    0x0100: scene_chunk
    0x0101: scene_header
    0x0102: scene_final
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
    2: scene_transfer
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
