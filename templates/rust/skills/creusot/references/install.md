# Installing Creusot

Creusot is installed from its git repository with its own `./INSTALL` script,
which builds everything Creusot needs: `cargo-creusot`, a pinned Rust nightly,
a local opam switch with Why3 and why3find, and the SMT provers. The
recipe below is the one of `tests/rust/provision.sh` in the auto-wp
repository, and the versions are those of the end-to-end run of 2026-10-28
(`auto-wp.md` §4.3.6).

## 1. System packages (Ubuntu 24.04)

```sh
sudo apt-get install -y git python3 curl opam build-essential pkg-config \
    libcairo2-dev libgtk-3-dev libgtksourceview-3.0-dev \
    libgmp-dev zlib1g-dev unzip m4
```

The GTK packages are needed because Creusot's opam dependencies include
`why3-ide`.

**Inside an LXD container**, unload the AppArmor profile Ubuntu 24.04 ships
for opam first. It denies opam's downloads their network sockets, and
`opam init` then fails with "Could not resolve host":

```sh
sudo ln -sf /etc/apparmor.d/opam /etc/apparmor.d/disable/
sudo apparmor_parser -R /etc/apparmor.d/opam
```

## 2. opam and Rust

```sh
opam init --disable-sandboxing -y --bare
curl -sSf https://sh.rustup.rs | sh -s -- -y
. ~/.cargo/env
```

`./INSTALL` installs the Rust nightly it needs through rustup; the stable
toolchain rustup installs here is only the entry point.

## 3. Creusot, pinned

```sh
mkdir -p ~/git
git clone https://github.com/creusot-rs/creusot.git ~/git/creusot
cd ~/git/creusot
git checkout f15b985        # the commit tested on 2026-10-27/28
./INSTALL                   # an hour or more
```

**Keep the checkout where it is.** `./INSTALL` edits `~/.cargo/config.toml`
to point `creusot-std` at this checkout (`[patch.crates-io] creusot-std =
{ path = ... }`). Moving or deleting `~/git/creusot` breaks every project.
Record its path with the toolchain versions.

To move to another Creusot commit, check it out and run `./INSTALL` again,
then re-run the workspace cases of `auto-wp.md` §4.3.6: the
`why3find.json` behaviour below depends on the version.

## 4. Verify

```sh
cargo creusot version
```

It must list Why3, why3find, Alt-Ergo, Z3, CVC4 and CVC5. On 2026-10-28,
commit `f15b985` gave:

| Tool | Version |
|---|---|
| cargo-creusot | 0.15.0-dev |
| Rust | nightly-2026-08-03 |
| Why3 | 1.8.2+git |
| why3find | v1.3.0+dev |
| Alt-Ergo | 2.6.4 |
| Z3 | 5.3.2 |
| CVC4 | 1.8 |
| CVC5 | 1.4.1 |

Then prove the generated example, **in a directory with no `Cargo.toml`
above it**:

```sh
mkdir -p /tmp/creusot-smoke && cd /tmp/creusot-smoke
cargo creusot new smoke
cd smoke && cargo creusot          # the generated add_one: proved
```

## Pitfalls

- **A `Cargo.toml` above the project.** `cargo creusot new`/`init` writes
  `why3find.json` (and a `.gitignore` if there is none) next to the nearest
  parent `Cargo.toml`, not in the new project, and `cargo creusot` then fails
  with `why3find.json not found`. An empty `[workspace]` table in the
  project's `Cargo.toml` is not enough on its own: also copy
  `why3find.json` into the project, and remove the files `new` left in the
  parent (`auto-wp.md` §4.3.5–§4.3.6, cases C to H). Never create a Creusot
  project inside the crate under study; use an overlay next to it.
- **Unpinned commit.** Creusot's main branch moves fast, and its Pearlite
  syntax changes between versions. Pin the commit, and check the guide in
  `~/git/creusot/guide/src/` against `cargo creusot version` when a detail
  looks different from `../SKILL.md`.
