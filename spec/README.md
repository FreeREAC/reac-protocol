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
`reac_braid_pos()`, `reac_decode()` — against the parser ksc generates from
`reac.ksy`. It is out of `make check` and out of CI on purpose: it needs a libreac
checkout and a C toolchain the spec repo does not otherwise depend on, and the
hermetic gate should stay hermetic.

Latest run — 4 upstream goldens plus one downstream frame built by libreac's own
encoder:

```
field checks : 53
PCM samples  : 1536
mismatches   : 0
```

## What that agreement proves — and what it does not

`reac.ksy` was written by reading libreac. Agreement between the two is therefore
**internal consistency, not independent confirmation of the wire format**. Both sides
can be wrong together; on the downstream audio layout at least one of libreac's own
two readings must be. A green `check-oracle` is not evidence about Roland's protocol.

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

**The downstream audio layout is an open question, and the grammar picks a side.**
Upstream is settled: the braid, on real captures, at three box widths. Downstream is
not. libreac ships two incompatible readings of the same 1492 bytes — `reac_decode()`
reads plain LE sample-major and is still a consumer's default; `reac_braid_pos()` is
the braid, and `reac_downstream_build()` *encodes* with it. On a frame built by that
encoder all **480/480** samples differ between the two readings. `reac.ksy` describes
the braid, on the evidence listed in its own doc, and says in the same breath that
this is a choice and not a fact. Whether OHRCA-generation gear differs downstream is
what a rig capture has to settle. Note also that **there is no downstream fixture in
this repo** — every committed golden is an upstream return, so the downstream side of
the grammar is checked only against frames libreac's encoder built, which exercises
the envelope and the structure, not the layout.


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
