# frama-c-patches — out-of-tree patches to Frama-C / WP

Local source patches to **Frama-C** that we depend on but that are **not (yet) upstream**. Kept here so
they can be re-applied to a fresh checkout, audited, and **re-based as Frama-C evolves** — if a patch is
backported upstream, drop it from this directory; if not, port its hunk to the new version.

These patch the Frama-C *source tree* (the `framac-src` dev build), **not** this repo. `framac-src` is a
vendored, untracked checkout (`opam source frama-c.<ver>`), so its edits cannot live in this repo's git;
this directory is how they survive and travel.

## Why these patches exist

They come out of the **cast/region soundness investigation** (`../bugs-to-report/wp-cast-region-soundness/`,
`../23-0545-consistency-*.md`): validating WP's byte-level memory model (`-wp-model bytes`) as a path to
verifying pointer-cast / CONTAINER_OF / intrusive-container code. Evaluating `bytes` at scale surfaced
robustness/precision defects that block or distort that evaluation; each patch here fixes one, with a
filed report + reproducer under `../bugs-to-report/`.

We carry them because **adopting `bytes` (even opt-in, per cast-heavy unit) requires it to not abort on
ordinary kernel code**. Until the fixes land upstream, every `bytes` run in this project assumes them.

## Pinned version

- **Frama-C 32.1 (Germanium)**, opam switch `framac-coq8` (Why3 1.8.2, Alt-Ergo 2.6.3, Z3 4.13.3, Coq
  8.20.1). Line numbers in the patches are 32.1; re-confirm on rebase (they drift between releases).

## Patches

| # | file | component | what it fixes | upstream status |
|---|---|---|---|---|
| 0001 | `0001-membytes-unknown-size-array-sizeof.patch` | `src/plugins/wp/MemBytes.ml` | `-wp-model bytes` aborts with a **fatal internal error** (`Failure: Sizeof unknown-size array`) on extern / flexible / linker-section arrays; `protected_sizeof_object` doesn't guard the unknown-size `C_array` case that `Ctypes.sizeof_object` raises on. Degrade like `MemTyped` (max_int / recoverable `Warning.error`). Compilation-only, no new axiom. | not submitted — report at `../bugs-to-report/wp-cast-region-soundness/REPORT-membytes-sizeof.md` |
| 0002 | `0002-cabs2cil-gnu-zero-length-array-non-final-field.patch` | `src/kernel_internals/typing/cabs2cil.ml`, `src/kernel_services/ast_queries/cil.{ml,mli}` | A **GNU zero-length array** (`T x[0];`) in a **non-final** struct field is hard-rejected as if it were a C99 flexible array member (`T x[];`), aborting the whole TU at parse time. `cil.ml:6052` folds the two constructs together; `cabs2cil.ml:5134` then applies the C99 final-position rule to both. Adds `Cil.has_unsized_flexible_array_member` (only `TArray(_,None)`) and uses it as the guard, leaving `has_flexible_array_member` byte-for-byte unchanged. A **true** non-final C99 `[]` is still rejected. Typing-stage acceptance widening only, no new axiom. | not submitted — report at `../bugs-to-report/frama-c-frontend-fam-non-final-field/README.md` |

Each patch carries its own rationale + verification in its header (`git`-style `From:/Subject:` block).

## Apply

```sh
# point at your framac-src checkout (default: ../framac-src)
FRAMAC_SRC=../framac-src ./apply.sh
```
or by hand, from the Frama-C source root:
```sh
cd framac-src
for p in /path/to/frama-c-patches/0*.patch; do git apply "$p" || patch -p1 < "$p"; done
```

## Rebuild after applying (IMPORTANT)

WP is a **dynamically-loaded plugin**: `dune exec frama-c` alone does **not** relink it after a `.ml`
edit — it keeps running the stale plugin. Use:
```sh
cd framac-src
eval $(opam env --switch=framac-coq8 --set-switch)
dune build @install            # required: relinks the dynamic plugin
dune exec --root . -- frama-c -wp -wp-model bytes ...
```
Tell that you're on a stale plugin: an error backtrace cites the *old* line numbers even though you
inserted lines. To drive an overlay's `verify.sh` (which calls bare `frama-c`) with the dev build, put a
PATH shim ahead: a `frama-c` script that execs `dune exec --root <framac-src> -- frama-c "$@"`.

## Rebasing onto a new Frama-C release

1. `opam source frama-c.<newver> --dir=framac-src`.
2. For each patch: `git apply --3way` (or `patch -p1`); on reject, port the hunk by hand to the new code
   (the patch header says exactly which function and why).
3. Re-run the verification that justified it (see each patch's `Verified` section and the linked report)
   — e.g. for 0001: the minimal repro `extern int tbl[]; int *g(void){ return &tbl[0]; }` must no longer
   abort under `-wp-model bytes`, and `mem_slab.c` must complete.
4. If the defect is fixed upstream in `<newver>`, **delete the patch** and note it here.
