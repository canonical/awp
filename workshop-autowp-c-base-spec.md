# Workshop SDKs for auto-wp — specification

This document specifies three Workshop SDKs that package the proof
environments auto-wp's skills need:

| SDK | Provides | Used by |
|---|---|---|
| `autowp-framac` | Frama-C 32.1 with WP, built from source with auto-wp's `frama-c-patches/`, the macsl plugin, Why3 1.8, Coq 8.20.1 for WP, Alt-Ergo, Z3, `bear` | the C layer: `frama-c`, `frama-c-launch`, `frama-c-monitoring`, `framac-sl`, `time-loop` |
| `autowp-rocq` | Rocq, for interactive and stand-alone proofs | the common skill `rocq` |
| `autowp-lean` | Lean 4 through elan, Lake, ripgrep, the Lean LSP MCP server | the common skill `lean` |

They replace the hours-long, hand-run toolchain build (`tests/c/provision.sh`
step 3, `frama-c-launch`'s first-run build, `frama-c/references/install.md`)
with a prebuilt, versioned unit that a workshop installs in minutes. The
name of this file keeps the `autowp-c-base` of the test base container it
supersedes. The SDKs are implemented in `sdks/` (see `sdks/README.md`);
§11 records how the implementation differs from this design and what the
tests showed. The open points are in §10.

## 1. Workshop in brief

Facts this spec relies on, from the Workshop documentation (its source,
`github.com/canonical/workshop/docs/`, read on 2026-10-31; the hosted pages
under `canonical-workshopubuntucom.readthedocs-hosted.com` need a login):

- A **workshop** is an LXD container described by a definition in the
  project, `.workshop/<name>.yaml`, with a `base` (for example
  `ubuntu@24.04`) and a list of `sdks`, each with an optional `channel`.
  `workshop launch` builds it; `workshop shell` opens a login shell as the
  unprivileged user `workshop`; the project directory is mounted at
  `/project/`, and changes show on both sides.
- An **SDK** is built and published with **SDKcraft** from a
  `sdkcraft.yaml` (`name`, quoted `version`, `summary`, `description`,
  `license`, `platforms` such as `ubuntu@24.04:amd64`, `plugs`, `slots`,
  `parts`) and a `hooks/` directory. The workshop's `base` must match one of
  the SDK's platforms.
- **Parts** use the Craft Parts mechanism of Snapcraft (`dump`, `rust`,
  `go`, `python` plugins and the others; `stage-packages` and `stage-snaps`
  are not supported). Parts produce a prebuilt payload; the SDK is
  installed in the workshop under **`/var/lib/workshop/sdk/<name>/`**, which
  hooks see as **`$SDK`**.
- **Hooks**, shell scripts linted with ShellCheck when the SDK is packed:
  - `setup-base` runs as root at install and on every refresh, and becomes
    part of the workshop's base snapshot: the place for `apt-get install`
    (apt is preconfigured with `-y` and no recommends) and for
    `/etc/profile.d/<name>.sh`;
  - `setup-project` runs as `workshop` after the project is mounted and
    interfaces are connected, is not snapshotted, and writes under
    `/home/workshop/` and `~/.profile`;
  - `check-health` reports `workshopctl set-health okay|error|waiting`;
  - `save-state` / `restore-state` carry state across a refresh through
    `$SDK_STATE_DIR`.
- **Interfaces**: a `mount` plug with a `workshop-target` keeps a directory
  on the host across refreshes (the host side is chosen by Workshop, not the
  SDK); `tunnel` slots expose ports; `gpu`, `ssh`, `secret` exist.
- **Workflow**: `sdkcraft try` packs `<name>_<arch>_<base>.sdk` into a local
  try area, used from a definition as `- name: try-<name>`;
  `sdkcraft test` runs spread tests; `sdkcraft login`, `register`,
  `upload … --release <track>/<risk>` publish to the SDK Store, from which a
  definition takes `- name: <name>` with a `channel`. Requirements: LXD
  6.8+, `snap install --classic sdkcraft` and `workshop`.
- The Workshop best practices: Debian packages in `setup-base`, not in
  parts; pinned or custom-built binaries in parts; system-wide variables in
  `/etc/profile.d/`, user ones in `~/.profile`; environment variables
  prefixed with the SDK name.

On this host, `workshop` 0.1.29 is installed (snap, classic) and the bridge
`workshopbr0` exists; `sdkcraft` is not installed. The installed `workshop`
has no `sdk-find` command, which the current documentation lists, so the
store could not be searched for existing Frama-C, Rocq or Lean SDKs (open
point 1).

## 2. Common decisions

- **Three independent SDKs.** Each one installs and works alone; none
  depends on another. A workshop combines them as a project needs: a C
  campaign takes `autowp-framac`, plus `autowp-rocq` or `autowp-lean` only if
  its skills reach for them.
- **Platform.** `ubuntu@24.04:amd64` first, the base the auto-wp tests and
  READMEs use. `arm64` is a later addition (open point 6).
- **Immutable toolchains.** Each SDK's toolchain is read-only under `$SDK`
  and owned by root. Users run it; they do not `opam install` or
  `elan toolchain install` into it. What must change per user or per
  project lives in the home directory, through `setup-project` and `mount`
  plugs.
- **Built in parts, not in hooks.** The long builds (Coq, Why3, Frama-C,
  macsl, Rocq) run once in `sdkcraft`'s build, so `workshop launch` installs
  a prebuilt tree instead of rebuilding for hours (the reason for this
  spec). Only apt packages go in `setup-base`, per the best practices.
- **opam is not relocatable, so it is built at a fixed path.** An opam
  root and its switch embed absolute paths. The parts build with
  `OPAMROOT=/opt/autowp-<name>/opam` and ship that tree; at run time,
  `setup-base` links `/opt/autowp-<name>` to `$SDK`, so the embedded paths
  resolve whatever `$SDK` is (implemented and tested, §11).
- **Environment.** `setup-base` writes `/etc/profile.d/<name>.sh`. Each SDK
  puts only its own entry points on `PATH`, and prefixes its variables
  (`AUTOWP_FRAMAC_…`, `AUTOWP_ROCQ_…`, `AUTOWP_LEAN_…`). §3.4 explains why
  `autowp-framac` does not export its `coqc`.
- **Versioning.** The SDK `version` is the main upstream version (`32.1`,
  the Rocq version, the Lean toolchain version). Store tracks follow it
  (`32/stable` for Frama-C 32.x); `latest/edge` gets every build.
- **Source of truth.** The SDK sources live in the auto-wp repository under
  `sdks/<name>/`, so the Frama-C SDK takes `frama-c-patches/` from
  `templates/c/tools/` by a local part source, the same files a generated
  project ships. A change to the patches is then one commit for both.

## 3. `autowp-framac`

### 3.1 Contents

| Component | Version | How |
|---|---|---|
| OCaml | 4.14.2 | opam switch `framac-coq8` in `$SDK/opam` |
| Coq | 8.20.1 | opam, installed **before** Why3 (`frama-c/references/install.md` §3) |
| Why3 | `>=1.8.0 <1.9`, with its Coq realizations | opam |
| Alt-Ergo, Z3 | opam's versions at build time, recorded in the SDK | opam |
| Frama-C | 32.1, release archive `frama-c-32.1-Germanium.tar.gz`, sha256 `dd5d6e89…13e2` | built from source with `frama-c-patches/` applied, exactly as `bin/fetch-sources.sh` does, then `dune build @install` and `dune install` of `frama-c frama-c-wp frama-c-rtegen frama-c-region frama-c-server qed` |
| macsl | `canonical/macsl` at `b7a472e2b6b944ffb2f70e66802ad5e162d74605` | `dune build` in the switch; the `.cmxs` installed under `$SDK/macsl/` |
| patched sources | the `framac-src/` tree | shipped read-only at `$SDK/src/frama-c-32.1/`, for the skills that read Frama-C's source (`frama-c-internals`, the patch scripts) |

### 3.2 `sdkcraft.yaml` (sketch)

```yaml
name: autowp-framac
version: "32.1"
summary: Frama-C 32.1 with WP, macsl and provers, as used by auto-wp
description: |
  Frama-C 32.1 built from source with auto-wp's frama-c-patches, the
  macsl plugin, Why3 1.8 with Coq 8.20.1 realizations, Alt-Ergo and Z3,
  in a read-only opam switch.
license: LGPL-2.1-only          # Frama-C's; the bundle's other licences are listed in the README
platforms:
  ubuntu@24.04:amd64:

plugs:
  why3-cache:
    interface: mount
    workshop-target: /home/workshop/.cache/autowp-framac

parts:
  framac:
    plugin: nil
    source: https://www.frama-c.com/download/frama-c-32.1-Germanium.tar.gz
    source-checksum: sha256/dd5d6e89df5dde6a40b38bead302d0a5b9860b1c3b65bcd85360a778087c13e2
    build-packages: [opam, build-essential, pkg-config, m4, unzip, rsync,
                     libgmp-dev, zlib1g-dev, libgtk-3-dev,
                     libgtksourceview-3.0-dev, libgraphviz-dev]
    override-build: |
      # opam root at the path $SDK/opam will have in the workshop (§2)
      ...see §3.3...
  patches:
    plugin: dump
    source: ../../templates/c/tools/frama-c-patches
    organize: { "*": share/frama-c-patches/ }
  macsl:
    after: [framac]
    plugin: nil
    source: https://github.com/canonical/macsl.git
    source-commit: b7a472e2b6b944ffb2f70e66802ad5e162d74605
    override-build: |
      ...dune build in the framac-coq8 switch, install the .cmxs to macsl/...
```

The exact plugin keys follow Craft Parts; the sketch shows the structure,
not tested syntax (open point 3).

### 3.3 Build steps (`override-build` of `framac`)

The recipe of `frama-c/references/install.md` and `tests/c/provision.sh`,
with the opam root at its final path:

1. `export OPAMROOT=/var/lib/workshop/sdk/autowp-framac/opam`;
   `opam init --disable-sandboxing -y --bare`;
   `opam switch create framac-coq8 ocaml-base-compiler.4.14.2 -y`.
2. `opam install -y coq.8.20.1`, then
   `opam install -y "why3>=1.8.0" "why3<1.9" alt-ergo z3`; check
   `"$(why3 --print-libdir)/coq/BuiltIn.vo"`.
3. `opam install -y yaml ppx_deriving_yaml ocamlgraph ppx_inline_test unionFind dune`
   and `opam install -y --deps-only frama-c.32.1`.
4. Unpack the archive, apply the patches in the order of
   `bin/fetch-sources.sh` (`frama-c-patches/apply.sh` for 0001 and 0002;
   `cabs2cil-c23-auto.patch` with `patch -p0`; `cbits.mlw.patch`; the
   `Cbits.v.realization` appended to `coqwp/Cbits.v`), and check that
   `land_le_l` is in `cbits.mlw`. The SDK build reuses
   `bin/fetch-sources.sh` itself, so the two cannot drift.
5. `dune build @install`; `dune install --prefix "$(opam var prefix)"` of
   the six packages.
6. Remove what the runtime does not need (opam's download cache,
   `_build/`), then move the opam root into `$CRAFT_PART_INSTALL/opam`.

### 3.4 Runtime

- **`setup-base`** installs `bear`, `build-essential`, `pkg-config`, `git`
  and `ripgrep` with apt (packages the campaign runs, not build
  dependencies of the SDK), and writes `/etc/profile.d/autowp-framac.sh`:
  - `OPAMROOT=$SDK/opam`, `AUTOWP_FRAMAC_SWITCH=framac-coq8`;
  - `PATH` gains `$SDK/bin`, which holds small wrappers `frama-c`,
    `frama-c-gui`, `why3`, `alt-ergo`, `z3` that run the tool with the
    switch's environment (`opam exec --switch=framac-coq8 -- <tool>`);
  - `AUTOWP_FRAMAC_MACSL=$SDK/macsl/macsl.cmxs`,
    `AUTOWP_FRAMAC_SRC=$SDK/src/frama-c-32.1`.

  `coqc` is deliberately **not** on `PATH`: the switch's Coq is 8.20.1,
  pinned for WP, while `autowp-rocq` provides a Rocq for stand-alone proofs.
  Exporting both would make `coqc` depend on SDK order. WP finds its Coq
  through Why3's configuration, not `PATH`.
- **`setup-project`** runs `why3 config detect` as `workshop`, which writes
  `~/.why3.conf` for this user; the `why3-cache` mount keeps Why3's and
  WP's caches across refreshes.
- **`check-health`** runs, as `workshop`: `frama-c -version` is `32.1`;
  `frama-c -wp-detect` lists Alt-Ergo, Z3 and Coq; `land_le_l` is in the
  installed `cbits.mlw`; the macsl `.cmxs` loads
  (`frama-c -load-module "$AUTOWP_FRAMAC_MACSL" -version`). Any failure
  sets `error` with the failing command's output.

### 3.5 What changes in auto-wp

- **`bin/fetch-sources.sh`**: when `AUTOWP_FRAMAC_SRC` is set and
  `framac-src/` is absent, link `framac-src` to it instead of downloading;
  same for `macsl/`. Without the SDK, behaviour is unchanged.
- **`frama-c-launch`'s toolchain confirmation**: accept the SDK as a
  conformant toolchain when `check-health` would pass, and skip the build.
- **`frama-c/references/install.md`**: a first section, "In a workshop:
  add `autowp-framac` to the definition", before the build-from-source
  recipe, which stays for hosts without Workshop.
- The project's own packages (GRUB's build dependencies, gzip's `configure`
  needs) are not in the SDK. A generated project carries them as a
  project-local SDK, `.workshop/autowp-project/` with a `setup-base` that
  runs `apt-get install` of the list the README has today.

## 4. `autowp-rocq`

| Component | Version | How |
|---|---|---|
| Rocq | 9.x, the current release at build time, pinned in `sdkcraft.yaml` (open point 4) | opam switch `rocq` in `$SDK/opam`, packages `rocq-prover` and `rocq-stdlib` |
| MathComp | optional, `rocq-mathcomp-ssreflect` (open point 4) | opam |
| Rocq MCP server | the server the `rocq` skill's `rocq_query` tools talk to | to be identified (open point 5) |

- **Build**: as §3.3 steps 1 and 6, with `OPAMROOT=/var/lib/workshop/sdk/autowp-rocq/opam`.
- **`setup-base`**: `/etc/profile.d/autowp-rocq.sh` puts `rocq`, `coqc`,
  `coqtop`, `coqdep` wrappers on `PATH`, and sets `ROCQ_PYTHON_BIN` to the
  system `python3` (the skill's capability table checks it). apt:
  `python3`, `ripgrep`.
- **`setup-project`**: registers the MCP server with Claude Code for the
  `workshop` user, if open point 5 gives one.
- **`check-health`**: `coqc --version`; compile a one-lemma `.v` file
  with no `Admitted`.

## 5. `autowp-lean`

| Component | Version | How |
|---|---|---|
| elan | pinned release | `dump` of the release tarball |
| Lean 4 | one pinned toolchain (`leanprover/lean4:v4.x.y`) | installed with elan at build time |
| Lake | the toolchain's | — |
| ripgrep | apt | `setup-base` (the skill's `lean_local_search` needs it) |
| lean-lsp-mcp | v0.21 or later (the version the `lean` skill documents) | `python` part into `$SDK/venv`, or `uv tool` |

Lean differs from the two opam SDKs: a project's `lean-toolchain` file
selects its toolchain, and Mathlib is a per-project Lake dependency of
several GB. So the toolchains cannot all be read-only:

- **`ELAN_HOME=~/.elan`**, kept across refreshes by a `mount` plug
  `elan` (`workshop-target: /home/workshop/.elan`). `setup-project` seeds
  it from the toolchain shipped in `$SDK/elan` when it is empty, so the
  pinned toolchain is there offline; a project that asks for another one
  downloads it into the mount.
- **Mathlib's cache** gets its own mount plug
  (`workshop-target: /home/workshop/.cache/mathlib`), so `lake exe cache get`
  downloads it once per host, not once per refresh.
- **`setup-base`**: `/etc/profile.d/autowp-lean.sh` with `ELAN_HOME` and
  `PATH="$ELAN_HOME/bin:$PATH"`, and `LEAN4_PYTHON_BIN` (the skill's
  capability table).
- **`setup-project`**: seeds `~/.elan`; registers lean-lsp-mcp with Claude
  Code for the `workshop` user.
- **`check-health`**: `lean --version`, `lake --version`; `lake new` and
  `lake build` of a scratch project in a temporary directory.

## 6. Using them from auto-wp

`auto-wp.py` writes a workshop definition into each generated project,
`.workshop/autowp.yaml`:

```yaml
name: autowp
base: ubuntu@24.04
sdks:
  - name: autowp-framac        # --c projects
    channel: 32/stable
  - name: autowp-rocq          # optional
  - name: autowp-lean          # optional
  - name: project-autowp-project   # the project's own apt packages (§3.5)
```

`--c` projects list `autowp-framac`; `--rust` projects list none of the
three until a Creusot SDK exists (open point 7). Whether `autowp-rocq` and
`autowp-lean` are listed by default is open point 8.

The README then gains a Workshop quick start next to the LXD one:

```
cd {{DIR}}
workshop launch
workshop shell
```

followed by step 2 of today's README (clone the code, install Claude Code,
`tmux`, `claude`), with `/project` in place of `/home/ubuntu/{{DIR}}`.
Workshop mounts the project, as `bin/launch_lxc.sh` does today, so the
safety notes on writes into the host directory stay as they are.

## 7. Tests

Each SDK has spread tests run by `sdkcraft test` on the packed SDK:

- **`autowp-framac`**: the `check-health` checks; WP proves a three-line
  function with `-wp-rte` (`Valid` on every goal); a goal that needs the
  `wp-cbits-bound-lemmas` patch proves (a function from the patch's
  README), which a stock Frama-C fails; macsl loads.
- **`autowp-rocq`**: compile a lemma; `Print Assumptions` shows no axiom.
- **`autowp-lean`**: `lake new` and `lake build`; lean-lsp-mcp starts and
  answers its `--help`.

In auto-wp:

- `tests/c/provision.sh` gains a Workshop mode that launches a workshop
  with `autowp-framac` instead of building the toolchain, so
  `make provision-c` takes minutes. The LXD base stays for hosts without
  Workshop.
- `test_auto_wp.py` checks the generated `.workshop/autowp.yaml` per
  language.
- `make sdk-framac`, `make sdk-rocq`, `make sdk-lean` run `sdkcraft try`
  and `sdkcraft test` in `sdks/<name>/`; they are not part of `make test`.

## 8. Publishing

- Register the three names in the SDK Store with `sdkcraft register`.
- CI on the auto-wp repository builds on pull requests and uploads to
  `latest/edge` on merge (the pattern of `canonical/template-sdk`).
  Promotion to `<track>/stable` is by hand, after the auto-wp level 3 test
  (`make smoke-c` or `make smoke-c-gzip`) passes on the edge revision.
- Each SDK's README lists the bundled components and their licences
  (Frama-C LGPL-2.1, Why3 LGPL-2.1, Coq/Rocq LGPL-2.1, Alt-Ergo's
  licence, Z3 MIT, Lean Apache-2.0, macsl's licence). The `license` field of
  `sdkcraft.yaml` names the main component's.

## 9. Documents to update

- `auto-wp.md`: the `.workshop/` definition in §3 (what `auto-wp.py` writes
  and the README quick start), the `sdks/` directory in §4, the tests in §5.
- `tests.md`: the Workshop mode of `provision.sh`; the SDK tests.
- `templates/c/README.md`, `templates/rust/README.md`: the Workshop quick
  start.
- `frama-c/references/install.md`, `frama-c-launch/SKILL.md`: §3.5.

## 10. Open points

1. **Existing SDKs.** The installed `workshop` (0.1.29) has no `sdk-find`,
   so the store was not searched. If Rocq or Lean SDKs already exist there,
   using them may be better than publishing new ones; Frama-C with these
   patches is specific to auto-wp either way.
2. **The `$SDK` path.** *Resolved* (§11): a tried SDK is installed under
   its own name, not `try-<name>`, and the `/opt/autowp-<name>` link makes
   the opam builds independent of the path anyway.
3. **Craft Parts syntax.** *Resolved* (§11): `nil` with `override-build`
   works; a source outside the SDK directory does not, so `prepare.sh`
   copies it into `vendor/`.
4. **Rocq contents.** Which Rocq version, and whether to include MathComp
   (the `rocq` skill mentions it) or other libraries.
5. **Rocq MCP server.** The `rocq` skill documents `rocq_query` and other
   MCP tools but does not name the server or how to install it. Without it
   the skill runs its "scripts + `coqc`" profile.
6. **arm64.** All three toolchains build on arm64; the cost is CI time and
   a test host.
7. **Creusot.** A fourth SDK, `autowp-creusot`, would follow the same
   pattern (Creusot's `./INSTALL` at commit `f15b985`, its opam switch and
   Rust nightly at fixed paths); not requested here.
8. **Default SDKs.** Whether a `--c` project lists `autowp-rocq` and
   `autowp-lean` by default (they are common skills) or only on request
   (they add launch time and disk).
9. **Claude Code in the workshop.** The README installs it in step 2. An
   SDK or a project-local SDK could do it in `setup-project`, but the login
   must stay interactive and in the container (the rule of the current
   README).
10. **Size.** The Frama-C switch with Coq, Why3 and the provers is several
    GB before pruning; the SDK Store's size limits are not documented in
    what was read.

## 11. Implementation and test results (2026-10-31)

The SDKs are in `sdks/autowp-framac/`, `sdks/autowp-rocq/` and
`sdks/autowp-lean/`, with `sdks/test-sdk.sh` and the `make sdk-*` targets.
Tools: `sdkcraft` 0.9.4 (snap), `workshop` 0.9.9, LXD 6.10.1.

**Differences from the design above:**

- **opam path.** Built at `/opt/autowp-<name>/opam` and linked to `$SDK` by
  `setup-base` (§2), not built at `/var/lib/workshop/sdk/<name>/opam`.
- **`env.sh`.** Written by hand in the build: `opam env` prints the whole
  build-time `PATH`, which would replace the user's `PATH` at run time; the
  SDK's `env.sh` only prepends the switch's `bin/`.
- **Coq 8.20.1 is pinned with `opam pin add coq 8.20.1`.** With a plain
  `opam install coq.8.20.1`, the next `opam install` that upgraded `dune`
  (Alt-Ergo 2.6.4 needs a newer one) also upgraded Coq to 9.3.0, and the
  build would have shipped the wrong Coq. The same fix went into
  `tests/c/provision.sh` and the `frama-c` skill's install instructions; the
  build now checks `coqc --version` before and after the Frama-C pin.
- **Why3's Coq realizations are the opam package `why3-coq`.** `why3`
  alone does not build `BuiltIn.vo`, so WP had no Coq; the build checks
  for it. `tests/c/provision.sh` and the `frama-c` skill had the same gap.
- **`graphviz`** (the program, not only `libgraphviz-dev`) is a system
  dependency of the opam `frama-c` package; without it the pin stops with
  opam exit code 10. Added to the build packages, `tests/c/provision.sh`
  and the skill's package list.
- **Frama-C is installed with `opam pin add --kind=path frama-c .`** from the
  patched tree, as Frama-C's `INSTALL.md` describes, instead of `dune
  install` of a package list: it installs every plugin and its dependencies.
- **Patches.** `sdkcraft` builds in a container that only sees the SDK
  directory, so `prepare.sh` copies `bin/fetch-sources.sh` and
  `frama-c-patches/` into `vendor/` (not committed); the part runs
  `bin/fetch-sources.sh` itself.
- **lean-lsp-mcp** is installed in `setup-base` into a venv at
  `/opt/autowp-lean/venv` (a pinned pip install), not as a part: a Python
  venv is not relocatable either.
- **`check-health`** runs its checks with `runuser -u workshop -- bash -lc`;
  `sudo -u workshop --login bash -c` re-quotes a multi-line script and broke
  it (`cd: too many arguments`).
- **No `why3-cache` plug** in `autowp-framac`: WP keeps its caches in the
  project.

**Findings about Workshop:**

- `workshop` 0.1.29 (a sideloaded revision on this host) could not launch
  any workshop on LXD 6.10: `"nvidia.driver.capabilities" is not supported
  for "container"`. It was refreshed to 0.9.9 from `latest/stable`.
- A tried SDK appears in `workshop info` under its own name (`autowp-lean`),
  tracking `~/.local/share/workshop/try/<name>`.
- A workshop reaches `ready` only when every SDK's `check-health` sets
  `okay`; a health error aborts the launch.
- The first `sdkcraft try` on a host builds a base build instance in an LXD
  project `sdkcraft` (about 15 minutes); a forced stop of a build instance
  leaves a stale disk device, and `sdkcraft clean` is then needed.

**Test results** (`sdks/test-sdk.sh`):

| SDK | Packed size | Result |
|---|---|---|
| `autowp-lean` | 684 MB | launch, `ready`; `lean`, `lake`, `rg`, `lean-lsp-mcp` run; `lake new` + `lake build` of a project runs "Hello, world" |
| `autowp-rocq` | 400 MB | launch, `ready`; Rocq 9.2 proves a lemma, `Print Assumptions` closed |
| `autowp-framac` | 929 MB | launch, `ready`; `frama-c -version` 32.1; `-wp-detect` lists Alt-Ergo, Z3, Coq; WP with `-wp-rte` proves every goal of a small function; macsl loads; the switch's `coqc` is not on `PATH` |
| all three in one workshop | | launch, `ready`; every check above passes with the three SDKs installed together, and `coqc` is Rocq 9.2 from `autowp-rocq`, not the 8.20.1 of `autowp-framac` |

**Not implemented yet:** the auto-wp side of §3.5 and §6 (the
`.workshop/autowp.yaml` that `auto-wp.py` would write, the Workshop quick
start in the READMEs, `bin/fetch-sources.sh` reusing `AUTOWP_FRAMAC_SRC`,
`frama-c-launch` accepting the SDK), the Workshop mode of
`tests/c/provision.sh`, and publishing to the SDK Store (§8).
