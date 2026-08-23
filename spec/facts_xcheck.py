# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Pau Aliagas <linuxnow@gmail.com>
"""The ratchet: reac.ksy must still carry what protocol-facts.yaml says.

This is the hermetic half of the convergence — no compiler, no captures, no rig.
It reads `protocol-facts.yaml` and `reac.ksy` as data and asserts the second
still spells what the first declares, so a constant changed in one and not the
other is a RED TEST rather than a field failure six weeks later.

Three things it checks, and one it deliberately does not.

  * DIRECT — every fact carrying a `ksy:` path resolves through the grammar's
    own structure to the schema's value. It is a path, not a string match:
    `types/scene_chunk_payload/seq/1/size` follows the grammar, so a field that
    MOVES is caught even when the prose beside it still reads correctly.

  * STRUCTURAL — the scene body's tag offsets are recomputed by WALKING
    reac.ksy's own `scene_body` field sizes, and must land on the numeric
    offsets libreac indexes with. The grammar never writes 0x368 down; it
    describes a sequence of fields that happens to put SYSP there. If either
    the grammar's field list or the schema's number moves, they stop agreeing.
    That is the check with real teeth.

  * ARITHMETIC — the derived facts (`52 + 40*36 = 1492`, `24 + 341*26 + 14 =
    8904`) are recomputed from their inputs. The scene's three sizes and its
    total are one fact, not four, and this is where that is enforced.

  * NOT CHECKED HERE — anything only libreac spells. Comparing against the C is
    `xcheck_ctrl_oracle.py`, which needs a compiler; this file stays hermetic
    so CI can run it everywhere.
"""
import pathlib
import subprocess
import sys

import pytest
import yaml

HERE = pathlib.Path(__file__).resolve().parent
SCHEMA = yaml.safe_load((HERE / "protocol-facts.yaml").read_text())
KSY = yaml.safe_load((HERE / "reac.ksy").read_text())

FACTS = {}
for _g in SCHEMA["groups"]:
    for _f in _g.get("facts", []):
        assert _f["name"] not in FACTS, f"duplicate fact {_f['name']}"
        FACTS[_f["name"]] = dict(_f, _group=_g)

VALUES = {n: f["value"] for n, f in FACTS.items()}


def ksy_path(path):
    """Resolve `a/b/3/c` through the parsed reac.ksy. Ints index lists."""
    node = KSY
    for part in path.split("/"):
        if isinstance(node, list):
            node = node[int(part)]
        else:
            node = node[part]
    return node


# --------------------------------------------------------------------------
# DIRECT — the facts that name a place in the grammar

DIRECT = [(n, f) for n, f in FACTS.items() if "ksy" in f]


def test_direct_facts_are_not_all_gone():
    """Positive control. A path-resolution bug that silently found nothing
    would leave every check below vacuously green, and this file would report
    PASS on an empty scan. Assert the scan has population before trusting it."""
    assert len(DIRECT) >= 15, f"only {len(DIRECT)} facts carry a ksy: path"


@pytest.mark.parametrize("name,fact", DIRECT, ids=[n for n, _ in DIRECT])
def test_ksy_carries_the_fact(name, fact):
    node = ksy_path(fact["ksy"])
    how = fact.get("ksy_as", "int")
    if how == "int":
        got, want = node, fact["value"] - fact.get("ksy_offset", 0)
    elif how == "bytes_be":
        got = int.from_bytes(bytes(node), "big")
        want = fact["value"]
    elif how == "byte0":
        got, want = node[0], fact["value"]
    elif how == "byte1":
        got, want = node[1], fact["value"]
    elif how == "literal":
        got, want = node, fact["ksy_value"]
    elif how == "substring":
        assert fact["ksy_value"] in str(node), (
            f"{name}: reac.ksy {fact['ksy']} = {node!r} no longer contains "
            f"{fact['ksy_value']!r}")
        return
    else:
        raise AssertionError(f"unknown ksy_as {how}")
    assert got == want, (f"{name}: schema says {want!r}, "
                         f"reac.ksy {fact['ksy']} says {got!r}")


# --------------------------------------------------------------------------
# ENUMS

ENUM_FACTS = []
for _g in SCHEMA["groups"]:
    _ge = _g.get("ksy_enum")
    for _f in _g.get("facts", []):
        _e = _f.get("ksy_enum", _ge)
        if _e and "ksy_name" in _f:
            ENUM_FACTS.append((_f["name"], _e, _f["ksy_name"], _f["value"]))


def test_enum_scan_found_something():
    assert len(ENUM_FACTS) >= 10, f"only {len(ENUM_FACTS)} enum facts scanned"


@pytest.mark.parametrize("name,enum,member,value", ENUM_FACTS,
                         ids=[e[0] for e in ENUM_FACTS])
def test_ksy_enum_member(name, enum, member, value):
    table = KSY["enums"][enum]
    assert value in table, f"{enum} has no member {value:#x} (schema: {name})"
    assert table[value] == member, (
        f"{enum}[{value:#x}] is {table[value]!r}, schema says {member!r}")


# --------------------------------------------------------------------------
# STRUCTURAL — walk scene_body's own field sizes and land on libreac's offsets

def type_size(tname):
    prim = {"u1": 1, "u2": 2, "u2le": 2, "u4": 4, "u4le": 4, "s2le": 2}
    if tname in prim:
        return prim[tname]
    seq = KSY["types"][tname]["seq"]
    return sum(field_size(f) for f in seq)


def field_size(f):
    if "contents" in f:
        n = len(f["contents"])
    elif "size" in f:
        n = f["size"]
        if not isinstance(n, int):
            raise AssertionError(f"non-literal size {n!r} in {f['id']}")
    elif "type" in f and isinstance(f["type"], str):
        n = type_size(f["type"])
    else:
        raise AssertionError(f"cannot size field {f.get('id')}")
    return n * f.get("repeat-expr", 1)


def scene_body_offsets():
    off, out = 0, {}
    for f in KSY["types"]["scene_body"]["seq"]:
        out[f["id"]] = off
        off += field_size(f)
    out["_total"] = off
    return out


SCENE_OFFSETS = scene_body_offsets()
SCENE_FACTS = [(n, f) for n, f in FACTS.items() if "ksy_scene_field" in f]


def test_scene_body_walk_found_the_fields():
    """Positive control before any absence claim: the walk must produce the
    field names the checks below index, or a typo turns into a green run."""
    assert len(SCENE_FACTS) >= 5
    for _, f in SCENE_FACTS:
        assert f["ksy_scene_field"] in SCENE_OFFSETS


def test_scene_body_total_is_the_declared_total():
    """The grammar's field list must add up to the number the header declares.
    This is the one that catches a field silently resized."""
    assert SCENE_OFFSETS["_total"] == VALUES["SCENE_BYTES"], (
        f"reac.ksy scene_body walks to {SCENE_OFFSETS['_total']} bytes, "
        f"the schema declares {VALUES['SCENE_BYTES']}")


@pytest.mark.parametrize("name,fact", SCENE_FACTS, ids=[n for n, _ in SCENE_FACTS])
def test_scene_field_lands_on_the_offset(name, fact):
    got = SCENE_OFFSETS[fact["ksy_scene_field"]]
    assert got == fact["value"], (
        f"{name}: walking reac.ksy's scene_body puts "
        f"`{fact['ksy_scene_field']}` at {got:#05x}; the schema (and libreac) "
        f"index {fact['value']:#05x}")


def test_scene_slot_stride_matches_the_record_type():
    assert type_size("scene_record") == VALUES["SCENE_SLOT_BYTES"]


# --------------------------------------------------------------------------
# ARITHMETIC — the derived facts recompute from their inputs

DERIVED = [(n, f) for n, f in FACTS.items() if "derived" in f]


def test_derived_scan_found_something():
    assert len(DERIVED) >= 5


@pytest.mark.parametrize("name,fact", DERIVED, ids=[n for n, _ in DERIVED])
def test_derived_fact_recomputes(name, fact):
    got = eval(fact["derived"], {"__builtins__": {}}, dict(VALUES))  # noqa: S307
    assert got == fact["value"], (
        f"{name}: schema says {fact['value']}, "
        f"`{fact['derived']}` computes {got}")


def test_the_scene_lengths_sum_to_the_total():
    """Stated on its own because it is the law the whole transfer rests on: the
    lengths each step DECLARES are what must sum to what the header declares."""
    total = (VALUES["SCENE_HEAD_BYTES"]
             + VALUES["SCENE_CHUNKS"] * VALUES["SCENE_CHUNK_BYTES"]
             + VALUES["SCENE_TAIL_BYTES"])
    assert total == VALUES["SCENE_BYTES"]


def test_frame_geometry_law():
    """52 + n*36, for the one width the downstream frame is fixed at."""
    assert (VALUES["FRAME_OVERHEAD"]
            + VALUES["MAX_CHANNELS"] * VALUES["BYTES_PER_CHANNEL"]
            == VALUES["FRAME_BYTES"])
    assert (VALUES["SAMPLES_PER_PKT"] * VALUES["RESOLUTION"]
            == VALUES["BYTES_PER_CHANNEL"])
    assert (VALUES["L2_HEADER_LEN"] + len([VALUES["END_MARKER_0"],
                                           VALUES["END_MARKER_1"]])
            == VALUES["FRAME_OVERHEAD"])


def test_control_block_sits_inside_the_header():
    assert VALUES["CTRL_BLOCK_OFF"] + VALUES["CTRL_BLOCK_LEN"] == VALUES["CTRL_BLOCK_END"]
    assert VALUES["CTRL_BLOCK_END"] == VALUES["AUDIO_OFFSET"]
    assert VALUES["CTRL_CKSUM_OFF"] - VALUES["CTRL_BLOCK_OFF"] == VALUES["CTRL_CKSUM_OFF_IN_BLOCK"]
    assert VALUES["TYPED_BLOCK_OFF"] + VALUES["TYPED_BLOCK_LEN"] == VALUES["CTRL_BLOCK_END"]


def test_head_amp_space_is_not_the_audio_fabric():
    """The conflation that silently dropped a 16-input box's top half."""
    assert VALUES["HEADAMP_CH_SPAN"] == 48
    assert VALUES["HEADAMP_CH_SPAN"] != VALUES["MAX_CHANNELS"]
    placement = next(g for g in SCHEMA["groups"] if g["id"] == "placement")
    for row in placement["rows"]:
        assert row["base"] + row["in_ch"] <= VALUES["HEADAMP_CH_SPAN"], row


def test_phantom_granularity_matches_the_scene_record_stride():
    """Phantom is per four; the scene's twelve-group loop reads every fourth
    record. Both sides of that coincidence live here, so it cannot drift apart
    silently."""
    assert 1 << VALUES["HEADAMP_GRAN_PHANTOM_SHIFT"] == VALUES["PORTS_CH_PER_SLOT"]
    assert VALUES["PORTS_TABLE_SLOTS"] * VALUES["PORTS_CH_PER_SLOT"] == VALUES["HEADAMP_CH_SPAN"]
    assert VALUES["ENROLL_GROUPS"] * 8 == VALUES["MAX_CHANNELS"]


# --------------------------------------------------------------------------
# THE GENERATOR

def test_generated_files_are_current():
    r = subprocess.run([sys.executable, str(HERE / "gen-facts.py"), "--check"],
                       capture_output=True, text=True)
    assert r.returncode == 0, r.stdout + r.stderr


def test_generator_is_idempotent(tmp_path):
    """Generate, generate again, diff. A generator that varies between two runs
    over one input regresses the file it maintains on every regeneration."""
    import shutil
    work = tmp_path / "spec"
    work.mkdir()
    for f in ("gen-facts.py", "protocol-facts.yaml"):
        shutil.copy(HERE / f, work / f)
    first = {}
    for run in range(2):
        r = subprocess.run([sys.executable, str(work / "gen-facts.py")],
                           capture_output=True, text=True)
        assert r.returncode == 0, r.stdout + r.stderr
        out = sorted((work / "generated").iterdir())
        assert out, "the generator wrote nothing"
        if run == 0:
            first = {p.name: p.read_text() for p in out}
        else:
            assert {p.name: p.read_text() for p in out} == first
            assert "unchanged" in r.stdout


def test_generated_header_says_it_is_generated():
    h = (HERE / "generated" / "reac_facts.h").read_text()
    assert "GENERATED FILE - DO NOT EDIT." in h
    assert "protocol-facts.yaml" in h
    assert "gen-facts.py" in h


def test_generated_header_defines_every_fact():
    h = (HERE / "generated" / "reac_facts.h").read_text()
    missing = [n for n in FACTS if f"#define REAC_{n} " not in h
               and f"#define REAC_{n:<26} " not in h]
    assert not missing, missing


def test_every_fact_carries_provenance():
    """A row with no evidence line is a number somebody remembered."""
    for name, f in FACTS.items():
        assert f.get("why"), name
        assert f.get("evidence"), name
