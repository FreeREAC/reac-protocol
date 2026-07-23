meta:
  id: reac_control
  title: Roland REAC 0x8819 control-plane record (all master/box control ops)
  license: GPL-3.0-or-later
  ks-version: 0.9
  endian: be
  bit-endian: be
doc: |
  A Roland REAC control record as carried on the 0x8819 Ethernet wire, reverse-engineered
  from real M-200 / M-300 / M-5000 captures (FreeREAC). Two marker families share the layout
  `marker(2) op(2) op_len(2) body`:
    - cd ea  — the control records (probe / SUB01 / SUB02 / op-0103 pages / op-0403 head-amp)
    - cf ea  — the cfea master-announce (op 0xffff)

  op-0403 wraps a genuine Roland DT1 (Data Set 1) MIDI SysEx (F0 41 .. 12 .. F7) with two nested
  checksums (INNER Roland DT1 -> sum==0x80 mod 256; OUTER 32-byte REAC block -> sum==0 mod 256,
  validated in tools/corpus_protocol_conformance.py). The other ops are fixed/known blocks whose
  key fields are modelled below with the remainder left as raw `body`.

  DISPATCH RULE for op-0403 (do NOT rely on `04 03` alone): the box-upstream audio braid also
  carries `cd ea 04 03` but with wrapper `02 00 fe 00` and no SysEx. A genuine head-amp record is
  `cd ea 04 03` AND `00 02 00 fe` AND `f0 41 ...`; the `wrapper`/`sysex_start`/`roland_id` fixed
  contents in `dt1_record` reject the impostors.

  Anchor: parse starting at the marker. The 2-byte free-running frame counter sits immediately
  BEFORE it (frame[14:16], little-endian) and is not part of this record.

  Validated: 7130/7130 real op-0403 control records conform (100%). Worked example
  (S-1608 input 1, phantom ON):
    cd ea 04 03 00 13 00 02 00 fe 0e f0 41 0a 00 00 12 12 01 01 20 00 01 5d f7
    -> op=dt1_container tag=head_amp ch=0x20 param=phantom value=1 (inner cksum 0x5d).
seq:
  - id: marker
    type: u2
    doc: 0xcdea = control record, 0xcfea = cfea master-announce.
  - id: op
    type: u2
    enum: control_op
  - id: op_len
    type: u2
    doc: Big-endian container/length field; op-specific meaning (op-0403 record_len = op_len - 0x0d).
  - id: body
    size-eos: true
    type:
      switch-on: op
      cases:
        'control_op::dt1_container': dt1_record
        'control_op::probe': probe
        'control_op::sub01': sub01
        'control_op::sub02': sub02
        'control_op::page_0103': page_0103
        'control_op::cfea': cfea
    doc: Body dispatched on op. Unknown ops fall through as raw bytes.
types:
  dt1_record:
    doc: op-0403 record container wrapping a Roland DT1 SysEx (head-amp / join-grant / identity).
    seq:
      - id: wrapper
        contents: [0x00, 0x02, 0x00, 0xfe]
        doc: Fixed REAC console wrapper OUTSIDE the SysEx. Part of the op-0403 dispatch signature.
      - id: len_echo
        type: u1
        doc: SysEx-payload length echo. Always == op_len - 5.
      - id: sysex_start
        contents: [0xf0]
      - id: roland_id
        contents: [0x41]
        doc: Roland Corporation registered MIDI manufacturer ID.
      - id: device_id
        type: u1
        doc: Roland SysEx unit ID. 0x0a observed across all consoles.
      - id: model_id
        size: 3
        doc: Roland 3-byte model ID. 00 00 12 across M-200/M-300/M-5000.
      - id: command
        type: u1
        enum: dt_command
        doc: 0x12 DT1 (write) on edits; 0x11 RQ1 (request) only on identity polls.
      - id: tag
        type: u2
        enum: reg_page
        doc: High 2 bytes of the DT1 address — selects the register page / record type.
      - id: payload
        size: data_len
        type:
          switch-on: tag
          cases:
            'reg_page::head_amp': head_amp
            'reg_page::join_grant': join_grant
        doc: DT1 data. head-amp = CH/PARAM/VALUE; other pages raw.
      - id: inner_checksum
        type: u1
        doc: 'Roland DT1 checksum: sum(tag_hi+tag_lo+payload+inner_checksum) & 0xff == 0x80.'
      - id: sysex_end
        contents: [0xf7]
    instances:
      record_len:
        value: '_parent.op_len - 0x0d'
        doc: DT1 record bytes = tag(2) + data + inner_checksum(1).
      data_len:
        value: 'record_len - 3'
        doc: DT1 data bytes. head-amp=3, join-grant=4, identity=6/10.
  probe:
    doc: |
      Master hunt/probe stream (op-0100). A rotating 27-byte payload: a sliding window over the
      period-10 sequence {0,0,0,1,0,0,0,0,0,sub}, sub=0x02 while PROBING / 0x03 once ESTABLISHED,
      plus 4 inventory-special variants at burst indices 30..33. The BOX advances its JOIN state
      (op-0403 join_grant `06 00 XX 00`, XX 0x01 -> 0x09) by tracking this rotation, so the master
      must emit the FULL set: a real M-200 emits 15 distinct probe structures; reac-pw's
      M-300-derived model (phase-step 6 -> only 5 even phases) emits 9, leaving the S-1608 stuck at
      JOIN 0x01 and un-committed. See reac-pw src/reac_master.c gen_probe / probe_prepare.
    seq:
      - id: payload
        size-eos: true
        doc: Rotating hunt window + trailing block checksum (last byte).
  sub01:
    doc: |
      Establishment handshake step 1 (op-0101). Fixed block (reac-pw SUB01_BLK). With sub02
      (~0.68 s later) it drives the box scene-FSM toward state-4. reac-pw sends this byte-identical
      to the M-200, at the M-200 cadence.
    seq:
      - id: reserved0
        type: u1
      - id: model_const
        type: u2
        doc: |
          Model/protocol identity constant. 0x22c8 for the S-1608 family; the box's config-accept
          gate (firmware FUN_0c003aae comparing DAT_0c003b86) rejects a mismatch. Gates
          ESTABLISHMENT, not head-amp latching.
      - id: ident_ascii
        size: 4
        doc: ASCII "1234" identity marker.
      - id: body
        size-eos: true
        doc: Remaining fixed SUB01 payload + block checksum.
  sub02:
    doc: Establishment handshake step 2 (op-0102), follows sub01. Fixed block (reac-pw SUB02_BLK).
    seq:
      - id: body
        size-eos: true
  page_0103:
    doc: |
      op-0103 multiplexes on op_len: 0x0019 = chanmap (40-slot fabric -> box mapping, rotating
      window per gen_chanmap), 0x0010 = box config-announce (box declares its input width — the
      recognizer reads this into cfea's box_in_width), 0x0001 = box heartbeat/ack, 0x000d =
      reac-pw enrollment record (NOT emitted by a real M-200; an extra reac-pw sends).
    seq:
      - id: body
        size-eos: true
    instances:
      page_len:
        value: '_parent.op_len'
        doc: 0x19 chanmap / 0x10 config-announce / 0x01 heartbeat / 0x0d enroll.
  cfea:
    doc: |
      Master announce (op 0xffff, marker cf ea). Advertises the console + the connected box's
      input width / count + the master MAC. Corrected 2026-07-11/13 (gen_cfea): box_in_width tracks
      the linked box INPUT width, not output; it was previously left static at the 0x08 idle default.
    seq:
      - id: header
        size: 5
        doc: Fixed 01 03 0d 01 04.
      - id: our_mac
        size: 6
        doc: Master source MAC. reac-pw = 00:40:ab:c9:cc:04; the real M-200 = ...:cc:03 (NEVER let
          reac-pw use cc:03 — it impersonates the console).
      - id: total_slots
        type: u1
        doc: 0x28 = 40-slot fabric total.
      - id: box_in_width
        type: u1
        doc: Connected box INPUT width — 0x08 idle, 0x10 once a 16-in S-1608 links, 0x08 for an
          8-in S-0808. (gen_cfea out[18], fed from the box's op-0103 config-announce.)
      - id: console_field
        type: u1
      - id: box_count
        type: u2
        doc: 0x0000 idle -> 0x0001 once a box links. (gen_cfea out[20:21].)
      - id: body
        size-eos: true
  head_amp:
    doc: DT1 data for the head-amp register page (tag 0x0101). address low = CH, PARAM.
    seq:
      - id: ch
        type: u1
        doc: |
          Box PHYSICAL input = model_base + (input - 1). S-0808 base 0x00 (0x00..0x07),
          S-1608 base 0x20 (0x20..0x2f), S-4000 base 0x00 (0x00..0x1f). Addresses the BOX
          input, not the console strip.
      - id: param
        type: u1
        enum: head_amp_param
      - id: value
        type: u1
        doc: |
          phantom/pad: 0x00 off, 0x01 on. sens: 0x00..0x37 (56 steps, 1 dB/step, PAD-relative:
          pad-off 0x00=-10 dBu .. 0x37=-65 dBu; pad-on +20 dB shift, applied by the box).
  join_grant:
    doc: |
      DT1 data for the join grant (tag 0x0100). Observed 06 00 XX 00 where XX is the box JOIN
      state, climbing 0x01 -> 0x09 as the box locks to the master's probe rotation.
    seq:
      - id: body
        size-eos: true
enums:
  control_op:
    0x0100: probe
    0x0101: sub01
    0x0102: sub02
    0x0103: page_0103
    0x0403: dt1_container
    0xffff: cfea
  dt_command:
    0x12: dt1_set
    0x11: rq1_request
  reg_page:
    0x0101: head_amp
    0x0100: join_grant
    0x0500: identity
    0x0000: page_0000
    0x0302: box_ready
  head_amp_param:
    0x00: phantom_48v
    0x01: pad_minus20db
    0x02: sens
