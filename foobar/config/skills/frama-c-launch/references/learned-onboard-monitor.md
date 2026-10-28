# Learned knowledge — Onboarding monitor (frama-c-launch)

Append-only, Gate-S-gated heuristics the **onboarding monitor** capitalized while squeezing the
prep work against the shipped profile + the attack surface (see this skill's `SKILL.md` §5, §6).
Each entry passed an `sl-monitoring-sl` Gate S audit by a disjoint monitor (or a human) and
carries provenance.

**Scope / barrier:** how to *catch* a coherent-and-wrong onboarding from a base the producer does
not hold — the wrong-but-parsing config, the silent attack-surface miss, the wrong faithfulness
baseline, the endogenous scope. Record audit *tells* only — never the prober's/architect's
rationale (the monitor judges artifacts against `U`/`L`, never the producer's account). Run the
prep as **sub-agents**; the delegation boundary is the barrier.

**Entry format:**
```
### <title>
- Check kind: conservative-transformation | trigger-test | completeness-critic | endogenous-U-flag
- Gate S: PASS | CARVE-OUT
- Arose from: <target / gap-N>
- Tell: <what the catch looks like and how to run it>
```

## Entries

### Faithfulness baseline must be checked per OWNING repo — a submodule file falsely passes against the parent
- Check kind: conservative-transformation
- Gate S: PASS
- Arose from: mbedtls (`asn1parse.c` lives in the `tf-psa-crypto` submodule)
- Tell: the highest-value onboarding catch. When the target vendors code in submodules, a file's
  pristine baseline is **its submodule's HEAD**, not the parent clone's. A `strip-ACSL == git HEAD`
  check run in the *parent* repo **falsely PASSES** while the submodule file was edited — every
  downstream faithfulness gate is then vacuous. Run the round-trip in each file's **owning repo**
  (`git -C <submodule> diff`); pin the baseline commit per repo. An onboarding script that diffs
  one repo misses this — it is exactly why onboarding is a squeeze, not a script.

### Wrong-but-parsing config: trigger-test the feature profile, not just the parse
- Check kind: trigger-test
- Gate S: PASS
- Arose from: frama-c-launch design (the dominant coherent-and-wrong)
- Tell: the prober's flag-set is an ignore-signal artifact — it "ignores" the profile signal once
  the parse oracle is green. Perturb the defines to the **shipped/named profile** and check whether
  the **compiled paths / feature set differ** (e.g. a `#define` that switches an entire parser
  family on/off). If they differ, the parse-green flag-set is the wrong program → CARVE-OUT (defer
  to the profile clause in the guidance/build docs) or REJECT. The parse oracle alone cannot catch
  this — both configs parse.

### Completeness critic over the scope map — what attack-surface module is missing?
- Check kind: completeness-critic
- Gate S: PASS
- Arose from: sl-monitoring-sl (target 2: audit the triage against ground truth)
- Tell: the architect's scope map is an ignore-signal triage ("these units are out of scope") that
  can silently drop real attack surface. Diff it against the **documented** untrusted-input surface
  (and a `framac-gold/` if present): any parser/boundary module the map omits is a systematic miss,
  not noise. For a **repeated heterogeneous-onboarding suite**, run the critic **cross-provider**
  (extreme-case decorrelation — reasoners need large `num_predict`; instruct models are the
  workhorses; see `../../frama-c-monitoring/references/wp-gotchas.md`). Carve the scope rule to
  honor the missed module, accepting the wider downstream fan-out.

### A unit that PARSES is not a unit that PROVES — never let the parse oracle stand in for the smoke proof
- Check kind: endogenous-U-flag
- Gate S: PASS
- Arose from: frama-c-launch design (no-blend at the launch level)
- Tell: Gate B_launch requires an actual **smoke proof** (≥1 leaf unit WP all-`Valid`), not merely
  "the queue parses." A green parse oracle proves the flags are right, not that the WP→(SMT|Coq)
  pipeline composes on this target. If the smoke unit needs Coq, the smoke proof also exercises the
  `framac-coq8` path (a stronger feasibility gate). Refuse a handoff whose only evidence is parsing.
