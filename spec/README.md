# The REAC spec — three parties and why

`reac.ksy` is the **formal, machine-checkable** layout of the REAC `0x8819` frame
family: the L2 envelope, the control multiplex at its fixed offsets, the `op 04 03`
Roland DT1 record container with its tag dispatch, the two nested checksums, and the
audio region described structurally. The prose in [`../wire-format.md`](../wire-format.md)
is the readable rendering of the same facts; this file is the one a machine can check.

**One grammar, not one per plane.** `reac.ksy` is the whole frame family — audio and
control, both directions, the scene transfer, the chanmap and the config announce. There is
deliberately no separate control-only grammar: the control ops are reached by dispatch from
the same envelope (`typed_block` → `control_block` → the op types), and splitting them into a
second file gives two envelopes to keep in step and a second place for a constant to drift.
That is the defect [`protocol-facts.yaml`](protocol-facts.yaml) exists to close, so
reintroducing it in the grammar itself would be moving backwards.

## Roles — the decision, and the reasoning

There are three artefacts describing one wire format, and they are deliberately not
peers:

| artefact | role | authority |
|---|---|---|
| **libreac** (`FreeREAC/libreac`) | the **executable C oracle** — the layout as running code: `reac_braid_pos()`, `reac_frame_clean_len()`, `reac_upstream_channels()`, the frame constants | what the tools actually do |
| **`reac.ksy`** (this repo) | the **formal spec** — the layout as a declarative grammar, with the evidence trail in its `doc:` blocks | what the protocol *is* |
| the **generated parser** | the **referee** — ksc turns the spec into a parser; [`reac_xcheck.py`](reac_xcheck.py) runs it over the checked-in goldens (hermetic), and [`xcheck_c_oracle.py`](xcheck_c_oracle.py) runs it against the compiled libreac (dev-only) | catches drift between the two |

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

## One source for the facts both sides spell

`reac.ksy` and libreac each wrote out the frame geometry, the scene sizes, the validated
tag offsets, the checksum rules, the op codes and the head-amp granularities
independently, and nothing noticed a constant changed in one and not the other.
[`protocol-facts.yaml`](protocol-facts.yaml) holds them once — 90 rows, each with what
the number is and how it was evidenced — and [`gen-facts.py`](gen-facts.py) writes three
artefacts from it into [`generated/`](generated/):

| file | for |
|---|---|
| `reac_facts.h` | libreac, in place of the hand-written `#define` block in `reac_ctrlblk.h` |
| `reac_facts.ksy` | a standalone Kaitai type, `meta: imports: [reac_facts]` |
| `reac_facts_assert.h` | the lane that has not adopted the header yet: `_Static_assert`s binding libreac's own macros to the schema, compiled against libreac's headers |

Every generated file says it is generated on its first lines. The generator reads nothing
but the schema — no clock, no environment, no path outside the repo — because a generator
that varies between two runs over one input regresses the file it maintains on every
regeneration. `make facts-idempotent` generates twice into a scratch tree and diffs.

Kaitai cannot close this on its own: it has no plain-C backend and it emits parsers rather
than serialisers. So the convergence is not "compile the ksy into libreac" — it is this
file plus the cross-parse below.

### The corpus is a regression suite, not a demonstration

[`corpus-check.py`](corpus-check.py) parses **every capture** in the FreeREAC corpus with the
grammar and refuses a regression against [`corpus-baseline.json`](corpus-baseline.json).

```
make corpus-check CAPTURES=~/Devel/audio/reac-captures
make corpus-selftest CAPTURES=~/Devel/audio/reac-captures
```

The unit suite and the corpus are DIFFERENT EVIDENCE. The unit suite runs on the checked-in
goldens, so it stays green while a grammar edit quietly stops parsing a capture we used to
handle — which is the easiest defect here to ship, because the new fields all read correctly on
the frames you were looking at. The baseline records per-file counts (the corpus itself is
private), so `ok` going down or `failed` going up in any single file exits non-zero, and a file
that starts parsing is reported in the other direction.

Two things the checker had to learn, both of which had already produced a wrong answer:

- **A snaplen-truncated record is not a short frame.** Several captures were taken at snaplen
  64/128/200/400, and a truncated frame's length can land on `52 + 36n` by coincidence, reach the
  parser and fail the end marker — 3200 "grammar failures" that were nothing of the kind. Every
  pcap record carries `caplen` and `origlen`; compare them.
- **Discarding those records silently is the other half of the same trap.** SEVEN of the 72
  captures are truncated in every record, so a whole-frame-only check reads zero frames from them
  and still calls the corpus clean. A snaplen of 50 or more carries the ENTIRE control block, so
  those records are parsed as a bare `frame[16:50]` typed_block and counted separately. That turns
  seven silent files into live coverage and adds 44 400 control blocks from records that were
  being thrown away.

`--self-test` corrupts every frame and requires the run to go red, because a checker that cannot
fail reports success over any grammar at all.

### The ratchet

[`facts_xcheck.py`](facts_xcheck.py) runs inside `make check` and asserts `reac.ksy` still
carries every value. It resolves a PATH into the parsed grammar rather than matching prose,
so a field that moves is caught even when the comment beside it still reads correctly. The
scene tag offsets get a stronger check: the grammar never writes `0x368` down, it describes
a sequence of fields that happens to put SYSP there — so the test WALKS `scene_body`'s own
field sizes and requires the walk to land on the offset libreac indexes with, and to add up
to 8904. Sabotage-verified: a chunk resized 26 -> 25, a six-byte reserved run grown to
seven, and an enum member renamed each go red on exactly the rows they should.

## Build it with libreac, read it back with the ksy

```sh
make -C spec check-ctrl-oracle LIBREAC=../../libreac
```

This is the half that catches a MISUNDERSTANDING rather than a typo. Two sides can spell 26
identically and still disagree about what the 26 bytes are, where they start, or which of
them the box validates; the only thing that catches that is making one side emit and the
other read.

[`c_ctrl_dump.c`](c_ctrl_dump.c) links the compiled libreac and builds;
[`xcheck_ctrl_oracle.py`](xcheck_ctrl_oracle.py) parses with the ksy-generated parser and
compares. What runs:

- **the scene round trip** — libreac builds all 343 transfer steps from a body, the parser
  reads every frame, and the body is REASSEMBLED from what the parser found and compared
  byte for byte with the input. Four bodies: the two recovered desk bodies committed in
  `fixtures/`, the tag-only body libreac's own `reac_ctrl_scene_build()` makes, and a body
  GENERATED from the named field layout (`--make-scene PATH`). A chunk at the wrong offset,
  a header declaring the wrong total or a final carrying the wrong tail all come back as a
  byte diff with an offset on it;
- **head-amp records** — every other channel of the 48-slot space, all three parameters,
  read back CH / PARAM / VALUE / tag / both checksums. Plus the ORDERING law: the same
  record with the nested checksums stamped in the wrong order, which the grammar parses
  happily — that is the danger — and libreac's verifier must reject;
- **the reverse**, over every control block in `fixtures/control.json` and the 56-frame
  grant sweep: the parser classifies and decodes, libreac's verifiers judge, and the two
  must agree on every block and every head-amp triple;
- **the constants**, as a translation unit of `_Static_assert`s compiled against libreac's
  own headers.

Two properties it keeps, both of them scars. It fires a **positive control** — a flipped
byte both sides must notice — before it is allowed to print a zero, because a probe that
reports silence has to prove it can hear first. And **INCONCLUSIVE is a verdict**: thin
coverage never reports PASS, and a missing input (no generated body, no corpus) degrades
the verdict rather than vanishing.

It never touches the libreac checkout: libreac is snapshotted with `git archive` and built
in a temp directory, so a lane mid-migration there is neither read half-written nor built
over.

Where the two sides genuinely disagree — and they do — is written down in
[`../convergence-defects.md`](../convergence-defects.md) rather than reconciled silently.

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

- **frame geometry** — `clean_len` and the `+2` rule in both directions, the channel
  width derived from the frame size (REAC carries no width field in an audio frame),
  and that the parser stops at the end marker: a capture's FCS residue is left unread,
  never claimed as a field, and changes no other value;
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

The harness above is hermetic by design: it compares against the numbers the C tests
are held to, plus Python transcriptions of the C contracts. A transcription is a
second reading of the same header, and a reading can be wrong the same way twice —
so there is a second, **dev-only** check that links the real thing:

```sh
make -C spec check-oracle LIBREAC=../../libreac
```

That builds libreac, links [`c_oracle_dump.c`](c_oracle_dump.c) against it, and diffs
the compiler's actual output — `reac_frame_clean_len()`, `reac_upstream_channels()`,
`reac_frame_counter()`, `reac_upstream_decode()`, `reac_downstream_build()`,
`reac_braid_pos()`, `reac_decode()`, `reac_decode_plain_le()` — against the parser ksc
generates from `reac.ksy`. It is out of `make check` and out of CI on purpose: it needs
a libreac checkout and a C toolchain the spec repo does not otherwise depend on, and the
hermetic gate should stay hermetic. It needs **libreac >= 0.5.0**, the release where
`reac_decode()` was fixed to un-braid.

Latest run — 4 upstream goldens plus one downstream frame built by libreac's own
encoder, against libreac 0.5.0:

```
field checks : 54
PCM samples  : 1536
mismatches   : 0
```

The downstream frame is now checked against `reac_decode()` as well as against
`reac_braid_pos()` and the encoder's input, because as of 0.5.0 those are one layout.
The `reac_decode_plain_le()` diagnostic is dumped alongside and reported — 480/480
samples differ from the braid — so the refuted reading stays a measured number rather
than a claim in prose.

## What that agreement proves — and what it does not

`reac.ksy` was written by reading libreac. Agreement between the two is therefore
**internal consistency, not independent confirmation of the wire format**. Both sides
can be wrong together. A green `check-oracle` is not evidence about Roland's protocol.

What it does buy, and this is real:

- the spec is **executable** and matches the running code field for field on every
  golden, so it can be handed to a third party as a parser rather than as prose that
  may or may not have kept up;
- **drift** between spec and implementation is a red test instead of a field failure;
- the C oracle's contracts are pinned against a declarative description written
  independently of its control flow — a shape mismatch (an off-by-one region, a
  mis-sized field) shows up even though a shared assumption would not.

Independent confirmation of the **layout** comes from elsewhere entirely: three
codebases that never saw this spec (per-gron/reacdriver's `MbufUtils`,
norihiro/obs-h8819's `convert_to_pcm24lep`, listening-validated against a real
M-200i) and the rig's own listening and autocorrelation tests. Neither harness here
adds to that, and neither should be cited as if it did.

## Fixtures

`fixtures/upstream.json` — real MAC-sanitized rig captures with their PCM truth
tables, the same arrays libreac pins (`UP8` 340 B / `UP16` 628 B / `UP32A`, `UP32B`
1206 B — 1204 B frames the capture left two bytes of Ethernet FCS on).

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

**There is no downstream fixture in this repo.** The audio layout itself is settled —
one braid, both directions, every generation (`reac.ksy` carries the evidence, and the
per-generation "M-5000 plain LE vs the rest" idea is refuted, never having been more
than an untested guess at a discrepancy that turned out to be a mid-byte lane shift).
What this repo lacks is a *captured* downstream frame: every committed golden is an
upstream return, so the downstream side of the grammar is checked only against frames
libreac's encoder built. That exercises the envelope, the structure and agreement with
the codec — not a console on a wire. A downstream capture would close the gap in the
corpus; it is not needed to decide the layout.


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
