# Where the two expressions of REAC disagree

Two artefacts describe one protocol. [`spec/reac.ksy`](spec/reac.ksy) is declarative — it
parses and validates, and it now reads the whole capture corpus with no unexplained bytes.
[`libreac`](https://github.com/FreeREAC/libreac) is imperative C — it builds frames and drives
boxes. Neither generates the other.

[`spec/protocol-facts.yaml`](spec/protocol-facts.yaml) now holds the constants they both spell,
and two harnesses hold them to it: `facts_xcheck.py` asserts the grammar still carries every
value, and `xcheck_ctrl_oracle.py` makes libreac build frames that the ksy-generated parser has
to read back. Both are green as of this file's date.

**This page is what they cannot fix.** These are places where the two sides say different things
about the same bytes, or where one of them says nothing at all. They are written down rather than
reconciled: reconciling a measured disagreement quietly, by picking whichever number the person
holding the file happens to prefer, is how a wrong number becomes a settled one.

---

## 1. SENS — RESOLVED 2026-08-23: one dB per step, no twins

**Was: three live readings of the same byte, spanning 19 dB.** It is the number a console
publishes as preamp gain, so it reaches an operator.

A head-amp record's VALUE for `PARAM = 0x02` is a step index, `0x00..0x37`. What that step meant
in dB had three answers in the tree, all load-bearing somewhere:

| where | law | step 0x37 works out at |
|---|---|---|
| `spec/reac.ksy`, `head_amp_data.value` | "56 steps of 1 dB", `dB = -10 - value + (pad ? 20 : 0)` | **-65.00 dBu** |
| `libreac`, `reac_ctrlblk.h` + `SENS_GAIN_CDB[]` | a 56-entry firmware table, breaks at 8 / 24 / 40, per-stage 0.90 / 0.95 / 0.98 dB, total span 48.75 dB | **-58.75 dBu** |
| `reac-pw` commit `07d1802`, measured on the rig | ~1.235 dB per step, one number rather than a curve | **-77.9 dBu** |

This page named the discriminating experiment and said nobody had run it: a steady electrical
source swept across all 56 steps, with the breaks at 8 / 24 / 40 probed specifically for the
duplicate-gain twins libreac predicted — none under a linear law, exactly three under the table.

**It has now been run.** S-0808, output 1 cabled to input 1, so the source is an electrical
loopback of a digital level we generated and therefore know. Phantom and pad commanded off on
that input and both records confirmed on the wire first, since an output stage was connected to a
mic input. All 56 steps at three generator levels whose ranges overlap and agree to 0.05 dB where
they meet.

| | measured | flat 1 dB/step | libreac's table |
|---|---|---|---|
| span 0x00 -> 0x37 | **54.60 dB** | 55.00 | 48.75 |
| slope, least squares over 56 steps | **0.988 dB/step**, max residual 0.44 dB | 1.000 | non-uniform |
| step 7 -> 8 | **+0.92 / +1.12 dB** | 1.00 | 0.00 |
| step 23 -> 24 | **+1.36 / +1.31 dB** | 1.00 | 0.00 |
| step 39 -> 40 | **+0.97 / +0.84 dB** | 1.00 | 0.00 |

Each pair was taken as a rapid A/B/A alternation, twice, at two different generator levels, so
residual drift shows up as a mismatch between the A readings; those controls came out at 0.08 to
0.34 dB, an order of magnitude under the effect. The generator was also cut and restored (the
1 kHz component on the measured channel fell to -96.6 dBFS, below its own broadband floor, and
came back within 0.003 dB), and one step re-read at one-minute intervals repeated to 0.011 dB.
The pad measured 20.12 and 20.20 dB against a nominal 20, which is the check that this dB axis is
the box's own. Raw data: reac-pw `docs/measurements/sens-sweep-2026-08-23-*.csv`.

**The linear law wins and libreac was wrong.** The firmware's four coarse stages are real — the
56-entry table at `0x0c0327a0` is there and its breaks are at 8, 24 and 40 — but *gain being
continuous across a break* was an inference from that structure, and it is refuted. The map is
injective; a round trip through it is the identity.

**Why the table's scale came out low**, since the reasoning looked strong: it was scaled by the
preamp's own NOISE FLOOR. A floor is gain times input-referred noise PLUS whatever the output
stage and converter add after the gain, and that second term does not scale, so a floor's slope is
always shallower than the gain's. It reproduces beautifully — 0.03 dB across sessions — and that
is what made it convincing. It is an excellent probe of repeatability and a biased probe of slope.
The 6.06 dB floor drop at 23 -> 24 is real and stands: it is a noise-figure step sitting on top of
an ordinary 1 dB gain step, not instead of one.

**What did NOT get settled, and it should not be quietly assumed.** A loopback measures the SPAN
exactly, which is what discriminates 48.75 from 55.00, but it cannot separate the absolute dBu of
either endpoint from the box's own converter reference — it sees only their sum. So `-10 dBu` at
step 0 is inherited from the three prior readings that already agreed on it, and `-65` is that
plus the measured span. Pinning either endpoint absolutely needs a calibrated source or the
S-0808's converter levels from a source other than this loop.

`protocol-facts.yaml` now carries the curve as the `headamp_sens` group — three constants libreac
exposes and the generated `reac_facts_assert.h` holds it to, and three substrings of the ksy doc
that `facts_xcheck.py` holds it to. It is no longer a contested number, so the reason it was kept
out of the schema no longer applies.

---

## 2. `REAC_HEADAMP_MAX_CH` is defined twice in libreac, and one of them is undefined

**Severity: every consumer building libreac with `-Werror` fails today.**

On libreac `HEAD` (`ee71f20`, migration slice 2), `include/reac/reac_ctrlblk.h` carries:

```
line 370:  #define REAC_HEADAMP_MAX_CH REAC_HEADAMP_SLOTS
line 414:  #define REAC_HEADAMP_MAX_CH     48
```

Two problems, not one.

* It is a **redefinition with a different body**, so every translation unit that includes the
  header emits a warning — including libreac's own `src/reac_ctrlblk.c`. `xcheck_ctrl_oracle.py`
  reports it on every run rather than letting it scroll past.
* `REAC_HEADAMP_SLOTS` **is not defined anywhere in libreac**. It belongs to reac-pw
  (`src/reac_slots.h`), which the comment beside line 370 names. So the first definition expands
  to an undefined identifier; it is inert only because the second one wins.

The values do agree — 48 either way, which is why `protocol-facts.yaml`'s `HEADAMP_CH_SPAN` binds
to this macro and the static assertion passes. The defect is structural, and it is the kind that a
migration mid-flight produces: a constant moved into a header that already had it.

**Fix belongs to the libreac lane**, which is mid-migration in that file. Deleting line 370 and
keeping line 414 is the whole change; the assertion in `generated/reac_facts_assert.h` will keep
the surviving one honest.

---

## 3. A gap, not a disagreement: libreac has no head-amp granularity at all

**This defect was mostly wrong, and how it was wrong is the useful part.** It read:

    SENS and the flag bits   PER CHANNEL          ch
    phantom                  PER GROUP OF FOUR    ch >> 2
    the readback nibble      PER EIGHT            ch >> 3

and concluded that libreac, which expresses none of them and sweeps phantom per channel, "writes
three records in four into the void — with correct bytes, correct checksums, and an acknowledging
box". Measured 2026-08-23: libreac's behaviour is the correct one. Phantom is per channel
(`HEADAMP_GRAN_PHANTOM_SHIFT` is now 0 — see wire-format.md), and the per-eight readback turned
out to be the same axis as the refresh bank rather than a third granularity. What was left of the
gap is one real thing, the 48-channel ceiling, and it is covered by `HEADAMP_CH_SPAN`.

The lesson worth keeping is the shape of the error: the schema had a number libreac lacked, so the
C side was filed as the deficient one and the plan was to make it conform. Had that landed before
the measurement, a correct implementation would have been broken to match a wrong constant. **A
convergence defect names a divergence, not which side is right** — decide that from evidence, not
from which side is more specific.

---

## 4. Not a defect, and worth saying so: the placement base

`reac.ksy` refuses to encode the per-model fabric slot base and parses the three collinear
carriers instead. `libreac`'s `reac_headamp_base()` returns the measured table (8 -> `0x00`,
16 -> `0x20`, 32 -> `0x00`) and refuses any width it has not seen.

Those look like a disagreement and are not. The grammar refuses to claim a LAW; the library
refuses to GUESS a value. `protocol-facts.yaml` carries the measured table under a group doc that
says in as many words that it is negotiated session state and not a wire field, so an adopter
cannot mistake it for something a frame carries.

---

## How these were found, and how the next one will be

Not by reading. By making one side build and the other side read:

```
make -C spec check-ctrl-oracle LIBREAC=../../libreac
```

libreac builds all 343 steps of a scene transfer from four different bodies; the ksy-generated
parser reads every frame; the body is reassembled out of what the parser found and compared byte
for byte with the input. Head-amp records go the same way, both checksums included, with a
deliberate wrong-stamping-order case that the grammar parses happily and the library must reject.
The committed corpus goes through both. The run reports INCONCLUSIVE rather than PASS on thin
coverage, and fires a positive control — a flipped byte that both sides must notice — before it is
allowed to print a zero.

A shared constant catches a typo. This catches a misunderstanding, which is what the two
disagreements above are.
