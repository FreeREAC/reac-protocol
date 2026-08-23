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

## 1. SENS: three live readings of the same byte, spanning 19 dB

**Severity: this reaches an operator.** It is the number a console publishes as preamp gain.

A head-amp record's VALUE for `PARAM = 0x02` is a step index, `0x00..0x37`. What that step means
in dB has three different answers in the tree today, and all three are load-bearing somewhere.

| where | law | step 0x37 works out at |
|---|---|---|
| `spec/reac.ksy`, `head_amp_data.value` | "56 steps of 1 dB", `dB = -10 - value + (pad ? 20 : 0)` | **-65.00 dBu** |
| `libreac`, `reac_ctrlblk.h` + `SENS_GAIN_CDB[]` | a 56-entry firmware table, breaks at 8 / 24 / 40, per-stage 0.90 / 0.95 / 0.98 dB, total span 48.75 dB | **-58.75 dBu** |
| `reac-pw` commit `07d1802`, measured on the rig | ~1.235 dB per step, one number rather than a curve as far as that measurement can see | **-77.9 dBu** |

They are not roundings of each other.

* The **ksy** states the linear law flatly, in a `doc:` block a third party would reasonably build
  a client from. `reac-pw`'s `reac_ctrl.h` says the same thing (`1 dB/step`), so two of the three
  agree — which is exactly the situation where a wrong number looks confirmed.
* **libreac** refutes linearity with two independent things: a 56-entry table resolved out of the
  S-1608's own image, reached by both of the firmware's write paths and ending exactly where the
  `V03.05` version string begins; and a noise-floor measurement on an S-0808 that reproduces to
  0.03 dB across sessions. Its curve has a structural consequence a linear law cannot express at
  all: **the map is not injective.** Gain is continuous across the three stage breaks, so steps
  7/8, 23/24 and 39/40 deliver the same gain and differ only in noise. `reac_headamp_sens_value_cdb()`
  deliberately returns the quieter twin. A round trip through libreac's law and a round trip
  through the ksy's law are therefore **different functions**, not two spellings of one.
* **reac-pw** measured the wire with a real acoustic source, one commanded change at a time, and a
  return-to-baseline control that landed 0.3 dB from where it started after three L2 cycles. Over
  the widest span it read 1.235 dB per step — larger than either written law. That commit
  deliberately did NOT correct the codec, and says why: the conversion runs both ways,
  `reac_slave.c` derives a virtual preamp gain from it, and openmixer carries `sensDbu` across the
  wire, so three components agree on today's scale and moving it wants its own change, its own
  before/after on the rig, and the operator's say-so on whether the published unit moves with it.

**Not reconciled here, and deliberately.** `protocol-facts.yaml` therefore carries no SENS curve:
a schema whose job is to stop drift must not be the place a contested number gets frozen by
whoever typed the file first. What it does carry is `HEADAMP_SENS_MAX = 0x37`, which all three
agree on.

**What would settle it**, and it is not another microphone: a steady electrical source or a tone
into the input, swept across all 56 steps, with the stage breaks at 8 / 24 / 40 specifically
probed for the duplicate-gain twins libreac predicts. A linear law predicts no twins; the table
predicts three. That is a discriminating experiment, and nobody has run it.

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

`reac.ksy` states, from the box's own executed code, that "head-amp" is **three granularities**:

    SENS and the flag bits   PER CHANNEL          ch
    phantom                  PER GROUP OF FOUR    ch >> 2
    the readback nibble      PER EIGHT            ch >> 3

libreac expresses none of them. It has `REAC_HEADAMP_NPARAMS = 3` and a 48-channel ceiling, and
nothing that says a phantom record to `0x27` moves nothing while one to `0x24` moves group 9. A
consumer built on libreac alone will sweep phantom per channel and write three records in four
into the void — with correct bytes, correct checksums, and an acknowledging box.

The schema now carries `HEADAMP_GRAN_*_SHIFT` for all three, so this closes as soon as the header
is adopted. Until then it is a gap in the C side that the grammar has already documented, which is
the mirror image of the SENS defect above.

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
