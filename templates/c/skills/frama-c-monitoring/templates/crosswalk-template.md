# Crosswalk + STRIDE coverage ledger — canonical template

The **schema contract** for the threat↔verification join. A crosswalk is the one document where the
**code-blind** risk study (exogenous upper bound `U`) meets the **code-aware** verification (lower
bound `L`) without contaminating either. It is authored by the *architect* (who reads the source) —
that asymmetry is the whole point, and it is what keeps the upstream `ebios-sl` / `rmf-sl` report
exogenous.

This template is consumed by:
- `rmf-sl` / `ebios-sl` — produce the per-campaign crosswalk (`rmf-crosswalk.md` / `ebios-crosswalk.md`);
- `bin/rmf-lint.sh` / `bin/ebios-lint.sh` — emit + structurally check the STRIDE coverage ledger (§3);
- `frama-c-monitoring` — the join (§2/§4) and the **ratchet CI gate** (§3) over the ledger.

> **Plane / no-blend rule (load-bearing).** A WP `PROVED` is a **hard** truth that retires exactly
> **one class** (RTE / memory-safety, or one named functional property) of **one** attack step on the
> **amenable** surface of **one** supporting asset. A green does **not** lower the risk *level* — only
> the risk owner / Authorizing Official does that, at the human terminus, downstream. **Every row names
> its plane.** A green cell may never silently stand in for a risk-level reduction.

---

## 1. Asset crosswalk — supporting asset ↔ translation unit ↔ scope

| Supporting asset (Wkshop-1 / Categorize) | Translation unit(s) | Scope-map status | Note |
|---|---|---|---|
| **SA1** … | `path/to.c` | **amenable** / **split** / **BLOCKED** | one-line plane note |

- **amenable** — the whole asset is WP-reachable (RTE and/or the named functional property).
- **split** — field/length parsing amenable; the decision/state/crypto *logic* is BLOCKED.
- **BLOCKED** — out of WP reach (crypto math, entropy quality, side-channel, protocol-state logic).

## 2. Scenario crosswalk — the exogenous ranking (highest risk first)

Ranking key = the risk study's own **risk level** (severity × likelihood / impact × likelihood),
**cited, not re-derived** from the code. Where the feared event is logic/crypto/state, the
verification target is **BLOCKED → non-formal** (a flagged residual, §5), never a silent drop.

| ID | Attack path | SA → TU | Feared event · severity | Likelihood | Risk | Verification target | Priority |
|----|---|---|---|---|---|---|---|
| RS1/AP1 | … | SA1 → `t.c` | FE… · **Hi/G4** | **L4/V2** | **High** | RTE no-OOB on the decode path | **1** |

## 3. STRIDE coverage ledger — asset × {S,T,R,I,D,E}  (WS2; the Gate-C surface)

The completeness ledger `macsl` cannot self-produce: a family can be unmodeled for an asset and the
suite still goes green. Enumeration is owned **here** (threat loop + crosswalk), not by the plugin.

### 3.1 Cell lifecycle (the ratchet)

Every (asset, family) cell holds exactly one token:

| Token | Meaning | Set by |
|---|---|---|
| `UNMODELED` | no policy authored, no residual signed — **the gap** | default |
| `PROVED` | a non-vacuous `macsl`/WP verdict retires the family's amenable core for this asset | `frama-c-monitoring` join (§4) from WP + `-macsl-list-targets` |
| `TRUSTED-PENDING` | declared out-of-amenable-scope; awaiting human sign-off | threat-loop author |
| `TRUSTED` | signed residual — risk owner / AO accepted it | human terminus only |
| `N/A` | family structurally inapplicable to this asset (justify in note) | threat-loop author |

### 3.2 Ratchet rule (Issue 2 — regression-only, so the gate is not DOA)

The CI gate (`frama-c-monitoring`, §4) **fails only on regression**, never on a merely-incomplete
matrix:

1. **FAIL** if a cell was `PROVED` or `TRUSTED` in the frozen baseline and is now `UNMODELED`.
2. **FAIL** if a **high-value asset** (any SA driving a Hi/G4 scenario in §2) appears with **no row**.
3. **WARN** (not fail) on any `UNMODELED` / `TRUSTED-PENDING` cell — surfaced, ratcheted, never blocking.
4. The first ledger ships a **frozen baseline** (`*-ledger-baseline.tsv`): every current cell accepted
   as-is. Progress = cells moving `UNMODELED → PROVED | TRUSTED`; the baseline only moves forward.

> **WS1 stage-1 caveat (Issue 3).** A syntactic `\guarded_by` proof establishes *lock-held-at-access*,
> **not** check-then-act atomicity. While only WS1 stage-1 is shipped, the race-family cell (column
> under the relevant asset) **stays `TRUSTED`, never `PROVED`** — it is promoted to `PROVED` only when
> WS1 stage-2 (rely-guarantee) lands. The join gate (§4) enforces this.

### 3.3 The matrix (one row per supporting asset)

| Asset | S | T | R | I | D | E | ATT&CK (WS9) |
|---|---|---|---|---|---|---|---|
| SA1 | `UNMODELED` | `PROVED` | … | … | … | … | T1059,… |

## 4. Verdict join — what verification covers vs the ranking

**Plane: every "covers" is the named property only (RTE / the stated functional contract).** Joined by
`frama-c-monitoring` from the overlay `verdicts.tsv` + `macsl` non-vacuity verdicts.

| Scenario target | Verdict (verdicts.tsv) | What it retires (named plane) | Residual (other planes) |
|---|---|---|---|
| RS1/AP1 (rank 1) | unit `f` PROVED N/N | the memory-safety step on path X | crypto/logic = residual §5 |

## 5. Residual register — named, planed, signed

Out-of-model **by design**; the job is to make each a *listed, signed* residual, never a false proof.
Each row cites its scenario (RS#) and routes to non-formal treatment; the human terminus signs.

| RR# | Residual | Plane | Treatment (non-formal) | Signed (risk owner / AO) |
|---|---|---|---|---|
| RR1 | crypto primitive strength | crypto | review / KAT vectors | ☐ PENDING |

Standing residual classes (always named, never proved): cryptographic primitive strength; network
flooding / volumetric & distributed DoS (out-of-band rate-limiting — RMF 800-53 / EBIOS SCIP);
compiler correctness / supply-chain (SLSA / reproducible build); physical & social-engineering.

## 6. Handoff

- **Verification priority** = the §2 ranking (this is the order `frama-c-monitoring` pursues).
- **Feedback** = when the campaign closes amenable goals, propose *likelihood* deltas for the proved
  *memory-safety / named-property* step **only** (per the loop's `references/*-feedback.md`), keyed to
  RS#/CTL#/SA#, **no proof internals** (keeps a future code-blind re-run exogenous). Carry every
  BLOCKED residual into the Authorize / W5 step for human adjudication.

---

### Authoring invariants (every crosswalk must hold)

- **Asymmetry preserved** — the upstream report passed the endogeneity tripwire (no code artifacts in
  the code-blind sections); only *this* document is code-aware.
- **No-blend** — every §3/§4 cell names its plane; a green never lowers a risk level here.
- **Ratchet** — §3.2 holds; the baseline only moves forward; no `UNMODELED` for a high-value asset is
  silently green — it is a `WARN` ratcheted toward `PROVED`/`TRUSTED`.
- **`\fuel` spine (Issue 4)** — DoS/bounded-work cells reference `\fuel` (step-budget) with `\cost`
  (WP step bound) and `\resource` (allocations/depth/handles) as its projections; the relational
  timing cell uses `\noninterference(\cost)`.
