# reac-protocol

The **REAC protocol reference** — an independent, interoperability-oriented
description of Roland's REAC (Roland Ethernet Audio Communication), the proprietary
Layer-2 audio-over-Ethernet transport (EtherType `0x8819`) used by Roland's
V-Mixer / M-series consoles and their stageboxes.

Part of [FreeREAC](https://github.com/FreeREAC) — *REAC Exposed Audio
Communications*.

> This is **not** official Roland documentation. REAC is a Roland trademark; this is
> an independent reference, re-expressed in original words and tables from packet
> captures, GPL-licensed open-source reverse-engineering projects, and a
> reverse-engineering pass on console firmware. No Roland binaries, symbols, or
> disassembly listings are reproduced. Reverse engineering for interoperability is
> permitted and protocol interfaces are not copyrightable. *(Not legal advice.)*

## Documents

- **[docs/mixer-protocol.md](docs/mixer-protocol.md)** — how a Roland console and a
  stagebox talk to each other, master side first: the frame and its cadence, roles,
  enrolment, head-amp control, the scene transfer and chanmap, trunk VLANs, a box on
  M, and a table of every control-block kind by its two-byte tag.
- **[spec/reac.ksy](spec/reac.ksy)** — the wire format as a **machine-checkable
  [Kaitai Struct](https://kaitai.io) grammar**: the `0x8819` frame family in both
  directions, the control multiplex, the `op 04 03` DT1 record container, the two
  nested checksums, and the audio region described structurally. The prose in this
  reference is the readable rendering of the same facts.
- **[wire-format.md](wire-format.md)** — the wire-format reference: frame geometry,
  the sequence counter, roles and addressing, the frame-type registry, the CONTROL
  checksum, audio de-interleave, sample rates, clocking, the connection handshakes,
  **head-amp source control** (op `04 03` tagged records wrapping a **Roland DT1
  SysEx** — phantom / pad / SENS, the pad-relative dB law, the per-model channel base,
  and the two nested checksums), and the **state-assertion model** (the master's
  declarative, DMX-style periodic re-assert of the whole console state) with a full
  connection-lifecycle state diagram.
- **[spec/protocol-facts.yaml](spec/protocol-facts.yaml)** — the constants the grammar
  and libreac each need, written once: frame geometry, the scene transfer, the tags
  the box validates, both checksum rules, the op codes and sub-page selectors, and
  the three head-amp granularities.
- **[firmware-protocol.md](firmware-protocol.md)** — the protocol as the device
  firmware states it, rather than as the wire shows it: the class names the images
  carry, the message inventory in the receive dispatch (including arms not seen on
  the wire), the box state machine with its failure edges, the struct layouts and
  every indexing shift as a granularity fact.
- **[capturing.md](capturing.md)** — how to capture and decode REAC: the raw socket /
  tcpdump filter, frame validation, de-interleave, rate sanity-checks, and the traps
  (VLAN tags, level correctness).
- **[firmware-findings.md](firmware-findings.md)** — device behaviour derived from
  firmware reverse-engineering and live-hardware observation: on-rig verification of
  the wire spec, slave establishment, the head-amp commit model (what arms a
  channel), the AES/EBU crossbar, the remote-control (RCP) command surface, and
  bidirectional-TX feasibility. Its final section goes source-level: the M-300 /
  S-1608 connection engine — function map, the master FSMs, the box FSM, and the
  wire-level signature of each phase.

## Sources

Derived from packet captures, three GPL-3.0 reverse-engineered codebases
(`per-gron/reacdriver`, `norihiro/obs-h8819-source`, `norihiro/reaccapture`), an
independent decoder, and a reverse-engineering pass on console and stagebox
firmware. Tools to capture and analyse REAC are in the
[reac-tools](https://github.com/FreeREAC) and
[reac-aes67](https://github.com/FreeREAC) repos.

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).
