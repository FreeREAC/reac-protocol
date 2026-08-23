# The protocol as the firmware states it

`wire-format.md` describes REAC as it appears on the wire. This document describes it as the
**device firmware itself states it**: the classes the code is built out of, the messages its
receive dispatch will accept, the state machine that accepts them, and the table layouts it
reads and writes. A capture can only show what somebody happened to send. A dispatch arm is
the protocol's own inventory, and it lists messages nobody on this rig has ever sent.

Every row carries a **provenance**: the image, the function symbol, and the address. A claim
without one does not belong here.

Every row also carries a **corroboration** state, and the two are deliberately separate:

| tag | meaning |
|---|---|
| **CORROBORATED** | the firmware handles it AND the capture corpus contains it |
| **FIRMWARE-ONLY** | the firmware handles it and no capture in the corpus has ever carried it — a capability we did not know we had |
| **CORPUS-ONLY** | seen on the wire, no handler located in any image we hold |

## The images

| device | role | image | board | version | REAC control plane recovered? |
|---|---|---|---|---|---|
| S-1608 | 16-in stagebox | `S-1608.BIN`, 546688 B, SH-4 LE, image base `0x0BFE0000` | ECM42 | `s1608_sys_ver2200`, boot banner `ECM42 BOOT Ver.2.200 02/19/2010 09:30:00` | **yes — the reference box image** |
| S-4000S | 32-in stagebox | `S-4000.BIN`, 497152 B, SH-4 LE | ECM25 | `s4000_sys_ver2500`, `ECM25 BOOT Ver.2.500 01/31/2012 10:30:00` | yes |
| S-0808 | 8-in stagebox | `S-0808.BIN`, 524288 B | ECM52 | `s0808_sys_v1003`, banner `Digital Snake(S-0808) Boot Setup Menu` | **no** — the image is packed differently; it carries ZERO `C[A-Z]…` class strings against the others' 100 and 104, and no decompile exists, so nothing below is read out of it |

The image spans `0x0BFE0000`..`0x0C065780`. Addresses above that — `0x0c08xxxx` vtables,
`0x0c0cxxxx` state tables, `0x0c12xxxx` class flags — are RAM, and are only ever reached
through a pointer stored in the image.

## The names are the firmware's own

The S-1608 and S-4000S images carry a class registry in `.rodata`. Each record is 16 bytes,
and what is READ OUT of it is: word 0 is the constant `0x0c036510` on every record, word 1 is
a pointer to a plain-ASCII class name inside the image, word 2 is a distinct RAM address that
increments by one per consecutive record, and word 3 is a RAM address above the image end.
The reading of words 2 and 3 as a per-class flag byte and a vtable is INFERRED from that
shape; only the names are read. That is enough, because **the protocol's own vocabulary
survives in the binary** and nothing below needs an invented name. The S-1608 and S-4000S
sets are identical but for four AES/EBU classes only the S-4000S carries.

The records carry no resolvable base-class pointer, so the hierarchies below are INFERRED
from the names and from the records' adjacency, not read from a type descriptor.

| firmware name | registry record | name string | what it is |
|---|---|---|---|
| `CReacMsgParser` | `0x0c035474` | `0x0c033d84` | the REAC receive dispatch, base class |
| `CMasterReacMsgParser` | `0x0c035484` | `0x0c033d94` | the dispatch in MASTER role |
| `CSlave1ReacMsgParser` | `0x0c035494` | `0x0c033dac` | the dispatch in SLAVE role — the role a stagebox runs |
| `CMsgParser` | `0x0c0353d8` | `0x0c033d1c` | parser base above both |
| `CReacMsg` | `0x0c034b9c` | `0x0c032c18` | a REAC control message |
| `CReacRecMsg` | `0x0c034bac` | `0x0c032c24` | a REAC **record** message — the `op 0403` DT1 container |
| `CLinkCheckMsg` | `0x0c034f70` | `0x0c032f5c` | the link check — the heartbeat both directions carry |
| `CDevInfoMsg` | `0x0c035358` | `0x0c033ca8` | the device-info message — the box's own declaration |
| `CReacTDataMsg` | `0x0c035218` | `0x0c033b74` | transfer-data message |
| `CReacTDataKikiMsg` | `0x0c034df8` | `0x0c032e3c` | transfer-data, **kiki** (機器, "equipment") — the per-device variant |
| `CReacTDataRecMsg` | `0x0c034ea8` | `0x0c032ed4` | transfer-data carrying records |
| `CReacTDataPrgTxMsg` | `0x0c035248` | `0x0c033bac` | transfer-data carrying a **program** (firmware) transmit |
| `CReacTDataMsgOverGData` | `0x0c035258` | `0x0c033bc0` | transfer-data layered over "GData" |
| `CReacTDataRecMsgOverGData` | `0x0c035268` | `0x0c033bd8` | as above, records |
| `CReacPrgMsg` / `CReacPrgMsgIF` | `0x0c035180` / `0x0c034de8` | `0x0c033b10` / `0x0c032e2c` | REAC **program update** message and its interface |
| `CTDataParser` | `0x0c034e08` | `0x0c032e50` | transfer-data parser base |
| `CTDataKikiMsgParser` | — | `0x0c032e60` | device-variant parser |
| `CSplitTDataKikiMsgParser` | — | `0x0c032e74` | the same parser in **split** role |
| `CTDataRecMsgParser` | — | `0x0c032e90` | record parser |
| `CTDataPrgMsgParser` | — | `0x0c032ea4` | program-update parser |
| `CDataBitMap` | `0x0c034ec4` | `0x0c032ee8` | a bitmap — the per-slot present bits are one |
| `CMacAdrs` | `0x0c035028` | `0x0c0330ec` | a MAC address |
| `CMsgBase` | many | `0x0c032cc4` | message base class |

Three things follow from the names alone, before a single function is read.

**REAC has three roles, not two.** `CReacMsgParser` has exactly two subclasses in a stagebox
image — `CMasterReacMsgParser` and `CSlave1ReacMsgParser` — and the serial-side family beside
it has three: `CMasterSciMsgParser`, `CSlave1SciMsgParser`, `CSplitSciMsgParser`. `Split` is a
first-class role in the firmware's own vocabulary, and `Slave1` is numbered, which is what a
protocol that expects a `Slave2` looks like.

**A stagebox carries the MASTER parser too.** `CMasterReacMsgParser` is present in the S-1608
and S-4000S images. Whatever else that means, the master side of this protocol is not absent
from the box.

**Firmware update travels over REAC.** `CReacPrgMsg`, `CReacPrgMsgIF`, `CTDataPrgMsgParser`
and `CReacTDataPrgTxMsg` are a program-transport family, and the S-4000S boot menu spells it
out in plain text: `2. REAC Program update(XMODEM)` and `6. REAC Program update(MIDI)`. None
of it appears in any capture we hold.

Other firmware-carried strings worth having in one place: the RTOS task and mailbox names
`REAC TData Tx Task`, `REAC TD Tx MailBox`, `ADBoard Tx MailBox`, `Remote-RX Task`,
`Remote-TX Task`, `RemoteUpdate Task`, `Genarate-RX Task`, `Genarate-TX Task` (the
misspelling is the firmware's); the version probe `REAC version: ` with its failure line
`REAC version: Can't find version info.`; and the manufacturer banner `REAC - Roland ED`.

The scene body's three ASCII tags are literals in the box image as well as on the wire:
`1234` at file `0x523fc`, `SYSP` at `0x52764`, `SCEN` at `0x52df8` — which is the box side of
the three-tag gate `wire-format.md` describes.

## Corroboration — what the corpus actually carries

Counted over every `.pcap` in the FreeREAC capture corpus — 72 files, 43 018 309 frames, of
which 43 018 308 are REAC: 6 907 318 control frames and 36 110 990 FILLER. Keyed on
`(type word, op, op_len, block[4])`. Those totals are the positive control: a zero in this
table is a real zero and not a scan that could not match.

| type | op | op_len | block[4] | frames | files |
|---|---|---|---|---|---|
| `cdea` | `0100` | `001a` | `00` | 772 556 | 41 |
| `cdea` | `0101` | `0018` | `00` | 2 211 | 41 |
| `cdea` | `0102` | `000e` | `00` | 2 269 | 41 |
| `cdea` | `0103` | `0001` | `81` | 10 217 | 57 |
| `cdea` | `0103` | `000d` | `10` | 103 | 21 |
| `cdea` | `0103` | `0010` | `82` | 259 | 20 |
| `cdea` | `0103` | `0010` | `84` | 44 | 14 |
| `cdea` | `0103` | `0019` | `01` | 22 984 | 70 |
| `cdea` | `0103` | `001a` | `00` | 2 | 2 |
| `cdea` | `0401` | `001b` | `00` | 18 | 9 |
| `cdea` | `0402` | `000d` | `00` | 18 | 9 |
| `cdea` | `0403` | `0013` | `00` | 11 042 | 45 |
| `cdea` | `0403` | `0014` | `00` | 3 044 | 43 |
| `cdea` | `0403` | `0014` | `02` | 6 053 140 | 1 |
| `cdea` | `0403` | `0016` | `00` | 272 | 30 |
| `cdea` | `0403` | `001a` | `00` | 272 | 30 |
| `cfea` | `0000` | `0000` | `00` | 30 | 1 |
| `cfea` | `ffff` | `0100` | `01` | 28 837 | 69 |

Three rows are worth reading twice.

`cdea 0403 0014` with `block[4] == 0x02` — the box's constant upstream return block — is 88% of
all control traffic in the corpus and comes from ONE session. It is a single distinct 32-byte
block repeated six million times. Nothing in either box image has been shown to read it.

`cdea 0103 001a` appears twice in the whole corpus, in two `reacpw-…` captures. That is our own
master emitting an `op_len` no console sends and no page in the grammar claims.

`cfea 0000 0000` with an all-zero block appears 30 times in one capture: an announce type word
carrying no op at all.
