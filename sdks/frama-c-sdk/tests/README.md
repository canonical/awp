# frama-c-sdk tests

Real Frama-C/WP verification work in a throwaway workshop that uses the
`frama-c-sdk` SDK: positive cases that must prove completely, negative cases
whose named goal must stay unproved, each prover on its own, a Coq proof
script driven through WP, a macsl (HAPPY) meta-property, and the patched
frontend. `sdks/test-sdk.sh frama-c-sdk` only smoke-tests one `inc`.

## Run

```sh
cd sdks/frama-c-sdk && ./prepare.sh && sdkcraft try   # packs try-frama-c-sdk (both bases)
sdks/frama-c-sdk/tests/run.sh                          # ubuntu@24.04
BASE=ubuntu@26.04 sdks/frama-c-sdk/tests/run.sh
KEEP=1 ...          # keep the workshop (framac-tests) for inspection
LOGDIR=/some/dir ...  # save every check's output as <check>.log
SDK=frama-c-sdk ... # test a store SDK instead of try-frama-c-sdk
```

The script creates a temporary project with `.workshop/framac-tests.yaml`
(base `$BASE`, SDK `try-frama-c-sdk`), copies `cases/` into it (mounted at
`/project`), launches the workshop, runs each check in a fresh copy of the
cases, prints `PASS:`/`FAIL:` per check and a `SUMMARY:` line, and removes the
workshop (unless `KEEP=1`). Exit status 0 only if every check passed. The
launch takes several minutes (the SDK's `setup-base` installs packages).

WP runs as the `frama-c` skills run it: `frama-c -wp -wp-rte -wp-timeout 10`,
with `-wp-cache none` so no cached verdict can mask a prover.

A positive check passes only if frama-c exits 0, prints no error, and reports
`Proved goals: N / N` with N > 0. A negative check passes only if frama-c exits
0 with no error (so a parse error or a crash is a FAIL), reports fewer proved
goals than goals, **and** lists the expected goal as unproved.

## Checks

| check | what it proves |
|---|---|
| `launch`, `health` | the workshop launches and reaches `ready` (the SDK's `check-health`) |
| `versions` | Frama-C 32.1, Why3 1.8, Alt-Ergo 2.6.4, Z3 on `PATH` |
| `wp-detect` | `frama-c -wp-detect` lists Alt-Ergo 2.6.4, Z3 and Coq 8.20.1 |
| `why3-provers` | `why3 config list-provers` has Coq 8.20.1, Alt-Ergo, Z3, nothing partial |
| `no-coqc-on-path` | the switch's Coq is not exported (it would shadow rocq) |
| `patched-sources` | `$FRAMA_C_SDK_SRC` holds the patched sources; WP's `cbits.mlw` has `land_le_l` |
| `alt-ergo-licence` | `share/licenses/alt-ergo/` has `LICENSE.md` and `OCamlPro-Non-Commercial-License.txt` (spec open point 11) |
| `why3-prove` | `why3 prove -P alt-ergo` and `-P z3` on `cases/why3/arith.mlw`, without Frama-C |
| `arrays` | `cases/arrays.c`: find max, linear search, binary search on a sorted array (overflow-safe midpoint), memset, a bounded sum; loop invariants, loop assigns, variants, behaviors |
| `pointers` | `cases/pointers.c`: swap and a caller, `\valid`, `\separated` arrays and scalars, struct fields, `assigns` |
| `rte` | `cases/rte.c`: array bounds, division (`INT_MIN / -1` excluded), `INT_MIN` negation, overflow-free sums and midpoints, an unsigned shift, unsigned wrap |
| `behaviors` | `cases/behaviors.c`: named behaviors with `complete`/`disjoint` |
| `rte-goals`, `behavior-goals` | `frama-c -rte` really emits signed-overflow, index-bound, division-by-zero and shift assertions on `rte.c`; WP's JSON report (`-wp-report-json`) has the `complete`/`disjoint` goals of both functions of `behaviors.c` |
| `prover-alt-ergo`, `prover-z3` | `pointers.c behaviors.c` proved by `-wp-prover alt-ergo` alone, then `z3` alone; WP's summary credits only that prover (`arrays.c` is not used: Z3 5.1.0 alone times out on a `binary_search` invariant at 10 s, which Alt-Ergo proves) |
| `prover-why3` | `pointers.c` with the exact Why3 prover names `-wp-detect` prints (`Alt-Ergo:2.6.4,Z3:5.1.0`); WP 32.1 runs every prover through Why3, and the skills use `alt-ergo,z3` |
| `machdep-x86_64` | `arrays.c pointers.c` with `-machdep gcc_x86_64`, as the skills run kernel units |
| `neg-wrong-post` | `cases/neg/wrong_post.c`: `ensures wrong_post` (off by one) unproved |
| `neg-wrong-post-right-proved` | the correct `ensures right_post` of the same file is proved |
| `neg-off-by-one` | `cases/neg/off_by_one.c`: the loop writes `s[n]`; `rte_mem_access` unproved |
| `neg-missing-loop-assigns` | `cases/neg/missing_loop_assigns.c`: `loop assigns i` only; the loop assigns goal unproved |
| `neg-overflow` | `cases/neg/overflow.c`: unbounded `a + b`; `rte_signed_overflow` unproved |
| `neg-not-separated` | `cases/neg/not_separated.c`: no `\separated(p, q)`; `ensures q_unchanged` unproved |
| `neg-not-complete`, `neg-not-disjoint` | `cases/neg/behaviors.c`: behaviors missing `x == 0`, and overlapping at `x == 5` |
| `macsl-list-contexts` | `frama-c -load-module "$FRAMA_C_SDK_MACSL" -macsl-list-contexts` |
| `macsl-instrumented` | `-macsl-print` on `cases/macsl.c` shows a `no_tamper: meta:` assertion at every write site (the non-vacuity gate of the `frama-c-monitoring` skill) |
| `macsl-prove` | `cases/macsl.c`: the `\writing` meta-property "nobody but `set_secret` writes `secret_reg`" proved by WP, run as the skill runs it (`-no-autoload-plugins -load-module … -load-plugin wp -macsl -wp`) |
| `neg-macsl` | `cases/neg/macsl.c`: `tamper()` writes `secret_reg`; its `no_tamper` assertion unproved, `set_pub`'s proved (the mandatory negative control) |
| `coq-smt-alone-fails` | `cases/coq/sum.c`: the lemma `sum_nonneg` needs induction; Alt-Ergo and Z3 cannot prove it |
| `coq-script` | the script `cases/coq/lemma_sum_nonneg.v` (induction with `natlike_ind`), copied into the WP session's `interactive/`, proves it with `-wp-prover coq` alone (the switch's Coq 8.20.1, through Why3); WP credits Coq with 1 goal |
| `coq-and-smt` | the whole file with `alt-ergo,z3,coq`: the lemma by Coq, `triangle` (which needs it) by SMT |
| `neg-coq-bad-script` | the same script with every `lia.` replaced by `idtac.` does not prove the lemma (the green above comes from the script) |
| `patch-gnu-zero-length-nonfinal` | `cases/patches/zero_length_nonfinal.c` parses (frama-c-patches 0002; stock 32.1 aborts) |
| `patch-return-void-expr` | `cases/patches/return_void.c` parses (`cabs2cil-c23-auto` fix 2; stock 32.1 rejects it) |

The `alt-ergo-licence` check fails on SDKs built before the licence files were
added to `files/share/licenses/alt-ergo/`; rebuild with `sdkcraft try`.
