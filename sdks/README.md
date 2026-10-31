# Workshop SDKs for auto-wp

Three [Workshop](https://ubuntu.com/workshop/docs/) SDKs that package the
proof environments auto-wp's skills need. The design is
`../workshop-autowp-c-base-spec.md`.

| SDK | Version | Contents |
|---|---|---|
| `autowp-framac/` | 32.1 | Frama-C 32.1 built from source with `templates/c/tools/frama-c-patches/`, macsl, Why3 1.8, Coq 8.20.1 (pinned) for WP, Alt-Ergo, Z3; `bear` and the C build tools at run time |
| `autowp-rocq/` | 9.2.0 | Rocq 9.2.0 and its standard library, with `coqc`, `coqtop`, `coqdep` |
| `autowp-lean/` | 4.35.0 | elan 4.2.4 with the toolchain `leanprover/lean4:v4.35.0`, Lake, ripgrep, lean-lsp-mcp 0.32.0 |

All three target `ubuntu@24.04` on amd64 and are independent of each other.

## Build and test

Needs LXD 6.8 or later, `sdkcraft` and `workshop`
(`sudo snap install --classic sdkcraft workshop`). From the repository root:

```
make sdk-lean        # minutes
make sdk-rocq        # about an hour on the first build
make sdk-framac      # hours on the first build (Coq, Why3, Z3, Frama-C)
make test-sdks       # the three together in one workshop
```

Each target packs the SDK with `sdkcraft try`, which puts
`<name>_amd64_ubuntu@24.04.sdk` in the try area, then runs `test-sdk.sh`: it
launches a throwaway workshop that uses the SDK as `try-<name>`, checks that
the workshop reaches `ready` (every SDK's `check-health` passed), runs the
tools, and removes the workshop (`KEEP=1` keeps it).
`autowp-framac/prepare.sh` first copies `bin/fetch-sources.sh` and
`frama-c-patches/` from `templates/c/tools/` into `autowp-framac/vendor/`,
because `sdkcraft` builds in a container that only sees the SDK's directory.

## Using them

In a project, `.workshop/<name>.yaml`:

```yaml
name: dev
base: ubuntu@24.04
sdks:
  - name: try-autowp-framac     # or autowp-framac with a channel, once published
  - name: try-autowp-rocq
  - name: try-autowp-lean
```

then `workshop launch` and `workshop shell`. The project is at `/project`.

- `frama-c`, `frama-c-gui`, `why3`, `alt-ergo`, `z3`, `dune` and
  `ocamlfind` are wrappers in `/opt/autowp-framac/bin` that run the tool in
  the SDK's opam switch; `autowp-framac-exec <cmd>` runs any other command
  there. The switch's `coqc` (8.20.1) is not on `PATH`, so it does not shadow
  `autowp-rocq`'s. `AUTOWP_FRAMAC_MACSL` is the macsl plugin for
  `-load-module`, `AUTOWP_FRAMAC_SRC` the patched Frama-C sources.
- `coqc` and `rocq` come from `autowp-rocq`.
- `lean`, `lake` and `elan` come from `~/.elan`, which the first launch
  seeds from the SDK and a mount keeps across refreshes; Mathlib's cache in
  `~/.cache/mathlib` is kept the same way. `lean-lsp-mcp` is on `PATH`; add
  it to Claude Code with `claude mcp add lean-lsp -- lean-lsp-mcp`.

## How the opam SDKs are built

An opam root embeds absolute paths, so it cannot be moved after it is
built. `autowp-framac` and `autowp-rocq` build their switch at
`/opt/autowp-<name>/opam` in the build container and ship that tree; at run
time, `setup-base` links `/opt/autowp-<name>` to the SDK's install directory
(`$SDK`), so every embedded path resolves. The switch is read-only: users run
its tools but do not `opam install` into it. Each SDK's `env.sh` prepends the
switch's `bin/` to `PATH` and never replaces it.
