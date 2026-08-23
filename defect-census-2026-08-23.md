# Defect and pending-work census — the REAC stack, 2026-08-23

What this is: an honest inventory of what is broken, half-built, or known-wrong and still
shipping, across the nine REAC repos and openmixer's REAC-facing code. It is a survey, not a
repair: **nothing was fixed**, and section 10 records exactly what was and was not run, and
proves every repo is unmodified.

Two other lanes ran beside this one: one censuses protocol UNKNOWNS, one settles disputed facts.
Neither is duplicated here. This lane is CODE.

**Ranking rule.** Blast radius, not effort. A defect that makes a MEASUREMENT LIE outranks one
that makes a feature missing, because a wrong number contaminates every decision taken after it.
Silent audio corruption outranks both. A missing feature is visible; a wrong number is not.

**The column that matters** is "how it shows up". It is the one that gets skipped, and it is the
one that tells you whether a bug has already cost you a night.

Every claim carries a file:line. Absences were proved with a positive control in the same
command, because an empty grep and a broken grep look identical.

---

## The ranked list in one table

Full write-ups follow. `A*` = reac-pw / reac-tools / reac-label / the stale aes67 fork,
`B*` = reac-repacer / reac-aes67 / reac-kmod, `O*` = openmixer.

| # | Defect | Where | What an operator sees |
|---|---|---|---|
| 1 | A loss gap ≥32768 packets reports ZERO loss and permanently shifts the PTP timeline | `reac-aes67/src/media_clock.c:40-50` | 8.19 s of audio gone, "Loss: 0" on the page, and a Dante stream silently un-anchored from the grandmaster until restart |
| 2 | Two audio layouts; the measurement half uses the wrong one | `reac-tools/reac_codec.py:192` + 6 files | A clean line reads impure, granular and 36 dB low. Contaminates a documented night of conclusions |
| 3 | `diff.py` dedupes on the raw 16-bit counter | `reac-tools/reac/diff.py:38-44` | "link clean" on a link that lost 500 frames. **Lies in the safe direction** — a longer capture lies harder |
| 4 | Five instruments still hardcode SR=96000 | `reac_ab_defect.py:8`, `measure_b7.py:7`, +3 | A real 1 kHz tone reads 2000 Hz, fails the sanity gate, and is reported as **no tone** on a healthy line |
| 5 | Ring-full drops counted, displayed nowhere, and the frames renumbered contiguous | `reac-repacer/tools/reac_repacer.c:508` | Spliced audio that every instrument — log, ubus, LuCI, the box's own counter — calls perfect |
| 6 | `--tone-detune` buzzes on 36 of 40 channels | `reac-aes67/src/tone.c:120,128` | The bench tool built to rule out the receiver manufactures the fault instead |
| 7 | The stale aes67 fork emits REAC with no pacer | `reac-aes67/pipewire/src/reac_sink_node.c:73-81` | Boxes hear word-clock jitter; intermittent link drops that blame graph load |
| 8 | "Pkts/s" is a constant and "Uptime" is not uptime | `reac-aes67/src/main.c:312,314` | Unplug the stagebox and the status page still reads 4000 pkts/s |
| 9 | SENS anchor disagrees by 10 dB, openmixer vs libreac | `openmixer/.../declarations/src/index.ts:103` vs `libreac/src/reac_ctrlblk.c:167` | Console says 32 dB where the Roland desk says −42 dBu. Latent only because nothing reads a preamp back |
| 10 | The kmod licence gate looks for imports, so vendored GPL-3 passes green | `reac-kmod/tools/smoke.sh:65` | Nothing — which is the point. Sabotage-verified: GPL-3 code in the binary, all gates ok |
| 11 | The stale fork carries a ppm bug fixed upstream 2026-06-30 | `reac-aes67/pipewire/src/reac_rx.c:69-72` | A drift measurement that spikes once per capture loop, from the tool's own seam |
| 12 | A CI job named `reac-pw` tests a two-month-stale fork | `reac-aes67/.github/workflows/ci.yml:21-35` | A green check that means nothing it appears to mean |
| 13 | The startup banner confirms two knobs that do not exist | `reac-repacer/tools/reac_repacer.c:1387` | `plc=0` in the log while concealment runs, defeating the exact diagnostic the man page prescribes |
| 14 | The missing-hardware alarm is gated shut by a dead key | `openmixer/.../reac-config-store.ts:239` | An unplugged S-0808 says nothing — the defect this code was written to fix |
| 15 | Slave FSM timers are raw frame counts, master's are scaled | `reac-pw/src/reac_fsm.h:35,41,49,55,69` | 48 kHz slave establishment that never completes, or completes intermittently. **Already filed as P1/P2** |
| 16 | Prefill barrier with no timeout + four RX paths, three VLAN policies | `reac-repacer/tools/reac_repacer.c:1480-1490,487` | A tagged interface hangs the daemon forever, no error, no counter, and procd never respawns it |
| 17 | An un-modelled box is never adopted, rostered or made safe | `openmixer/.../server.ts:4550` | "The box isn't showing up" while its audio plainly arrives. Phantom stays where the last user left it |
| 18 | Browser and server compute different box widths | `openmixer/.../web-ui/app/utils/stagebox.ts:234` | Name a box "Drums 8ch" and preamps 9-16 vanish from the UI but not the server |
| 19 | `REACPW_NO_HEADAMP=0` turns the kill switch ON | `reac-pw/src/reac_pacer.c:251` | No phantom, no gain, on any channel. The only live knob missing from the docs |
| 20 | RME mic pres escape the one-preamp-per-channel guard | `openmixer/.../structural-dsp.ts:65` | Two preamps behind one strip; phantom and gain become ambiguous |
| 21 | Saved patches fall back to a remembered port name | `openmixer/.../patch-identity.ts:76` | A show reloads with channels on the wrong preamps, no refusal raised |
| 22 | `decode_probe.py` cannot find the layout it hunts | `reac-tools/decode_probe.py:74-84` | "signal itself may be distorted" — a broken search wearing a confident error message |
| 23 | `--bcast-only` dead in the Dante profile, and no UCI knob at all | `reac-aes67/src/main.c:279,656-667` | Two counter streams interleaved into "concealment garbage", per the code's own comment |
| 24 | Breath-rate in Hz from a non-uniformly sampled series | `reac-tools/reac_clock_measure.py:145-148` | A number with a unit that drifts with the fault it measures, logged beside real ones |
| 25 | A refused bind is reported to the client as applied | `openmixer/.../stagebox-name-row.ts:115-129` | 200 OK, key unchanged, no log line |
| 26 | Cross-transport bind refusal: settled law, zero code, UI promises it | `openmixer/.../stagebox-registry.ts:428` | A patch addressing sixteen XLRs on metal with twelve inputs, unrecoverable |
| 27 | `probe` briefly takes the segment lock it is probing | `reac-kmod/tools/reac-segment-lock.c:185-201` | A diagnostic that can cause the fault it looks for — and two masters are live right now |
| 28 | reac-label returns an error code as a slot token | `reac-label/reaclabel/client.py:89` | A channel named after an error code, shaped exactly like a real row |
| 29 | Multicast egress pinning fails silently | `reac-aes67/src/aes67_send.c:63` | The AES67 stream goes out the WAN port and the daemon reports success |
| 30 | `verify_tag_0500.py` checksum rule rejects valid records | `reac-tools/verify_tag_0500.py:74` | A gate that false-alarms ~half the time, so it stops being read |
| 31 | `reac_spectrum.py` is blind to VLAN tags | `reac-tools/reac_spectrum.py:38` | "no usable upstream" — reads identically to a dead box |
| 32 | `setName` mints undeletable ghost roster entries | `openmixer/.../stagebox-registry.ts:302` | A permanent phantom row from one stale tab |
| 33 | `REAC_ROLE` deleted from the operator's file on every write | `openmixer/.../reac-config-store.ts:79-86` | A rig set to slave silently flips back to master |
| 34 | libreac's version is a hand-set string; wraps float on `main` | 3 × `libreac.wrap` + 3 disagreeing numbers inside libreac itself | Nothing — which is the problem. No build reproducible, no version check able to fail |
| 35 | `if (n)` guards one of three statements | `reac-pw/src/reac_sink_node.c:1212` | Nothing today; unreachable. Listed because the compiler said so and nobody read it |

**If only three things are fixed: #1, #2 and #3.** Each makes a number lie, each has already been
believed, and #1 also loses audio.

---
## 1. The already-known items, re-verified

Each was checked against the current tree rather than taken on trust. Severity changes are noted.

| Item | Still true? | Severity change |
|---|---|---|
| reac-pw rate-match reads ring depth before the push; standing +1310..+3810 ppm; ships OFF | **Yes** | **None.** See A8. The disposition is right and the reasoning at `main.c:725-756` is worth preserving verbatim |
| Catch-up budget now expressed in time (1000 us), not slots | **Yes** — `reac-pw/src/reac_pacer.h:220` `REAC_CATCHUP_MAX_DEFAULT_US 1000`, resolved per rate by `reac_catchup_default_slots(fps)` at `:225-230` | **One small regression left behind** — see below |
| reac-tools counter-wrap (8.2 s) and four tools hardcoding SR=96000 | **Partly fixed, partly live** | **Worse than the summary implied** — see A1-A5 |
| reac-aes67/pipewire is a stale second copy of reac-pw | **Yes**, and worse than "24 files against 56" suggested | **Raised** — see A5, A6, A7 |

**The catch-up budget's leftovers.** The fix itself is exemplary — `reac_pacer.h:193-220` states
the reasoning ("a budget written as 4 slots silently means 1.0 ms at 48 kHz and 0.5 ms at 96")
and the constant is measured, not guessed. Two things did not follow it:

- The env var is still named **`REACPW_CATCHUP_MAX_SLOTS`** and the struct field is still
  `catchup_max_slots` (`reac_pacer.h:190`), while what it now expresses is a time. A knob whose
  name states the wrong unit is the same trap the fix was written to remove.
- `reac-pw/src/main.c:319-321` documents it as "Unset = 4 (measured)". That is true only at
  48 kHz; at 96 kHz the default resolves to 8. The help text pins a rate-dependent value to one
  rate — again, exactly the class of thing being fixed.

Both are one-line documentation/rename items, listed here so they are not lost.

**On reac-tools.** The picture is more mixed than "those fixes exist in a lineage that must not
be pushed". Some of the work **is already on the current branch**: `f6592c8` fixed the wrap for
the six tools that call `reac_codec.order_by_counter`, `3c7c907` fixed the rate for four
instruments, `eef5f7e` removed the 3000-fps default, `cecad8d` added the empty-scan gate. What
remains is listed as A1-A5 and A11-A14, and **no fix exists on any branch for A1 (the layout
split), A2 (`reac/diff.py`), A3's remaining five files, or A5**. The cherry-pick will not cover
them; they are new work.

The unmerged branches carry different things: `fix/mirror-twin-dedup-rate` has `3186324` and
`4cc4a87` (including `clean_payload_len`, absent from this branch); `feat/headamp-capture-diff`
has `reac/ctrl.py`, `reac/headamp.py`, `capture-headamp.py`; `feat/capture-corpus-index` has
`tools/build_capture_index.py`.

---
## 2. The ranked defect list

The `A*` items — reac-pw, reac-tools, reac-label, and the stale reac-aes67 fork of reac-pw.
The `B*` items (reac-repacer, reac-aes67 top level, reac-kmod) are in section 3 and the `O*`
items (openmixer) in section 4, each with that area's own half-built inventory, test-honesty
verdict and duplication table, because those only make sense read together.

### A1 — reac-tools decodes the audio region two different ways, and the half used for measurement is wrong

`reac/characterize.py:56-66` reads the 1440-byte audio region as a pair-interleave.
`reac_codec.py:192-198`, `reac_deep.py:53-57`, `reac_pitch.py:68-71`, `reac_spectrum.py:56-57`,
`reac_glitch.py:44`, `reac_clock_measure.py:96-101` and `reac_out_health.py:52` read it as plain
little-endian. One protocol, two byte maps, seven files on the wrong one.

Settled against the repo's own real capture bytes (`tools/real_capture_payloads.json`, the same
frames behind `tests/fixtures/real_reac_stream.pcap`): the interleaved read gives a coherent
few-LSB dither floor on an idle desk, max |sample| 29. The plain-LE read gives max |sample|
65536 — exactly 0x010000, the signature of a byte landing in the wrong significance position —
and per-channel peaks in a 2^16 / 2^8 / 2^0 ladder. The interleave is right.

**How it shows up.** Not as an error. A mathematically perfect 1 kHz sine, encoded in the true
layout and read back through the plain-LE chain, reports **purity 0.275, 1499 clicks, and a
level 36 dB low** — while reporting the frequency and the channel correctly. Everything the
operator checks first looks right. So a clean line reads as granular, impure and quiet, and the
operator goes hunting a transport fault that does not exist.

This is not hypothetical. `reac_clock_measure.py:15` states as established fact that the
re-pacer reconstruction "reads ~±385 ppm / purity ~0.25" — 0.25 is precisely what this decoder
returns for a *clean* input. `REAC-REPACER-NIGHT.md:59-64` names `reac_codec`, `reac_deep`,
`reac_spectrum` and `reac_pitch` as the instruments behind that night's conclusions. All four
are plain-LE. Every purity, click, ppm and dBFS figure they produced is unverified.

Scope, stated honestly: the proof is decisive for the 40-slot downstream direction, the only
real capture in the repo. Three of the plain-LE tools explicitly claim that direction
(`reac_glitch.py:5`, `reac_deep.py:137`, `reac_clock_measure.py:47-51`). The box upstream layout
was never settled either way.

**Would a test have caught it?** Yes, and one assertion would have done it.
`tests/test_characterize.py:38-41` calls the correct decoder on the real fixture and asserts only
`len(channel_peak) == 40`. It never looks at a sample value. The one place the repo holds real
wire bytes, it checks the array's length and not its contents.

---

### A2 — reac/diff.py dedupes on the raw 16-bit counter: a longer capture reports a cleaner link

`reac/diff.py:38-44` builds `{f.seq for f in sender}` — a set of raw counters — then sorts it.
The counter wraps every 16.4 s at 48 kHz, 8.2 s at 96 kHz.

Demonstrated on a 20-second run at 48 kHz with a real 500-frame loss injected:

```
truth: sent=80000  really lost=500 (0.625%)
tool : sent=65536  lost=0          (0.000%)   -> "link clean"
control (same loss, no wrap): reports 500 correctly
```

**How it shows up.** In the worst possible direction. `reac/diff.py:67` prints
`-> link clean: every sent frame arrived, none foreign`. `README.md:118` and
`tests/test_diff.py:8` both call the dual-point diff "the decisive on-site measurement". So the
operator's correct instinct — capture longer, be more careful — is exactly what hides the fault.
`capture-dualpoint.sh` takes a duration argument with no upper guard.

**Would a test have caught it?** Yes, and the repo already knows the failure mode.
`tests/test_analyzer.py:31-35` has the wrap test for the analyzer. `tests/test_diff.py` has four
tests, all under seq 1000 (`F(i) for i in range(100)`, line 43). The gap is one test file wide.

Still present on every branch: `f.seq for f in` appears twice in `reac/diff.py` on all 21 refs.

---

### A3 — five reac-tools instruments still hardcode SR=96000; every 48 kHz reading doubles

Four were fixed on this branch (`3c7c907`). Five are not:

| file:line | what breaks |
|---|---|
| `reac_ab_defect.py:8` (used 33, 42, 43) | every f0, wobble and click rate doubles at 48 kHz |
| `measure_b7.py:7` (used 25, 29, 30) | same |
| `decode_probe.py:13` | see A4 |
| `reac_codec.py:23,227,240,246,251` | `measure_wobble()` reads module-level `SR`; no `sr` parameter |
| `reac_out_health.py:37,75` | `n/8000` for seconds, `/8` for ms — every duration reported at HALF its true value |

**How it shows up**, and this is the sharp edge: `reac_ab_defect.py:34` and `measure_b7.py:26`
gate on `800 < fr[pk] < 1200`. A real 1 kHz tone at 48 kHz reads as 2000 Hz and **fails the
gate**. The tool does not report "2000 Hz, suspicious". It drops the channel and reports
**no tone** — on a healthy line. A doubling bug wearing the costume of a dead box.

`reac_glitch.py` is internally inconsistent with itself: line 52 derives the rate correctly,
line 87 hardcodes `round(r/96,1)` to convert samples to milliseconds.

`README.md:65-66` claims "No tool here pins a rate; each reads it off the capture." Five files
contradict that line and nothing enforces it.

---

### A4 — decode_probe.py cannot find the layout it was written to find

`decode_probe.py:74-84` brute-forces `nch x offset x {sample-major, channel-major} x {le, be}`.
It never tries the pair-interleave — the layout its own sibling `reac/characterize.py:56-66` and
`wireshark/reac.lua:21` use. Compounded by the hardcoded `SR = 96000` at line 13, which puts a
real 1 kHz tone at 500 Hz, outside the `980 < f0 < 1020` gate at line 83.

**How it shows up.** `decode_probe.py:90` prints
`NONE found a 1 kHz tone in any layout -> signal itself may be distorted`, and the operator
concludes the box is broken. The search was structurally incapable of succeeding. This is the
"a search that finds nothing may be a broken search" trap wearing a confident error message.

---

### A5 — the stale reac-aes67/pipewire copy emits REAC frames on the graph's cadence, with no pacer

`reac-pw/src/reac_pacer.h:6-14` states the requirement: "A real REAC slave (stagebox) recovers
its word clock from the master's frame inter-arrival interval, so the downstream broadcast MUST
leave at a rock-steady pps ... The PipeWire graph thread cannot guarantee that: its quantum is
bursty and a sendto() syscall on the RT graph thread adds wake jitter."

`reac-aes67/pipewire/src/reac_sink_node.c:73-81` does exactly the forbidden thing: it calls
`reac_tx_emit` from inside `on_process`, the RT graph callback, once per full 12-sample stage.
There is no pacer anywhere in that tree — `grep -l clock_nanosleep` over
`reac-aes67/pipewire/src/` returns nothing, while the same grep over `reac-pw/src/` returns six
files. The `tx_ring` argument is accepted and discarded at
`reac-aes67/pipewire/src/reac_sink_node.c:94` — `(void)tx_ring; /* direct-emit cut: no ring yet
(a pacer thread would use it) */` — and `reac_sink_node.h:46` calls it "reserved for the future
slot-pacer cut; the direct-emit path ignores it".

**How it shows up.** A box fed by this binary hears rate jitter on its recovered word clock. The
symptom is intermittent and blames the wrong thing: link drops under graph load, audio that is
fine until something else in PipeWire changes the quantum, and a master that measures perfectly
from its own side because everything it counts is correct.

**Mitigating, and it matters:** `reac-aes67/README.md:56` explicitly declares this tree "a
pre-split snapshot and is not its source", pointing at FreeREAC/reac-pw. So it is documented
dead. See A6 for why that is not sufficient.

---

### A6 — the stale copy still carries a packaged spec that builds an RPM named `reac-pw`

`reac-aes67/packaging/reac-pw.spec:4-6` — `Name: reac-pw`, `Version: 0.1.0`, `Release: 3` —
builds from the pipewire/ subtree. The real repo's `reac-pw/packaging/reac-pw.spec:3,7,8` is
`reac-pw 0.2.0-1`.

**How it shows up.** Today it does not: 0.2.0 outranks 0.1.0-3, so a repo holding both installs
the real one. That is luck, not design. The moment anyone bumps the snapshot's release, or the
real repo's version is expressed differently, `dnf install reac-pw` installs a two-month-stale
daemon with no pacer (A5) and a shared-state ppm bug (A7), under the right name, with a plausible
description. The failure has no signature: the binary starts, the link establishes, health is
green.

A README line saying "not the source" does not disarm a spec file that builds and names a
package. **Recommendation, not applied:** delete `reac-aes67/packaging/reac-pw.spec` and the
`pipewire/` subtree, or at minimum rename the package so it cannot collide.

---

### A7 — the stale copy carries a ppm-measurement bug fixed upstream two months ago

`reac-aes67/pipewire/src/reac_rx.c:69-72` keeps the ppm window state — `win_start_ns`,
`win_frames`, `last_counter`, `have_last` — in **function-static locals**. Fixed in reac-pw on
2026-06-30 by commit `e18d19c`, whose message names both consequences: the statics survive a
pcap-loop restart, so the counter discontinuity at the loop seam spikes one bogus ppm per loop;
and they make RX a non-reentrant singleton, so two `reac_rx` instances share one window. The
stale copy has the pcap loop that triggers the first, at
`reac-aes67/pipewire/src/reac_rx.c:125-130`, which resets `ps` and `wall_first_ns` and not the
statics.

reac-pw's fix is at `reac-pw/src/reac_rx.h` (the four fields moved into `struct reac_rx`) with
the reset co-located with the pcap restart.

**How it shows up.** A ppm figure that spikes once per capture loop, in a tool whose entire job
is to report ppm. An operator reading a drift measurement off an offline capture sees a periodic
excursion that is an artefact of the tool's own loop seam, and attributes it to the clock.

**Would a test have caught it?** No, and the fix commit says so plainly: "No focused unit test:
update_ppm is file-static and reac_rx has no test harness." That honesty is worth more than a
fake test would have been, but the gap is real and still open in both trees.

---

### A8 — reac-pw's rate-match loop reads the ring depth one quantum too early

Already known; **verified still true, and the severity is unchanged.**

`reac-pw/src/reac_sink_node.c:236` reads `reac_frame_ring_readable(&n->pacer.ring)`. The frames
for this cycle are pushed at `reac_pacer_submit`, `reac-pw/src/reac_sink_node.c:350` — 114 lines
later in the same callback. So the loop measures the ring before its own producer has filled it,
and reads about one quantum low: `qf = nframes / REAC_SAMPLES_PER_PKT` = 21 frames at a 256-frame
quantum. With `target = qf * 2` = 42 (line 253), a ring genuinely sitting at 42 reads as 21, so
`err = -0.5` and the loop holds a standing **+2500 ppm** to sit where it already is. That matches
the observed +1310..+3810 ppm across the soak.

The sign is verified correct on hardware. Only the phase is wrong.

**How it shows up.** It does not, currently — and that is the point of the disposition.
`reac-pw/src/main.c:757-759` ships it OFF (`REACPW_RATE_MATCH=1` opts in), and the reasoning at
main.c:725-756 is exactly right: the whole reason the applied correction is published as
`reac.health.rate-match-ppm` is that a large steady correction is a fault report, and this one
is reporting a fault in itself. Left on, an operator watching that field would see 26-76% of the
loop's authority spent at rest and have no way to tell it from a real upstream frame loss.

**Status: not fixed, not measured.** The fix is "read the depth after the push". The claim that
would close it — "near zero at rest" — has not been made yet.

---

### A9 — the slave FSM's five establishment timers are raw frame counts; the master's are rate-scaled

**Already documented. Not a discovery — a confirmation that it is still open, and it is the
highest-blast-radius open item in reac-pw.** It is written up in full as **P1 and P2 of
`reac-repacer/REPACER-FIXES.md:41-95`**, which is worth reading in preference to this entry: it
derives the corrected constants and separates the offline-testable mechanism from the rig-gated
values. Two notes about its filing, below.

**Verified still unfixed today.** All five constants are unchanged at
`reac-pw/src/reac_fsm.h:35,41,49,55,69`:

```
REAC_FSM_LINKCHECK_RELOAD   600    /* 0x0258 frames */
REAC_FSM_TXMUTE_DWELL       800    /* ~100ms @8000fps */
REAC_FSM_FLOOD_BURST       5460
REAC_FSM_JOIN_RETRY_PERIOD  800    /* ~100ms @8000fps */
REAC_FSM_GRANT_ACK_FRAMES  7200    /* 9 x JOIN_RETRY_PERIOD */
```

The asymmetry is the finding. The master scales everything from fps at init —
`reac-pw/src/reac_master.c:411-421` derives `cycle_len`, `probe_stride`, `grant_frames`,
`chanmap_off`, and reac_master.h:135,144 do the same for the link-check and grant dwell. On the
slave side exactly one timer is scaled: `heartbeat_period = sample_rate / 12` at
`reac-pw/src/reac_slave.c:88`. The other five are `#define`s pinned to 8000 fps, which is 96 kHz.

At 48 kHz (4000 fps) the 800-frame TX_MUTE dwell becomes **200 ms against a real master's ~150 ms
grant window** (`reac_master.c:420`, `(fps*15)/100`) — violating the constraint that
`reac_fsm.h:36-40` states in its own comment. `GRANT_ACK_FRAMES` becomes 1.8 s. `FLOOD_BURST`
5460 is 0.68 s at 96 kHz, half the byte-verified 1.36 s.

The dwell decrements once per received frame or tick (`reac-pw/src/reac_fsm.c:162-164`), and that
code's own comment says "8000 fps — the normal case", which is where the pinning came from.
`--role slave` is a shipped mode (`reac-pw/src/main.c:269`, call chain
`reac_slave.c:68,103,111,119`), so this is reachable, not a test fixture.

**How it shows up.** A 48 kHz segment where the slave role never completes establishment, or
completes it intermittently depending on where the dwell lands relative to the master's window.
Nothing in either log says "200 against 150": the master simply stops seeing the unicast it was
waiting for and re-probes, and the box LED does what a box LED does. P1 notes the trigger — the
96k-OHRCA work "made rate a live variable, so this asymmetry is now reachable."

**Would a test have caught it?** No, and it cannot as written. `reac-pw/tests/test_reac_fsm.c`
contains no mention of fps, rate, 48000 or 96000 (verified with a positive control), so the FSM
is exercised purely in frame counts and a rate-scaling error is invisible to it by construction.
Worse, its timing assertions are tautologies: line 109 is
`CHK(fsm.link_check == REAC_FSM_LINKCHECK_RELOAD)`, line 67 is
`CHK(... >= REAC_FSM_FLOOD_BURST)`. The constant is asserted against itself; any value passes.
The structural assertions in that file are genuinely good. Every timing assertion in it is
decoration.

**Two notes on the filing, which is the part this census can add.**

1. **reac-pw's defect list lives in reac-repacer.** P1, P2 and P3's headline all cite
   `reac-pw/src/*` from inside `reac-repacer/REPACER-FIXES.md`. Nothing in reac-pw points at it —
   a grep for `REPACER-FIXES` across reac-pw returns nothing. Anyone opening reac-pw to work on
   the FSM will not find the analysis, and the same lesson was independently re-derived by this
   lane before the doc was found. (The repo is aware of the general shape: today's HEAD commit is
   "fixes list: say which repo each item belongs to.")
2. **The lesson exists inside reac-pw and did not cross a file boundary.**
   `reac-pw/src/reac_pacer.h:193-220` is a careful write-up of exactly this bug class — "a budget
   written as 4 slots silently means 1.0 ms at 48 kHz and 0.5 ms at 96" — written while fixing the
   catch-up budget, in the same repo, and not applied to `reac_fsm.h`.

### A10 — REACPW_NO_HEADAMP triggers on presence, so setting it to 0 turns it ON

`reac-pw/src/reac_pacer.c:251` — `getenv("REACPW_NO_HEADAMP")`. Truthiness by pointer, not by
value. The comment directly above at line 243 says "REACPW_NO_HEADAMP=1 suppresses our own
head-amp push entirely". So does `=0`. So does `=` with nothing after it.

This contradicts the project's own written law, one file away:
`reac-pw/src/reac_conf.h:48-51` — "An empty value is NOT an answer. `REAC_RATE=` sets nothing and
falls through, because a key someone blanked out is a key they turned off, not a key they set to
the empty string." And it is inconsistent within its own repo: `REACPW_RATE_MATCH` at
`reac-pw/src/main.c:758-759` correctly uses `atoi(getenv(...)) != 0`.

Compounding it: **this is the only live env knob absent from `docs/ENV-KNOBS.md`.** The table at
ENV-KNOBS.md:10-18 documents `REACPW_GRANT_DWELL_S`, `REAC_DEBUG`, `REACPW_CLOCK_FOLLOW`,
`REACPW_CATCHUP_MAX_SLOTS`, `REACPW_RATE_MATCH` and `REACPW_CLOCK_REF` — six of the seven that
`getenv` actually reads. The seventh is this one.

**How it shows up.** An operator or a deploy script writes `REACPW_NO_HEADAMP=0` into a systemd
EnvironmentFile, intending to state explicitly that the diagnostic mode is off. The master then
pushes **no head-amp records at all**: phantom power and preamp gain are never asserted on any
channel, and the box keeps whatever its own state-4 commit promoted. Condenser mics are dead.
Gains are wrong. The code's own comment at reac_pacer.c:248-249 names the consequence — "a master
that pushes no head-amp leaves the operator's phantom and gain unasserted."

There is one line of defence: `reac_pacer.c:252-253` prints a message at establishment. It goes
to stderr, once, at a moment nobody is reading. And because the knob is undocumented, an operator
who suspects it cannot look it up.

**Would a test have caught it?** No test covers env-var parsing for this knob. The fix is one
expression and is testable; it is not applied here.

---

### A11 — reac_clock_measure reports a breath-rate in Hz from a non-uniformly sampled series

`reac-tools/reac_clock_measure.py:140` builds `insf` by *removing* out-of-band samples from
`inst`, producing a gappy, non-uniformly decimated series. Lines 145-148 then FFT it and read
`np.fft.rfftfreq(len(iw), 1.0/sr)`, treating it as uniformly sampled at `sr`. The result is
printed as `@{wobble:.1f}Hz` (line 153) and written to the CSV log (line 155).

**How it shows up.** The "pitch breathes at 1.4 Hz" figure is not the frequency of anything. It
drifts *with the fault it is meant to characterise*: more dropouts means more samples removed
means a more wrong axis. It looks like a measurement, it has a unit, and it lands in
`measure-log.csv` beside real ones.

The repo already knows: `reac_pitch.py:98-100` computes the same quantity, marks it `# approx`,
and discards it. The file that keeps it is the file that prints it as fact.

---

### A12 — reac-label returns an error code as a slot token

`reaclabel/proto.py:70` sets `is_error=True` on an error reply. `tests/test_proto.py:60` asserts
it. **Nothing reads it.** `reaclabel/client.py:89` returns `r.args[0]` for any reply.

```
parse_reply('ERR:5;') -> args=['5'], is_error=True
input_patch() returns slot = '5'
label table  -> {'5': 'Kick'}
```

`channel_name()` at `reaclabel/client.py:84` has the same hole: an error number becomes a channel
*name*.

**How it shows up.** The bad row is shaped exactly like a good one, so it flows into the JSON
that reac-aes67 stamps onto AES67 channel labels. A channel comes up named after an error code,
or patched to a slot derived from one, and nothing anywhere logs a failure.

The flag is already set and already tested. One `if` at client.py:82-94 closes it.

---

### A13 — reac_spectrum.py is blind to VLAN-tagged captures

`reac-tools/reac_spectrum.py:38` pins the ethertype to offset 12 (`p[12] != 0x88 or p[13] !=
0x19`), and lines 42, 47, 52 pin the counter, channel-count and audio offset to the untagged
geometry. Its siblings all scan `(12, 16, 20)`: `reac_deep.py:48`, `reac_pitch.py:42`,
`reac_frame_anatomy.py:43`.

**How it shows up.** On the tagged rig it prints `no usable upstream` (line 66) — which reads
identically to a dead box. `README.md:98-101` documents that the bridge shows a phantom tag and
that the operator must inspect bytes 12-13 to tell tagged from untagged. This tool silently
requires the answer to come out one way.

---

### A14 — verify_tag_0500.py's checksum rule probably rejects half of all valid records

`reac-tools/verify_tag_0500.py:74` — `ok = (sum(rec) & 0xff) == 0x80`. The Roland convention is
`(sum & 0x7F) == 0`, satisfied by 0x00, 0x80, 0x100, 0x180, ... This accepts only 0x80, 0x180,
0x280, ... and rejects every record whose byte sum is a multiple of 0x100. Failures become
`badck` (line 103), which sets `ok = False` (line 160) and exits 1 (line 174).

**How it shows up.** The identity-handshake gate cries `ANOMALY/COUNTEREXAMPLE FOUND` on
conforming captures, roughly half the time. A gate that false-alarms gets ignored, and the true
counterexample gets ignored along with it.

**Flagged as suspected, not proven.** Settling it needs a capture from `reac-captures`, outside
this lane's scope. Worth one run before the gate is trusted either way.

---

### A15 — reac_sink_node_set_rate_source: `if (n)` guards only the first of three statements

`reac-pw/src/reac_sink_node.c:1212-1218`:

```c
	if (n)
		n->rate_src = rx;
		/* Reset the receiver AT the re-establishment, not a tick later. */
		n->pacer.session_ctx = rx;
		n->pacer.on_session  = sink_on_session;
```

Missing braces. The last two statements dereference `n` unconditionally. The compiler says so —
`-Wmisleading-indentation` fires on this line in a clean build.

**How it shows up: today, it does not, and the census should say so rather than inflate it.**
The only caller is `reac-pw/src/main.c:853`, itself guarded by `if (sink)` at line 852, and the
one path that could produce a NULL sink calls `exit(1)` at main.c:790. The bug is unreachable.
What it costs is the guard: the NULL check that was written to make this function safe does not
make it safe, so the first caller that trusts the signature gets a segfault at startup.

Ranked low deliberately. It is listed because it is a compiler-visible defect in a shipping build
and nobody has looked at the warnings — which is the finding that generalises.

---

## 3. reac-repacer, reac-aes67 (top level), reac-kmod

Surveyed together. **The worst finding available — two copies disagreeing about the wire format —
does not exist in these three.** It was hunted deliberately with a constant-by-constant sweep
(table at the end of this section) and every geometry constant agrees with libreac. The damage is
elsewhere: a counter boundary that silently corrupts a clock, fabricated numbers on the
operator's screen, and five documented knobs no C code reads.

Suites actually run: reac-repacer `meson test` 2/2; reac-aes67 15 of 17 binaries, 85 test
functions, all pass (2 skipped — `test_aes67_send` and `test_e2e_udp` open UDP sockets, loopback
only but excluded on instruction); reac-kmod `make check` 7/7 gates and `lock-contract.sh` 5/5.
Nothing was loaded, no raw socket opened, the rig untouched.

### B1 — a loss gap of 32768 packets or more reports ZERO loss and permanently shifts the PTP timeline

`reac-aes67/src/media_clock.c:40`:

```c
int16_t delta = (int16_t)(uint16_t)(counter - mc->last_counter - 1);
```

Reading it signed is deliberate and correct for duplicates and reordering — the comment at
:36-39 explains why, citing reac-tools' `analyzer._signed_delta` as the convention. But at a gap
of 32768 the value flips negative and the packet takes the "duplicate or reordered" branch at
:42-50, which advances `rtp_ts` by one packet, adds nothing to `total_lost`, emits no
concealment, and — the part that does the lasting damage — **never updates `last_counter`**.

Measured, with a positive control:

```
gap= 1000  -> silence_packets= 1000  total_lost= 1000  rtp_ts=  12012 (correct  12012)
gap=32767  -> silence_packets=32767  total_lost=32767  rtp_ts= 393216 (correct 393216)
gap=32768  -> silence_packets=    0  total_lost=    0  rtp_ts=     12 (correct 393228)
gap=40000  -> silence_packets=    0  total_lost=    0  rtp_ts=     12 (correct 480012)
```

32768 packets is **8.19 s at 48 kHz, 4.10 s at 96 kHz** — one Wi-Fi stall or one cable pull on
the WDS link this bridge exists to cross.

**How it shows up.** The LuCI "Loss" column (`openwrt/luci-app-reac-aes67/.../status.js:85`
reads `loss_total`) shows **0** across the single worst event of the show. And on the Dante path
— `pipeline_anchor` → `media_clock_init_anchored`, announced as `a=mediaclk:direct=0` in
`src/sdp.c:68` — the RTP timeline is now 8.19 s short of TAI **permanently**. The receiver's
playout no longer maps to the grandmaster, and the header's promise at `src/media_clock.h:35`
("under genlock, sample-counting stays TAI-aligned forever") is void until restart. Nothing
announces it.

**Would a test have caught it?** No. `tests/test_media_clock.c:57` reorders by −2;
`test_counter_wraps` (:75) wraps by one packet. Nothing goes near ±32768.

**Recommendation, not applied:** clamp the gap and re-anchor (`last_counter = counter`) with a
distinct "resync" counter, rather than laundering a multi-second outage as a reorder.

### B2 — `--tone-detune` emits a phase discontinuity on 36 of 40 channels

`reac-aes67/src/tone.c:128` wraps the **base** phase by 2π, but `:120` scales that base phase by
`f/freq_hz` per channel. A 2π step in the base is `2π·f/f0` in a detuned channel — not a multiple
of 2π. Measured, as the seam step at the packet boundary over the largest legitimate in-packet
step (1.00 = continuous):

```
control detune=0  ch 0/10/39   ratio 1.00  (clean everywhere)
detune=50  ch  0  f=1000  ratio 1.00
detune=50  ch  5  f=1250  ratio 7.04   <-- discontinuity
detune=50  ch 10  f=1500  ratio 7.89   <-- pi jump, full inversion
detune=50  ch 20  f=2000  ratio 1.00   (integer ratio, accidentally clean)
detune=50  ch 35  f=2750  ratio 4.49   <-- discontinuity
```

The base phase wraps every 5 packets, so a waveform inversion every 1.25 ms — an ~800 Hz buzz.
`tone.c:120` also divides by `t->freq_hz`, so `--tone-freq 0` yields NaN across all 40 channels.

**How it shows up.** `--gen-tone` exists precisely "to prove the receiver end without a mixer on
the bench" (`src/main.c:12-13`). Channels 1 and 21 sound clean and the rest buzz, so you conclude
the Dante receiver or the network is broken. It is the generator. A bench tool that
manufactures the fault it is used to rule out is worth more than its rank suggests.

**Would a test have caught it?** `tests/test_tone.c:47` checks continuity **only on channel 0**
(:56-57) — the one channel where `f == f0` makes the wrap exact.
`test_per_channel_detune_differs` (:64) asserts only `c0 != c39`, which any garbage satisfies.

### B3 — reac-repacer counts ring-full drops and shows them nowhere

`reac-repacer/tools/reac_repacer.c:508,509` increment `n_drop_full`. There is no other use of
that variable anywhere: not in the 2 s telemetry line (`:1914-1924`), not in the shutdown summary
(`:1939-1940`), not in `ubus call reac_repacer get` (`:1042-1045` publishes rx/tx/underrun/plc
only). Meanwhile `:774` restamps every emitted frame with the daemon's own monotonic counter, so
the dropped frames are spliced out and **renumbered contiguous** — the stagebox cannot detect
them either.

**How it shows up.** A WDS burst overruns the ring, audio is spliced, and every instrument you
have — the log line, the ubus object, the LuCI page, and the box's own counter — says the link
was perfect. `docs/internals.md:191` tells the operator to read `underrun` and `plc` "to tell you
how often it happened"; those cover the *empty* case. The *full* case has no reader at all.

**Would a test have caught it?** No; reac-repacer has no test that runs the relay.

### B4 — reac-aes67's LuCI "Pkts/s" is a constant and "Uptime" is not uptime

Two of the five numbers on the status page are fabricated.

- **Pkts/s.** `src/main.c:312` — `int pps = lc->mode->sample_rate / lc->mode->samples_per_pkt;`
  passed to `ubus_stats_update` as `packets_per_sec` (`:314` → `src/ubus_stats.c:79`) and
  rendered at `status.js:67,:84`. It is derived from configuration. Unplug the stagebox and the
  page still says **4000 pkts/s**. This is the single most likely field to be looked at when
  someone asks "is REAC arriving?", and it cannot answer that question.
- **Uptime.** `main.c:314` — `(unsigned)(g_listen_pkts / (pps ? pps : 1))` → `uptime_s`
  (`ubus_stats.c:78`) → `status.js:71,:88`. It is *seconds of audio received*. On a link losing
  40% of frames it runs at 60% of wall clock; on a dead link it freezes. "The bridge has been up
  3 minutes" after 5 minutes of running is a 40% loss rate wearing a clock's clothes.

**Would a test have caught it?** No. `tests/test_stats.c` is titled "the data the ubus status
object publishes" (:4) but exercises only the pure `pipeline_stats` core and never links
`ubus_stats.c`. Both fabricated fields are computed in `main.c`, outside everything tested.

### B5 — reac-repacer's startup banner prints the state of two knobs that do not exist

`tools/reac_repacer.c:1387` prints `plc=%d reclaim=%d` from `g_plc` and `g_reclaim`. Neither is
read anywhere else — `grep -n g_plc` gives 176 (declaration), 1237 (parse), 1387 (the banner);
`g_reclaim` gives 177, 1239, 1387. Yet both are documented as working: `--no-plc` in the man page
at `reac-repacer.8:65,186` and in `docs/internals.md:184`, which even cites
`reac_repacer.c:686-699` as the reader — a line range that does not read it; `--reclaim` in
`usage()` at `:1173-1174`, the man page `:125`, and `internals.md:123`.

**How it shows up.** You disable concealment to find out whether the link is really delivering
frames, the log confirms `plc=0`, the box stays silent-and-happy, and you conclude the link is
clean. That defeats exactly the diagnostic the man page tells you to use —
`reac-repacer.8:60-66`: "an unclicking box is not by itself proof that the link delivered every
frame." A banner that confirms a knob took effect is worse than no knob.

### B6 — reac-repacer's prefill barrier has no timeout, and four RX paths hold three VLAN policies

`tools/reac_repacer.c:1480-1490` — `any_active` is set only for ports with `n_rx != 0`, so if no
frame ever arrives the loop spins at 1 ms **forever** after printing only `auto-rate: no input
seen on any port`. It never reaches `repacer: prefilled, pacing` and never exits, so procd's
`respawn 3600 5 5` (`openwrt/files/reac-repacer.init:114`) never fires. The ingest-settle loop
directly above it does have a 30 s cap (`:1404`); this one has none.

The trigger is easy, and it is the second half of this finding: `fwd_rx` accepts **untagged
frames only** (`:487`, `buf[12]==0x88 && buf[13]==0x19`), while `clk_meter` (`:560-561`),
`ds_pacer` (`:621-622`) and `inj_copy_rx` (`:398`) all handle 802.1Q. Four RX paths in one file,
three VLAN policies. Give the daemon a tagged interface and it hangs with no error and no
counter.

Related: `clk_meter` also ignores every frame under 1000 bytes (`:561`), tuned for the
40-channel downstream broadcast at 1492 B. An S-0808 return is 340 B, an S-1608 return 628 B, an
S-4000 return 1204 B. Point `--clock-source local` at anything narrower than 32 channels and the
meter counts zero, `clk_act` never latches, and the only symptom is `clk=acq` forever in the
telemetry line with no explanation. The shipped AP/STA profiles both meter the master broadcast,
so this is latent — but that magic `1000` is the one geometry constant in the tree with no name
and no comment.

### B7 — smaller reac-aes67 correctness items

- **`--bcast-only` is dead in the Dante profile.** `g_bcast_only` (`main.c:279`) is consulted
  only through `frame_wanted`, called at `:301` and `:405`, both inside `run_listen`;
  `run_dante`'s own capture loop (`:656-667`) never calls it. The comment at `:281-285` says what
  happens without the filter: "decoding them together interleaves two independent counter streams
  into concealment garbage." There is also **no UCI knob for it at all**, so on OpenWrt the filter
  is unreachable in both profiles.
- **`--plc-xfade` / `--plc-fade` are honoured in one mode of three.** `run_listen` calls
  `pipeline_init_ex` (`main.c:332`); `run_pcap` (`:263`) and `run_dante` (`:628`) call plain
  `pipeline_init`, which hardcodes `0, 0` (`pipeline.c:129`). `validate_stream_section`
  (`reac-aes67.init:45-46`) accepts them regardless.
- **A failed RTP build counts as a sent packet.** `pipeline.c:150-156` — `if (n > 0) emit(...)`,
  but `stats.packets++` and `rtp.seq++` run unconditionally. Same shape at
  `packetizer.c:163-166`, where an out-of-range slice is skipped with no counter and no log, so a
  misconfigured `ch_per_flow` yields a silent flow nothing reports.
- **Multicast egress pinning fails silently.** `aes67_send.c:63` — if `ifname_to_addr` fails (the
  interface has no IPv4), `IP_MULTICAST_IF` is never set and the stream follows the default
  route, which the comment itself says "on a router goes out WAN" (`:60`). Returns success. The
  AES67 stream is nowhere on the LAN and the daemon reports nothing.
- **Unbounded concealment burst.** `pipeline.c:183-188` emits `step.silence_packets` RTP packets
  in one call — up to 32767, roughly 45 MB of UDP as fast as the socket takes it, from inside a
  single `reac_capture_next` iteration.
- **Discarded return codes.** `reac_repacer.c`: `mlockall` (:1308), `sched_setaffinity`
  (:479,:540,:614,:1347), `setsockopt` (:465-467,:547) and **every** `pthread_create`
  (:1325,:1326,:1330,:1333,:1337). A failed `fwd_rx` thread leaves the port dormant forever with
  no message — indistinguishable from B6. Same in `aes67_send.c:52,56,64,67`.
  **Malloc-without-free on an error path: none found**, in any of the three. That class is clean.

### B8 — reac-kmod: two small items, and an otherwise strong repo

- **`claim` on an already-claimed segment logs the wrong cause.** `src/lock.c:43-44` returns
  `-EALREADY`; `src/segment.c:159-162` treats any non-zero as "refused: segment lock
  unavailable". dmesg accuses a competing master when the module already owns the lock. The errno
  differs (−114 vs −98) so it is recoverable, but the sentence is wrong.
- **`reac-segment-lock probe` briefly takes the lock it is probing.**
  `tools/reac-segment-lock.c:185` binds, `:197` closes. A reac-pw trying to bind in that window
  gets `EADDRINUSE` and refuses the segment. Worse, the mode string is validated *after* the bind
  (`:201`), so `reac-segment-lock hodl eth1` also takes and drops the lock. A diagnostic that can
  cause the fault it looks for — and one that matters right now, with two masters live.
- **Attaching changes an interface's `rx_dropped`.** `segment.c:104-110` registers a
  `packet_type` for `0x8819` and consumes the skb; frames that previously hit the kernel's drop
  path and bumped `dev->rx_dropped` now do not. Audio is unaffected and so are reac-pw's
  AF_PACKET copies, but `ip -s link` stops counting REAC frames as dropped after `attach`, which
  narrows the claim at `main.c:65-66` ("changes no packet's fate"). Flagged as a mechanical
  consequence, not a proven operator report.

### Half-built: the config knobs nothing reads

Every option in `openwrt/files/*.config`, the init scripts, the LuCI views, `packaging/*.conf`,
`meson_options.txt` and the man pages was traced to a reader.

**reac-repacer — two fully dead, four mis-described:**

| Knob | Declared | Reader |
|---|---|---|
| `--no-plc` / `g_plc` | `reac_repacer.c:176,1237`; man `:65,:186`; `internals.md:184` (which cites a line range that does not read it) | **NONE** — B5 |
| `--reclaim` / `g_reclaim` | `:177,1239`; `usage()` `:1173-1174`; man `:125`; `internals.md:123` | **NONE** — B5 |
| `pll` | UCI `:45` (AP=1), init `:32`, LuCI `:93` "Phase-lock the output clock" | Read at `:1691`, gated on `!clk_alive` — and the AP profile ships `clock_source=local`, which makes `clk_alive` true (`:1690`). **Inert on the shipped AP configuration**, and it is a *frequency* lock, not a phase lock |
| `pace_by_downstream` | UCI `:46`; LuCI `:98` and `internals.md:268` both say "from the downstream port **occupancy**" | Read at `:1335,:1764` — the code phase-locks to downstream frame **arrival timestamps** (`ds_pacer`, `:604-626`), and `:1891` is emphatic that "jitter-buffer occupancy is NEVER an input or trigger to the clock". The description is wrong in both places |
| `detect_ms` | LuCI `:56` "how long to look for a REAC stream before declaring the port idle" | Read at `:1779` — it is the telemetry/rate-detect period. No port is ever declared idle |
| `servo_clamp_ppm` | LuCI `:49` "Latency-reclaim rate (ppm)" | Read at `:1538,:1646,:1663`, but `:1646` is gated on `!g_steady` and `g_steady` defaults to 1 (`:228`). On every shipped configuration the servo is off and `bias_ppm` stays 0 |

Everything else in `reac-repacer.config` traces to a real reader — `enabled`, `wait_iface`,
`cpu`, `prefill_ms`, `clock_margin_ppm`, `forward_only`, `etf`, `etf_delta_us`, the four `adapt_*`
keys, `role`, `clock_source`, `bcast_only`, `port`. **A dead ubus ACL:**
`luci-app-reac-repacer/root/usr/share/rpcd/acl.d/*.json` grants `reac_repacer: [get]` and
`[set]`, and the LuCI view calls neither — the single `ubus` hit in `config.js` is line 45, inside
a help string telling the operator to run `ubus call` from a shell. The daemon publishes per-port
`occ`, `underrun` and `plc` (`:1040-1045`) and no page shows them.

**reac-aes67 — knobs dropped between layers:** `plc_xfade`/`plc_fade_pkts` on the Dante branch;
`rate` on the Dante branch (`reac-aes67.init:77-87` omits `--rate`); `--bcast-only` with no UCI
representation at all; `--origin` with no UCI knob, so every SAP announcement from an OpenWrt
install carries origin `0.0.0.0`. The validator accepts `rate:or("48000","96000")` (`.init:39`)
while the C supports 44100, so a supported rate cannot be expressed — and conversely `--rate 9600`
is silently accepted and becomes 48000 (`libreac/src/reac.c:20-25` returns the 48 k mode for
anything unknown), with no warning.

**reac-kmod — this class is EMPTY, and that is worth saying.**
`grep -rn "module_param\|MODULE_PARM" src/` returns nothing (positive control:
`MODULE_LICENSE/AUTHOR/DESCRIPTION/VERSION` all present at `src/main.c:126-129`). `dkms.conf` has
five keys, all consumed by DKMS itself, and `PACKAGE_VERSION` is mechanically tied to
`src/reac_kmod.h:19` and the spec by `tools/version-check.sh`.

**Dead code:** `reac_repacer.c:571-601` `ds_emit_one()` is marked `__attribute__((unused))` and
never called — a 30-line duplicate of `pace_one`'s emit body (`:758-783`) that has to be kept in
sync by hand. `:266` declares `n_skip` and `n_hold`, never incremented or read; `n_ctrl` is
incremented at `:500` and never read. `:273-274` `edit_win` (written `:710`, never read),
`edit_owe`, `edit_gap`, `adapt_cnt`, `gh`, `sd`, `occ_sum`/`occ_cnt` are only ever zeroed; the
per-stream `t_floor`/`t_ceil` computed at `:711-712` are never read, the pacing loop using its own
locals at `:1549-1550`. In reac-aes67, `src/ubus_stats.h:40` declares `ubus_stats_poll()`, defined
twice (`:170`, `:242`) and **called by nothing** — its comment says "call from the daemon loop"
and the fallback loop (`main.c:397-413`) does not. `status.js:78`'s "not running" branch is
unreachable, because the daemon always sets `running: 1` (`ubus_stats.c:77`) and a dead daemon's
rpc call is dropped by `.filter(Boolean)` at `:76`.

**No TODO/FIXME/XXX in any of the three**, and no header declaring a function no `.c` defines —
every prototype in `reac-aes67/src/*.h` and `reac-kmod/src/reac_kmod.h` resolves.

### Test honesty for these three

**The clearest "cannot fail" cases in the census, and their own headers say so.**
`reac-aes67/tests/test_repacer_steady.c` and `test_repacer_retarget.c` test **reac-repacer**,
which lives in a different repository, by hand-copying its algorithm.
`test_repacer_steady.c:8-13` states it: "the logic below is a HAND MIRROR of it ... these tests
cannot fail when the real re-pacer changes."

- `steady_ifi_sd` (`:98-118`) advances `dl += period` with `period` a constant (`:112`), so every
  inter-frame interval is exactly `period` and `stdev` is **0 by construction**.
  `ASSERT(sd_lo < 1.0)` (`:134`), `ASSERT(sd_hi < 1.0)` (`:135`), `ASSERT(steady_lo < 1.0)`
  (`:160`) and `ASSERT(steady_hi < steady_lo + 0.1)` (`:168`) all assert that adding a constant
  produces a constant. The test is named `test_steady_ifi_independent_of_input_jitter`, and the
  arrival series it builds at `:126-130` is never read by the emitter it grades.
- `test_repacer_retarget.c`: `schedule()` (`:27-40`) is a verbatim copy of `apply_hot_params`
  (`reac_repacer.c:901-912`) and `simulate()` (`:43-48`) is its exact algebraic inverse. It
  cannot fail unless someone edits both halves inconsistently.
- **The mirror has already drifted.** `parse_lock` (`test_repacer_steady.c:175-191`) copies
  `lock_load` (`reac_repacer.c:648-666`) but **drops the ±5% period sanity check**
  (`reac_repacer.c:660-661`), and uses `char nm[32]`/`%31s` where the original has
  `char nm[IFNAMSIZ]`/`%15s`. The test accepts records the real parser rejects.

Net: reac-repacer's steady clock, its warm-start file and its live-retune have **no test in
reac-repacer**, and the tests that claim to cover them live in another repo and never link the
subject.

**`reac-repacer/tests/inject_goldens.inc` — the goldens are generated by the code under test.**
Line 1: "generated by tests/test_inject.c --regen", and `./tests/test-inject --regen` reproduces
the checked-in file byte for byte. `test_inject.c:17-18` is honest that the fixture came from
"this same driver run against the pre-libreac implementation". So it is a **change detector, not
a wire oracle** — green today even if the braid had been wrong from day one. It does bite, which
was sabotage-verified: masking one bit in `braid_write` (`reac_repacer.c:385`) took the suite
from 0 failures to **2180 failures**, exit 1. `roundtrip_case` (`:124-148`) is explicit
self-consistency and says so at `:115-123`; it passes against any consistent-but-wrong map. And
its report line is wrong: `:214-216` prints a hardcoded 420 slot injections per injector where
the actual figure is 840 (Σ nch for even 2..40 = 420, × 2 trailer variants).

**Better than expected:** `reac-repacer/tests/test_geometry.c` checks `frame_channels` against
libreac's **independent** oracle (`reac_upstream_channels`, `:73-76`), enumerates the four real
rig widths by hand (`:67-70`), and makes the malformed case concrete by computing the exact byte
the bad stride would land on and asserting the end marker survives (`:91-108`). That is real
reasoning against an outside source.

**`reac-aes67/tests/test_decode.c` is the strongest test in the census.**
`test_inspect_valid_48k` (`:36`) asserts `counter == 0xfd7e` from a real captured pcap — a wire
fact. `test_build_decode_roundtrip` (`:90`) carries a **negative control**:
`ASSERT(plain_maxerr > 0.5f)` (`:143`) requires the plain-LE reading of the same bytes to be
wrong, which is what stops a shared-assumption pass. Its limit is labelled honestly at `:9-12`:
`test_decode_known_sample` (`:49`) is "a fixture/offset/sign check and deliberately not a layout
check". So **no assertion anywhere in reac-aes67 distinguishes the braid from another layout on
real captured audio** — both halves of the round trip are libreac's, and the pcap contributes one
counter value and one all-ones sample.

**`reac-aes67/tests/cross_verify.py` is exemplary and should not be touched.** Its docstring
(`:6-31`) names itself "NOT a cross-check", explains that an oracle adopting the assumption under
test cannot test it, records that this file *used to* assert the layout the other way and was
wrong, and prints the caveat on success (`:129-130`). Two brittleness notes: `c_decode_frames`
parses `parts[3]` (`:99`) and will `IndexError` on the `frame N: MALFORMED` line `main.c:241`
emits; and the Python side skips non-REAC packets (`:68`) while `--dump-samples` prints a line for
every packet, so a mixed capture desynchronises the comparison.

**`reac-kmod/tools/smoke.sh` — a real gate, sabotage-verified by its author, with one gate that
cannot see what it names.** The good first: `:15-19` documents and fixes the exact
`objdump | grep -q` SIGPIPE trap that made two gates report false negatives, and `:28-30`
documents the `set -e` + pipeline trap that swallowed a failed build. Both are the right kind of
scar.

**Gate 4, "no undefined libreac symbols" (`:65`), cannot catch the break its own comment
describes** — "it would happen by an #include, quietly" (`:64`). It runs
`nm -u reac.ko | grep -c '^reac_'`, which sees only **unresolved imports**. Proven by sabotage:
libreac's GPL-3.0 braid byte map and a `reac_frame_clean_len` were vendored into a scratch copy of
`src/segment.c`, built, and `tools/smoke.sh` run unmodified:

```
no undefined libreac symbols                         ok
smoke: all gates pass (kernel 7.1.9-200.fc44.x86_64)
$ nm reac.ko | grep reac_frame_clean_len
0000000000000450 T reac_frame_clean_len          <-- GPL-3 code, in the binary, gate green
```

An `#include` of a header-only inline is even less visible: `reac_braid.h` is entirely
`static inline`, so it produces no symbol at all. This is the only thing standing between the
project and a GPL-2/GPL-3 link, and it is looking in the wrong direction. Gate 7, "no transmit
path linked" (`:90`), lists `netdev_start_xmit` — a static inline that can never appear in
`nm -u` — and misses `sock_sendmsg`/`kernel_sendmsg`/`skb_send_sock`, which matter because the
module already links AF_UNIX socket calls (`lock.c:60-66`). Gate 3, "no floating-point
instructions" (`:58`), greps x86-64 mnemonics only, so on any non-x86 DKMS autoinstall target it
finds nothing and reports `ok` — a scan measuring nothing.

**`reac-kmod/tests/lock-contract.sh` is above expectations.** Step 1 (`:31-32`) establishes that
the probe *can* report `FREE` before step 3's `HELD` (`:48`) is trusted — the "prove the probe can
detect presence first" discipline, applied unprompted. Step 5 (`:66`) tests the death property the
kernel side deliberately lacks. Its scope limit is stated at `:5-8`: both holder and prober are
`reac-segment-lock`, so the module's own `reac_lock_acquire` is never exercised. And note that
smoke gate 6 greps for `reac-pw/segment/%u/%d` (the module's format, `lock.c:32`) while the tool
uses `%u/%u` (`reac-segment-lock.c:128`) — the same output for any real ifindex, but nothing would
catch the two drifting.

**`reac-kmod/tests/netns-key.sh` exits 0 having asserted nothing, in its normal state.** `:15` —
`[ -d /sys/kernel/reac ] || { echo "module not loaded, skipping"; exit 0; }`, and loading requires
Secure Boot enrolment. Neither this file nor `lock-contract.sh` is invoked by anything: `make
check` runs only `tools/smoke.sh` (`Makefile:30`), and reac-kmod has no CI. Both are cited as
evidence in `README.md:44` and `docs/verification.md:141,196`.

**Gates whose name no longer matches what they measure:**

- `test_96k_uses_24_samples` (`reac-aes67/tests/test_media_clock.c:99`) hand-passes `24` to
  `media_clock_init`. `REAC_MODE_96K` is `{96000, 40, 12}` (`libreac/src/reac.c:18`). The name
  states a wire fact that is **false**, and the test never touches the 96 k mode. `test_plc.c:144`
  in the same suite asserts `st.S == 12` for `REAC_MODE_96K` — two tests in one tree disagreeing
  about the 96 kHz geometry.
- `test_sdp_96k_20ch` (`tests/test_sdp.c:29`) hand-passes `channels = 20`; no such mode exists.
- The same fossil is in a shipped header: `src/plc.h:14` says "(12 @48k/40ch, 24 @96k/20ch)", and
  it sizes every `REAC_MAX_CHANNELS * 24 * 3` buffer (`pipeline.c:57,72,95`; `main.c:237,435,436`;
  `packetizer.h:53`). Those over-allocate 2×, so they are harmless slack — but the belief is
  wrong, and the UCI config file states the truth at `reac-aes67.config:6-9`: "96 kHz does not
  halve channels."
- reac-repacer's `PLL_RECOVER_SECS` recovery term hardcodes 8000 fps
  (`reac_repacer.c:1711`), so at 44.1 k (3675 fps) the advertised "60-second recovery" takes 130 s.

**CI coverage.** reac-repacer's only workflow is `sanitize-guard.yml`, a token grep — **its two
unit tests run in no CI.** reac-aes67 has real CI (`ci.yml:14-16`) but clones libreac at
`--depth 1` from `main`, unpinned. reac-kmod has no CI at all.

### Duplicated logic in these three: every copy agrees

`reac-aes67/src` does **not** re-implement REAC parsing. The premise that both repos carry
`subprojects/libreac.wrap` is false — `find reac-aes67 -name '*.wrap'` returns only the
out-of-scope `pipewire/` one. The top-level tree links libreac through a plain Makefile
(`Makefile:29-52`) and pulls `<reac/reac.h>` into six headers. A sweep for hard-coded wire
constants across `reac-aes67/src/*.c` found **zero** literal byte offsets, **zero** `0x8819` and
**zero** `1492`/`1440`/`50`.

reac-repacer is mixed but consistent — symbolic where it computes, literal where it touches bytes
directly:

| Constant | libreac | reac-repacer literals | Agree? |
|---|---|---|---|
| EtherType `0x8819` | `reac.h:19` | symbolic `:398,399`; literal `:487,524,561,621,622` | **yes** |
| counter offset 14 | `reac.h:27` | `:579,591,592,762,773,774`; `:562` via `eo+2` | **yes** |
| frame-type offset 16 | (no symbol) | `:399,413,433,498,580,593,763,775` | n/a |
| filler-audio start 18 | `reac_ctrlblk.h:41` | `:581,594,764,776` | **yes** |
| audio offset 50 | `reac.h:22` | symbolic `:401,415,436`; literal `:394,413,433` | **yes** |
| overhead 52 / per-ch 36 | `reac.h:53-54` | symbolic only | **yes** |
| `0x1988` (htons) | — | `reac-kmod/src/reac_kmod.h:22`, a forced second definition (a GPL-2 module cannot link GPL-3 libreac) | **yes**, and checked by `smoke.sh:73` |

The one place a divergence could have hidden is the mute path's `memset(f + 18, ...)` (`:581`),
which looks like it wipes the 32-byte control block — but it is gated on `f[16]==0 && f[17]==0`,
and `libreac/include/reac/reac_ctrlblk.h:39-40` states that FILLER frames carry audio at [18:50]
instead of a control block and are checksum-exempt. The code is right, and right for a subtle
reason. It also never touches the checksum byte at 49 on a control frame, because it only ever
restamps [14:15], which the checksum does not cover.

**The one genuine second copy of the byte map** is `reac-aes67/tests/cross_verify.py:75-84`,
despite `libreac/include/reac/reac_braid.h:41-42` saying "Do not add a second copy of this byte
map anywhere." It is labelled as such at `:74-79` and it matches `reac_braid_pos` exactly. Also
duplicated but agreeing: the s24 sign-extension appears four times (`plc.c:16`, `main.c:248`,
`tone.c`, `reac_repacer.c:377`) because libreac's `reac_sample.h` offers only float converters,
not an int32 pair — arguably a gap in libreac rather than a defect here.

**And a fourth disagreeing libreac version number**, extending D-2 above:

| Source | Declared libreac version |
|---|---|
| `libreac/packaging/libreac.spec:4` | **0.6.0** |
| `libreac/openwrt/libreac/Makefile:10` | **0.5.0** |
| `libreac/src/reac.c:12-13` (`LIBREAC_VERSION` fallback) | **0.5.0** |
| `reac-repacer/subprojects/packagefiles/libreac/meson.build:25` | **0.4.0** |
| installed on this host (`pkg-config --modversion`) | **0.6.0** |

So libreac disagrees with **itself** in three places, before any consumer is considered. The
constants all agree, so this is not a wire-format divergence — but it means no version floor
anywhere in the stack is a real gate. reac-aes67's is the best of them: `Makefile:43-45` actually
runs `pkg-config --atleast-version` and errors out, though only on the `LIBREAC_SYSTEM=1` path,
and its own comment at `:26-28` admits the sibling-checkout default is unchecked.

### These three, in better shape than expected

- **reac-kmod is the strongest of the three.** No module parameters means the whole "config knob
  nothing reads" class is empty. The build is clean on 7.1.9, all 7 gates pass, and the gates are
  the right *kind* — mechanical, two of them carrying the scar of the false negative they were
  fixed for. `lock-contract.sh` uses a positive control unprompted. The `(netns, ifindex)` keying
  (`segment.c:38-46`) and the teardown-order fix (`:255-263`) are both documented with the
  live-rig incident that forced them. Its one real weakness is that its licence gate cannot see
  the licence break it names.
- **reac-aes67's test-honesty documentation is the best in the tree.** `cross_verify.py:6-31`
  refutes its own former claim in writing, names the epistemics correctly, and prints the caveat
  on success. `test_decode.c` carries a real negative control. The source has zero hard-coded wire
  constants. Its defects are concentrated in two places: the ubus/LuCI presentation layer, which
  nothing tests and which fabricates two of its five numbers, and the ≥32768 counter boundary.
- **reac-repacer's comments are load-bearing and mostly accurate**, and `test_geometry.c` is
  genuinely good. But it is the only one of the three whose shipping behaviour contradicts its own
  man page in two places, whose ring-full drop counter has no reader, and whose unit tests run in
  no CI.

---

## 4. openmixer's REAC-facing code

Surveyed separately because it is the only consumer of this stack that an operator touches
directly. Full file:line detail was gathered for ~47 files; what follows is ranked and trimmed.

### O1 — the SENS number means two different things, ten decibels apart

**This is the most consequential cross-repo disagreement in the census, and it needs a ruling
rather than a patch.** It is written up here with the evidence and without pre-empting one; the
disputed-facts lane may already own it.

openmixer publishes the REAC preamp travel as **0..55 dB**:
`openmixer/packages/declarations/src/index.ts:103-107`, restated in the design specs at
`docs/design/specs/2026-08-06-channel-contract.md:150` ("0..55 on a Roland box and 0..65 on an
RME mic input"), `2026-08-22-osc-surface.md:178`, and `2026-08-22-stagebox-identity-and-device-
model.md:89`. The write path is deliberately arithmetic-free —
`packages/audio-engine/src/reac-head-amp.ts:548` sends `clampGainDb(gainDb, {0,55,1})` as the
SENS byte, with the comment at :540-542: "the box's SENS VALUE byte runs 0x00..0x37 at exactly
1 dB per step, so it IS the gain in dB ... there is no arithmetic left to get wrong."

libreac and reac-pw anchor the same byte ten decibels higher. Verified in the C directly:
`libreac/src/reac_ctrlblk.c:167-172` computes `sens_cdb = -1000 - value*100 + (pad?2000:0)`, so
byte 0x00 pad-off is **-10.00 dBu**, and `libreac/src/reac_ctrlblk.c:913-915` grounds that on the
desk's own display — "Ground-truthed on the M-200 SENS display: pad off 0x00 = -10 dBu ..
0x37 = -65 dBu". `reac-pw/src/reac_slave.c:161` then defines gain as the negated sensitivity,
`gain_cdb = -reac_headamp_sens_cdb(...)`, giving **+10..+65 dB** for the same bytes openmixer
labels 0..55.

| byte | openmixer says | reac-pw says | Roland's own display |
|---|---|---|---|
| 0x00 | 0 dB | +10 dB | -10 dBu |
| 0x20 | 32 dB | +42 dB | -42 dBu |
| 0x37 | 55 dB | +65 dB | -65 dBu |

**Two corrections to how this was first reported, because the severity turns on them.**

1. **No actuator range is lost.** `clampGainDb` bounds to 0..55 and those map to bytes
   0x00..0x37 — the box's entire 56-step travel. Every gain the preamp can produce is reachable
   from openmixer. The earlier framing that "the top 10 dB is unreachable and the bottom 10 dB
   does not exist" is wrong.
2. **The audio is not wrong.** The byte written is the byte intended; the slope (1 dB/step) and
   the span (55 dB) agree on both sides. Nothing is misrouted or mis-gained relative to what the
   operator asked for on openmixer's own scale.

**So what is actually wrong is the reference point, and it is a genuine ambiguity rather than an
obvious bug.** "Gain" relative to the preamp's own minimum (openmixer) and "gain" relative to a
0 dBu nominal (reac-pw, from the desk's sensitivity display) are both defensible readings of the
word. They are not interchangeable, and nothing in either tree states which one the wire
vocabulary means.

**How it shows up.** Three ways, all of them latent today and none of them self-announcing:

- An operator cross-checking openmixer against a Roland desk's own SENS display reads 32 against
  -42 and has no way to know the two describe the same setting.
- The moment a read-back exists it will be ten off. openmixer currently has **no query arm at
  all** (O5), so the disagreement cannot yet surface as a contradiction — the console never asks
  the box what it is set to. That is the only reason this has stayed invisible.
- reac-pw's virtual-box slave role reports gain on the +10..+65 scale
  (`reac-pw/src/reac_slave.c:148-163`), so a bench setup pairing openmixer against a virtual box
  will show two numbers ten apart for one setting.

**No test constrains it, and the test that looks like it does is a tautology.**
`openmixer/packages/core/src/head-amp.test.ts:37` asserts `REAC_HEAD_AMP_GAIN_RANGE` equals
`{minDb: SENS_VALUE_MIN, maxDb: SENS_VALUE_MAX, stepDb: 1}` — but `SENS_VALUE_MIN` and
`SENS_VALUE_MAX` are *defined as* those very fields at `packages/core/src/head-amp.ts:87,89`.
Lines 43-49 then loop 56 times asserting `clampGainDb(db) === db`, that a round number rounds to
itself. The suite is named "the REAC travel is DEDUCED from the box"; it is deduced from a
constant beside it, and would pass identically at `{10, 65}`.

**The fix pattern already exists in this repo.** `packages/declarations/src/index.ts:154-156`
pins `OMX_EQ_MAX_BANDS` to the native header, and `output-delay-ceiling.test.ts` *reads that
header*. libreac publishes its curve as three named constants
(`libreac/include/reac/reac_ctrlblk.h:171-175`) with a generated `reac_facts_assert.h` precisely
so a schema can bind to them. Whichever way the ruling goes, binding the travel to those
constants would make a future divergence impossible.

### O2 — the browser computes a different box width than the server

`packages/core/src/stagebox.ts:354-367` tries an anchored tail parse
(`/[—–]\s*(\d+)\s*ch\b/gi`, defined at `:333-341`) before falling back to a loose regex.
`packages/web-ui/app/utils/stagebox.ts:234-242` has **only** the loose `/\b(\d+)\s*ch\b/i`;
`anchoredTailWidth` does not exist in web-ui (three grep hits, all in core; positive control:
`labelStrings` resolves in both).

Core has a named regression test for the exact case —
`packages/core/src/stagebox.test.ts:135`, "does not let an operator-named box's `<digits>ch`
fool the width parse (Drums 8ch — 16 ch)". The web-ui test file has no equivalent.

**How it shows up.** An operator names a box "Drums 8ch". `declaredWidth` takes the minimum, so
the UI clamps to 8: the patchbay shows 8 of 16 inputs, and preamps 9-16 are invisible and
unpatchable in the browser while the server would happily patch them. Neither side knows the
other disagrees.

This is a class, not an instance. `packages/web-ui/app/utils/stagebox.ts` says "Mirrors X in
`@openmixer/core`" four times — `REAC_AUDIO_FABRIC_SLOTS` (line 268, a hand-copied `40`),
`declaredWidth` (277), `groupOf` (295), `isRealBox` (~310). A comment saying "mirrors" is not a
gate.

### O3 — the missing-hardware alarm is gated shut by a key the rig no longer sets

`packages/server/src/reac-config-store.ts:239` returns `{ stageboxes: [] }` unless
`config.label` is set, and `label` exists only when `REAC_BOX` is present (`:123-135`). The
comment eleven lines above, at `:111-116`, records that `REAC_BOX` is gone: "the console unable
to read the LIVE rig's own reac.env, which has carried no REAC_BOX for some time (measured
2026-08-22)."

So `readConfiguredHardware` always returns empty and everything downstream is unreachable:
`diffConfiguredStageboxes` (`packages/core/src/hardware-manifest.ts:330`) and
`diffConfiguredOnly` (`:392`) return `[]` on their first line; `summarizeConfigured` (`:370`) and
the `hardware.missing.configured-on` locale key never render. `hardware-manifest.ts:281-286`
describes this code as the fix for "the rig defect: an unplugged S-0808 said nothing." It is
wired end to end (`console-rig.ts:1964` → `server.ts:4944`) and dead at the source. The
model-contradiction detector dies with it (`console-rig.ts:1968` → `server.ts:4735`).

Adjacent, and the reason nobody noticed: any `reac.env` parse error throws `ReacConfigError`,
swallowed at `console-rig.ts:1968` and again at `server.ts:3979-3983`. The operator edits the
file, sees no error, and the console behaves as though the file does not exist.

### O4 — a box that has not named its model is never adopted, rostered, or made safe

`packages/server/src/server.ts:4550-4551` — `if (!model) continue;`, where `formatBoxModel`
(`packages/core/src/stagebox.ts:483-485`) returns `undefined` for `''` or `'none'`. The comment
justifies skipping the model *recording*; the `continue` also skips `registry.adopt` (`:4564`)
and `determineWhenRestored` (`:4570`).

**How it shows up.** A box streaming audio is absent from `/stagebox`, has no name or `boxId`,
cannot be addressed by a saved patch (patches address `boxId` + input,
`packages/core/src/patch-identity.ts:39-44`), and its preamps are never determined — so phantom
stays wherever the last user left it. It reads as "the box isn't showing up" while audio plainly
arrives from it. It also opens the window for O6.

### O5 — the head-amp has no query arm, so §6c cannot be satisfied

`packages/audio-engine/src/head-amp-resource.ts:196-207` declares `PatchedInput.current` as the
seed that makes the record start at the truth. The only production `PatchedInputs`,
`MixerPatchedInputs` (`packages/server/src/console-resources.ts:370-406`), never supplies it —
deliberately, per its comment at `:366-368`. `current` is populated only by test doubles.

The governing law is
`docs/design/specs/2026-07-30-southbound-actuator-contract.md` §6c: latches are kept honest by
**query and compare**, not blind re-assertion. There is no query.
`native.setNodeProps(id, …)` returning `true` (`reac-head-amp.ts:634`) means "the node is in the
native mirror", not "the box applied it". The deliberate choice is defensible; the consequence —
that the desk never reads a preamp back, so O1's ambiguity cannot be detected and a box that
silently ignored a record looks identical to one that applied it — is not stated anywhere.

### O6 — the saved patch falls back to a remembered port name, which the spec forbids

`packages/core/src/patch-identity.ts:76-78` — `storeLeg` returns `identify(port) ?? port`, where
the spec requires a box and an input with no fallback to a remembered port name. The fallback is
needed for genuine non-box sources, but it makes the two cases indistinguishable: a string leg
means both "correctly a port" and "a box input we failed to identify". `resolveEndpoint`
(`:113-129`) treats it as live and returns the stale port — the defect
`packages/core/src/stagebox.ts:659-660` records as having "moved an S-0808's input 8 onto the
channel belonging to an S-1608 (2026-08-21)".

**How it shows up.** A show saved while a box was un-adopted (O4's window) stores port names.
Reloaded where that node name belongs to different metal, channels come up on the wrong preamps
with no `absent` refusal.

### O7 — two `isPhysicalInputPort`s that disagree; RME mic pres escape the one-preamp guard

Same name, both barrel-exported, different meanings:
`packages/core/src/physical-input-map.ts:112` is transport-general and true for the RME row at
`:78`; `packages/audio-engine/src/reac-head-amp.ts:117` is REAC-only, because
`parseReacCapturePort` returns `undefined` when `ref.adapter !== 'reac'` (`:104`).

Every production consumer imports the REAC-only one:
`packages/server/src/structural-dsp.ts:65` (used at `:1271,:1273` inside
`assertSinglePhysicalInput`) and `packages/server/src/engine-console-state.ts:89` (used at
`:922,:1845` in `collapsePhysicalInputs`). Core's transport-general copy has zero consumers. That
RME mic ports genuinely own preamps is settled in the same package —
`packages/audio-engine/src/software-adapter.ts:116-119`.

**How it shows up.** An RME Babyface mic input can be summed onto a channel that already sources
a REAC preamp. Phantom, pad and gain on that strip become ambiguous: one control, two preamps.
That is exactly what `structural-dsp.ts:1265-1268` exists to prevent.

### O8 — the transport-cross bind refusal is settled law with zero implementation

`docs/design/specs/2026-08-22-stagebox-identity-and-device-model.md:172-176` declares that a bind
across transports is refused, in a code, checked by `transport` equality. Nothing implements it:
`packages/server/src/stagebox-registry.ts:428` (`bindKey`) checks id shape, key shape, entry
existence and key inequality, and no transport; `packages/server/src/stagebox-name-row.ts:178`
implements only `NO_KEY_SURRENDER`; `packages/core/src/resource.ts:236` closes the `RefusalCode`
union with no cross-transport arm; `packages/core/src/stagebox-key.ts:62`
(`stageboxTransportOf`, the only way to extract a transport) has zero callers outside its test.

And `packages/web-ui/app/composables/useStageboxRoster.ts:153` **tells the operator the refusal
exists.**

**How it shows up**, in the spec's own terms: binding an `s1608` entry to a `usb:` key succeeds
silently, and the entry's patch then addresses sixteen XLR ports on metal with twelve inputs of
three kinds. `isOnTheWire` joins by key (`stagebox-roster-row.ts:136-138`) so it reads `absent`
forever, and `refuse` (`:178-179`) forbids surrendering the key to undo it.

### O9 — a bind the registry refused is reported to the client as applied

`packages/server/src/stagebox-name-row.ts:115-129` returns `bound || named`, so a refused bind is
masked whenever the name also changed. Worse, the boolean is read by nothing:
`EngineDoorSlice.write` is typed `Promise<unknown> | void`
(`packages/server/src/engine-door-station.ts:32`) and the station uses it only for rejection
logging (`:64-77`) — and because the slice is `async`, `fired` is always a truthy Promise, so
`if (!fired)` at `:66` can never trigger. `bindKey`/`setName` signal refusal by returning
`false`, never by throwing, so `registrySlice.refusal` ("the registry refused the write",
`stagebox-name-row.ts:131`) is unreachable for every case it was written for.

**How it shows up.** The bind answers 200, the key reads back unchanged, no log line appears.
This is the house defect — a PATCH that changed a number and moved nothing — in a new place.

### O10 — `setName` mints ghost roster entries that cannot be deleted

`packages/server/src/stagebox-registry.ts:287-307`. `setName` validates only the id's *shape*,
then `this.boxes.set(id, {...})` at `:302`, creating an entry for an id never minted. `bindKey`
refuses that case (`:432`) and has a test for it (`stagebox-registry.test.ts:467`); `setName`
does not. No DELETE exists — `buildStageboxRosterRow` (`stagebox-roster-row.ts:194-261`) declares
only `create` (positive control: `patch-crosspoint-rows.ts` does declare `delete:`, so the mold
supports it).

**How it shows up.** A PATCH to `/stagebox/box-deadbeef` from a stale tab creates a permanent row
— a name, no key, no model, width 0/0, presence `absent` — that cannot be removed.

Two siblings in the same file: `setName` (`:287`) and `noteModel` (`:313`) are the only mutators
that skip `await this.init()`, which `adopt` (`:349`), `createVirtual` (`:397`), `bindKey`
(`:429`) and `hasEverHeld` (`:250`) all do — and `:340-342` names that omission as the
accumulate-duplicates trap (`server.ts:3974-3975` closes the window in practice). And `reindex()`
(`:220-226`) silently drops the *second* entry claiming a duplicate key, first-in-file wins, no
warning.

### O11 — `REAC_ROLE` is silently deleted from the operator's file on every write

Documented as operator-settable at `docs/admin/reac-configuration.md:32`, consumed by
`packaging/systemd/reac-pw-master.service:65` (`--role "${REAC_ROLE:-master}"`), present in the
live `reac.env` — and neither read (`packages/server/src/reac-config-store.ts:110`; `role` is
hardcoded `'master'` at `:172`) nor written (`:79-86`). Every `writeReacConfig`, fired on adapter
start and on every settings change (`reac-adapter.ts:183,189`), rewrites the file without it.

Harmless while the unit defaults to `master`, but a rig deliberately set to `slave` is silently
flipped back, and `slave` is unreachable from the console. Directly relevant to
`docs/design/specs/2026-08-20-reac-master-arbitration.md` §1, which requires switching to slave
on an unambiguous foreign master.

### O12 — the bounded wire-channel helper is dead; the actuator uses an unbounded twin

`packages/core/src/reac-slots.ts:3-48` is 48 lines on why the `0x2f` head-amp ceiling and the
40-slot audio fabric must each bound their own direction, citing the "48 V never lit" campaign.
Its head-amp half has no production reader — `headAmpChannel` (`:127`), `isHeadAmpChannel`
(`:111`), `REAC_HEADAMP_SLOTS` (`:64`), `REAC_HEADAMP_CEILING` (`:67`), `REAC_HEADAMP_RING`
(`:73`), `REAC_AUDIO_FABRIC_CEILING` (`:58`), all zero (positive control: `audioFabricFits`
resolves to 2 production refs, so the audio-fabric half is alive).

The actuator re-implements the formula unbounded: `reacWireChannel`
(`packages/audio-engine/src/reac-head-amp.ts:77-79`), used at `:592`. The REAC rows in
`physical-input-map.ts:74,76` carry no `maxInputs` (unlike the RME row at `:78`). The only guard
is `boxInput > caps.channels` (`head-amp-resource.ts:1027`), skipped entirely when caps are
absent or pre-capability, both branches being gated on `caps &&`.

### openmixer half-built inventory

- **~709 lines of superseded discovery, dead but armed.**
  `packages/server/src/reac-pw-prober.ts` (310 lines) and `reac-discovery.ts` (399). Production
  wires `ReacPropsDiscoveryProvider` (`console-rig.ts:1815`); these appear only in their own
  tests. `activeProbe` (`reac-pw-prober.ts:249-257`) spawns `reac-pw --role master --box
  matrix:probe` for up to 5 s — forbidden by
  `docs/design/specs/2026-08-20-reac-master-arbitration.md` ("reac-pw is ONE long-lived daemon
  and never a spawned probe"), documented as the hazard it was replaced for
  (`reac-props-discovery.ts:20-27`), and using a flag reac-pw has retired
  (`reac-pw/src/reac_box_pin.h:13-21`). Five doc-comments still assert the composition root
  injects them (`reac-discovery.ts:12,125,133,161`, `reac-pw-prober.ts:189`). Given that two live
  masters are on the rig right now, dead code that spawns a master is the item on this list to
  delete first.
- **Two disagreeing box-model vocabularies.** `STAGEBOX_MODELS`
  (`packages/declarations/src/index.ts:592-597`) declares `s0808/s1608/s4000s`; the reac adapter
  declares `s0808/s1608/matrix` (`reac-config-store.ts:38`, `reac-adapter.ts:45-49,68,275-279`).
  So an S-4000S operator cannot state the expectation that arms the alarm, and `matrix` is
  offered in an OPTIONS menu while `stageboxModel('matrix')` is undefined, so the roster's create
  door refuses what the adapter panel accepts.
- **Two unreachable `return`s that kill documented offline paths.**
  `packages/web-ui/app/composables/useStageboxes.ts:73` sits after `return serverDevices.value;`
  at `:72`, so the offline derivation promised at `:66-68` never runs and `detectStageboxes` is
  imported at `:28` solely for that dead line.
  `packages/web-ui/app/composables/usePatchbay.ts:413` sits after `:412`, making `deriveDevices`
  (`:364-401`, 38 lines) entirely dead and falsifying the doc at `:407-409`. These are the only
  two of this shape in scope.
- **`reac.discovery.seq`, a documented wedge detector, never read.** `PROP_SEQ`
  (`packages/server/src/reac-props-discovery.ts:49`) is referenced nowhere else (positive
  control: `PROP_STATE` → 4 reads). The staleness rule at `:56-62` is based on a frozen `seq`;
  the check at `:282` uses `age_ms` only.
  `docs/design/specs/2026-07-16-reac-discovery-via-reac-pw.md:54` documents it as what "lets a
  reader spot a frozen publisher."
- **`REAC_BOX` and the achieved pace write into a void.** openmixer parses, validates and writes
  both `REAC_BOX` and `REAC_RATE` (`reac-config-store.ts:79-88`); reac-pw reads exactly one key
  from that file, `REAC_RATE` (`reac-pw/src/main.c:607`), and `REAC_BOX` returns zero hits across
  `reac-pw/src`. Nothing reads back the *achieved* pace either. The pace select writes a file,
  restarts a unit, and nothing verifies the daemon came up at that rate.
- **The port-group control contract is published and nobody reads it.**
  `stageboxPortHasControl` (`packages/core/src/stagebox-ports.ts:44`), documented as "what a
  surface asks before drawing a phantom button", has zero callers outside its test.
  `PortGroupView.controls`/`.sens` (`stagebox-model-row.ts:41,43`) are projected at `:80-81`,
  mirrored into the client type, and never read — `StageboxRoster.vue:89` reads `connector` and
  `count` only.
- **Master-arbitration properties exist only in prose.** The four published properties of
  `docs/design/specs/2026-08-20-reac-master-arbitration.md` — `reac.master.state`,
  `reac.master.mac`, `reac.pace.source`, `reac.clock.source` — appear in no code file, while
  `.claude/spec-map.txt:68` treats that spec as governing `packages/server/src/clock-follow.ts`.
  Positive control: `reac.box-model` and `reac.link-state` return many hits in the same sweep.
  Possibly unstarted work rather than a defect, flagged because the spec-map treats it as live.
- Smaller dead exports: `OUTPUT_GROUP_IDS` (`web-ui/app/utils/patchbay.ts:466`),
  `isStageboxAssignError` (`core/src/stagebox.ts:886`), `boxesReferenced`
  (`patch-identity.ts:140`), `isEmptyPatch` (`patch.ts:187`), `findReacNode`
  (`reac-head-amp.ts:187`), `ReacLifecycle.update` (`reac-adapter.ts:157`). And a stale unit:
  `web-ui/app/utils/capabilities.ts:43` still documents SENS as "dBu" on a field that has been
  dB since #165.

**What the sweep did NOT find, stated because negatives are evidence:** no `TODO`/`FIXME`/`XXX`
markers across the 47 in-scope files; no empty method bodies; no `throw new Error('not
implemented')`. All 14 stagebox/patchbay/patch path constants
(`packages/core/src/resource-paths.ts:180-263`) have both a server registration and a client
reference — no row emitted-but-not-subscribed or the reverse. `/console/defaults` is fully wired.
`/clock/ownership` round-trips completely.

### openmixer test honesty

- **`packages/core/src/head-amp.test.ts:33-50` is a tautology** and it is the only thing standing
  between the desk and O1. Detail in O1.
- **`packages/core/src/reac-slots.test.ts`** — 10 cases, 4 of which (`:64,:75,:81,:90`) test code
  with no production caller, making a dead module look load-bearing.
- **`reac-pw-prober.test.ts` (294 lines) + `reac-discovery.test.ts` (365 lines)** test a path no
  operator can reach, and would go red if someone deleted the hazard.
- **The web-ui `stagebox.test.ts` lacks the case the server was fixed for** (O2). The regression
  test lives in core and was never mirrored with the code it guards.
- **Credit where due: `packages/audio-engine/src/reac-head-amp.test.ts` is honest about the
  write.** It asserts the exact argv (`:105,:113,:122`) and the exact `setNodeProps` call
  (`:161`), so `async setSens() {}` fails it. What it cannot prove is that the box applied
  anything — see O5 — and its name (`:100`, "S-1608 (base 0x20): setPhantom(true) on box input 3
  → …") claims a box where it measures a prop write. That is fine for a unit test; the problem is
  that no tier above it measures the box, so that name is the strongest claim in the whole tree
  about REAC head-amp actuation.

### openmixer duplicated-protocol verdicts

Everything below was checked number by number against libreac and reac-pw.

**Disagree:** the SENS anchor (O1); the default-SENS *dB claim* — `core/src/head-amp.ts:139`
says "the byte IS +32 dB" where `reac-pw/src/reac_headamp_tx.c:48,53` calls the same `0x20`
"-42 dBu pad-off", i.e. +42 dB (the *byte* agrees; and the symbol openmixer names,
`REAC_GRANT_DEFAULT_SENS`, no longer exists in reac-pw, renamed by `56786fd`); and the frame
classifier in `packages/discovery/src/reac.ts` — `:81` requires `sel === 0x82` (S-1608 only)
where `libreac/src/reac_ctrlblk.c:300,328,372` uses `0x84` for S-0808 **and** S-4000S, and
`:100-102` reads the big-endian op-len as a channel count where libreac has it as `00 10`, a
block length, on all three models. That file is dead — nothing imports `parseReacFrame` — and
`packages/server/src/reac-props-discovery.ts:7-12` already states why ("AF_PACKET needs
CAP_NET_RAW, and the engine has none: measured on the rig, CapEff 0"). Deleting its 266 lines
removes three wrong protocol facts at once, and `workspace-reachability.test.ts:293` already
carries the issue number.

**Crossed defaults:** `reac-adapter.ts:76` defaults the pace to 48000 and the mixer to `m5000`
(`:112`); `reac-pw/src/reac_master.h:561` defaults to 96000 and `main.c:407` to `m200`. Bites
only when the operator never picked one — on this 96 k rig an unset pace starts the segment at
48 k.

**Agree, verified, no action:** slot geometry (`core/src/reac-slots.ts:55,58,64,67,73,127` vs
`reac-pw/src/reac_slots.h:53,54,60,61,65,25` — every value identical, and `reac-slots.ts:5` names
reac-pw PR #70 as its source: declared duplication done right); box in/out counts; the pad
(20 dB, actuator not range, `0|1`); the pace vocabulary (`[44100,48000,96000]` both sides, and
192000 legal on neither); MAC→key (`core/src/stagebox.ts:605-609` vs
`reac-pw/src/reac_disco.c:296`, byte for byte). No frame size, checksum, braid or control-block
template leaks into TypeScript — a grep for `1492` across `packages/` returns zero, with
`REAC_AUDIO_FABRIC_SLOTS` → 5 hits as the positive control in the same command.

**The model to copy:** phantom. openmixer never spells the wire byte — it sends the *name*
(`reac-head-amp.ts:55,58,65-67`) and reac-pw maps it
(`reac-pw/src/reac_headamp_prop.c:47-56`), with the prop prefix and caps token set matching
exactly. Likewise the head-amp base placement table lives only in `libreac/src/reac_ports.c:31-39`
and openmixer correctly refuses to guess (`reac-head-amp.ts:583-590`). Worth telling the C side:
`reac-pw/src/reac_link_state.h:50-56` still accuses openmixer of duplicating that table. It no
longer does.

**Fragile but not currently wrong:** `reac.box-width` is published as `"16x8"`
(`reac-pw/src/reac_sink_node.c:623`) and read with a radix-10 `parseInt` at
`packages/audio-engine/src/pipewire-graph.ts:443`. It yields the input width only because
`parseInt` stops at the `x`, and `"0x0"` → `0` by the same accident.

### openmixer verdict

**Better than expected on discipline; the gaps follow one pattern.** The head-amp actuator
refuses rather than guessing a base. The known-set discipline
(`head-amp-resource.ts:42-58`) is a real fix for a real 48 V incident, reasoned from the
incident. `HeadAmpRefusalSink` exists because two production paths used to report `applied: true`
over a preamp nothing reached. The determination gate (`server.ts:4537-4611`) is carefully
bounded and correctly ordered against the session restore. Almost every constant carries the
incident that produced it.

The pattern in the failures is worth naming, because it predicts where the next one will be:
**a fact is stated correctly in a doc-comment or a spec, and the code beside it does something
else.** O1 (a ruling that "the adapter translates", implemented as the identity function), O3 (an
alarm gated shut by a key whose absence is documented eleven lines above), O8 (a settled refusal
with no code and a UI string promising it), O12 (a 48-line essay on a bound the actuating copy
does not apply), and the two unreachable `return`s. The prose in this repo is unusually good,
which is exactly what makes the gaps invisible — the comment reads like a verification.

---

## 5. Half-built things — declared but not wired

This section covers reac-pw, libreac, reac-tools and reac-label. reac-repacer / reac-aes67 /
reac-kmod have their own inventory inside section 3, and openmixer's is inside section 4.

The flagship class. reac-pw was recently found to read no config file at all while three layers
of config were documented; that specific hole is now closed (`a0ebf76`, `src/reac_conf.c`), so
the sweep looked for the rest of the family.

### Dead oracles — captured evidence compiled in and never compared

These are the most valuable items in this section, because each one is a real-desk measurement
sitting inches from the code it was captured to verify.

- **`reac-pw/tests/test_reac_master.c:53,55` — `GOLD_SUB01` / `GOLD_SUB02`.** The comment above
  them (lines 50-52) declares their purpose: "The header and the final chunk of the scene push,
  transcribed off a real desk LONG BEFORE the transfer was understood — **which is what makes
  them an oracle here: the chunker must reproduce both from the recovered body alone.**" They are
  referenced nowhere in the repo. Their siblings `GOLD_CHANMAP` and `GOLD_CFEA_M300` *are*
  asserted (lines 180, 192, 195); these two are not. The compiler reports them unused on every
  build. So the scene push's op-0101 header and op-0102 tail — the framing that decides whether a
  box enrols — have a real-desk oracle in the test file, disconnected.

- **`reac-pw/tests/test_reac_s1608.c:79` — `gold_probe()`.** Defined, never called. It is the
  `(phase, sub)` lookup into `GOLD_PROBES`, the ten probe blocks transcribed off a live M-200.
  The comment at lines 88-95 claims the test asserts "the emitted chunks walk the body in order,
  **byte-exact vs those captures**" and that "the goldens stay the oracle."

  What `test_probe_rotation` actually asserts, at line 124, is
  `memcmp(f + 23, m.scene + off, REAC_SCENE_CHUNK_BYTES) == 0` — the emitted chunk against the
  master's own scene buffer. That does check the slicing arithmetic against real bytes
  (`reac_scene_placeholder` is a recovered M-200i body, `src/reac_scene_body.c:6-12`, 20.2%
  non-zero). It does **not** check the emission order against the captured walk, which is what
  `GOLD_PROBES` encodes and what the header comment claims. The test says so itself four lines
  later (129-134): "Comparing chunk bytes cannot express this — a generated body is mostly
  zeros."

  So the claim is stale, the accessor for the real oracle is dead, and the one property the old
  model got wrong (double-emission) is now checked via `m.scene_step`, an internal counter,
  rather than against the wire. This sits directly upstream of the open "S-1608 inputs 9-16 bank
  still un-enrolled" problem, which makes it worth more than its rank suggests.

### Config knobs and flags

- **reac-pw: one undocumented live knob**, `REACPW_NO_HEADAMP` — see A10. The other six all
  appear in `docs/ENV-KNOBS.md`. Worth stating the negative result plainly: the four knobs
  ENV-KNOBS.md:73-74 names as having "rotted before being removed" (`REACPW_EST_COMMIT`,
  `REACPW_ANNOUNCE_BURST`, `REAC_TX_LAYOUT`, `REACPW_ANNOUNCE_UNGRANTED`) are genuinely gone from
  `src/` — checked with a positive control. reac-pw's knob hygiene is better than expected, and
  the doc's stated rule ("a knob whose motivating theory is debunked gets deleted, not kept
  around", ENV-KNOBS.md:5-8) is actually being followed.

- **reac-tools and reac-label: no dead CLI flags in either.** `reac/cli.py:49-55` declares four
  arguments; all four dests are read at lines 58, 79-83, 103-107. `reaclabel/__main__.py:27-34`
  declares eight; all eight are read at lines 37-61. Every module-level `def` in both repos has a
  caller. Zero `TODO`/`FIXME`/`XXX`/`NotImplementedError`/stub across ~4,700 lines, verified with
  a positive control that found 147 `def`s. That is unusual and it should be said.

- **reac-pw `meson_options.txt` is empty by design** and says so. Nothing dead there.

### Declared interfaces with no implementation

- **`reac-aes67/pipewire/src/reac_sink_node.c:94`** — `(void)tx_ring`. The ring parameter is in
  the signature, documented at `reac_sink_node.h:46` as "reserved for the future slot-pacer cut",
  and discarded. This is A5's half-built face: the interface for the correct design exists and
  the implementation behind it does not.

- **`reac-pw/src/reac_scene_body.c:6-12`** — the scene body pushed to every box is **a real
  M-200i's scene**, recovered from a capture, kept "because a body of the RIGHT LENGTH is what
  lets the transfer complete". The file says the follow-on work is generating it from our own
  console. Not a defect — an honest placeholder, correctly labelled — but it is the largest
  outstanding piece of unbuilt work in reac-pw and belongs on this list.

- **`reac-pw/src/reac_fsm.h:36`** — `REAC_FSM_TXMUTE_DWELL` is explicitly labelled "PLACEHOLDER
  pending a rig capture". See A9: the placeholder is also arithmetically wrong at 48 kHz.

### Dead exports

- **libreac: two public functions with zero callers anywhere** — `reac_ctrl_box_frame_len` and
  `reac_ctrl_record_cksum_verify`, both declared in `include/reac/reac_ctrlblk.h`, defined in
  `src/reac_ctrlblk.c`, referenced by no consumer and by no test. Positive control:
  `reac_ctrl_stamp_headamp` resolves to five files. Papercuts, listed for completeness.
  `reac_ctrl_build_headamp` is test-only, which is fine — it is a legitimate API and shares its
  byte table with the production stamper (see section 7).

### Left in the tree

- **`reac-tools/verify_0500_corpus.py`** — untracked (commit `baa537b` untracked it as
  superseded) but still present and runnable, sorted next to its replacement, one tab-completion
  apart. It carries exactly the defect the replacement was written to remove: lines 105-107 print
  `VERDICT: ALL 0500 records conform` and return 0 **even when every capture yielded
  `n_0500 == 0`**. An empty scan reads as a pass. Its replacement `verify_tag_0500.py:164-171`
  fixes this and names the trap in a comment at 142-144.

- **`reac-tools/reac/__pycache__/`** holds `ctrl.cpython-314.pyc` and `headamp.cpython-314.pyc`
  for modules that exist only on unmerged branches. Harmless until an import succeeds by
  accident.

- **`reac-tools/reac_pitch.py:99-100`** — `sp` and `fq` computed and never used; the
  modulation-rate feature abandoned mid-write. `reac_glitch.py:43` carries a dead
  `if False else` branch from debugging.

### reac-label's documented-but-absent M-5000 path

`reac-label/README.md:56-57` and `reaclabel/__main__.py:19` both state that `--model m5000`
"sizes a name scan and nothing more", and README.md:90 says "A scan that returns names but no
slots is the M-5000 case". But the output is keyed by slot (`reaclabel/join.py:52-61`), so no
slot means no row means no name. Verified: `m5000 scan output: {}`. There is no names-only code
path and no flag that produces one. `--model m5000` scans 128 channels over TCP and prints
nothing.

Relatedly, `reaclabel/__main__.py:44` seeds the simulator with `out_patch={"RAO1": "AX1"}` but
`--outputs` defaults to `0` (line 31), so README.md:72's advertised demo can never reach it.

---

## 6. Test honesty, per repo

Covers libreac, reac-pw, reac-protocol, reac-tools and reac-label. The verdicts for
reac-repacer / reac-aes67 / reac-kmod are in section 3 and openmixer's is in section 4.

The question is not "is the suite green". It is "could this suite go red". A suite that cannot
fail is a defect in itself.

| Repo | Suite actually run | Result | Verdict |
|---|---|---|---|
| libreac | `make test` | 8 binaries, all pass, exit 0 | **Exercises the wire.** Best in the stack |
| reac-pw | `meson test` (34 of 35; the socket test excluded on instruction) | 34 ok, 0 fail | **Largely honest**, with named exceptions |
| reac-protocol | `make facts` + generated-file sync | in sync, idempotent | **Its two real oracles cannot run here** |
| reac-tools | `pytest -q` / `make test` | 53 passed / 40 ok | **The gate for its own headline bug cannot fail** |
| reac-label | `pytest -q` | 18 passed | **Honest**, one file is exemplary |
| reac-lab | n/a | n/a | Documentation only — 19 `.md` files, no code |

### libreac — the standard the rest should be held to

`make test` builds and runs eight binaries. What they assert is the point:

- `tests/test_upstream.c` decodes **real captured frames** — 16-ch 628 B, 8-ch 340 B, 32-ch
  1206/1204 B — and asserts full PCM match, not shape.
- `tests/test_braid.c` proves `braid_pos` **bijective** for every width 2..40 against a reference
  byte map, plus exact f32<->s24 round-trip and clamp.
- `tests/test_decode.c` pins the **plain-LE layout as a negative control** — a debunked
  alternative kept alive so the regression cannot return quietly. That is a test designed to
  fail, which is the rarest and most valuable kind.
- `tests/test_facts.c` checks against `reac_facts_assert.h`, generated in reac-protocol from
  `protocol-facts.yaml` — a cross-repo oracle rather than a self-check.

Builds clean under `-Wall -Wextra` with no warnings. **libreac is in better shape than expected
and none of the defects above are in it.**

One structural caveat: `libreac/tests/reac_facts_assert.h` is a **hand copy** of
`reac-protocol/spec/generated/reac_facts_assert.h`. They are byte-identical today (verified). But
`libreac/tests/test_facts.c:7-9` says it is copied, and no gate anywhere compares them. The whole
value of the facts oracle is that libreac is checked against the spec; a hand copy means libreac
is checked against a *snapshot* of the spec, and nothing will announce the drift.

### reac-pw — a serious suite with three specific holes

34 tests pass. The master-side goldens are real and really asserted:
`tests/test_reac_s1608.c:170-176` checks all 11 chanmap windows **byte-exact** against a captured
M-300 sweep; `tests/test_reac_master.c:180,192,195` does the same for the chanmap and cfea. This
is not a fixture-shaped suite.

The holes:

1. **Every timing assertion in `tests/test_reac_fsm.c` is a tautology.** Line 109:
   `CHK(fsm.link_check == REAC_FSM_LINKCHECK_RELOAD)`. Line 67:
   `CHK(fsm.flood_frames >= REAC_FSM_FLOOD_BURST)`. The constant is asserted against itself, so
   any value passes. Combined with the file containing no mention of fps or sample rate at all
   (verified with a positive control), A9's rate-scaling bug is invisible to this suite by
   construction.

2. **Two dead oracles** — `GOLD_SUB01`/`GOLD_SUB02` and `gold_probe()`, section 2. The compiler
   reports all three unused on every build and the warnings are not being read.

3. **`test_reac_s1608.c`'s probe-rotation comment no longer matches what the test measures** —
   it claims byte-exactness against captures and asserts self-consistency against the master's
   own buffer. A gate whose name outran its body. Section 2 has the detail.

Worth stating: the build emits four warnings and three of them are the dead oracles. The fourth
is a real bug (A15). **The compiler found more in this repo than any grep did**, and nobody is
reading it.

### reac-protocol — the two checks that catch a misunderstanding cannot run

`spec/Makefile:11-21` documents `check-oracle` and `check-ctrl-oracle`, and describes the second
as "the check that catches a MISUNDERSTANDING rather than a typo" — it builds a frame with
libreac, parses it with the ksy-generated parser, and requires them to agree. Both are
**deliberately outside `check` and outside CI**, which "stay hermetic".

On this machine neither runs, and neither does `make check`: `kaitai-struct-compiler` is not
installed, so `make check` dies at `Makefile:41` before doing anything. Every claim that
`spec/reac.ksy` agrees with libreac is therefore **currently unverified here**.

What does run and is green: `make facts` regenerates `spec/generated/` from
`spec/protocol-facts.yaml` and reports all three files unchanged, and `git status` on
`spec/generated` is clean — so the committed generated artefacts are in sync with their source.
That is a real gate and it holds.

The honest summary: reac-protocol's hermetic CI proves the grammar is self-consistent with a
Python transcription of libreac. The cross-implementation oracle — the one that would catch two
copies disagreeing — is opt-in, needs a JRE-built tool, and has no evidence of having been run
recently.

### reac-tools — the gate for the counter-wrap bug cannot fail, proven by sabotage

This is the sharpest test-honesty finding in the census, because it was demonstrated rather than
argued. The wrap bug was reintroduced into `reac_codec.order_by_counter` and all three entry
points were run:

```
python3 -m pytest -q       -> 53 passed          EXIT=0   GREEN
make test                  -> Ran 40 tests, OK   EXIT=0   GREEN
python3 test_reac_tools.py -> 12 passed, 2 failed EXIT=1  caught it
```

Two independent mechanisms:

1. **`check()` never raises.** `test_reac_tools.py:15-22` and `test_reac_repacer.py:20-25` print
   `FAIL` and increment a counter; only the `__main__` block at `test_reac_tools.py:127` turns
   that into a non-zero exit. Under pytest the 13 collected functions return normally whatever
   they measure — **green by construction**.
2. **`make test` never collects them.** `Makefile:5` is `unittest discover tests`, which sees only
   `tests/`. `README.md:154` documents that as *the* test command.

So `test_decode_survives_the_counter_wrap` (`test_reac_tools.py:81-93`) — a correct, well-written
regression test for the exact 8.2-second bug — is enforced by **no automated entry point**. It
runs only if a human types the filename, as `REAC-REPACER-NIGHT.md:67` instructs.

Tests that would pass against a stubbed implementation:

- `test_reac_tools.py:29-41` `test_roundtrip_clean_sine` — builds with `rc.encode_frame`, reads
  with `rc.decode_frames`. Any invertible byte permutation passes, **including the wrong one it
  actually uses**. It reports purity 1.000 for a decoder that returns 0.275 against real bytes
  (A1), and `REAC-REPACER-NIGHT.md:60` cites that 1.000 as evidence the codec is trustworthy.
- `test_reac_tools.py:43-78` — four more tests in the same closed loop, all at SR=96000, the only
  rate the module can generate.
- `test_reac_repacer.py` **entirely**. Its header (lines 5-9) says it validates the transform
  "mirroring reac-repacer-clk v3"; it tests `reac_repacer_model.py`, a Python re-implementation.
  `reac_repacer_v3.c` is not in this repo, and `reac_repacer_model.py:7` cites "lines ~314-331"
  of a file nothing here can check. If the C diverges from the model, every test stays green.

The real pcap fixture is **better than expected**: `tests/test_fixture.py:29` asserts the exact
sequence `[0xfd7e..0xfd81]`, line 33 the exact source MAC, `tests/test_characterize.py:26` the
exact payload length 1478, lines 30-31 `inferred_rate == 48000` from real inter-arrivals. It is
real-value testing. **But the audio is never checked** — `test_characterize.py:38-41` asserts
only `len(channel_peak) == 40`. That single missing assertion is what let A1 live.

Gates whose name no longer matches what they measure:

- `tests/test_fixture.py:40` **`test_jitter_matches_real_spacing`** measures against
  `nominal_dt=1/3000`. 3000 fps is not a REAC rate — `reac/model.py:43-54` refuses it and
  `test_reac_tools.py:116` asserts `rate_from_pps(3000) is None`. Commits `eef5f7e`, `98ea3aa`
  and `d2c35c2` scrubbed 3000 from the code and the README; this test kept it. The fixture is
  48 kHz, asserted three lines away in another file. It passes only because the assertion is a
  loose `< 1.5`.
- `Makefile:4` **`test`** runs 40 of the repo's 53 tests and omits every gate protecting the two
  bugs this census was commissioned over.
- `REAC-REPACER-NIGHT.md:60,62` cites "7 tests" and "8 tests" for files that now define 8 and 5.

### reac-label — honest, and one exemplary file

18 tests, all real. `tests/test_e2e.py` runs client and join over a real socket against
`reaclabel/simulator.py` — the repo talking to itself, which is worth having but is not external
truth. `tests/test_proto.py` is the best test file in either Python repo: its docstring (lines
6-11) grounds every assertion in documented VMXProxy `simrc.txt` command/response pairs, and it
asserts real strings (`'CNS:I1,"NoName";'`, `"PIS:I22,RAI22;"`). That is testing against a
source outside the repo, which is the only kind that can catch a misunderstanding.

---

## 7. Duplicated logic — which copy is authoritative, and do they agree

The cross-repo table. Section 3 carries the constant-by-constant sweep for reac-repacer /
reac-aes67 / reac-kmod, and section 4 carries openmixer's — both feed the verdicts here.

Hunted deliberately, because two copies that disagree about the protocol is the worst finding
available.

### The headline: the wire geometry has exactly one home, and it holds

Every frame-geometry constant is defined once, in `libreac/include/reac/reac.h:20-28` —
`REAC_FRAME_BYTES` 1492, `REAC_AUDIO_BYTES` 1440, `REAC_AUDIO_OFFSET` 50, `REAC_L2_HEADER_LEN`
50, `REAC_MAX_CHANNELS` 40, `REAC_SAMPLES_PER_PKT` 12, `REAC_RESOLUTION` 3,
`REAC_HDR_COUNTER_OFF` 14. A sweep for a second `#define` of any of the eight across libreac,
reac-pw, reac-aes67, reac-repacer, reac-kmod and openmixer/packages returns **nothing** —
positive control confirmed the search works. reac-pw, reac-aes67/pipewire and reac-repacer all
consume them through `<reac/reac.h>`.

That is a genuinely good result and it should be said before the disagreements below are read.

### The disagreement table

| Logic | Authoritative | Copies | Agree? |
|---|---|---|---|
| Frame geometry constants | `libreac/include/reac/reac.h:20-28` | none | **n/a — single home** |
| Downstream frame builder | `libreac` `reac_downstream_build` | `reac-aes67/pipewire/src/reac_tx.c:79` calls it; `reac-pw/src/reac_sink_node.c:347` calls it | **Agree — both delegate** |
| Head-amp record bytes | `libreac/src/reac_ctrlblk.c` `CTRL_FRAMES[CTRL_HEADAMP]` | two entry points, `reac_ctrl_build_headamp:865` and `reac_ctrl_stamp_headamp:879`, sharing one table and one `headamp_args_ok`; `put_groupa:949-957` deliberately routes through the stamper "as the single source of these bytes" | **Agree by construction** |
| SENS step -> dB law | `libreac/include/reac/reac_ctrlblk.h:174-175` | `reac-pw/src/reac_ctrl.h:83` defers explicitly; `reac-pw/src/reac_slave.h:151-155` uses `reac_headamp_sens_db()` | **Converged.** The three-way split that `reac-protocol/convergence-defects.md` documented is resolved: libreac now ships the flat law (`SENS_REF_CDB -1000`, `SENS_STEP_CDB 100`) and reac-pw carries no second copy. See the note below |
| ppm window state | `reac-pw/src/reac_rx.h` (per-instance) | `reac-aes67/pipewire/src/reac_rx.c:69-72` (file statics) | **DISAGREE — A7** |
| TX cadence | `reac-pw/src/reac_pacer.c` (SCHED_FIFO deadline grid) | `reac-aes67/pipewire/src/reac_sink_node.c:73-81` (direct emit from RT callback) | **DISAGREE — A5, and this one is protocol-level** |
| Upstream accept path | `reac-pw/src/reac_rx.c` (`REAC_RX_ACCEPT_UPSTREAM`, source-MAC gate, `reac_upstream_decode`) | `reac-aes67/pipewire/src/reac_rx.c` — **absent entirely** | **Copy is missing a direction** |
| Audio sample layout (reac-tools) | `reac/characterize.py:56-66` (pair-interleave) | seven files on plain-LE | **DISAGREE — A1, the worst finding in the census** |
| pcap reader (reac-tools) | `reac/pcap.py:52-111` | **14 independent re-implementations**, none importing it | Mostly agree; diverge on ethertype offset — A13 |
| Ethertype offset scan | `reac/pcap.py:41-49` (12 or 16) | `(12,16,20)` in three files; **pinned to 12** in eight | **Three-way divergence — A13** |
| Rate table | `reac/model.py:25-40` | `reac_codec.py:40-41` | Agree today. Two declarations of one law, nothing keeping them in step |
| Wrap-safe counter ordering | `reac_codec.order_by_counter:125-149` (correct) | `reac/analyzer.py:12-18` correct; `reac/diff.py:38` **wrong**; `reac_ab_defect.py`, `measure_b7.py`, `decode_probe.py` **wrong** | **Both copies carry a wrong instance — A2, A3** |
| Protocol facts oracle | `reac-protocol/spec/generated/reac_facts_assert.h` | `libreac/tests/reac_facts_assert.h`, hand-copied | Byte-identical today; **no gate** |
| reac-label proto vs reac-tools parser | — | — | **No overlap.** Different protocols (ASCII control on TCP 8023 vs Ethernet 0x8819). Nothing to reconcile |

### The four dedicated defect notes from this table

**D-1. reac-aes67/pipewire is a two-month-stale fork of reac-pw and every shared file has
diverged.** 11 files against reac-pw's 57; all 11 differ, from 35 diff lines (`reac_ring.c`) to
1338 (`reac_sink_node.c`). It carries A5 (no pacer), A7 (a ppm bug fixed upstream on 2026-06-30),
and lacks the upstream RX direction entirely. It also still has the defensive-init
divergence reac-pw closed: `reac-aes67/pipewire/src/reac_rx.c:54` declares
`float planar[REAC_MAX_CHANNELS * REAC_SAMPLES_PER_PKT];` uninitialised where reac-pw's
equivalent is `= { 0 }`. Latent in this copy — `nch` is always 40 on the downstream-only path it
supports — but it is the guard reac-pw added when it gained a path where `nch < 40`.

`reac-aes67/README.md:56` declares the tree dead, which is the right call. **The declaration is
not load-bearing.** Two mechanisms keep the stale copy alive and give it credibility:

- `reac-aes67/packaging/reac-pw.spec` still builds an RPM named `reac-pw` from it (A6).
- **`reac-aes67/.github/workflows/ci.yml:21-35` has a CI job literally named `reac-pw`** that
  runs `meson setup build pipewire` and `meson test`. So reac-aes67's CI publishes a green check
  called "reac-pw" for a tree that is not reac-pw — with no pacer (A5) and a ppm bug fixed
  upstream two months ago (A7). Anyone reading that check as evidence about reac-pw is being
  misled by the name.

  The job's own comment (ci.yml:18-20) is the sharpest thing in the file: "The pipewire/ endpoint
  was never built here, so its tests never ran — which is how a downstream encoder emitting the
  wrong audio layout survived in the tree." The job was added for exactly the right reason. Its
  name is now the problem.

**D-2. The libreac version gate measures nothing.** All three consumers pin
`revision = main, depth = 1` (`reac-pw/subprojects/libreac.wrap`,
`reac-repacer/subprojects/libreac.wrap`, `reac-aes67/pipewire/subprojects/libreac.wrap`) — so
every build floats on a moving branch and no build is reproducible. Worse, the version meson
checks against is a **hand-set string in the shim**, not anything libreac reports:

| consumer | floor demanded | shim claims | libreac actually is |
|---|---|---|---|
| reac-pw | `>=0.6.0` (`meson.build:47`) | `0.6.0` (`subprojects/packagefiles/libreac/meson.build:17`) | 0.6.0 |
| reac-aes67/pipewire | `>=0.5.0` (`meson.build:48`) | **`0.5.0`** (`.../meson.build:16`) | 0.6.0 |
| reac-repacer | `>=0.4.0` (`meson.build:37`) | **`0.4.0`** (`.../meson.build:21`) | 0.6.0 |

Each shim is hand-set to exactly its own floor, so the check passes by definition regardless of
what code the wrap fetched. reac-pw's own shim comment admits it: "The version string alone
proves nothing." **A gate whose name no longer matches what it measures**, in the place where the
wire format enters three binaries. How it shows up: it does not — that is the problem. If
libreac's `main` changes the braid map, all three consumers pick it up on the next build and
every version check still says "satisfied".

**D-3. The facts oracle is hand-copied.** `libreac/tests/reac_facts_assert.h` is byte-identical
to `reac-protocol/spec/generated/reac_facts_assert.h` today. No Makefile, test or CI step in
either repo compares them (checked; positive control confirmed the search). The point of the
oracle is that libreac is held to the spec; a hand copy holds it to a snapshot, and nothing
announces the drift.

**D-4. SENS is genuinely converged, and the residual is a choice not a bug.** Worth recording
because it was the stack's headline disagreement. The measured law is 0.988 dB/step, span
54.60 dB (`reac-protocol/convergence-defects.md`, the S-0808 loopback sweep). libreac ships
1.000 dB/step, span 55.00 (`reac_ctrlblk.h:174-175`). The 0.4 dB difference at the top of the
range sits inside the measurement's own stated max residual of 0.44 dB, so the flat law is a
defensible rounding rather than a defect. The three-way split is closed: the 56-entry firmware
table is gone from libreac, and reac-pw defers rather than carrying the ~1.235 dB/step figure
from `07d1802`.

---

## 8. What is in better shape than expected

An inflated defect list is as useless as a missing one, so this section is not politeness. Four
of these are load-bearing: they tell you where NOT to spend the next week.

- **libreac is the best-engineered thing in the stack and carries none of the defects above.**
  Eight test binaries, all green, all asserting real captured PCM rather than fixture shape; a
  bijection proof for the braid across every width 2..40; a debunked layout pinned as a
  *negative* control so it cannot return quietly; a cross-repo facts oracle. Builds clean under
  `-Wall -Wextra` — 8 compile lines, 0 warnings. Zero `TODO`/`FIXME` anywhere in `src/` or
  `include/`. Its only findings in this census are two dead exports and a hand-copied oracle
  header. **The wire format has one home and the home is sound.**

- **The frame geometry is genuinely centralised.** The single most likely catastrophic finding —
  two copies of the frame layout disagreeing — does not exist. Eight constants, one definition
  site, no second `#define` anywhere in six repos plus openmixer.

- **reac-pw's suite is real.** 34 of 35 tests pass (the 35th excluded here on instruction, not
  because it fails), and the master-side assertions are byte-exact against captured M-200 and
  M-300 frames, not against its own output. Its knob hygiene is better than expected: six of
  seven env vars documented, and the four knobs the docs claim were deleted for rotting really
  are gone. The reasoning comments throughout — `reac_pacer.h:6-14`, `reac_conf.h:1-58`,
  `main.c:725-756`, `reac_sink_node.c:352-367` — are the most valuable artefact in the repo and
  several of them correctly name traps before the code falls into them.

- **The SENS disagreement is closed.** The stack's headline three-way protocol split — 19 dB
  apart on a number that reaches an operator as preamp gain — was measured and resolved, and the
  code converged. That is the discipline working.

- **reac-label is solid.** 775 lines, 18 honest tests, no dead code, no dead flags, no duplicated
  logic, clean separation of pure from I/O. Its `tests/test_proto.py` is the best test file in
  either Python repo because it asserts against externally documented wire strings rather than
  against itself.

- **reac-tools' `reac/` package is careful and correct** even though the scripts around it are
  not. `reac/model.rate_from_pps:43-54` returns `None` rather than snapping an off-nominal
  stream; `reac/cli.py:91-98` withholds a jitter ratio rather than inventing a nominal;
  `reac/analyzer._signed_delta:12-18` handles the wrap properly. That instinct — refuse to answer
  rather than answer wrongly — is present throughout the package and is the right one.

- **reac-lab is documentation only** (19 `.md` files plus a CI guard, no code), so it has no code
  defects. Not a gap; a correct separation.

- **reac-protocol's `make facts` gate holds.** Regeneration is idempotent and the committed
  artefacts are in sync with `protocol-facts.yaml`. `convergence-defects.md` is an unusually
  honest document: it records measured disagreements rather than reconciling them by preference,
  and its opening states why.

- **The credential leak in reac-tools' history is being handled correctly.** Today's HEAD
  (`b3b1082`) removes the literal password from the warning that documents it, naming the commit
  instead — a warning about a credential should not be a second copy of it.

---

## 9. Recommendations — noted, not applied

Ordered by value per unit of work, not by defect rank.

1. **One assertion closes A1's blind spot.** In `reac-tools/tests/test_characterize.py`, assert
   `max(r.channel_peak) < 1000` on the real fixture: the interleave gives 29, plain-LE gives
   65536. Then settle the layout in one place and delete the other —
   `reac/characterize._sample` is the correct implementation and `reac_codec.decode_frames`
   should call it rather than re-derive. Until that is done, treat every purity, click, ppm and
   dBFS figure from the seven plain-LE tools — including those in `REAC-REPACER-NIGHT.md` and
   `measure-log.csv` — as unverified.
2. **Make `check()` raise.** One line each in `reac-tools/test_reac_tools.py:22` and
   `test_reac_repacer.py:25` turns 13 decorative tests into real ones and puts the counter-wrap
   gate under `pytest`. Then point `Makefile:5` at pytest so `make test` sees all 53 rather
   than 40.
3. **Delete `reac-aes67/pipewire/` and `reac-aes67/packaging/reac-pw.spec`, and drop the CI job
   named `reac-pw`.** This removes A5, A6, A7 and half the duplication table in one commit. If
   the tree must stay, rename the package and the CI job so neither can be mistaken for the real
   reac-pw.
4. **Give the three `libreac.wrap` files a pinned revision instead of `main`**, and make the shim
   version come from libreac rather than a hand-set string — or delete the version check, which
   would at least be honest about measuring nothing (D-2).
5. **Fix `reac/diff.py:38-42` to diff on unwrapped counters.** The arithmetic already exists
   twice in the same package (`reac_codec.order_by_counter`, `reac/analyzer._signed_delta`). Add
   the wrap case to `tests/test_diff.py` first — `tests/test_analyzer.py:31-35` is the template.
6. **P1's scaling mechanism in reac-pw** (`reac-repacer/REPACER-FIXES.md:41-68`) is offline-
   testable even though the exact constants are rig-gated. Do the mechanism now; it removes A9's
   whole class. Add one fps parameter to `tests/test_reac_fsm.c` so the suite can express the
   bug at all.
7. **Read the compiler.** reac-pw's build emits four warnings; three are dead real-desk oracles
   and one is a real (if currently unreachable) NULL deref. Turning `-Werror` on for the test
   targets would have caught all four the day they landed.
8. **Wire `REACPW_NO_HEADAMP` to its value rather than its presence** and add it to
   `docs/ENV-KNOBS.md` (A10).
9. **Gate the facts-header copy.** A three-line `diff` in libreac's `make test` comparing
   `tests/reac_facts_assert.h` against reac-protocol's generated copy would keep D-3 from ever
   becoming a silent drift.
10. Run `reac-tools/verify_tag_0500.py` once against a known-good capture before trusting its
    checksum rule (A14), and delete or gitignore `verify_0500_corpus.py` (its empty-scan-is-a-pass
    defect is the exact thing its replacement was written to remove).
11. `reaclabel/client.py:82-94` should check `r.is_error` before returning `r.args[0]` (A12). The
    flag is already set and already tested.
12. **Clamp the `media_clock` gap and re-anchor** (`reac-aes67/src/media_clock.c:40-50`) with a
    distinct resync counter. One branch, and it is the only finding in the census that silently
    loses audio *and* corrupts a clock *and* reports zero. Do it before anything else on this
    list.
13. **Make `packets_per_sec` and `uptime_s` actual measurements, or delete the columns.** A field
    that cannot answer the question it is read for is worse than a blank one (B4).
14. **Delete `--no-plc` and `--reclaim`** from the parser, `usage()`, the man page and
    `internals.md`, or implement them. The banner printing their state is worse than either
    (B5). Then print `n_drop_full` in the telemetry line and publish it over ubus (B3).
15. **Change reac-kmod smoke gate 4 to scan defined symbols and strings**, not unresolved
    imports. It is the only thing between the project and a GPL-2/GPL-3 link, and it has been
    shown to pass with GPL-3 code in the binary. Same pass should widen gate 7 to
    `sock_sendmsg`/`kernel_sendmsg`/`skb_send_sock`.
16. **Wrap `tone.c`'s per-channel phase individually** instead of scaling a wrapped base (B2).
17. **Set `"allowUnreachableCode": false` in `openmixer/tsconfig.base.json`.** It is unset today
    (only `"strict": true` at line 6), so TypeScript reports unreachable code as an editor
    suggestion rather than an error. That one line turns both of openmixer's dead `return`
    statements into compile failures, for free and forever.

---

## 10. What this lane changed

**No source file in any repo was modified.** Verified at the end:
`git status --porcelain` is empty in libreac, reac-pw, reac-protocol, reac-aes67, reac-repacer,
reac-label, reac-lab, reac-kmod and openmixer. reac-tools shows one untracked file,
`verify_0500_corpus.py`, which this lane did not create — commit `baa537b` untracked it as
superseded before this work began, and it is written up in section 5.

Three sabotage experiments were run to test whether a gate could fail. All three were reverted or
performed on a scratch copy:

- The counter-wrap bug was reintroduced into `reac_codec.order_by_counter` to show that
  `pytest` and `make test` stay green while only the un-run entry point catches it. Reverted;
  reac-tools' `git diff` is empty.
- One bit was masked in reac-repacer's `braid_write` (`reac_repacer.c:385`) to confirm
  `test_inject` does bite — it went from 0 failures to 2180. Reverted.
- libreac's GPL-3.0 braid map and a `reac_frame_clean_len` were vendored into a **scratch copy**
  of reac-kmod's `src/segment.c` to show that smoke gate 4 passes with GPL-3 code in the binary.
  The repo itself was never touched.

**Nothing was fixed.** Several findings are one-line, obviously-correct changes — the missing
braces at `reac-pw/src/reac_sink_node.c:1212`, the `allowUnreachableCode` flag, the
`REACPW_NO_HEADAMP` value test — and they are written up as recommendations in section 9 rather
than applied. A lane that quietly rewrites while surveying produces neither a census nor a
trustworthy fix.

Builds and offline suites were run in libreac, reac-pw, reac-protocol, reac-tools, reac-label,
reac-repacer, reac-aes67 and reac-kmod. **Nothing that opens a raw socket was run.** Specifically
excluded: `reac-pw`'s `test_reac_pacer` (the only reac-pw test that opens one — AF_PACKET on
`lo`), and `reac-aes67`'s `test_aes67_send` and `test_e2e_udp` (UDP, loopback only). The kernel
module was built but never loaded. reac-pw was never executed. The live rig was not touched, and
the two masters currently driving stageboxes were left alone.

The openmixer vitest suites were **not** run, and no claim here depends on them: a filtered run is
a substring filter against absolute paths and would have collected stale worktree copies, and
without a dependency-closure build the packages resolve through a possibly-stale `dist`. Every
openmixer finding is source-level.

## Reading this later

The findings are ranked by blast radius, not by how easy they are to fix. If this document is
picked up cold, the three things worth knowing are that **#1 loses audio and reports zero**,
**#2 and #3 mean a documented night of measurements rests on instruments that were wrong**, and
that the recurring shape across all nine repos is not sloppiness — it is a **correct fact written
in a comment or a spec beside code that does something else.** The prose in these repos is
unusually good, which is exactly what makes those gaps invisible: the comment reads like a
verification. Where a gate exists, check what it measures before trusting that it is green.
