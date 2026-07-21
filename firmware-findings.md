# REAC firmware-derived findings

Device **behaviour** — distinct in provenance from the wire schema in
[wire-format.md](wire-format.md). These restate, in our own words and tables,
behaviours derived from a reverse-engineering pass on Roland console firmware and from
on-rig observation of live M-5000 hardware. **No Roland binaries, symbols, or
disassembly listings are reproduced.** Status tags as in the wire-format doc.

**Why the firmware only shows connection logic. [S]** On these devices the wire
framing and the sample clock live in an **on-board FPGA**, not in the device CPU.
The `0x8819` Ethernet framing, the per-frame counter,
the per-frame sample tick, and the link-check counter are all FPGA-generated; the CPU
is handed already-parsed control messages and runs the high-level connection state
machine on top. So a firmware RE pass yields the **connection behaviour** below — join,
hold, drop, channel-map negotiation — but never the frame builder or the clock
recovery, which is why those facts have to come from on-wire capture instead.

## On-rig verification of the wire spec (live M-5000 master) [V]

Forward broadcast control frames captured from both REAC ports of an M-5000 master
confirm the schema on live hardware:

- **MASTER_ANNOUNCE (`cf ea`):** `unknown1 = ff ff 01 00 01 03 0d 01 04`; the MAC at
  `data[9..14]` is the master's interface MAC (OUI `00:40:ab`), the two ports
  differing only in the low bits of the last octet (= REAC port index); `inChannels`
  `data[15] = 0x28` (= 40); `outChannels` `data[16] = 0x10` (16) on one port vs `0x08`
  (8) on the other (the larger is the doubled split form); `unknown2 = 01 00 01 00`.
  The announce is constant per port, so its checksum is constant.
- **CONTROL channel-info (`cd ea`):** forward header `01 03 00 19 01`, then 8 ×
  `(ch#, flags, gain=00)`, rotating modulo 49, `0xfe @ ch48` + flag `0x01` terminator.
- **Checksum verified on-rig:** all captured control frames satisfy
  `Σ data[0..31] == 0 (mod 256)` (e.g. `Σ data[0..30] = 0x65`, `data[31] = 0x9b`,
  `0x65 + 0x9b = 0x100`). From-source, on-rig, and firmware-RE all agree.

## M-5000 channel-info flag bytes (supersede the macOS driver values) [V]

The firmware RE and the live M-5000 agree this device emits flag bytes **`0x28`** for
channels 0–39 and **`0x38`** for channels 40–47 (records `XX 28 00`), **not** the
macOS `reacdriver`'s `0x20`/`0x10`/`0x30` — a different device generation. Bit `0x08`
is set on all records; channels 40–47 additionally set `0x10`. For the M-5000, treat
`0x28`/`0x38` as authoritative.

## Per-port link identity [V]

A REAC port's link identity = **src MAC + outChannels**. The channel-map structure is
identical across a master's ports; only the rotation phase and audio payload differ.
Confirmed on-rig: a stagebox refuses a foreign port's stream (wrong master MAC — link
LED flashes, no audio) and syncs only to its own port's master MAC. Cadence is
~99.97% FILLER/audio frames + ~1.7 control/s (~1:1 MASTER_ANNOUNCE : CONTROL).

## Slave establishment (observed live; completes the driver's partial path) [V]

A real REAC slave (a merge unit in slave mode — on the wire a plain slave) using its
own OUI `00:40:ab` interface MAC was captured linking and running against an M-5000
master:

- **Steady state (slave→master):** all unicast to the master MAC, ~8000 fps:
  FILLER/audio (type `00 00`) + periodic CONTROL (`cd ea`, ~1/s). The slave emits no
  MASTER_ANNOUNCE (`cf ea`, master-only) and no SPLIT_ANNOUNCE (`ce ea` / `c2 ea`).
- The slave's CONTROL sub-header is **`01 03 00 01 81`** (the return channel-map: the
  inputs the slave presents to the master) vs the master's forward `01 03 00 19 01`.
  The record format afterwards is identical: 8 × `(ch#, flags, gain)`, flags
  `0x28`/`0x38`, `0xfe @ ch48` terminator, two's-complement `data[31]` checksum.
- **Establishment at a cold-start replug:** (1) cold start → broadcast FILLER flood
  (~1–1.5 s, dst `ff:ff:ff:ff:ff:ff`) to announce presence; (2) → switch to
  unicast-to-master + a burst of ~6 CONTROL frames in the first second to
  (re)negotiate the channel map; (3) → established unicast audio + ~1 CONTROL/s steady.

A virtual REAC slave is reproducible from this: flood broadcast FILLER, then unicast
audio + checksummed CONTROL (return map `01 03 00 01 81`) to the master MAC.

## Holding the link — the per-frame link-check budget [S]

Once established, the link is held against a **single per-frame budget of ~600 frames**.
Each REAC frame decrements it; reaching zero declares the peer absent. Because a frame is
one sample slot, 600 frames is **≈150 ms at 48 kHz / ≈75 ms at 96 kHz** — so the
wall-clock loss tolerance *halves* when the sample rate doubles, and a 96 kHz link is
about twice as fragile as a 48 kHz one over a lossy hop. This matches the observed 96 kHz
Wi-Fi fragility on the rig.

The established side re-arms the budget with its **periodic keep-alive heartbeat** (the
~1/s CONTROL frame `01 03 00 01 81`): a heartbeat carrying the keep-alive selector resets
the count to full, the same selector cleared latches an explicit disconnect, and a change
of the peer's source MAC also forces a disconnect. The counter itself is decremented
**in the FPGA**, not in CPU code — the device firmware only arms and tests it. A frame
budget that is FPGA-ticked but CPU-armed is the device-side mechanism behind the wire's
~1000 ms no-audio cutoff and the heartbeat re-arm described in
[wire-format.md](wire-format.md).

## Head-amp commit — staging vs active tables [S][?]

The wire-format reference documents *what* head-amp records look like
([wire-format.md](wire-format.md), source control). This is the firmware-side behaviour of *how a box
applies them* — re-expressed from an RE pass, **not yet confirmed at the pins**, and the practical
reason a software master can command 48 V correctly on the wire yet only commit it to one input.

A box keeps **two head-amp tables**: an **active** table (what the converters actually run) and a
**staging** table (pending values). Two record streams feed them, and they are **complementary**, not
alternatives:

- **op-`0103` channel map** — the per-input **presence / enrol** stream. It writes head-amp into the
  **active** table directly, and is how an *already-enrolled* input carries its state. (Its per-record
  marker byte is a constant hardware-bank tag — the `0x28` / `0x38` byte in the channel-info records
  above — **not** a phantom bit.)
- **op-`0403` TAG `01 01`** — the per-channel head-amp **values**, written to the **staging** table.
- a **commit** step copies **staging → active for every slot at once**. It is driven by the console's
  bulk **`cd ea 01 01` → `cd ea 01 02`** start/end marker pair (the same pair that brackets a
  SCENE / SYSPARAM transfer), and a working console **sustains** that pair on its steady cadence rather
  than firing it once.

The consequence for a master implementation, and why it matters: emitting correct op-`0403` values for
every input is **not sufficient**. Without the commit pair, only the box's default-enrolled **anchor**
input flushes from staging to active — 48 V lands on one socket and silently ignores the rest. A master
that fires the start/end pair only during the join/probe phase (before it has staged any values) shows
exactly this: the anchor commits, the others do not.

**[?] Status — RE-derived, rig-unvalidated.** The falsification test is direct: on a box whose anchor
already commits, a master that (1) emits the commit pair *after* staging the values and (2) **sustains**
it on the established cadence should light **every** enrolled input — confirmed by a physical 48 V check
per socket (a real condenser microphone, or a meter across the XLR pins; never a software level
readout). Until that bench check passes, treat "stage the values, then sustain the commit pair" as the
current best model, not a settled fact. Captured console cadences for the pair disagree — a scene-recall
burst fires it a few times within seconds, a steady session spaces it out — which is itself the argument
for *sustaining* the pair rather than counting its occurrences.

## Master split/mirror output vs a true split device [V]

A master REAC port configured as a split / mirror output emits a passive copy of the
mirrored port: same master MAC, same MASTER_ANNOUNCE + CONTROL + audio, broadcast. It
is **not** a split-announce source (no `ce ea`) and is one-way — it carries the forward
stream but does not answer a slave's return handshake, so a bidirectional slave cannot
lock to it (a receive-only recorder can). The `ce ea` / `c2 ea` SPLIT_ANNOUNCE types
are emitted only by an actual split device / topology, never by a plain slave, a merge
unit in slave mode, or a mirror output — so they remain the last unmapped frame types
(need a real split device in the chain to capture).

## Console-side AES/EBU and the REAC↔AES3 crossbar [S][V]

From a V-Mixer-class console of this generation (firmware RE corroborating published
vendor docs and the public AES3 / IEC 60958 standards; not pinned to a firmware
version):

- **24-bit PCM throughout** — internal mixing, REAC transport, and AES3 all 24-bit
  (ALSA `S24_3LE`, matching REAC's 3-byte samples). No width conversion on the
  REAC↔AES path.
- **No sample-rate converter on the AES/EBU inputs** — an incoming AES3 stream must
  already be synchronous to the console word clock. Conversion is synchronous by
  construction.
- **One global sample rate** for the whole engine: 44.1 / 48 / 96 kHz (no per-port
  rate); 48 and 96 kHz are the common operational rates.
- The **REAC↔AES3 reframing crossbar is in the FPGA**, not CPU code. The CPU only
  configures it through a memory-mapped FPGA register block (a per-REAC-port array of
  16-bit words). "Which source feeds AES OUT 1/2" is a patchbay / routing parameter,
  identical in nature to "which source feeds a REAC out slot." This is consistent with
  the upstream-audio finding (the channel MAP is FPGA-owned and invisible to CPU
  firmware-RE).
- The console maintains a full AES3 **channel-status array** (24 bytes) and can
  internally lock its clock to an AES input, though the vendor UI documents AES IN as a
  clock slave only (AES-as-master is an undocumented internal capability, not something
  to rely on).
- The master exposes a **settable clock-source selector** over the control protocol
  (not over the REAC audio wire): the front-panel-visible sources are **WORD CLOCK**,
  **REAC A**, **REAC B**, **INTERNAL** (free-run — the normal "master" mode), and
  **AES** input pairs (plus expansion-slot sources). Choosing REAC A/B slaves the
  desk's own clock to a clock arriving on a REAC port; choosing INTERNAL makes the desk
  free-run and clock the fabric. The selection changes *what* the master locks to, not
  the on-wire REAC frame form. (The selector is a routing/configuration parameter, the
  same in nature as "which source feeds an output slot" — see the clock-source selector
  note in [wire-format.md](wire-format.md).)
- The rear panel exposes 2 stereo AES3 pairs each way (AES/EBU IN 1/2, IN 3/4,
  OUT 1/2, OUT 3/4), all IEC 60958-compliant; each pair is one AES3 stream whose
  A/B subframes carry L/R.

## Mixer remote-control (RCP) command surface — separate from the REAC wire [S]

The Roland V-Mixer / M-5000 remote-control protocol is a **separate TCP channel**, not
the REAC audio wire. It exists to recover the slot↔name mapping a passive tap cannot
see.

- **Transport:** telnet over TCP 8023, no auth, single connection at a time, poll-only
  (no unsolicited push).
- **Framing:** `STX(0x02)` + 3 letters + `:` + CSV args + `;`. Over telnet the STX is
  dropped and the `0x06` ack renders as literal `OK`; errors arrive as `ERR:<n>;`. The
  3rd letter is the action: `C` = set, `Q` = query, `S` = status reply. Category
  whitelist (2-letter): CN, PI, PO, FD, MU, PT, PS, PG, EQ, FL, AX, MX, PN.
- **Key queries:**
  - `CNQ:I<ch>;` → `CNS:I<ch>,"<name>";` — channel name (6 chars; blank = 6 spaces).
  - `PIQ:I<ch>;` → `PIS:I<ch>,RAI<slot>;` — input patch (which REAC input slot feeds a
    channel). Slot tokens: `RAI1..RAI40` (REAC A in), `RBI*` (REAC B), plus `CI*`,
    `STIL`/`STIR`, `FX*`, `PLAY*`, `OFF`.
  - `POQ:RAO<slot>;` → `POS:RAO<slot>,<source>;` — output patch (`RAO1..RAON`).
  - `VRQ` (version), `FDQ`/`MUQ` (fader / mute), `RCQ` → `RCS` (REAC connection status
    — coarse connected/disconnected; format unverified on real hardware).
- The `RAI<n>`/`RAO<n>` index equals the REAC slot index a passive tap keys on, so
  joining `PIS` (channel→slot) with `CNS` (channel→name) yields slot→name directly.
  Invert `PIS` across all channels to get slot→channel, then join `CNS`.
- Per-model channel counts: M-200 / M-200i = 32 in, M-300 = 32, M-480 = 48, M-5000
  (OHRCA) = 128 (the M-5000's 128 free paths may use non-RAI/RAO tokens — detect and
  branch at runtime).
- `RCQ` is coarse and unpushed: the hardware clock-recovery PLL state sits below the
  remote-control API, so a sub-second sync lock-flap is likely invisible from telnet.
  Pair telnet `RCQ` (coarse connection + labels) with a wire-side health monitor
  (fine-grained jitter / lock) on the decoder side.
- Public reference implementations (proven query paths, per-model counts, a
  hardware-free simulator): `bitfocus/companion-module-roland-m5000` and
  `JamesCC/VMXProxyPy`.

Re-expressed only — no Roland binary or protocol-PDF verbatim text.

## Timing / bidirectional TX feasibility [?]

The original driver conclusion "kernel scheduling can't do jitter-free REAC playback"
predates mainline `PREEMPT_RT` (in Linux since 6.12). On a wired RT-tuned host it is
now expected feasible:

- `SCHED_DEADLINE` (period = the REAC slot, `SCHED_FIFO` fallback), isolated core
  (`isolcpus`/`nohz_full` + IRQ affinity), waking via
  `clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME)` to an accumulated absolute
  deadline.
- For tightest pacing use `SO_TXTIME` + the ETF qdisc (hardware launch-time / TSN) on
  a capable NIC (Intel i210 / i225 / i226 class). Measure scheduler jitter and on-wire
  send jitter separately.
- As **master**, Linux needs only a stable continuous cadence (the whole fabric locks
  to the sender, so the sender's rate becomes the system rate) — RT scheduling
  suffices. As **slave**, add a software clock servo disciplining TX to the recovered
  master clock. Target the master role first.
- The remaining gate for the drive-a-stagebox path is **protocol acceptance**, not
  timing: emit MASTER_ANNOUNCE + the replayed control cadence + a known tone in
  correctly-justified audio frames into a standalone stagebox (no console, so nothing
  live is at risk) and listen on its analog outs.

## Open items needing on-rig capture (firmware-RE exhausted)

- The exact **upstream channel MAP** (needs distinct simultaneous tones, one frequency
  per input).
- `ce ea` / `c2 ea` **SPLIT_ANNOUNCE** byte sequences (need a real split device /
  topology).
- **44.1 kHz on the wire** (3675 pps?) — not yet exercised.
- `RCQ`→`RCS` real-hardware format and whether it is granular enough to observe sync
  lock-flap (likely only coarse).
- Why a Wi-Fi-fed upstream port scrambles while a wired port stays clean. The audio
  byte framing is FPGA-owned, so only on-rig capture advances this — CPU firmware-RE is
  exhausted.
