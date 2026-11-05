# Using and operating workshops

Load when writing a workshop definition, running `workshop` commands, wiring interfaces, or diagnosing a workshop.

- [Using workshops](#using-workshops)
- [Interfaces: plugs, slots, connections](#interfaces-plugs-slots-connections)
- [Troubleshooting workshops and SDKs](#troubleshooting-workshops-and-sdks)

## Using workshops

### Projects and definition files

A **project** is a directory that holds one or more workshop definitions.
`workshop launch` ties the project to its workshops through a hidden
`.workshop.lock` file. Keep that file in the project, never copy it, and add it
to `.gitignore`. Commit the definitions and `.workshop/` itself.

| Layout | File |
|--------|------|
| One workshop | `workshop.yaml` or `.workshop.yaml` at the project root |
| Several workshops | `.workshop/<NAME>.yaml`; `<NAME>` must equal `name:` |
| In-project SDKs | `.workshop/<SDK>/sdk.yaml` (or `.workshop/<SDK>/meta/sdk.yaml`), hooks in `.workshop/<SDK>/hooks/` |

When there are several workshops you cannot omit the workshop name in commands.
Workshop tracks moves and copies of the project directory. If you delete the
directory without first running `workshop remove`, the workshop is orphaned
(see [troubleshooting](#orphaned-workshops)).

#### Top-level keys

| Key | Required | Notes |
|-----|----------|-------|
| `name` | yes | Starts with a lowercase letter; lowercase letters, digits and inner hyphens; at most 40 characters |
| `base` | yes | `ubuntu@22.04`, `ubuntu@24.04` or `ubuntu@26.04`. An SDK that declares a `base` must use the same one |
| `sdks` | no | Ordered list; `system` is installed first implicitly |
| `connections` | no | `- plug: <SDK>:<PLUG>` / `slot: <SDK>:<SLOT>` pairs proposed to auto-connect |
| `actions` | no | `name: bash script` |
| `runtime` | no | `lxd-container` (default) or the experimental `lxd-vm`. The VM how-to documents this key, but the definition reference table omits it |

#### SDK entries

```yaml
sdks:
  - name: go                 # Store SDK
    channel: "1.26"          # <TRACK>/<RISK>/<BRANCH>, at least one part; default latest/stable
  - name: try-mysdk          # from the try area (filled by `sdkcraft try`); channel ignored
  - name: project-tools      # in-project SDK at .workshop/tools/
  - name: system             # only to graft plugs or slots onto the system SDK
    plugs:
      app:
        interface: tunnel
        endpoint: 127.0.0.1:8090
  - name: consumer
    plugs:
      cache:
        bind: go:mod-cache   # bind to another SDK's plug (no other attributes allowed)
```

- Name length: at most 40 characters for the bare name, 44 with `try-`, 48
  with `project-`. `agent` is reserved.
- `channel` has no effect for `try-`, `project-` and `system` SDKs, but must
  still be well formed. Quote values that look numeric (`"1.26"`).
- `plugs` and `slots` under an entry **graft** extra interface endpoints onto
  that SDK, or bind a plug. See [interfaces](#interfaces-plugs-slots-connections).

#### Actions

```yaml
actions:
  lint: |
    go vet
    golangci-lint run
  tests: go test "$@"
```

- An action name starts with a lowercase letter and contains lowercase
  letters, digits and inner hyphens.
- The body is bash with `errexit` and `pipefail` set. Arguments after the
  action name arrive as `"$@"`, `"$1"` and so on.
- Actions are read lazily, so an edit works immediately without a refresh.
  They are not part of the snapshot layers.
- `workshop actions [WS]` lists them as YAML.

#### Creating a definition from the CLI

```bash
workshop init dev --sdks go,uv                 # writes .workshop/dev.yaml
workshop init dev --base ubuntu@22.04 --sdks go/1.26/stable
workshop init dev --runtime lxd-vm             # runtime: lxd-container (default) or lxd-vm
```

### Command reference

Global flags: `-h/--help`, `-p/--project DIR`, `-v/--version`. The workshop
name is optional when the project has a single workshop.

| Command | Purpose and key flags |
|---------|-----------------------|
| `workshop launch WS...` | Build workshops from Off. `--verbose` (merge hook stdout and stderr; sets `xtrace` in hooks), `--wait-on-error` (single workshop only; pause instead of reverting), `--continue`, `--abort`, `--no-wait`. If several workshops are listed and one fails, none is built. Running it again on a launched workshop fails |
| `workshop refresh WS...` | Apply definition and SDK changes. Workshop must be **Ready**. Same flags as launch. Keeps manual `connect`s and manual `disconnect`s (unless the disconnect used `--forget`). On failure it reverts to the previous snapshot |
| `workshop restore WS...` | Roll the container filesystem back to the last successful launch or refresh, and reset connections and remount sources to their defaults. Workshop must be Ready. Transactional across several workshops. `--verbose`, `--no-wait` |
| `workshop exec [WS] [--] CMD...` | Run a command. Workshop must be Ready or Waiting. `-w/--cwd` (default `/project`), `--env K=V` or `--env K` (inherit from the caller), `--uid`/`--gid` (default 1000; `--uid 0` for root), `--timeout` (e.g. `30s`), `-i` to force interactive, `-I` to force non-interactive. Without `--`, the first argument is taken as the workshop name |
| `workshop shell [WS]` | Login shell of the `workshop` user (a shorthand for exec) |
| `workshop run [WS] [--] ACTION ARGS...` | Run a named action; same flags as exec |
| `workshop info [WS]` | YAML: name, base, project, hostname, status, runtime, notes, SDKs (tracking, installed date and revision), mounts, tunnels |
| `workshop list [--global]` | Project workshops with their status. `--global` covers all projects but omits Off workshops |
| `workshop changes` | Recent changes in the project: ID, Status, Spawn, Ready, Summary |
| `workshop tasks [ID]` | Tasks of a change (the latest by default), with logs from failed hooks |
| `workshop start WS...` / `workshop stop WS...` | Start (sets Ready) or stop a launched workshop |
| `workshop remove WS...` | Stop and delete the workshop. Keeps the definition and project files. Deletes the default mount directories but keeps remount sources. Refused if any listed workshop is Off or Pending |
| `workshop connect` / `disconnect` / `connections` / `remount` | See [interfaces](#interfaces-plugs-slots-connections) |
| `workshop sketch-sdk` / `workshop sketches` | See [sdk-development](sdk-authoring.md#sketch-sdks) |
| `workshop warnings [--all] [--verbose]` / `workshop okay` | List and acknowledge system-wide warnings, such as a broken mount |

Inside a workshop, `exec`, `run` and `shell` run login shells as uid/gid
1000. `XDG_RUNTIME_DIR` is `/run/user/1000` and the session bus is at
`/run/user/1000/bus`. Using other IDs can break sessions. The host user maps to
`workshop` (1000:1000), so files created in `/project` belong to you on the
host. The `workshop` user can use `sudo` without a password.

Every running workshop has the hostname `<WORKSHOP>.<PROJECT>.wp`. Workshops in
the same project reach each other by the bare `<WORKSHOP>` name.

### Launch, refresh, restore

| Command | When | Filesystem effect | Connections |
|---------|------|-------------------|-------------|
| `launch` | Workshop is Off | Base image, then each SDK with its `setup-base` and a ZFS snapshot per SDK layer | All auto-connect candidates connected |
| `refresh` | Definition changed, or new SDK revisions on the channels | Reuses snapshots of unchanged SDK layers; SDKs added, removed or changed (and every SDK listed after them) are reinstalled | Re-evaluated; manual connects kept; manual disconnects stay disconnected |
| `restore` | Discard runtime drift | Rolls the container filesystem back to the snapshot of the last good launch or refresh; ignores definition edits since then | Back to the definition's defaults; manual connects dropped, manual disconnects reconnected |

Order at launch: install the base, then `system` and its `setup-base`, then a
snapshot. Then each SDK in list order with its `setup-base` and a snapshot,
then `sketch`. Then the time zone, the `/project` mount, interface setup and
auto-connect. Then `setup-project` for all SDKs, then `check-health` for all
SDKs.

Order at refresh (as seen in `workshop tasks`): retrieve SDKs, create the SDK
state storage, run `save-state` (old revision), disconnect interfaces,
uninstall, stash the old workshop, restore from the deepest unchanged
snapshot, then install and run `setup-base` for the changed SDKs. Then mount
the project, resolve and auto-connect interfaces, run `setup-project`, run
`restore-state` (new revision), run `check-health`, remove the state storage
and drop the stash.

A refresh with nothing to apply does nothing and runs no hook. Workshop 0.1.29
prints `no updates available`. Edits to `actions` never need a refresh.

`refresh` pulls the latest revision of each SDK from its channel. To change
version, edit `channel` and refresh. SDK files are mounted read-only, so their
own updaters cannot update them inside the workshop.

After a Workshop snap upgrade, existing workshops pick up the new features
(and the new embedded `system` SDK) at their next `refresh`. Until then,
`restore`, `launch --continue` and `refresh --continue` are refused. Workshop
is not forward compatible: to downgrade, remove and reinstall the snap, which
deletes all workshops.

### What persists

| Location | `stop`/`start` | `refresh` | `restore` | `remove` |
|----------|----------------|-----------|-----------|----------|
| Project directory (`/project`, a host directory) | kept | kept | kept | kept |
| Mount plug, default host source (`~/.local/share/workshop/id/<PROJECT-ID>/<WS>/mount/<SDK>/<PLUG>/`) | kept | kept | kept (connection reset) | **deleted** |
| Mount plug remounted to your own host directory | kept | kept (last remount reapplied) | kept on disk, but the plug goes back to its default source | kept |
| Container filesystem (`/etc`, `/usr`, `/home/workshop` outside mounts, `/tmp`) | kept | rebuilt from snapshots, so changes outside SDK layers are lost | rolled back to the last launch or refresh | deleted |
| Data copied by `save-state` into `$SDK_STATE_DIR` | n/a | handed to `restore-state` | handed to `restore-state` | n/a |

`$SDK_STATE_DIR` is a temporary volume for one refresh or restore. It is
removed when the workshop stops, so do not use it for long-lived data; use a
mount plug or the project directory.

Each workshop keeps an apt cache at `/var/cache/apt/archives`. It is deleted
with the workshop.

### Statuses

| Status | Meaning | Accepted transitions |
|--------|---------|----------------------|
| Off | Defined only; no container | `launch` gives Ready, Error, or Waiting with `--wait-on-error` |
| Ready | Running and usable | `stop`, `remove`, `remount`, `refresh` |
| Stopped | Container stopped, still linked to the project | `start`, `remount` |
| Pending | A change is in progress; few commands accepted | (wait) |
| Waiting | Paused mid-change for debugging; `exec`, `shell` and `run` work | `launch --continue` or `--abort`; `refresh --continue` or `--abort` |
| Error | Nonfunctional | `remove` |

The workshop reaches Ready only when every SDK's `check-health` reports
`okay`, so `workshop info | grep -E 'status:\s+ready'` doubles as a health
assertion. In `workshop info` the SDK entry shows `installed: <date> (N)` or
`(xN)` for local SDKs; N counts installed revisions.

### Multiple workshops and git

- One project with several workshops (`.workshop/a.yaml`, `.workshop/b.yaml`)
  can share in-project SDKs. Workshops in the same project reach each other by
  hostname.
- A git worktree is a separate project, which is useful for testing another
  base. Git commands fail inside its workshop because the worktree's `.git`
  file points outside the mount, so run git on the host.
- In CI, the `canonical/launch-workshop@v1` GitHub Action installs Workshop
  and launches the workshop. Its inputs include `workshop` and `cache`, which
  takes `<SDK>:<PLUG>` lines to persist mount plugs through the GitHub cache.
  Pin it to a commit SHA in production.

### Storage

On Linux, workshops live in an LXD ZFS storage pool named `workshop` (Btrfs on
WSL). When the pool is 90% or more full, the daemon enters degraded mode and
refuses commands that change state. Free space or grow the pool with
`lxc storage set workshop size=<N>GiB`; LXD never shrinks a pool. Do not use
`zfs` or `btrfs` directly on it.

### Virtual machine runtime

VM workshops are experimental. Opt in first with
`sudo snap set workshop workshop.experimental-vms=1 && sudo snap restart workshop.workshopd`.
Then set `runtime: lxd-vm` in the definition (`workshop init NAME --runtime lxd-vm`
writes it for you). The runtime is fixed at launch, and most interfaces are
unsupported. Each mount uses a virtual PCIe port: there are 8 for
`system`, 4 more per SDK, and 192 at most. Exceeding the budget gives
`No unused PCIe ports available` errors.

## Interfaces: plugs, slots, connections

An interface is a predefined resource type; you cannot create custom ones. A
**slot** provides a resource and a **plug** consumes it. Host resources are
exposed only through slots of the built-in **system** SDK. A regular SDK can
declare slots only for `mount` and `tunnel`.

The same plug and slot shape is used in `sdkcraft.yaml`, `sdk.yaml` and the
workshop definition, where it is grafted onto an SDK entry.

### The eight interfaces

| Interface | Plug name | Plug attributes | Slot | Auto-connect |
|-----------|-----------|-----------------|------|--------------|
| `mount` | any | `workshop-target` (required, absolute, `$SDK` allowed), `mode`, `uid`, `gid`, `read-only` | `system:mount` (host); regular SDK slot with `workshop-source` | Partial: to `system:mount` only, unless a `connections:` entry names a regular SDK slot |
| `tunnel` | any | `endpoint` (default `localhost/tcp`) | any SDK, `endpoint` | Partial: host to workshop only (a plug on `system`, a slot on a regular SDK), same name or a `connections:` entry, plug endpoint loopback or Unix socket |
| `gpu` | must be `gpu` | none | `system:gpu` | Yes |
| `ssh-agent` | must be `ssh-agent` | none | `system:ssh-agent` | No |
| `secret` | any | none | system SDK only, added in the workshop definition with `attributes` (and optionally `collection`) | No |
| `desktop` | must be `desktop` | none | `system:desktop` (Wayland socket) | No |
| `camera` | must be `camera` | none | `system:camera` | No |
| `custom-device` | any | `subsystem`, `vendorid`, `productid` (at least one; `productid` needs `vendorid`; quote IDs) | `system:custom-device` | No |

Plugs of every interface are declared by regular SDKs, not by the system SDK.
The exception is `tunnel`, whose plugs can also be grafted onto `system` to
expose workshop services on the host.

#### Mount details

```yaml
plugs:
  cache:
    interface: mount
    workshop-target: /home/workshop/.cache/foo   # created if missing
    # mode: 0o775    # default 0o775, or 0o755 when the resolved uid is 0
    # uid: 1000      # default 1000 under /home/workshop/, /project/, /run/user/1000/; else 0
    # gid: 1000      # same path rule, even if uid is set explicitly
    # read-only: false
slots:
  venv:
    interface: mount
    workshop-source: /home/workshop/uv-venv      # must already exist when connecting
```

- Ownership and mode apply only to directories that Workshop creates. An
  existing path keeps its ownership and permissions.
- The SDK install tree is read-only, so a target inside `$SDK` works only
  where the SDK already ships that directory.
- The default host source is
  `~/.local/share/workshop/id/<PROJECT-ID>/<WS>/mount/<SDK>/<PLUG>/` under
  `$XDG_DATA_HOME`. An SDK cannot choose a host path; users can, with
  `workshop remount`.
- A newer SDK revision that drops a plug removes the connection, but the
  host-side content remains.

#### Tunnel endpoints

`<ADDRESS>/<PROTOCOL>`, where any part may be omitted: `8080`,
`127.0.0.1:8080`, `localhost:8080/tcp`, `1234/udp`, `'[::1]:8080/tcp'`. A Unix
socket is `/path` (`$HOME` and `$XDG_RUNTIME_DIR` are expanded) or
`'@abstract'`. Quote values that start with `[` or `@`. Hostnames are not
resolved; only `localhost`, `ip6-localhost` and `ip6-loopback` are accepted. A
port may be omitted on one side only. Tunnel plugs on the system SDK cannot
use ports below 1024, nor sockets outside `$HOME` and `$XDG_RUNTIME_DIR`. UDP
plugs connect only to UDP slots. Tunnels between two regular SDKs, or within
`system`, are not supported: clients connect directly.

```yaml
# SDK exposes a service; the user exposes it on the host
# sdkcraft.yaml of "ollama"
slots:
  ollama-server:
    interface: tunnel
    endpoint: 11434
# workshop.yaml
sdks:
  - name: ollama
  - name: system
    plugs:
      ollama-server:              # same name, so it auto-connects
        interface: tunnel
        endpoint: 127.0.0.1:11434
```

A system plug on a non-loopback address such as `0.0.0.0:8081` exposes the
service to the network and must be connected manually.

### Wiring in the workshop definition

```yaml
sdks:
  - name: uv
    slots:                       # graft a slot the publisher did not declare
      api: {interface: tunnel, endpoint: 8000}
  - name: jupyter
  - name: torchvision
    plugs:
      hub:
        bind: torchaudio:hub     # bind: share another plug's target, resolving conflicts
connections:
  - plug: jupyter:venv           # mount plug to a regular SDK slot (otherwise system:mount)
    slot: uv:venv
  - plug: system:app             # names differ, so an explicit entry is needed
    slot: uv:api
```

- A `connections:` entry only **proposes** a pairing to auto-connect, and the
  interface policy still applies. Entries for `ssh-agent` and `secret` produce
  nothing; use `workshop connect`. The `<SDK>` part may be empty
  (`:ssh-agent`) to mean `system`.
- A bound plug carries no other attributes. It cannot belong to `system`,
  cannot bind to a bound plug, and cannot also appear in `connections:`.
- When several slots are eligible for a plug, the order is not guaranteed.
  Write the pairing down in `connections:`.

### Runtime commands

```bash
workshop connections [WS] [--all]                  # --all also lists disconnected plugs
workshop connect WS/SDK:PLUG                       # target defaults to WS/system:PLUG
workshop connect WS/SDK:PLUG :SLOT                 # WS/system:SLOT
workshop connect WS/SDK:PLUG WS/OTHER              # the only slot of the same interface on OTHER
workshop connect WS/SDK:PLUG WS/OTHER:SLOT
workshop disconnect WS/SDK:PLUG [--forget]         # --forget: auto-connect again at the next refresh
workshop disconnect WS/system:mount                # disconnect every plug from a slot
workshop remount WS/SDK:PLUG ~/some/host/dir       # new host source for a mount plug
```

- Connections made with `connect` show `manual` in `workshop connections`.
  Bound plugs show `bind.<N>`.
- Several plugs can connect to one slot, but a plug connects to only one slot.
- `remount` works atomically when the new source is missing, or empty and on
  the same filesystem. Otherwise the workshop must be **Stopped**. `refresh`
  reapplies the last remount. To return to the default source:
  `workshop disconnect WS/SDK:PLUG --forget && workshop refresh WS`.
- After a `try-` SDK is installed, its plugs use the SDK's own name, without
  the prefix: `workshop connect dev/mysdk:api-key dev/system:key`.

How each connection type behaves across `refresh` and `restore`:

| Connection | After refresh | After restore |
|------------|---------------|---------------|
| Auto-connection still valid | re-established | re-established |
| Manual `connect` still valid | kept | dropped |
| Plug or slot removed from the definition | dropped | n/a |
| Auto-connection manually disconnected | stays disconnected (unless `--forget`) | reconnected |

### Secrets

The user stores an item in the host keyring and adds a slot to `system`:

```yaml
sdks:
  - name: system
    slots:
      demo-key:
        interface: secret
        attributes: {service: secret-demo, account: test}   # must match exactly one item
        # collection: default
  - name: secret-demo
```

```bash
secret-tool store --label="Secret demo" --collection=default service secret-demo account test
workshop connect dev/secret-demo:api-key dev/system:demo-key
```

The SDK declares `plugs: {api-key: {interface: secret}}` and asks for the
value when it needs it: `workshopctl get-secret secret-demo.api-key`. Exit
codes: 0 ok, 1 not found, 2 provider locked, 3 plug not connected, 4 several
matches, 255 other. Delivery patterns for SDK authors:

| Consumer | Mechanism |
|----------|-----------|
| Tool with a credential-helper setting | configure the helper as `workshopctl get-secret <SDK>.<PLUG>` |
| Command that reads stdin | pipe from `workshopctl get-secret` |
| Command that needs an env var | an SDK wrapper script that exports the variable only for the `exec`'d tool and keeps a value the user already set |
| systemd service | `LoadCredential=<SDK>.<PLUG>:${SDK_SYSTEMD_SECRET_SOCKET}` in a unit installed by `setup-base`; read `$CREDENTIALS_DIRECTORY/<SDK>.<PLUG>` |
| One-off value | the user passes `workshop exec --env NAME ...` |

Each request creates a `Retrieve secret` change, which never contains the
value. Never print the value, never use `set -x` around it, and never write it
to files.

### Security reminders

Only the `workshop` user can use host resources exposed through interfaces.
Connected `ssh-agent`, `secret`, `desktop`, tunnels, devices and writable host
mounts all extend what processes inside the workshop can reach. See
[ai-agents](ai-agents.md#security-boundaries).

## Troubleshooting workshops and SDKs

### First steps

```bash
workshop info [WS]                 # status, notes, SDK health messages
workshop changes                   # find the failed change (Status Error; no Ready time)
workshop tasks [ID]                # its tasks; failed hooks print their log after the table
workshop launch|refresh --verbose  # merge hook stdout and stderr, set xtrace in hooks
```

A failed task appears as, for example,
`Error  1m12.5s  Run hook "setup-base" for "go" SDK`. The tasks after it show
`Hold`, and earlier tasks that were rolled back show `Undone`. The hook's log
lines follow the table.

### Pause on error instead of reverting

```bash
workshop launch --wait-on-error     # or: workshop refresh --wait-on-error (one workshop only)
# workshop is now Waiting: inspect it
workshop shell                      # or: workshop exec -- ...
workshop refresh --continue         # after fixing it in place
workshop refresh --abort            # revert, as if --wait-on-error had not been used
```

If you edit the **definition** while paused, you must `--abort` and start
again. After a Workshop snap upgrade, `--continue` is refused on workshops
that have not yet been refreshed.

### Typical failures

| Symptom | Likely cause and fix |
|---------|----------------------|
| `Run hook "setup-base" ... exit code 1` | A command failed under `errexit`. Check the log in `workshop tasks`. Network problems (DNS) show up here |
| SDK in Error after `check-health` | It reported `error`, exited non-zero, set no status, took more than 5 s, or stayed `waiting` 10 times. Check the message in `workshop info` |
| `set-health` itself fails | The message must be 7 to 70 characters; `--code` is not allowed with `okay` |
| A command works in `workshop shell` but not in a hook | The hook runs as root from `hooks/` (except `setup-project`). Use `sudo -u workshop --login` |
| `PATH` or variables missing | They were written to `~/.bashrc` instead of `/etc/profile.d` or `~/.profile`, or a non-login shell is in use |
| Writing to `$SDK` fails | The SDK tree is mounted read-only. Write under `/home/workshop`, a mount plug, or a system path from `setup-base` |
| A mount plug target is empty in `setup-base` | Mounts connect after `setup-base`. Seed them in `setup-project` |
| `save-state` and `restore-state` never ran | The refresh had nothing to do. Change the definition or install a new revision (bump `version`, then `sdkcraft try`) |
| `workshop launch` fails on an existing workshop | Use `refresh`; `launch` only builds from Off |
| Refresh refused | The workshop must be Ready (`workshop start`, or `remove` if it is in Error) |
| The base is not accepted | The workshop `base` is not among the SDK's platforms, or the SDK declares a different `base` |
| A plug is not connected | Its interface does not auto-connect (`ssh-agent`, `secret`, `desktop`, `camera`, `custom-device`), or a tunnel's plug and slot names differ, or a mount slot is on a regular SDK without a `connections:` entry. Use `workshop connect`, then check with `workshop connections --all` |
| `workshop warnings` reports a broken mount | The remount source no longer exists. Recreate it, or `disconnect --forget` and `refresh`. Acknowledge with `workshop okay` |
| An SDK tool cannot update itself | The SDK is read-only. Run `workshop refresh` (pulls from the channel) or change `channel` |
| Daemon refuses changes and reports pool usage | The storage pool is 90% or more full. Remove workshops or SDKs, or `lxc storage set workshop size=<N>GiB` |

### Isolate the SDK

When several SDKs fail together, comment them out one at a time in the
definition and refresh after each change. Test a new SDK alone in a
throwaway project with `try-<name>` before combining it with others.

### Installation and LXD

```bash
snap info workshop                                     # installed version
sudo snap install --channel=6/stable lxd               # LXD 6.8+ required by sdkcraft
sudo snap start --enable lxd.daemon && sudo snap services lxd
sudo usermod -a -G lxd $USER
sudo snap logs workshop                                # daemon logs
sudo lxc list --all-projects                           # workshops live in LXD project workshop.<USER>
sudo lxc info --show-log <container> --project workshop.<USER>
sudo snap set lxd daemon.debug=true && sudo snap restart lxd.daemon
```

### Orphaned workshops

If a project directory was deleted before `workshop remove`, the workshop
becomes orphaned. `workshop list --global` shows it in Error with a
`missing-project` note, and commands that resolve the project by path, such as
`remove`, no longer work. Recover the data with
`sudo lxc shell <name>-<id> --project workshop.<USER>`, or delete the
container with `sudo lxc delete <name>-<id> --project workshop.<USER>`. Then
remove the leftover host directories under
`~/.local/share/workshop/id/<PROJECT-ID>/`. The upstream purge guide on the
public docs site describes a more aggressive cleanup.

### Reporting

Workshop and SDKcraft move fast. Use the latest releases; older ones may have
known bugs. Report issues at <https://github.com/canonical/workshop/issues>.
