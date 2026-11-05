---
name: frama-c-launch
description: >-
  A top-level Squeeze Loop that ONBOARDS a heterogeneous C/C++ codebase for
  Frama-C verification and hands a validated "onboarding package" to the
  frama-c-monitoring loop (which it sits on top of). Given a mission like
  "onboard the library xxx in directory yyy for verification", it derives the
  per-unit preprocessing context (configure/build -> compile_commands.json or a
  hand-built -cpp-extra-args + feature defines + force-includes + -machdep),
  confirms the toolchain (frama-c -wp-detect + the framac-coq8 opam switch) — installing/building it from
  source into the switch when absent (§0 recipe: provers via opam + `why3 config detect`, frama-c 32.1 via
  `dune build @install`, macsl),
  runs/owns the Phase-0 architectural audit (the WP-amenability scope map + the
  attack-surface ranking), scaffolds the durable <target>-acsl/ overlay (the
  setup.sh/verify.sh/patches/harness/sessions layout, with the faithfulness
  baseline pinned to the right pristine commit), and proves ONE leaf unit
  end-to-end as a feasibility smoke proof. It is itself a squeeze loop MONITORING
  the prep work (sl-monitoring-sl): a disjoint onboarding-monitor squeezes the
  prober's flag-set and the architect's scope map against the SHIPPED build
  configuration and the real attack surface, catching the coherent-and-wrong an
  onboarding script cannot — a config that parses but selects the wrong feature
  set, a scope map that silently drops an attack-surface module, or a
  faithfulness baseline pinned to the wrong commit/submodule. Use to set up a NEW
  codebase for the frama-c-monitoring/framac-sl loops, to discover a target's
  Frama-C build flags, to run the Phase-0 scope/attack-surface audit, to scaffold
  a <target>-acsl/ overlay, or when onboarding many heterogeneous codebases
  repeatedly and the build/scope/baseline judgment needs disjoint cross-checking.
---

# frama-c-launch — a Squeeze Loop that onboards a codebase for `frama-c-monitoring`

`frama-c-launch` is the **launch / onboarding** loop. It sits **on top of**
`frama-c-monitoring` (`../frama-c-monitoring/SKILL.md`): it prepares a heterogeneous
C/C++ target and emits a validated **onboarding package** that `frama-c-monitoring`
consumes at its Phase-0/Gate-A_top, then `frama-c-monitoring` drives `framac-sl`
per unit. It is built with the `sl-builder` methodology and monitored with the
`sl-monitoring-sl` meta-pattern. Run it **unsupervised or interactively**; the
onboarding monitor runs the prep agents as **sub-agents** (the delegation boundary
is the barrier — the monitor sees only returned onboarding artifacts, never a prober's
rationale).

> Drafted with `sl-builder`; monitoring discipline from `sl-monitoring-sl`. Slots the
> mission did not fix are marked `ASSUMPTION:`; run the C1/C2 checks before trusting an
> instance. Downstream loop: `frama-c-monitoring`; base ACSL reference: `frama-c`.

## When to run this loop — repeated / heterogeneous onboarding, NOT a one-off build
The onboarding squeeze is *assurance machinery for the SETUP*, not a build script. Its cost
(≈4 prep roles + the disjoint monitor) is justified **only** when a wrong-but-plausible
onboarding is expensive — and it is, because a bad onboarding **silently corrupts the entire
downstream verification campaign** (you prove the wrong program, or under-cover the attack
surface, or rest every faithfulness check on the wrong baseline). That payoff is real when
(a) you onboard **many heterogeneous codebases repeatedly** (each new build/config maze can be
plausibly-but-wrongly set up — the user's stated case); (b) the target's feature configuration
is non-trivial (`#ifdef`/`configure`/`user_settings.h` mazes, submodules, callback conventions);
and (c) the verification must be trusted without re-auditing the setup by hand. **For a single,
well-understood target with an obvious build, a plain onboarding *script* (`bin/framac-onboard.sh`)
is the right call — skip the squeeze.** Reach for the full loop deliberately.

## 0. Mission & deliverable
- **Mission shape:** `onboard the library <xxx> in directory <yyy> for verification` +
  **guidance** (the upper bound — §1): which **deployment/feature profile** to verify (the
  as-shipped config, a named build profile, or a specific `user_settings.h`), which subsystems
  are in scope, and the verification target the downstream loop will pursue (e.g. RTE-robustness
  on the untrusted-input parsers).
- **Deliverable — the onboarding package** (the handoff contract; template in
  `templates/onboarding-package.md`):
  1. **Preprocess context** — `compile_commands.json` *or* a per-unit `{file, flags}` queue with
     the `-cpp-extra-args` set (`-I`/`-D` + the **feature defines for the chosen profile** +
     force-includes) and the `-machdep`. **This MUST be derived from a real compilation of the
     target for the chosen profile** — an actual `configure`/CMake/`make`/`west build` run that
     emits `compile_commands.json` and the **build-generated headers** (syscall tables, `autoconf.h`,
     devicetree, version, offsets, …). Hand-synthesised flags / hand-written stand-in headers / a
     guessed config are NOT a substitute: a unit whose generated dependencies were never produced is
     *not* onboarded, it is **un-built**, and the loop **fails** rather than recording it BLOCKED and
     falling back to a lifted leaf driver (see the build oracle in §1 and Gate B_launch in §4).
     - **`-machdep` override — the one preprocess value the caller may PIN (`--machdep=<name>` via `/rmf`).**
       When `/rmf` forwards `--machdep=<name>`, pin `-machdep` to it for the campaign (record it in the
       onboarding package and the generated `verify.sh`; do **not** re-derive it from the build). This is
       the sanctioned override for **cross/embedded** targets Frama-C has no exact machdep for: `<name>`
       must be one `frama-c -machdep help` lists, and the ABI-faithful proxies are **`gcc_x86_32` for
       32-bit ARM** (Cortex-M / Zephyr `mps2_an385`: ILP32, 4/4/4 int/long/ptr, little-endian) and
       **`macos_arm` for AArch64** (LP64). Only the width/alignment model is pinned — the `-I`/`-D`/
       force-includes + build-generated headers still come from the real compilation (a pinned machdep is
       **not** a licence to skip the real build). With no flag, derive and pin it from the build as today
       (default `gcc_x86_64`).
     - **Memory-model selection is an onboarding decision (this loop's, NOT `frama-c-monitoring`'s).**
       The default is `Typed`. When the target has **cast/region residue** (pointer-cast loads/stores,
       `*(void**)`/`*(char**)`, CONTAINER_OF, intrusive containers) that times out under `Typed`,
       add an **opt-in `-wp-model bytes` SEPARATE-PASS profile** as an onboarding-package amendment: a
       `verify-bytes.sh` sibling that runs the cast-heavy units under `bytes` on the patched dev build
       (the byte model needs `frama-c-patches/0001` — the unknown-size-array sizeof fix — or it aborts;
       see the `frama-c-internals` skill). `Typed` stays the default `verify.sh`; the model is
       **whole-program**, so this is genuinely *per-unit separate passes*, not a per-function flag.
       `frama-c-monitoring` then RUNS the profile and banks verdicts (tag `bytes`-banked vs `Typed`-banked,
       never double-count); it does not change the model itself. Sound opt-in only — never `+cast`
       (vacuity risk). Evidence this pays off: a byte-model pass banks the recast-pointer derefs +
       some byte-range `\valid` that `Typed` severs, but NOT the nonlinear core — and `bytes` is itself
       *less* complete than `Typed` on a few byte-range `\valid`-at-call-site preconditions, so it is a
       **different slice, not a superset**. Scope it honestly.
  2. **Toolchain confirmation** — `frama-c -wp-detect` output + the `framac-coq8` switch present
     (Coq needed for the recurring bitmask/induction residue).
     - **In a workshop with the `frama-c-sdk` SDK (`FRAMA_C_SDK_SWITCH` is set): the SDK IS the
       conformant toolchain — do NOT build.** It is Frama-C 32.1 built from the release archive with
       every `frama-c-patches/` patch applied by `bin/fetch-sources.sh` itself, in a read-only
       `framac-coq8` switch under `/opt/frama-c-sdk` (no opam root of the user's: never run
       `opam switch`/`opam env`; the wrappers `frama-c`, `why3`, `alt-ergo`, `z3` are on `PATH` and
       `frama-c-sdk-exec <cmd>` runs any other command of the switch). Confirm it with the SDK's own
       health checks and record the result as the TOOLCHAIN provenance (`FRAMA_C_SDK_SWITCH`,
       `FRAMA_C_SDK_SRC`, `FRAMA_C_SDK_MACSL`, `frama-c -version`):
       ```sh
       frama-c -version | grep -q '^32\.1'
       frama-c -wp-detect 2>&1 | grep -qi alt-ergo && frama-c -wp-detect 2>&1 | grep -qi z3 \
         && frama-c -wp-detect 2>&1 | grep -qi coq
       grep -q land_le_l "$(frama-c -print-share-path)/wp/why3/frama_c_wp/cbits.mlw"   # patch-liveness
       frama-c -no-autoload-plugins -load-module "$FRAMA_C_SDK_MACSL" -macsl-list-contexts  # Plane H
       ```
       All four pass → toolchain confirmed, skip the rest of this item. `$FRAMA_C_SDK_SRC` is the
       patched source tree (`bin/fetch-sources.sh` links `framac-src` to it) for the skills that read
       Frama-C's source. The build recipe below is for a plain container without the SDK.
     - **MANDATORY — a GIT/SOURCE Frama-C checkout MUST exist and EVERY patch in `frama-c-patches/`
       MUST be applied to it; a plain `opam install frama-c` build is NOT a conformant toolchain.**
       The stock opam binary is missing the local WP/frontend fixes this project depends on
       (`0001-membytes` unknown-size-array sizeof — else `-wp-model bytes` *aborts* on extern/flexible
       arrays; `wp-cbits-bound-lemmas` — the bitwise bound/nilpotence axioms without which `land`/`lor`/
       `lnot` goals reliably fail SMT; `cabs2cil-c23-auto` — the C23 frontend fixes). Running the
       campaign on the unpatched binary means those patches are **inert** and every "class-A bitwise
       ceiling" / "bytes-model abort" verdict is really a *self-inflicted, un-enriched-toolchain*
       artifact (the `frama-c-patches/README.md` + each subdir README are the source of truth). Setup:
       ```sh
       # 1. get a source tree pinned to the switch version (32.1):
       opam source frama-c.32.1 --dir=framac-src          # or use the vendored ./framac-src checkout
       # 2. apply ALL patches (top-level + each subdir has its own apply.sh):
       FRAMAC_SRC=framac-src frama-c-patches/apply.sh                       # 0001-membytes
       FRAMAC_SRC=framac-src frama-c-patches/wp-cbits-bound-lemmas/apply.sh # cbits axioms + Cbits.v realization
       FRAMAC_SRC=framac-src frama-c-patches/cabs2cil-c23-auto/apply.sh     # C23 frontend
       # 3. REBUILD (WP is a dynamic plugin — dune build @install is REQUIRED to relink it):
       cd framac-src && eval $(opam env --switch=framac-coq8 --set-switch) && dune build @install
       ```
       **VERIFY the patches are LIVE, not just present** (the exact trap): `grep -q land_le_l
       framac-src/src/plugins/wp/share/why3/frama_c_wp/cbits.mlw` and confirm the `MemBytes.ml`/
       `cabs2cil.ml` hunks are in the tree; a directly-installed dev binary that crashes
       (`Failure("hd")`) means run it via `dune exec --root framac-src -- frama-c …` instead.
     - **The generated `verify.sh` (and every bare `frama-c` invocation) MUST resolve to the PATCHED
       build, or the toolchain confirmation is vacuous.** Put a PATH shim ahead of the opam binary — a
       `frama-c` wrapper that `exec dune exec --root <framac-src> -- frama-c "$@"` (or point at the
       rebuilt `$PREFIX/bin/frama-c`) — and record which binary is live in the onboarding package's
       TOOLCHAIN provenance. On every **class-A retry** (the ceiling is soft/extensible), re-confirm the
       patched build is the one running — a bitwise/bytes residue re-tested on the stock binary has not
       actually been retried against the enriched toolchain.
     - **Install order is load-bearing: Coq *before* Why3** — the `why3` opam package builds its Coq realizations (the
     `$(why3 --print-libdir)/coq/*.vo` that `-wp-prover coq` inlines) only when Coq is already in
     the switch; verify `BuiltIn.vo` exists there. If a campaign treats coq greens as load-bearing,
     the realization library `coqwp` is the TCB and should be vendored + hardened + CI-gated (the
     `frama-c` skill's `references/coqwp-trust-root.md`; the GitHub-Actions gate runs `coqwp/check.sh`
     and reproduces this Coq-before-Why3 order).
  3. **Scope map + attack-surface ranking** — WP-amenable units vs BLOCKED (asm/syscall/crypto/
     concurrency/float), ranked by input exposure (Phase 0).
  4. **The `<target>-acsl/` overlay scaffold** — `setup.sh`/`verify.sh`/`patches/`/`harness/`/
     `sessions/`/`README.md`/`verdicts.tsv` (mbedtls-acsl layout), with the **faithfulness
     baseline** pinned to the correct pristine commit(s) (clone HEAD, and *each submodule's* HEAD).
  5. **A feasibility smoke proof** — one leaf unit carried to WP all-`Valid` end-to-end, proving
     the Frama-C→WP→(SMT|Coq) pipeline composes on *this* target.
- **Dominant coherent-and-wrong to guard** (the reason this is a squeeze, not a script):
  - **Wrong-but-parsing config.** Flags chosen so WP *parses*, but selecting a different feature
    set than the target ships/deploys → the downstream loop proves dead or wrong code paths. The
    build oracle says "parses" (green) while it is the wrong program.
  - **Silent attack-surface miss.** The scope map omits a parser/boundary module → the whole
    campaign under-covers while *looking* complete.
  - **Wrong faithfulness baseline.** The pristine baseline is pinned to a dirty/patched/wrong
    commit — or, classically, to the **parent repo when the file lives in a submodule** — so every
    downstream `strip-ACSL == git HEAD` check is vacuous.
  - **Endogenous scope.** The scope map's *functional* claims read off the code are
    self-consistency, not conformance (flagged, per `sl-monitoring-sl`).
  - **Smoke-proof skipped.** Onboarding declared ready without proving the pipeline composes →
    `frama-c-monitoring` fails on unit 1.

## 1. Bounds
- **Upper bound `U` (soft, normative):** the onboarding must be **faithful to the shipped/named
  build profile** and **complete over the attack surface**. The citable authority is the target's
  own build documentation + `configure` defaults / the deployment profile the mission names + the
  mission guidance (which subsystems, which config). The strongest claim a prep output may make is
  "a reading the build docs + guidance do not refute." A `framac-gold/` or an external requirement,
  if present, is a second concrete upper bound on scope completeness.
  - **Exogenous risk bound for the ranking (when present): an EBIOS RM study.** The architect's
    attack-surface *ranking* is otherwise read off the code (endogenous — self-consistency, not
    conformance). When an EBIOS Risk Manager study exists (the `ebios-risk-manager` skill), it is the
    **exogenous** upper bound on *what to verify first*: the ranking key becomes the EBIOS **risk
    level** (severity × likelihood) per supporting asset, joined to translation units through
    `templates/ebios-crosswalk.md`. This is the `sl-monitoring-sl` remedy ("supply an exogenous
    bound") for the endogenous ranking. Sound only if the EBIOS scenarios were authored **without
    reading the implementation** (W1–W3); otherwise it is endogenous in disguise — flag and discount.
    Produce it with the **`ebios-sl`** loop (`../ebios-sl/SKILL.md`) — a code-disjoint peer that runs
    *first*, never inside this loop — and consume its report here; that separation is what keeps the
    bound exogenous.
    - **Or a NIST RMF assessment (the equivalent exogenous bound).** Instead of EBIOS, the ranking may
      come from a NIST Risk Management Framework assessment produced by the **`rmf-sl`** loop
      (`../rmf-sl/SKILL.md`, the code-disjoint sibling of `ebios-sl`, grounded in SP 800-30/37/53 +
      STRIDE), joined through `templates/rmf-crosswalk.md`; the verdict→risk return half is
      `references/rmf-feedback.md` (landing on the 800-37 *Monitor* step). Same exogeneity rule: sound
      only if R1–R4 were authored **without reading the implementation**. EBIOS and RMF are
      interchangeable peer sources of the exogenous ranking — use whichever the engagement mandates.
- **Lower bound `L` (executable, ground truth):** the onboarding **oracles**, which no prep actor
  can argue with:
  0. **Build oracle (precedes all others)** — the target **actually compiled** for the chosen
     profile: the build ran (`configure`/CMake/`make`/`west build`) and produced
     `compile_commands.json` + the build-generated headers the units `#include`. The check is
     physical: the generated artifacts exist on disk and the in-scope units appear as real TU
     entries. **If no build was done, the onboarding FAILS here** — it does not proceed to the parse
     oracle on synthesised flags, and it does not record the un-built units as BLOCKED. ("BLOCKED" is
     for units WP cannot reason about — asm/crypto/float — *after* they build; it is never a synonym
     for "I could not build it.") The final ELF need not link (a board-specific link error downstream
     of header generation does not fail this oracle — the generated headers + `compile_commands.json`
     are what onboarding consumes), but the **compile** of the in-scope TUs must have succeeded.
  1. **Parse oracle** — `frama-c [flags] file.c` preprocesses + parses with **no dropped-annotation
     warnings** (`unbound logic function` / "ignoring" reads as benign but means a stripped type
     chain → fix the force-includes), on a representative unit and ideally the whole queue.
  2. **Toolchain oracle** — `frama-c -wp-detect` lists the provers; the `framac-coq8` switch exists
     (in a workshop: the `frama-c-sdk` SDK's, confirmed as in §0 item 2, not an opam root of the user's).
  3. **Faithfulness round-trip** — strip-ACSL == `git HEAD` on the (in-place) clone, **per repo
     and per submodule**; `setup.sh` applies *and reverses* cleanly (`git apply --reverse --check`).
  4. **Smoke proof** — ≥1 leaf unit reaches WP all-`Valid` (the feasibility gate).
  5. **TU-correspondence** — each `compile_commands.json` entry maps to a real translation unit.

## 2. Actors and their disjoint `(U,L)` pairs
The canonical `sl-builder` cast, instantiated for **onboarding** (the implementer is a *prober*:
it derives setup, it does not write proofs). The downstream proving cast lives in `framac-sl`.

| Actor | Builds | U (above) | L (below) | Forbidden move | Must NOT see |
|---|---|---|---|---|---|
| **Launch coordinator** | the onboarding plan; Gate approvals; the handoff of the onboarding package to `frama-c-monitoring`; gap-doc adjudication | the mission + build docs + the named profile | the aggregated onboarding oracles (parse/toolchain/faithfulness/smoke) | edit source/ACSL; declare onboarding done on a prober's say-so; pick a profile not in the guidance | a prober's rationale |
| **Build/toolchain prober** (configurator) | the preprocess context (`compile_commands.json` / per-unit flags + feature defines + force-includes + `-machdep`); the toolchain confirmation | the target's **documented build for the chosen profile** (configure defaults, README, `user_settings.h`) | the **parse oracle** + `-wp-detect` (does it actually preprocess/parse + are the provers present) | pick flags that merely make it parse regardless of whether they match the shipped profile; declare a unit BLOCKED to dodge a flag problem | the proof annotations (n/a yet); the architect's ranking rationale |
| **Architect / auditor** (Phase 0) | the **scope map** (WP-amenable vs BLOCKED, with reasons) + the **attack-surface ranking** | the mission + the system's *documented* intent + **an EBIOS RM study if present (the exogenous risk bound)** | the actual source (read-only) | edit the target; verify anything; assert a claim it did not read out of the code; rank by raw input-exposure when an EBIOS risk level is available (use risk = severity × likelihood instead) | — |
| **Scaffolder** | the `<target>-acsl/` overlay (`setup.sh`/`verify.sh` skeleton/`patches/`/`harness/`/`README`/`verdicts.tsv`); the **faithfulness baseline pin** | the mbedtls-acsl layout (the durable-overlay convention) | the **faithfulness round-trip** (setup applies+reverses; strip-ACSL==HEAD per repo+submodule) | pin the baseline to a dirty/patched commit; track the vendored clone itself; alter the source | — |
| **Onboarding monitor** (`sl-monitoring-sl`) | per-onboarding verdicts on the prober's flag-set, the architect's scope map, and the baseline pin — **PASS / CARVE-OUT / REJECT** | `U` (shipped profile + attack-surface gold + guidance) | `L` (the parse/faithfulness/smoke oracles), as a differential comparator | edit the prober's/architect's work; read a prep agent's rationale; accept an onboarding it has not gated; fake a PASS for an un-runnable oracle | the prep agents' private notes |
| **Probe** (opt.) | minimal Frama-C capability experiments on this target (does it parse this construct? does `-machdep X` matter? does `-wp-fct` rescue a whole-file abort?) | one design claim per probe | Frama-C's *actual* behaviour | implement a fix | — |

**Disjointness (C1):** the prober holds "what flags make it parse" (never whether they match the
shipped profile); the architect holds "what the source contains" (never whether the scope is the
*intended* one); the **monitor holds "what the shipped profile + attack surface mandate" + "what the
oracles actually return"** — a base disjoint from the actor that produced each artifact; the
coordinator holds the guidance + aggregated oracles (never producing an artifact it grades).
**Intersection** = an onboarding whose flags parse *and* match the shipped profile, whose scope
covers the real attack surface, and whose baseline round-trips — none certified by its own producer.

**Catchability (C2):**
- prober **skips the real build** (synthesises flags / hand-writes the generated headers / declares
  units "preprocessing-BLOCKED" instead of compiling them) → caught by the **build oracle (§1.0)**:
  the build-generated artifacts are physically absent → Gate B_launch FAILS. Un-built is not BLOCKED.
- prober picks a **wrong-but-parsing** config → caught by the monitor (it holds the shipped profile;
  the parse oracle alone cannot tell — both configs parse). High-risk *ignore-signal* case: the
  prober "ignores" the profile signal because the parse oracle is satisfied → trigger test (does the
  feature set differ under the named profile?) → CARVE-OUT/REJECT.
- architect **misses an attack-surface module** → caught by the monitor's **completeness critic**
  against the documented surface (ideally cross-provider for a repeated-onboarding suite).
- architect's **functional scope claims are endogenous** (read off the code) → flagged per
  `sl-monitoring-sl` target 3; PASS certifies self-consistency, not conformance.
- scaffolder pins the **wrong faithfulness baseline** → caught by the round-trip oracle (a
  submodule file diffed against the parent "passes" falsely → the monitor checks per-submodule).
- onboarding declared ready with **no smoke proof** → Gate B_launch refuses.

## 3. Physical barriers
- **Monitor ⊥ prep rationale.** The onboarding monitor judges each artifact only against `U`
  (shipped profile + attack-surface) and `L` (the oracles) — never a prober/architect's account of
  *why* it chose a flag or a scope. Run the prep as **sub-agents** so their reasoning lives and dies
  in the sub-agent context and never crosses back (the delegation boundary IS the barrier).
- **Coordinator judges against the guidance**, not a prep agent's self-report; onboarding is never
  "ready" because a prober reported success.
- **Faithfulness baseline is physical.** The pristine baseline is `git HEAD` of the in-place clone
  (and *each submodule's* HEAD); the scaffolder records the exact commit(s), and the round-trip is a
  byte diff — not a promise.

## 4. Gates (launch level)
- **Gate A_launch — editorial.** The coordinator judges the onboarding plan + **the chosen feature
  profile** + the scope/ranking against `U`: is the profile the one that ships/deploys (not an
  arbitrary parse-success config)? is the attack surface scoped right? is the baseline-pin plan
  per-submodule? Amend / cut / sharpen; no scaffolding from a `DRAFT`.
- **Gate B_launch — machine.** Every onboarding oracle is green, **starting with the build oracle
  (§1.0): if the target was not actually compiled for the chosen profile — no real
  `configure`/CMake/`make`/`west build`, no `compile_commands.json`, no build-generated headers —
  Gate B_launch FAILS outright** (no fallback to synthesised flags or lifted leaf drivers; un-built
  ≠ BLOCKED). Then: the queue **parses** under the derived flags (no dropped-annotation warnings);
  `-wp-detect` + `framac-coq8` confirmed; `setup.sh` **applies and reverses** cleanly; strip-ACSL
  round-trips **per repo and per submodule**; the **smoke proof** reaches all-`Valid`;
  `compile_commands.json` entries map to real TUs.
- **Gate C_launch — coverage / no-blend / coherent-and-wrong.** The flag-set **matches the shipped
  profile** (the monitor's trigger test fires if the feature set diverges); the scope map **covers
  the documented attack surface** (completeness critic; no silent unit drop); the baseline pin is the
  **right commit**; **endogenous scope** is flagged (a functional scope claim read off the code is
  self-consistency, marked as such). The **parse oracle never substitutes for the smoke proof** (a
  unit that parses is not a unit that proves) — no plane blend.
- **Gate S — skill-consistency.** Onboarding heuristics the prep roles consolidate (per-buildsystem
  flag recipes, scope-map tells, baseline-pin idioms) are audited by a **disjoint** monitor (or a
  human) before landing in this skill's `references/learned-*.md`; never self-audited.

## Phase order (the onboarding sequence)
Run before any `frama-c-monitoring` unit. Each step is a sub-agent; the monitor gates the returned
artifact before the next step builds on it.

0. **Probe the build** (prober). Discover the buildsystem (autotools/CMake/make + `user_settings.h`),
   pick the **profile from the guidance**, then **actually build it** for that profile and emit
   `compile_commands.json` (`bear -- make` / `-DCMAKE_EXPORT_COMPILE_COMMANDS=ON` / `west build`) +
   the build-generated headers. This real build is **mandatory** — the **build oracle (§1.0)** gates
   it; you may not hand-synthesise the flags/headers or skip the build and call units BLOCKED. (The
   final link may legitimately fail downstream of header generation — that is fine; the **compile**
   of the in-scope TUs must succeed.) Then run the **parse oracle** on a representative unit. Confirm
   `-wp-detect` + `framac-coq8`. If the target genuinely cannot be built in this environment (missing
   toolchain/modules), that is a **hard blocker** to route, not a fallback to a synthesised config.
   **If the Frama-C TOOLCHAIN ITSELF is absent** (`frama-c` not on `PATH`, or the switch is gone, or
   `-wp-detect`/`-wp-timeout` report "unknown option" = the WP plugin failed to Dynlink-load against a
   missing switch's libs), first check for the SDK: if `FRAMA_C_SDK_SWITCH` is set, the toolchain is
   the `frama-c-sdk` SDK (§0 item 2) and a failing `frama-c` there is an SDK health problem to report
   (`workshop info` on the host), not something to rebuild. Otherwise do NOT stop at
   `DEPENDENCY-UNMET` — **INSTALL/BUILD it** (this is opam-local,
   reversible with `opam switch remove`, no `sudo`; verified working recipe, mbedtls 2026-07):
   - **Provers first (cheap, from opam):** `opam install alt-ergo` into the switch; `z3` is usually the
     system `/usr/bin/z3` or `opam install z3`. Then **register them with why3**: `why3 config detect`
     (WP calls provers *through* why3 — an installed alt-ergo that why3.conf doesn't know is "not found
     in why3.conf"; `-wp-detect` will list only what why3 registered). Re-run `-wp-detect` → must list
     `Alt-Ergo` + `Z3`.
   - **UPDATE (2026-07): Frama-C 32.1 IS now in the public opam repo** — `opam install frama-c -y
     --switch=framac-coq8 --assume-depexts` gives 32.1 (Germanium) directly. **This alone is NOT a
     conformant toolchain (§0 item 2 MANDATORY): the opam binary is unpatched, so you MUST still do the
     source-tree build below and apply `frama-c-patches/`.** The opam install is only a convenient way to
     get the *dependency base* (provers, coq/why3, apt depexts) into the switch; the binary you actually
     RUN must be the patched `framac-src` build. Requires these apt deps first: `sudo apt-get install -y
     libgtk-3-dev libgraphviz-dev libgtksourceview-3.0-dev` (for ivette GUI; not needed for WP/CLI but
     required by the opam package). **Also note:** `opam install coq` now gives Rocq 9.x, not 8.20.1 —
     the Coq-escalation path may be degraded; SMT-only (alt-ergo + z3) still works. See
     `references/learned-prober.md` for the full confirmed recipe.
   - **REQUIRED (not merely a fallback): build from the `framac-src` source tree** (a 32.x checkout) into
     the switch that has the right base (ocaml 4.14.x + coq 8.20 + why3 1.8.x + dune) — this is the ONLY
     way to get the `frama-c-patches/` fixes into the running binary (§0 item 2). Air-gapped environments
     have no other option; networked environments still need it for the patches:
     1. `opam install` its OCaml deps if missing — the recurring set is **`yaml ppx_deriving_yaml
        ocamlgraph ppx_inline_test unionFind`** (`unionFind` is the lib `region`/`alias`/`wp` link — WP
        will not load without it; `frama-c-wp` also link-needs `frama-c-eva.core`, so build/install eva's
        lib even though you never RUN eva — that is not an EVA-analysis use and does not break "no EVA").
     1b. **APPLY ALL `frama-c-patches/` BEFORE building** (MANDATORY — §0 item 2): run the top-level
        `apply.sh` and each subdir's `apply.sh` (`wp-cbits-bound-lemmas/`, `cabs2cil-c23-auto/`) against
        this `framac-src`; verify each hunk landed (`git status`/`grep` for the added axioms). Skipping
        this yields a source binary that is still missing the fixes — the same inert-patch trap as the
        stock opam binary.
     2. **Build the WHOLE project:** `dune build @install` (dev profile, ALL packages). **Do NOT scope with
        `-p <pkg>` / `--only-packages`** — that release-mode scoping silently omits the dune-site *plugin*
        `.cmxs` (you get `frama-c` core but `-wp-detect` stays "unknown"; the giveaway is `_build` having
        only kernel/boot `.cmxs`). Iterate on any "Library X not found" by `opam install`-ing X, then
        re-run.
     3. **Install into the switch:** `dune install --prefix "$(opam var prefix)" frama-c frama-c-wp
        frama-c-rtegen frama-c-region frama-c-server qed` (name the packages — a blanket `dune install`
        fails if optional plugins alias/region/volatile lack `.install`). The wp plugin must land in
        `$PREFIX/lib/frama-c/plugins/wp/`.
   - **macsl (Plane H)** builds on top: `dune build` in the `macsl/` submodule → `macsl.cmxs`; smoke it with
     `frama-c -no-autoload-plugins -load-module <macsl.cmxs> -macsl-list-contexts`.
   - **Gate before proceeding:** `frama-c -wp-detect` lists both provers **and** a trivial `-wp -wp-rte`
     proof discharges (e.g. `set42`/`add` → all `Valid`) **AND the running binary is the PATCHED
     `framac-src` build** (§0 item 2) — confirm with a patch-liveness probe: `land_le_l` present in the
     live `cbits.mlw`, `-wp-model bytes` does not abort on `extern int t[]; int*g(){return &t[0];}`, and
     `which frama-c` / the `verify.sh` shim resolves to the patched build, not `~/.opam/*/bin/frama-c`.
     Record the built switch + versions **+ the patch set applied** in the onboarding package's TOOLCHAIN
     provenance. (Known secondary gap: `why3 config detect` may report
     "Coq found but no Why3 libraries compiled for it" — the Coq escalation path is then unavailable; pure
     WP+SMT still works, so only deep bitmask/Zbits residues that need Coq are affected — note it, do not
     block on it.)
   **The hard-blocker report MUST be ACTIONABLE when the cause is a missing build dependency** (a
   `pkg-config` module not found, an absent `-dev` header, a build tool like `meson`/`ninja`/`bear` not
   on `PATH`) — do NOT just say "BLOCKED: deps missing". Emit the exact remediation command the user
   must run (the user installs it; the loop does not, since this needs `sudo`):
   - **If the target `XXX` is a known Debian/Ubuntu source package** (verify with `apt-cache showsrc XXX`
     — non-empty output): instruct **`sudo apt-get build-dep XXX`**. This pulls the *entire* declared
     build-dependency set in one shot and is the preferred form.
   - **Otherwise** (a vendored lib, an upstream tarball, or a target with no source package): resolve each
     missing dependency to its `-dev` package and emit an explicit **`sudo apt-get install <pkg> …`**
     line. Map the failing signal to the package: a missing `pkg-config` module `foo-N.M` → the
     `libfoo-…-dev` package (confirm with `apt-cache search 'libfoo.*-dev'` / `apt-file search
     foo-N.M.pc`); a missing tool → its package name (e.g. `meson`, `ninja-build`, `bear`). List ALL the
     missing deps on one line so the user fixes it in a single command.
   - **`apt-get source XXX` is NOT a fix** — it only unpacks source trees; it installs no headers, no
     `pkg-config` files, and no tools, so `pkg-config`/the build still fail. Never tell the user to run
     `apt-get source` to unblock a build; that lifts a class-A residue only for the *slice* approach
     (modeling an API by contract, headers consulted for confirmation), not for a real compile.
   - Re-run the build oracle after the user reports the install done; only then proceed (un-built ≠ done).
1. **Architectural audit** (architect, read-only fan-out). Produce the scope map (amenable vs
   BLOCKED) + attack-surface ranking. **Ranking key:** if an **EBIOS RM** study exists, rank by its
   **risk level** (severity × likelihood) via `templates/ebios-crosswalk.md` — the exogenous bound;
   a high-severity supporting asset that is BLOCKED becomes a *flagged residual risk*, not a silent
   drop. With no study, fall back to input-exposure and **mark the ranking endogenous**. (This is the
   audit `frama-c-monitoring`'s Phase 0 *consumes* — `frama-c-launch` owns it; see the handoff below.)
2. **Gate A_launch** → APPROVED (coordinator judges profile + scope + baseline plan).
3. **Scaffold** (scaffolder). Create `<target>-acsl/` from the mbedtls-acsl template; pin the
   faithfulness baseline (clone HEAD + each submodule HEAD); write `setup.sh` (init submodules +
   apply-patches idempotent) and a `verify.sh` skeleton.
4. **Smoke proof** (a single `framac-sl` instance on the highest-value leaf unit) → WP all-`Valid`,
   captured into `<target>-acsl/` (patch + session). This is the feasibility gate.
5. **Onboarding monitor** runs Gate B_launch + Gate C_launch on the package; emits verdicts +
   carve-outs; routes build-system gaps to `getting-better/`.
6. **Handoff.** On all-green, the coordinator hands the onboarding package to `frama-c-monitoring`
   (its Phase 0 consumes the scope map + queue; its Gate A_top re-judges against the *verification*
   guidance). Divergence (won't parse / wrong profile / scope miss / baseline wrong / smoke fails) →
   `gap-N` → re-plan; a tooling gap → route (`getting-better/`), never absorb.

## 5. Monitoring the prep (the `sl-monitoring-sl` discipline)
The prep roles produce **artifacts** (flags, scope map, scaffold) and **soft outputs** (the
`learned-*.md` recipes). Both can be **coherent-and-wrong**; the monitor squeezes each from a base
the producer does not hold — `U` = shipped profile + attack surface; `L` = the oracles.
- **Run prep as sub-agents** so the monitor sees only returned artifacts, never the rationale.
- **Conservative-transformation gate** for the baseline: strip-ACSL must reproduce the pristine
  source byte-for-byte **per repo and per submodule** — a submodule file diffed against the parent
  *falsely passes*, so check each owning repo (the mbedtls trap, §6).
- **Trigger test (ignore-signal)** for the prober's flag-set: it "ignores" the profile signal when
  the parse oracle is satisfied; perturb to the named profile and check whether the **feature set /
  compiled paths differ** → CARVE-OUT (defer to the shipped profile) or REJECT.
- **Completeness critic (coverage)** for the scope map: against the documented attack surface (and a
  `framac-gold/` if any), what module is missing? For a repeated heterogeneous-onboarding suite, run
  it **cross-provider** (extreme-case decorrelation; see `../frama-c-monitoring/references/wp-gotchas.md`).
- **Endogenous-`U` flag** for the architect: functional claims read off the code are self-consistency
  — mark them; exogenous RTE/robustness scope is sound.
- **Verdicts** PASS / CARVE-OUT / REJECT, each grounded in the build doc / guidance clause and
  traceable to the unit/`gap-N`. A monitor that flags everything or nothing is miscalibrated.

## 6. Worked example — onboarding mbedtls (replaying the real campaign under this loop)
The mbedtls campaign's setup, recast as a `frama-c-launch` run, shows each role and the catches.

- **Build/toolchain prober.** Found a bare clone **won't preprocess** (`tf_psa_crypto_platform_
  requirements.h: No such file`) → `git submodule update --init --recursive` is the binding
  precondition. Derived **two flag sets**: `PARSER` (minimal: `-I include -I tf-psa-crypto/{include,
  drivers/builtin/include,core} -DMBEDTLS_CONFIG_FILE='<mbedtls/mbedtls_config.h>'`) for leaf
  ASN.1/X.509, and `FULL` (adds `builtin/src extras platform utilities library
  -DMBEDTLS_PLATFORM_IS_UNIXLIKE`) for units pulling the cascade via `ssl_misc.h`. `-machdep
  gcc_x86_64`. Parse oracle: `asn1parse.c` parsed (34/58 baseline, no annotations). Toolchain:
  `framac-coq8` confirmed (needed for the bitmask lemma).
- **Architect.** Scope map: crypto submodule + TLS state machines + syscalls/IO → **BLOCKED**; the
  `library/` parsing layer (ASN.1/X.509/MPS/ciphersuite/cookie/ticket) → amenable. Ranking by
  input-exposure: ASN.1 `get_len`/`get_tag` → X.509 field parsers → mps_reader → record-header →
  cookie/ticket → ciphersuite.
- **Scaffolder.** Created `mbedtls-acsl/` (`patches/`, `harness/fc_harness_recv_asn1.c`,
  `sessions/asn1parse.wp.session`, `setup.sh` = submodule-init + idempotent patch-apply, `verify.sh`).
  Faithfulness baseline = **clone HEAD *and* the `tf-psa-crypto` submodule HEAD**.
- **Smoke proof.** `mbedtls_asn1_get_len`/`_get_tag` → **PROVED 99/99 + 1 Coq lemma** — the
  feasibility gate, proving the full Frama-C→WP→(SMT|Coq) path composes on real mbedtls source.
- **Onboarding monitor — the disjoint catches that justify the loop:**
  - **Submodule faithfulness baseline (conservative-transformation gate).** `asn1parse.c` lives in
    the `tf-psa-crypto` **submodule**, not the parent. A faithfulness check diffed against the parent
    repo would **falsely PASS** while the submodule file was edited. The monitor checks per-owning-repo
    → baseline pinned to the submodule HEAD. This is the textbook coherent-and-wrong an onboarding
    script misses.
  - **Whole-file WP abort (probe).** Frama-C's own `sys/socket.h` `assigns …(0..)` infinite-range
    stub aborts whole-file WP on any unit including `<sys/socket.h>` → `-wp-fct <fn>` recorded in the
    queue as a scoping flag, not a unit failure.
  - **`void*`-callback model.** The BIO `void *ctx` cast trips the Typed model → `-wp-model +cast`
    recorded for the callback-style units.
  These became seed entries in `references/learned-prober.md` / `learned-onboard-monitor.md`.

## 7. Executable oracle setup (the L tooling — built & tested)
`frama-c-launch`'s lower bound rests on these scripts (all at repo root, runnable today):
- **`bin/framac-onboard.sh <target-dir> [--build] [--switch NAME] [--sample N] [--cpp "FLAGS"]`** — the
  prober's primary oracle. Checks the toolchain (`-wp-detect` provers + the `framac-coq8` switch),
  inits submodules, finds/derives `compile_commands.json` (`--build` attempts `bear -- make` /
  `cmake -DCMAKE_EXPORT_COMPILE_COMMANDS=ON`), and runs the **parse oracle** on a sample of units
  (do they preprocess/parse with no dropped-annotation warnings?). Prints the §1/§2 onboarding-package
  rows with `PASS`/`DEPENDENCY-UNMET`; exit 0 only if toolchain + parse are green. Never fakes a PASS.
  (A `DEPENDENCY-UNMET` on the **Frama-C toolchain itself** — no `frama-c`/switch, WP won't load, provers
  absent — is not a terminal stop: run the §0 install/build-the-toolchain recipe first, then re-gate.)
- **`bin/framac-monitor-check.sh --git <file>`** — the real-codebase faithfulness oracle: strip-ACSL ==
  `git show HEAD:<file>` in the file's **owning repo**, resolved per file so a submodule file is
  diffed against the **submodule's** HEAD (the trap a single-repo diff falsely passes). Prints
  `ACCEPT | FABRICATED | NOORIG | MISSING`. (The original `framac/`+`framac-orig/` mirror mode is
  still the default first-arg form, for corpora that use a pristine mirror.)
- **`bin/framac-smoke.sh [--fct …] [--model +cast] [--prover …] [--switch framac-coq8] [--cpp "FLAGS"] FILE`**
  — the feasibility gate: runs one leaf unit through WP (`-wp -wp-rte`) and asserts every goal Valid;
  prints `SMOKE-PASS N/N` (exit 0) | `SMOKE-FAIL N/M` | `SMOKE-ERROR …`. Parse-green ≠ proof-green, so
  the handoff requires this, not merely a unit that parses (no-blend).
- Reused as-is: `bin/framac-queue.sh` (queue from `compile_commands.json`), `bin/framac-squeeze-audit.sh`
  (C1/C3 of the launch cast), `bin/framac-gen-report.sh --lint` (the onboarding report), and the
  `mbedtls-acsl/` layout as the scaffold template.
If an oracle's dependency is genuinely absent (no Bear/CMake → no `compile_commands.json`; no
`framac-coq8`), the scripts report `DEPENDENCY-UNMET` / `ONBOARD-BLOCKED` and the package records it —
never fake a PASS for an unaudited target (`sl-monitoring-sl` honesty rule).

## 8. The handoff to `frama-c-monitoring`
The onboarding package is the input to `frama-c-monitoring`:
- its **scope map + attack-surface ranking** seed `frama-c-monitoring`'s **Phase 0** (which then
  *consumes* rather than re-derives the audit) and **Gate A_top**;
- its **queue + flags + `-machdep`** feed the scheduler;
- its **`<target>-acsl/` scaffold + faithfulness baseline** become the durable overlay the monitor's
  faithfulness gate diffs against;
- its **smoke proof** is the first verified unit.
`frama-c-monitoring`'s Gate A_top **re-judges** the package against the *verification* guidance (it
does not blindly trust it) — the two loops are disjoint: `frama-c-launch` certifies "the target is
correctly set up for the shipped profile"; `frama-c-monitoring` certifies "the units verify." A
launch PASS is **never** a verification claim.

## 8b. Linux-kernel onboarding profile (`--linux` / `--full-tu`)
Spec: repo-root `linux-analysis.md`. When the mission carries **`--linux`** (forwarded by
`/rmf`/`/ebios`, or given directly), the scaffolder uses the **prebuilt modeled-runtime
overlay `linux/linux-acsl/`** instead of deriving a fresh `<target>-acsl/` from scratch.
Implementation is the canonical preset **`linux/linux-acsl/onboard-linux.sh <analysis-dir>
[--full-tu] [--kernel-src DIR]`** — it bakes the registration contract into the analysis dir
(no manual `-cpp-extra-args`):
- toolchain `-std c23 -machdep gcc_x86_64`; overlay includes **FIRST** (`hdr-overlay`,
  `asm-overlay`, `include`) so modeled headers shadow real ones; force-include
  `framac_kernel_shim.h`; apply `frama-c-patches/wp-cbits-bound-lemmas` (idempotent);
- emits `linux-acsl.env` (sourceable flags, incl. `ACSL_FRAMAC`/`ACSL_FRAMAC_TU` verifier
  binaries and the `framac_kernel_tcb.h` include), a `verify.sh` honoring the `*_good.c`/`*_bad.c`
  non-vacuity convention (and, in full-tu, the annotated-unit faithfulness gate + per-unit
  verdicts), and a `setup.log` provenance ledger (overlay / cbits patch / **c23 frontend patch** /
  machdep / std / baseline / **full-tu verifier status** / coqwp-gate result). Verified: a
  capability harness discharges through it with zero manual flags; `linux/linux-acsl/verify.sh`
  stays 17/17.
- **Default = harness mode** (verify drivers that `#include` the modeled runtime — works now).
  **`--full-tu`** additionally engages the kernel-TU parse compat layer and the **patched full-tu
  verifier binary** (the C23 frontend fixes `frama-c-patches/cabs2cil-c23-auto/` built with WP;
  the installed campaign frama-c cannot parse C23 kernel TUs). `onboard-linux.sh` resolves/probes
  it (`--framac-src`/`$FRAMAC_SRC`) and emits `ACSL_FRAMAC_TU`. **Status: reaches WP** — e.g.
  `security/commoncap.c` parses fully and its capability hooks WP-verify on the real TU
  (`linux-acsl/units/commoncap.c` + `verify-commoncap.sh`; `VERIFIED <proved/total>` in
  `verdicts.tsv`). Units that hit a fresh wall MUST still **loud-fail** (`PARSE-BLOCKED <unit>
  <header:line>`), never silently skip. Soundness: the cbits axioms are sound-by-correspondence;
  `coqwp-gate.sh` is the mechanical gate (TIER 1 GREEN in-env, TIER 2 full-chain `coqc` CI-only) —
  `setup.log` records its status.
- **Code-blindness:** this profile configures only the *verification* onboarding; the upstream
  `rmf-sl`/`ebios-sl` risk study stays barriered from source (its W1–W3/R1–R4 disjointness is
  untouched — see those skills).

## 9. Compliance & execution order
- **C1 Disjointness:** ✓ prober / architect / scaffolder / monitor / coordinator hold distinct
  `(U,L)` bases; the monitor's base (shipped profile + attack surface + oracles) is disjoint from the
  producers'. Run `bin/framac-squeeze-audit.sh` on the launch cast at Gate A_launch.
- **C2 Catchability:** ✓ wrong-but-parsing config → monitor trigger test; scope miss → completeness
  critic; wrong baseline → per-submodule round-trip; endogenous scope → the endogenous-`U` flag; no
  smoke → Gate B_launch.
- **C3 Physical barriers:** ✓ prep run as sub-agents; monitor never reads prep rationale; baseline is
  a byte diff per owning repo.
- **C4 Gate-defined done:** ✓ onboarding ready = all oracles green + profile-match + scope-coverage +
  baseline-correct + smoke-proved + monitor verdicts; no self-report.
- **Execution order:** probe-build → audit → Gate A → scaffold → smoke → monitor → handoff. The smoke
  proof is the pilot (pin reality before building machinery on it).

## Reference files
- `references/learned-prober.md` — buildsystem→flags recipes, force-include/`-machdep`/profile
  discovery, the parse-oracle tells (Gate-S-gated).
- `references/learned-architect.md` — scope-map + attack-surface-ranking heuristics; endogenous-vs-
  exogenous scope discipline (Gate-S-gated).
- `references/learned-onboard-monitor.md` — onboarding-audit tells: the submodule-baseline catch, the
  wrong-but-parsing-config trigger test, the completeness critic (Gate-S-gated).
- `templates/onboarding-package.md` — the handoff-contract + `<target>-acsl/` overlay skeleton.
- `templates/ebios-crosswalk.md` — the EBIOS RM ↔ launch join table: supporting assets ↔ translation
  units, attack paths ↔ verification targets, and the risk-level ranking (the exogenous `U`).
- `references/ebios-feedback.md` — the downstream half: how `frama-c-monitoring`'s verdicts become
  EBIOS W5 treatment evidence (SCIP measures + residual risks) at campaign close (`frama-c-monitoring`
  §8e runs it). The coordinator proposes; the EBIOS risk owner adjudicates (human terminus).
- The **`ebios-sl`** loop (`../ebios-sl/SKILL.md`) — the **producer** of the exogenous risk bound: a
  code-disjoint peer that authors the EBIOS report (W1–W4) *before* this loop and hands it over. Its
  W1 severity + W4 likelihood feed the crosswalk's ranking; W5 consumes the verification verdicts back
  as treatment evidence (downstream, see the crosswalk §3). The EBIOS method content it uses is the
  **`ebios-risk-manager`** skill (invocable via the Skill tool).
- **NIST RMF alternative (peer of the EBIOS trio above):** `templates/rmf-crosswalk.md` +
  `references/rmf-feedback.md` + the **`rmf-sl`** loop (`../rmf-sl/SKILL.md`) — the same producer→
  crosswalk→feedback chain in NIST form (SP 800-30/37/53 + STRIDE), the return half landing on the
  800-37 *Monitor* step. Use the EBIOS set or the RMF set per the engagement; they are interchangeable
  exogenous-bound sources.
- Downstream: `../frama-c-monitoring/SKILL.md` (consumes the package); base ACSL/loop reference:
  `../frama-c/SKILL.md`, `../framac-sl/SKILL.md`.
- Tooling lore reused: `../frama-c-monitoring/references/wp-gotchas.md`,
  `../frama-c-monitoring/references/stabilizers.md`. Design rationale:
  `../frama-c-monitoring/references/loops-design.md`.
- Methodology: `sl-builder` (design), `sl-monitoring-sl` (monitor), `sl-internal` (theory),
  `sl-auditor` (audit an instance).

## ASSUMPTIONS & open questions
- `ASSUMPTION:` "the target" is a vendored clone of one C/C++ codebase under `<dir>`, its own git
  repo (so in-place git-HEAD faithfulness applies); the durable overlay is `<target>-acsl/` and the
  narrative report is `<target>-report.md` (mbedtls convention).
- **Profile source. OPEN:** the shipped/deployment feature profile is the loop's `U` for "wrong-but-
  parsing config." Is it a named `configure` line, a `user_settings.h`, or free-text guidance? It
  must be **citable** when the monitor carves the prober's flag-set.
- **compile_commands availability. OPEN:** Bear/CMake may be unavailable; then flags are hand-built
  and the parse oracle is the only guard — record `DEPENDENCY UNMET` for the auto-queue.
- **Smoke-unit choice. OPEN:** default to the highest-value amenable leaf (the most-exposed parser);
  if even that needs Coq, the smoke proof also exercises the `framac-coq8` path (a stronger gate).
