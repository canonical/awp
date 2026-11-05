# Review of `workshop-autowp-rust-base-spec.md` (2026-10-31)

Reviewed against: the Creusot checkout at `f15b98593980ce264a681a275b204891d03e9608`
(`/home/fabrice/git/creusot`, read-only), `templates/rust/skills/creusot/references/install.md`,
`tests/rust/provision.sh`, `auto-wp.md` §4.3.5–4.3.6, `/home/fabrice/git/use-creusot/`,
the C spec (§1, §2, §11), `sdks/autowp-lean/`, `sdks/autowp-rocq/`, `sdks/autowp-framac/hooks/`,
`sdks/test-sdk.sh`, and the host installation of the same commit (`cargo creusot version`,
`cargo creusot config`, `ldd creusot-rustc`, `~/.rustup`, `~/.cargo`). Web sources: coreutils
NEWS, rustup CHANGELOG and `src/toolchain.rs`, cargo `src/bin/cargo/main.rs` and the cargo
reference, Alt-Ergo `LICENSE.md` at `v2.6.4`.

## Summary verdict

The spec reads Creusot's installer and `cargo-creusot` correctly in almost every detail
(paths, `$CREUSOT_DATA_HOME`, the local opam switch, `RUSTUP_TOOLCHAIN`/`RUSTC`, prover
resolution through `$DATA/bin`, the `[patch]` mechanism, the workspace pitfall), and the
SDK shape (fixed `/opt` path, hand-written environment, `runuser` health check, mount plugs)
follows the three built SDKs. It is not buildable as written, though: **no step ever sets a
default rustup toolchain**, so the first `cargo creusot` of the build (step 5) and every
hook that goes through the `cargo` proxy fail. Four further points would make a check
vacuous or a stated property false: the step-6 prune experiment reuses cargo's cache, the
"offline first proof" needs `CARGO_NET_OFFLINE`, `cargo creusot version` does not print
CVC5 in the format the checks expect, and `cp --no-clobber` exits non-zero on Ubuntu
24.04 (coreutils 9.4) when it skips a file. Two factual claims are wrong (`cargo-creusot`
on PATH cannot be shadowed; `why3` is on PATH). The rest is nuance and wording.

## Blocking

1. **No default toolchain is set, so every `cargo creusot` through the rustup proxy fails** (§3 step 2 and step 5, §4.2, §4.3, §6 `cargo-test`).
   - Problem: `rustup-init … --default-toolchain none` installs no default; the auto-install triggered by `rust-toolchain` (step 2) installs the nightly but does not make it the default. Outside the Creusot checkout (the smoke project of step 5, the hooks, the user's shell) `cargo` is the rustup proxy, which refuses to run without a default or an override ("rustup could not choose a version of cargo to run"). `cargo creusot` itself is launched through that proxy; `cargo-creusot` then calls `cargo` again (`cargo-creusot/src/main.rs:141-162`) with `RUSTUP_TOOLCHAIN` set, which only helps the inner call. §4.2 asserts "The default toolchain is the nightly" but nothing produces that state, and the seeded `settings.toml` would carry whatever the build left.
   - Evidence: `rustup-init` flags in §3 step 2; `cargo-creusot/src/main.rs:24` (`parse_from(std::env::args().skip(1))`, i.e. the binary expects to be run by cargo) and `:141-162`; host `~/.rustup/settings.toml` shows `default_toolchain` is how rustup picks one.
   - Fix: after `./INSTALL`, `rustup default nightly-2026-08-03` (or install explicitly: `rustup toolchain install nightly-2026-08-03 --profile minimal -c rustfmt -c rustc-dev -c llvm-tools && rustup default nightly-2026-08-03`), and in `setup-project` re-assert it after seeding (`rustup default …`, see major 4). Do not set `RUSTUP_TOOLCHAIN` in `profile.d`: it would override the crate's own `rust-toolchain.toml` (§1 property 3). For the hooks, `cargo-creusot creusot config --update` and `/opt/autowp-creusot/bin/cargo-creusot creusot version` also work without the proxy (argv[1] is skipped), which makes `setup-project` independent of the default.

## Major

2. **Step 6's "rerun the smoke proof" after removing `rustc-dev`/`llvm-tools` proves nothing** (§3 step 6, §10.1).
   - Problem: rerunning `cargo creusot` in the same smoke project reuses `target/creusot/` (cargo's fingerprints are unchanged: same `creusot-rustc` binary, same sources), the `verif/*.coma` files and the `.why3find` cache; `creusot-rustc` is not executed again, so the proof "still proves" whether or not `librustc_driver` is loadable.
   - Evidence: `cargo-creusot/src/main.rs:170-175` (`CARGO_TARGET_DIR=target/creusot`, `CARGO_INCREMENTAL=0` only); `why3find_wrapper.rs:81-83` (`--no-cache` is opt-in). On the host, `ldd creusot-rustc` gives `librustc_driver-6b1d913cde17a464.so => not found`; the library is found at run time only because rustup's proxy prepends `<toolchain>/lib` to `LD_LIBRARY_PATH` (rustup `src/toolchain.rs`, `set_ldpath`), and it lives in `<toolchain>/lib/` (the `rustc` component; `lib/rustlib/components` on the host lists `rustc` and `rustc-dev` separately) — so the spec's expectation is plausible, but the experiment as written cannot confirm it.
   - Fix: run the second proof in a fresh `cargo creusot new smoke2` directory (or `rm -rf target verif .why3find` first), and also run `cargo test` there, since §6 relies on the plain toolchain too.

3. **"The network is not needed" for the first proof is not true as written** (§2 last row, §4.3 check 3, §5 "Lace needs targets and offline work").
   - Problem: `cargo creusot new` generates a project with no `Cargo.lock`; `cargo metadata` (`Runner::new`, `main.rs:63-66`) and `cargo check` must resolve `creusot-std`'s dependency graph from the registry index. Cargo only guarantees offline use after `cargo fetch` "if a `Cargo.lock` file is available … unless the lock file changes", and without `--offline` it "will stop with an error if it needs to access the network and the network is not available" (cargo-fetch and config references). The seed makes the data available; nothing tells cargo to use it without asking crates.io.
   - Fix: run the health check and the tests with `CARGO_NET_OFFLINE=true` (do not put `[net] offline = true` in the user's `config.toml`: it would break every real crate), and ship the smoke project's `Cargo.lock` in `files/` so the offline resolution is exactly what the seed holds. State in §5 that a crate's own first build still needs the network (the spec says this) and that the offline guarantee is "with `CARGO_NET_OFFLINE=true`".

4. **`cp -a --no-clobber` fails the hook on Ubuntu 24.04 and keeps a stale default toolchain** (§4.2 first bullet).
   - Problem (a): coreutils 9.2 made `cp -n` "exit with nonzero status if they skip their action because the destination exists"; 9.5 reverted it. Ubuntu 24.04 ships coreutils 9.4, so on `noble` a seed into a non-empty mount (every refresh that ships a new nightly: the guard "when the nightly is not already there" lets the copy run, and `settings.toml`, `~/.cargo/bin/*`, the registry index all exist) exits 1 and aborts a `set -e` hook. On 26.04 (host: coreutils 9.7) it is silent. coreutils' own NEWS (9.5) says "-n,--no-clobber … is best avoided due to platform differences".
   - Problem (b): with no-clobber semantics, the user's old `settings.toml` is kept, so after a refresh to a revision with another nightly the default is still the previous one; the old nightly is never removed either.
   - Problem (c): the spec says this is "as `autowp-lean` seeds `~/.elan`", but `sdks/autowp-lean/hooks/setup-project` uses a guard plus a plain `cp -a`, not `--no-clobber`.
   - Fix: `cp -a --update=none` (coreutils ≥ 9.3, exit status unaffected) or `rsync -a --ignore-existing`; then `rustup default nightly-2026-08-03` unconditionally in `setup-project`; and say "like `autowp-lean`'s guard, with …" rather than claiming the same command.

5. **`cargo creusot version` does not print CVC5 the way §2, step 5, §4.3 (1) and §6 expect** (§2 "the versions … are the expected ones (install.md §4)").
   - Problem: at this commit the CVC5 detector expects the prefix `This is cvc5 version` (`creusot-setup/src/tools.rs:140-146`), but cvc5 1.4.1 prints `cvc5 1.4.1 [git …]`. On the host, `cargo creusot version` prints four lines for it: `cvc5 bad CVC5 version: cvc5 1.4.1 [git 2b2e844 on branch HEAD]`, `compiled as a unrestricted build …`, a copyright line, then ` (recommended 1.4.1)` is appended. `install.md` §4's table (`CVC5 | 1.4.1`) is idealised. A check written as "the line `cvc5 1.4.1`" or "no `(recommended` marker" fails the build (step 5 says the build fails otherwise).
   - Fix: write the checks as `grep -q 'cvc5 1.4.1'` (matches inside the message), note the format in §2, and record it as a Creusot upstream nit; or check `cvc5 --version | head -1` directly from `$DATA/bin`.

6. **`cargo-creusot` in `/opt/autowp-creusot/bin` can be shadowed by `~/.cargo/bin`; the spec claims the opposite** (§4.1 PATH bullet).
   - Problem: cargo looks up external subcommands with `search_directories`, which inserts `$CARGO_HOME/bin` at position 0 unless PATH already contains it (cargo `src/bin/cargo/main.rs`); rustup's proxy also prepends `$CARGO_HOME/bin` to PATH (`set_ldpath`). So a `cargo install cargo-creusot` into `~/.cargo/bin` *does* win, whatever `profile.d` does.
   - Fix: drop the claim; make health check 1 verify the first line `cargo-creusot 0.15.0-dev` and that `~/.cargo/bin/cargo-creusot` does not exist (or that it is the SDK's, if you decide to seed it there — then the refresh must overwrite it, which conflicts with the no-clobber seeding). Alternatively put `/opt/autowp-creusot/bin` on PATH *and* have cargo see `~/.cargo/bin` after it by listing `$HOME/.cargo/bin` explicitly in PATH (cargo then keeps the user's order), which is what the spec's PATH already does — but only for cargo's lookup, not for rustup's proxy, so the claim still cannot be made absolute.

7. **`why3 --version` (§6 `tools` row) is not on PATH** (§4.1, §6).
   - Problem: §4.1 puts `/opt/autowp-creusot/bin` (cargo-creusot) and `~/.cargo/bin` on PATH; `why3`, `why3find` and the provers are in `$DATA/bin` = `/opt/autowp-creusot/data/bin` (symlinks to `data/_opam/bin/`, `creusot-install/src/main.rs:210-211`), which is only prepended by `cargo-creusot` for its own children (`why3find_wrapper.rs:91-96`, `why3_launcher.rs:30-33`).
   - Fix: call it by path in the test (`/opt/autowp-creusot/data/bin/why3 --version`), and say in §4.1 that `$DATA/bin` is deliberately not on PATH: in a combined workshop it would collide with `autowp-framac`'s `why3`, `alt-ergo` and `z3` wrappers (both profiles prepend; `profile.d` order is alphabetical, so `autowp-framac.sh` would win anyway).

8. **Health check cost and content** (§4.3).
   - Check 2: `cargo creusot config` in check mode always exits 0 and only prints (`config.rs:88-125`): `No problems found.`, `… may be out of date …`, `No … needed …`, or `no path found …`. The check must `grep -qx 'No problems found.'`. Also, the compared path is the parent of cargo-creusot's compile-time `CARGO_MANIFEST_DIR` (`config.rs:132-139`) or `$CREUSOT_PATH`, not `$AUTOWP_CREUSOT_SRC`; §4.2's "pointing at `$AUTOWP_CREUSOT_SRC/creusot-std`" holds only because step 1 builds at that path. Say so.
   - Check 3 compiles `creusot-std`, `creusot-std-proc`, `pearlite-syn`, `syn`, `uuid` … with `creusot-rustc` and then proves: minutes, on every launch and refresh. Whether Workshop bounds a hook's run time is unverified (not in the docs read for the C spec). Consider leaving the proof to `test-sdk.sh` and keeping `check-health` to version + config + `creusot-rustc --version` through the proxy (`RUSTUP_TOOLCHAIN=nightly-2026-08-03 cargo … ` or `rustup run nightly-2026-08-03 "$DATA/toolchains/nightly-2026-08-03/bin/creusot-rustc" --version`, which exercises the `librustc_driver` loading).
   - Check 4 is redundant and expensive: `$SDK` is root-owned, so a write attempt fails and surfaces in check 3; `find "$SDK" -newer …` walks several GB of small files. Drop it, or use `-print -quit`.

9. **Registry seed scope** (§2 last row, §3 step 7).
   - Problem: the build runs `cargo run`/`cargo install` with `CARGO_HOME=$R/cargo`, so `$CARGO_HOME/registry` already holds all 192 crates of Creusot's `Cargo.lock` plus extracted `src/` — several hundred MB — not "`creusot-std`'s crates.io dependencies".
   - Fix: build the seed in a fresh home: `CARGO_HOME=$R/seed/cargo cargo fetch` in the smoke project after copying the `[patch]` `config.toml` into that home (without it cargo would look for `creusot-std 0.15.0-dev` on crates.io and fail), then delete that `config.toml` and `registry/src/` (cargo re-extracts from `registry/cache/`).

10. **Alt-Ergo's licence is now known, and it blocks redistribution** (§8, §10.5).
    - Evidence: `LICENSE.md` at tag `v2.6.4`: the OCaml sources and the GitHub/opam releases are under the *OCamlPro Non-Commercial Purpose License*; Apache-2.0 only for Alt-Ergo Club Gold members; a separate `-free` release exists under CeCILL-C v1 on opam. The binary `./INSTALL` downloads is the non-commercial one.
    - Fix: turn open point 5 into a decision: either build Alt-Ergo in the switch from the free release (`opam install alt-ergo-free`, check that its version matches the `alt_ergo_26` driver of `creusot_why3.conf`) and pass `--external alt-ergo` to `./INSTALL`, or ship without Alt-Ergo (the strategy in `creusot_why3.conf` and `why3find.json` lists four provers; the smoke proof passes with Z3/CVC5 — to be confirmed) and document it. The same applies to `autowp-framac` (its Alt-Ergo 2.6.4 comes from opam, same licence).

## Minor

11. §1 property 2: `cargo creusot` also writes `verif/` (the coma output, `OUTPUT_PREFIX`, `main.rs:332`), `_creusot_erasure/` (`main.rs:86-88`), the `.why3find/` cache, and on `new`/`init` `why3find.json` and `.gitignore` — all in the project, so the property holds, but list them (the overlay `.gitignore` the skills generate must cover them).
12. §1 table "user config … written again by every `cargo creusot` run if missing": only by runs that reach the prove stage (`why3find_wrapper.rs:114`) and by `cargo creusot why3` (`why3_launcher.rs:26`); `--only coma` does not. And `why3find prove` never reads that file (it gets `-j` and `WHY3CONFIG=$DATA/creusot_why3.conf`, `why3find_wrapper.rs:72-98`); only `cargo creusot why3 ide|replay` passes it with `-C`. So §4.2 bullet 3 has little value, there is no `cargo creusot` subcommand that writes only that file, and "so the first proof does not race the first launch" is unclear. Either drop the bullet or write the five lines by hand (format: `creusot-setup/src/lib.rs:131-136`, `running_provers_max = $(nproc)`).
13. §1 "the `[patch]` path needs the whole Creusot source tree": true, and for a stronger reason than workspace inheritance: `creusot-std` depends on `creusot-std-proc = { path = "../creusot-std-proc" }`, which depends on `pearlite-syn = { path = "../pearlite-syn" }` (`creusot-std/Cargo.toml:21`, `creusot-std-proc/Cargo.toml:30`).
14. §1 table: the installer's download cache is `~/.cache/creusot` (`CreusotPaths::cache_dir`, `creusot-setup/src/lib.rs:27`), not under `$CREUSOT_DATA_HOME`; harmless in the build container, but step 6's prune list and §10.2 could note that `$DATA` holds no cache.
15. §3 step 2: "the first `cargo` in the checkout installs the nightly" relies on rustup's auto-install, removed in 1.28.0 and restored in 1.28.1 (`RUSTUP_AUTO_INSTALL=0` and `rustup set auto-install disable` turn it off). Install the toolchain explicitly (see blocking 1). Also say where `rustup-init` comes from and how it is pinned (`static.rust-lang.org/rustup/dist/x86_64-unknown-linux-gnu/rustup-init` with a sha256; Ubuntu 24.04 also packages `rustup` 1.27.1).
16. §3 `build-packages`: Why3 from git needs `autoconf` (`conf-autoconf {build & dev}` in its opam file; `conf-autoconf.0.2` is in the host switch). opam's depext would install it in the build container, but the list should be complete; the GTK/cairo `conf-*` packages are correctly avoided through `in-creusot-ci`.
17. §3 step 1: as `autowp-rocq` does, `rm -rf "$R"` first, and name the source location (`$CRAFT_PART_SRC` or the part's build directory).
18. §3 `source-commit: f15b98593…`: the full id is known, `f15b98593980ce264a681a275b204891d03e9608`.
19. §3 `license: LGPL-2.1-only`: Creusot's crates declare `LGPL-2.1-or-later` (`creusot/Cargo.toml:6`, `creusot-std/Cargo.toml:6`); use that.
20. §4.1: write the profile from `files/autowp-creusot.profile` with `install -m 644` as the three SDKs do, leaving `$HOME` unexpanded and using their idempotent `case ":$PATH:"` pattern.
21. §6 `mutant` row: `#[ensures(result == x + 1u32)]` uses machine-integer arithmetic in Pearlite; the generated template uses the `@` idiom (`#[requires(a@ < i64::MAX@)] #[ensures(result@ == a@ + 1)]`, `cargo-creusot/src/new.rs:86-93`). Prefer `#[requires(x@ < u32::MAX@)] #[ensures(result@ == x@ + 1)]` with body `x + 2`; whether `x + 1u32` is accepted was not verified.
22. §2 "Creusot sources | the same tree without `target/`": also without `.git/` (step 6), which is why `git rev-parse` (step 5) must precede the prune — it does; say it.
23. `creusot-launch` does not exist yet (`templates/rust/skills/` has no such directory; `auto-wp.md` §4.3.7 roadmap step 1). The introduction lists it among the skills served, and §4.1, §7 and §9 speak of "`creusot-launch`'s toolchain check" and `creusot-launch/SKILL.md` as existing documents. Mark them "to be written".
24. §5 "the nightly of the older Creusot it was run with": `use-creusot` records no Creusot commit (its README only says Creusot was installed and verified); unverified, say "presumably".
25. §9 "`workshop-autowp-c-base-spec.md`: open point 7 points here": already done in the uncommitted diff.
26. §7 channel `0.15/stable`: fine, but note that `0.15.0-dev` is a pre-release of a version not yet released; a future `0.15.0` release would share the track with these `-dev` revisions.

## Editorial

27. §1 table, row "Why3": "a **local opam switch** with OCaml 5.3.0, Why3 `git-05bf4ddf` (1.8.2+git), why3find `git-0f054b93` (Creusot's fork), and `why3-ide` unless …" — long; split the IDE clause into its own sentence under the table.
28. §1 last paragraph: the sizes are confirmed (see the verified list); add that `lib/rustlib/x86_64-unknown-linux-gnu/lib` alone is 967 MB on the host, which is where `rustc-dev`'s rlibs live — the saving step 6 is after.
29. §3 step 7: "move `$CARGO_HOME/bin` (rustup's proxies; `cargo-creusot` goes to `$R/bin`)" reads as if `cargo-creusot` were a proxy; rewrite: "move `$CARGO_HOME/bin` to the seed after taking `cargo-creusot` out of it into `$R/bin`".
30. §4.2 bullet 3: "by running the step `cargo creusot` runs itself" — no such step exists (minor 12); reword or drop.
31. §4.3 title "(as `workshop`, through `runuser -u workshop -- bash -lc`)" and §4.3's last line "the launch then aborts (C spec §11)" are correct; add that `bash -lc` is what makes `/etc/profile.d/autowp-creusot.sh` and `HOME=/home/workshop` apply.
32. §5 "Workspace pitfall": the cited file is `templates/rust/skills/creusot-monitoring/bugs-to-report/…`; give the `templates/rust/skills/` prefix once, as `auto-wp.md` does.
33. §6 table caption "after `make sdk-creusot` (`sdkcraft try`)" — consistent with the Makefile pattern (`cd sdks/<name> && sdkcraft try`, then `test-sdk.sh`); fine.
34. §8: "CVC5 BSD-3-Clause in general but the static binary `./INSTALL` downloads is the **GPL build**" — correct (`cvc5-Linux-x86_64-static-gpl.zip`); consider "CVC5: BSD-3-Clause, but the static binary `./INSTALL` downloads is the GPL build".
35. §10.1 "Step 6 decides whether those components can go" — point to the fixed experiment (major 2).

## Claims verified as correct

- Pinned commit `f15b985` = `f15b98593980ce264a681a275b204891d03e9608` (2026-10-27, "Say that VecDeque::index_mut leaves the other elements alone"); workspace version `0.15.0-dev` (`Cargo.toml:20`); `cargo-creusot 0.15.0-dev` printed on the host.
- `./INSTALL` runs `cargo run --bin creusot-install -- $ARGS $@` (`INSTALL:13`); `--external <tool>` exists (`creusot-install/src/main.rs:39-41`).
- `rust-toolchain`: `nightly-2026-08-03`, components `rustfmt`, `rustc-dev`, `llvm-tools`.
- `creusot-deps.opam`: `ocaml = 5.3.0`, `why3 = git-05bf4ddf`, `why3-ide = git-05bf4ddf & !?in-creusot-ci`, `why3find = git-0f054b93` (Creusot's fork, `github.com/creusot-rs/why3find`), optional `ocamlgraph`, `camlzip`, `zarith`; so defining the opam variable `in-creusot-ci` skips `why3-ide` and GTK. `opam var --global VAR=VALUE` is the opam ≥ 2.1 syntax (host opam 2.5 help).
- Why3 is a **local switch** at `$DATA/_opam` (`opam switch create -y $DATA`, `main.rs:193-208`), with `$DATA/bin/why3` and `why3find` symlinked to `_opam/bin/` (`:210-211`); host `$DATA` holds `_opam bin creusot-deps.opam creusot_why3.conf share toolchains why3find.json`, `bin/` holds `alt-ergo cvc4 cvc5 why3 why3find z3`.
- `$DATA` = `$CREUSOT_DATA_HOME` or `~/.local/share/creusot` (`creusot-setup/src/lib.rs:21-24`); config dir `~/.config/creusot` (not under `$DATA`); honoured by `creusot-install` and every `cargo-creusot` path (`main.rs:145`, `why3find_wrapper.rs`, `why3_launcher.rs`, `new.rs:131`).
- Prelude: `prelude-generator` into `target/creusot/packages/creusot/creusot`, installed to `$DATA/share/why3find/packages/creusot/creusot` (`main.rs:275-290`).
- `cargo install --path cargo-creusot` (→ `$CARGO_HOME/bin`) and `cargo install --path creusot-rustc --root $DATA/toolchains/nightly-2026-08-03` (`main.rs:228-247`).
- Provers: Alt-Ergo 2.6.4 (`alt-ergo-v2.6.4-x86_64-linux-musl`), Z3 5.3.2 (`z3-5.3.2-x64-glibc-2.39.zip`), CVC4 1.8, CVC5 1.4.1 (`cvc5-Linux-x86_64-static-gpl.zip`), sha256-checked (`tools_versions_urls.rs:18-36`, `main.rs:338-365`), into `$DATA/bin`. arm64 Linux: Z3 and CVC5 only (`:38-54`).
- `creusot_why3.conf` names provers by bare command (`alt-ergo`, `z3`, `cvc5`, `cvc4`); `cargo-creusot` prepends `$DATA/bin` to `PATH` for `why3find` and `why3`, and sets `WHY3CONFIG=$DATA/creusot_why3.conf`, `DUNE_DIR_LOCATIONS=why3find:lib:$DATA/share/why3find`, `--no-autodetect-provers`.
- `why3find.json` is copied by `cargo creusot new`/`init` (`new.rs:159-160`), next to the nearest parent `Cargo.toml` when one exists (`:152-157`, `:165-174`) — the workspace pitfall as `install.md` and `auto-wp.md` §4.3.5–4.3.6 describe it.
- `cargo creusot` runs `cargo check` (or `build` with `CREUSOT_CONTINUE`) with `RUSTUP_TOOLCHAIN=nightly-2026-08-03`, `RUSTC=$DATA/toolchains/…/bin/creusot-rustc`, `CARGO_TARGET_DIR=target/creusot`, `-F creusot-std/creusot creusot-std/nightly` (`main.rs:131-176`); so rustup and the nightly are required, and `creusot-rustc` loads the nightly's `librustc_driver` (host `ldd`; rustup `set_ldpath`).
- `cargo creusot config --update` writes `[patch.crates-io] creusot-std = { path = "<checkout>/creusot-std" }` into `$CARGO_HOME/config.toml` or `~/.cargo/config.toml`, preserving the rest (toml_edit), only because the version has a pre-release tag (`config.rs:28-33`); the host file has exactly that form. Check mode is the default ("Update … (default is to only check it)", `config.rs:19-21`).
- `creusot-std` uses `version.workspace = true` (`creusot-std/Cargo.toml:3`).
- `cargo creusot version` prints cargo-creusot, the toolchain, `why3 --version` (`Why3 platform, version 1.8.2+git`), `why3find --version` (`v1.3.0+dev`), then the four provers (`main.rs:538-555`) — six tools.
- `cargo creusot why3 ide` exists (`main.rs:521-526`), and `cargo creusot new` generates `add_one` on `i64` with `#[requires(a@ < i64::MAX@)]` (`new.rs:86-93`).
- The C spec facts reused: `/opt/autowp-<name>` link in `setup-base` (`autowp-rocq/hooks/setup-base:4`), hand-written env (`autowp-rocq/sdkcraft.yaml`), `runuser -u workshop -- bash -lc` health checks, `mount` plugs with `workshop-target` (`autowp-lean/sdkcraft.yaml:20-26`), `install -m 644 "$SDK/<name>.profile"`. The platform block (`noble`/`resolute`, `build-on`/`build-for`) matches the three SDKs' uncommitted `sdkcraft.yaml` change of 2026-10-31, and `test-sdk.sh` has the `BASE=` variable the spec's §6 uses. The C spec's open point 7 already points to this file (uncommitted diff).
- `install.md` §3 "Keep the checkout where it is" and §4's version table (apart from the CVC5 format, major 5); `provision.sh` step 2 is the hour-long `./INSTALL` with GTK packages (`:52-75`).
- `use-creusot`: `Makefile:13` `TOOLCHAIN ?= nightly-2026-04-21`, `compile-check.sh:21` `rustc +nightly-2026-04-21`; `monitor-check.sh:15-16` calls `/tmp/strip-creusot/target/release/strip-creusot`; `lace-workflow.md:117` "it targets `x86_64-unknown-uefi`"; `lxc-usage.md` runs the agents offline (loopback-only network); README: 241 corpus files.
- Z3 5.3.2 needs glibc 2.39; Ubuntu 24.04 ships 2.39.
- `auto-wp.md` §4.3.5 toolchain-check row: checks the tool versions and the checkout path from `~/.cargo/config.toml`, "do not install"; the stripping script is `creusot-launch`'s to ship.
- Licences: Creusot LGPL-2.1 (`LICENSE`), Z3 MIT, CVC4 BSD-3-Clause, CVC5 GPL build, Rust MIT/Apache-2.0; why3find's repository carries an `LGPLv2.1` file (its `LICENSE.md` was not read — unverified).
- Host sizes (`du -sh`, 2026-10-31): `~/.local/share/creusot` 1.4 GB; `~/.rustup/toolchains/nightly-2026-08-03-x86_64-unknown-linux-gnu` 2.4 GB, of which `lib/rustlib/x86_64-unknown-linux-gnu/lib` is 967 MB. The spec's figures are exact.

## Not verified

- Whether Workshop bounds the run time of `check-health`.
- That the smoke proof passes without `rustc-dev`/`llvm-tools` (plausible from the `lib/` layout; the fixed step-6 experiment decides).
- That Pearlite accepts `result == x + 1u32` (minor 21).
- Which Creusot commit `use-creusot` was run with (minor 24).
- Whether `alt-ergo-free` on opam exists at a 2.6.x version compatible with the `alt_ergo_26` driver (major 10).
