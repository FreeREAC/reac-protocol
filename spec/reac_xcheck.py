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
    """libreac reac_frame_clean_len(): strip the +2 FCS residue if present.

    A REAC frame is 52 + n*36 for some channel width n, so a length of
    52 + n*36 + 2 is a frame the capture left two bytes of its own Ethernet FCS
    on, and comes back reduced by 2. Every other length, including every clean
    one, is returned unchanged.
    """
    if n > REAC_UPSTREAM_OVERHEAD and (n - REAC_UPSTREAM_OVERHEAD) % REAC_UPSTREAM_BYTES_PER_CH == 2:
        return n - 2
    return n


def oracle_upstream_channels(n):
    """libreac reac_upstream_channels(): width from the frame size, or -1.

    Rejects an odd width (the braid packs channel pairs) and rejects the 40-ch
    solution, which is the downstream broadcast and never a box return.
    """
    clean = oracle_clean_len(n)
    rest = clean - REAC_UPSTREAM_OVERHEAD
    if rest <= 0 or rest % REAC_UPSTREAM_BYTES_PER_CH:
        return -1
    nch = rest // REAC_UPSTREAM_BYTES_PER_CH
    if nch % 2 or nch < 2 or nch >= REAC_MAX_CHANNELS:
        return -1
    return nch


# enum reac_ctrl_kind, in its C declaration order
KIND_NONE, KIND_FILLER, KIND_PROBE, KIND_MASTER_HB, KIND_MASTER_ANNOUNCE, \
    KIND_GRANT, KIND_HEADAMP, KIND_BOX_HB, KIND_UNKNOWN = range(9)


def oracle_ctrl_kind(block34):
    """reac_ctrl_parse()'s classification, over a frame[16:50] window.

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

def parse_frame(hexstr):
    return R.Reac(KaitaiStream(BytesIO(bytes.fromhex(hexstr))))


def parse_block(hexstr):
    """A bare captured frame[16:50] window — the form the C goldens store."""
    return R.Reac.TypedBlock(KaitaiStream(BytesIO(bytes.fromhex(hexstr))))


UP_FRAMES = [(f["name"], f) for f in UPSTREAM["frames"]]
BLOCKS = [(b["name"], b) for b in CONTROL["blocks"]]
GRANT_FRAMES = CONTROL["grant_sweep"]["frames"]
GRANT_CELLS = CONTROL["grant_sweep"]["head_amp_cells"]


# --------------------------------------------------------------------------
# frame geometry: clean_len, the +2 FCS residue, derived width
# --------------------------------------------------------------------------

@pytest.mark.parametrize("name,fx", UP_FRAMES)
def test_frame_geometry_matches_oracle(name, fx):
    p = parse_frame(fx["hex"])
    assert p.raw_len == fx["raw_len"]
    assert p.clean_len == oracle_clean_len(fx["raw_len"])
    assert p.num_channels == fx["channels"] == oracle_upstream_channels(fx["raw_len"])
    assert p.has_fcs_residue == (fx["raw_len"] != p.clean_len)
    assert p.len_audio == p.num_channels * REAC_UPSTREAM_BYTES_PER_CH
    assert not p.is_downstream_width


@pytest.mark.parametrize("name,fx", UP_FRAMES)
def test_fcs_residue_is_left_unread_not_modelled(name, fx):
    """The grammar stops at the end marker and never claims the residue.

    This is the whole design of the +2 handling, so it is pinned as a test: the
    parser consumes exactly `clean_len` bytes whether or not the capture kept
    the FCS, no field is declared for the leftovers, and nothing generated from
    this grammar can therefore emit them.
    """
    p = parse_frame(fx["hex"])
    assert p._io.pos() == p.clean_len
    assert p._io.size() - p._io.pos() == (2 if p.has_fcs_residue else 0)
    assert not hasattr(p, "ohrca_trailer")
    assert not hasattr(p, "fcs_residue")


@pytest.mark.parametrize("name,fx", UP_FRAMES)
def test_residue_changes_no_field(name, fx):
    """A frame parses the same with the residue and with it stripped.

    Residue is capture noise, so removing it must be a no-op on every field.
    The 342/1206 B goldens exercise the "with" side; slicing gives the "without"
    side of the very same frame.
    """
    p = parse_frame(fx["hex"])
    if not p.has_fcs_residue:
        pytest.skip("golden has no residue to strip")
    stripped = parse_frame(bytes.fromhex(fx["hex"])[:-2].hex())
    assert not stripped.has_fcs_residue
    assert stripped.clean_len == p.clean_len
    assert stripped.num_channels == p.num_channels
    assert stripped.counter == p.counter
    assert stripped.len_audio == p.len_audio
    assert bytes(stripped.end_marker) == bytes(p.end_marker) == b"\xc2\xea"
    assert [[bytes(g) for g in ts.pair_groups] for ts in stripped.audio.time_samples] \
        == [[bytes(g) for g in ts.pair_groups] for ts in p.audio.time_samples]


def test_clean_len_rule_over_the_whole_frame_family():
    """Both directions, clean and residue-carrying, against the oracle's one rule."""
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
    assert oracle_upstream_channels(1494) == -1


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
        assert t.block.op_len == t.op_len_raw


def test_page_0103_subpage_dispatch():
    kinds = {}
    for name, blk in BLOCKS:
        t = parse_block(blk["hex"])
        if t.op_raw == 0x0103:
            kinds[name] = t.block.payload.page_kind
    assert kinds["chanmap_w00"] == R.Reac.PageKind.chanmap.value
    assert kinds["s1608_config_block"] == R.Reac.PageKind.config_announce.value
    assert kinds["s0808_config_block"] == R.Reac.PageKind.config_announce.value
    assert kinds["s4000s_config_block"] == R.Reac.PageKind.config_announce.value
    assert kinds["enroll_000d_w8"] == R.Reac.PageKind.enroll_group_map.value


# --------------------------------------------------------------------------
# declared / derived widths — the placement CARRIERS, never a base
# --------------------------------------------------------------------------

@pytest.mark.parametrize("model,in_ch,out_ch,selector,unit_offset", [
    ("s0808", 8, 8, 0x84, 0x00),
    ("s1608", 16, 8, 0x82, 0x02),
    ("s4000s", 32, 8, 0x84, 0x00),
])
def test_config_announce_declares_the_box_width(model, in_ch, out_ch, selector, unit_offset):
    blk = next(b for n, b in BLOCKS if n == f"{model}_config_block")
    page = parse_block(blk["hex"]).block.payload.page
    assert page.selector == selector
    assert page.unit_offset == unit_offset
    assert page.declared_in_channels == in_ch
    assert page.declared_out_channels == out_ch
    assert len(page.cells) == 12
    # the inventory is in DECLARATION order, always from cell 0 — the S-1608
    # declares cells 0..3 and is still placed at 0x20, which is why no base is
    # derivable from this frame (see PLACEMENT-EVIDENCE.md).
    inputs = [i for i, c in enumerate(page.cells)
              if c == R.Reac.InventoryCell.analog_input]
    assert inputs == list(range(in_ch // 4))


def test_config_announce_carriers_are_collinear_in_this_corpus():
    """The three surviving placement carriers agree on every row we hold — which
    is exactly why none of them can be promoted to the law. This test pins the
    collinearity so a future fixture that BREAKS it is noticed immediately."""
    rows = []
    for name, blk in BLOCKS:
        if not name.endswith("_config_block"):
            continue
        page = parse_block(blk["hex"]).block.payload.page
        rows.append((page.declared_in_channels, page.selector, page.unit_offset))
    for width, selector, unit_offset in rows:
        assert (width == 16) == (selector == 0x82) == (unit_offset == 0x02)


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

@pytest.mark.parametrize("name,blk", [(n, b) for n, b in BLOCKS if "cc00" in n])
def test_dt1_container_shape(name, blk):
    r = parse_block(blk["hex"]).block.payload
    assert r.len_echo == parse_block(blk["hex"]).op_len_raw - 5
    assert r.device_id == 0x0a
    assert bytes(r.model_id) == b"\x00\x00\x12"
    assert r.record_len == r.data_len + 3
    assert r.sysex_end == b"\xf7"


@pytest.mark.parametrize("name,blk", [(n, b) for n, b in BLOCKS if "cc00" in n])
def test_dt1_inner_checksum_is_0x80(name, blk):
    raw = bytes.fromhex(blk["hex"])
    r = parse_block(blk["hex"]).block.payload
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
        d = t.block.payload.data
        cells.append([d.ch, d.param.value, d.value])
    assert len(cells) == 48
    assert cells == GRANT_CELLS


def test_grant_sweep_every_record_and_block_checksums():
    for hexstr in GRANT_FRAMES:
        raw = bytes.fromhex(hexstr)
        t = parse_block(hexstr)
        assert oracle_block_cksum_ok(t.raw_block)
        r = t.block.payload
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
        assert t.op_len_raw == 0x001a == 26, "op_len is the CHUNK LENGTH"
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
    assert t.op_len_raw == 0x0018 == 24, "op_len is this chunk's length"
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


def test_scene_declares_twelve_inventory_cells_like_the_box_does():
    """The box's commit walks twelve cells at a stride of 0x28 over the slot
    table — four records each — so the desk declares its inventory in exactly the
    vocabulary the box declares its own in config_announce_page. An M-200i sends
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
                assert e.bank == 0x00
                continue
            assert e.slot < 0x30
            assert e.bank == (0x38 if e.slot >= 0x28 else 0x28)
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
    # every kind the oracle can produce on a REAC frame is exercised. UNKNOWN is
    # reached by the two 0x04-family ops that are not the DT1 container — the
    # ASCII model-name frame (0x0401) and the extra cold-connect (0x0402).
    assert kinds == {KIND_FILLER, KIND_PROBE, KIND_MASTER_HB,
                     KIND_MASTER_ANNOUNCE, KIND_GRANT, KIND_HEADAMP,
                     KIND_UNKNOWN}
    unknown = {n for n, b in BLOCKS
               if oracle_ctrl_kind(bytes.fromhex(b["hex"])) == KIND_UNKNOWN}
    assert unknown == {"s0808_name_block", "s0808_extra_block"}
