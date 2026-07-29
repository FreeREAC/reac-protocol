"""Diff the generated parser against the COMPILED libreac, not a transcription.

`reac_xcheck.py` is the hermetic referee: it compares `reac.ksy` against the
truth tables the C tests are held to, plus Python rewrites of the C contracts.
Those rewrites are a second reading of the same headers, and a reading can be
wrong the same way twice. This script closes that step — it builds libreac,
links `c_oracle_dump.c` against it, and compares the compiler's actual output
with the parser ksc generates from the spec.

    make -C spec check-oracle LIBREAC=../../libreac

Dev-only, and deliberately outside `make check` and CI: it needs a libreac
checkout and a C toolchain that the spec repo does not otherwise depend on.

WHAT AGREEMENT HERE PROVES, EXACTLY
-----------------------------------
`reac.ksy` was written by reading libreac. Agreement between the two is
therefore *internal consistency*, not independent confirmation of the wire
format: both sides can be wrong together, and on the downstream audio layout at
least one of libreac's own two readings must be (see below). What agreement
does buy is real but bounded:

  * the spec is EXECUTABLE and matches the running code, field for field, on
    every golden — so it can be handed to a third party as a parser, not as
    prose that may or may not have kept up;
  * drift between spec and implementation becomes a red test instead of a field
    failure;
  * the C oracle's contracts are pinned against a declarative description that
    was written independently of its control flow.

Independent confirmation of the LAYOUT comes from elsewhere entirely — three
codebases that never saw this spec (per-gron/reacdriver, norihiro/obs-h8819)
and the rig's listening tests. This script cannot and does not add to that.

THE ONE PLACE THE TWO SIDES ARE KNOWN TO DISAGREE
-------------------------------------------------
The downstream audio layout. libreac ships two different readings of the same
1492 bytes: `reac_decode()` (plain LE, sample-major) and the braid oracle
`reac_braid_pos()`, which is what `reac_downstream_build()` ENCODES with. They
cannot both describe the wire. `reac.ksy` describes the braid. This script
reports the divergence numerically rather than hiding it, and the assertion it
makes is only that the spec agrees with the ENCODER — see the downstream check
below for what that is and is not worth.
"""
import argparse
import json
import pathlib
import shutil
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent

SAMPLES_PER_PKT = 12
MAX_CHANNELS = 40


def s24le(lo, mid, hi):
    v = lo | (mid << 8) | (hi << 16)
    return v - 0x1000000 if v & 0x800000 else v


def braid_pos(s, ch, n_ch):
    """reac_braid_pos(), for reading the ksy's pair groups back as channels."""
    g = (s * n_ch + (ch & ~1)) * 3
    return (g + 3, g + 0, g + 1) if ch % 2 == 0 else (g + 4, g + 5, g + 2)


def ksy_planar(parsed, n_ch):
    """Decode a parsed frame's audio region through the spec's pair-group
    structure plus the braid the spec documents. Returns planar [ch][s]."""
    out = []
    for ch in range(n_ch):
        row = []
        for s in range(SAMPLES_PER_PKT):
            grp = parsed.audio.time_samples[s].pair_groups[ch // 2]
            idx = (3, 0, 1) if ch % 2 == 0 else (4, 5, 2)
            row.append(s24le(grp[idx[0]], grp[idx[1]], grp[idx[2]]))
        out.append(row)
    return out


class Report:
    def __init__(self):
        self.checks = 0
        self.samples = 0
        self.failures = []

    def eq(self, what, got, want):
        self.checks += 1
        if got != want:
            self.failures.append(f"{what}: ksy={got!r} oracle={want!r}")

    def ok(self):
        return not self.failures


def build(libreac: pathlib.Path, workdir: pathlib.Path) -> pathlib.Path:
    """Build libreac, then link c_oracle_dump.c against it. Returns the binary."""
    if not (libreac / "include" / "reac" / "reac.h").is_file():
        sys.exit(f"not a libreac checkout: {libreac}\n"
                 f"pass --libreac PATH (or make check-oracle LIBREAC=PATH)")
    subprocess.run(["make", "-s", "libreac.a"], cwd=libreac, check=True)
    binary = workdir / "c_oracle_dump"
    cc = shutil.which("cc") or shutil.which("gcc")
    if not cc:
        sys.exit("no C compiler found (cc/gcc)")
    subprocess.run([cc, "-O2", "-std=c11", "-Wall", "-Wextra",
                    f"-I{libreac / 'include'}", str(HERE / "c_oracle_dump.c"),
                    str(libreac / "libreac.a"), "-lm", "-o", str(binary)],
                   check=True)
    return binary


def check_upstream(binary, R, rep):
    """The four committed rig goldens, through both sides, field for field."""
    fixtures = json.loads((HERE / "fixtures" / "upstream.json").read_text())["frames"]
    hexlines = "".join(f["hex"] + "\n" for f in fixtures)
    proc = subprocess.run([str(binary), "upstream"], input=hexlines,
                          capture_output=True, text=True, check=True)
    dumps = [json.loads(l) for l in proc.stdout.splitlines() if l.strip()]
    assert len(dumps) == len(fixtures), "oracle dumped a different number of frames"

    from kaitaistruct import BytesIO, KaitaiStream
    for fx, c in zip(fixtures, dumps):
        name = fx["name"]
        raw = bytes.fromhex(fx["hex"])
        p = R.Reac(KaitaiStream(BytesIO(raw)))
        rep.eq(f"{name}.raw_len", p.raw_len, c["raw_len"])
        rep.eq(f"{name}.clean_len", p.clean_len, c["clean_len"])
        rep.eq(f"{name}.num_channels", p.num_channels, c["upstream_channels"])
        rep.eq(f"{name}.counter", p.counter, c["counter"])
        rep.eq(f"{name}.has_trailer", p.has_ohrca_trailer,
               c["raw_len"] != c["clean_len"])
        rep.eq(f"{name}.len_audio", p.len_audio,
               c["upstream_channels"] * 36)
        rep.eq(f"{name}.samples", len(p.audio.time_samples),
               c["upstream_samples"])
        got = ksy_planar(p, c["upstream_channels"])
        rep.eq(f"{name}.pcm", got, c["upstream_pcm"])
        rep.samples += c["upstream_channels"] * SAMPLES_PER_PKT
        # the frame's own end marker, past the audio, with the trailer stripped
        rep.eq(f"{name}.end_marker", bytes(p.end_marker), b"\xc2\xea")


def check_downstream(binary, R, rep):
    """A 40-channel downstream frame built by libreac's own encoder.

    Scope, stated bluntly: this is a SYNTHETIC frame from
    `reac_downstream_build()`, not a captured console. Agreement proves the
    spec's structural description of the 1492-byte downstream envelope matches
    what libreac emits, and nothing whatsoever about what a real desk puts on
    the wire — that would need a downstream capture, which this repo has none
    of. The corpus is upstream-only.
    """
    proc = subprocess.run([str(binary), "downstream"], capture_output=True,
                          text=True, check=True)
    c = json.loads(proc.stdout)
    raw = bytes.fromhex(c["hex"])

    from kaitaistruct import BytesIO, KaitaiStream
    p = R.Reac(KaitaiStream(BytesIO(raw)))
    rep.eq("downstream.raw_len", p.raw_len, c["built_len"])
    rep.eq("downstream.clean_len", p.clean_len, c["clean_len"])
    rep.eq("downstream.num_channels", p.num_channels, MAX_CHANNELS)
    rep.eq("downstream.is_downstream_width", p.is_downstream_width, True)
    rep.eq("downstream.counter", p.counter, c["counter"])
    rep.eq("downstream.has_trailer", p.has_ohrca_trailer, False)
    rep.eq("downstream.end_marker", bytes(p.end_marker), b"\xc2\xea")
    rep.eq("downstream.eth_dst", bytes(p.eth_dst), b"\xff" * 6)
    rep.eq("downstream.type_word", p.control.type_word,
           R.Reac.FrameType.filler.value)
    rep.eq("downstream.ctrl_kind", p.control.ctrl_kind,
           R.Reac.CtrlKind.filler.value)
    rep.eq("downstream.descriptor_slots", len(p.control.block.descriptor), 16)

    got = ksy_planar(p, MAX_CHANNELS)
    rep.eq("downstream.braid_pcm_vs_oracle", got, c["braid_pcm"])
    rep.eq("downstream.braid_pcm_vs_encoder_input", got, c["encoded_pcm"])
    rep.samples += MAX_CHANNELS * SAMPLES_PER_PKT
    return c, got


def report_downstream_divergence(c, ksy_pcm):
    """The known open question, quantified rather than asserted away."""
    plain = c.get("plain_le_pcm")
    if plain is None:
        return "libreac's plain-LE reac_decode() refused the frame"
    differing = sum(1 for a, b in zip(ksy_pcm, plain) for x, y in zip(a, b) if x != y)
    total = MAX_CHANNELS * SAMPLES_PER_PKT
    agree = total - differing
    return (f"{differing}/{total} samples differ between the braid (what the "
            f"spec and reac_downstream_build() use) and libreac's plain-LE "
            f"reac_decode(); {agree} agree by coincidence of the byte map")


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--libreac", default=str(HERE.parent.parent / "libreac"),
                    help="path to a libreac checkout (default: ../../libreac)")
    args = ap.parse_args(argv)

    sys.path.insert(0, str(HERE))
    try:
        import reac as R
    except ImportError:
        sys.exit("spec/reac.py not found — generate it first: make -C spec parser")

    binary = build(pathlib.Path(args.libreac).resolve(), HERE)
    rep = Report()
    check_upstream(binary, R, rep)
    c, ksy_pcm = check_downstream(binary, R, rep)

    print("reac.ksy (generated parser) vs the compiled libreac oracle")
    print(f"  frames compared : 4 upstream goldens + 1 synthesized downstream")
    print(f"  field checks    : {rep.checks}")
    print(f"  PCM samples     : {rep.samples}")
    print(f"  mismatches      : {len(rep.failures)}")
    for f in rep.failures:
        print(f"    FAIL {f}")
    print()
    print("open question, not a failure — the downstream audio layout:")
    print(f"  {report_downstream_divergence(c, ksy_pcm)}")
    print("  libreac ships both readings; reac.ksy describes the braid and says")
    print("  so. Only a downstream capture settles which one a console emits.")
    return 0 if rep.ok() else 1


if __name__ == "__main__":
    raise SystemExit(main())
