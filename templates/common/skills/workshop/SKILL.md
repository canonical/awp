---
name: workshop
description: "Create, test, publish and use Canonical Workshop SDKs and workshops. Use when writing or debugging a workshop definition (workshop.yaml, .workshop/<name>.yaml), running workshop launch/exec/shell/run/info/refresh/restore/remove/changes/tasks, wiring interfaces (mount, tunnel, gpu, ssh-agent, secret, desktop, camera, custom-device) with connect/disconnect/remount, or diagnosing a workshop stuck in Waiting or Error. Or when authoring an SDK: sketch SDKs (workshop sketch-sdk), in-project SDKs (.workshop/<name>/sdk.yaml), sdkcraft.yaml, hooks (setup-base, setup-project, check-health, save-state, restore-state), workshopctl, sdkcraft init/pack/try/test, spread tests, canonical/template-sdk layout (README, renovate.json, sdkcraft-actions workflows), publishing with sdkcraft login/register/upload/release. Or: \"my workshop won't start\", \"package a toolchain as an SDK\", \"push an SDK to the store\". Not for snapcraft, rockcraft, charmcraft, Docker, devcontainers, plain LXD/LXC or Nix, unless relating them to Workshop."
---

# Workshop SDKs and workshops

Workshop runs development environments ("workshops") in LXD containers. A
workshop is built from a **base** (Ubuntu image) plus an ordered list of
**SDKs**. SDKs are built with **SDKcraft** and distributed through the **SDK
Store** on channels. Four CLIs are involved:

| CLI | Who uses it | For |
|-----|-------------|-----|
| `workshop` | users | launch and operate workshops, wire interfaces, sketch SDKs |
| `sdk` | users | `sdk find`, `sdk info`, `sdk list` (Store search, local SDK volumes) |
| `sdkcraft` | SDK publishers | `init`, `pack`, `try`, `test`, `clean`, Store commands |
| `workshopctl` | SDK hooks and wrappers, inside a workshop | `set-health`, `get-secret` |

Public docs: <https://ubuntu.com/workshop/docs/>. Append `.md` to any page URL
for Markdown; `llms.txt` and `llms-full.txt` are at the docs root.

## Core principles

**The definition is the source of truth.** Everything a workshop needs goes in
its definition and its SDKs. Ad-hoc changes made with `workshop shell` or
`workshop exec` live in the container filesystem, which `refresh` rebuilds and
`restore` rolls back.

**Know what persists.** Only these survive a refresh or restore: the project
directory (mounted at `/project`), mount-plug directories (which live on the
host), and whatever `save-state` copies to `$SDK_STATE_DIR` and
`restore-state` reads back (both hooks are in the table under
[SDK essentials](#sdk-essentials)). See [persistence](references/workshop-usage.md#what-persists).

**Hooks are bash, strict and ordered.** Each hook runs with `errexit` and
`pipefail`. SDKs run in a fixed order: `system`, then the SDKs in the order
they are listed, then `sketch`. There is no dependency resolution: list
an SDK after any SDK it relies on.

**Design for refresh.** Hooks must be idempotent and must tolerate missing
input. A new SDK revision can be installed onto a workshop whose old revision
had no `save-state` hook.

**Verify every mutating command.** After `launch`, `refresh`, `restore`,
`connect` and similar commands, check `workshop info`, then `workshop changes`
and `workshop tasks <ID>` if anything failed.

## Which path?

| Situation | Do this | Reference |
|-----------|---------|-----------|
| Use existing SDKs in a project | Write `workshop.yaml`, then `workshop launch` | [workshop-usage](references/workshop-usage.md#using-workshops) |
| Add a tool to one workshop quickly | `workshop sketch-sdk` | [sdk-authoring](references/sdk-authoring.md#sketch-sdks) |
| Keep project-only setup in the repository | In-project SDK in `.workshop/<name>/`, listed as `project-<name>` | [sdk-authoring](references/sdk-authoring.md#in-project-sdks) |
| Package software for everybody | SDKcraft project from `canonical/template-sdk` | [sdk-authoring](references/sdk-authoring.md#sdkcraftyaml-reference) |
| Repository layout, README, CI | Canonical template conventions | [sdk-shipping](references/sdk-shipping.md#canonical-sdk-repository-conventions-canonicaltemplate-sdk) |
| Automated tests for an SDK | spread tests and `sdkcraft test` | [sdk-shipping](references/sdk-shipping.md#spread-tests-for-sdks) |
| Put it on the Store | `sdkcraft register/upload/release` | [sdk-shipping](references/sdk-shipping.md#publishing-to-the-sdk-store) |
| Plugs, slots and connections | | [workshop-usage](references/workshop-usage.md#interfaces-plugs-slots-connections) |
| Workshop in Waiting or Error, hook failed | | [workshop-usage](references/workshop-usage.md#troubleshooting-workshops-and-sdks) |
| Running an AI agent in a workshop | | [ai-agents](references/ai-agents.md) |

## Minimal workshop definition

One workshop per project: `workshop.yaml` (or `.workshop.yaml`) at the project
root. Several workshops: `.workshop/<NAME>.yaml`, where `<NAME>` equals the
`name:` field.

```yaml
name: dev                    # lowercase letters, digits, hyphens; <= 40 chars
base: ubuntu@24.04           # ubuntu@22.04 | ubuntu@24.04 | ubuntu@26.04
sdks:
  - name: go                 # Store SDK; try-<NAME> = try area; project-<NAME> = .workshop/<NAME>/
    channel: "1.26"          # <TRACK>/<RISK>/<BRANCH>; default latest/stable; quote numeric values
actions:                     # run with `workshop run [<WS>] -- <action> args...`
  tests: go test "$@"        # bash with errexit+pipefail; edits apply without refresh
```

## Daily commands

```bash
workshop launch [--verbose] [--wait-on-error]      # build from Off; fails if already launched
workshop info [WS]                                 # YAML: status, SDKs, mounts, tunnels
workshop exec [WS] -- CMD...                       # default user workshop (uid 1000), cwd /project
workshop shell [WS]                                # login shell as the workshop user
workshop run [WS] -- ACTION ARGS...                # named action from the definition
workshop refresh [WS] [--wait-on-error]            # apply definition or SDK updates; must be Ready
workshop restore [WS]                              # roll the container FS back to the last launch/refresh
workshop changes ; workshop tasks [ID]             # what happened and why it failed
workshop stop|start [WS] ; workshop remove [WS]    # remove keeps the definition and the project files
workshop list [--global]
```

The workshop name is optional when the project has a single workshop. Use
`-p/--project DIR` to point at another project directory.

## SDK essentials

An SDK has a **build-time** definition, `sdkcraft.yaml`, written by the
publisher, and a **runtime** definition, `meta/sdk.yaml`, which SDKcraft
generates. In-project and sketch SDKs have only an `sdk.yaml`, which you write
yourself, with no `parts`, `platforms` or `build-base`.

```yaml
# sdkcraft.yaml (minimal, multi-base)
name: hello                  # reserved: agent, system, sketch, try-*, project-*
version: "1.2.3"             # quote it
summary: One line, at most 78 characters
description: |
  This SDK provides ... Caches are persisted on the host to speed up builds
  across workshop updates.
license: MIT
platforms:
  ubuntu@22.04:amd64:
  ubuntu@24.04:amd64:
plugs:
  cache:
    interface: mount
    workshop-target: /home/workshop/.cache/hello
parts:
  hello:
    plugin: dump             # stage-packages and stage-snaps are forbidden
    source: https://example.com/hello-${CRAFT_PROJECT_VERSION}-${CRAFT_ARCH_BUILD_FOR}.tar.gz
    source-type: tar
```

Hooks live in `hooks/<name>`. They are executable bash scripts, linted with
ShellCheck at pack time and not listed in `sdkcraft.yaml`.

| Hook | Runs as | Working dir | Extra env | When |
|------|---------|-------------|-----------|------|
| `setup-base` | root | SDK `hooks/` | none | install or revision change; output goes into the base snapshot |
| `setup-project` | `workshop` | `/project` | `HOME`, `XDG_RUNTIME_DIR`, `DBUS_SESSION_BUS_ADDRESS` | launch, refresh, restore; after the mounts and auto-connect |
| `check-health` | root | SDK `hooks/` | none | after all `setup-project` hooks (and after `restore-state` on refresh) |
| `save-state` | root | SDK `hooks/` | `SDK_STATE_DIR` | refresh and restore, **old** revision, before teardown |
| `restore-state` | root | SDK `hooks/` | `SDK_STATE_DIR` | refresh and restore, **new** revision, after all `setup-project` hooks |

Every hook gets `$SDK`, the SDK's read-only install root
(`/var/lib/workshop/sdk/<SDK>`). Details, examples and `workshopctl` are in
[sdk-authoring](references/sdk-authoring.md#sdk-hooks).

**Publisher loop:**

```bash
sdkcraft init                         # sdkcraft.yaml, hooks/, tests/ skeleton
sdkcraft try                          # pack each platform, copy to the try area
# workshop.yaml: sdks: [{name: try-hello}] ; base must match a platform
workshop launch --verbose --wait-on-error
# edit, then: sdkcraft try && workshop refresh   (sdkcraft clean for a clean rebuild)
sdkcraft test                         # spread suite in fresh LXD VMs
sdkcraft login && sdkcraft register hello
sdkcraft upload hello_amd64_ubuntu@24.04.sdk --release latest/edge
sdk info hello                        # what the Store serves: version, base, rev
```

**Is it on the Store?** After an upload, check what users will get with
`sdk info`, not `sdkcraft revisions`: its CHANNELS table gives one line per
base (`ubuntu@24.04`, `ubuntu@26.04`) with version and revision, while
`sdkcraft revisions` has no base column and needs a keyring. For several
SDKs at once:

```bash
for i in rocq lean creusot frama-c-sdk; do sdk info $i; done
```

A definition whose `base:` has no line under its channel fails at launch with
`"<SDK>" SDK: Revision not found`. Right after an upload, the new revision
can take a while to show up; `sdk info` tells you when it has.

## Best practices (from the upstream guidance)

- Install Debian packages with `apt-get` in `setup-base`. In hooks, apt skips
  recommended and suggested packages and assumes "yes". Ship pinned or custom
  binaries as parts instead.
- Set system-wide environment in `/etc/profile.d/<sdk>.sh` from `setup-base`.
  Set per-user environment in `~/.profile` from `setup-project`. Never use
  `~/.bashrc`, `~/.bash_profile` or `/etc/bash.bashrc`. Prefix variables with
  the SDK name and comment why each one is set.
- Use mount plugs for caches and data that must survive workshop updates. An
  SDK cannot choose the host directory; users can `workshop remount` it.
- Prefer user-level systemd services, enabled from `setup-project` with
  `systemctl --user enable --now`.
- `check-health` must test real functionality, finish within 5 s, and call
  `workshopctl set-health okay` or `error "<message, 7-70 chars>"`. Run user
  commands with `sudo -u workshop --login ...`.
- Make every hook idempotent. For example, seed a mount only if it is empty,
  and guard `restore-state` with `[ -f "$SDK_STATE_DIR/..." ]`.
- Do not put secrets in SDK content, hooks, definitions, profiles or logs.
  Declare a `secret` plug and use `workshopctl get-secret <SDK>.<PLUG>`.

## Gotchas

- A `refresh` with nothing to apply is a no-op that runs no hooks. Workshop
  0.1.29 prints `no updates available`. To exercise `save-state` and
  `restore-state`, change the definition or install a new SDK revision.
  Re-running `sdkcraft try` with identical content does not create a new
  revision; bump `version`.
- `restore` resets connections to what the definition gives, drops manual
  `connect`s, reconnects manual `disconnect`s, and resets `remount` sources
  to their defaults. The host-side mount content survives.
- `workshop remove` deletes the default host directories behind mount plugs.
  Sources set with `remount` are kept.
- Never delete a project directory before running `workshop remove`, or the
  workshop is orphaned. Add `.workshop.lock` to `.gitignore`.
- The workshop `base` must match one of the SDK's platforms. An SDK that
  declares a `base` only installs on workshops with that base.
- Git commands fail inside a workshop launched from a git worktree. Run them
  on the host.

## References

Each file opens with a contents list. Load the one that matches the task:

- [workshop-usage](references/workshop-usage.md): load when writing a
  workshop definition, running `workshop` commands, wiring interfaces, or
  diagnosing a workshop.
  - Using workshops: definition files, every `workshop` command,
    launch/refresh/restore, persistence, statuses, projects
  - Interfaces: the eight interfaces, attributes, auto-connection rules,
    `connections:`, `bind:`, connect, disconnect, remount, secrets
  - Troubleshooting: changes and tasks, wait-on-error, health, warnings, LXD,
    orphaned workshops
- [sdk-authoring](references/sdk-authoring.md): load when creating or
  changing an SDK.
  - Developing SDKs: sketch, in-project and crafted SDKs, `sdk.yaml`, the
    `sdkcraft` build commands, the try area, the iteration loop
  - sdkcraft.yaml: every key, platform forms, parts and plugins, examples
  - Hooks: the hook contract, environment variables, `workshopctl`, state,
    health, worked hooks
- [sdk-shipping](references/sdk-shipping.md): load when setting up an SDK
  repository, writing tests, or publishing.
  - Repository conventions: the `canonical/template-sdk` layout, README
    template, description rule, renovate, workflows, branches
  - Spread tests: `tests/spread.yaml`, `task.yaml`, `workshop.yaml.in`, MATCH
    and NOMATCH, `sdkcraft test`
  - Publishing: login, register, tracks, upload, release, revisions,
    channels, CI credentials
- [ai-agents](references/ai-agents.md): load when running an AI agent in a
  workshop: LLM-readable docs, the upstream agent skills, agent SDKs, the
  security boundaries
