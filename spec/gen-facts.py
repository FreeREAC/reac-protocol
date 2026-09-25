#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Pau Aliagas <linuxnow@gmail.com>
"""Generate the shared REAC constants from spec/protocol-facts.yaml.

Two artefacts describe one protocol and can drift: reac.ksy parses, libreac
builds. This writes the numbers they both spell, from one source:

    generated/reac_facts.h      the #define block, for libreac
    generated/reac_facts.ksy    the same constants as a Kaitai type, importable
    generated/reac_facts_assert.h
                                _Static_asserts binding libreac's own macros
                                to the schema, for the lane that has not
                                adopted the header yet

    ./gen-facts.py              write all three
    ./gen-facts.py --check      fail if any differs from what would be written
    ./gen-facts.py --outdir D   write (or with --check, compare) D instead of
                                generated/
    ./gen-facts.py --perturb SEED --outdir D
                                write a PERTURBED set into D: every free
                                numeric fact moved within its legal range, every
                                derived fact recomputed from the moved inputs,
                                every law in `meta: perturb_laws` still holding.
                                It is NOT the protocol. A consumer that builds
                                and passes its tests against it spells nothing
                                by hand; one that fails has a hardcoded copy of
                                a fact the failure names. Refuses generated/.

DETERMINISTIC BY CONSTRUCTION, and that is a requirement rather than a nicety.
Nothing here reads the clock, the environment, a path outside the repo, or the
current file's own mtime. A generator that varies its output between two runs
over one input regresses the file it maintains on every regeneration, and the
`--check` mode plus `make facts-idempotent` exist to keep that honest: generate,
generate again, diff.
"""
import argparse
import pathlib
import sys

import yaml

HERE = pathlib.Path(__file__).resolve().parent
SCHEMA = HERE / "protocol-facts.yaml"
OUTDIR = HERE / "generated"

BANNER_LINES = [
    "GENERATED FILE - DO NOT EDIT.",
    "",
    "Source:    spec/protocol-facts.yaml   (in FreeREAC/reac-protocol)",
    "Generator: spec/gen-facts.py",
    "",
    "Edit the schema and regenerate. A hand-edit here is erased by the next run",
    "and, worse, is invisible to the cross-check that keeps reac.ksy and libreac",
    "agreeing - which is the whole reason this file is generated.",
]


def fmt_value(value, fmt):
    # A YAML `true`/`false` is a Python bool, and str() spells it `True` - which
    # is not C (`'True' undeclared` at the first use) and not a Kaitai literal.
    # Every target spells it the 1/0 a C #define and a ksy expression both read.
    if isinstance(value, bool):
        return "1" if value else "0"
    if fmt == "hex8":
        return f"0x{value:08x}"
    if fmt == "hex2":
        return f"0x{value:02x}"
    if fmt == "hex3":
        return f"0x{value:03x}"
    if fmt == "hex4":
        return f"0x{value:04x}"
    if fmt == "dec_hex":
        return f"{value}"
    return str(value)


def wrap(text, width, prefix):
    """Deterministic greedy wrap. Blank lines survive as blank lines."""
    out = []
    for para in text.rstrip("\n").split("\n"):
        para = para.rstrip()
        if not para:
            out.append(prefix.rstrip())
            continue
        indent = len(para) - len(para.lstrip())
        pad = " " * indent
        line = ""
        for word in para.split():
            cand = f"{line} {word}" if line else f"{pad}{word}"
            if len(cand) > width and line:
                out.append(f"{prefix}{line}".rstrip())
                line = f"{pad}{word}"
            else:
                line = cand
        out.append(f"{prefix}{line}".rstrip())
    return out


def facts_of(group):
    return group.get("facts", [])


def c_comment(text, width=78):
    """A block comment: `/* ` on the first line, ` * ` after, ` */` to close."""
    lines = wrap(text, width - 3, "")
    if len(lines) == 1:
        return [f"/* {lines[0]} */"]
    out = [f"/* {lines[0]}"]
    out += [f" * {l}".rstrip() for l in lines[1:]]
    out.append(" */")
    return out


def emit_h(schema):
    meta = schema["meta"]
    L = ["// SPDX-License-Identifier: GPL-3.0-or-later",
         "// Copyright (C) 2026 Pau Aliagas <linuxnow@gmail.com>",
         "//"]
    L += [f"// {b}".rstrip() for b in BANNER_LINES]
    L += ["",
          f"#ifndef {meta['guard']}",
          f"#define {meta['guard']}",
          ""]

    for group in schema["groups"]:
        rule = "-" * max(3, 74 - len(group["title"]))
        L.append(f"/* ---- {group['title']} {rule}")
        L += wrap(group["doc"], 76, " * ")
        L.append(" */")

        if group.get("kind") == "table":
            cols = group["columns"]
            name = group["id"].upper()
            L.append(f"#define REAC_{name}_ROWS {len(group['rows'])}")
            body = ", ".join(
                "{ " + ", ".join(
                    fmt_value(row[c], "hex2" if c == "base" else "dec") for c in cols
                ) + " }"
                for row in group["rows"])
            L.append(f"/* {{ {', '.join(cols)} }} rows: */")
            L.append(f"#define REAC_{name}_TABLE {{ {body} }}")
            for row in group["rows"]:
                L += c_comment(f"{row[cols[0]]} -> {fmt_value(row[cols[1]], 'hex2')}: "
                               f"{row['why']}  [{row['evidence']}]")
            L.append("")
            continue

        for fact in facts_of(group):
            L += c_comment(f"{fact['why']}  [{fact['evidence']}]")
            val = fmt_value(fact["value"], fact.get("fmt", "dec"))
            if fact.get("fmt") == "dec_hex":
                val = f"{fact['value']}   /* 0x{fact['value']:04x} */"
            L.append(f"#define REAC_{fact['name']:<26} {val}")
            L.append("")
    L.append(f"#endif /* {meta['guard']} */")
    return "\n".join(L) + "\n"


def ksy_const(name, value, doc):
    return [f"  {name}:",
            f"    value: {value}",
            "    doc: |"] + wrap(doc, 70, "      ")


def emit_ksy(schema):
    meta = schema["meta"]
    L = [f"# {b}".rstrip() for b in BANNER_LINES]
    L += ["",
          "# The same constants reac.ksy's grammar and libreac's headers spell, as a",
          "# standalone Kaitai type. It parses nothing: every constant is a value-only",
          "# instance, so `meta: imports: [reac_facts]` makes them available by name",
          "# without changing a byte of any grammar that imports it.",
          "meta:",
          f"  id: {meta['ksy_id']}",
          f"  title: {meta['ksy_title']}",
          "  license: GPL-3.0-or-later",
          "  endian: be",
          "seq: []",
          "instances:"]

    for group in schema["groups"]:
        L.append(f"  # ---- {group['title']} ----")
        if group.get("kind") == "table":
            cols = group["columns"]
            for row in group["rows"]:
                L += ksy_const(f"{group['id']}_base_in{row[cols[0]]}",
                               fmt_value(row[cols[1]], "hex2"),
                               f"{row['why']}  [{row['evidence']}]")
            continue
        for fact in facts_of(group):
            L += ksy_const(fact["name"].lower(),
                           fmt_value(fact["value"], fact.get("fmt", "dec")),
                           f"{fact['why']}  [{fact['evidence']}]")
    return "\n".join(L) + "\n"



def emit_assert_h(schema):
    """A translation unit's worth of _Static_assert: every schema row that
    libreac ALSO spells, checked against libreac's own macro at compile time.

    This is the cheap half of the convergence, and it is the half that works
    before anybody adopts anything. libreac keeps its hand-written #defines;
    this header includes them and refuses to compile if one has drifted from
    the schema, naming the constant in the error. Once the generated header is
    adopted the assertions become tautologies and can go — until then they are
    the only thing standing between the two spellings."""
    L = ["// SPDX-License-Identifier: GPL-3.0-or-later",
         "// Copyright (C) 2026 Pau Aliagas <linuxnow@gmail.com>",
         "//"]
    L += [f"// {b}".rstrip() for b in BANNER_LINES]
    L += ["//",
          "// Compile this against libreac's headers. Every assertion that fails names",
          "// a constant the two expressions of the protocol no longer agree on.",
          "",
          "#ifndef REAC_FACTS_ASSERT_H",
          "#define REAC_FACTS_ASSERT_H",
          "",
          "#include <reac/reac.h>",
          "#include <reac/reac_ctrlblk.h>",
          "#include <reac/reac_ports.h>",
          ""]
    rows = [(f, g) for g in schema["groups"] for f in facts_of(g) if "libreac" in f]
    for fact, group in rows:
        # A YAML `true`/`false` reaches here as a Python bool, and str() spells it
        # `True` — which is not C and fails to compile with `'True' undeclared`, an
        # error naming nothing a reader would connect to the schema. C has no bool
        # literal in a _Static_assert either, so render it as the 1/0 libreac's own
        # #define spells. Handled HERE rather than by asking every author to
        # remember `value: 1`: a rule nobody can forget beats a rule in a comment.
        if isinstance(fact["value"], bool):
            val = "1" if fact["value"] else "0"
        else:
            val = fmt_value(fact["value"], fact.get("fmt", "dec"))
            if fact.get("fmt") == "dec_hex":
                val = str(fact["value"])
        L.append(f'_Static_assert({fact["libreac"]} == {val},')
        L.append(f'               "{fact["libreac"]} has drifted from '
                 f'protocol-facts.yaml {fact["name"]}");')
    L += ["",
          f"#define REAC_FACTS_ASSERTIONS {len(rows)}",
          "",
          "#endif /* REAC_FACTS_ASSERT_H */"]
    return "\n".join(L) + "\n"


TARGETS = {"reac_facts.h": emit_h,
           "reac_facts.ksy": emit_ksy,
           "reac_facts_assert.h": emit_assert_h}


# ---- perturbation ---------------------------------------------------------
#
# A consumer that spells a fact by hand agrees with this schema by accident of
# the value, and no test run against the real value can tell the difference:
# `36` and `REAC_BYTES_PER_CHANNEL` read the same until one of them moves. So
# move it. `--perturb SEED` writes the same three targets with every free
# numeric fact shifted, deterministically from SEED, within its legal range,
# and every `derived:` fact recomputed from the shifted inputs. Build a consumer
# against that and every hand copy disagrees with the header it included:
# reac_facts_assert.h fails to compile naming each libreac macro that is a
# copy, and a consumer's own tests fail wherever a literal restates a fact.
#
# "Legal" is what keeps the perturbed set a consistent (if fictional) protocol
# rather than noise, so a failure means a copy and not a contradiction:
#   * a fact's own range: `perturb: [lo, hi]`, else the width its `fmt` gives
#     (hex2 a byte, hex4 a u16, ...), else +-max(2, |v|/4) never below zero;
#   * `perturb: false` pins a fact whose value is a switch, not a quantity;
#   * booleans (rulings) are not quantities and are never moved;
#   * every `derived:` expression holds, and evaluates to an integer;
#   * enum members (one `kind: enum` group, or one `ksy_enum`) stay distinct;
#   * every expression in `meta: perturb_laws` holds;
#   * a table group's `perturb_row_law` holds on every row.
# A draw that breaks any of it is redrawn under the next attempt number, so the
# output is still a pure function of (schema, SEED).

FMT_RANGE = {"hex2": (0, 0xFF), "hex3": (0, 0xFFF), "hex4": (0, 0xFFFF),
             "hex8": (0, 0xFFFFFFFF)}
MAX_ATTEMPTS = 20000

PERTURB_BANNER = [
    "",
    "PERTURBED (seed {seed}) - THIS IS NOT THE REAC PROTOCOL.",
    "Every free numeric fact is moved within its legal range and every derived",
    "fact recomputed, so a consumer built against this header that still",
    "passes spells no fact by hand. perturbation.json beside it maps each",
    "fact to its real and its perturbed value. Never install or ship it.",
]


def _draw(seed, attempt, key, lo, hi):
    import hashlib
    h = hashlib.sha256(f"{seed}:{attempt}:{key}".encode()).digest()
    return lo + int.from_bytes(h[:8], "big") % (hi - lo + 1)


def _range(fact):
    v, pr = fact["value"], fact.get("perturb")
    if isinstance(pr, list):
        return tuple(pr)
    if fact.get("fmt") in FMT_RANGE:
        return FMT_RANGE[fact["fmt"]]
    d = max(2, abs(v) // 4)
    return (max(0, v - d) if v >= 0 else v - d, v + d)


def is_free(fact):
    return (not isinstance(fact["value"], bool)
            and isinstance(fact["value"], int)
            and fact.get("perturb", True) is not False
            and "derived" not in fact)


def _eval(expr, env):
    return eval(expr, {"__builtins__": {}}, dict(env))  # noqa: S307


NAME = __import__("re").compile(r"\b[A-Z][A-Z0-9_]*\b")


def resolve_derived(facts, values):
    """Fill every derived fact from the others, in whatever order the
    expressions allow. Returns the names whose result is not an integer."""
    todo = [f for f in facts if "derived" in f]
    for f in todo:          # a stale derived value must not feed another
        values.pop(f["name"], None)
    bad = []
    while todo:
        progressed = False
        for f in list(todo):
            try:
                got = _eval(f["derived"], values)
            except NameError:
                continue
            if got != int(got):
                bad.append(f["name"])
            values[f["name"]] = int(got)
            todo.remove(f)
            progressed = True
        if not progressed:
            raise SystemExit("derived facts form a cycle or name an unknown "
                             "fact: " + ", ".join(f["name"] for f in todo))
    return bad


def broken(schema, facts, values):
    """Every fact implicated in a broken law, a non-integer derivation, an
    out-of-width value or an enum collision. Empty means legal."""
    out = set(resolve_derived(facts, values))
    for f in facts:
        lo, hi = FMT_RANGE.get(f.get("fmt"), (None, None))
        if (lo is not None and not isinstance(f["value"], bool)
                and not lo <= values[f["name"]] <= hi):
            out.add(f["name"])
    enums = {}
    for g in schema["groups"]:
        for f in facts_of(g):
            key = f.get("ksy_enum", g.get("ksy_enum") or
                        (g["id"] if g.get("kind") == "enum" else None))
            if key:
                enums.setdefault(key, []).append(f["name"])
    for names in enums.values():
        vals = [values[n] for n in names]
        out |= {n for n in names if vals.count(values[n]) > 1}
    for law in schema["meta"].get("perturb_laws", []):
        if not _eval(law, values):
            out |= set(NAME.findall(law)) & values.keys()
    return out


def free_inputs(name, by_name, seen=None):
    """The free facts a (possibly derived) fact is computed from."""
    f = by_name[name]
    if "derived" not in f:
        return {name} if is_free(f) else set()
    seen = seen if seen is not None else set()
    if name in seen:
        return set()
    seen.add(name)
    out = set()
    for dep in set(NAME.findall(f["derived"])) & by_name.keys():
        out |= free_inputs(dep, by_name, seen)
    return out


def perturb(schema, seed):
    """Return (perturbed schema, manifest). Pure function of (schema, seed).

    Every free fact is drawn once; then, while anything is illegal, only the
    free inputs of what broke are redrawn, each under its own counter. A local
    repair converges where redrawing the whole set would almost never land on
    a draw that satisfies every law at once."""
    import copy
    facts = [f for g in schema["groups"] for f in facts_of(g)]
    by_name = {f["name"]: f for f in facts}
    real = {f["name"]: f["value"] for f in facts}
    draws = {}

    def draw(f):
        lo, hi = _range(f)
        k = draws[f["name"]] = draws.get(f["name"], -1) + 1
        v = _draw(seed, k, f["name"], lo, hi)
        if v == f["value"]:
            v = lo + (v - lo + 1) % (hi - lo + 1)
        return v

    values = dict(real)
    for f in facts:
        if is_free(f):
            values[f["name"]] = draw(f)
    for attempt in range(MAX_ATTEMPTS):
        bad = broken(schema, facts, values)
        if not bad:
            break
        redo = set()
        for n in bad:
            redo |= free_inputs(n, by_name)
        for n in sorted(redo):
            values[n] = draw(by_name[n])
    else:
        raise SystemExit(f"no legal perturbation for seed {seed} in "
                         f"{MAX_ATTEMPTS} repairs - a law is unsatisfiable")

    out = copy.deepcopy(schema)
    manifest = {"seed": seed, "attempt": attempt, "facts": {}, "tables": {}}
    for g in out["groups"]:
        for f in facts_of(g):
            if values[f["name"]] != f["value"]:
                manifest["facts"][f["name"]] = [f["value"], values[f["name"]]]
            f["value"] = values[f["name"]]
        if g.get("kind") == "table":
            law = g.get("perturb_row_law", "True")
            for i, row in enumerate(g["rows"]):
                orig = dict(row)
                for a in range(MAX_ATTEMPTS):
                    for c in g["columns"]:
                        lo, hi = _range({"value": orig[c]})
                        row[c] = _draw(seed, a, f"{g['id']}/{i}/{c}", lo, hi)
                        if row[c] == orig[c]:
                            row[c] = lo + (row[c] - lo + 1) % (hi - lo + 1)
                    if _eval(law, dict(values, **row)):
                        break
                else:
                    raise SystemExit(f"no legal perturbation of {g['id']} row {i}")
                keys = [r[g["columns"][0]] for r in g["rows"][:i + 1]]
                if len(keys) != len(set(keys)):
                    raise SystemExit(f"{g['id']}: perturbed keys collide, "
                                     f"try another seed")
                manifest["tables"][f"{g['id']}/{i}"] = [
                    [orig[c] for c in g["columns"]], [row[c] for c in g["columns"]]]
    return out, manifest


def main():
    global BANNER_LINES
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true",
                    help="do not write; exit 1 if any target differs")
    ap.add_argument("--outdir", type=pathlib.Path, default=OUTDIR,
                    help="directory to write (or --check) instead of generated/")
    ap.add_argument("--perturb", type=int, metavar="SEED",
                    help="write a perturbed set (requires --outdir elsewhere)")
    args = ap.parse_args()

    schema = yaml.safe_load(SCHEMA.read_text())
    outdir = args.outdir.resolve()
    extra = {}
    if args.perturb is not None:
        if args.check or outdir == OUTDIR.resolve():
            ap.error("--perturb writes a fictional protocol; give it an "
                     "--outdir that is not generated/, and no --check")
        schema, manifest = perturb(schema, args.perturb)
        BANNER_LINES = BANNER_LINES + [l.format(seed=args.perturb)
                                       for l in PERTURB_BANNER]
        import json
        extra["perturbation.json"] = json.dumps(manifest, indent=1,
                                                sort_keys=True) + "\n"

    outdir.mkdir(parents=True, exist_ok=True)
    stale = []
    want_all = {name: fn(schema) for name, fn in sorted(TARGETS.items())}
    want_all.update(extra)
    for name, want in sorted(want_all.items()):
        path = outdir / name
        have = path.read_text() if path.is_file() else None
        if args.check:
            if have != want:
                stale.append(name)
            continue
        if have != want:
            path.write_text(want)
            print(f"wrote {path}")
        else:
            print(f"unchanged {path}")
    if args.check:
        if stale:
            print("STALE, regenerate with ./gen-facts.py: " + ", ".join(stale),
                  file=sys.stderr)
            return 1
        print(f"{args.outdir} is current ({len(TARGETS)} targets)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
