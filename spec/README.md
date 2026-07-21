# REAC control-plane spec (Kaitai Struct)

`reac_control.ksy` is the **canonical, machine-readable** layout of a REAC `0x8819`
**control record** — the Roland DT1 SysEx container that carries head-amp (48 V / pad /
SENS), the join grant, and the model-identity exchange. It is the single source of truth
the prose in [../wire-format.md](../wire-format.md) is derived from.

## Generate a parser

`ksc` compiles the spec into a parser in C++, Python, Go, Rust, JS, …:

```sh
ksc -t cpp_stl --outdir out reac_control.ksy   # C-family parser (the real-time tooling)
ksc -t python  --outdir out reac_control.ksy   # capture analysis + the tests here
```

Kaitai has no pure-C backend; `cpp_stl` (C++ with the STL) is its C-family target — the
generated `reac_control_t` / `head_amp_t` / `join_grant_t` classes — and it is what the
C real-time code links against.

## Analyse a capture

Drop `reac_control.ksy` into the Kaitai Web IDE (`ide.kaitai.io`) to overlay the field map
directly on a hex capture, or script the generated Python parser to sweep a `.pcap` and flag
any record the spec cannot parse (a new tag, a wrapper variant).

## Test / conformance

`test_reac_control.py` decodes a set of known control records (the worked examples from the
protocol reference) and asserts the decode plus the Roland DT1 inner-checksum invariant
(`Σ(TAG..CKSUM) ≡ 0x80`). CI regenerates the parser from the spec and runs it on every change
(`.github/workflows/ksy-conformance.yml`):

```sh
ksc -t python --outdir . reac_control.ksy && python -m pytest test_reac_control.py -q
```

The generated parser (`reac_control.py` / `.cpp` / `.h`) is never committed — it is
regenerated from the spec.

## Scope — what the spec does and does not cover

- **Covers:** one genuine control *record* — the `cd ea 04 03` marker, the `00 02 00 fe`
  wrapper, the `f0 41 … f7` Roland DT1 SysEx envelope, the tag switch (head-amp / grant /
  identity), and the **inner** (Roland DT1) checksum.
- **Does not cover:** the full 1492-byte frame, the audio de-interleave, or the handshake
  FSM; and the **outer** 32-byte block checksum spans past the record into frame padding, so
  it is validated in code, not in the spec. Full-corpus conformance across every capture is a
  separate check; the fixtures here are the public gate.

## Installing ksc

Not in distro repos. Grab the universal zip (JVM, build-time only — the *generated* parser is
native, no JVM in the artifact):

```sh
curl -fsSLO https://github.com/kaitai-io/kaitai_struct_compiler/releases/download/0.10/kaitai-struct-compiler-0.10.zip
unzip -q kaitai-struct-compiler-0.10.zip
./kaitai-struct-compiler-0.10/bin/kaitai-struct-compiler -t cpp_stl reac_control.ksy
```
