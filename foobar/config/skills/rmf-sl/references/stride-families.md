# STRIDE feared-event families — authored CODE-BLIND (RMF)

> **Code-blind barrier (load-bearing).** Every family below is authored from **threat doctrine** (STRIDE
> + NIST SP 800-30/53) and the threat-intelligence corpus — **never** from reading the implementation.
> These families are enumerated in R2 (threat sources & events) of a code-blind `rmf-sl` report. Naming
> an asset by its *role* ("the TLS record parser") is in scope; naming a file, function, hex constant,
> or ACSL goal is endogeneity and voids the exogenous bound (the `C8` tripwire FAILs on it). The crosswalk
> (`crosswalk-format.md`) is the *only* code-aware join; the report stays disjoint from the source.

These are the families the new workstreams (WS1/WS3/WS4/WS6/WS7) add **on top of** the classic STRIDE
six. Each maps to a STRIDE column in the §3.3 coverage ledger and to an 800-30 threat **origin**
(`ADV` adversarial · `ACC` accidental · `ENV` environmental — the origin set RMF weights, unlike EBIOS
which weights only the adversarial). Each names how (or whether) it can ever reach a WP proof.

> **Each WS family has a macsl `\context(...)` that expresses it** — pick it from the catalog
> `config/skills/frama-c-api/references/macsl-contexts.md` (source of truth: `macsl -macsl-list-contexts`):
> WS1 race/TOCTOU → `\guarded_by` / `\stable_check`; **WS3 principal/authorization → `\authorized`**;
> WS4 non-repudiation → `\tamper_evident`; WS6 bounded-work → `\fuel`; WS7 lattice/RBAC → `\flow`; plus the
> classic six: Tampering → `\writing`, Info-disclosure → `\noninterference \secret(…)` / `\reading`, DoS →
> `\total`. These are **in the tool** — do not fall back to `\writing`/`\total` or a hand-rolled WP
> postcond when the row names a richer context.

## WS1 — race / TOCTOU feared-event  (STRIDE: Tampering · origin **ACC** — in scope with no adversary)
A check-then-act window where shared state changes between the check and the use. 800-30 weights this
as an **accidental** origin: it is a feared event **even when there is no attacker** — a benign
concurrent path, a signal handler, or a reordered store is enough. So `TS#` for this family is tagged
`ACC` (and may *also* be raised by an `ADV` source who races deliberately). The feared event is "stale
read / lost update / inconsistent multi-field state," not "an attacker injects." Author it from
doctrine: *which assets are reachable from more than one flow of control?* — never from inspecting
locks in the code.

**Proof reach (state honestly in the crosswalk).** WS1 **stage-1** ships only a *syntactic*
`\guarded_by` proof — it establishes **lock-held-at-access**, **not** check-then-act atomicity. While
only stage-1 is shipped, the race-family cell stays **`TRUSTED`**, *never* `PROVED`; it is promoted to
`PROVED` only when WS1 stage-2 (rely-guarantee / atomicity) lands. Until then the residual is signed,
not proved.

## WS3 — principal-spoofing trust boundary  (STRIDE: Spoofing · origin **ADV**)
A **trust boundary** is a doctrine-level decision: across it, an identity claim must be *authenticated*
before it is *trusted*. The feared event is "an unauthenticated principal is treated as an authenticated
one" — peer-identity confusion, forged origin, accepted-without-verification. Author it by drawing the
boundary from the mission (who must prove who they are to whom), **not** from the auth code.

**Proof reach.** Split the family: the **authorization decision** ("the principal is GENUINE — a
forged/literal principal does not satisfy the gate without the binding") IS expressible via macsl
`\authorized` (WS3 write-site walk over the uninterpreted `authorized(principal,OP)`) — drive it in-situ,
do **not** hand-roll it as a WP postcondition (the campaign smell). Only the **crypto identity** slice
(certificate/signature trust) stays `TRUSTED` (BLOCKED for WP — a residual). Most of
this family is `TRUSTED` (crypto identity / certificate trust is BLOCKED for WP — a residual); the
amenable slice is only the memory-safety of the parser that *carries* the claim.

## WS4 — what-must-be-non-repudiable  (STRIDE: Repudiation · origin **ADV**/**ACC**)
The doctrine question is "**which actions must leave evidence that the actor cannot later deny?**" — an
audit/accountability requirement decided from the mission, before any logging code exists. The feared
event is "a security-relevant action occurs without attributable, tamper-evident evidence." This family
is almost always `TRUSTED` or `N/A` at the WP plane (logging completeness/integrity is a logic/control
residual, not a memory-safety property); the column exists so the *gap* is named, not silently absent.

## WS6 — volumetric / flooding DoS  (STRIDE: Denial of Service · origin **ENV** — out-of-band)
**Volumetric / distributed flooding** (connection floods, amplification, resource exhaustion at the
network edge) is an **environmental / out-of-band** threat: it is treated by **rate-limiting and
capacity controls (800-53 SC-5 / SC-7)**, **never** by a WP proof. The crosswalk cell for this family
is **always a signed residual** (`TRUSTED`/`RR#`), never `PROVED`. *Distinguish it* from **algorithmic /
bounded-work DoS** (a single malicious input drives unbounded work) — *that* slice **is** amenable: it
reaches a WP proof via the `\fuel` step-budget spine (`\cost` = WP step bound, `\resource` =
allocations/depth/handles). Author both as feared events; only the bounded-work one can go green.

## WS7 — privilege lattice (system-model decision)  (STRIDE: Elevation of Privilege · origin **ADV**)
The **privilege lattice** is a **Categorize-step / system-model decision**, not a finding: you *declare*
the partial order of privilege levels (who may do what) as part of defining the system — the **AC-6
least-privilege** baseline. The feared event is "an actor acquires a privilege above its lattice
position." `macsl` proves **monotonicity over** this declared lattice (no operation moves an actor up
the order) as a least-privilege hyperproperty — so this is one of the few EoP cells that can reach
**`PROVED`** (e.g. an API mode-gate). The lattice itself is authored code-blind from the AC-6 baseline;
`macsl` only proves the code respects it.

## How these land in the ledger
| WS | Family | STRIDE col | 800-30 origin | 800-53 / control | WP reach |
|----|---|---|---|---|---|
| WS1 | race / TOCTOU | T | **ACC** (also ADV) | SI-7 / SC-3 | `TRUSTED` (stage-1); `PROVED` only at stage-2 |
| WS3 | principal-spoofing | S | ADV | IA-2 / SC-23 | mostly `TRUSTED` (crypto identity BLOCKED) |
| WS4 | non-repudiation | R | ADV/ACC | AU-10 / AU-9 | `TRUSTED`/`N/A` (logging = logic residual) |
| WS6 | volumetric DoS | D | **ENV** (out-of-band) | **SC-5 / SC-7 rate-limiting** | **never `PROVED`** (signed residual); bounded-work slice → `\fuel` `PROVED` |
| WS7 | privilege lattice | E | ADV | **AC-6 least-privilege** | `PROVED` (macsl monotonicity hyperproperty) |

See [`attack-mapping.md`](./attack-mapping.md) for the feared-event → MITRE ATT&CK technique join and the
full 800-53 control families. See [`report-format.md`](./report-format.md) §5 for how each non-proved
family becomes a signed `RR#` residual.
