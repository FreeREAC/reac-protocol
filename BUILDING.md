# Building and checking reac-protocol

This repository is a protocol reference plus a machine-checkable grammar. Nothing here is
installed; "building" means generating the parser from the grammar and running the
cross-checks that hold the grammar, the declared facts and the C oracle (libreac) together.
[`spec/README.md`](spec/README.md) explains what each check proves; this page is how to run them.

## Requirements

- Python 3 with `kaitaistruct`, `pytest` and `PyYAML`:

      pip install kaitaistruct pytest pyyaml

- The Kaitai Struct compiler, `kaitai-struct-compiler` 0.11. It is not in the distribution
  repositories; it needs a Java runtime (17 or later) at build time only, and the parser it
  generates is plain Python:

      curl -fsSLO https://github.com/kaitai-io/kaitai_struct_compiler/releases/download/0.11/kaitai-struct-compiler-0.11.zip
      unzip -q kaitai-struct-compiler-0.11.zip
      export PATH="$PWD/kaitai-struct-compiler-0.11/bin:$PATH"

- GNU make.

## The checks CI runs

    make -C spec check     # generate spec/reac.py from spec/reac.ksy, then the cross-check suite
    make -C spec cpp       # prove the C-family (cpp_stl) target also generates

    python3 -m unittest discover -s tools -p 'test_*.py'
    python3 tools/freereac_ops.py check

`make -C spec check` regenerates the parser (it is never committed), requires the generated
fact headers to be current and reproducible, and runs `reac_xcheck.py`, `facts_xcheck.py` and
`facts_fresh_xcheck.py`. `tools/freereac_ops.py check` keeps the public tree public: no
internal material, no file-name citation of a moved document, no build command on the README.

## The declared facts

`spec/protocol-facts.yaml` is the one source for the constants the grammar and libreac share.
After editing it, regenerate and commit `spec/generated/`:

    make -C spec facts

`make -C spec facts-perturb SEED=n OUT=dir` writes a fictional but self-consistent fact set to
build a consumer against; anything that breaks spelled a fact by hand.

## Developer-only checks

These need other checkouts and stay out of CI, which is hermetic:

    make -C spec check-oracle      LIBREAC=../../libreac   # the parser against the compiled libreac
    make -C spec check-ctrl-oracle LIBREAC=../../libreac   # libreac builds, the parser reads back
    make -C spec corpus-check      CAPTURES=/path/to/reac-captures
    make -C spec corpus-selftest   CAPTURES=/path/to/reac-captures

## Tests that need the private fixtures

Two recovered desk scene bodies are vendor captures and are kept in the private
`FreeREAC/freereac-ops` repository, not here. `tools/freereac_ops.py` finds that checkout at
`$FREEREAC_OPS`, else at a sibling `../freereac-ops`. Without it, the tests that need those
exact bytes skip with an `OPS-ABSENT <name>` reason and everything else runs, including the
scene-layout tests on a synthetic body. With access, run the suite against it, and make an
absent checkout a failure rather than a skip:

    FREEREAC_OPS=/path/to/freereac-ops FREEREAC_REQUIRE_OPS=1 make -C spec check
