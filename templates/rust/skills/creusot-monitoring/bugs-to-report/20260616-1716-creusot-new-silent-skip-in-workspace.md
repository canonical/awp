# `cargo creusot new/init` writes `why3find.json` next to a parent `Cargo.toml`, not in the new project

> Corrected 2026-10-28. The first version of this report said the scaffold step
> "silently skips" `why3find.json`. It does not: it writes the file into the wrong
> directory. Re-tested end to end and checked against the source (see **Cause**).
> The filename is kept so existing references still resolve.

- **Trigger:** three independent `creusot-sl` sub-agents scaffolding proof projects under
  `/tmp` during a `creusot-monitoring` run (a stray `/tmp/Cargo.toml` was present).
- **Expected:** `cargo creusot new <p>` / `cargo creusot init` creates a project that
  `cargo creusot` can verify, with `why3find.json` at the root Cargo will use, or fails
  with an error.
- **Actual:** when any parent directory contains a `Cargo.toml`, `new`/`init` prints only
  `Info: It seems that you are in a workspace (found <parent>/Cargo.toml).` and writes
  `why3find.json` **and a `.gitignore`** into `<parent>/`, not into `<p>/`. It does this
  whatever the parent `Cargo.toml` contains: a real workspace, an ordinary package, or an
  empty file. `cargo creusot` then looks for `why3find.json` in Cargo's workspace root,
  which is usually `<p>/`, and fails:
  - parent is a real workspace (or a package, with `[workspace]` added to `<p>`):
    `Error: <p>/why3find.json not found. Perhaps you are in the wrong directory, or you
    need to run cargo creusot init.`
  - parent is an empty file (the `/tmp` case): Cargo itself fails first,
    `cargo metadata ... failed to parse manifest at <parent>/Cargo.toml`.

  Side effect: if the new project is created inside an existing crate, `why3find.json` and
  `.gitignore` are added to that crate's source directory. The `.gitignore` is created only
  if none exists; existing files are never overwritten.
- **Cause** (`creusot-rs/creusot` @ `f15b985`, `cargo-creusot/src/new.rs`):
  `create_project` calls `find_parent_cargo_toml`, which walks up from the current
  directory and returns the first parent `Cargo.toml` without reading it. The parent's
  directory becomes the target for `why3find.json` and `.gitignore`. The prove step
  (`why3find_wrapper.rs`, `check_why3find_json_exists`) instead uses
  `cargo metadata`'s `workspace_root`. The two disagree whenever the parent is not
  actually the project's workspace root.
- **Minimal reproducer:**
  ```sh
  mkdir -p ~/ws-repro && cd ~/ws-repro
  printf '[workspace]\nmembers = []\n' > Cargo.toml
  cargo creusot new p          # Info: It seems that you are in a workspace ...
  ls                           # .gitignore  Cargo.toml  p  why3find.json   <- here, not in p/
  cd p && printf '\n[workspace]\n' >> Cargo.toml
  cargo creusot                # Error: .../p/why3find.json not found
  ```
- **Workaround** (verified: each variant below then proves the generated `add_one`):
  1. Scaffold outside any directory tree that has a `Cargo.toml`, and never inside the crate
     under verification.
  2. Otherwise add an empty `[workspace]` table to `<p>/Cargo.toml` **and** copy
     `$CREUSOT_DATA_HOME/why3find.json` (default `~/.local/share/creusot/why3find.json`)
     into `<p>/`, then delete the `why3find.json` and `.gitignore` that `new` left in the
     parent. `[workspace]` alone is not enough: Cargo then takes `<p>` as the root, but
     `why3find.json` is still in the parent.
- **Suggested fix:** use the same root as the prove step (`cargo metadata`'s
  `workspace_root`, or the new project when the parent is not a workspace that lists it),
  or print a warning naming the directory where `why3find.json` was actually written.
- **Versions:** first seen with cargo-creusot 0.13.0-dev, Why3 1.8.2+git, why3find
  v1.3.0+dev (alt-ergo 2.6.2, z3 4.15.3, cvc4 1.8, cvc5 1.3.1). Re-tested 2026-10-28 with
  cargo-creusot 0.15.0-dev (commit `f15b985`), Rust nightly-2026-08-03, Why3 1.8.2+git,
  why3find v1.3.0+dev (alt-ergo 2.6.4, z3 5.3.2, cvc4 1.8, cvc5 1.4.1), cargo 1.88.0.
- **Severity:** usability, not soundness. It can also modify the source tree of the crate
  being verified (the side effect above).
