# The REAC spec — three parties and why

`reac.ksy` is the **formal, machine-checkable** layout of the REAC `0x8819` frame
family: the L2 envelope, the control multiplex at its fixed offsets, the `op 04 03`
Roland DT1 record container with its tag dispatch, the two nested checksums, and the
audio region described structurally. The prose in [`../wire-format.md`](../wire-format.md)
is the readable rendering of the same facts; this file is the one a machine can check.

## Roles — the decision, and the reasoning

There are three artefacts describing one wire format, and they are deliberately not
peers:

| artefact | role | authority |
|---|---|---|
| **libreac** (`FreeREAC/libreac`) | the **executable C oracle** — the layout as running code: `reac_braid_pos()`, `reac_frame_clean_len()`, `reac_upstream_channels()`, the frame constants | what the tools actually do |
| **`reac.ksy`** (this repo) | the **formal spec** — the layout as a declarative grammar, with the evidence trail in its `doc:` blocks | what the protocol *is* |
| the **generated parser** | the **referee** — ksc turns the spec into a parser, [`reac_xcheck.py`](reac_xcheck.py) runs it over the checked-in goldens and asserts field-for-field agreement with the oracle | catches drift between the two |

Drift between a spec and its implementation is normally invisible until something
breaks in the field. Here it is a red test.

### Why there is no C target

Kaitai has **no pure-C backend** — its C-family target is `cpp_stl` (C++ with the
STL). More to the point, **libreac already is the C parser**, and it is the single
layout oracle by design: the braid byte map, the `+2` handling and the s24/float pair
each exist exactly once, in one header, because they were previously duplicated across
three files and drifted. Generating a second C(++) decoder from the spec and shipping
it would recreate precisely the duplication that consolidation removed.

So: **Python is the generated target.** It fits where the referee has to run — test
time, capture analysis, `reac-tools` — and it is not on any real-time path. `make cpp`
proves the C-family target still *generates* (a grammar that only compiles to one
language is usually a grammar with a mistake in it), but that output is never
committed, never linked and never shipped.

## Running the cross-check

```sh
make -C spec check
```

That regenerates `reac.py` from `reac.ksy` and runs the harness. Prerequisites:

```sh
pip install kaitaistruct pytest
# ksc is not packaged by any distro; the zip needs a JRE at BUILD time only
curl -fsSLO https://github.com/kaitai-io/kaitai_struct_compiler/releases/download/0.11/kaitai-struct-compiler-0.11.zip
unzip -q kaitai-struct-compiler-0.11.zip
export PATH="$PWD/kaitai-struct-compiler-0.11/bin:$PATH"
```

The generated parser is **not committed** — a checked-in parser goes stale, and a
stale parser is the exact failure this arrangement exists to catch. CI regenerates it
on every change to `spec/**`.

## What the harness asserts

Everything it reads is committed beside it: no network, no capture files, no rig.

- **frame geometry** — `clean_len` and the `+2` rule in both directions, and the
  channel width derived from the frame size (REAC carries no width field in an audio
  frame);
- **the braid** — the audio region decoded through the spec's pair-group structure
  must reproduce, sample for sample, the planar s24 tables libreac's own
  `tests/test_upstream.c` asserts. The permutation itself is documented in the spec
  and validated here rather than expressed in Kaitai, which has no byte-permutation
  primitive;
- **frame-kind classification** — against a transcription of `reac_ctrl_parse()`'s
  decisions, its two known quirks included;
- **control-op dispatch** — including the `op 0103` sub-page multiplex
  (chanmap `0019` / config-announce `0010` / enroll group map `000d` / heartbeat `0001`);
- **head-amp records** — the 56-frame M-200i → S-1608 enrolment sweep decoded to
  48 `(CH, PARAM, VALUE)` triples, compared against the table the C grant tests pin;
- **both checksums** — the outer 32-byte block summing to `0` and the inner Roland
  DT1 record summing to `0x80`, on every fixture;
- **the placement carriers** — declared width, config selector, `unit_offset`,
  the cfea width byte and the enroll group map — *as carriers*, never as a base
  (see below).

### Direct comparison against the C oracle

The committed harness compares against the numbers the C tests are held to, which
keeps it hermetic. To diff against the compiled oracle itself, build libreac and
decode the same fixtures through `reac_upstream_decode()` / `reac_frame_clean_len()` /
`reac_upstream_channels()`; scalars and every PCM sample must match. That comparison
was run when this spec landed: 4 frames, 1056 samples, agreement on every field.

## Fixtures

`fixtures/upstream.json` — real MAC-sanitized rig captures with their PCM truth
tables, the same arrays libreac pins (`UP8` 340 B / `UP16` 628 B / `UP32A`, `UP32B`
1206 B with the OHRCA trailer).

`fixtures/control.json` — 43 control blocks stored as `frame[16:50]` windows (the type
word plus the checksummed block, which is the form the C goldens use), plus the full
56-frame grant sweep and its decoded cell table. Covers cfea for three consoles across
three link states, chanmap windows, all ten probe rotations, sub01/sub02, the enroll
group map, and the config-announce and cold-connect inventory for the S-0808, S-1608
and S-4000S.

MAC addresses in both files are **synthetic stand-ins in the Roland OUI**, never
captured console or box addresses — the cfea blocks carry a per-console stand-in at
index 11..16 with the block checksum re-stamped, and the upstream frames carry the
sanitized pair the capture corpus uses. Every other byte is as captured.

To refresh them, re-extract the C arrays from the sibling checkouts — libreac's
`tests/upstream_fixtures.inc` and reac-pw's `tests/reac_{m200,grant,conformance}_golden.inc`,
`tests/test_reac_master.c`, `src/reac_master.c` and `src/reac_ctrl.c` — rather than
editing the JSON by hand. Each array is `frame[16:50]`, so index *i* is frame offset
*16+i*.

## Scope — what the spec does not cover

**Slot placement is not in the grammar, on purpose.** Why an S-1608 is addressed at
`0x20` while an S-0808 and an S-4000S are both at `0x00` is *negotiated session state*
— no byte in any frame carries the base. A corpus study over 42 establishments, three
consoles and four units killed every testable candidate law and left three carriers
that are perfectly collinear across every row, so promoting any one of them to "the
law" would be picking one of three indistinguishable hypotheses and calling it
knowledge. The grammar therefore parses the **carriers** as typed fields and says so
in the `doc:`; the base stays out. See `PLACEMENT-EVIDENCE.md` in the reac-pw docs for
the corpus, the dead candidates, and the five-run experiment that would settle it.

Also deliberately absent: the establishment FSM and the probe rotation law (both are
*sequences* of frames, not layouts), and the byte permutation inside the audio region
(documented, and validated by cross-check).

## Analysing a capture

Drop `reac.ksy` into the Kaitai Web IDE (`ide.kaitai.io`) to overlay the field map on a
hex dump, or script the generated Python parser across a `.pcap` to flag any frame the
spec cannot parse — a new tag, an unmodelled op, a wrapper variant.
