meta:
  id: reac_control
  title: Roland REAC 0x8819 control-plane record (head-amp / grant / identity)
  license: GPL-3.0-or-later
  ks-version: 0.9
  endian: be
  bit-endian: be
doc: |
  A Roland REAC control record as carried on the 0x8819 Ethernet wire, reverse-engineered
  from real M-200 / M-300 / M-5000 captures (FreeREAC). It is the payload the console
  broadcasts to command a stagebox's head-amp (48V phantom / -20 dB PAD / SENS), plus the
  join grant and the model-identity exchange.

  Structure: op-0403 is a length-prefixed RECORD CONTAINER that wraps a genuine Roland
  DT1 (Data Set 1) MIDI SysEx message (F0 41 .. 12 .. F7). Two nested checksums:
    - INNER (Roland DT1): the record `tag .. inner_checksum` (record_len bytes) sums to
      0x80 (mod 256), i.e. Roland's `(128 - sum(address+data) mod 128) mod 128` rule.
    - OUTER (REAC block): the 32-byte control block [op .. op+32] sums to 0 (mod 256).
  The outer block spans past this record into the frame padding, so it is validated in
  code (tools/corpus_protocol_conformance.py), not as a field here.

  DISPATCH RULE (do NOT rely on the `04 03` opcode alone): the box-upstream audio braid
  and the box self-describe frames also carry `cd ea 04 03`, but with wrapper `02 00 fe 00`
  and no SysEx envelope. A genuine control record is `cd ea 04 03` AND `00 02 00 fe` AND
  `f0 41 ...`. This type only parses genuine control records (the fixed `magic`/`wrapper`/
  `sysex_start`/`roland_id` contents fields reject the impostors).

  Anchor: parse starting at the `cd ea` marker. The 2-byte free-running frame counter sits
  immediately BEFORE it (frame[14:16], little-endian) and is not part of this record.

  Validated: 7130/7130 real control records across all consoles/boxes conform (100%).
  Worked example (S-1608 input 1, phantom ON):
    cd ea 04 03 00 13 00 02 00 fe 0e f0 41 0a 00 00 12 12 01 01 20 00 01 5d f7
    -> tag=head_amp ch=0x20 param=phantom value=1 ; inner cksum 0x5d (01+01+20+00+01+5d=0x80).
seq:
  - id: magic
    contents: [0xcd, 0xea]
    doc: Control-frame marker. Half of the dispatch signature (see DISPATCH RULE).
  - id: op
    type: u2
    doc: 0x0403 = record container. (Other ops — 0x0103 chanmap, 0xffff cfea — not modelled here.)
  - id: op_len
    type: u2
    doc: Big-endian container length. record_len = op_len - 0x0d.
  - id: wrapper
    contents: [0x00, 0x02, 0x00, 0xfe]
    doc: Fixed REAC console wrapper, OUTSIDE the SysEx. Rest of the dispatch signature.
  - id: len_echo
    type: u1
    doc: SysEx-payload length echo. Always == op_len - 5.
  - id: sysex_start
    contents: [0xf0]
    doc: MIDI System Exclusive start (F0).
  - id: roland_id
    contents: [0x41]
    doc: Roland Corporation registered MIDI manufacturer ID.
  - id: device_id
    type: u1
    doc: Roland SysEx device (unit) ID. 0x0a observed across all consoles.
  - id: model_id
    size: 3
    doc: Roland extended (3-byte) model ID. 00 00 12 observed across M-200/M-300/M-5000.
  - id: command
    type: u1
    enum: dt_command
    doc: Roland command byte. 0x12 DT1 (Data Set 1, a write) on all edits; 0x11 RQ1 (Data
      Request) only on master-sourced identity polls.
  - id: tag
    type: u2
    enum: reg_page
    doc: High 2 bytes of the Roland DT1 address — selects the register page / record type.
  - id: payload
    size: data_len
    type:
      switch-on: tag
      cases:
        'reg_page::head_amp': head_amp
        'reg_page::join_grant': join_grant
    doc: The DT1 data. For head-amp it is CH/PARAM/VALUE; other pages left as raw bytes.
  - id: inner_checksum
    type: u1
    doc: |
      Roland DT1 checksum. Invariant: sum(tag_hi + tag_lo + payload_bytes + inner_checksum)
      & 0xff == 0x80. Enforced in tools/corpus_protocol_conformance.py.
  - id: sysex_end
    contents: [0xf7]
    doc: MIDI SysEx end (EOX / F7). Sits at record offset record_len (op_len - 0x0d).
instances:
  record_len:
    value: 'op_len - 0x0d'
    doc: Bytes of the DT1 record = tag(2) + data + inner_checksum(1).
  data_len:
    value: 'record_len - 3'
    doc: Bytes of DT1 data (payload). head-amp = 3 (CH PARAM VALUE); grant = 4; identity = 6/10.
types:
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
    doc: DT1 data for the join grant (tag 0x0100). Observed 06 00 01 00.
    seq:
      - id: body
        size-eos: true
enums:
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
