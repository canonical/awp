---
name: frama-c-internals
description: >-
  Grounded knowledge of Frama-C/WP internals — the memory-model architecture
  (Typed / +cast / Bytes / Region), how casts/validity/assigns/frame compile to
  proof obligations, the exact source-file/line map (Frama-C 32.1), the dev-build
  workflow, and the open "cast/region soundness" investigation trail (the cast-frame
  defect + the CONTAINER_OF round-trip). Use when working ON WP itself — modifying or
  reasoning about a memory model, diagnosing why a pointer-cast / intrusive-container
  RTE goal won't discharge, distinguishing model-limitation from spec-gap from
  prover-weakness, or resuming the sound-+cast/region-model fix. NOT for ordinary ACSL
  authoring (that is the `frama-c` skill) or campaign orchestration (`frama-c-monitoring`).
---

# frama-c-internals — WP memory-model internals & the cast/region soundness trail

> Built from a grounded investigation (Frama-C **32.1 Germanium**): every source line cited
> was read in `framac-src` (`opam source frama-c.32.1`); every prover result was reproduced.
> Verified facts are stated plainly; the **open question** is flagged as such. When resuming,
> re-confirm line numbers against the version in use — they drift between releases.

## 0. Why this skill exists
A class of RTE goals on idiomatic systems C — a load/store **through a pointer cast** (`*(char**)p`,
`*(void**)head`, `CONTAINER_OF`, intrusive dlist/slist/free-list nodes) — does not discharge in WP's
default model, and is **not** a spec gap and **not** prover-weakness: it is a **memory-model
limitation**. This skill stores what is known so the open-ended fix (a sound `+cast`/region model) can
be resumed without re-deriving. The full report/plan/impl-design live at repo root:
`22-2208-report.md` (defect), `22-2208-plan.md` (high-level plan), `22-2208-impl.md` (impl design +
the investigation log §0–§0quater). This skill is the durable, version-anchored companion.

> **Two other distinct blockers are filed separately (don't conflate with the cast/region trail).**
> (a) **Proof residue — bitwise:** elementary `land`/`lor`/`lnot` lemmas SMT can't discharge (class
> (2) true-but-hard) — `references/bitwise-smt-trail.md`, `bugs-to-report/wp-bitwise-smt-incompleteness/`.
> (b) **Frontend / PARSE gap — C23:** real kernel TUs don't even type-check (C23 `auto` mistyped as
> int, `__typeof_unqual__` unrecognized, `__int128` unsupported) — this *precedes* WP, NOT a residue
> class — `references/c23-frontend-trail.md`, `bugs-to-report/frama-c-c23-frontend-gaps/`. The C23
> `auto` gap is the sound blocker capping full-TU kernel onboarding (`linux-analysis.md` §5.2).

## 1. The residue taxonomy (the lens)
Every undischarged WP goal is exactly one of three — keep them distinct:
1. **missing-hypothesis (spec gap)** — the goal is *false in some model*; add the antecedent
   (`requires \valid`, `terminates`, a `loop invariant`, callee `ensures`). No prover (SMT *or* Coq)
   closes a non-theorem. Tell: adding the antecedent flips it to `Valid` instantly.
2. **true-but-hard** — valid, no counter-model, but SMT can't find it; **Coq** closes it (nonlinear
   `nia`, induction, bitmask). Tell: stays stuck with full hypotheses in scope, no counter-model.
   The **bitmask** sub-case is its own filed item — elementary `land`/`lor`/`lnot` lemmas
   (`(a&b)≤a`, `a&~a==0`, `d<m ⟹ (d&~m)<2^63`) that Alt-Ergo/Z3 reliably miss and `wp:bitrange`/Coq
   close: see `references/bitwise-smt-trail.md` and `bugs-to-report/wp-bitwise-smt-incompleteness/`.
3. **model-limitation** — the model *discarded* the fact (cast/region); neither spec nor Coq helps;
   needs a WP change. Tell: even `+cast` (the only complete option) is unsound/vacuous or
   mis-computes. **This is the cast/region trail.**
The discriminator between (1) and (2) is the **refutation probe**; (3) is identified when the probe
shows the fact is gone from the encoding regardless of prover. (See `frama-c-monitoring` §0.)

## 2. WP memory-model architecture (verified, 32.1)
- **Model selection — `Factory`** (`src/plugins/wp/Factory.ml/.mli`).
  `type mheap = Hoare | ZeroAlias | Eva | Bytes | Region | Typed of MemTyped.pointer`;
  `type mvar = Raw | Var | Ref | Caveat`. `-wp-model` strings map in `Factory.parse`
  (`:334-336` → `TYPED→Typed Fits`, `CAST→Typed Unsafe`, `NOCAST→Typed NoCast`); default =
  `Var,Typed,Nat,Real`. `Factory.compiler mheap mvar : (module Memory.Compiler)`.
- **Default model — `MemTyped`** (`MemTyped.ml`). `type pointer = NoCast | Fits | Unsafe` (`:13/:51`).
  Per-type "chunks"; locations are `addr`. **Crucial:** `Context.get pointer` (the Fits/Unsafe/NoCast
  policy) is consulted **only inside `cast`** (`:897` warning, `:913` match) — **NOT** in
  load/store/frame. So `Fits` and `Unsafe` differ *only* in the cast.
- **Address & validity theory — `MemAddr`** (`MemAddr.ml/.mli` + Why3
  `share/why3/frama_c_wp/memaddr.mlw`). `addr` is a **Why3 record** `{ base:int; offset:int }`
  (`memaddr.mlw:15`); `shift p k = { p with offset = p.offset + k }`. Validity is **allocation-table**
  based: `valid_rw/valid_rd (m:malloc) (p:addr) (n:int)` over the `linked`/`T_alloc` table — *not*
  per-chunk. `included`/`separated` are parameterized by `~shift ~addrof ~sizeof` (region containment
  exists). Qed simplifiers registered: `set_builtin_1 f_base/f_offset`, `set_builtin_2 f_shift`,
  `set_builtin_eqp f_shift eq_shift` (`MemAddr.ml:336-339`).
- **Other models:** `MemBytes` (byte-level), `MemRegion`+`RegionAnalysis` (region inference),
  `MemVar`/`MemVal`, `MemEmpty`/`MemZeroAlias`. `MemLoader` is the load/store functor; `Cvalues` does
  value reinterpret; `Ctypes`/`Layout` hold sizeof/alignment/`Layout.fits`.
- **The TCB:** WP's Coq path realizes the `*.mlw` theories under `share/why3/frama_c_wp/<lib>/` (Coq).
  Any new model axiom enters this trust root and must be **admit-free realized** (the project's
  hardened-`coqwp` posture; CI-gated via `axiom-wp/coqwp`).

## 3. How a cast compiles (the heart of the trail)
- `CodeSemantics.exp_node` (`:314`): `CastE(tr,e) → cast tr (typeOf e) (s_exp env e)` → `MemTyped.cast`.
- `MemTyped.cast s l` (`:910`): `NoCast`→`Warning.error`; `Fits`→ if `Layout.fits` return `l` **else
  `Warning.error`**; `Unsafe`→ warn (`"Keep pointer value"`) and **return `l`**. The location is
  *preserved* either way — casts do **not** fabricate a fresh address.
- **The hide:** `CodeSemantics.exp_protected` (`:319`) wraps expression compilation in
  `Warning.handle ~handler:exp_undefined ~fallback:"Hide sub-term definition"`. When `cast` raises
  `Warning.error` (Fits, non-fitting), the handler replaces the **whole expression with a fresh opaque
  `addr`**. That fresh `addr` is what severs base/offset reasoning. (`LogicSemantics.ml:951` is the
  ACSL-side twin.)

## 4. The two mechanisms (and what is settled vs open)
- **Mechanism (1) — non-fitting value access** (`*(char**)p = v`): under `Fits` the cast errors → the
  store target is hidden → `assigns`+`valid` can't reduce (e.g. `castmin.c` = 2/4). Under `+cast` it is
  4/4 (sound *for this no-call case*). The documented **`wp-cast-frame-defect`**: `+cast` drops the
  malloc-frame across an `assigns *(cast)ptr` **call**, yielding vacuous greens — a *distinct*
  call/frame scenario (the soundness boundary to locate).
- **Mechanism (2) — CONTAINER_OF round-trip** (`(T*)((char*)&c->m − offsetof(m)) == c`): **ROOT-CAUSED.**
  WP's Typed model indexes offsets in **CELLS, not bytes** (`length_of_object` of any scalar = `F.e_one`,
  `MemTyped.ml:234`). So `&c->m` shifts by `position_of_field(m)` *cells* (`:256`, e.g. 1 for the 2nd
  field) while the source's `(char*)… − offsetof(m)` shifts by `offsetof(m)` *bytes-taken-as-cells* (e.g.
  4) — net displacement `position − offsetof ≠ 0`, so Qed correctly decides `c2 ≠ c` → `Prove: false`
  under `+cast`, and the term is *hidden* under default `Fits`. **Decisive confirmation:** replacing the
  byte literal with the *cell* position (e.g. `−1` instead of `−4`) proves **4/4**
  (`references/reproducers/c2_cellconfirm.c`). It is a **byte↔cell representation-consistency gap**, not
  extensionality/fresh-addr/spec-gap (H1–H4 refuted; H5 confirmed — `references/cast-region-trail.md`).
  The fix plan + consistency law is `23-0545-consistency-plan.md`. **Open is now the *fix direction*
  (byte-indexed offsets vs cell-kept), not the diagnosis.**

## 5. Dev-build workflow (verified)
```
opam source frama-c.32.1 --dir=framac-src          # 78M source
cd framac-src
eval $(opam env --switch=framac-coq8 --set-switch)
dune exec --root . -- frama-c -version             # builds kernel+WP, sets runtime env (32.1)
# edit src/plugins/wp/*.ml, then RELINK the plugin (see below), then:
dune exec --root . -- frama-c -wp -wp-rte -wp-prover alt-ergo,z3 <file.c>
```
- **A WP `.ml` edit needs `dune build @install` to take effect — `dune exec frama-c` alone runs the
  STALE plugin** ([[framac-dev-plugin-relink]]). WP is a *dynamically-loaded* plugin: the boot exe
  doesn't statically depend on it, so `dune exec` (and `dune build src/init/boot/empty_file.exe`)
  recompile the source but don't relink what's loaded at runtime. Do `dune build @install` first. The
  earlier "do NOT @install (~40 min)" caution was wrong — @install is fast once e-ACSL is built once;
  the install-target relink is the real requirement. **Tell you're on a stale plugin:** an error
  backtrace cites the *old* line numbers even though you inserted lines. `bin/frama-c.exe` is not a
  target; the binary is `src/init/boot/empty_file.exe` (symlinked `frama-c`), only runnable via
  `dune exec` (sets `FRAMAC_SHARE`/plugin paths) — bare it gives `Failure("hd")`. To drive an overlay's
  `verify.sh` (calls bare `frama-c`) with the dev build, PATH-shim a `frama-c` that execs
  `dune exec --root <framac-src> -- frama-c "$@"`.
- **Persist source patches in `frama-c-patches/` (repo root).** `framac-src` is vendored + untracked,
  so its edits can't live in this repo's git — `frama-c-patches/` is how they survive a fresh checkout
  and **re-base as Frama-C evolves**: a README (pinned version, per-patch table + upstream status, the
  rebuild gotcha, the rebase procedure), numbered self-documenting `.patch` files (git-style
  `From:/Subject:` header with problem/fix/verified), and `apply.sh` (`apply` / `--check` vs
  `$FRAMAC_SRC`). Each patch pairs with a filed report under `bugs-to-report/`. Delete a patch when it
  lands upstream. First entry: `0001-membytes-unknown-size-array-sizeof.patch` (the `-wp-model bytes`
  unknown-size-array fatal, §4 of the cast/region trail).
- **Fast theory iteration:** the `*.mlw` theories are loaded at *runtime*; editing
  `share/why3/frama_c_wp/memaddr.mlw` (or the installed copy under
  `~/.opam/framac-coq8/share/frama-c/share/wp/why3/frama_c_wp/`) changes SMT behavior **without an
  OCaml rebuild** — good for probing lemma effects (but the Coq realization must match for soundness).

## 6. Probing recipes (verified)
- **Dump a goal term:** `frama-c -wp -wp-prop <name> -wp-print file.c` (shows `Assume … Prove …`).
- **Why3 task:** `-wp-prover why3 -wp-gen -wp-msg-key print-generated`.
- **Interactive Coq:** `-wp-prover coq -wp-interactive -wp-session <dir> -wp-cache none` (cache MUST be
  `none` — a cached SMT result masks the Coq script; imports go *inside* `Proof.`).
- **Model compare:** add `-wp-model +cast` (= `Typed Unsafe`) to see the cast-policy delta.
- **Per-goal verdict diff (banking method):** `-wp-report-json <file.json>` emits one record per goal
  (`file`, `function`, `property`, `line`, `passed`, `verdict`, `provers`). To find what a second
  model/setting newly closes, run both and diff by the key **`(file, function, property, line)`** (NOT the
  goal name — it is model-prefixed, e.g. `typed_…`/`bytes_…`; include `file` so keys don't collide across
  a multi-file run). A goal `passed` under B but not A = newly banked; under A but not B = lost. This is
  how to bank a `-wp-model bytes` separate pass against `Typed` without double-counting. (Goal *numbering*
  also shifts between runs — Qed-discharged goals get no prover goal — so always key by
  file+function+property+line, and re-diff after any annotation change.)
- **Vacuity probe (is a green non-vacuous?):** inject `/*@ assert vac: \false; */` at the goal's exact
  program point and run that prop. If the prover **proves `\false`** there, the context is inconsistent →
  the green was **vacuous**; if it **cannot** (0/1), the context is consistent → the green is a genuine
  derivation. Pair with a teeth check (mutate so the property is genuinely violated → must go RED) to rule
  out a model that "proves everything." (WP's `-wp-smoke-tests` is the built-in analogue for whole-function
  inconsistency; the `assert \false` probe is the per-goal, point-precise version.)
- Reproducers preserved in `references/reproducers/` (`castmin.c`, `c2_roundtrip.c`, `c2_literal.c`,
  `canary.c`, `c2_cellconfirm.c`, `frame_char.c`, `membytes_sizeof_crash.c`).

## 7. The open trail — how to resume
Goal: a memory model **sound AND complete** on pointer-cast lvalues. **The diagnosis is DONE** (the
Qed-term trace is complete — mechanism (2) is the cell-vs-byte offset unit mismatch, §4 above;
`23-0545-consistency-plan.md` states the consistency law + oracle). Next concrete step is the **fix
direction**, the design gate of `22-2208-plan.md` Phase 1, now informed by the root cause:
- **(A) byte-indexed offsets** — make `length_of_object`/`position_of_field` measure real bytes (as
  `MemBytes` does) so `+offsetof`/`−offsetof` cancel; largest blast radius on cell-based typed-separation.
- **(B) keep cells, lift byte arith** — treat `(char*)`+`offsetof` as a reinterpretation lifted back to a
  field path, never mixed numerically; smaller radius, cannot express true sub-object byte-puns (those
  stay honest residual).
Build the §4 consistency oracle first (round-trip family over the field-offset matrix **with the
perturbation teeth** — `offsetof ± 1` / wrong field must go RED — that is what the `−4` vs `−1` probe
proved). Hold the line: a `COQ-NEEDED`/residue label needs the refutation probe; never adopt `+cast` to
turn an honest residual into a vacuous green (here it produces `false`, not even a vacuous green); any new
consistency axiom must be admit-free realized. See `references/cast-region-trail.md` (H5 confirmed) for
the full log.
