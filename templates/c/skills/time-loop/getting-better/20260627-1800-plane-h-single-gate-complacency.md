# Plane-H single-gate complacency — one HAPPY gate ≠ plane covered (worked example)

- **Trigger:** the `/time-loop musl-1.2.5 6` campaign, 2026-06-27. Drove ONE Plane-H gate
  (`secure_getenv`, macsl HAPPY `secure_env_gate`, in-situ + non-vacuous) and then treated
  Plane H as exhausted, **skipping a second distinct gate** (`locale_map` / `__get_locale`'s
  `MUSL_LOCPATH` env-trust gate) with the self-judgment "low marginal value / complex-TU RTE."
- **Why that was a coherent-and-wrong (now (h)):** the skip was a coordinator *value
  self-judgment* parking in-scope authorization coverage — the intra-plane form of
  plane-blindness (d). I even *found* the discriminator that proves the gate is **distinct, not
  redundant**: `catopen`/`locale_map` read benign env (`getenv("LANG")`, `LC_ALL`) **even when
  secure**, so a single shared `getenv`-targeted policy *fails* on those sites. By the FAIL-test,
  `MUSL_LOCPATH` (locale-file load from an env path) is a different sensitive resource → its own
  deliverable. "Distinct authorization gate" is high-value by definition and is **not** subject to
  the (b) budget-burning cut.
- **The two skill gaps that permitted it (now fixed in SKILL.md):**
  1. The coherent-and-wrong list had plane-blindness only *inter*-plane; no rule against
     "one gate done → plane done." → added **(h) SINGLE-GATE COMPLACENCY** + the **Plane-H
     gate-completeness** clause (§0) + the **gate-enumeration Gate-C/Gate-S closure condition**.
  2. "Complex host RTE" was wrongly usable as a skip reason. → standing-gate-set item 6 now states
     **a gate's "done" = the macsl `..._meta` assertion discharges + its attack flips — NOT the host
     function's full Plane-W RTE**; the surrounding RTE is a *separate* Plane-W residue.
- **The mechanism the fix mandates:** enumerate gates by tracing the integrity/authority flag
  (`grep -rn 'libc.secure'`) to its use-sites; each distinct guarded resource = one gate; **target
  the sensitive OPERATION** (here `__map_file`), not a shared primitive (`getenv`) that also serves
  benign reads. Drive each to WITNESSED-in-situ or a probe-classified residue before the terminus.
- **Guidance link:** §0 "Plane-H gate-completeness"; Gate C / Gate S gate-enumeration closure;
  coherent-and-wrong (h). Worked closure of this exact miss: the `locale_map` `__map_file` gate,
  driven in `musl-1.2.5-analysis-acsl/` (verdicts.tsv, attacks/).
