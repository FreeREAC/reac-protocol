#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Pau Aliagas <linuxnow@gmail.com>
"""Parse the whole capture corpus with the grammar, and refuse a regression.

The captures are a REGRESSION SUITE, not a demonstration. A grammar edit that
makes a new field read correctly on the frames you were looking at, and quietly
stops parsing a capture that used to work, is the easiest defect in this repo to
ship: the unit suite stays green because it runs on the goldens, and the corpus
is a different body of evidence.

So this walks every capture, parses WHOLE frames -- header, control block, audio
region and end marker -- and compares the per-file result against a committed
baseline. Any file that parsed before and does not now is a regression and exits
non-zero. Files that failed before and pass now are reported too, in the other
direction, because that is what an improvement looks like.

    ./corpus-check.py --captures ~/Devel/audio/reac-captures
    ./corpus-check.py --captures DIR --write-baseline corpus-baseline.json
    ./corpus-check.py --captures DIR --ksy /some/other/reac.ksy   # baseline a
                                                                 # different grammar
    ./corpus-check.py --captures DIR --self-test                  # prove it can fail

The corpus is NOT in this repo -- it is FreeREAC's private capture set -- so this
is a dev-only check like `make check-oracle`, and the committed baseline records
the counts rather than the bytes.

TWO TRAPS THIS SCRIPT EXISTS TO AVOID, both hit while writing it:

  * A SNAPLEN-TRUNCATED RECORD IS NOT A SHORT FRAME. Several of these captures
    were taken at snaplen 64/128/200/400, and a truncated frame's length can
    land on 52+36n by coincidence, so it reaches the parser and fails the end
    marker. That produced 3200 "grammar failures" that were nothing of the kind.
    Every pcap record carries both caplen and origlen; compare them.

    But DISCARDING them silently is the second half of the same trap: SEVEN of
    the 72 captures are truncated in every record, so a whole-frame-only check
    reads zero frames from them and calls the corpus clean. A snaplen of 50 or
    more still carries the ENTIRE control block, which is the part this grammar
    mostly describes -- so those records are parsed as a bare frame[16:50]
    typed_block and counted separately. Seven dead files become live coverage,
    and so do 3.3 million truncated records in the other sixty-five.

  * A CHECKER THAT CANNOT FAIL REPORTS SUCCESS OVER ANY GRAMMAR. --self-test
    corrupts a byte of every frame before parsing and requires the run to go
    red. Run it whenever you doubt a clean result.
"""
import argparse
import collections
import glob
import importlib.util
import json
import os
import pathlib
import shutil
import struct
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
DEFAULT_KSY = HERE / "reac.ksy"
DEFAULT_BASELINE = HERE / "corpus-baseline.json"
ETHERTYPE = 0x8819


# --------------------------------------------------------------------------
# pcap reading
# --------------------------------------------------------------------------

PCAP_LE = (b"\xd4\xc3\xb2\xa1", b"\x4d\x3c\xb2\xa1")
PCAP_BE = (b"\xa1\xb2\xc3\xd4", b"\xa1\xb2\x3c\x4d")


def pcap_records(path):
    """Yield (data, truncated) for each record. `truncated` means the capture
    kept fewer bytes than the wire carried, which is a property of the CAPTURE
    and never of the frame."""
    with open(path, "rb") as f:
        head = f.read(24)
        if len(head) < 24:
            return
        magic = head[:4]
        if magic in PCAP_LE:
            end = "<"
        elif magic in PCAP_BE:
            end = ">"
        elif magic == b"\x0a\x0d\x0d\x0a":
            raise RuntimeError("pcapng is not handled")
        else:
            raise RuntimeError("not a pcap (magic %r)" % magic)
        linktype = struct.unpack(end + "I", head[20:24])[0]
        if linktype != 1:
            raise RuntimeError("linktype %d is not Ethernet" % linktype)
        while True:
            rec = f.read(16)
            if len(rec) < 16:
                return
            _, _, caplen, origlen = struct.unpack(end + "IIII", rec)
            data = f.read(caplen)
            if len(data) < caplen:
                return
            yield data, caplen < origlen


# --------------------------------------------------------------------------
# the grammar under test
# --------------------------------------------------------------------------

def build_parser(ksy_path, outdir):
    ksc = os.environ.get("KSC", "kaitai-struct-compiler")
    if not shutil.which(ksc):
        sys.exit("kaitai-struct-compiler not found; see spec/Makefile ksc-help")
    subprocess.run([ksc, "-t", "python", "--outdir", str(outdir), str(ksy_path)],
                   check=True)
    module = outdir / "reac.py"
    if not module.exists():
        sys.exit("ksc produced no reac.py from %s" % ksy_path)
    spec = importlib.util.spec_from_file_location("reac_under_test", module)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


LEGACY_NAMES = {0: "none", 1: "filler", 2: "scene_transfer", 3: "master_hb",
                4: "master_announce", 5: "grant", 6: "head_amp", 7: "box_hb",
                8: "unknown_ctrl", 9: "config_announce", 10: "group_map",
                11: "record_fragment", 12: "link2"}


def legacy_ctrl_kind(b):
    """reac_ctrl_parse() as it stood before 2026-08-23, over frame[16:50].

    Keyed on the 16-bit op and on TWO LENGTHS, which is the defect: everything
    on the session link that was not the slot map or the link ack fell into
    scene_transfer. Kept here as the left-hand side of the partition proof."""
    t0, t1 = b[0], b[1]
    op = (b[2] << 8) | b[3]
    rec_len = (b[4] << 8) | b[5]
    if (t0, t1) == (0x00, 0x00):
        return 1
    if (t0, t1) == (0xcf, 0xea):
        return 4
    if (t0, t1) != (0xcd, 0xea):
        return 8
    if op == 0x0403:
        if b[16] == 0x12 and b[17] == 0x12 and b[18] == 0x01 and b[19] == 0x01:
            return 6
        return 5
    if op == 0x0103 and rec_len == 0x0019:
        return 3
    if op == 0x0103 and rec_len == 0x0001:
        return 7
    if op >> 8 == 0x01:
        return 2
    return 8


def exercise(frame, reac, kaitai):
    """Parse one frame and TOUCH the lazy instances.

    Kaitai defers `instances`, so a parse that never reads them proves only that
    the `seq` fits. Everything reachable is forced here on purpose."""
    f = reac.Reac(kaitai.KaitaiStream(kaitai.BytesIO(frame)))
    _ = f.raw_len, f.num_channels, f.len_audio
    t = f.control
    _ = t.ctrl_kind, t.op_raw, t.op_len_raw, t.block_checksum
    block = t.block
    for name in ("link", "seg", "seg_kind", "seg_is_first", "seg_is_last",
                 "opcode", "op", "op_len"):
        if hasattr(block, name):
            getattr(block, name)
    payload = getattr(block, "payload", None)
    if payload is not None:
        if hasattr(payload, "page"):
            page = payload.page
            _ = payload.subtype, payload.page_kind
            if hasattr(page, "entries"):
                for e in page.entries:
                    _ = e.slot, e.cell_type, e.is_group_anchor
                    for extra in ("value", "flags", "is_identity_record"):
                        if hasattr(e, extra):
                            getattr(e, extra)
            if hasattr(page, "group_bytes"):
                _ = page.group_bytes
            if hasattr(page, "declared_in_channels"):
                _ = page.declared_in_channels, page.declared_out_channels
        if hasattr(payload, "body"):
            _ = payload.body
        if hasattr(payload, "fragment"):
            _ = payload.len_echo, payload.fragment
    _ = f.audio
    return f


def exercise_block(window, reac, kaitai):
    """Parse a bare frame[16:50] -- the type word plus the control block.

    This is what survives a snaplen of 50 or more, and it is the same type the
    C goldens are stored as, so a truncated capture still exercises the whole
    control multiplex."""
    t = reac.Reac.TypedBlock(kaitai.KaitaiStream(kaitai.BytesIO(window)))
    _ = t.ctrl_kind, t.op_raw, t.op_len_raw, t.block_checksum
    block = t.block
    for name in ("link", "seg", "seg_kind", "seg_is_first", "seg_is_last",
                 "opcode", "op", "op_len"):
        if hasattr(block, name):
            getattr(block, name)
    payload = getattr(block, "payload", None)
    if payload is not None:
        if hasattr(payload, "page"):
            page = payload.page
            _ = payload.subtype, payload.page_kind
            if hasattr(page, "entries"):
                for e in page.entries:
                    _ = e.slot, e.cell_type, e.is_group_anchor
                    for extra in ("value", "flags", "is_identity_record"):
                        if hasattr(e, extra):
                            getattr(e, extra)
            if hasattr(page, "group_bytes"):
                _ = page.group_bytes
            if hasattr(page, "declared_in_channels"):
                _ = page.declared_in_channels, page.declared_out_channels
        if hasattr(payload, "body"):
            _ = payload.body
        if hasattr(payload, "fragment"):
            _ = payload.len_echo, payload.fragment
    return t


def scan_file(path, reac, kaitai, per_file, corrupt, moves=None):
    seen = truncated = off_law = ok = 0
    blocks = blocks_ok = 0
    errors = collections.Counter()
    lengths = collections.Counter()
    for data, was_truncated in pcap_records(path):
        if was_truncated:
            truncated += 1
            # The control block survives any snaplen of 50 or more.
            if len(data) >= 50 and struct.unpack(">H", data[12:14])[0] == ETHERTYPE:
                if per_file and blocks >= per_file:
                    continue
                window = data[16:50]
                if corrupt:
                    # NOT a byte flip: an unknown type word is TOLERATED by the
                    # grammar (the switch has no default and the block falls
                    # through as raw bytes), so flipping one proved nothing and
                    # the block path reported 44400 clean under corruption.
                    # A short window cannot be tolerated by anything.
                    window = window[:30]
                blocks += 1
                try:
                    tb = exercise_block(window, reac, kaitai)
                    blocks_ok += 1
                    if moves is not None and not corrupt:
                        moves[(legacy_ctrl_kind(window), int(tb.ctrl_kind))] += 1
                except Exception as exc:
                    errors["block %s: %s" % (type(exc).__name__, str(exc)[:70])] += 1
            continue
        if len(data) < 52 or struct.unpack(">H", data[12:14])[0] != ETHERTYPE:
            continue
        n = len(data)
        # THIS SCRIPT IS THE CAPTURE READER, and this is the only place the +2
        # is handled. A mirrored/trunked tap leaves two bytes of the frame's own
        # Ethernet FCS after the end marker; the grammar models a REAC frame and
        # refuses a buffer carrying them (it has no residue vocabulary at all,
        # since 2026-09-21), so a reader that skipped this line would file every
        # mirrored frame as a grammar failure. libreac's ingest does the same
        # thing in the same place — reac_frame_clean_len().
        if (n - 52) % 36 == 2:
            data, n = data[:n - 2], n - 2
        if (n - 52) % 36 != 0:
            off_law += 1
            continue
        seen += 1
        if corrupt:                     # --self-test: break the end marker
            data = bytearray(data)
            data[-1] ^= 0xFF
            data = bytes(data)
        try:
            f = exercise(data, reac, kaitai)
            ok += 1
            lengths[n] += 1
            if moves is not None:
                w = data[16:50]
                moves[(legacy_ctrl_kind(w), int(f.control.ctrl_kind))] += 1
        except Exception as exc:
            errors["%s: %s" % (type(exc).__name__, str(exc)[:80])] += 1
        if per_file and seen >= per_file and (not truncated or blocks >= per_file):
            break
    return {
        "frames": seen,
        "ok": ok,
        "failed": seen - ok,
        "blocks": blocks,
        "blocks_ok": blocks_ok,
        "blocks_failed": blocks - blocks_ok,
        "truncated_records": truncated,
        "off_length_law": off_law,
        "lengths": dict(sorted(lengths.items())),
        "errors": dict(errors.most_common(3)),
    }


# --------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--captures", required=True,
                    help="directory holding the .pcap corpus (searched recursively)")
    ap.add_argument("--ksy", default=str(DEFAULT_KSY),
                    help="grammar to test; point it at an older copy to baseline")
    # NO CAP. The cap existed because the corpus was 47.9 GB and reading all of
    # it through this parser was not affordable; it read the HEAD of every
    # capture, which is the establish handshake, and never reached the steady
    # state or the scene push behind it. The corpus is now distilled to 666 MB
    # and an uncapped run takes about a minute, so the reason for the cap is
    # gone. Keep it at 0: a cap silently turns "the corpus parses" into "the
    # first 4000 frames parse".
    ap.add_argument("--per-file", type=int, default=0,
                    help="cap frames read per capture (0 = every frame)")
    ap.add_argument("--baseline", default=str(DEFAULT_BASELINE))
    ap.add_argument("--write-baseline", metavar="PATH",
                    help="record this run as the baseline instead of comparing")
    ap.add_argument("--self-test", action="store_true",
                    help="corrupt every frame; the run MUST go red")
    ap.add_argument("--quiet", action="store_true",
                    help="only print the summary and any regression")
    ap.add_argument("--classify-delta", action="store_true",
                    help="tabulate ctrl_kind under the pre-2026-08-23 rule "
                         "against the current one, and require the difference "
                         "to be a PARTITION of the old buckets")
    args = ap.parse_args()

    # *.pcap* and not *.pcap: tcpdump -C splits a capture into .pcap00,
    # .pcap01 ... and eleven of this corpus's files are split that way. A glob
    # of "*.pcap" silently covered 72 of 83 files, and the eleven it dropped
    # were the longest sessions in the set.
    caps = sorted(glob.glob(os.path.join(os.path.expanduser(args.captures),
                                         "**", "*.pcap*"), recursive=True))
    if not caps:
        sys.exit("no .pcap under %s -- an empty corpus proves nothing" % args.captures)

    import kaitaistruct
    with tempfile.TemporaryDirectory() as tmp:
        reac = build_parser(pathlib.Path(args.ksy), pathlib.Path(tmp))
        results = {}
        moves = collections.Counter() if args.classify_delta else None
        for path in caps:
            name = os.path.relpath(path, os.path.expanduser(args.captures))
            try:
                results[name] = scan_file(path, reac, kaitaistruct,
                                          args.per_file, args.self_test, moves)
            except Exception as exc:
                results[name] = {"frames": 0, "ok": 0, "failed": 0,
                                 "blocks": 0, "blocks_ok": 0, "blocks_failed": 0,
                                 "unreadable": str(exc)}

    total_frames = sum(r["frames"] for r in results.values())
    total_ok = sum(r["ok"] for r in results.values())
    total_failed = sum(r["failed"] for r in results.values())
    total_blocks = sum(r["blocks"] for r in results.values())
    total_blocks_ok = sum(r["blocks_ok"] for r in results.values())
    total_blocks_failed = sum(r["blocks_failed"] for r in results.values())
    files_clean = sum(1 for r in results.values()
                      if (r["frames"] or r["blocks"])
                      and not r["failed"] and not r["blocks_failed"])
    files_silent = [n for n, r in results.items()
                    if not r["frames"] and not r["blocks"]]

    if not args.quiet:
        print("%-56s %8s %7s %6s %9s %6s"
              % ("capture", "frames", "ok", "fail", "blocks", "fail"))
        for name, r in results.items():
            flag = "" if not (r["failed"] or r["blocks_failed"]) else "  <-- FAILURES"
            print("%-56s %8d %7d %6d %9d %6d%s"
                  % (name[-56:], r["frames"], r["ok"], r["failed"],
                     r["blocks"], r["blocks_failed"], flag))
            for e, n in r.get("errors", {}).items():
                print("%-56s        x%-6d %s" % ("", n, e))

    print("\n%d captures: %d whole frames (%d ok, %d failed), "
          "%d truncated control blocks (%d ok, %d failed), %d files fully clean"
          % (len(results), total_frames, total_ok, total_failed,
             total_blocks, total_blocks_ok, total_blocks_failed, files_clean))
    for n in files_silent:
        print("SILENT     %s contributed NOTHING -- it covers no grammar at all" % n)

    # A clean result is only meaningful if the scan actually read something.
    if total_frames + total_blocks == 0:
        sys.exit("the scan read ZERO frames -- a zero failure count is meaningless")

    if args.classify_delta:
        print("\nctrl_kind under the OLD rule -> under the CURRENT rule:")
        split, stayed, sideways = collections.Counter(), 0, []
        for (was, now), n in sorted(moves.items()):
            tag = "" if was == now else "   MOVED"
            print("   %-16s -> %-16s %10d%s"
                  % (LEGACY_NAMES[was], LEGACY_NAMES[now], n, tag))
            if was == now:
                stayed += n
            else:
                split[was] += n
                if was not in (2, 8):
                    sideways.append((was, now, n))
        # A reclassification must SPLIT old buckets, never move between them.
        for was, now, n in sideways:
            print("SIDEWAYS   %s -> %s (%d) came out of a bucket that is not "
                  "being split" % (LEGACY_NAMES[was], LEGACY_NAMES[now], n))
        if sideways:
            print("\nthe change is not a partition of the old classification")
            return 1
        if not split:
            print("\nNOTHING MOVED -- the two rules are identical here, so this "
                  "comparison observed nothing")
            return 1
        print("\npartition holds: %d frames unchanged, %d split out of "
              "scene_transfer/unknown_ctrl, nothing moved sideways"
              % (stayed, sum(split.values())))
        return 0

    if args.self_test:
        # Both paths must be shown capable of failing, independently. A
        # self-test that only exercises one of them leaves the other unproven.
        bad = []
        if total_frames and total_failed != total_frames:
            bad.append("whole-frame path: %d of %d corrupted frames still parsed"
                       % (total_frames - total_failed, total_frames))
        if total_blocks and total_blocks_failed != total_blocks:
            bad.append("control-block path: %d of %d corrupted blocks still parsed"
                       % (total_blocks - total_blocks_failed, total_blocks))
        if bad:
            print("SELF-TEST FAILED -- the checker cannot detect a broken grammar:")
            for line in bad:
                print("   " + line)
            return 2
        print("self-test ok: %d corrupted frames and %d corrupted control blocks "
              "were ALL rejected" % (total_failed, total_blocks_failed))
        return 0

    if args.write_baseline:
        payload = {"per_file": args.per_file,
                   "captures": len(results),
                   "files": {k: {"frames": v["frames"], "ok": v["ok"],
                                 "failed": v["failed"], "blocks": v["blocks"],
                                 "blocks_ok": v["blocks_ok"],
                                 "blocks_failed": v["blocks_failed"]}
                             for k, v in results.items()}}
        pathlib.Path(args.write_baseline).write_text(
            json.dumps(payload, indent=1, sort_keys=True) + "\n")
        print("baseline written to %s" % args.write_baseline)
        return 0

    base_path = pathlib.Path(args.baseline)
    if not base_path.exists():
        print("no baseline at %s -- run with --write-baseline first" % base_path)
        return 0
    base = json.loads(base_path.read_text())
    if base["per_file"] != args.per_file:
        sys.exit("baseline was taken at --per-file %d, this run used %d; "
                 "the counts are not comparable"
                 % (base["per_file"], args.per_file))

    regressions, improvements, missing = [], [], []
    for name, was in base["files"].items():
        now = results.get(name)
        if now is None:
            missing.append(name)
            continue
        if (now["ok"] < was["ok"] or now["failed"] > was["failed"]
                or now["blocks_ok"] < was.get("blocks_ok", 0)
                or now["blocks_failed"] > was.get("blocks_failed", 0)):
            regressions.append((name, was, now))
        elif (now["ok"] > was["ok"] or now["failed"] < was["failed"]
              or now["blocks_ok"] > was.get("blocks_ok", 0)):
            improvements.append((name, was, now))
    added = [n for n in results if n not in base["files"]]

    for name, was, now in improvements:
        print("IMPROVED   %s: frames ok %d -> %d, failed %d -> %d; blocks ok %d -> %d"
              % (name, was["ok"], now["ok"], was["failed"], now["failed"],
                 was.get("blocks_ok", 0), now["blocks_ok"]))
    for name in added:
        print("NEW FILE   %s (not in the baseline)" % name)
    for name in missing:
        print("MISSING    %s was in the baseline and is not in the corpus" % name)
    for name, was, now in regressions:
        print("REGRESSION %s: frames ok %d -> %d, failed %d -> %d; "
              "blocks ok %d -> %d, failed %d -> %d"
              % (name, was["ok"], now["ok"], was["failed"], now["failed"],
                 was.get("blocks_ok", 0), now["blocks_ok"],
                 was.get("blocks_failed", 0), now["blocks_failed"]))
        for e, n in results[name].get("errors", {}).items():
            print("             x%-6d %s" % (n, e))

    if regressions:
        print("\n%d capture(s) regressed. The corpus is a regression suite: a "
              "capture that parsed before must parse now." % len(regressions))
        return 1
    print("\nno regressions against %s (%d captures, %d improved)"
          % (base_path.name, len(base["files"]), len(improvements)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
