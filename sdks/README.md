# Workshop SDKs for auto-wp

Four [Workshop](https://ubuntu.com/workshop/docs/) SDKs that package the
proof environments auto-wp's skills need. The designs are
`../workshop-autowp-c-base-spec.md` (Frama-C, Rocq, Lean) and
`../workshop-autowp-rust-base-spec.md` (Creusot).

| SDK | Version | Contents |
|---|---|---|
| `frama-c-sdk/` | 32.1 | Frama-C 32.1 built from source with `templates/c/tools/frama-c-patches/`, macsl, Why3 1.8, Coq 8.20.1 (pinned) for WP, Alt-Ergo, Z3; `bear` and the C build tools at run time |
| `rocq/` | 9.2.0 | Rocq 9.2.0 and its standard library, with `coqc`, `coqtop`, `coqdep` |
| `lean/` | 4.35.0 | elan 4.2.4 with the toolchain `leanprover/lean4:v4.35.0`, Lake, ripgrep, lean-lsp-mcp 0.32.0 |
| `creusot/` | 0.15.0-f15b985 | Creusot at `f15b985` (cargo-creusot, creusot-rustc), Rust `nightly-2026-08-03`, Creusot's Why3 1.8.2 and why3find switch, Alt-Ergo 2.6.4, Z3 5.3.2, CVC4 1.8, CVC5 1.4.1, the Creusot sources `creusot-std` is patched to |

**Alt-Ergo licence.** `frama-c-sdk` and `creusot` bundle
Alt-Ergo 2.6.4 under the *OCamlPro Non-Commercial
Purpose License*: use is allowed **solely for research**, not "in
connection with a product or service which is sold, … or used in a
profit-making context". The licence and OCamlPro's notice are shipped in
`$SDK/share/licenses/alt-ergo/`; anyone redistributing the SDK must keep
them. Commercial use needs a licence from OCamlPro (contact@ocamlpro.com).
Without Alt-Ergo, WP and Creusot still have Z3 (and CVC4/CVC5 for Creusot).

All four are built for `ubuntu@24.04` and `ubuntu@26.04` on amd64 (one
`.sdk` per base) and are independent of each other.

## Build and test

Needs LXD 6.8 or later, `sdkcraft` and `workshop`
(`sudo snap install --classic sdkcraft workshop`). From the repository root:

```
make sdk-lean        # minutes
make sdk-rocq        # about an hour on the first build
make sdk-framac      # hours on the first build (Coq, Why3, Z3, Frama-C)
make sdk-creusot     # about 40 minutes (Creusot's ./INSTALL, both bases)
make test-sdks       # the four together in one workshop
```

Each target packs the SDK with `sdkcraft try`, which puts
`<name>_amd64_ubuntu@24.04.sdk` and `<name>_amd64_ubuntu@26.04.sdk` in the
try area, then runs `test-sdk.sh`: it
launches a throwaway workshop that uses the SDK as `try-<name>`, checks that
the workshop reaches `ready` (every SDK's `check-health` passed), runs the
tools, and removes the workshop (`KEEP=1` keeps it). The workshop's base is
`ubuntu@24.04` unless `BASE=ubuntu@26.04` is set, e.g.
`BASE=ubuntu@26.04 sdks/test-sdk.sh lean`.
`frama-c-sdk/prepare.sh` first copies `bin/fetch-sources.sh` and
`frama-c-patches/` from `templates/c/tools/` into `frama-c-sdk/vendor/`,
because `sdkcraft` builds in a container that only sees the SDK's directory.

### arm64 (Apple Silicon, arm64 servers)

Each SDK also declares `noble-arm64` and `resolute-arm64`. `sdkcraft` does
not cross-build, so an amd64 host packs only the amd64 platforms; the arm64
ones are built by `.github/workflows/sdks-arm64.yml` on GitHub's
`ubuntu-24.04-arm` runner (run it by hand, or on a push to `master` that
touches `sdks/`), which keeps each `.sdk` as a workflow artifact. Workshop
itself only runs on Linux: on a Mac, use it inside an arm64 Ubuntu VM
(Multipass, UTM, Lima), and test the arm64 SDKs there with `test-sdk.sh`.
Differences on arm64: Creusot's Alt-Ergo 2.6.4 is built from opam (there is
no arm64 binary), and CVC4 is not shipped (no arm64 build exists; CVC5
supersedes it), so `cargo creusot new` projects use Alt-Ergo, Z3 and CVC5.

## Using them

In a project, `.workshop/<name>.yaml`:

```yaml
name: dev
base: ubuntu@24.04             # or ubuntu@26.04
sdks:
  - name: try-frama-c-sdk     # or frama-c-sdk with a channel, once published
  - name: try-rocq
  - name: try-lean
  - name: try-creusot   # Rust projects
```

then `workshop launch` and `workshop shell`. The project is at `/project`.

- `frama-c`, `frama-c-gui`, `why3`, `alt-ergo`, `z3`, `dune` and
  `ocamlfind` are wrappers in `/opt/frama-c-sdk/bin` that run the tool in
  the SDK's opam switch; `frama-c-sdk-exec <cmd>` runs any other command
  there. The switch's `coqc` (8.20.1) is not on `PATH`, so it does not shadow
  `rocq`'s. `FRAMA_C_SDK_MACSL` is the macsl plugin for
  `-load-module`, `FRAMA_C_SDK_SRC` the patched Frama-C sources.
- `coqc` and `rocq` come from `rocq`.
- `lean`, `lake` and `elan` come from `~/.elan`, which the first launch
  seeds from the SDK and a mount keeps across refreshes; Mathlib's cache in
  `~/.cache/mathlib` is kept the same way. `lean-lsp-mcp` is on `PATH`; add
  it to Claude Code with `claude mcp add lean-lsp -- lean-lsp-mcp`.
- `cargo creusot` comes from `creusot`. rustup and Cargo live in
  `~/.rustup` and `~/.cargo`, which the first launch seeds with the
  nightly and a small crate cache, and mounts keep across refreshes; a
  crate's own `rust-toolchain.toml` and `rustup target add` work there.
  `setup-project` points `creusot-std` at the SDK's Creusot sources in
  `~/.cargo/config.toml`. Why3 and the provers are not on `PATH`
  (`cargo creusot` finds them), so they do not clash with `frama-c-sdk`'s.
  `CARGO_NET_OFFLINE=true` lets a project prove without crates.io once its
  crates are cached.

## How the opam SDKs are built

An opam root embeds absolute paths, so it cannot be moved after it is
built. `frama-c-sdk` and `rocq` build their switch at
`/opt/autowp-<name>/opam` in the build container and ship that tree; at run
time, `setup-base` links `/opt/autowp-<name>` to the SDK's install directory
(`$SDK`), so every embedded path resolves. The switch is read-only: users run
its tools but do not `opam install` into it. Each SDK's `env.sh` prepends the
switch's `bin/` to `PATH` and never replaces it.
