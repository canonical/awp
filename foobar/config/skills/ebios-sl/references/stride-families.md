# STRIDE feared-event families — authored CODE-BLIND (EBIOS RM)

> **Code-blind barrier (load-bearing).** Every family below is authored from **threat doctrine** (STRIDE
> + EBIOS RM / ANSSI) — **never** from reading the implementation. These families are enumerated as
> **feared events (`FE#`)** in W1 and chained through the strategic/operational scenarios (W3/W4) of a
> code-blind `ebios-sl` report. Naming a supporting asset by its *role* ("the certificate parser") is in
> scope; naming a file, function, hex constant, or ACSL goal is endogeneity and voids the exogenous
> bound (the `C8` tripwire FAILs on it — W1–W3 are scanned). The crosswalk (`crosswalk-format.md`) is the
> *only* code-aware join.

These are the families the new workstreams (WS1/WS3/WS4/WS6/WS7) add **on top of** the classic STRIDE
six. Each maps to a STRIDE column in the §3.3 coverage ledger and carries an EBIOS **severity** `G1`..`G4`.
EBIOS scenarios are written around the **deliberate attacker** (the risk origin / `RO#`), but two of
these families are *non-adversarial* by nature — flag them explicitly so they are not silently dropped
from a purely adversary-shaped study.

## WS1 — race / TOCTOU feared-event  (STRIDE: Tampering · **non-adversarial — in scope anyway**)
A check-then-act window where shared state changes between the check and the use. This is a feared
event **even with no risk origin / attacker**: a benign concurrent path, a signal handler, or a
reordered store is enough — so it does not fit the classic EBIOS "deliberate origin" mould and must be
authored as an `FE#` on its own merits (severity by impact on the business asset, e.g. `G3` if it can
corrupt a value asset). Author it from doctrine: *which assets are reachable from more than one flow of
control?* — never from inspecting locks in the code.

**Proof reach (state honestly in the crosswalk).** WS1 **stage-1** ships only a *syntactic*
`\guarded_by` proof — **lock-held-at-access**, **not** check-then-act atomicity. While only stage-1 is
shipped, the race cell stays **`TRUSTED`**, *never* `PROVED`; promoted to `PROVED` only when WS1 stage-2
(rely-guarantee) lands.

## WS3 — principal-spoofing trust boundary  (STRIDE: Spoofing · adversarial)
A **trust boundary** is a doctrine-level decision: across it an identity claim must be *authenticated*
before *trusted*. The feared event is "an unauthenticated principal is treated as authenticated."
Author it by drawing the boundary from the mission (who must prove who they are to whom), **not** from
the auth code. Mostly `TRUSTED` (crypto identity / certificate trust is BLOCKED for WP — a residual);
the amenable slice is only the memory-safety of the parser carrying the claim.

## WS4 — what-must-be-non-repudiable  (STRIDE: Repudiation · adversarial / accidental)
The doctrine question is "**which actions must leave evidence the actor cannot later deny?**" — an
accountability requirement decided from the mission. The feared event is "a security-relevant action
occurs without attributable, tamper-evident evidence." Almost always `TRUSTED`/`N/A` at the WP plane
(logging completeness/integrity is a logic residual); the column exists so the *gap* is named.

## WS6 — volumetric / flooding DoS  (STRIDE: Denial of Service · **environmental / out-of-band**)
**Volumetric / distributed flooding** (connection floods, amplification, edge resource exhaustion) is
an out-of-band threat treated by **rate-limiting / capacity controls carried in the EBIOS Security
Continuous Improvement Plan (SCIP / W5 treatment)**, **never** by a WP proof. The crosswalk cell is
**always a signed residual** (`TRUSTED`/`RR#`). *Distinguish it* from **algorithmic / bounded-work DoS**
(a single malicious input drives unbounded work) — *that* slice **is** amenable via the `\fuel`
step-budget spine (`\cost` = WP step bound, `\resource` = allocations/depth/handles) and can reach
`PROVED`. Author both as feared events; only the bounded-work one goes green.

## WS7 — privilege lattice (system-model decision)  (STRIDE: Elevation of Privilege · adversarial)
The **privilege lattice** is a **scope / system-model decision** (W1), not a finding: you *declare* the
partial order of privilege levels (the least-privilege baseline) as part of defining the system. The
feared event is "an actor acquires a privilege above its lattice position." `macsl` proves
**monotonicity over** this declared lattice (no operation climbs the order) as a least-privilege
hyperproperty — so this is one of the few EoP cells that can reach **`PROVED`**. The lattice itself is
authored code-blind; `macsl` only proves the code respects it.

## How these land in the ledger
| WS | Family | STRIDE col | EBIOS nature | W5 treatment | WP reach |
|----|---|---|---|---|---|
| WS1 | race / TOCTOU | T | **non-adversarial** (also deliberate) | integrity control / SCIP | `TRUSTED` (stage-1); `PROVED` at stage-2 |
| WS3 | principal-spoofing | S | adversarial | authentication baseline | mostly `TRUSTED` (crypto identity BLOCKED) |
| WS4 | non-repudiation | R | adversarial/accidental | audit/logging baseline | `TRUSTED`/`N/A` (logic residual) |
| WS6 | volumetric DoS | D | **environmental / out-of-band** | **SCIP rate-limiting** | **never `PROVED`** (signed residual); bounded-work slice → `\fuel` `PROVED` |
| WS7 | privilege lattice | E | adversarial | least-privilege baseline | `PROVED` (macsl monotonicity hyperproperty) |

The MITRE ATT&CK technique join and the cross-walk to NIST 800-53 control families live RMF-side:
[`../../rmf-sl/references/attack-mapping.md`](../../rmf-sl/references/attack-mapping.md). See
[`report-format.md`](./report-format.md) for how each non-proved family becomes a signed `RR#` residual
that the risk owner accepts at W5.
