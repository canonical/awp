# Learned knowledge — Build/toolchain prober (frama-c-launch)

Append-only, Gate-S-gated heuristics the **prober** capitalized while onboarding codebases for
the Frama-C loops (see this skill's `SKILL.md` §4–§5). Each entry passed an `sl-monitoring-sl`
Gate S audit by a disjoint monitor and carries provenance.

**Scope / barrier:** how to derive a target's Frama-C **preprocess context** — the buildsystem →
`compile_commands.json`/`-cpp-extra-args`, the **feature defines for the chosen profile**,
force-includes, `-machdep`, and the parse-oracle tells. Record build/flag knowledge only — no
specs, no proof scaffolding, no scope rankings. Future onboardings load this at delegation time.

**Entry format:**
```
### <title>
- Kind: ignore-signal | defer-to-oracle
- Gate S: PASS | CARVE-OUT
- Arose from: <target / gap-N>
- Heuristic: <rule>
- Carve-out: <exception → build-doc/guidance clause>   (if any)
```

## Entries

### Init submodules before anything — a bare clone often won't preprocess
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: mbedtls 4.1.0 onboarding
- Heuristic: many real targets vendor code in git submodules; a bare clone is missing the headers
  and **nothing preprocesses** (mbedtls: `tf_psa_crypto_platform_requirements.h: No such file`).
  `git submodule update --init --recursive` is the binding precondition — run it (in `setup.sh`)
  before the parse oracle. The parse oracle (frama-c parses the file) confirms it worked.

### Discover flags per profile, then prove them with the parse oracle — never assume
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: mbedtls (two flag sets) / StandardAlgorithms (force-includes)
- Heuristic: each C TU needs its own `-I`/`-D` to parse; get them from `compile_commands.json`
  (`bear -- make`, CMake `-DCMAKE_EXPORT_COMPILE_COMMANDS=ON`) or hand-build. Recurring shapes:
  (1) a **minimal** include set for leaf parsers vs a **full cascade** set for units pulling a
  mega-header (mbedtls: `PARSER` vs `FULL` via `ssl_misc.h`); (2) a mandatory config define
  (`-DMBEDTLS_CONFIG_FILE='<…>'`) and a platform define (`-DMBEDTLS_PLATFORM_IS_UNIXLIKE`).
  Validate every flag set with the **parse oracle**; a bare `-I` is rejected — wrap in
  `-cpp-extra-args="…"`. A unit that won't parse is a prober gap (wrong flags), not a unit FAILED.

### Force-includes restore type chains stripped by ACSL/overlay prep — without editing source
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: StandardAlgorithms corpus prep
- Heuristic: when the overlay/prep removed an include chain a unit relied on for typedefs, the
  parser emits `unexpected token` / `unbound logic function` and **silently drops the annotation**
  (reads as a benign "ignoring" warning). Restore the types with `-cpp-extra-args="-include
  typedefs.h …"` — a preprocessor force-include, so the body stays byte-identical and the
  faithfulness baseline still round-trips. Scan parse output for "ignoring"/`unbound` as a tell.

### The profile signal is load-bearing — "it parses" is NOT enough (high-risk)
- Kind: ignore-signal
- Gate S: CARVE-OUT
- Arose from: frama-c-launch design (the dominant coherent-and-wrong)
- Heuristic: it is tempting to treat the **feature profile as noise** once the parse oracle is
  green — any `#define` set that compiles looks fine. **Exception: defer to the shipped/named
  profile (U).** A config that parses but selects a different feature set than the target
  ships/deploys makes the downstream loop prove dead or wrong code paths. Pick the defines from
  the mission's named profile / `configure` defaults / `user_settings.h`, and let the onboarding
  monitor's trigger test confirm the compiled paths match. The parse oracle cannot catch this —
  both configs parse.

### Frama-C "Ignoring unknown attribute" is benign — not a dropped ACSL annotation
- Kind: ignore-signal
- Gate S: PROVISIONAL (seed — confirm via Gate S on next use)
- Arose from: wolfssl onboarding (parse-oracle false positive — all 4 sample units flagged)
- Heuristic: frama-c's kernel prints `[kernel:unknown-attribute] Ignoring unknown attribute: <x>`
  for GCC attributes it doesn't model (e.g. `mode`, ubiquitous in portable C like wolfssl's
  `types.h`). It is **harmless** — the file parses (exit 0), no ACSL is dropped. The parse oracle
  must NOT read a bare `ignoring`/`dropping` as a dropped-annotation signal; restrict the dropped-ACSL
  tell to annotation-specific messages (`unbound logic`, `annot-error`, `ignoring/dropping (the)
  annotation`, `unexpected token`) and gate PARSE-FAIL on frama-c's **exit code**. Otherwise every
  attribute-using TU reads as a false DEPENDENCY-UNMET (fixed in `bin/framac-onboard.sh`).

### Pin -machdep; record -wp-fct / -wp-model +cast as queue flags, not failures
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: mbedtls (net/ssl units)
- Heuristic: fix `-machdep` (e.g. `gcc_x86_64`) — `sizeof`/widths/overflow bounds depend on it and
  a mismatch flips RTE goals downstream. Two recurring per-unit scoping flags belong in the queue,
  not the FAILED column: `-wp-fct <fn>` when a header (e.g. frama-c's own `sys/socket.h`
  `assigns …(0..)`) aborts whole-file WP, and `-wp-model +cast` for `void*`-callback code. Confirm
  the Coq path (`framac-coq8`) at onboarding since byte parsers recur into bitmask SMT-incompleteness.

### opam installation — use the official installer script, not the system package
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: grub2-2.12 campaign (2026-07-07); opam 2.1.5 was the system default, uninitialized
- Heuristic: the system opam (`/usr/bin/opam` on Ubuntu 24.04 noble) may be an OLD version
  (2.1.5) and is typically **uninitialized** (`opam init` not run). The canonical fix is the
  official installer: `curl -fsSL https://opam.ocaml.org/install.sh | bash -s -- --version 2.5.1`
  — it detects that `sudo` is available and installs opam 2.5.1 to `/usr/bin` automatically
  (backs up the old binary as `opam.2.1.5`). **Do NOT prompt interactively** — `bash -s` (not
  `sh <(curl …)`) prevents the "where should it be installed?" prompt from stalling. After install,
  `opam init --no-setup --bare -y` then `opam switch create framac-coq8 ocaml-base-compiler.4.14.2`.
  Confirmed working recipe, grub2-2.12 2026-07.

### Frama-C 32.1 (Germanium) IS now in the public opam repo — `opam install frama-c` gives 32.1
- Kind: ignore-signal (update to SKILL.md claim)
- Gate S: PASS
- Arose from: grub2-2.12 campaign (2026-07-07)
- Heuristic: SKILL.md §0 says "Frama-C 32.1 is NOT in the public opam repo (tops out at 31.0)".
  **This is now STALE** — `opam show frama-c` reports `version: 32.1` in the default opam repo as
  of 2026-07. `opam install frama-c -y --switch=framac-coq8 --assume-depexts` installs 32.1
  (Germanium) directly. The `framac-src` source-build path is no longer needed (but the
  build-from-source recipe in SKILL.md remains valid as a fallback for air-gapped environments).
  Always verify the installed version with `frama-c -version` before trusting the campaign.

### opam frama-c install needs GUI system deps — install them with apt before opam install
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: grub2-2.12 campaign (2026-07-07); `conf-gtk3`, `conf-gtksourceview3`, `conf-graphviz` failed
- Heuristic: `opam install frama-c` pulls in Ivette (the GUI) which needs three system packages.
  Install them BEFORE running `opam install frama-c`:
  ```
  sudo apt-get install -y libgtk-3-dev libgraphviz-dev libgtksourceview-3.0-dev
  ```
  Then re-run `opam install frama-c -y --switch=framac-coq8 --assume-depexts`. Without
  `--assume-depexts` opam prompts interactively and aborts on a non-interactive terminal.
  **Note:** these are GUI deps for Ivette only — they do NOT affect WP/CLI correctness. If you
  cannot install them (no sudo), you can pin frama-c without ivette:
  `opam install frama-c --ignore-constraints-on=conf-gtk3,conf-gtksourceview3,conf-graphviz`
  (experimental; test with `frama-c -wp-detect`).

### opam Coq install now gives Rocq 9.x — the framac-coq8 Coq-escalation path may break
- Kind: defer-to-oracle
- Gate S: CARVE-OUT
- Arose from: grub2-2.12 campaign (2026-07-07)
- Heuristic: `opam install coq` now installs **Coq 9.1.1 (Rocq)**, NOT 8.20.1. The SKILL.md and
  `wp-gotchas.md` specify `framac-coq8 switch (Coq 8.20.1, not Rocq 9.x)` because the Coq WP
  realizations (Why3's `BuiltIn.vo`) were compiled for 8.x. With Rocq 9.x installed, `why3 config
  detect` registers it, but the Why3 Coq libraries may not load under `-wp-prover coq` — the
  `"Coq found but no Why3 libraries compiled for it"` warning from SKILL.md §0 is the tell.
  **SMT-only (alt-ergo + z3) still works** and covers the vast majority of RTE goals. The Coq
  escalation path (for bitmask/induction residues) is degraded until the Why3 Coq realizations
  are rebuilt for Rocq 9.x or a Coq 8.20.1 pin is used. Record this as a `getting-better/` item
  when it blocks a campaign.
  Carve-out: if Coq escalation is critical for the campaign, pin Coq 8.20.1 explicitly:
  `opam install "coq=8.20.1" -y --switch=framac-coq8` (check availability first with
  `opam show coq --field=all-versions`).

### Full opam install sequence for framac-coq8 (2026-07 confirmed working recipe)
- Kind: defer-to-oracle
- Gate S: PASS
- Arose from: grub2-2.12 campaign (2026-07-07); replaces the stale SKILL.md §0 recipe
- Heuristic:
  ```bash
  # 0. Install opam 2.5.1 (if absent or old)
  curl -fsSL https://opam.ocaml.org/install.sh | bash -s -- --version 2.5.1
  opam init --no-setup --bare -y

  # 1. Create switch
  opam switch create framac-coq8 ocaml-base-compiler.4.14.2 -y

  # 2. Coq first (load-bearing order for Why3 realizations)
  eval $(opam env --switch=framac-coq8 --set-switch)
  opam install coq -y --switch=framac-coq8  # gives Rocq 9.x today; see Coq note above

  # 3. Why3 + Alt-Ergo (Why3 builds Coq realizations while Coq is present)
  opam install why3 alt-ergo -y --switch=framac-coq8
  why3 config detect   # must list Alt-Ergo + Z3 (system z3 auto-found)

  # 4. Install GUI system deps (needed by frama-c's ivette component)
  sudo apt-get install -y libgtk-3-dev libgraphviz-dev libgtksourceview-3.0-dev

  # 5. Install Frama-C 32.1 (now in public opam repo)
  opam install frama-c -y --switch=framac-coq8 --assume-depexts

  # 6. Gate check
  opam exec --switch=framac-coq8 -- frama-c -version    # → 32.1 (Germanium)
  opam exec --switch=framac-coq8 -- frama-c -wp-detect  # → Alt-Ergo 2.6.3, Z3 4.8.12
  ```
  Total wall time on a fresh Ubuntu 24.04 container: ~15–25 min depending on network speed.
