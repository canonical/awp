# macsl context vocabulary under-surfaced — the move-set was a fraction of the tool's

- **Trigger:** after the `/time-loop kernel/bpf` campaign (2026-06-27/28), a user asked "how could
  macsl enlarge the HAPPY properties it covers?" Reading `macsl/src/macsl.ml` showed the
  `context` type + `run_policy` dispatch already **implement ~13 contexts** — `\authorized` (EoP),
  `\noninterference`/`\reading` (confidentiality), `\fuel` (bounded-work), `\guarded_by`/`\stable_check`
  (concurrency), `\tamper_evident`, `\flow`, `\ni_cost` — each wired parser→dispatch→visitor/emit,
  non-stub. **Every kernel campaign to date drove only `\writing` and `\total`.** A grep across all
  skills found **no skill named `\authorized` at all**, and six skills each named a *different partial
  subset* of the rest.

- **Why that was a coherent-and-wrong (the producer's move-set under-enumerated):** this is the
  sl-builder Group-4 failure turned on our own skills — "a producer told to discharge work by a fixed
  list will handle exactly those and dump the rest." The Plane-H move-set the skills surfaced was
  `{\writing, \total}` (+ `\fuel`/`\guarded_by` only as WP *carve-outs*), so every authorization gate
  (`bpf_token_capable`, the security/ LSM hooks) was **hand-rolled as a WP postcondition** — not because
  `\authorized` couldn't express it, but because the skills never told anyone `\authorized` existed. The
  result reads as plane-coverage while a first-class authorization/confidentiality mechanism sat unused.

- **Root cause = drift with no source of truth.** The tool grew (WS1/WS3/WS4/WS6/WS7); nothing
  reconciled the skills' context list against the tool's `context` type, so the skills silently went
  stale and diverged from each other.

- **The fixes (Phases 0–2 landed):**
  1. **Tool is the source of truth.** Added `-macsl-list-contexts` to `macsl.ml` (prints token |
     mechanism | obligation for every context, from `contexts_doc` next to the dispatch). Downstream
     consumes the tool, not a hand-kept list.
  2. **One canonical catalog** — `config/skills/frama-c-api/references/macsl-contexts.md` (token,
     mechanism, obligation, STRIDE row, **honest kernel-maturity** column: exercised vs latent). Every
     other skill **links** it instead of re-listing.
  3. **Driver skills fixed.** `time-loop/SKILL.md` §0 now has the **"pick the context the threat-row
     names — macsl has ~13, not 2"** rule, with the explicit EoP→`\authorized` /
     info-leak→`\noninterference` mapping and **"a hand-rolled WP postcond for an authorization gate is a
     SMELL when `\authorized` applies."** `rmf-sl/references/stride-families.md` now tags each WS family
     with its `\context` token and splits WS3 into the `\authorized`-provable authorization decision vs
     the crypto-identity residual.
  4. **Anti-drift canary** — `frama-c-monitoring/canaries/macsl-contexts-sync.sh` fails when the tool's
     context set and the catalog disagree, so a new tool context forces a catalog update in the same
     change.

- **General lesson (beyond macsl):** when a skill *drives a tool*, the skill's enumerated capability
  list is a move-set that silently caps what gets attempted. Tie it to the tool as source of truth
  (a `-list-*` flag + a sync canary), keep a maturity column honest, and never let "the familiar two"
  stand in for "the menu." Validation that the fix took: an agent running the updated skills should
  reach for `\authorized`/`\noninterference` unprompted (the `happy-kernel.md` probe is that test).
