# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Pau Aliagas <linuxnow@gmail.com>
"""GENERATED-IS-FRESH: spec/generated/ is exactly what the schema generates.

protocol-facts.yaml is the one declaration of every REAC number and
spec/generated/ is what consumers include. A tracked output that has fallen
behind the schema (someone edited the YAML and did not regenerate) or run ahead
of it (someone hand-edited a generated value) is a second declaration, and the
consumers would build against it without anything noticing. So:

  * FRESH — regenerate from the tracked schema into a scratch directory and
    require every target to be BYTE-IDENTICAL to the tracked file, and the
    tracked directory to hold nothing the generator does not write.
  * POSITIVE CONTROL — the comparison has to be able to say "equal": a copy of
    the tracked outputs passes `--check`, so a green run is not an empty scan.
  * SABOTAGE CONTROLS — it has to be able to say "different": a hand-edited
    generated value goes red, and so does a schema moved without regenerating.

And the PERTURBATION mode the consumers build against (see gen-facts.py and
docs/audits/2026-09-25-contract-copies.md) is held to its own contract here:
deterministic per seed, every free number moved, every derived fact and every
law still holding, and never written over generated/.
"""
import json
import pathlib
import re
import shutil
import subprocess
import sys

import pytest
import yaml

HERE = pathlib.Path(__file__).resolve().parent
GEN = HERE / "gen-facts.py"
SCHEMA = HERE / "protocol-facts.yaml"
TRACKED = HERE / "generated"
TARGETS = ["reac_facts.h", "reac_facts.ksy", "reac_facts_assert.h"]


def run(*args, cwd=HERE):
    return subprocess.run([sys.executable, str(cwd / "gen-facts.py"), *args],
                          cwd=cwd, capture_output=True, text=True)


def facts_of(schema):
    return [f for g in schema["groups"] for f in g.get("facts", [])]


# ---- fresh -----------------------------------------------------------------

def test_regenerating_is_byte_identical_to_the_tracked_outputs(tmp_path):
    r = run("--outdir", str(tmp_path))
    assert r.returncode == 0, r.stderr
    for name in TARGETS:
        fresh = (tmp_path / name).read_bytes()
        tracked = (TRACKED / name).read_bytes()
        assert fresh == tracked, (
            f"spec/generated/{name} is not what protocol-facts.yaml generates; "
            f"run `make -C spec facts` and commit the result")


def test_tracked_directory_holds_only_generated_targets():
    assert sorted(p.name for p in TRACKED.iterdir()) == sorted(TARGETS)


def test_every_tracked_output_says_it_is_generated():
    for name in TARGETS:
        head = "\n".join((TRACKED / name).read_text().splitlines()[:6])
        assert "GENERATED FILE - DO NOT EDIT." in head, name
        assert "PERTURBED" not in (TRACKED / name).read_text(), (
            f"{name}: a perturbed set was committed as the protocol")


# ---- controls --------------------------------------------------------------

def test_positive_control_a_faithful_copy_passes(tmp_path):
    for name in TARGETS:
        shutil.copy(TRACKED / name, tmp_path / name)
    r = run("--check", "--outdir", str(tmp_path))
    assert r.returncode == 0, r.stderr


def test_sabotage_a_hand_edited_generated_value_goes_red(tmp_path):
    for name in TARGETS:
        shutil.copy(TRACKED / name, tmp_path / name)
    h = tmp_path / "reac_facts.h"
    text = h.read_text()
    edited = re.sub(r"(#define REAC_ETHERTYPE\s+)0x8819", r"\g<1>0x8818", text)
    assert edited != text, "sabotage found nothing to edit"
    h.write_text(edited)
    r = run("--check", "--outdir", str(tmp_path))
    assert r.returncode == 1
    assert "reac_facts.h" in r.stderr


def test_sabotage_a_schema_moved_without_regenerating_goes_red(tmp_path):
    shutil.copy(GEN, tmp_path / "gen-facts.py")
    shutil.copytree(TRACKED, tmp_path / "generated")
    text = SCHEMA.read_text()
    moved = re.sub(r"(- name: SCENE_TAIL_BYTES\n(?:        .*\n)*?        value: )14",
                   r"\g<1>15", text)
    assert moved != text, "sabotage found nothing to move"
    (tmp_path / "protocol-facts.yaml").write_text(moved)
    r = run("--check", cwd=tmp_path)
    assert r.returncode == 1
    assert "reac_facts.h" in r.stderr and "reac_facts_assert.h" in r.stderr


# ---- perturbation ------------------------------------------------------------

SEEDS = [1, 2, 3, 20260925]


def perturbed(tmp_path, seed):
    out = tmp_path / f"p{seed}"
    r = run("--perturb", str(seed), "--outdir", str(out))
    assert r.returncode == 0, r.stderr
    return out, json.loads((out / "perturbation.json").read_text())


def macros(text):
    return {m.group(1): m.group(2) for m in
            re.finditer(r"^#define (REAC_\w+)\s+(\S+)", text, re.M)}


def test_perturbation_refuses_to_write_the_tracked_directory():
    r = run("--perturb", "1", "--outdir", str(TRACKED))
    assert r.returncode != 0
    r = run("--perturb", "1")
    assert r.returncode != 0


@pytest.mark.parametrize("seed", SEEDS)
def test_perturbation_is_deterministic(tmp_path, seed):
    a, _ = perturbed(tmp_path / "a", seed)
    b, _ = perturbed(tmp_path / "b", seed)
    for name in TARGETS + ["perturbation.json"]:
        assert (a / name).read_bytes() == (b / name).read_bytes(), name


@pytest.mark.parametrize("seed", SEEDS)
def test_perturbation_moves_every_free_number(tmp_path, seed):
    schema = yaml.safe_load(SCHEMA.read_text())
    out, manifest = perturbed(tmp_path, seed)
    free = [f["name"] for f in facts_of(schema)
            if isinstance(f["value"], int) and not isinstance(f["value"], bool)
            and f.get("perturb", True) is not False and "derived" not in f]
    assert len(free) >= 60, f"only {len(free)} free facts - scan is broken"
    unmoved = [n for n in free if n not in manifest["facts"]]
    assert not unmoved, f"perturbation left {unmoved} at their real values"
    # and the header actually carries the moved values
    got = macros((out / "reac_facts.h").read_text())
    for name, (real, moved) in manifest["facts"].items():
        assert got[f"REAC_{name}"] != str(real) or real == moved


@pytest.mark.parametrize("seed", SEEDS)
def test_perturbation_keeps_every_derived_fact_and_law(tmp_path, seed):
    schema = yaml.safe_load(SCHEMA.read_text())
    _, manifest = perturbed(tmp_path, seed)
    values = {f["name"]: f["value"] for f in facts_of(schema)}
    values.update({n: v[1] for n, v in manifest["facts"].items()})
    env = {"__builtins__": {}}
    for f in facts_of(schema):
        if "derived" in f:
            assert eval(f["derived"], env, dict(values)) == values[f["name"]], f["name"]  # noqa: S307
    for law in schema["meta"].get("perturb_laws", []):
        assert eval(law, env, dict(values)), law  # noqa: S307
    # booleans are rulings, not quantities: never moved
    for f in facts_of(schema):
        if isinstance(f["value"], bool) or f.get("perturb") is False:
            assert f["name"] not in manifest["facts"], f["name"]


def test_perturbed_assert_header_names_every_libreac_binding(tmp_path):
    """The assert header is the consumer-side detector: compiled against a
    perturbed set, every libreac macro that is a hand copy fails its assertion.
    That only works if the perturbed values reach it."""
    schema = yaml.safe_load(SCHEMA.read_text())
    out, manifest = perturbed(tmp_path, 1)
    text = (out / "reac_facts_assert.h").read_text()
    for f in facts_of(schema):
        if "libreac" in f and f["name"] in manifest["facts"]:
            real, moved = manifest["facts"][f["name"]]
            assert re.search(rf"_Static_assert\({f['libreac']} == (0x0*{moved:x}|{moved}),",
                             text), f["name"]


def test_real_values_satisfy_the_perturbation_laws():
    """The laws are protocol facts too: they must hold on the real values,
    or the perturbation is enforcing a relation the protocol does not have."""
    schema = yaml.safe_load(SCHEMA.read_text())
    values = {f["name"]: f["value"] for f in facts_of(schema)}
    for law in schema["meta"]["perturb_laws"]:
        assert eval(law, {"__builtins__": {}}, dict(values)), law  # noqa: S307
