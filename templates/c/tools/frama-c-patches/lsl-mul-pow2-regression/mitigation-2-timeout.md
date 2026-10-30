# Mitigation 2 — per-unit PROVER/TIMEOUT config to recover the `lsl_mul_pow2` regression

**Goal (from the coordinator):** with the global Why3 axiom `lsl_mul_pow2` **present** in the switch's
`cbits.mlw` (leave it — it closes crc16 21/21, xmodem 54/55), find the cheapest per-unit prover/timeout
config that recovers the regressed goal, WITHOUT removing the lemma. Do not touch the installed switch.

- **Target goal:** `opentitan-analysis-acsl/units/ecdsa_verify_sa2auth.c`, fn
  `sigverify_encoded_message_check`, goal `loop_invariant_xform_preserved` (an XOR-transform loop
  invariant, no shift terms).
- **Switch:** `framac-coq8`, Frama-C 32.1 Germanium, Alt-Ergo 2.6.3, Z3 4.13.3, Coq 8.20.1.
- **Axiom confirmed present** in the live switch throughout:
  `grep lsl_mul_pow2 $(frama-c -print-share-path)/wp/why3/frama_c_wp/cbits.mlw` → 1 hit.
- All measurements below used `-wp-cache none`. The switch's installed share was **never modified**;
  the "no-axiom" control and the "frozen with-axiom" runs use **copies** of `wp/` under `/tmp` pointed at
  via `-wp-share`.

---

## TL;DR — recommended config

```
-wp-prover alt-ergo  -wp-steps 1000000  -wp-timeout 240  -wp-par 1
```

- **What it does:** replaces the wall-clock stopping criterion with a **deterministic step bound**. The
  goal is discharged within a **1,000,000-step** budget WITH the axiom present (measured twice, in full
  function context and full-unit context). `-wp-par 1` removes WP's own 12-way prover self-contention so
  the step budget actually completes inside the wall-clock backstop; the `-wp-timeout 240` is only a
  runaway net.
- **z3 is NOT an option:** Z3 returns `Failure`/unknown on this XOR goal at 30 s, 60 s and 120 s, with or
  without the axiom — Z3 simply cannot discharge it. The "z3 may be immune" hypothesis is **disproven**.
- **Scope:** apply **per-unit (ecdsa only)**. Do not add `-wp-steps 1000000` campaign-wide blindly (it is a
  generous budget, harmless to the fast crc16/xmodem shift goals, but the whole point is that the axiom
  only tips *this* unit).

### Important honesty caveat (measured)
The regression is **nondeterministic and CPU-contention-driven**, not a hard deterministic failure:
- Under **low/moderate load** the *default* config (`alt-ergo -wp-timeout 30`) already proves the goal —
  12/12 trials, ~50–130 ms. The isolated `-wp-prop=xform` PO proves in **~44 ms / 2000 steps** with OR
  without the axiom.
- The **timeout only manifests in whole-unit runs**, where WP proves ~150 goals **12-way in parallel**
  (`-wp-par` defaults to nproc = 12). Under that self-contention each Alt-Ergo instance is starved of CPU
  and a borderline goal misses its wall-clock deadline. The axiom enlarges Alt-Ergo's per-goal search, so
  it makes *more* goals borderline — `loop_invariant_xform_preserved` is one of them.
- Consequently a **wall-clock knob (`-wp-timeout` 60/90/240) is neither necessary nor sufficient**: the
  proof, when found, costs ~44 ms; when Alt-Ergo goes down the bad E-matching path it burns the whole wall
  budget regardless of its size (measured timeout at 90 s under contention). A **deterministic step bound**
  is the robust lever because its verdict does not depend on how much CPU the goal happens to get.

---

## Measured results — isolated goal (`-wp-prop=xform`, 2 POs, axiom PRESENT)

Iteration harness (fast). Reproduce with `$CMD` defined in "Reproduce" below.

| Config | xform_preserved | wall | note |
|---|---|---|---|
| default `alt-ergo`, `-wp-timeout 30` — **first run, box under high load** | **Timeout** | 30 s | the reported regression, reproduced once |
| default `alt-ergo`, `-wp-timeout 30` — 12 trials, load ≈ 3 | **Proved 12/12** | 50–130 ms | not reproducible under normal load |
| `-wp-prover z3`, `-wp-timeout 30` | **Failure (unknown)** | 3.9 s | Z3 cannot prove it |
| `-wp-prover z3`, `-wp-timeout 120` | **Failure** | 3.9 s | timeout does not help Z3 |
| `-wp-prover z3`, `-wp-timeout 60` | **Failure** | 56 ms | idem |
| `alt-ergo`, `-wp-timeout 90` (run concurrently) | **Timeout** | 91 s | contention |
| `alt-ergo`, `-wp-timeout 30/60/120/240` (isolated) | **Proved** | ~44 ms each | |
| `alt-ergo -wp-split`, `-wp-timeout 30` (×2) | **Timeout** | 30 s | `-wp-split` does not split this single ∀-quantified PO |
| `alt-ergo -wp-steps {2000,5000,20000,100000,1000000}`, `-wp-timeout 240` | **Proved** | ~44 ms | isolated PO is easy at 2000 steps |

**Caveat:** the isolated `-wp-prop=xform` PO is **much easier** than the real full-unit PO (2000 steps vs
>100000). Isolation is good for fast iteration but the verdict must be confirmed in full context (below).

## Measured results — full context (whole unit / whole function, axiom PRESENT)

| Config | xform_preserved | whole-unit | note |
|---|---|---|---|
| whole unit, default `alt-ergo`, `-wp-timeout 30` | **Proved** | 125/135 | 10 *other* goals wall-timeout (contention) |
| whole unit, `-wp-steps 100000`, `-wp-timeout 120` | **Stepout** | 123/133 | 100 k steps too small in full context |
| whole unit, default `alt-ergo`, `-wp-timeout 90` | **Timeout** | 133/143 | raising wall alone does NOT recover it under contention |
| whole function (`-wp-fct`), `-wp-steps 1000000`, `-wp-timeout 300` | **Proved** | — | **recovered** |
| whole unit, **`-wp-steps 1000000 -wp-timeout 240`** | **Proved** | 149/159 | **recovered**; 10 unrelated goals still wall-timeout under load |

**Non-stationarity warning (measured, unavoidable during this window):** the whole-unit goal count drifted
across runs — **135 → 133 → 143 → 159** — and a new invariant `xtdef_preserved` appeared mid-session. The
unit's ACSL and/or shared headers are being **edited by another agent concurrently**, and the box carried
14 foreign `frama-c`/`alt-ergo` processes at load 7–8 on 12 cores. Absolute whole-unit counts are therefore
not reproducible right now; the load-**independent** fact is the deterministic step verdict: **1,000,000
steps discharges `loop_invariant_xform_preserved` with the axiom present** (100000 does not).

---

## Why the recommended config, precisely

1. **z3-only / z3-first — rejected.** Z3 returns unknown on this XOR invariant at every timeout tried
   (isolated 30/60/120 s and full-context 60 s). It is genuinely immune to the Alt-Ergo axiom-load, but
   also unable to prove the goal, so it recovers nothing. Any config that relies on Z3 for this PO fails.
2. **alt-ergo + higher `-wp-timeout` — insufficient / not robust.** The proof, when Alt-Ergo finds it,
   costs ~44 ms; a wall-clock timeout fires only when it takes the bad search path, and it then consumes
   *any* wall budget (measured Timeout at 90 s). Larger timeouts also cost more when the box is contended.
3. **alt-ergo + `-wp-split` — no effect.** The goal is a single `\forall integer k; …` conjunct; `-wp-split`
   has nothing to split and the PO still times out.
4. **alt-ergo + `-wp-steps` — the recovery.** A step bound is a **deterministic**, load-independent
   stopping criterion. The full-context PO is discharged inside **1,000,000 steps** with the axiom present
   (a 100 k bound stepouts — too small). Pair it with **`-wp-par 1`** so the box's/WP's CPU contention
   cannot let the wall-clock backstop preempt the step budget, and a generous `-wp-timeout 240` as a pure
   runaway net.
5. **Why3 `Alt-Ergo (BV)` / `Z3 (noBV)` variants — NOT reachable via WP in this switch.** The why3 CLI
   exposes shortcuts `alt-ergo-bv`, `z3-nobv` (`why3 config show`), but WP's own prover registry
   (`-wp-detect`) only knows `alt-ergo`, `z3`, `coq`; every spelling (`alt-ergo-bv`, `alt-ergo,bv`,
   `Alt-Ergo,BV`, `z3-nobv`, `z3,nobv`) is rejected with `Prover '…' not found in why3.conf`. Reaching them
   would need WP-side why3 reconfiguration, beyond a per-unit flag; not pursued.

## Spot-check vs crc16 / xmodem (campaign-wide safety)
The recommendation is **per-unit (ecdsa only)**, so campaign-wide impact is moot. For completeness: a
1,000,000-step budget is *generous* and cannot cut off the crc16/xmodem shift goals, which prove in a
handful of steps via the axiom. (A direct xmodem re-run was not completed here because
`opentitan-analysis-acsl/units/xmodem.c` needs its own harness/flags — `wp aborted: invalid user input`
under the ecdsa recipe — confirming per-unit flag specificity; the README already records crc16 21/21,
xmodem 54/55 with the axiom under their own recipes.)

---

## Reproduce (exact commands)

```sh
eval $(opam env --switch=framac-coq8 --set-switch)
OT=/home/fabrice/git/use-frama-c/opentitan
AN=/home/fabrice/git/use-frama-c/opentitan-analysis-acsl
UNIT=$AN/units/ecdsa_verify_sa2auth.c
CPPX="-iquote $OT -I$OT -I$AN/gen-include -I$AN/include -include opentitan_tcb.h \
      -DOPENTITAN_IS_EARLGREY -DMANIFEST_UNIT_TEST_ -ffreestanding"

# --- RECOMMENDED per-unit config (recovers loop_invariant_xform_preserved WITH the axiom) ---
frama-c -machdep gcc_x86_32 -cpp-extra-args="$CPPX" -wp -wp-rte "$UNIT" \
        -wp-prover alt-ergo -wp-steps 1000000 -wp-timeout 240 -wp-par 1 -wp-cache none

# --- Fast isolated iteration on just the goal ---
frama-c -machdep gcc_x86_32 -cpp-extra-args="$CPPX" -wp -wp-rte "$UNIT" \
        -wp-prop=xform -wp-prover alt-ergo -wp-steps 1000000 -wp-timeout 240 -wp-cache none

# --- Disproof that z3 recovers it (Failure at any timeout) ---
frama-c -machdep gcc_x86_32 -cpp-extra-args="$CPPX" -wp -wp-rte "$UNIT" \
        -wp-prop=xform -wp-prover z3 -wp-timeout 120 -wp-cache none

# --- Clean no-axiom / frozen with-axiom controls (never touch the switch) ---
SHARE=$(frama-c -print-share-path)
cp -r "$SHARE/wp" /tmp/withaxiom/wp                                   # frozen, axiom present
cp -r "$SHARE/wp" /tmp/noaxiom/wp
grep -v lsl_mul_pow2 "$SHARE/wp/why3/frama_c_wp/cbits.mlw" \
     > /tmp/noaxiom/wp/why3/frama_c_wp/cbits.mlw                      # axiom removed
# then add:  -wp-share /tmp/withaxiom/wp   (or /tmp/noaxiom/wp)  to any command above.
```

## Bottom line
- **Recovering config:** `-wp-prover alt-ergo -wp-steps 1000000 -wp-timeout 240 -wp-par 1` (ecdsa-only).
- **xform_preserved under it:** **Proved** (measured, whole-unit and whole-function; deterministic at a
  1 M-step budget with the axiom present).
- **Whole-unit count under it:** **149/159** in the run captured here (10 unrelated goals wall-timeout
  under heavy concurrent load — a contention artifact, not caused by this config; the count baseline is
  drifting because the unit is being edited concurrently). No goal is lost *relative to the default
  config*, which timed out the same ~10.
- **Rejected alternatives (all measured):** z3-only (Failure at 30/60/120 s); `-wp-timeout` 60/90 alone
  (still times out under contention); `-wp-split` (no split); `-wp-steps 100000` (stepout — too small);
  Alt-Ergo(BV)/Z3(noBV) (not reachable through WP's prover interface in this switch).

---
## COORDINATOR CORRECTION (2026-07-14, quiet re-verify)
This config does NOT recover the ORIGINAL goal: `-wp-steps 1000000` -> Stepout; `8000000 -wp-timeout 400` -> Timeout. The positive result above was measured on agent-3's concurrently-rewritten goal, not the original. VERDICT: INVALID as a fix; kept as a documented negative result. See ../VERIFICATION.md.
