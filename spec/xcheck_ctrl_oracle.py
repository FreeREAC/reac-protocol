#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Pau Aliagas <linuxnow@gmail.com>
"""Build it with libreac, read it back with the ksy — and require them to agree.

    make -C spec check-ctrl-oracle LIBREAC=../../libreac

THE POINT, stated plainly. Sharing a constant catches a typo. It does not catch
a MISUNDERSTANDING: two sides can spell 26 identically and still disagree about
what the 26 bytes are, where they start, or which of them the box validates.
The only thing that catches that is making one side emit and the other side
read, and asserting the value across the boundary.

Tonight's synthetic-body defect is the case in point. The frames were
structurally valid and semantically wrong — a real box accepted the transfer,
replied, and came up reporting model=unknown with zero ports. Nothing in a
constants file would have moved. A round trip does move: it reassembles the
body out of what the grammar read from libreac's own frames and compares it to
the body that went in, so a chunk that lands at the wrong offset, a header that
declares the wrong total, or a final that carries the wrong tail all come back
as a byte diff with an offset on it.

WHAT RUNS

  FORWARD   libreac builds all 343 steps of a scene transfer from a recovered
            desk body; the ksy-generated parser reads each frame; the body is
            REASSEMBLED from what the parser found and compared byte for byte
            with the input. Repeated for every body fixture, and for the
            tag-only body libreac's own reac_ctrl_scene_build() makes.
  FORWARD   libreac stamps head-amp DT1 records; the parser reads back CH,
            PARAM, VALUE, the tag and both checksums.
  ORDERING  the same record with the two nested checksums stamped in the wrong
            order. The grammar still parses it — that is the whole danger —
            and libreac's block verifier must reject it. A harness that cannot
            tell these two apart is not checking anything.
  REVERSE   every control block in the committed corpus goes to BOTH: the
            parser classifies and decodes it, libreac's verifiers judge it, and
            the two must agree on every block and on every head-amp triple in
            the 56-frame grant sweep.
  CONSTANTS a translation unit of _Static_asserts binding libreac's own macros
            to protocol-facts.yaml, compiled against libreac's headers.

TWO PROPERTIES THIS HARNESS KEEPS, both of them scars.

  A POSITIVE CONTROL BEFORE ANY ABSENCE CLAIM. Before reporting zero
  mismatches, the harness corrupts a frame it has already checked and requires
  the comparison to go RED. A probe that reports silence has to prove it can
  hear first.

  INCONCLUSIVE IS A VERDICT. Thin coverage reports INCONCLUSIVE, never PASS. A
  green run over two frames is not evidence about a protocol, and a run that
  found nothing to compare must say so rather than print a zero.

IT DOES NOT TOUCH THE LIBREAC CHECKOUT. libreac is snapshotted with `git
archive` and built in a temp directory, so a lane mid-migration there is
neither read half-written nor built over.
"""
import argparse
import json
import pathlib
import shutil
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent

# Below these, the run reports INCONCLUSIVE rather than PASS. They are floors on
# what was actually COMPARED, not on the size of the corpus: a scan that finds
# nothing must not read as a scan that found nothing wrong.
MIN_SCENE_BODIES = 2
MIN_SCENE_STEPS = 343
MIN_CORPUS_BLOCKS = 40
MIN_HEADAMP_RECORDS = 24


class Report:
    def __init__(self):
        self.checks = 0
        self.failures = []
        self.counts = {}

    def eq(self, what, got, want):
        self.checks += 1
        if got != want:
            self.failures.append(f"{what}: ksy={got!r} libreac={want!r}")
        return got == want

    def bump(self, key, n=1):
        self.counts[key] = self.counts.get(key, 0) + n

    def ok(self):
        return not self.failures

    def parse(self, what, fn):
        """A grammar that REFUSES bytes libreac wrote is a disagreement like any
        other, and it must be reported as one rather than end the run in a
        traceback — a harness that dies on the first divergence hides every
        divergence behind it."""
        self.checks += 1
        try:
            return fn()
        except Exception as e:                      # noqa: BLE001
            self.failures.append(f"{what}: the ksy parser refused libreac's "
                                 f"bytes — {type(e).__name__}: {e}")
            return None


def snapshot_libreac(src: pathlib.Path, work: pathlib.Path) -> pathlib.Path:
    """Copy libreac out of git rather than off disk. Two reasons: another lane
    may be mid-edit in that checkout, and building in place would leave objects
    in somebody else's tree."""
    if not (src / "include" / "reac" / "reac_ctrlblk.h").is_file():
        sys.exit(f"not a libreac checkout: {src}\n"
                 f"pass --libreac PATH (or make check-ctrl-oracle LIBREAC=PATH)")
    dst = work / "libreac"
    dst.mkdir()
    tar = subprocess.run(["git", "-C", str(src), "archive", "HEAD"],
                         capture_output=True, check=True).stdout
    subprocess.run(["tar", "-x", "-C", str(dst)], input=tar, check=True)
    rev = subprocess.run(["git", "-C", str(src), "rev-parse", "--short", "HEAD"],
                         capture_output=True, text=True, check=True).stdout.strip()
    dirty = subprocess.run(["git", "-C", str(src), "status", "--porcelain"],
                           capture_output=True, text=True, check=True).stdout.strip()
    return dst, rev, bool(dirty)


def build(libreac: pathlib.Path, work: pathlib.Path):
    cc = shutil.which("cc") or shutil.which("gcc")
    if not cc:
        sys.exit("no C compiler found (cc/gcc)")
    noise = []
    r = subprocess.run(["make", "-s", "libreac.a"], cwd=libreac,
                       capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit("libreac did not build:\n" + r.stdout + r.stderr)
    noise += [l for l in r.stderr.splitlines() if "warning:" in l]

    dump = work / "c_ctrl_dump"
    r = subprocess.run([cc, "-O2", "-std=c11", "-Wall", "-Wextra",
                        f"-I{libreac / 'include'}", str(HERE / "c_ctrl_dump.c"),
                        str(libreac / "libreac.a"), "-lm", "-o", str(dump)],
                       capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit("c_ctrl_dump did not build:\n" + r.stdout + r.stderr)
    noise += [l for l in r.stderr.splitlines() if "warning:" in l]

    # The constants TU. Compiled, never linked: every _Static_assert in it is
    # about a macro, and a failure names the constant that drifted.
    tu = work / "facts_assert.c"
    tu.write_text('#include "generated/reac_facts_assert.h"\n'
                  'int reac_facts_assertions_compiled = REAC_FACTS_ASSERTIONS;\n')
    r = subprocess.run([cc, "-c", "-std=c11", "-Wall", "-Wextra",
                        f"-I{libreac / 'include'}", f"-I{HERE}",
                        str(tu), "-o", str(work / "facts_assert.o")],
                       capture_output=True, text=True)
    return dump, r, sorted(set(noise))


def run_dump(dump, *args, stdin=None):
    r = subprocess.run([str(dump), *args], input=stdin, capture_output=True,
                       text=True)
    if r.returncode != 0:
        sys.exit(f"c_ctrl_dump {' '.join(args)} failed:\n{r.stderr}")
    return r.stdout.splitlines()


# --------------------------------------------------------------------------

def check_scene_roundtrip(R, KS, BIO, dump, body: bytes, label: str, rep: Report):
    """libreac builds every step; the parser reads every step; the body is put
    back together out of what the parser found and compared with the original."""
    tmp = pathlib.Path(tempfile.mkdtemp()) / "body.bin"
    tmp.write_bytes(body)
    windows = run_dump(dump, "scene", str(tmp))
    rep.eq(f"{label}: step count", len(windows), 343)
    if len(windows) != 343:
        return

    rebuilt = bytearray()
    declared_total = None
    for step, hexline in enumerate(windows):
        blk = rep.parse(f"{label} step {step}",
                        lambda h=hexline: R.Reac.TypedBlock(KS(BIO(bytes.fromhex(h)))))
        if blk is None:
            continue
        rep.bump("scene_steps")

        # the block checksum, judged by the library and by the grammar's own rule
        raw = bytes.fromhex(hexline)[2:]
        rep.eq(f"{label} step {step}: block sums to 0", sum(raw) % 256, 0)

        pay = blk.block.payload
        if step == 0:
            rep.eq(f"{label} step 0: op", blk.block.op,
                   R.Reac.ControlOp.scene_header)
            declared_total = pay.scene_total_len
            rep.eq(f"{label} step 0: op_len is the head length",
                   blk.block.op_len, 24)
            rebuilt += pay.body_head
        elif step < 342:
            rep.eq(f"{label} step {step}: op", blk.block.op,
                   R.Reac.ControlOp.scene_chunk)
            rep.eq(f"{label} step {step}: op_len", blk.block.op_len, 26)
            rep.eq(f"{label} step {step}: subtype byte is zero",
                   pay.chunk_reserved, 0)
            rebuilt += pay.chunk
        else:
            rep.eq(f"{label} step {step}: op", blk.block.op,
                   R.Reac.ControlOp.scene_final)
            rep.eq(f"{label} step {step}: op_len", blk.block.op_len, 14)
            rebuilt += pay.chunk[:blk.block.op_len]

    rep.eq(f"{label}: header declares the body length",
           declared_total, len(body))
    rep.eq(f"{label}: reassembled length", len(rebuilt), len(body))
    if len(rebuilt) == len(body):
        bad = [i for i in range(len(body)) if rebuilt[i] != body[i]]
        rep.checks += 1
        if bad:
            rep.failures.append(
                f"{label}: round trip differs in {len(bad)} bytes, first at "
                f"+{bad[0]:#06x} (libreac->ksy {rebuilt[bad[0]]:#04x}, "
                f"input {body[bad[0]]:#04x})")

    # The grammar's structural walk must land on the offsets libreac indexes.
    sb = rep.parse(f"{label}: reassembled body",
                   lambda: R.Reac.SceneBody(KS(BIO(bytes(rebuilt)))))
    if sb is None:
        return
    rep.eq(f"{label}: magic", sb.magic, b"1234")
    rep.eq(f"{label}: SYSP where libreac indexes it",
           bytes(rebuilt[0x368:0x36c]), sb.sysp.tag)
    rep.eq(f"{label}: SCEN where libreac indexes it",
           bytes(rebuilt[0x37c:0x380]), sb.scen.tag)
    rep.eq(f"{label}: master id where libreac indexes it",
           bytes(rebuilt[0x340:0x346]), sb.master_id)
    rep.bump("scene_bodies")


def check_headamp(R, KS, BIO, dump, rep: Report):
    # Every other channel of the 48-slot head-amp space, all three parameters.
    # The space is walked rather than sampled because its top half is exactly
    # what a table bounded by the 40-slot audio fabric silently drops, and a
    # harness that only tests low channels would never see that.
    cases = [(ch, p, v)
             for ch in range(0x00, 0x30, 2)
             for p, v in ((0x00, 1), (0x01, 0), (0x02, 0x37))]
    lines = []
    for ch, p, v in cases:
        hexline = run_dump(dump, "headamp", str(ch), str(p), str(v))[0]
        lines.append(hexline)
        blk = rep.parse(f"headamp {ch:#04x}/{p}",
                        lambda h=hexline: R.Reac.TypedBlock(KS(BIO(bytes.fromhex(h)))))
        if blk is None:
            continue
        rep.eq(f"headamp {ch:#04x}/{p}: kind", blk.ctrl_kind,
               R.Reac.CtrlKind.head_amp)
        rec = blk.block.payload.body
        rep.eq(f"headamp {ch:#04x}/{p}: tag", rec.tag, R.Reac.RegPage.head_amp)
        rep.eq(f"headamp {ch:#04x}/{p}: ch", rec.data.ch, ch)
        rep.eq(f"headamp {ch:#04x}/{p}: param", rec.data.param.value, p)
        rep.eq(f"headamp {ch:#04x}/{p}: value", rec.data.value, v)
        rep.bump("headamp_records")

    judged = run_dump(dump, "verify", stdin="\n".join(lines) + "\n")
    for (ch, p, v), js in zip(cases, judged):
        j = json.loads(js)
        rep.eq(f"headamp {ch:#04x}/{p}: libreac accepts the block", j["block_ok"], 1)
        rep.eq(f"headamp {ch:#04x}/{p}: libreac accepts the record", j["record_ok"], 0)

    # THE ORDERING LAW. The record checksum is stamped inside the block, so a
    # record fixed up after the block invalidates it. The grammar cannot see
    # that — it parses the frame happily — which is exactly why the library's
    # verifier has to, and why this asserts BOTH halves.
    bad = run_dump(dump, "headamp-badorder", "32", "0", "1")[0]
    blk = R.Reac.TypedBlock(KS(BIO(bytes.fromhex(bad))))
    rep.eq("wrong-order record: the grammar still parses it",
           blk.block.payload.body.data.ch, 32)
    j = json.loads(run_dump(dump, "verify", stdin=bad + "\n")[0])
    rep.eq("wrong-order record: libreac REJECTS the block", j["block_ok"], 0)
    rep.eq("wrong-order record: the inner record is still well formed",
           j["record_ok"], 0)


def check_corpus(R, KS, BIO, dump, rep: Report):
    fx = json.loads((HERE / "fixtures" / "control.json").read_text())
    blocks = [(b["name"], b["hex"]) for b in fx["blocks"]]
    blocks += [(f"grant_sweep[{i}]", h)
               for i, h in enumerate(fx["grant_sweep"]["frames"])]

    judged = run_dump(dump, "verify",
                      stdin="".join(h + "\n" for _, h in blocks))
    rep.eq("corpus: one verdict per block", len(judged), len(blocks))

    for (name, hexline), js in zip(blocks, judged):
        j = json.loads(js)
        raw = bytes.fromhex(hexline)
        blk = rep.parse(name, lambda r=raw: R.Reac.TypedBlock(KS(BIO(r))))
        if blk is None:
            continue
        rep.bump("corpus_blocks")

        # The grammar's checksum rule and the library's verifier, on the same
        # bytes. FILLER is exempt in both.
        if blk.type_word != R.Reac.FrameType.filler:
            rep.eq(f"{name}: block checksum", sum(raw[2:]) % 256 == 0,
                   bool(j["block_ok"]))
            rep.eq(f"{name}: the stamp libreac would write is the one there",
                   raw[33], j["restamped"])

        if blk.ctrl_kind == R.Reac.CtrlKind.head_amp:
            rec = blk.block.payload.body
            rep.eq(f"{name}: libreac accepts the nested record",
                   j["record_ok"], 0)
            rep.eq(f"{name}: record checksum sums to 0x80",
                   sum(raw[18:18 + blk.block.op_len - 0x0d]) % 256, 0x80)
            rep.eq(f"{name}: ch is inside the head-amp space",
                   rec.data.ch < 0x30, True)
            rep.bump("corpus_headamp")


def positive_control(R, KS, BIO, dump, rep: Report):
    """Before believing a zero, prove the comparison can go red. A single byte
    is flipped in a frame the harness has already accepted; the library and the
    grammar must both notice, and the round trip must produce a diff."""
    good = run_dump(dump, "headamp", "32", "0", "1")[0]
    raw = bytearray(bytes.fromhex(good))
    raw[22] ^= 0x01                      # the VALUE byte: 48V on -> off
    flipped = bytes(raw).hex()

    blk = R.Reac.TypedBlock(KS(BIO(bytes(raw))))
    seen = blk.block.payload.body.data.value
    j = json.loads(run_dump(dump, "verify", stdin=flipped + "\n")[0])

    problems = []
    if seen != 0:
        problems.append("the parser did not read the flipped VALUE back")
    if j["block_ok"] != 0:
        problems.append("libreac accepted a block whose checksum is now wrong")
    if j["restamped"] == raw[33]:
        problems.append("libreac would restamp to the same byte it found")
    return problems


# --------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--libreac", default=str(HERE.parent.parent / "libreac"))
    ap.add_argument("--make-scene", default=None, metavar="PATH",
                    help="lane N's docs/design/notes/scene/make-scene.py. Its "
                         "output is round-tripped like any other body, which "
                         "is the interesting case: a body BUILT from a named "
                         "field layout rather than recovered from a capture.")
    args = ap.parse_args()

    sys.path.insert(0, str(HERE))
    try:
        import reac as R
        from kaitaistruct import BytesIO as BIO, KaitaiStream as KS
    except ImportError as e:
        sys.exit(f"{e}\nrun `make -C spec parser` first (and pip install kaitaistruct)")

    rep = Report()
    skipped_generator = None
    with tempfile.TemporaryDirectory() as td:
        work = pathlib.Path(td)
        libreac, rev, dirty = snapshot_libreac(pathlib.Path(args.libreac).resolve(),
                                               work)
        dump, facts_tu, noise = build(libreac, work)

        bodies = [(p.stem, p.read_bytes())
                  for p in sorted((HERE / "fixtures").glob("scene-*-8904.bin"))]
        # ... plus the one libreac builds for itself, which is the refuted
        # tag-only body. It goes through the same round trip: refuted as a
        # DRIVER of real hardware is not the same as malformed, and the
        # transfer arithmetic has to hold for it too.
        built = bytes.fromhex(run_dump(dump, "scene-build", "00:40:ab:00:00:01")[0])
        bodies.append(("libreac-scene-build", built))

        # A body GENERATED from a named field layout, not recovered from a
        # capture. If the layout is complete this is the same 8904 bytes a real
        # desk sends, and putting it through the transfer proves the emitter and
        # the grammar agree about a body neither of them has ever seen on a wire.
        gen = args.make_scene
        if gen is None:
            probe = (HERE.parent.parent / "openmixer-nightN" / "docs" / "design"
                     / "notes" / "scene" / "make-scene.py")
            gen = str(probe) if probe.is_file() else None
        if gen:
            out = work / "made-scene.bin"
            r = subprocess.run([sys.executable, gen, "--mac", "00:40:ab:c9:cc:03",
                                "--generation", "0", str(out)],
                               capture_output=True, text=True)
            if r.returncode == 0 and out.is_file():
                bodies.append(("make-scene-generated", out.read_bytes()))
            else:
                skipped_generator = r.stderr.strip() or "make-scene.py refused"
        else:
            skipped_generator = "make-scene.py not found; pass --make-scene PATH"

        for label, body in bodies:
            check_scene_roundtrip(R, KS, BIO, dump, body, label, rep)
        check_headamp(R, KS, BIO, dump, rep)
        check_corpus(R, KS, BIO, dump, rep)
        control = positive_control(R, KS, BIO, dump, rep)

    c = rep.counts
    print("libreac builds it, the ksy-generated parser reads it back")
    print(f"  libreac         : {rev}{'  (WORKING TREE DIRTY — HEAD was used)' if dirty else ''}")
    print(f"  scene bodies    : {c.get('scene_bodies', 0)}"
          f" ({c.get('scene_steps', 0)} transfer steps parsed)")
    print(f"  head-amp records: {c.get('headamp_records', 0)} built"
          f" + {c.get('corpus_headamp', 0)} from the corpus")
    print(f"  corpus blocks   : {c.get('corpus_blocks', 0)}")
    if skipped_generator:
        print(f"  generated body  : NOT COVERED — {skipped_generator}")
    print(f"  field checks    : {rep.checks}")
    print(f"  mismatches      : {len(rep.failures)}")

    if noise:
        print(f"  libreac warnings: {len(noise)} — not this harness's to fix, "
              f"reported because a build nobody reads is a build nobody reads")
        for l in noise:
            print(f"      {l.strip()}")
    print(f"  constants TU    : ", end="")
    n_assert = next(
        (int(l.split()[-1]) for l in
         (HERE / "generated" / "reac_facts_assert.h").read_text().splitlines()
         if l.startswith("#define REAC_FACTS_ASSERTIONS")), 0)
    if facts_tu.returncode == 0:
        print(f"{n_assert} _Static_asserts compiled clean against libreac's "
              f"own headers")
    else:
        print("FAILED — libreac's macros have drifted from protocol-facts.yaml")
        for line in facts_tu.stderr.splitlines():
            if "static assertion" in line or "drifted" in line:
                print(f"      {line.strip()}")

    if rep.failures:
        print("\nmismatches:")
        for f in rep.failures[:40]:
            print(f"  {f}")
        if len(rep.failures) > 40:
            print(f"  ... and {len(rep.failures) - 40} more")

    thin = []
    if c.get("scene_bodies", 0) < MIN_SCENE_BODIES:
        thin.append(f"scene bodies {c.get('scene_bodies', 0)} < {MIN_SCENE_BODIES}")
    if c.get("scene_steps", 0) < MIN_SCENE_STEPS:
        thin.append(f"transfer steps {c.get('scene_steps', 0)} < {MIN_SCENE_STEPS}")
    if c.get("corpus_blocks", 0) < MIN_CORPUS_BLOCKS:
        thin.append(f"corpus blocks {c.get('corpus_blocks', 0)} < {MIN_CORPUS_BLOCKS}")
    if c.get("headamp_records", 0) < MIN_HEADAMP_RECORDS:
        thin.append(f"head-amp records {c.get('headamp_records', 0)} < {MIN_HEADAMP_RECORDS}")
    if skipped_generator:
        thin.append("no GENERATED body was round-tripped — every body checked "
                    "was recovered or tag-only, so this run says nothing about "
                    "an emitter building one from a field layout")

    if control:
        print("\nINCONCLUSIVE — the positive control did not fire, so a zero here")
        print("means nothing: the harness could not be shown to detect a difference.")
        for p in control:
            print(f"  {p}")
        return 2
    if facts_tu.returncode != 0 or rep.failures:
        print("\nFAIL")
        return 1
    if thin:
        print("\nINCONCLUSIVE — coverage too thin to call this a pass:")
        for t in thin:
            print(f"  {t}")
        return 2
    print("\nPASS — positive control fired, coverage above the floors,")
    print("       and every field libreac wrote reads back the same way.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
