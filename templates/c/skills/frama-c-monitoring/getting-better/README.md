# getting-better/ — feature suggestions

One `*.md` per **feature suggestion** that would make C/C++ units easier to verify with
Frama-C/WP — a missing WP/ACSL capability, a useful lemma or invariant template, a tooling
improvement. Filed by any `frama-c-monitoring` / `framac-sl` agent when it hits a
limitation, and **confirmed by the base-SL monitor against `L`** (the gap is real:
`framac-sl` genuinely could not express or discharge the thing). A surprise is *routed
here, never absorbed* with a silent local workaround.

**Filename:** `YYYYMMDD-hhmm-simple-name.md` — e.g. `20260618-1530-wp-array-lemma-template.md`.

**Each file should state:**
- **Trigger** — the unit / `gap-N` / mission that surfaced it.
- **Observed** — what Frama-C/WP currently does (or can't do).
- **Desired** — the capability that would make verification easier/more thorough.
- **Minimal example** — the smallest C + ACSL that shows the gap.
- **Guidance link** — the `U` clause it serves (e.g. "specify thoroughly").

## Filed
- `20260619-1600-wp-typed-model-fresh-allocation-unimplemented.md` — WP Typed/+cast model drops
  `\fresh`/allocation; caps `assigns`/separation goals over freshly-`calloc`'d linked structures
  (mbedtls `x509_get_name`; RTE-safety still provable). Confirmed against `L`.
- `20260619-1601-wp-cast-model-malloc-frame-defect.md` — `-wp-model +cast` drops the malloc-frame
  relation across a call through a cast pointer → false-as-generated `assigns`/`requires` VCs on
  `void*`-callback code (mbedtls `ssl_ticket_parse`, `net_recv`); `Caveat` proves but is vacuous.
