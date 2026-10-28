# Report/ledger drift — the summary silently contradicted the source-of-truth ledger (worked example)

- **Trigger:** the `/time-loop linux-7.1.3 10 --linux` campaign, 2026-07-18. The user asked two
  pointed questions: "Where are the 3 flagged latent hazards? The interim report only has 2. Where is
  the Plane-W untrusted-buflen OOB-write confinement on the keyctl(KEYCTL_READ) path?" Both landed:
  - The interim report's flagged-hazards section listed **2** (`aa_map_resource`,
    `evm_read_protected_xattrs`), while `verdicts.tsv` (the source of truth) recorded a **3rd** — the
    landlock `unmask_layers` `level ∈ [1,16]` caller-maintained cross-function invariant, flagged in
    cycle-110. The report headline even still said "2 flagged."
  - The cycle-132 keys `keyring_read_iterator` KEYCTL_READ OOB-write unit was in `verdicts.tsv` and the
    state file, but **absent from the interim report**.
- **Why that was a coherent-and-wrong (bookkeeping drift):** the interim/summary report was last
  comprehensively refreshed at cycle-100; from then on I only `sed`-bumped the `+N`-units headline each
  cycle and did **not** propagate per-cycle deltas (new flagged hazards, new units/areas, monitor
  corrections, duplicate-rejections) into the report's prose. So the DERIVED view silently drifted from
  the SOURCE OF TRUTH. My own running standing-summary said "3 flagged hazards" (correct vs the ledger)
  while the shipped report said "2" — an internal contradiction a reader (the user) caught immediately.
  Hand-maintaining a count in two places is the drift vector.
- **Root cause:** no gate tied the summary report's counts to the ledger. `verdicts.tsv` was authored
  additively and correctly every cycle; the report was hand-bumped on one axis (headline) only.
- **The fix (now in SKILL.md):**
  1. **§4 step 5 → new Gate R (REPORT/LEDGER RECONCILIATION, push-blocking).** `verdicts.tsv` is the
     single source of truth; any interim/summary report is a DERIVED view, re-derived-and-verified every
     cycle. For EVERY per-cycle ledger item (new WITNESSED unit, flagged hazard, self-overturn,
     monitor-correction/duplicate-rejection, class-A ceiling, lever, subsystem area) the report section
     is updated **in the same commit** — additively, not just the headline. Before `git push`, every
     count the report asserts MUST equal its `grep -c` count from `verdicts.tsv`; a mismatch is a
     push-blocking REJECT. Prefer a **regenerated** summary (counts computed by `grep`/`awk`) over a
     hand-edited one.
  2. **Standing-gate-set item 1 (Monotone coverage)** now states the source-of-truth/derived-view rule
     and points to Gate R.
  3. **§7 Stabilizers** gained a **Report/ledger reconciliation (Gate R, anti-drift)** bullet.
- **Bonus sub-case folded in (same cycle, cycle-130):** a verifier sub-agent re-proposed an
  already-witnessed function (`device_cgroup verify_new_ex`) under a **different filename prefix**
  (`device_cgroup_` vs the earlier `devcgroup_`), so its filename-based dedup missed it. The disjoint
  monitor caught the duplicate, reverted it, and did not double-count. Gate R + the dedup rule now say:
  **dedup by function NAME (`grep -icE '\bFN\b' verdicts.tsv`), never by unit filename.**
- **Takeaway:** a summary/report is only as trustworthy as its last reconciliation with the machine
  ledger. If a number lives in two places, one of them must be *computed*, and the computation must run
  before every push — otherwise the human reader becomes the drift detector, which is exactly the
  monitor's job to pre-empt.

## Follow-up hardenings (same campaign, later cycles) — the generator's own edge cases

The mechanical generator (Gate R) removed *headline* drift, but two of its own parsing
edge-cases surfaced as near-misses and are now fixed:

1. **Phantom-area col1 (cycle-148).** A verdict row whose col1 used the *unit-copy* path
   (`units/commoncap_rootid_from_xattr.c`) instead of the pristine source filename
   (`commoncap.c`) made `subsystem_of()` mint a spurious `"units"` area and hid the row
   from `commoncap`. Fix: `subsystem_of()` now **refuses** a `units/`-prefixed col1 loudly
   (raises), and the ledger convention is reaffirmed: **col1 = pristine source path**, never
   the `units/` overlay path.

2. **Negated colon-marker miscount (cycle-153).** The flagged-hazard detector keys on the
   positive `FLAGGED LATENT HAZARD:` (colon) marker and excludes negated mentions. The
   exclusion was case-sensitive (`[Nn]o`), so a NON-hazard row that wrote "**NO** FLAGGED
   LATENT HAZARD:" (uppercase, colon form) was **counted as a hazard** (7 vs the true 6).
   Two-part fix: (a) discipline — a non-hazard row must NOT use the `HAZARD:` colon form at
   all (write "correctly NO hazard flag (...)"; the colon marker is reserved for genuine
   flags); (b) defense-in-depth — the generator's negation exclusion is now
   case-insensitive and also matches "not": `(?i)\b(no|not)\b[^.\t]{0,40}FLAGGED LATENT`.
   Verified it still counts the genuine smack `smk_parse_long_rule` flag (whose "no lever"
   is separated from "FLAGGED LATENT" by a sentence period, outside the 40-char window).

**Meta-takeaway:** a *mechanical* derived-view still has a parser, and the parser has its own
silent-miscount modes. Each cycle's regenerate-and-diff caught these because the count moved
against the monitor's independent expectation — so the load-bearing habit is not just "run the
generator" but "regenerate AND sanity-check the delta against what this cycle actually changed."

## Dedup sub-case #2 (cycle-163) — a helper proven inside a multi-function unit

A verifier sub-agent proposed `skipn_spaces` (apparmor/lib.c) and claimed both `grep verdicts.tsv`=0
AND `grep units-faithfulness.tsv`=0. The first was true; the second was FALSE. `skipn_spaces` was
already proven in a committed unit `apparmor_lib.c` that verifies TWO functions
(`skipn_spaces,aa_splitn_fqname`) — its manifest row lists both, but its verdicts.tsv coverage is
recorded under the MAIN function, so a verdicts.tsv-only grep for the helper name returns 0. The monitor
caught the duplicate via the faithfulness gate printing the `skipn_spaces` row twice. **Rule sharpened:
the sub-agent dedup MUST grep BOTH `verdicts.tsv` AND `units-faithfulness.tsv` by function name — the
manifest is the authoritative record of every faithfulness-gated function, including helpers bundled in a
multi-function unit that never got their own ledger row.** (Cousin of the cycle-130 filename-duplicate:
same function, different filename; here same function, a multi-fn sibling unit.)
