# Installing the Frama-C toolchain

The campaign runs **Frama-C 32.1 built from source with `frama-c-patches/`
applied**, in the opam switch **`framac-coq8`**, with Coq 8.20.1, Why3 1.8.x,
Alt-Ergo and Z3. A stock `opam install frama-c` is **not** a conformant
toolchain: it lacks the WP and frontend fixes this project depends on, and a
"tool ceiling" verdict produced with it is self-inflicted (see
`../../frama-c-launch/SKILL.md`, toolchain confirmation).

Run everything from the **project root** (the directory with `bin/` and
`frama-c-patches/`). `frama-c-launch` runs these steps itself on the first
campaign run when the toolchain is missing; this page is the recipe it
follows and the one to use by hand. It is the recipe of
`tests/c/provision.sh` in the auto-wp repository; the source download and
patching (step 4) were run end to end on 2026-10-28, the build steps are
those of that script.

## 1. System packages (Ubuntu 24.04)

```sh
sudo apt-get install -y git python3 curl opam build-essential pkg-config \
    libgtk-3-dev libgraphviz-dev graphviz libgtksourceview-3.0-dev bear \
    unzip rsync m4 libgmp-dev zlib1g-dev
```

`bear` produces `compile_commands.json` for the code under study; the GTK
packages are for the Frama-C GUI and Why3 IDE dependencies opam pulls in.

**Inside an LXD container**, unload the AppArmor profile Ubuntu 24.04 ships
for opam first. It denies opam's downloads their network sockets, and
`opam init` then fails with "Could not resolve host":

```sh
sudo ln -sf /etc/apparmor.d/opam /etc/apparmor.d/disable/
sudo apparmor_parser -R /etc/apparmor.d/opam
```

## 2. opam and the `framac-coq8` switch

```sh
opam init --disable-sandboxing -y --bare
opam switch create framac-coq8 ocaml-base-compiler.4.14.2 -y
eval "$(opam env --switch=framac-coq8 --set-switch)"
```

Use this switch for every Frama-C command, and never install Coq into the
default switch.

## 3. Coq, then Why3 and the provers

**Order matters: Coq first, then Why3**, so Why3's build compiles its Coq
realizations against the installed Coq. **Pin Coq to 8.20.1 with `opam pin`**,
not `opam install coq.8.20.1`: when a later install upgrades `dune` (Alt-Ergo
2.6.4 does), opam upgrades an unpinned Coq to 9.x with it (seen on
2026-10-31). Also, a plain
`opam install coq` now gives Rocq 9.x, which Why3 1.8 does not detect, which
ships only the `rocq` binary, and whose stdlib layout breaks the 8.x
realizations (details in `coq-escalation.md`).

```sh
opam pin add -y coq 8.20.1
opam install -y "why3>=1.8.0" "why3<1.9" "why3-coq>=1.8.0" "why3-coq<1.9" alt-ergo z3
why3 config detect
test -f "$(why3 --print-libdir)/coq/BuiltIn.vo"   # the realizations were built
```

The Coq realizations are the separate opam package `why3-coq` (same version
as `why3`): without it `BuiltIn.vo` is missing and WP cannot use Coq. If
Why3 went in before Coq, `opam reinstall why3-coq` rebuilds them.

## 4. Frama-C's dependencies and the patched sources

```sh
opam install -y yaml ppx_deriving_yaml ocamlgraph ppx_inline_test unionFind dune
opam install -y --deps-only frama-c.32.1     # the dependency base only, not the binary
bin/fetch-sources.sh
```

`bin/fetch-sources.sh` downloads the Frama-C 32.1 release archive, checks its
sha256, applies every patch of `frama-c-patches/` and leaves the result in
`framac-src/`. It also clones the macsl plugin at a pinned commit into
`macsl/`. Both directories are kept out of git by `.gitignore`. Rerunning it
keeps an existing `framac-src/` or `macsl/`.

## 5. Build and install Frama-C

```sh
cd framac-src
dune build @install
dune install --prefix "$(opam var prefix)" frama-c frama-c-wp frama-c-rtegen \
    frama-c-region frama-c-server qed
cd ..
```

WP is a dynamic plugin: after changing a patched file under `framac-src/`,
`dune build @install` (and the `dune install` line) must run again, or the
change is not in the binary that runs.

## 6. The macsl plugin (Plane H)

```sh
(cd macsl && dune build)
```

in the `framac-coq8` switch. How to load and smoke it is in
`../../frama-c-monitoring/references/macsl-recipe.md`.

## 7. Verify

```sh
frama-c -version          # 32.1 (Germanium)
frama-c -wp-detect        # lists Alt-Ergo, Z3 and Coq
grep -q land_le_l "$(frama-c -print-share-path)/wp/why3/frama_c_wp/cbits.mlw" \
    && echo patched       # the wp-cbits-bound-lemmas patch is in the installed share
```

All three must hold before any verdict is trusted. Record the outputs in the
onboarding package (`frama-c-launch`, toolchain confirmation).

## Pitfalls

- **Stock binary.** `opam install frama-c` installs an unpatched 32.1. Use it
  only through `--deps-only` (step 4).
- **Rocq 9.x.** Detected by Why3 1.8 as "version 9.2" (a regex miss), no
  `coqc`; shims do not fix the realization ABI. Pin `coq.8.20.1`.
- **Wrong switch.** `eval "$(opam env --switch=framac-coq8 --set-switch)"` in
  every new shell; `frama-c -wp-detect` without Coq usually means the default
  switch is active.
- **`opam source`.** `opam source frama-c.32.1` also gets the sources, but it
  needs a switch to exist and the patches are then applied by hand;
  `bin/fetch-sources.sh` does both.
