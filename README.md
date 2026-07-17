# reac-protocol

The **REAC protocol reference** — an independent, interoperability-oriented
description of Roland's REAC (Roland Ethernet Audio Communication), the proprietary
Layer-2 audio-over-Ethernet transport (EtherType `0x8819`) used by Roland's
V-Mixer / M-series consoles and their stageboxes.

Part of [FreeREAC](https://github.com/FreeREAC) — *REAC Exposed Audio
Communications*.

> This is **not** official Roland documentation. REAC is a Roland trademark; this is
> an independent reference derived from our own packet captures, from GPL-licensed
> open-source reverse-engineering projects, and from a reverse-engineering pass on
> console firmware — all **re-expressed in our own words and tables**. No Roland
> binaries, symbols, or disassembly listings are reproduced. Reverse engineering for
> interoperability is permitted and protocol interfaces are not copyrightable.
> *(Not legal advice.)*

## Documents

- **[wire-format.md](wire-format.md)** — the wire-format reference: frame geometry,
  the sequence counter, roles and addressing, the frame-type registry, the CONTROL
  checksum, audio de-interleave, sample rates, clocking, the connection handshakes,
  **head-amp source control** (op `04 03` tagged records — phantom / pad / SENS, the
  pad-relative dB law, the per-model channel base, and the two nested checksums), and
  the **state-assertion model** (the master's declarative, DMX-style periodic
  re-assert of the whole console state) with a full connection-lifecycle state diagram.
- **[capturing.md](capturing.md)** — how to capture and decode REAC yourself: the
  raw socket / tcpdump filter, frame validation, de-interleave, rate sanity-checks,
  and the traps (VLAN tags, level correctness).
- **[firmware-findings.md](firmware-findings.md)** — device behaviour derived from
  firmware RE and live-hardware observation, re-expressed: on-rig verification,
  slave establishment, the AES/EBU crossbar, the remote-control (RCP) command
  surface, and bidirectional-TX feasibility.

## Status tags

Facts are tagged by provenance:

- **[V]** verified on our own captures
- **[S]** from an upstream open-source RE codebase
- **[?]** inferred or pending live confirmation

## Sources

Derived from packet captures plus three GPL-3.0 reverse-engineered codebases
(`per-gron/reacdriver`, `norihiro/obs-h8819-source`, `norihiro/reaccapture`), our
own decoder, and re-expressed firmware findings. The raw working material the
reference is distilled from lives in
[reac-lab](https://github.com/FreeREAC/reac-lab); tools to capture and analyse REAC
are in the [reac-tools](https://github.com/FreeREAC) and
[reac-aes67](https://github.com/FreeREAC) repos.

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).
