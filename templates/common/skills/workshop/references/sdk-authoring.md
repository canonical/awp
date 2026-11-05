# Authoring SDKs

Load when creating or changing an SDK: sketch, in-project or crafted, `sdkcraft.yaml`, hooks.

- [Developing SDKs: sketch, in-project, crafted](#developing-sdks-sketch-in-project-crafted)
- [sdkcraft.yaml reference](#sdkcraftyaml-reference)
- [SDK hooks](#sdk-hooks)

## Developing SDKs: sketch, in-project, crafted

An SDK usually goes through five stages. Not every SDK needs all of them:

| Stage | Commands | Lives in | Reach |
|-------|----------|----------|-------|
| 1. Sketch | `workshop sketch-sdk` | per-workshop data directory | one workshop |
| 2. In-project | `workshop sketch-sdk --eject`, or write it by hand | `.workshop/<NAME>/` in the repository | every workshop of the project |
| 3. Crafted | `sdkcraft init`, `pack`, `try`, `test` | its own repository with `sdkcraft.yaml` | local try area |
| 4. Published | `sdkcraft login`, `register`, `create-track`, `upload`, `release` | SDK Store | everyone |
| 5. Consumed | `sdk find`, `workshop launch`, `workshop info` | `workshop.yaml` | |

| Kind | Listed in the definition as | Definition file | Build features |
|------|-----------------------------|-----------------|----------------|
| Store | `name` (+ `channel`) | `meta/sdk.yaml`, generated from `sdkcraft.yaml` | parts, platforms |
| Try | `try-<NAME>` | `meta/sdk.yaml`, generated | parts, platforms |
| In-project | `project-<NAME>` | `.workshop/<NAME>/sdk.yaml` or `.workshop/<NAME>/meta/sdk.yaml` | none |
| Sketch | implicit; not listed | `~/.local/share/workshop/id/<PROJECT-ID>/<WS>/sdk/sketch/current/sdk.yaml` | none |
| System | implicit (`system`) | built into Workshop | none |

### Sketch SDKs

The quickest way to change one workshop the "Workshop way":

```bash
export EDITOR=vim            # optional
workshop sketch-sdk [WS]     # opens sdk.yaml in $EDITOR; saving refreshes the workshop
```

```yaml
# sdk.yaml as edited by sketch-sdk
name: sketch
hooks:
  setup-project: |
    source /var/lib/workshop/sdk/jupyter/venv/bin/activate
    pip install jupyter-console
plugs:
  # ...
slots:
  # ...
```

- Hooks are written **inline** under `hooks:` in the sketch file. When ejected
  they become files in `hooks/`.
- Each edit bumps the sketch revision (`x1`, `x2` and so on, shown in
  `workshop info` under `sdks: sketch:`).
- There is one sketch per workshop. It is installed last, carries no
  persistent data and does not appear in the definition.
- If the automatic refresh fails, debug it with `workshop changes`, `tasks`,
  and `refresh --continue` or `--abort`. An abort does not undo your edits:
  run `sketch-sdk` again.
- `--stash` removes it temporarily and `--restore` brings it back. There is
  only one stash slot, and the next `sketch-sdk` overwrites it.
- `--remove` deletes it. `workshop remove` also removes the sketch and its
  stash.
- `workshop sketches` lists the sketches of the project (Rev and Notes:
  current or stashed).
- `--verbose` merges hook output.

### In-project SDKs

Eject a sketch with `workshop sketch-sdk --eject --name console`. The default
name is the project directory's name. The result is:

```text
.workshop/console/
├── hooks/
│   └── setup-project
└── sdk.yaml
```

Then add it to the definition and refresh:

```yaml
sdks:
  - name: project-console
```

You can also write one by hand. Only `name` is required, and `architecture`
is assumed to match the host or `all`:

```yaml
# .workshop/ccache/sdk.yaml
name: ccache
version: "0.1"
summary: Shared ccache
description: |
  Project-specific SDK that exposes a mount target
  for preserving cache across workshop updates.
plugs:
  ccache:
    interface: mount
    workshop-target: /home/workshop/.cache/ccache
```

Use an in-project SDK for project-private tools, connections and
configuration. Commit `.workshop/`.

### Crafted SDKs (SDKcraft)

Prerequisites: install `sudo snap install --classic sdkcraft` and LXD 6.8 or
later (`sudo snap install --channel=6/stable lxd`, or `snap refresh` to that
channel). SDKcraft builds in LXD.

Start from <https://github.com/canonical/template-sdk> (see
[template-repo](sdk-shipping.md#canonical-sdk-repository-conventions-canonicaltemplate-sdk)), or run `sdkcraft init`:

```bash
sdkcraft init [--name NAME] [--profile simple] [DIR]
```

The `simple` profile creates:

```text
sdkcraft.yaml                  # name, version '0.1', summary, description, license, two platforms, nil part
hooks/setup-base               # commented apt-get example
hooks/setup-project            # commented example
tests/spread.yaml              # lxd VM backend, BASE/jammy and BASE/noble variants
tests/main/launch/task.yaml
tests/main/launch/workshop.yaml.in
```

#### Build commands

| Command | Does |
|---------|------|
| `sdkcraft pack` | Builds every platform and writes `<NAME>_<ARCH>_<BASE>.sdk` (e.g. `foo_amd64_ubuntu@24.04.sdk`) to `--output` (default `.`) |
| `sdkcraft try [SDKs...]` | Same as pack, then copies the artifacts to the Workshop **try area** (usually `$XDG_DATA_HOME/workshop/try/`) |
| `sdkcraft test [--list] [--platform P] [EXPR...]` | Packs the platforms that match the host architecture, installs Workshop and the packed SDKs (via try) in the spread environment, runs spread, and skips variants whose base was not packed. See [spread-tests](sdk-shipping.md#spread-tests-for-sdks) |
| `sdkcraft clean [--platform P] [PART...]` | Removes part assets, or the whole packing environment when no part is given |
| `sdkcraft pull/build/stage/prime [PART...]` | Run the Craft Parts lifecycle up to a step |
| `sdkcraft version` | Prints the version |

Common flags on the lifecycle commands: `--platform NAME` or
`--build-for ARCH`, `--debug` (shell into the environment on failure),
`--shell`, `--shell-after`, `--destructive-mode` (build on the host), and
`--use-lxd` (pull, build, stage, prime). Hooks are linted with ShellCheck
during packing, so a shell error fails the build.

#### The try area and `try-<NAME>`

```yaml
# workshop.yaml in some test project
name: dev
base: ubuntu@24.04           # must be one of the SDK's platforms
sdks:
  - name: try-hello          # no channel needed
```

- The try area has no channels and holds one version per SDK. That version can
  serve workshops with different bases.
- An SDK installed from the try area behaves exactly like a Store SDK.
- Workshop reuses an existing try SDK whose content digest matches, so
  re-running `sdkcraft try` with identical content and then `workshop refresh`
  is a no-op. Change something, for example bump `version`, to get a new
  revision. The `installed:` counter in `workshop info` goes from `(x1)` to
  `(x2)`.

#### Iterate

```bash
sdkcraft try                                   # or: sdkcraft clean && sdkcraft try
workshop launch --verbose --wait-on-error      # first time
workshop refresh --verbose --wait-on-error     # afterwards
workshop info                                  # SDK listed; workshop status ready
workshop changes; workshop tasks <ID>          # if not
```

`sdkcraft clean` is optional when an incremental rebuild is enough. If you
need a fresh workshop, run `workshop remove` and then `workshop launch`.
Test the SDK alone first, then with the SDKs it is meant to sit next to.

### Choosing a design (the upstream checklist)

Before writing files, decide:

- what software is packaged, and how upstream distributes it (release tarball:
  `dump` part; source: `rust`, `go` or `python` plugin; Debian package: apt in
  `setup-base`);
- what must persist across workshop updates (mount plugs);
- which network services it exposes (tunnel slots) and which hardware it needs
  (`gpu`, `camera`, `custom-device`, `desktop`);
- which credentials it needs (`secret` plug);
- which bases and architectures to build (`platforms`);
- whether it shares resources with other SDKs (mount slots that another SDK's
  plug can be connected to with `connections:`).

## sdkcraft.yaml reference

`sdkcraft.yaml` (or `.sdkcraft.yaml`) sits at the root of the SDK project,
with `hooks/` next to it. SDKcraft builds on craft-application and craft-parts
and copies `name`, `base`, `version`, `title`, `summary`, `description`,
`license`, `contact`, `issues`, `source-code`, `website`, `plugs` and `slots`
into the packed `meta/sdk.yaml`. The other keys only control the build.

### Top-level keys

| Key | Type | Notes |
|-----|------|-------|
| `name` | string, **required** | 1 to 40 characters; lowercase letters, digits and inner hyphens; at least one letter. Not `agent`, `system` or `sketch`, and must not start with `try-` or `project-` |
| `platforms` | object, **required** | See below |
| `base` | string | Runtime base: `ubuntu@22.04`, `ubuntu@24.04` or `ubuntu@26.04`. Omit it when the SDK works on any base. A workshop must use the same base |
| `build-base` | string | Build image. The reference says it is required when `base` is omitted, but see the multi-base form below |
| `version` | string | At most 32 characters. Quote it (`"1.0"`). Use the upstream version when the SDK wraps one tool. Available to parts as `$CRAFT_PROJECT_VERSION` |
| `title` | string | Human-readable title |
| `summary` | string | One line, at most 78 characters |
| `description` | string | About 100 words at most. The Canonical template rule is in [template-repo](sdk-shipping.md#the-description-rule) |
| `license` | string | License of the components actually installed; SPDX style (e.g. `MIT`, `GPL-3.0`, `LGPL-2.1`) |
| `contact`, `issues` | string, list or URL | Copied to `sdk.yaml`; Workshop ignores them |
| `source-code`, `website` | URL | Copied to `sdk.yaml`. `website` is in the JSON schema and in the copied-fields list but missing from the reference field table. `sdk info` shows `website` |
| `adopt-info` | string | Name of a part whose `craftctl set version=...` or `summary=...` provides the value at build time |
| `package-repositories` | list | Extra apt repositories for the **build** (craft-archives format) |
| `parts` | object | craft-parts definitions. If omitted, the default is `{default-part: {plugin: nil}}` |
| `plugs`, `slots` | object | Same shape as in the workshop definition; see [interfaces](workshop-usage.md#interfaces-plugs-slots-connections). Slots: `mount` and `tunnel` only |

### Platforms

A platform is a base plus a Debian architecture (`amd64`, `arm64`, `armhf`,
`i386`, `ppc64el`, `riscv64`, `s390x`), or `all` for SDKs without compiled
binaries. SDKcraft builds one artifact per platform. By default it builds every
platform that matches the build machine's architecture. A channel resolves to
a separate revision per platform.

**Single-base form.** The base comes from `base` or `build-base`, and the
platform names are architectures:

```yaml
base: ubuntu@24.04           # or build-base: ubuntu@24.04
platforms:
  amd64:
  arm64:
```

```yaml
build-base: ubuntu@24.04     # cross-build from amd64
platforms:
  amd64:   {build-on: [amd64], build-for: [amd64]}
  arm64:   {build-on: [amd64], build-for: [arm64]}
  riscv64: {build-on: [amd64], build-for: [riscv64]}
```

```yaml
platforms:                   # architecture-independent needs the long form
  all:
    build-on: [amd64, arm64, riscv64]
    build-for: all
```

**Multi-base form.** There is no `base` and no `build-base`. Each entry carries
`<BASE>:<ARCH>`, and the prefix in `build-on` must match the one in
`build-for`:

```yaml
platforms:
  ubuntu@22.04:amd64:        # shorthand: name = build-on = build-for
  ubuntu@24.04:amd64:
```

```yaml
platforms:
  noble:
    build-on: [ubuntu@24.04:amd64, ubuntu@24.04:arm64]
    build-for: ubuntu@24.04:all
  jammy:
    build-on: [ubuntu@22.04:amd64, ubuntu@22.04:arm64]
    build-for: ubuntu@22.04:all
```

The template's upload workflow distinguishes the two forms by its
`platform-flag` input: `--build-for` for single-base and `--platform` for
multi-base (see [template-repo](sdk-shipping.md#upload)).

### Parts

Parts use the standard craft-parts syntax (`plugin`, `source`, `source-type`,
`source-tag`, `organize`, `prime`, `override-build`, `build-packages` and so
on). SDKcraft adds only one restriction: **`stage-packages` and `stage-snaps`
are forbidden**. Install packages and snaps from the `setup-base` hook instead.
Everything else, including per-plugin and per-base limits, follows upstream
craft-parts:
<https://documentation.ubuntu.com/craft-parts/latest/reference/plugins/>.

Build-time variables: `$CRAFT_PROJECT_VERSION`, `$CRAFT_ARCH_BUILD_FOR`, and
the other craft-parts variables such as `$CRAFT_PART_INSTALL`. The primed
tree becomes `$SDK` in the workshop, so a file primed as `bin/foo` runs as
`$SDK/bin/foo`.

```yaml
parts:
  # Release tarball
  go:
    plugin: dump
    source: https://go.dev/dl/go$CRAFT_PROJECT_VERSION.linux-$CRAFT_ARCH_BUILD_FOR.tar.gz
    source-type: tar
  # A single file shipped with the SDK (e.g. a systemd unit), ends up at $SDK/ollama.service
  user-service:
    plugin: dump
    source: ollama.service
    source-type: file
  # Built from source
  uv:
    plugin: rust
    source: https://github.com/astral-sh/uv
    source-tag: $CRAFT_PROJECT_VERSION
    source-type: git
    organize: {uv: bin/uv, uvx: bin/uvx}
    prime: [bin/uv, bin/uvx]
  # Configuration files from a directory of the repository
  config:
    plugin: dump
    source: files
```

How to split work between parts and hooks:

| Ship as a part | Install in a hook |
|----------------|-------------------|
| Pinned versions that do not depend on the distribution archive | Debian packages (`apt-get` in `setup-base`): security updates, apt cache, smaller SDK |
| Custom builds and special compilation flags | Choices that depend on the project or on detected hardware (`setup-project`) |
| Tools that are not in the archive | Large, frequently changing content that should stay out of snapshots (`setup-project`) |

Split parts along functional lines: runtime, configuration, data assets and
tools. Parts are optional; the smallest SDK has none and does everything in
hooks.

### Worked examples

Go, with a mount plug and cross-builds:

```yaml
name: go
build-base: ubuntu@24.04
title: Go SDK
summary: The Go programming language
description: |
  Go is an open source programming language that enables the production of
  simple, efficient and reliable software at scale.
version: "1.25.1"
license: LGPL-2.1
platforms:
  amd64:   {build-on: [amd64], build-for: [amd64]}
  arm64:   {build-on: [amd64], build-for: [arm64]}
plugs:
  mod-cache:
    interface: mount
    workshop-target: /home/workshop/go/pkg/mod
parts:
  go:
    plugin: dump
    source: https://go.dev/dl/go$CRAFT_PROJECT_VERSION.linux-$CRAFT_ARCH_BUILD_FOR.tar.gz
    source-type: tar
```

Ollama, multi-base, with GPU, a models mount and a tunnel slot:

```yaml
name: ollama
version: "0.9.6"
summary: Get up and running with large language models
description: |
  Get up and running with Llama 3.3, DeepSeek-R1, Phi-4,
  Gemma 3, Mistral Small 3.1 and other large language models.
license: MIT
platforms:
  ubuntu@22.04:amd64:
  ubuntu@24.04:amd64:
plugs:
  gpu:
    interface: gpu
  models:
    interface: mount
    workshop-target: /home/workshop/.ollama/models
slots:
  ollama-server:
    interface: tunnel
    endpoint: 11434
parts:
  ollama:
    plugin: dump
    source: https://github.com/ollama/ollama/releases/download/v${CRAFT_PROJECT_VERSION}/ollama-linux-amd64.tgz
    source-type: tar
  user-service:
    plugin: dump
    source: ollama.service
    source-type: file
```

Runtime `meta/sdk.yaml` that SDKcraft writes for Go. Do not edit it by hand:

```yaml
name: go
title: Go SDK
version: "1.25.1"
summary: The Go programming language
description: |
  Go is an open source programming language ...
base: ubuntu@24.04
architecture: amd64
license: LGPL-2.1
sdkcraft-started-at: "2026-04-12T08:30:00Z"
plugs:
  mod-cache:
    interface: mount
    workshop-target: /home/workshop/go/pkg/mod
```

### Inconsistencies in the sources

- The reference says `build-base` is "required when `base` is omitted", yet
  its own multi-base example and the platform reference use neither key.
  `<BASE>:<ARCH>` platform names stand in for them.
- The summary limit is 78 characters in the reference and schema, but the
  comment in the `sdkcraft init` template says 79. Use 78.
- The Go example has only `build-base`, but the matching runtime `sdk.yaml`
  shows `base: ubuntu@24.04`.

## SDK hooks

Hooks are executable bash scripts in `hooks/<NAME>`. There are five valid names
(see below). SDKcraft finds them on its own when packing, lints them with
ShellCheck, and does not list them in `sdkcraft.yaml`. Inside the workshop the
SDK is mounted read-only at `/var/lib/workshop/sdk/<SDK>/`, with its hooks
under `hooks/`. Few SDKs need all five hooks.

### Execution contract

- Each hook runs in a non-interactive bash **login** session with `errexit` and
  `pipefail`. Any failing command or pipe stage ends the hook with that code,
  and the change fails. With `--verbose` on `launch` or `refresh`, `xtrace` is
  also set.
- `$SDK` is set in every hook. It is the SDK's install root.
- In hooks, apt is configured to skip recommended and suggested packages and to
  answer "yes" to prompts, so `apt-get install foo` needs no `-y`.
- Hooks of different SDKs run one at a time, never in parallel, in this order:
  `system`, then the listed SDKs in definition order, then `sketch`.

| Hook | User | Working directory | Extra environment |
|------|------|-------------------|-------------------|
| `setup-base` | root | the SDK's `hooks/` | none |
| `setup-project` | `workshop` (1000) | `/project` | `HOME`, `XDG_RUNTIME_DIR`, `DBUS_SESSION_BUS_ADDRESS` |
| `check-health` | root | the SDK's `hooks/` | none |
| `save-state` | root | the SDK's `hooks/` | `SDK_STATE_DIR` |
| `restore-state` | root | the SDK's `hooks/` | `SDK_STATE_DIR` |

All hooks also receive `SDK_SYSTEMD_SECRET_SOCKET`, for `LoadCredential=`
units (see [interfaces](workshop-usage.md#secrets)).

### When each hook runs

| Hook | launch | refresh | restore |
|------|--------|---------|---------|
| `setup-base` | right after the SDK is installed, before `/project` is mounted and before interfaces exist | only when the SDK layer is rebuilt: the SDK was added or changed (new revision, new definition entry), or an SDK above it, or the base, changed. Otherwise the snapshot is reused | no |
| `save-state` | no | first, from the **old** revision | yes, before the rollback |
| `setup-project` | after `/project` is mounted and auto-connect has run | yes | yes |
| `restore-state` | no | after **all** `setup-project` hooks, from the **new** revision | yes |
| `check-health` | after all `setup-project` hooks | after all `restore-state` hooks | after all `restore-state` hooks |

The output of `setup-base` is stored in the SDK's ZFS snapshot layer. Other
hooks create no snapshots, so `setup-project` work is redone every time.

Note: the build how-to says `setup-base` runs "on every workshop refresh". The
hook explanation, the workshop concepts page and the hook how-to all say a
refresh reuses unchanged layers and skips it. The latter is the precise
behaviour.

### What goes where

| `setup-base` (root, before the project and interfaces) | `setup-project` (user, after the mounts) |
|--------------------------------------------------------|------------------------------------------|
| `apt-get update && apt-get install ...` | Per-user configuration under `/home/workshop/` and `~/.profile` |
| `/etc/profile.d/<sdk>.sh` (PATH, global variables) | Seeding mount plugs, which are only connected now |
| Shell completions, `update-alternatives`, system-wide files | User systemd units: `systemctl --user enable --now` |
| System systemd units (e.g. ones that use `LoadCredential=`) | Anything that depends on the project files or on connected interfaces (GPU detection, venvs) |
| Content that rarely changes and should be in snapshots | Large or often-changing content that should stay out of snapshots |

Neither hook should build the user's project; that is what actions are for.
Both should prepare the environment rather than start services, unless there
is a specific reason to start one.

### Environment-variable conventions

- System-wide: write `/etc/profile.d/<sdk>.sh` from `setup-base`. Escape `$`
  for anything that must expand at login, and let `$SDK` expand when the hook
  runs:
  ```bash
  cat <<EOF >/etc/profile.d/hello.sh
  export PATH="$SDK/bin:\$PATH"
  EOF
  ```
- Per-user: append to `~/.profile` from `setup-project`.
- Do not use `~/.bashrc`, `~/.bash_profile` or `/etc/bash.bashrc`, because
  Workshop supports several shells.
- Use clear names prefixed with the SDK name (`HELLO_HOME`, not `HOME2`), and
  comment why each value is set.
- `/etc/profile.d` is read by login shells, which `exec`, `run`, `shell` and
  the hooks all are. From a root hook, run user commands with
  `sudo -u workshop --login CMD` so that profile scripts apply.

### workshopctl

```bash
workshopctl set-health okay
workshopctl set-health waiting "service still starting"           # message: 7-70 characters
workshopctl set-health --code=missing-cuda error "CUDA libraries not found"
workshopctl get-secret <SDK>.<PLUG>                               # see interfaces.md
```

- The message is required with `waiting` and `error` and not allowed with
  `okay`. It must be 7 to 70 characters long.
- `--code` (3 to 30 characters: lowercase letters, digits and hyphens,
  starting with a letter) is optional and cannot be used with `okay`.
- The hooks explanation says `set-health` is the "only possible use" of
  `workshopctl`. The CLI reference also documents `get-secret`, which the
  secrets how-to uses. The reference is the more recent of the two.

#### Health semantics

- `okay` with exit 0: the SDK is Ready.
- `waiting`: Workshop sleeps 1 s and runs `check-health` again. After 10
  consecutive `waiting` results the SDK goes to Error.
- `error`, a non-zero exit, no status at all, or a run longer than **5 s**:
  the SDK goes to Error.
- The workshop is Ready only when every SDK reports `okay`. With
  `--wait-on-error`, `workshop info` shows the message.

Good checks test real functionality rather than mere installation, give
specific codes and short actionable messages, run fast, and handle edge
cases.

### SDK state

`$SDK_STATE_DIR` exists only for `save-state` and `restore-state`. It is a
volume that Workshop creates per SDK for a single refresh or restore cycle,
and it is removed when the workshop stops. A refresh discards the container's
writable filesystem, so anything outside mounts and `/project` that the new
revision needs must go through it. `restore-state` must tolerate missing
input, because the old revision may not have had `save-state`. Breaking
changes in the save and restore format between revisions make refreshes fail.

### Worked hooks

`hooks/setup-base`:

```bash
apt-get update
apt-get install build-essential cmake ninja-build

cat <<EOF >/etc/profile.d/hello.sh
# hello SDK: put its binaries first on PATH.
export PATH="$SDK/bin:\$PATH"
export HELLO_SDK="$SDK"
EOF
```

`hooks/setup-project`:

```bash
# Seed the mount plug once; afterwards it belongs to the user (idempotent).
if [ ! -e "$HOME/.cache/hello/.seeded" ]; then
  cp -a "$SDK/seed/." "$HOME/.cache/hello/"
  touch "$HOME/.cache/hello/.seeded"
fi

install -D --mode=644 --target-directory ~/.config/systemd/user "$SDK/hello.service"
systemctl --user daemon-reload
systemctl --user enable --now hello
```

`hooks/check-health`:

```bash
if ! sudo -u workshop --login hello --version >/dev/null 2>&1; then
  workshopctl set-health --code=hello-broken error "hello --version failed"
  exit 0
fi
workshopctl set-health okay
```

`hooks/save-state` and `hooks/restore-state`:

```bash
# save-state (old revision)
if [ -f /home/workshop/.hello-settings ]; then
  cp /home/workshop/.hello-settings "$SDK_STATE_DIR/"
fi
```

```bash
# restore-state (new revision)
if [ -f "$SDK_STATE_DIR/.hello-settings" ]; then
  install -m 0644 -o 1000 -g 1000 "$SDK_STATE_DIR/.hello-settings" /home/workshop/
fi
```

A matching user service unit, shipped with a `dump` part whose
`source-type` is `file`:

```ini
[Unit]
Description=Hello Service
After=network.target

[Service]
ExecStart=/bin/bash -lc "hello serve"
Restart=always
RestartSec=3

[Install]
WantedBy=default.target
```

### Verifying hooks

```bash
sdkcraft try
workshop launch --verbose --wait-on-error
workshop exec -- cat /etc/profile.d/hello.sh          # setup-base ran
workshop info                                         # status: ready means check-health said okay
# To exercise save-state and restore-state, refresh must have work to do:
# change the definition (e.g. add a mount), or bump version and `sdkcraft try` again.
workshop refresh --verbose
workshop tasks                                        # shows each "Run hook ..." task and its log
```

Note: the tutorial's `check-health` passes the raw output of the failed
command as the message. That output can break the 7 to 70 character limit, so
keep messages short and point to `workshop tasks` for details.
