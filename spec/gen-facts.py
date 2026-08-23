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

    ./gen-facts.py              write both
    ./gen-facts.py --check      fail if either differs from what would be written

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


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true",
                    help="do not write; exit 1 if any target differs")
    args = ap.parse_args()

    schema = yaml.safe_load(SCHEMA.read_text())
    OUTDIR.mkdir(exist_ok=True)
    stale = []
    for name, fn in sorted(TARGETS.items()):
        want = fn(schema)
        path = OUTDIR / name
        have = path.read_text() if path.is_file() else None
        if args.check:
            if have != want:
                stale.append(name)
            continue
        if have != want:
            path.write_text(want)
            print(f"wrote {path.relative_to(HERE)}")
        else:
            print(f"unchanged {path.relative_to(HERE)}")
    if args.check:
        if stale:
            print("STALE, regenerate with ./gen-facts.py: " + ", ".join(stale),
                  file=sys.stderr)
            return 1
        print(f"generated/ is current ({len(TARGETS)} targets)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
