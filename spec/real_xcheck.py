"""The grammar against real frames, read by something that is not the grammar.

`fixtures/real_frames.json` holds frames taken verbatim from the capture corpus
(Roland consoles and stageboxes, 48 and 96 kHz): whole frames, and the 34-byte
`frame[16:50]` window of every control kind. Each carries libreac's own decode of
the same bytes, and the checks below also read the bytes with plain arithmetic,
so the grammar is compared with two witnesses it did not write:

  * the arithmetic of the wire: the outer checksum sums to zero, the inner DT1
    checksum is seven bits, the two bytes after the end marker are the low 16 bits
    of the frame's own Ethernet FCS, the length is 52 + 36 n, the counter is a
    little-endian u16;
  * the audio itself: a box return read through the braid is a smooth signal and
    the same bytes read as plain sample-major are not. A permutation the grammar
    got wrong cannot pass that.

    make -C spec check
"""
import hashlib
import json
import pathlib
import struct
import sys
import zlib

import pytest
from kaitaistruct import BytesIO, KaitaiStream

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import reac as R  # noqa: E402  generated from reac.ksy by `make parser`
from xcheck_c_oracle import ksy_planar  # noqa: E402

REAL = json.loads((HERE / "fixtures" / "real_frames.json").read_text())
FRAMES = REAL["frames"]
WINDOWS = REAL["windows"]


def parse_frame(raw):
    return R.Reac(KaitaiStream(BytesIO(raw)))


def parse_window(win):
    return R.Reac.TypedBlock(KaitaiStream(BytesIO(win)))


def kind(t):
    return t.ctrl_kind.name


def s24(b):
    v = b[0] | b[1] << 8 | b[2] << 16
    return v - (1 << 24) if v & 0x800000 else v


def roughness(rows):
    """Mean |sample-to-sample step| / mean |sample| over the channels that carry
    a signal. A tone or program material is smooth (small); the same bytes read
    in the wrong order are broadband noise (about 1 and above)."""
    tot, n = 0.0, 0
    for x in rows:
        if max(abs(v) for v in x) < 3000:
            continue
        tot += sum(abs(x[i + 1] - x[i]) for i in range(len(x) - 1)) / (len(x) - 1) \
            / (sum(abs(v) for v in x) / len(x) + 1)
        n += 1
    return tot / n if n else None


def plain_planar(audio, n):
    return [[s24(audio[(s * n + ch) * 3:(s * n + ch) * 3 + 3]) for s in range(12)]
            for ch in range(n)]


# --------------------------------------------------------------------------
# whole frames
# --------------------------------------------------------------------------

@pytest.mark.parametrize("fx", FRAMES, ids=[f["name"] for f in FRAMES])
def test_a_real_frame_is_the_frame_the_wire_arithmetic_says(fx):
    raw = bytes.fromhex(fx["hex"])
    residue = (len(raw) - 52) % 36
    assert residue == fx["residue"] and residue in (0, 2)
    n = (len(raw) - residue - 52) // 36
    assert n == fx["width"]
    p = parse_frame(raw)
    assert p.num_channels == n
    assert p.frame_len == len(raw) - residue
    assert len(p.capture_residue) == residue
    assert bytes(p.end_marker) == b"\xc2\xea" == raw[len(raw) - residue - 2:len(raw) - residue]
    assert bytes(p.eth_src).hex(":") == fx["src"]
    assert p.counter == struct.unpack("<H", raw[14:16])[0]
    assert p.is_broadcast == (raw[:6] == b"\xff" * 6)
    assert p.is_downstream_width == (n == 40)


@pytest.mark.parametrize("fx", [f for f in FRAMES if f["residue"]],
                         ids=[f["name"] for f in FRAMES if f["residue"]])
def test_the_two_residue_bytes_are_the_low_half_of_the_frames_own_fcs(fx):
    raw = bytes.fromhex(fx["hex"])
    crc = zlib.crc32(raw[:-2]) & 0xFFFF
    assert raw[-2:] == struct.pack("<H", crc)


@pytest.mark.parametrize("fx", FRAMES, ids=[f["name"] for f in FRAMES])
def test_a_real_frame_agrees_with_libreac(fx):
    raw = bytes.fromhex(fx["hex"])
    lib = fx["libreac"]
    p = parse_frame(raw)
    assert p.frame_len == lib["clean_len"]
    assert p.num_channels == lib["channels"]
    assert p.counter == lib["counter"]
    assert kind(p.control) == lib["kind"]
    pcm = [v for ch in ksy_planar(p, p.num_channels) for v in ch]
    assert hashlib.sha256(b"".join(struct.pack("<i", v) for v in pcm)).hexdigest() \
        == lib["pcm_sha256"]


WITNESS = [f for f in FRAMES
           if f["smooth_braid"] is not None and f["smooth_plain"] is not None
           and f["smooth_braid"] < 0.3 and f["smooth_plain"] > 0.5
           and f["smooth_plain"] > 3 * f["smooth_braid"]]


def test_there_are_witness_frames_from_every_box_model_and_both_rates():
    assert {f["device"] for f in WITNESS} >= {"S-1608", "S-0808", "S-4000S-3208"}
    assert {f["rate"] for f in WITNESS} == {"48k", "96k"}


@pytest.mark.parametrize("fx", WITNESS, ids=[f["name"] for f in WITNESS])
def test_the_audio_region_decodes_to_a_signal_only_through_the_braid(fx):
    """Independent of libreac and of the permutation's author: the braid has to
    turn the bytes into something smooth, and the plain reading must not."""
    raw = bytes.fromhex(fx["hex"])
    p = parse_frame(raw)
    n = p.num_channels
    braided = roughness(ksy_planar(p, n))
    plain = roughness(plain_planar(raw[50:50 + n * 36], n))
    assert braided is not None and braided < 0.3
    assert plain is None or plain > 3 * braided


# --------------------------------------------------------------------------
# the control window of every kind
# --------------------------------------------------------------------------

@pytest.mark.parametrize("fx", WINDOWS, ids=[w["name"] for w in WINDOWS])
def test_a_real_control_window_is_classified_as_libreac_classifies_it(fx):
    win = bytes.fromhex(fx["hex"])
    assert len(win) == 34
    t = parse_window(win)
    assert kind(t) == fx["libreac"]["kind"]


@pytest.mark.parametrize("fx", [w for w in WINDOWS if w["libreac"]["kind"] != "filler"],
                         ids=[w["name"] for w in WINDOWS if w["libreac"]["kind"] != "filler"])
def test_a_real_control_block_sums_to_zero_and_says_what_the_bytes_say(fx):
    win = bytes.fromhex(fx["hex"])
    t = parse_window(win)
    assert sum(win[2:34]) & 0xFF == 0
    assert t.block_checksum == win[33] == t.block.block_checksum
    assert bytes(t.raw_block) == win[2:34]
    assert t.op_raw == int.from_bytes(win[2:4], "big")
    assert t.op_len_raw == int.from_bytes(win[4:6], "big")
    b = t.block
    assert int(b.seg_kind) == win[3] & 3
    assert (int(b.link), b.seg, b.rec_len, b.opcode) == (win[2], win[3], int.from_bytes(win[4:6], "big"), win[6])
    assert b.seg_is_first == bool(win[3] & 1) and b.seg_is_last == bool(win[3] & 2)
    lib = fx["libreac"]
    assert (int(b.link), b.seg, b.rec_len, b.opcode) == (lib["link"], lib["seg"], lib["rec_len"], lib["opcode"])


def _dt1_windows():
    out = []
    for w in WINDOWS:
        b = bytes.fromhex(w["hex"])
        if b[2:4] == b"\x04\x03" and b[6:10] == b"\x00\x02\x00\xfe" and b[11:13] == b"\xf0\x41":
            out.append(w)
    return out


DT1 = _dt1_windows()


def test_there_are_real_dt1_records():
    assert len(DT1) >= 15


@pytest.mark.parametrize("fx", DT1, ids=[w["name"] for w in DT1])
def test_a_real_dt1_record_is_the_roland_record_the_bytes_spell(fx):
    win = bytes.fromhex(fx["hex"])
    t = parse_window(win)
    rec = t.block.payload.body
    rec_len = int.from_bytes(win[4:6], "big")
    assert rec.len_echo == rec_len - 5 == win[10]
    assert int(rec.command) == win[17] and win[17] in (0x11, 0x12)
    assert int(rec.tag) == int.from_bytes(win[18:20], "big")
    data_len = rec_len - 0x10
    assert rec.data_len == data_len
    # the Roland rule: Sum(TAG .. CKSUM) is a multiple of 128
    assert sum(win[18:21 + data_len]) & 0x7F == 0
    assert rec.inner_checksum == win[20 + data_len]
    assert win[21 + data_len] == 0xF7


HEADAMP = [w for w in WINDOWS if w["libreac"]["kind"] == "head_amp"]


@pytest.mark.parametrize("fx", HEADAMP, ids=[w["name"] for w in HEADAMP])
def test_a_real_head_amp_record_reads_channel_parameter_value(fx):
    win = bytes.fromhex(fx["hex"])
    t = parse_window(win)
    h = t.block.payload.body.data
    assert win[18:20] == b"\x01\x01"
    assert (h.ch, int(h.param), h.value) == (win[20], win[21], win[22])
    lib = fx["libreac"]
    assert (h.ch, int(h.param), h.value) == (lib["ch"], lib["param"], lib["value"])


def test_every_control_kind_the_grammar_names_and_the_corpus_holds_is_here():
    held = {w["libreac"]["kind"] for w in WINDOWS}
    assert held >= {"filler", "scene_transfer", "master_hb", "master_announce", "grant",
                    "head_amp", "box_hb", "config_announce", "group_map", "record_fragment"}
    assert {w["device"] for w in WINDOWS} >= {"M-200i", "M-300", "M-5000", "S-0808", "S-1608",
                                              "S-4000S-3208"}


@pytest.mark.parametrize("fx", [w for w in WINDOWS if w["libreac"]["kind"] == "filler"],
                         ids=[w["name"] for w in WINDOWS if w["libreac"]["kind"] == "filler"])
def test_a_real_filler_has_sixteen_descriptor_words(fx):
    win = bytes.fromhex(fx["hex"])
    t = parse_window(win)
    assert list(t.block.descriptor) == list(struct.unpack(">16H", win[2:34]))


def test_an_m5000_sent_cfea_blocks_that_are_all_zero():
    """The grammar says a cfea announce carries op 0xffff. Thirty blocks in the
    M-5000's 96 kHz capture (matrix-m5000-s1608) are cfea with the whole block
    zero, checksum included. They parse, classify as an announce and carry op 0."""
    zero = [w for w in WINDOWS if w["hex"].startswith("cfea" + "00" * 32)]
    assert zero and all(w["device"] == "M-5000" for w in zero)
    t = parse_window(bytes.fromhex(zero[0]["hex"]))
    assert kind(t) == "master_announce"
    assert t.op_raw == 0 and sum(bytes.fromhex(zero[0]["hex"])[2:34]) == 0
