# Learned knowledge — Architect / auditor (frama-c-launch)

Append-only, Gate-S-gated heuristics the **architect** capitalized while running the Phase-0
audit during onboarding (see this skill's `SKILL.md` §4 step 1, §6). Each entry passed an
`sl-monitoring-sl` Gate S audit by a disjoint monitor and carries provenance.

**Scope / barrier:** how to produce the **scope map** (WP-amenable vs BLOCKED, with reasons) and
the **attack-surface ranking** for a heterogeneous codebase, read-only. Record audit/ranking
knowledge only — no flags (prober's job), no proof specifics, no monitor verdicts. The audit
**reads the implementation**, so its functional claims are endogenous — see the discipline below.

**Entry format:**
```
### <title>
- Kind: ignore-signal | defer-to-oracle
- Gate S: PASS | CARVE-OUT
- Arose from: <target / gap-N>
- Heuristic: <rule>
- Carve-out: <exception → guidance clause>   (if any)
```

## Entries

### Rank by input-exposure; the parsing layer is the attack surface
- Kind: defer-to-oracle
- Gate S: CARVE-OUT
- Arose from: mbedtls (4.x moved crypto to a submodule → `library/` is the parsing layer)
- Heuristic: for a security mission, the value/risk ranking is by **untrusted-input exposure** —
  the decoders/parsers of attacker-controlled bytes come first (mbedtls: ASN.1 `get_len`/`get_tag`
  → X.509 field parsers → mps_reader → record-header → cookie/ticket → ciphersuite). Report
  coverage as a fraction of this **amenable attack surface**, never the whole tree. A library that
  has moved its crypto out (mbedtls 4.x) is *mostly* parsing layer — recognize that shape.
- Carve-out: input-exposure is read **off the code** (endogenous — see the next entry). **When an
  EBIOS RM study exists, defer to it**: rank by EBIOS **risk level** (severity × likelihood) via
  `../templates/ebios-crosswalk.md`, the exogenous bound. Input-exposure is the *fallback* when no
  study exists (and the ranking is then marked endogenous). Reassuringly, on mbedtls the two agree —
  the risk-grounded order (ASN.1 → X.509 → record header) is the order the campaign actually took.

### When an EBIOS RM study exists, rank by risk level — it is the exogenous bound input-exposure isn't
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: connecting `ebios-risk-manager` to frama-c-launch (the exogenous-U wiring)
- Heuristic: an EBIOS RM study ranks **supporting assets** by **risk level = severity (W1) ×
  likelihood (W4)**, authored from threats/missions rather than the code — exactly the exogenous
  bound the input-exposure heuristic lacks. Join supporting assets → translation units and attack
  paths → verification targets through `../templates/ebios-crosswalk.md`, then verify highest-risk
  first. A high-severity supporting asset the scope map marks BLOCKED is a **flagged residual risk**
  (citable to its EBIOS scenario ID), never a silent drop. Caveat: this is only exogenous if the
  EBIOS W1–W3 were authored **without reading the implementation** — if the same actor read the code
  to build both the scenarios and the scope map, the bound is endogenous in disguise → flag it.

### BLOCKED is a first-class deliverable — name the reason, never fake or fail on it
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: mbedtls (crypto submodule, TLS state machines, syscalls)
- Heuristic: WP cannot reach inline asm, syscalls/IO, concurrency, function-pointer dispatch WP
  can't model, or weak-float code. Mark these **BLOCKED with the reason** in the scope map; the
  downstream loop concentrates on the amenable set and *records* the rest. Recording out-of-reach
  is part of the onboarding, not a failure — and it pre-empts the downstream loop wasting budget
  on, or faking, what WP cannot model.

### Functional scope claims read off the code are ENDOGENOUS — mark them self-consistency
- Kind: ignore-signal
- Gate S: CARVE-OUT
- Arose from: sl-monitoring-sl (target 3) applied to the Phase-0 audit
- Heuristic: it is tempting to treat the audit's extracted *functional* claims ("these parsers
  bounds-check", "this allocator never aliases") as a sound upper bound. **Exception: a claim read
  off the implementation is endogenous → it is a self-consistency check, not conformance.** Mark
  such claims as endogenous in the scope map; only **exogenous** safety/robustness properties
  (no overflow/OOB/div-by-zero for *any* input, via `-wp-rte` — universal, not read off the code)
  are sound onboarding targets unless a `framac-gold/` or external requirement is also supplied.
- Remedy (ranking): the **attack-surface ranking** has the same endogeneity when read off the code.
  Supply an **EBIOS RM** study as the exogenous bound and rank by its risk level (see the entry above
  + `../templates/ebios-crosswalk.md`) — provided the EBIOS scenarios were authored independently of
  the code, that converts the ranking from self-consistency to a threat-grounded judgment.
