# Tests of the `rocq` SDK

`sdks/test-sdk.sh rocq` only compiles a one-lemma file. These tests
use the SDK for real proof work in a throwaway workshop: multi-file projects
built three ways, recursion beyond structural `Fixpoint`, a verified
algorithm and a verified compiler, extraction to OCaml that is compiled and
run, every bundled library loaded, an independent kernel re-check, and
negative cases that must be rejected with Rocq's own error message.

## Running

```sh
sdks/rocq/tests/run.sh                       # base ubuntu@24.04
BASE=ubuntu@26.04 sdks/rocq/tests/run.sh
KEEP=1 sdks/rocq/tests/run.sh                # keep the workshop
LOGDIR=/some/dir sdks/rocq/tests/run.sh      # keep the step logs
```

The SDK must already be packed in the try area for the base
(`make sdk-rocq`, i.e. `sdkcraft try` in `sdks/rocq/`); `run.sh`
never builds it. It writes `.workshop/rocq-tests.yaml` (SDK
`try-rocq`) in a temporary project, copies `check.sh` and `cases/`
into it (mounted at `/project` in the workshop), launches the workshop
`rocq-tests`, runs `check.sh /project/work` as the workshop user through a
login shell, and removes the workshop unless `KEEP=1`. It prints `PASS:` or
`FAIL:` per check and a final `SUMMARY:` line, and exits 0 only if every
check passed. A run takes a few minutes, most of it the launch.

`check.sh` can also run by hand inside any workshop that has the SDK:
`bash check.sh [WORKDIR]`. Every step's output is in `WORKDIR/logs/`.

## Checks

| Check | What it proves |
|---|---|
| `launch`, `health` | the workshop launches from `try-rocq` and reaches `ready` (the SDK's `check-health` said okay) |
| `env.tools` | `coqc` and `rocq` report 9.2 and come from `/opt/rocq/opam/rocq/bin`, `coqc -where` is the SDK's library; `coqtop coqdep coqchk rocqchk coqdoc coq_makefile dune ocamlfind ocamlopt ocamlc rg` are on `PATH`; `ROCQ_PYTHON_BIN` runs Python 3 (the `rocq` skill reads it) |
| `env.read-only-switch` | the opam switch is not writable by the user |
| `libs.load-all` | one `Require` per `.vo` the SDK ships (Corelib, Stdlib, Ltac2: about 690 modules) in one file; `Print Libraries` lists them all |
| `env.build-tools` | `make`, `as` and `cc` are on `PATH` (needed by `rocq makefile` projects and by `ocamlopt`) |
| `project.rocq-compile` | `cases/make`: 8 files under `_RocqProject` (`-R theories AutoWP`) with cross-file imports, compiled one by one with `rocq compile` in `rocq dep -sort` order (needs no `make`) |
| `project.print-assumptions` | `Audit.v` runs `Print Assumptions` on every main theorem: all are *Closed under the global context* |
| `project.no-admitted` | no `Admitted`, `admit`, `Axiom`, `Parameter`, `Abort` in the sources |
| `project.rocqchk` | `rocqchk` re-checks the compiled `Trees Compiler Sort Recursion` and their dependencies: *Axioms: \<none\>* |
| `project.coqtop-batch` | `coqtop -batch -R … -l Sort.v`, the way Why3 runs Coq |
| `project.coqdoc` | `rocq doc` produces the HTML |
| `make.build` | the same project built the usual way: `rocq makefile -f _RocqProject` + `make -j`, every theorem closed |
| `make.coq_makefile` | the same sources built from `_CoqProject` by the `coq_makefile` compatibility binary and `make` |
| `extract.generate` | `Extract.v` extracts `isort gcd log2 interleave compile run eval cfold mirror to_list` to `ocaml/verified.ml(i)` |
| `extract.ocamlc-run` | `ocamlfind ocamlc` compiles it with `ocaml/main.ml`; the bytecode program's output equals `ocaml/expected.txt` |
| `extract.ocamlopt-run` | the same with `ocamlfind ocamlopt` (native code) |
| `dune.rocq-theory` | `cases/dune`: dune's Rocq build language (`(using rocq 0.11)`), a `rocq.theory` and a second one depending on it |
| `dune.print-assumptions` | the dependent theory's corollary is closed under the global context |
| `dune.rocq-extraction-byte` | a `rocq.extraction` stanza and an OCaml `executable` using the extracted module, bytecode mode: prints `sum upto 100 = 5050` |
| `dune.rocq-extraction-native` | the same executable in native mode |
| `dune.coq-theory` | `cases/dune-coq`: the deprecated `(using coq 0.10)` / `coq.theory` still builds |
| `negative.*` | see below |

The `cases/make/theories/` files:

- `Trees.v`: a polymorphic inductive `tree`, structural `Fixpoint`s, proofs
  by induction with `lia`, `congruence`, `injection`.
- `Compiler.v`: expressions, a stack machine, a compiler proved correct by
  a generalised induction, and a constant folder proved semantics-preserving.
- `Sort.v`: insertion sort, proved `Sorted le` and a `Permutation`.
- `Recursion.v`: Euclid's `gcd` by `Function … {measure}` with
  `functional induction`, proved the greatest common divisor (the goal
  auto-wp escalates from SMT to Coq in `coq-escalation.md`) and equal to
  `Nat.gcd`; `log2` by `Function … {wf lt}`; `Program Fixpoint` with a
  measure; `Program Definition` with subset types; explicit `Fix` with its
  unfolding lemma from `Fix_eq`.
- `Ssr.v`: ssreflect tactics (`elim:`, `case:`, `move=> /andP`, `have`,
  `rewrite /=`, `by`) from `Stdlib.ssr`.
- `Tactics2.v`: an Ltac2 proof, `lia` on `Z`, `nia`, `ring`, `field` on
  `Q`, `btauto`, `tauto`, `firstorder`, `vm_compute`, `native_compute`.
- `Extract.v`, `Audit.v`: see the table.

### Negative cases

Each file in `cases/negative/` starts with `(* EXPECT-FAIL: <ERE> *)` or
`(* EXPECT-OK: <ERE> *)`. For `EXPECT-FAIL`, `coqc` must exit non-zero,
print an `Error:` and match the ERE (output flattened to one line). For
`EXPECT-OK`, `coqc` must succeed and its `Print Assumptions` output must
match the ERE and must not say *Closed under the global context*. An
anomaly, an uncaught exception, a stack overflow or a timeout is always a
failure, never a pass.

| Case | Expected |
|---|---|
| `false_lemma_lia` | `n + 1 <= n` by `lia`: *Cannot find witness* |
| `false_lemma_refl` | `2 + 2 = 5` by `reflexivity`: *Unable to unify "5" with "2 + 2"* |
| `false_lemma_induction` | `rev l = l` by induction: *Unable to unify "x :: l" with "l ++ [x]"* |
| `incomplete_proof` | `Qed` with an open goal: *Attempt to save an incomplete proof* |
| `admitted` | `Admitted` compiles, but `Print Assumptions` of a theorem using it lists the admitted lemma under *Axioms:* |
| `axiom` | a smuggled `Axiom cheat` and Stdlib's `classic` both appear under *Axioms:* |
| `ill_typed`, `ill_typed_app` | *The term … has type … while it is expected to have type …* |
| `nonstructural` | `Fixpoint log2` recursing on `Nat.div2 n`: *Recursive definition of log2 is ill-formed* … *Recursive call to log2 has principal argument* |
| `nonterminating` | `{struct n}` on `loop n`: *Recursive definition of loop is ill-formed* |
| `positivity` | `C : (bad -> nat) -> bad`: *Non strictly positive occurrence of "bad"* |
| `missing_library` | *Unable to locate library … NoSuchModule* |
| `mutant_sort` | an `insert` that drops duplicates; the correct sort's permutation proof fails exactly on the duplicate branch: *Unable to unify "y :: l" with "x :: y :: l"* |

## Fixed SDK defect (2026-11-02)

The first runs found no `make` and no C compiler in the workshop on either
base, and no `as` on 24.04: `setup-base` installed only `libgmp10 zlib1g
python3 ripgrep`, and `build-essential` was only a build package. So
`env.build-tools`, `make.build`, `make.coq_makefile`, `extract.ocamlopt-run`
and `dune.rocq-extraction-native` failed (`timeout: failed to run command
'make'`, `sh: 1: as: not found`). Adding `make gcc` fixed the first three;
the native links then failed on `cannot find -lm` until `libc6-dev` was
added too. `setup-base` now installs `make gcc libc6-dev`, and the suite
passes 35/35 on ubuntu@24.04 and ubuntu@26.04.

## Notes

- The SDK has no MathComp, no Rocq MCP server and nothing sets
  `$ROCQ_SCRIPTS` (the `rocq` skill lists it as required); the skill is left
  with `coqc` alone. The ssreflect tactics come from `Stdlib.ssr`, not
  MathComp (no `ssrnat`, `seq`, …).
- `lia` does not see through `Nat.div2` (`1 <= S (Nat.div2 m)` fails with
  *Cannot find witness*); `Recursion.v` rewrites it to `/ 2` first.
- With `Program.Wf` imported, `Fix_eq` is Program's lemma about `Fix_sub`;
  the one about `Fix` is `Init.Wf.Fix_eq`.
- The native compiler is not configured (`COQ_NATIVE_COMPILER_DEFAULT=no`):
  `native_compute` falls back to the VM.
