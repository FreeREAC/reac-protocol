# SPDX-License-Identifier: GPL-3.0-or-later
"""A SYNTHETIC scene body, built field by field from the `scene_body` layout in reac.ksy.

The recovered desk bodies are vendor captures and live in freereac-ops (tools/freereac_ops.py
resolves them; the tests that need their exact bytes skip as OPS-ABSENT without it). The public
tests parse this instead. It is not a desk's body and does not try to be: every field the
grammar names carries a value chosen so that a field read at the wrong offset, at the wrong
width or in the wrong byte order reads something else, and every unnamed byte carries a pattern
that is never a tag. Only the three tags and the arithmetic are the format's own.
"""
import struct

SIZE = 0x37c + 8 + 800 * 10 + 4          # SCEN's own arithmetic: 8904
CHUNK, HEAD = 26, 24                     # the transfer: body_head, then 26-byte chunks
TAGS = {0x000: b"1234", 0x368: b"SYSP", 0x37c: b"SCEN"}
# twelve inventory cells of four records each, as the commit walks them (inventory_cell enum)
CELLS = (2, 2, 2, 2, 0, 1, 2, 3, 2, 3, 2, 3)
MASTER_ID = bytes.fromhex("020000c0ffee")   # locally administered, no vendor OUI
FIELDS = dict(unit_map_select=0x0201, map_a_arg=0x0908, sysp_version=0x1312, sysp_key=0x1514,
              sysp_flag=0x16, scen_version=0x2322, scen_key=0x2524)


def filler(off, n):
    """Bytes for an unnamed run at <off>: offset-derived, never 0, never ASCII letters."""
    return bytes(0x80 | ((off + i) * 7 & 0x7f) for i in range(n))


def record(cell, k):
    """A 10-byte scene_record whose four fields name their own index <k>."""
    return struct.pack("<5H", cell, 0x1000 | k, 0x2000 | k, 0x3000 | k, 0x4000 | k)


def slot_cell(k):
    return CELLS[k // 4] if k < 4 * len(CELLS) else 3


def build(revision=0, master_id=MASTER_ID):
    b = bytearray()

    def run(n):
        b.extend(filler(len(b), n))

    b += b"1234"
    b += struct.pack("<H", FIELDS["unit_map_select"])
    run(2)                                                     # reserved_06
    b += struct.pack("<H", FIELDS["map_a_arg"])
    run(10)                                                    # unknown_0a
    b += struct.pack("<H", revision)                           # +0x14
    run(4)                                                     # reserved_16
    for k in range(80):                                        # slots, +0x1a
        b += record(slot_cell(k), k)
    run(6)                                                     # reserved_33a
    assert len(b) == 0x340
    b += master_id
    run(4)
    b += bytes.fromhex("02000000aa01")                         # peer_id_1
    run(4)
    b += bytes.fromhex("02000000bb02")                         # peer_id_2
    run(14)                                                    # map_b
    assert len(b) == 0x368
    b += b"SYSP" + struct.pack("<HHB", FIELDS["sysp_version"], FIELDS["sysp_key"],
                               FIELDS["sysp_flag"])
    run(11)
    assert len(b) == 0x37c
    b += b"SCEN" + struct.pack("<HH", FIELDS["scen_version"], FIELDS["scen_key"])
    for k in range(800):
        b += record(k % 4, k)
    run(4)                                                     # trailer
    assert len(b) == SIZE
    return bytes(b)


def transfer(body):
    """The body as the three scene ops carry it: (body_head, [chunks], final chunk)."""
    n = (len(body) - HEAD) // CHUNK
    chunks = [body[HEAD + CHUNK * k:HEAD + CHUNK * (k + 1)] for k in range(n)]
    return body[:HEAD], chunks, body[HEAD + CHUNK * n:]
