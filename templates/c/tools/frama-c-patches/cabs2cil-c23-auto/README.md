# cabs2cil-c23-auto — Frama-C frontend fixes for full-TU Linux-kernel parsing

**Target:** Frama-C 32.1 `src/kernel_internals/typing/cabs2cil.ml`.
**Closes (when built):** the sound frontend blockers behind `linux-analysis.md` §5.2
full-TU kernel parsing — gap (1) of `bugs-to-report/frama-c-c23-frontend-gaps/` plus two
further frontend over-restrictions surfaced grinding the `security/commoncap.c` cascade.
**STATUS: IMPLEMENTED + COMPILED + VERIFIED WORKING.** With these three fixes (and the
header shim/overlays in `linux/linux-acsl/`), the real `security/commoncap.c` parses to
completion under `-std c23 -machdep gcc_x86_64` with the genuine kernel cpp recipe: RC=0,
zero errors, a 13580-line AST containing all seven `cap_*` LSM hooks
(`cap_capable`, `cap_settime`, `cap_inode_setxattr`, `cap_task_prctl`,
`cap_bprm_creds_from_file`, `cap_convert_nscap`, `cap_ptrace_access_check`).

## The three fixes (one patch, six hunks)

### 1. C23 `auto` type deduction  (the original headline; gap 1)
Implements `auto x = e;` (C23) as "deduce x's type = type of e", the missing feature behind
`[typing:implicit-int]` on `const auto`. Four edits:
1. `doSpecList`: add an `is_auto` flag.
2. storage match: `Cabs.AUTO -> is_auto := true; NoStorage` (was just `NoStorage`).
3. empty type-specifier branch: when `is_auto`, emit a **complete** sentinel base type
   `{ intType with tattr = ["__fc_autotype",[]] }` (complete so it does not trip the
   "initializer but incomplete type" check at the declaration site) instead of warning +
   defaulting to plain `int`.
4. `doInitializer`: if the var's type carries `__fc_autotype`, type the `SINGLE_INIT`
   expression (`doExp … (AExp None)`), then set `vi.vtype` to the deduced type, preserving the
   declared cv-qualifiers (`const auto x = e` → `const <typeof e> x = e`).

Verified: `const auto x = p;` → `unsigned long * const x = p;` (correct deduction, const
preserved); plain `foo(x)` still → `int foo(int x)` (no implicit-int regression). Mirrors GNU
`__auto_type`; only fires on `auto`-storage + no-type, so ordinary implicit-int still warns→int.

### 2. `return <void-expr>;` in a `void` function  (C11 6.8.6.4)
The `Cabs.RETURN (e,…)` arm errored unconditionally when the function returned `void`, even
though `return e;` is **legal** when `e` itself has type `void` (e.g. `return void_call();` —
common in kernel `static inline void` wrappers like `ratelimit_default_init`,
`sysfs_*`). Fix: probe `e`'s true type with `AType` (an `ADrop` evaluation reports a
placeholder `int` for void calls, so it can't be used for the test), error only when that
type is non-void, then evaluate `e` for side effects with `ADrop` as before.

### 3. `offsetof`/`container_of` with a runtime array index
`__builtin_offsetof` was forced to a compile-time constant via `Cil.bitsOffset`; the kernel's
`container_of(node, struct latch_tree_node, node[idx])` (rbtree_latch.h) uses a **runtime**
member index, so `bitsOffset` raised `SizeOfError "Index is not constant"` → hard error. But
`offsetof(t,m)` is by definition the address of member `m` taken against a null base, and the
builtin's argument `e` already *is* that address expression `&((t*)0)->m`. Fix: split the
`SizeOfError` handler — on `"Index is not constant"`, recover by using `e` cast to `size_t`
as the (genuinely runtime) offset value; all other `SizeOfError`s keep erroring. This is exact
(not an approximation) and clears the whole `container_of(…, arr[i])` class kernel-wide.

## Soundness / scope notes
- (1) deduces from the **unqualified** init type + re-adds declared cv-quals (C23 semantics);
  the type-probe `doExp` may double-evaluate a side-effecting `auto` initializer — acceptable
  for parse/typecheck, revisit if such an init is ever *verified*. Declarator-bearing forms
  (`auto *p = …`) are not specially handled (the kernel uses `[const] auto x = e`).
- (2) is a pure correctness fix (the frontend was over-strict vs the C standard).
- (3) is exact: the recovered offset expression equals the member address against null, which
  is precisely the runtime offset; no soundness gap.

## Build note (resolved)
The first builds failed on dune-site boot-loader generation
(`dune_site__Dune_site_data.ml-gen: No such file`). Root cause was a **polluted `_build`**, NOT
a dune bug. Fix: **`dune clean` then a fresh single-context build** of
`src/init/boot/empty_file.exe`. To RUN the dev binary, use `dune exec --root . -- frama-c …`
and ensure the dev share has machdeps
(`cp -rn share/machdeps _build/install/default/share/frama-c/share/`).

## Apply + build (in a WORKING frama-c build env)
```sh
cd $FRAMAC_SRC && patch -p0 < cabs2cil-c23-auto.patch   # paths relative to framac-src root
eval $(opam env --switch=framac-coq8 --set-switch)
dune build src/init/boot/empty_file.exe                 # or: dune build @install
# then test the headline fix:
dune exec --root . -- frama-c -std c23 -machdep gcc_x86_64 \
  bugs-to-report/frama-c-c23-frontend-gaps/reproducers/auto.c -print   # expect deduced type, no implicit-int
```
The installed campaign frama-c (the opam switch) is **unchanged** — only `framac-src` was edited.
