# Real-use tests of the creusot SDK

`sdks/test-sdk.sh creusot` checks that the SDK installs and proves the
generated `add_one`. These tests go further: they verify small but real Rust
crates with Creusot inside a workshop that uses the SDK, check that bugs are
refuted, run each prover on its own, prove offline, and run `cargo test` on
the same code.

## Running

```sh
sdks/creusot/tests/run.sh                      # base ubuntu@24.04
BASE=ubuntu@26.04 sdks/creusot/tests/run.sh
KEEP=1 ...       # keep the workshop (prints how to remove it)
LOGDIR=dir ...   # where the per-case logs go (default: a new directory
                 # under ${TMPDIR:-/tmp}, printed at the end)
```

`try-creusot` must already be packed in the try area for the base
(`make sdk-creusot`); `run.sh` does not build it. It creates a temporary
project with `.workshop/creusot-tests.yaml`, launches workshop `creusot-tests`,
and removes it on exit unless `KEEP=1`. A run takes 4 to 11 minutes (the
launch is 0.5 to 7 of them; the tests themselves about 3.5).

Output: one `PASS:`/`FAIL:` line per check, `INFO:` lines with timings, and a
final `SUMMARY: <n> passed, <m> failed`. Exit status 0 only if every check
passed.

## How it works

- `run.sh` (host): writes the workshop definition, copies `cases/` and
  `in-workshop.sh` into the project (`/project` in the workshop), launches,
  checks the workshop is `ready` with the SDK from the try area, runs
  `in-workshop.sh` as the workshop user in a login shell, counts its
  `PASS:`/`FAIL:` lines, and copies its logs back to `LOGDIR`.
- `in-workshop.sh` (workshop): copies each case to `/tmp/creusot-tests/<case>`
  (never under `/project`: `cargo creusot new/init` would write
  `why3find.json` next to a parent `Cargo.toml`), adds `why3find.json` with
  `cargo creusot init` as for any existing crate, and runs `cargo creusot`.
  All cases share one `CARGO_TARGET_DIR`, so `creusot-std` is compiled once.
- Each case in `cases/` is a stand-alone Cargo crate (`Cargo.toml`,
  `src/lib.rs`, as `cargo creusot new` writes them) plus an `expect` file:
  `proved <function>` or `failed <function>`, one per line; the function is
  the path of its `.coma` file under `verif/<crate>_rlib/` (for example
  `impl_Bounded/incr`).

## why3find calibration under load

The first time a goal is not discharged in the fast pass, why3find measures
each prover's speed on a calibration goal (5 s budget, from the `profile` of
`why3find.json`). On a heavily loaded host that goal can overrun and why3find
aborts with `Warning: Prover alt-ergo@ did not stop properly on goal
calibration[alt-ergo]` / `Error: can not calibrate prover alt-ergo@ (N=17,
Failed)`, whatever the crate (seen once on ubuntu@24.04 at load average 14,
on `overflow`). `in-workshop.sh` retries a `cargo creusot` run once when, and
only when, its log has `can not calibrate prover`, prints an `INFO:` line
saying so, and keeps the first log as `<log>.calib`.

## Checks

| Check | Passes when |
|---|---|
| `launch`, `health` | the workshop launches and reaches `ready` with `creusot` from the try area |
| `offline.prove` | a crate named `smoke` with the SDK's `share/smoke/Cargo.lock` and the `binsearch_reverse` code proves its 3 functions with `CARGO_NET_OFFLINE=true` and the HTTP proxies pointed at a closed port; run first, while `~/.cargo` holds only the SDK's registry seed |
| `offline.cargo-test` | `cargo test` passes in the same crate, offline |
| `offline.lock-unchanged` | Cargo did not rewrite the shipped `Cargo.lock` |
| `<case>.prove` | `cargo creusot` exits 0, prints `Proved (<n> files) ✔` with n the number of `proved` lines, no `proof failed`, and each function has its `.coma` and `proof.json` |
| `<case>.cargo-test` | `cargo test` on the same crate (plain rustc, Creusot attributes erased) passes, with at least one test run |
| `loops.replay` | `cargo creusot --replay` replays the recorded proofs |
| `<neg>.refute` | `cargo creusot` exits non-zero, compilation succeeded (no `error`), why3find reports a failed proof, each `failed` function is reported as `Goal Coma.vc_<fn>: ✘`, and no other goal fails. A crash or a compile error is a FAIL |
| `<neg>.proves-<fn>` | the correct function of the negative crate proves on its own (`cargo creusot verif/<crate>_rlib/<fn>.coma`) |
| `prover-<p>.prove` | with `why3find.json` restricted to the single prover p (`"provers": ["p"]`), `loops` proves and every `proof.json` names only p; for alt-ergo, z3, cvc5 and cvc4 (no cvc4 on arm64: the SDK has none) |
| `prover-<p>.refute` | restricted to p, `max_wrong_spec` is still not proved and `max_ok` is |
| `sdk-untouched` | nothing under `/opt/creusot/` (the SDK) changed during the run |

## Cases

Positive (everything proved, and `cargo test` passes):

| Case | What it exercises |
|---|---|
| `loops` | `while` loops with invariants and variants under `#[check(terminates)]` (a triangular sum with a non-linear invariant, a countdown with a `snapshot!`), `for` loops over ranges with `produced`, writing through `&mut Vec` with `^v` |
| `binsearch_reverse` | binary search over a sorted slice (`Result<usize, usize>`, quantified pre/postconditions, `lo + (hi - lo) / 2`), in-place reversal with `swap`, argmax over a `Vec` |
| `sort` | insertion sort on `&mut [i32]`: result sorted and `permutation_of` the input, nested loops |
| `lemma_ghost` | a recursive logic function with a variant, a lemma proved by induction and used in a `proof_assert!`, `ghost!` code with an `Int` ghost counter, snapshots |
| `overflow` | arithmetic overflow handled: a bounding precondition, `checked_add`, `saturating_add`, `wrapping_add` (specs from creusot-std), an overflow-free midpoint, `abs` excluding `i32::MIN` |
| `tyinv_model` | type invariants (`impl Invariant`) on a bounded counter and a bounded stack, logical models (`impl View`, the `@` notation), a client reasoning only on the model |

Negative (the bug must be reported; the correct twin in the same crate must
prove):

| Case | Bug that must be refuted | Correct twin |
|---|---|---|
| `neg_wrong_spec` | `max` specified as a minimum | `max_ok` |
| `neg_off_by_one` | `while i <= s.len()` then `s[i]` (out of bounds) | `contains_ok` |
| `neg_missing_invariant` | zeroing loop without the element invariant | `zero_ok` |
| `neg_overflow` | `(lo + hi) / 2`, and `x * x` with no bound | `midpoint_ok` |
| `neg_tyinv` | a method and a constructor breaking `value <= max` | `incr_ok` |
| `neg_variant` | a variant that does not decrease when `n` is odd | `countdown_ok` |
