"""Cross-validation harness: reac.ksy against the C oracle's own truth tables.

Three parties, one arrangement (see README.md):

  libreac   the executable C oracle — the layout as running code
  reac.ksy  the formal spec
  this file the REFEREE — it parses the checked-in golden fixtures with the
            parser ksc generates from the spec, and asserts field-for-field
            agreement with the oracle. Spec/code drift goes red here.

Two kinds of assertion are made, and the difference matters:

  * against the oracle's OWN pinned numbers — `fixtures/upstream.json` carries
    the PCM truth tables that libreac's tests/test_upstream.c asserts, and
    `fixtures/control.json` carries the head-amp cell table that reac-pw's grant
    tests assert. Agreeing with these is agreeing with the C code, because these
    are the numbers the C code is held to.

  * against an INDEPENDENT transcription of the oracle's decision rules — the
    `oracle_*` functions below are the cited C entry points rewritten in Python
    from their contracts, not from the .ksy. Where the spec and the transcription
    disagree, one of them is wrong.

Offline and deterministic: no network, no capture files, no rig. Everything it
reads is committed next to it.

    make -C spec check          # regenerate the parser, then run this
"""
import collections
import json
import pathlib

import pytest
from kaitaistruct import BytesIO, KaitaiStream

try:
    import reac as R
except ImportError:  # pragma: no cover - the generated parser is not committed
    raise SystemExit(
        "spec/reac.py not found. It is generated from reac.ksy, not committed:\n"
        "    make -C spec parser\n"
        "or directly:\n"
        "    kaitai-struct-compiler -t python --outdir spec spec/reac.ksy\n"
    )

HERE = pathlib.Path(__file__).resolve().parent
UPSTREAM = json.loads((HERE / "fixtures" / "upstream.json").read_text())
CONTROL = json.loads((HERE / "fixtures" / "control.json").read_text())

REAC_UPSTREAM_OVERHEAD = 52      # 50 B header + 2 B end marker
REAC_UPSTREAM_BYTES_PER_CH = 36  # 12 samples x 3 B
REAC_SAMPLES_PER_PKT = 12
REAC_MAX_CHANNELS = 40


# --------------------------------------------------------------------------
# The oracle's decision rules, transcribed from their C contracts
# --------------------------------------------------------------------------

def oracle_clean_len(n):
    """libreac reac_frame_clean_len(): INGEST's strip of the capture's +2.

    A REAC frame is 52 + n*36 for some channel width n, so a length of
    52 + n*36 + 2 is a frame the capture left two bytes of its own Ethernet FCS
    on, and comes back reduced by 2. Every other length, including every clean
    one, is returned unchanged.

    This is a rule about a CAPTURE PATH, not about the protocol: it lives in
    libreac's ingest (reac_rx, reac_tap) and in this harness's capture_reader,
    and deliberately nowhere in reac.ksy.
    """
    if n > REAC_UPSTREAM_OVERHEAD and (n - REAC_UPSTREAM_OVERHEAD) % REAC_UPSTREAM_BYTES_PER_CH == 2:
        return n - 2
    return n


def oracle_upstream_channels(n):
    """libreac reac_upstream_channels(): width from the frame size, or -1.

    Takes a CLEAN length: a residue-carrying one is not 52 + n*36 and is
    refused, like any other off-law length. The strip happened in the reader.
    Rejects an odd width (the braid packs channel pairs) and rejects the 40-ch
    solution, which is the downstream broadcast and never a box return.
    """
    rest = n - REAC_UPSTREAM_OVERHEAD
    if rest <= 0 or rest % REAC_UPSTREAM_BYTES_PER_CH:
        return -1
    nch = rest // REAC_UPSTREAM_BYTES_PER_CH
    if nch % 2 or nch < 2 or nch >= REAC_MAX_CHANNELS:
        return -1
    return nch


# enum reac_ctrl_kind, in its C declaration order
KIND_NONE, KIND_FILLER, KIND_PROBE, KIND_MASTER_HB, KIND_MASTER_ANNOUNCE, \
    KIND_GRANT, KIND_HEADAMP, KIND_BOX_HB, KIND_UNKNOWN, KIND_CONFIG_ANNOUNCE, \
    KIND_GROUP_MAP, KIND_RECORD_FRAGMENT, KIND_LINK2 = range(13)
# KIND_PROBE keeps its number and its name because the enum value 2 is
# `scene_transfer` and libreac still calls it the probe bucket. It is the bucket
# the new classification SPLITS, so it has to stay addressable by both names.


def legacy_ctrl_kind(block34):
    """reac_ctrl_parse() AS IT WAS BEFORE 2026-08-23, over a frame[16:50] window.

    Kept only as the left-hand side of the partition proof below. Nothing else
    should call it: it keys on two lengths where the protocol keys on a subtype.

    Transcribed decision for decision, quirks included: op 0x0403 is HEADAMP
    only when the DT1 command byte is 0x12 and the tag is 0x0101, everything
    else under 0x0403 is GRANT; and any op whose high byte is 0x01 that is
    neither chanmap (op_len 0x0019) nor box heartbeat (0x0001) falls through to
    PROBE, which sweeps up config-announce and the enroll group map.
    """
    b = block34
    t0, t1 = b[0], b[1]
    op = (b[2] << 8) | b[3]
    op_len = (b[4] << 8) | b[5]
    if (t0, t1) == (0x00, 0x00):
        return KIND_FILLER
    if (t0, t1) == (0xcf, 0xea):
        return KIND_MASTER_ANNOUNCE
    if (t0, t1) != (0xcd, 0xea):
        return KIND_UNKNOWN
    if op == 0x0403:
        # frame[32..35] = model-id low, command, tag
        if b[16] == 0x12 and b[17] == 0x12 and b[18] == 0x01 and b[19] == 0x01:
            return KIND_HEADAMP
        return KIND_GRANT
    if op == 0x0103 and op_len == 0x0019:
        return KIND_MASTER_HB
    if op == 0x0103 and op_len == 0x0001:
        return KIND_BOX_HB
    if op >> 8 == 0x01:
        return KIND_PROBE
    return KIND_UNKNOWN


def oracle_ctrl_kind(block34):
    """reac_ctrl_parse() as libreac now implements it: link, then segment,
    then subtype -- the order the record is built in.

    Transcribed decision for decision so the cross-check compares like with
    like. The one deliberate coarseness that survives is on link 4: a
    single-fragment record whose tag is not a DT1-command 0x0101 is GRANT
    rather than a kind per tag."""
    b = block34
    t0, t1 = b[0], b[1]
    if (t0, t1) == (0x00, 0x00):
        return KIND_FILLER
    if (t0, t1) == (0xcf, 0xea):
        return KIND_MASTER_ANNOUNCE
    if (t0, t1) != (0xcd, 0xea):
        return KIND_UNKNOWN
    link, seg, subtype = b[2], b[3], b[6]
    if link == 0x02:
        return KIND_LINK2
    if link == 0x04:
        if (seg & 3) != 3:
            return KIND_RECORD_FRAGMENT
        if b[16] == 0x12 and b[17] == 0x12 and b[18] == 0x01 and b[19] == 0x01:
            return KIND_HEADAMP
        return KIND_GRANT
    if link != 0x01:
        return KIND_UNKNOWN
    if subtype == 0x00:
        return KIND_PROBE            # enum 2, scene_transfer
    if subtype == 0x01:
        return KIND_MASTER_HB
    if subtype == 0x81:
        return KIND_BOX_HB
    if subtype == 0x10:
        return KIND_GROUP_MAP
    if subtype in (0x80, 0x82, 0x83, 0x84):
        return KIND_CONFIG_ANNOUNCE
    return KIND_UNKNOWN


def oracle_block_cksum_ok(block32):
    """reac_ctrl_checksum_verify(): Sum(frame[18..49]) mod 256 == 0."""
    return sum(block32) % 256 == 0


def oracle_record_cksum_ok(record):
    """reac_ctrl_record_cksum_verify(): Sum(TAG .. CKSUM) mod 256 == 0x80."""
    return sum(record) % 256 == 0x80


def oracle_braid_pos(s, ch, n_ch):
    """reac_braid_pos(): byte positions (lo, mid, hi) in the audio region."""
    g = (s * n_ch + (ch & ~1)) * 3
    if ch % 2 == 0:
        return g + 3, g + 0, g + 1
    return g + 4, g + 5, g + 2


def s24le(lo, mid, hi):
    v = lo | (mid << 8) | (hi << 16)
    return v - 0x1000000 if v & 0x800000 else v


# --------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------

def capture_reader(buf):
    """What a CAPTURE READER hands a parser: the frame, without the tap's +2.

    The residue is the capture path's, never the protocol's, so stripping it
    happens HERE — the same place libreac does it, in ingest
    (reac_frame_clean_len(), reac_rx/reac_tap), and the same place
    corpus-check.py does it, at the pcap record. The grammar below knows
    nothing about it and refuses a buffer that still carries it.
    """
    return buf[:oracle_clean_len(len(buf))]


def parse_frame(hexstr):
    return R.Reac(KaitaiStream(BytesIO(capture_reader(bytes.fromhex(hexstr)))))


def parse_raw(buf):
    """Straight to the grammar, no reader in front of it."""
    return R.Reac(KaitaiStream(BytesIO(buf)))


def parse_block(hexstr):
    """A bare captured frame[16:50] window — the form the C goldens store."""
    return R.Reac.TypedBlock(KaitaiStream(BytesIO(bytes.fromhex(hexstr))))


UP_FRAMES = [(f["name"], f) for f in UPSTREAM["frames"]]
BLOCKS = [(b["name"], b) for b in CONTROL["blocks"]]
GRANT_FRAMES = CONTROL["grant_sweep"]["frames"]
GRANT_CELLS = CONTROL["grant_sweep"]["head_amp_cells"]


# --------------------------------------------------------------------------
# frame geometry: 52 + n*36 exactly, derived width, and the refusal of anything
# past the end marker
# --------------------------------------------------------------------------

@pytest.mark.parametrize("name,fx", UP_FRAMES)
def test_frame_geometry_matches_oracle(name, fx):
    p = parse_frame(fx["hex"])
    assert p.raw_len == oracle_clean_len(fx["raw_len"])
    assert p.raw_len == REAC_UPSTREAM_OVERHEAD + fx["channels"] * REAC_UPSTREAM_BYTES_PER_CH
    assert p.num_channels == fx["channels"] == oracle_upstream_channels(p.raw_len)
    assert p.len_audio == p.num_channels * REAC_UPSTREAM_BYTES_PER_CH
    assert not p.is_downstream_width


@pytest.mark.parametrize("name,fx", UP_FRAMES)
def test_a_buffer_with_the_capture_residue_is_refused(name, fx):
    """A residue-carrying buffer handed STRAIGHT to the grammar must go red.

    The +2 is a capture artifact, and the grammar models a REAC frame — so a
    reader that forgets to strip gets an error, never a silently-accepted frame
    two bytes longer than the protocol's own law. The goldens that carry the
    residue (342 / 630 / 1206 B) are the positive side; the clean ones have
    nothing to refuse and are skipped by name.
    """
    raw = bytes.fromhex(fx["hex"])
    if len(raw) == oracle_clean_len(len(raw)):
        pytest.skip("golden carries no residue")
    with pytest.raises(Exception):
        parse_raw(raw)
    # and a clean frame with ANY two extra bytes is refused the same way — the
    # refusal is about the geometry, not about those bytes being an FCS
    with pytest.raises(Exception):
        parse_raw(capture_reader(raw) + b"\x00\x00")


@pytest.mark.parametrize("name,fx", UP_FRAMES)
def test_the_grammar_carries_no_capture_vocabulary(name, fx):
    """No residue field and no residue INSTANCE — the ratchet on the ruling.

    `has_fcs_residue` and `clean_len` were computed here until 2026-09-21; they
    are ingest's vocabulary and they are gone. A field for the bytes was never
    declared, so nothing generated from this grammar can emit them.
    """
    p = parse_frame(fx["hex"])
    assert p._io.pos() == p.raw_len == p._io.size()
    for gone in ("fcs_residue", "ohrca_trailer", "has_fcs_residue", "clean_len"):
        assert not hasattr(p, gone)


@pytest.mark.parametrize("name,fx", UP_FRAMES)
def test_the_reader_strip_changes_no_field(name, fx):
    """The frame inside a residue-carrying capture parses to the same bytes.

    Stripping is a no-op on every field, which is why it can live in the reader:
    the 342/630/1206 B goldens go through capture_reader, and slicing the last
    two bytes by hand gives the same parse, field for field.
    """
    raw = bytes.fromhex(fx["hex"])
    if len(raw) == oracle_clean_len(len(raw)):
        pytest.skip("golden has no residue to strip")
    p = parse_frame(fx["hex"])
    stripped = parse_raw(raw[:-2])
    assert stripped.raw_len == p.raw_len
    assert stripped.num_channels == p.num_channels
    assert stripped.counter == p.counter
    assert stripped.len_audio == p.len_audio
    assert bytes(stripped.end_marker) == bytes(p.end_marker) == b"\xc2\xea"
    assert [[bytes(g) for g in ts.pair_groups] for ts in stripped.audio.time_samples] \
        == [[bytes(g) for g in ts.pair_groups] for ts in p.audio.time_samples]


def test_the_readers_strip_rule_over_the_whole_frame_family():
    """Ingest's rule, both directions — libreac reac_frame_clean_len().

    Transcribed here because this harness plays the reader; the grammar itself
    has no opinion about it beyond refusing what the reader failed to strip.
    """
    for width in (8, 16, 32, 40):
        clean = REAC_UPSTREAM_OVERHEAD + width * REAC_UPSTREAM_BYTES_PER_CH
        assert oracle_clean_len(clean) == clean
        assert oracle_clean_len(clean + 2) == clean
    assert (oracle_clean_len(1492), oracle_clean_len(1494)) == (1492, 1492)
    assert (oracle_clean_len(1204), oracle_clean_len(1206)) == (1204, 1204)
    assert (oracle_clean_len(628), oracle_clean_len(630)) == (628, 628)
    assert (oracle_clean_len(340), oracle_clean_len(342)) == (340, 340)
    # the 40-ch solution is the downstream broadcast, never a box return
    assert oracle_upstream_channels(1492) == -1
    # and a length the reader did not strip is off the law, so the PARSER side
    # refuses it rather than quietly stripping it a second time
    for residue in (342, 630, 1206, 1494):
        assert oracle_upstream_channels(residue) == -1


# --------------------------------------------------------------------------
# the audio region: structure, and the braid the grammar deliberately omits
# --------------------------------------------------------------------------

@pytest.mark.parametrize("name,fx", UP_FRAMES)
def test_audio_region_structure(name, fx):
    p = parse_frame(fx["hex"])
    assert len(p.audio.time_samples) == REAC_SAMPLES_PER_PKT
    for ts in p.audio.time_samples:
        assert len(ts.pair_groups) == fx["channels"] // 2
        assert all(len(g) == 6 for g in ts.pair_groups)


@pytest.mark.parametrize("name,fx", UP_FRAMES)
def test_braid_decode_matches_the_oracle_pcm_tables(name, fx):
    """The spec's structure plus the documented braid must reproduce, sample for
    sample, the planar s24 tables libreac's own C tests assert."""
    p = parse_frame(fx["hex"])
    nch = fx["channels"]
    got = []
    for ch in range(nch):
        row = []
        for s in range(REAC_SAMPLES_PER_PKT):
            grp = p.audio.time_samples[s].pair_groups[ch // 2]
            if ch % 2 == 0:
                row.append(s24le(grp[3], grp[0], grp[1]))
            else:
                row.append(s24le(grp[4], grp[5], grp[2]))
        got.append(row)
    assert got == fx["pcm_s24"]


@pytest.mark.parametrize("name,fx", UP_FRAMES)
def test_braid_structure_agrees_with_the_absolute_byte_map(name, fx):
    """Decoding via the ksy pair-group structure and via reac_braid_pos()'s
    absolute offsets must be the same bytes — otherwise the structural
    description drifted from the layout it describes."""
    raw = bytes.fromhex(fx["hex"])
    nch, region = fx["channels"], raw[50:50 + fx["channels"] * 36]
    p = parse_frame(fx["hex"])
    for ch in range(nch):
        for s in range(REAC_SAMPLES_PER_PKT):
            lo, mid, hi = oracle_braid_pos(s, ch, nch)
            grp = p.audio.time_samples[s].pair_groups[ch // 2]
            idx = (3, 0, 1) if ch % 2 == 0 else (4, 5, 2)
            assert (grp[idx[0]], grp[idx[1]], grp[idx[2]]) == (region[lo], region[mid], region[hi])


# --------------------------------------------------------------------------
# frame-kind classification and control-op dispatch
# --------------------------------------------------------------------------

@pytest.mark.parametrize("name,fx", UP_FRAMES)
def test_upstream_frames_classify_as_filler(name, fx):
    p = parse_frame(fx["hex"])
    block34 = bytes.fromhex(fx["hex"])[16:50]
    assert p.control.ctrl_kind == oracle_ctrl_kind(block34) == KIND_FILLER
    assert len(p.control.block.descriptor) == 16


@pytest.mark.parametrize("name,blk", BLOCKS)
def test_ctrl_kind_matches_oracle(name, blk):
    t = parse_block(blk["hex"])
    assert t.ctrl_kind == oracle_ctrl_kind(bytes.fromhex(blk["hex"]))


@pytest.mark.parametrize("name,blk", BLOCKS)
def test_block_checksum_valid(name, blk):
    t = parse_block(blk["hex"])
    assert oracle_block_cksum_ok(t.raw_block), f"{name}: block does not sum to 0"
    assert t.block_checksum == t.raw_block[31]


@pytest.mark.parametrize("name,blk", BLOCKS)
def test_op_dispatch_reads_the_op_the_oracle_reads(name, blk):
    raw = bytes.fromhex(blk["hex"])
    t = parse_block(blk["hex"])
    assert t.op_raw == (raw[2] << 8) | raw[3]
    assert t.op_len_raw == (raw[4] << 8) | raw[5]
    if t.type_word == R.Reac.FrameType.control.value:
        assert t.block.op.value if hasattr(t.block.op, "value") else t.block.op
        assert t.block.rec_len == t.op_len_raw


def test_page_0103_subpage_dispatch():
    kinds = {}
    for name, blk in BLOCKS:
        t = parse_block(blk["hex"])
        if t.op_raw == 0x0103:
            kinds[name] = t.block.payload.page_kind
    assert kinds["chanmap_w00"] == R.Reac.PageKind.chanmap.value
    assert kinds["s1608_config_block"] == R.Reac.PageKind.commit_report.value
    assert kinds["s0808_config_block"] == R.Reac.PageKind.commit_report.value
    assert kinds["s4000s_config_block"] == R.Reac.PageKind.commit_report.value
    assert kinds["enroll_000d_w8"] == R.Reac.PageKind.enroll_group_map.value


# --------------------------------------------------------------------------
# declared / derived widths — the placement CARRIERS, never a base
# --------------------------------------------------------------------------

@pytest.mark.parametrize("model,in_ch,out_ch,selector,board_config_code", [
    ("s0808", 8, 8, 0x84, 0x00),
    ("s1608", 16, 8, 0x82, 0x02),
    ("s4000s", 32, 8, 0x84, 0x00),
])
def test_commit_report_declares_the_box_width(model, in_ch, out_ch, selector, board_config_code):
    blk = next(b for n, b in BLOCKS if n == f"{model}_config_block")
    page = parse_block(blk["hex"]).block.payload.page
    assert page.selector == selector
    assert page.board_config_code == board_config_code
    assert page.declared_in_channels == in_ch
    assert page.declared_out_channels == out_ch
    assert len(page.cells) == 12
    # the inventory is in DECLARATION order, always from cell 0 — the S-1608
    # declares cells 0..3 and is still placed at 0x20, which is why no base is
    # derivable from this frame (see PLACEMENT-EVIDENCE.md).
    inputs = [i for i, c in enumerate(page.cells)
              if c == R.Reac.InventoryCell.analog_input]
    assert inputs == list(range(in_ch // 4))


def test_commit_report_carriers_are_collinear_in_this_corpus():
    """The three surviving placement carriers agree on every row we hold — which
    is exactly why none of them can be promoted to the law. This test pins the
    collinearity so a future fixture that BREAKS it is noticed immediately."""
    rows = []
    for name, blk in BLOCKS:
        if not name.endswith("_config_block"):
            continue
        page = parse_block(blk["hex"]).block.payload.page
        rows.append((page.declared_in_channels, page.selector, page.board_config_code))
    for width, selector, board_config_code in rows:
        assert (width == 16) == (selector == 0x82) == (board_config_code == 0x02)


def test_enroll_group_map_is_a_pure_function_of_width():
    page = parse_block(
        next(b for n, b in BLOCKS if n == "enroll_000d_w8")["hex"]
    ).block.payload.page
    assert page.enrolled_in_channels == 8
    assert page.input_groups == [0x41, 0x00, 0x00, 0x00, 0x00]   # front-packed
    assert page.output_groups == [0x00, 0xc3, 0xc3, 0xc3, 0xc3]  # back-packed
    assert page.console_field in (0x00, 0x01)


@pytest.mark.parametrize("console,console_field", [
    ("m200", 0x00), ("m300", 0x00), ("m5000", 0x01),
])
@pytest.mark.parametrize("state,box_in_width,box_count", [
    ("idle", 0x08, 0), ("s1608", 0x10, 1), ("s0808", 0x08, 1),
])
def test_cfea_announces_the_linked_box_width(console, console_field, state,
                                             box_in_width, box_count):
    blk = next(b for n, b in BLOCKS if n == f"cfea_{console}_{state}")
    p = parse_block(blk["hex"]).block.payload
    assert p.total_slots == 0x28          # the 40-slot AUDIO fabric
    assert p.box_in_width == box_in_width  # placement carrier
    assert p.console_field == console_field
    assert p.box_count == box_count
    assert bytes(p.master_mac)[:3] == b"\x00\x40\xab"  # Roland OUI


def test_the_three_consoles_differ_in_exactly_two_bytes():
    """MAC and console_field, nothing else — the finding cfea pins."""
    for state in ("idle", "s1608", "s0808"):
        blocks = {c: bytes.fromhex(next(b for n, b in BLOCKS
                                        if n == f"cfea_{c}_{state}")["hex"])
                  for c in ("m200", "m300", "m5000")}
        a, b = blocks["m200"], blocks["m5000"]
        # indices are frame[16:50]-relative, so index i is frame offset 16+i
        differing = {i for i in range(34) if a[i] != b[i]}
        mac = set(range(11, 17))          # payload MAC, frame[27:33]
        console_field = {35 - 16}         # frame[35]
        checksum = {49 - 16}              # the block stamp follows from both
        assert differing <= mac | console_field | checksum, sorted(differing)


# --------------------------------------------------------------------------
# the op-0403 DT1 record container
# --------------------------------------------------------------------------

def dt1(t):
    """The DT1 record inside an op-0403 container.

    op-0403 is discriminated at block[4]: 0x00 is a DT1 record, 0x02 is the box's
    constant upstream return block. The record therefore sits one level in."""
    assert t.block.payload.subtype == 0x00, 'not a DT1 subtype'
    return t.block.payload.body


@pytest.mark.parametrize("name,blk", [(n, b) for n, b in BLOCKS if "cc00" in n])
def test_dt1_container_shape(name, blk):
    r = dt1(parse_block(blk["hex"]))
    assert r.len_echo == parse_block(blk["hex"]).op_len_raw - 5
    assert r.device_id == 0x0a
    assert bytes(r.model_id) == b"\x00\x00\x12"
    assert r.record_len == r.data_len + 3
    assert r.sysex_end == b"\xf7"


@pytest.mark.parametrize("name,blk", [(n, b) for n, b in BLOCKS if "cc00" in n])
def test_dt1_inner_checksum_is_0x80(name, blk):
    raw = bytes.fromhex(blk["hex"])
    r = dt1(parse_block(blk["hex"]))
    record = raw[18:18 + r.record_len]   # TAG .. CKSUM, frame[34:34+record_len]
    assert oracle_record_cksum_ok(record), f"{name}: record does not sum to 0x80"


def test_grant_sweep_head_amp_records_match_the_oracle_cell_table():
    """The 56-frame M-200i -> S-1608 enrolment sweep, decoded to (CH, PARAM,
    VALUE) triples, must reproduce the table the C grant tests pin."""
    cells = []
    for hexstr in GRANT_FRAMES:
        t = parse_block(hexstr)
        assert t.ctrl_kind == oracle_ctrl_kind(bytes.fromhex(hexstr))
        if t.ctrl_kind != KIND_HEADAMP:
            continue
        d = dt1(t).data
        cells.append([d.ch, d.param.value, d.value])
    assert len(cells) == 48
    assert cells == GRANT_CELLS


def test_grant_sweep_every_record_and_block_checksums():
    for hexstr in GRANT_FRAMES:
        raw = bytes.fromhex(hexstr)
        t = parse_block(hexstr)
        assert oracle_block_cksum_ok(t.raw_block)
        r = dt1(t)
        assert oracle_record_cksum_ok(raw[18:18 + r.record_len])


def test_grant_sweep_tag_inventory():
    """The sweep is not head-amp only: it opens with the join grant, carries a
    head marker and six identity requests, and the oracle folds all of those
    into GRANT rather than giving them kinds of their own."""
    tags = {}
    for hexstr in GRANT_FRAMES:
        t = parse_block(hexstr)
        tags.setdefault(t.dt1_tag, 0)
        tags[t.dt1_tag] += 1
    assert tags[R.Reac.RegPage.head_amp.value] == 48
    assert tags[R.Reac.RegPage.join_grant.value] == 1
    assert tags[R.Reac.RegPage.head_mark.value] == 1
    assert tags[R.Reac.RegPage.identity.value] == 6
    assert sum(tags.values()) == 56


def test_head_amp_channel_space_is_not_the_audio_fabric():
    """Every CH in the S-1608 sweep sits in 0x20..0x2f — past the 40-slot audio
    fabric and inside the 48-slot head-amp space. A table bounded by 40 drops
    the box's inputs 9..16 silently, which is the bug this distinction exists to
    prevent."""
    chans = sorted({c[0] for c in GRANT_CELLS})
    assert chans == list(range(0x20, 0x30))
    assert max(chans) >= REAC_MAX_CHANNELS
    assert max(chans) < 0x30


def test_head_amp_params_and_value_ranges():
    for ch, param, value in GRANT_CELLS:
        assert ch < 0x30
        assert param in (0x00, 0x01, 0x02)
        assert value <= (0x37 if param == 0x02 else 0x01)


# --------------------------------------------------------------------------
# the establishment ops
# --------------------------------------------------------------------------

SCENE_BODY = (pathlib.Path(__file__).parent / "fixtures" / "scene-m200i-8904.bin").read_bytes()


def test_scene_body_fixture_is_a_complete_transfer():
    """The recovered body must be exactly what the master declares, or every
    offset asserted below is measured against a truncated capture. 8904 is not a
    magic number here: it is 0x37c + 8 + 800*10 + 4, the SCEN block's own
    arithmetic, and the box carries the 800 independently in its literal pool."""
    assert len(SCENE_BODY) == 0x22c8 == 8904
    assert 0x37c + 8 + 800 * 10 + 4 == len(SCENE_BODY)


def test_scene_chunks_are_slices_of_the_body():
    """Every op-0100 payload in the corpus is a literal 26-byte slice of the
    scene body at 24 + 26k. This is the whole case that op-0100 is a scene
    continuation and not a probe, and it is a VALUE test across the boundary:
    bytes captured off the wire as 'probe windows' against bytes reassembled
    from a different capture of the transfer.

    The negative control matters as much as the positive: a payload that is NOT
    in the body must not be found, or the test would pass on any input."""
    chunks = {SCENE_BODY[24 + 26 * k:24 + 26 * k + 26] for k in range(341)}
    assert len(chunks) == 15, "the corpus catalogued 15 distinct op-0100 payloads"

    seen_cells = set()
    n = 0
    for name, blk in BLOCKS:
        if not name.startswith("probe_"):
            continue
        t = parse_block(blk["hex"])
        assert t.op_raw == 0x0100
        assert t.op_len_raw == 0x001a == 26, "rec_len is the CHUNK LENGTH"
        p = t.block.payload
        assert p.chunk_reserved == 0
        assert bytes(p.chunk) in chunks, f"{name} is not a slice of the body"
        assert p.checksum == t.raw_block[31]
        seen_cells |= set(bytes(p.chunk)) & {0x02, 0x03}
        n += 1
    assert n == 10
    # 0x02 / 0x03 are inventory_cell values reached by the 10-byte record
    # stride, not the master sub-states they were read as.
    assert seen_cells == {0x02, 0x03}
    assert bytes(range(0x40, 0x40 + 26)) not in chunks   # negative control


def test_scene_header_declares_the_total_not_a_model_constant():
    t = parse_block(next(b for n, b in BLOCKS if n == "sub01")["hex"])
    p = t.block.payload
    assert t.op_raw == 0x0101
    assert t.op_len_raw == 0x0018 == 24, "rec_len is this chunk's length"
    assert p.scene_total_len == len(SCENE_BODY) == 0x22c8
    assert bytes(p.body_head) == SCENE_BODY[:24]
    assert bytes(p.body_head)[:4] == b"1234"


def test_scene_final_carries_the_tail():
    t = parse_block(next(b for n, b in BLOCKS if n == "sub02")["hex"])
    assert t.op_raw == 0x0102
    assert t.op_len_raw == 0x000e == 14 == (8904 - 24) % 26
    assert bytes(t.block.payload.chunk)[:14] == SCENE_BODY[-14:]


def test_scene_body_parses_and_its_offsets_are_where_the_box_reads_them():
    """The S-1608 resolves these offsets out of its own literal pool against one
    staging base. Parsing must land each field on the same byte."""
    b = R.Reac.SceneBody(KaitaiStream(BytesIO(SCENE_BODY)))
    assert bytes(b.magic) == b"1234"
    assert b.unit_map_select == 1            # +0x04, every desk, every box
    assert b.map_a_arg == 4                  # +0x08
    assert b.revision == 0                   # +0x14, 1 on an M-5000
    assert len(b.slots) == 80                # +0x1a, 800 bytes
    assert bytes(b.master_id)[:3] == bytes.fromhex("0040ab")   # Roland OUI
    assert bytes(b.sysp.tag) == b"SYSP"      # +0x368
    assert bytes(b.scen.tag) == b"SCEN"      # +0x37c
    assert len(b.scen.entries) == 800
    # the offsets themselves, so a layout drift cannot pass quietly
    assert SCENE_BODY[0x1a:0x1a + 800] == b"".join(
        SCENE_BODY[0x1a + 10 * i:0x1a + 10 * i + 10] for i in range(80))
    assert SCENE_BODY[0x340:0x346] == bytes(b.master_id)
    assert SCENE_BODY[0x368:0x36c] == b"SYSP"
    assert SCENE_BODY[0x37c:0x380] == b"SCEN"


SCENE_BODY_M5000 = (pathlib.Path(__file__).parent / "fixtures" / "scene-m5000-8904.bin").read_bytes()


def test_scene_is_the_desks_not_the_boxs():
    """Two desk generations, and the bytes that differ are countable.

    Across the whole capture corpus 8 of 8904 bytes vary between real desks: the
    revision, the low half of the master id, and four bytes of M-5000 padding
    that change between that desk's own runs. An emitter therefore fills in two
    fields and copies the rest — which is the whole reason this grammar can be
    instantiated from rather than only parsed with."""
    a, b = SCENE_BODY, SCENE_BODY_M5000
    assert len(a) == len(b) == 8904
    differ = {i for i in range(8904) if a[i] != b[i]}
    assert differ == {0x14, 0x343, 0x344, 0x345, 0x366, 0x367, 0x22c6, 0x22c7}
    # the two that are FIELDS
    assert a[0x14] == 0 and b[0x14] == 1                      # revision
    assert a[0x340:0x343] == b[0x340:0x343] == bytes.fromhex("0040ab")
    # everything structural is byte-identical, including both record tables
    assert a[0x1a:0x1a + 800] == b[0x1a:0x1a + 800]
    assert a[0x384:0x384 + 8000] == b[0x384:0x384 + 8000]


def test_scene_body_parses_on_a_second_desk_generation():
    m = R.Reac.SceneBody(KaitaiStream(BytesIO(SCENE_BODY_M5000)))
    assert bytes(m.magic) == b"1234"
    assert m.unit_map_select == 1
    assert m.revision == 1                       # 0 on a V-Mixer desk
    assert len(m.slots) == 80 and len(m.scen.entries) == 800
    assert bytes(m.sysp.tag) == b"SYSP" and bytes(m.scen.tag) == b"SCEN"


def test_only_three_tags_are_validated_by_the_box():
    """The box's commit checks three four-byte tags and nothing else.

    Run the box's own code over real capture data with the body zeroed in
    128-byte windows and exactly 2 of the 70 windows break the commit. This test
    is the static half of that result: the three tags fall in exactly two
    windows, and the parser finds them at the offsets the box hard-codes. Two
    methods, one answer.

    The consequence for an emitter is the point: twelve bytes are checked and
    8892 are not, so a wrong value anywhere else is promoted silently."""
    b = R.Reac.SceneBody(KaitaiStream(BytesIO(SCENE_BODY)))
    tags = {0x000: bytes(b.magic), 0x368: bytes(b.sysp.tag), 0x37c: bytes(b.scen.tag)}
    assert tags == {0x000: b"1234", 0x368: b"SYSP", 0x37c: b"SCEN"}
    for off, want in tags.items():
        assert SCENE_BODY[off:off + 4] == want
    windows = {o // 128 for off in tags for o in range(off, off + 4)}
    assert windows == {0, 6}
    assert -(-len(SCENE_BODY) // 128) == 70


def test_scene_declares_twelve_inventory_cells_like_the_box_does():
    """The box's commit walks twelve cells at a stride of 0x28 over the slot
    table — four records each — so the desk declares its inventory in exactly the
    vocabulary the box declares its own in commit_report_page. An M-200i sends
    eight analog-input cells and four absent: 32 declared inputs."""
    b = R.Reac.SceneBody(KaitaiStream(BytesIO(SCENE_BODY)))
    cells = [b.slots[4 * i].cell for i in range(12)]
    assert cells.count(R.Reac.InventoryCell.analog_input) == 8
    assert cells.count(R.Reac.InventoryCell.absent) == 4
    assert sum(4 for c in cells if c == R.Reac.InventoryCell.analog_input) == 32
    # the scene carries no per-channel head-amp values: the commit is the GATE,
    # the values arrive as op-0403 TAG 0x0101 records.
    assert {(s.field_2, s.field_4, s.field_6, s.field_8) for s in b.slots} == {(0, 1, 0, 0)}


def test_chanmap_ring_is_identical_for_every_box():
    """The chanmap carries no per-box placement: slots 0x00..0x27 always read
    bank 0x28, 0x28..0x2f always 0x38, plus a 0xfe wrap marker."""
    seen = set()
    for name, blk in BLOCKS:
        if not name.startswith("chanmap_"):
            continue
        page = parse_block(blk["hex"]).block.payload.page
        assert page.page_id == 0x01
        assert len(page.entries) == 8
        for e in page.entries:
            if e.slot == 0xfe:
                assert e.is_identity_record
                assert e.cell_and_flags in (0x00, 0x01)
                assert e.sens == 0x00
                continue
            assert e.slot < 0x30
            assert e.cell_and_flags == (0x38 if e.slot >= 0x28 else 0x28)
            assert e.sens == 0x00, "no console has ever put a value here"
            assert e.flag_slot_4 == 1 and e.flag_slot_8 == 0 and e.flag_slot_6 == 0
            seen.add(e.slot)
        assert page.entries[0].slot == bytes.fromhex(blk["hex"])[7]  # sel2 cursor
    assert seen


# --------------------------------------------------------------------------
# corpus-level sanity
# --------------------------------------------------------------------------

def test_every_fixture_parses_and_is_covered():
    assert len(UP_FRAMES) == 4
    assert len(BLOCKS) >= 40
    assert len(GRANT_FRAMES) == 56
    kinds = {oracle_ctrl_kind(bytes.fromhex(b["hex"])) for _, b in BLOCKS}
    kinds |= {oracle_ctrl_kind(bytes.fromhex(h)) for h in GRANT_FRAMES}
    kinds |= {KIND_FILLER}
    # Every kind the classifier can produce is either exercised by a fixture or
    # named here with the reason it cannot be. A set that merely "contains" the
    # expected kinds would not notice a kind quietly falling out of reach.
    exercised = {KIND_FILLER, KIND_PROBE, KIND_MASTER_HB, KIND_MASTER_ANNOUNCE,
                 KIND_GRANT, KIND_HEADAMP, KIND_BOX_HB, KIND_CONFIG_ANNOUNCE,
                 KIND_GROUP_MAP, KIND_RECORD_FRAGMENT}
    unreachable = {
        KIND_NONE: "a non-REAC frame never reaches classification",
        KIND_UNKNOWN: "no fixture carries an unrecognised link or subtype -- "
                      "the two that used to, 0x0401 and 0x0402, are now "
                      "record_fragment",
        KIND_LINK2: "link 0x02 is built by the S-4000S image and appears in no "
                    "capture; FIRMWARE-ONLY",
    }
    # KIND_BOX_HB had no fixture at all until 2026-08-23 -- 10217 frames on the
    # wire and nothing in the goldens -- so `box_link_ack` was added rather than
    # excused here.
    _ = {
    }
    assert kinds == exercised, (
        "classifier coverage changed: %s" % sorted(kinds ^ exercised))
    assert not (kinds & set(unreachable)), "an 'unreachable' kind was produced"

    fragments = {n for n, b in BLOCKS
                 if oracle_ctrl_kind(bytes.fromhex(b["hex"])) == KIND_RECORD_FRAGMENT}
    assert fragments == {"s0808_name_block", "s0808_extra_block"}


# --------------------------------------------------------------------------
# The control block's header, as the stagebox firmware builds it
# --------------------------------------------------------------------------

@pytest.mark.parametrize("name,blk", BLOCKS)
def test_op_decomposes_into_link_and_segment(name, blk):
    """block[0] is a LINK selector and block[1] a two-bit SEGMENT field.

    The 16-bit `op` every tool indexes on is those two bytes side by side, so
    the decomposition must reproduce it exactly on every captured block. A test
    that only checked one direction would pass on a grammar that had silently
    dropped the second byte."""
    t = parse_block(blk["hex"])
    if not hasattr(t.block, "link"):
        pytest.skip("FILLER carries no control header")
    raw = bytes.fromhex(blk["hex"])
    assert int(t.block.link) == raw[2]
    assert t.block.seg == raw[3]
    assert t.block.seg_kind == raw[3] & 3
    assert t.block.seg_is_first == bool(raw[3] & 1)
    assert t.block.seg_is_last == bool(raw[3] & 2)
    assert t.block.opcode == raw[6]
    assert t.op_raw == (raw[2] << 8) | raw[3], "the two views must agree"


def test_op_len_counts_from_block_4_on_the_record_link():
    """On link 4 the length counts block[4] inclusive, so it lands exactly on
    the SysEx terminator of a single-frame record."""
    seen = 0
    for name, blk in BLOCKS:
        raw = bytes.fromhex(blk["hex"])
        if raw[2] != 0x04 or (raw[3] & 3) != 3 or raw[6] != 0x00:
            continue
        n = (raw[4] << 8) | raw[5]
        assert raw[6 + n - 1] == 0xF7, f"{name}: length {n:#x} does not end on F7"
        seen += 1
    assert seen >= 4, f"only {seen} single-frame link-4 blocks — too few to mean anything"


def test_op_len_counts_from_block_4_on_the_chanmap():
    """25 = one opcode byte + eight three-byte records. The length is a length,
    not the sub-page selector it was read as."""
    seen = 0
    for name, blk in BLOCKS:
        raw = bytes.fromhex(blk["hex"])
        if raw[2:4] != b"\x01\x03" or raw[6] != 0x01:
            continue
        assert (raw[4] << 8) | raw[5] == 1 + 8 * 3
        seen += 1
    assert seen, "no chanmap block in the fixtures — this test proved nothing"


# --------------------------------------------------------------------------
# op 0401 + op 0402 are ONE Roland DT1 record, split across two frames
# --------------------------------------------------------------------------

def _fragment(name):
    blk = dict(BLOCKS)[name]
    return parse_block(blk["hex"]).block.payload


def test_the_two_link4_fragments_reassemble_into_one_sysex():
    first, last = _fragment("s0808_name_block"), _fragment("s0808_extra_block")
    assert first._parent.seg_kind == 1, "0x0401 must read FIRST"
    assert last._parent.seg_kind == 2, "0x0402 must read LAST"
    assert first.len_echo == 0x16 and last.len_echo == 0x08
    rec = bytes(first.fragment) + bytes(last.fragment)

    assert rec[0] == 0xF0 and rec[-1] == 0xF7, "not a complete SysEx"
    assert rec[1] == 0x41, "not Roland"
    assert rec[6] == 0x12, "not a DT1 write"
    assert rec[7:9] == b"\x05\x00", "not the identity tag"
    assert sum(rec[7:-1]) % 128 == 0, "the DT1 checksum does not close"
    assert bytes(rec[12:18]) == b"S-0808"

    # Neither fragment closes on its own — which is the whole point.
    assert sum(bytes(first.fragment)[7:]) % 128 != 0
    assert 0xF7 not in bytes(first.fragment)


def test_group_map_bytes_decode_as_the_firmware_reads_them():
    """The only firmware that parses op-0103 0x000d reads its ten bytes as two
    packed fields, not as two five-byte arrays. Reproduce both loops."""
    page = parse_block(
        next(b for n, b in BLOCKS if n == "enroll_000d_w8")["hex"]
    ).block.payload.page
    g = bytes(page.group_bytes)
    assert g == bytes(page.input_groups) + bytes(page.output_groups), \
        "group_bytes must be exactly the same ten bytes, in order"
    low6 = [g[i >> 1] & 0x3f for i in range(12)]
    top2 = [(v if (v := g[i] >> 6) in (0, 1) else -1) for i in range(10)]
    assert low6 == [1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    assert top2 == [1, 0, 0, 0, 0, 0, -1, -1, -1, -1]


# --------------------------------------------------------------------------
# The reclassification is a PARTITION, not a reshuffle
# --------------------------------------------------------------------------

def test_reclassification_only_splits_and_never_moves_sideways():
    """Every frame the new classifier moves must come out of the old PROBE
    bucket or the old UNKNOWN bucket, and nothing else may move at all.

    A classifier rewrite is the kind of change that looks right on the frames
    you were staring at while quietly relabelling something else. Comparing the
    two expressions frame by frame is the only way to see that; a spot check on
    the frames that were MEANT to move cannot."""
    allowed = {
        (KIND_PROBE, KIND_PROBE),
        (KIND_PROBE, KIND_CONFIG_ANNOUNCE),
        (KIND_PROBE, KIND_GROUP_MAP),
        (KIND_PROBE, KIND_BOX_HB),
        (KIND_UNKNOWN, KIND_RECORD_FRAGMENT),
    }
    moved = collections.Counter()
    total = 0
    for name, blk in BLOCKS:
        raw = bytes.fromhex(blk["hex"])
        was, now = legacy_ctrl_kind(raw), oracle_ctrl_kind(raw)
        total += 1
        if was == now:
            continue
        assert (was, now) in allowed, (
            "%s moved %d -> %d, which is not a split of the old buckets"
            % (name, was, now))
        moved[(was, now)] += 1
    for h in GRANT_FRAMES:
        raw = bytes.fromhex(h)
        was, now = legacy_ctrl_kind(raw), oracle_ctrl_kind(raw)
        total += 1
        assert was == now or (was, now) in allowed
        if was != now:
            moved[(was, now)] += 1
    assert total >= 90, "too few frames compared for this to mean anything"
    assert moved, "nothing moved at all -- the two classifiers are identical, "\
                  "so this test is not observing the change it claims to"
    # the split must conserve: everything that left PROBE landed in the three
    # kinds PROBE splits into
    left_probe = sum(v for (w, n), v in moved.items() if w == KIND_PROBE)
    into = sum(v for (w, n), v in moved.items()
               if w == KIND_PROBE and n in (KIND_CONFIG_ANNOUNCE, KIND_GROUP_MAP,
                                            KIND_BOX_HB))
    assert left_probe == into, "a frame left PROBE for somewhere else"


def test_grammar_and_oracle_agree_on_every_fixture():
    """The ksy expression and the transcription of libreac must land on the
    same kind for every fixture, or one of the two has been edited alone."""
    for name, blk in BLOCKS:
        t = parse_block(blk["hex"])
        assert int(t.ctrl_kind) == oracle_ctrl_kind(bytes.fromhex(blk["hex"])), name
    for h in GRANT_FRAMES:
        t = parse_block(h)
        assert int(t.ctrl_kind) == oracle_ctrl_kind(bytes.fromhex(h))


def test_a_fragment_with_the_wrong_wrapper_is_REFUSED():
    """The `contents` guard on record_fragment's wrapper must actually reject.

    Deleting that guard left the whole suite GREEN, because nothing fed the
    parser a fragment with a wrong wrapper -- the guard was decoration. So this
    forges one, and forges it PROPERLY: the block checksum is restamped so the
    forgery is valid in every respect except the four bytes under test. A
    forgery that is also malformed somewhere else can be refused for the wrong
    reason, and then the guard is still unproven."""
    good = bytearray(bytes.fromhex(dict(BLOCKS)["s0808_name_block"]["hex"]))
    assert good[6:10] == bytearray(b"\x00\x02\x00\xfe"), "fixture moved"
    assert sum(good[2:]) % 256 == 0, "the fixture block must sum to zero"

    forged = bytearray(good)
    forged[9] = 0xff                       # wrapper byte 3: fe -> ff
    forged[33] = (forged[33] - 1) % 256    # restamp so the block still sums to 0
    assert sum(forged[2:]) % 256 == 0, "the forgery must be checksum-valid"
    assert oracle_ctrl_kind(bytes(forged)) == KIND_RECORD_FRAGMENT, \
        "the forgery must still CLASSIFY as a fragment, or the parser would " \
        "never reach the guard and this test would prove nothing"

    with pytest.raises(Exception):
        t = parse_block(bytes(forged).hex())
        t.block.payload.fragment      # force the lazy payload

    # and the untouched original must still parse, so the test is not simply
    # rejecting everything
    parse_block(bytes(good).hex()).block.payload.fragment
