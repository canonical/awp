# Coordinator verification of the three mitigations (2026-07-14, QUIET env, `-wp-cache none`)

Re-verified every agent claim independently on a **quiet machine** (stray solvers killed, load ~0.4),
single-prover alt-ergo where decisive, against the CORRECT ecdsa version for each (agent 1/2 → original
`git HEAD` ecdsa; agent 3 → its rewrite). The concurrent runs had confounded the agents' own measurements.

## Ground truth (settled)
The regression is **REAL and deterministic**, not merely CPU-contention: isolated `xform_preserved`,
alt-ergo, `-wp-timeout 20`, quiet →
- axiom **global**: **Timeout (1/2)**  ·  axiom **lean** (removed via `-wp-share` copy): **Proved (2/2)**.
The axiom enlarges Alt-Ergo's search so this XOR-under-∀ goal exceeds the default budget.

## Verdicts
| mitigation | verdict | evidence |
|---|---|---|
| **(1) opt-in `CbitsShift` theory** | ✅ **VALID — the clean fix** | ecdsa on LEAN share → **72/79**, `xform` AND `diff_match` both PROVED, only the known-open saturation+store-bloat remain. crc16 with the opt-in driver → **21/21**; without → 20/21 (control). Sound (same realized axiom, relocated). Switch unmutated. |
| **(2) timeout / step-bound** | ❌ **INVALID** | On the ORIGINAL goal, `-wp-steps 1000000` → **Stepout**; `-wp-steps 8000000 -wp-timeout 400` → **Timeout**. NO reasonable budget recovers it. Agent 2's "1M steps works" was measured on agent-3's *rewritten* goal (concurrent-edit confound it flagged). z3-only disproven (returns unknown). Kept as a documented NEGATIVE result. |
| **(3) ghost-mirror invariant** | ⚠️ **NOT CLEAN — trades one regression for another** | Recovers `xform` (2/2, faithful, `strip==pristine` byte-exact) BUT **regresses `diff_match`** (proved 1/1 on original → Timeout 0/1 under M3) + adds a ghost `assert_rte_mem_access_23` that also fails. The ghost arrays enlarge the state and tip a different borderline goal. Agent 3's "zero regressions / all 24 ghost goals proved" claim is **contradicted**. Stored as a reference variant, NOT applied to the live overlay. |

## Recommendation: adopt (1) — ✅ ADOPTED & OPERATIONAL 2026-07-14
It is the only mitigation that closes the shift residuals (crc16 21/21, xmodem 54/55) AND keeps ecdsa at
its clean 72/79 with no traded regression.

**Operationalized on the live switch (measured on the real lean share, not a `-wp-share` copy):**
1. The switch `cbits.mlw` is now **LEAN** — global `lsl_mul_pow2` + its orphaned `use int.Power` stripped
   (`$(frama-c -print-share-path)/wp/why3/frama_c_wp/cbits.mlw`, count 0).
2. `../wp-cbits-bound-lemmas/apply.sh` no longer inserts the axiom globally; it now **strips** any stale
   global copy (idempotent) and directs shift units to the opt-in driver.
3. Shift-unit recipe wired: `opentitan-analysis-acsl/onboard-flags.sh` defines `$OT_SHIFT_OPTIN`
   (`-wp-driver=…/shift_lemmas.driver -wp-library=…/wp-library`) — pass it ONLY to shift-heavy units.
4. Live re-verification on the lean switch: ecdsa **72/79** (`xform` proved), crc16 20→**21/21** and
   xmodem_recv_frame 53→**54/55** with the opt-in driver.

The live `ecdsa_verify_sa2auth.c` overlay is left at the ORIGINAL (pristine + baseline ACSL) — M3's
rewrite is NOT applied.

## SA2 saturation re-run on the enriched toolchain (2026-07-14, confirms scoping)
Re-ran `sigverify_encoded_message_check` on the operationalized toolchain to check the class-(iii)
2's-complement saturation goals (`assert_step1: diff==0 || (diff>>31)==1`, `assert_diff_sat`):
- **Lean, no driver (the correct config): 72/79.** The 2 saturation goals stay Timeout, dragging 5
  downstream goals with them (`ensures_auth`, `assert_xdone`, `rte_mem_access_6`, `assigns_normal_part07`,
  `assigns_exit_part7` all consume `diff==0||0xFFFFFFFF`). One root cause (the sign-bit slice) → 7 unproved.
  Longer budget (60s, z3-first) on just `step1,diff_sat` → still 0/2.
- **Lean + opt-in driver ON ecdsa: 71/79** — `xform_preserved` regresses AND the saturation still doesn't
  close. This is the exact regression M1 avoids: loading `lsl_mul_pow2` on a shift-free unit re-enlarges
  Alt-Ergo's search. **Confirms the scoping rule — the driver belongs on shift-heavy units ONLY; ecdsa
  stays lean.**

The enrichment is **orthogonal** to the saturation: `lsl_mul_pow2` is left-shift-as-multiplication; the
saturation needs a right-shift/sign-bit fact. Class (iii) is unchanged — its only sound route remains a
WP-level bit-slice normalization pass (or a whole-VC WP→Coq proof), per
`../../bugs-to-report/wp-bitwise-smt-incompleteness/REPORT.md §2`. No regression, no progress on this goal;
correct ecdsa verdict stays **72/79**.
