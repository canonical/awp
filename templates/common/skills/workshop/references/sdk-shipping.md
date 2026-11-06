# Shipping SDKs: repository, tests, Store

Load when setting up an SDK repository, writing spread tests, or publishing to the SDK Store.

- [Canonical SDK repository conventions (canonical/template-sdk)](#canonical-sdk-repository-conventions-canonicaltemplate-sdk)
- [Spread tests for SDKs](#spread-tests-for-sdks)
- [Publishing to the SDK Store](#publishing-to-the-sdk-store)

## Canonical SDK repository conventions (canonical/template-sdk)

New SDKs start from <https://github.com/canonical/template-sdk>. Use GitHub's
"Use this template" button, or `git clone` it. CI calls reusable workflows from
<https://github.com/canonical/sdkcraft-actions>.

### Layout

```text
my-sdk/
├── .github/workflows/
│   ├── build.yml            # PR to a version branch: build
│   ├── upload.yml           # push to a version branch: build, upload, release
│   ├── forward-port.yml     # push to main: forward-port to long-term branches
│   ├── renovate.yml         # scheduled Renovate run
│   └── renovate-check.yml   # PR touching renovate.json: validate it
├── .gitignore               # *.sdk  (+ .spread-reuse.yaml, see below)
├── README.md                # from the README template below
├── VERSION                  # upstream release the SDK wraps; bumped by Renovate
├── renovate.json
├── sdkcraft.yaml
├── hooks/                   # setup-base, setup-project, check-health, save-state, restore-state
└── tests/                   # spread suite, see spread-tests.md
    ├── spread.yaml
    └── main/<task>/{task.yaml,workshop.yaml.in}
```

According to the build how-to, the template contains `sdkcraft.yaml`, hook
stubs, `VERSION`, `renovate.json`, the CI workflows and a README template.
The tests skeleton comes from `sdkcraft init`. Fill in `sdkcraft.yaml`,
replace the hook stubs, set `VERSION` to the first upstream release you ship,
and adapt `renovate.json` if upstream releases are not on GitHub.

The docs do not show how `VERSION` reaches `sdkcraft.yaml`. One option the
`sdkcraft.yaml` keys allow is a part named in `adopt-info` that runs
`craftctl set version="$(cat VERSION)"`. Otherwise keep `version:` and
`VERSION` in step by hand. Check what the template ships before choosing.

#### Branches

- `main` holds shared work. `forward-port.yml` propagates its commits to the
  long-term branches listed in the repository variable `LONG_TERM_BRANCHES`.
- Each **version branch** tracks one upstream line. Use a major-only name
  (`20`, `22`, `24`, pattern `[0-9]+`) or a major.minor name (`1.24`, `7.1`,
  pattern `[0-9]+.[0-9]+`). Renovate bumps `VERSION` on each one. Merging a
  bump triggers `upload.yml`, which uploads and releases a new revision.
- Pick one pattern and use it in both `build.yml` and `upload.yml`. The
  template ships `"[0-9]+"` in `build.yml` and `"[0-9]+.[0-9]+"` in
  `upload.yml`, both marked TODO.

### .gitignore

```gitignore
# sdkcraft build artifacts
*.sdk

# spread reuse state (left behind when spread keeps instances for reuse)
.spread-reuse.yaml
```

The template ships only the `*.sdk` rule. Add the `.spread-reuse.yaml` rule
because `spread` writes that file next to `tests/spread.yaml` when a run keeps
its instances. The Workshop project itself ignores `.spread-reuse.*`.

### renovate.json

The template's version, with placeholders to fill:

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": ["config:recommended"],
  "enabledManagers": ["custom.regex"],
  "customManagers": [
    {
      "customType": "regex",
      "managerFilePatterns": ["/^VERSION$/"],
      "matchStrings": ["(?<currentValue>[0-9.]+)"],
      "depNameTemplate": "TODO_DEP_NAME",
      "datasourceTemplate": "TODO_DATASOURCE",
      "versioningTemplate": "semver"
    }
  ],
  "baseBranchPatterns": ["TODO_BRANCH"],
  "packageRules": [
    {
      "matchPackageNames": ["TODO_DEP_NAME"],
      "matchBaseBranches": ["TODO_BRANCH"],
      "allowedVersions": "/^TODO_VERSION_PREFIX\\./"
    }
  ]
}
```

- `depNameTemplate` and `datasourceTemplate` name the upstream package and its
  Renovate datasource, for example `github-releases` with `owner/repo` as the
  name.
- Add one `packageRules` entry per version branch. Each pins that branch to
  its own line through `allowedVersions` (e.g. `/^1\.24\./` on branch
  `1.24`) and lists the branch in `baseBranchPatterns`.

### Workflows

#### build.yml

```yaml
name: Build SDK
on:
  pull_request:
    branches:
      - "[0-9]+"            # TODO: your version-branch pattern
concurrency:
  group: ${{ github.workflow }}-${{ github.ref || github.run_id }}
  cancel-in-progress: true
jobs:
  build:
    uses: canonical/sdkcraft-actions/.github/workflows/build.yml@main
```

The template quotes the pattern as `- \"[0-9]+\"`. Write it as an ordinary
YAML string, `"[0-9]+"`, as `upload.yml` does.

#### upload

```yaml
name: Build and Upload SDK
on:
  push:
    branches:
      - "[0-9]+.[0-9]+"     # TODO: your version-branch pattern
  workflow_dispatch:
    inputs:
      branch:
        description: "Branch name (e.g., 1.0)"
        required: true
        type: string
concurrency:
  group: ${{ github.workflow }}-${{ github.ref || github.run_id }}
  cancel-in-progress: true
jobs:
  build-and-upload:
    uses: canonical/sdkcraft-actions/.github/workflows/upload.yml@main
    with:
      platforms: '["amd64"]'
      platform-flag: "--build-for"
    secrets:
      SDKCRAFT_STORE_CREDENTIALS: ${{ secrets.SDKCRAFT_STORE_CREDENTIALS_STAGING }}
```

| `sdkcraft.yaml` form | `platforms` input | `platform-flag` |
|----------------------|-------------------|-----------------|
| Single-base (`build-base` set; architecture platform names) | `'["amd64"]'` or `'["amd64","arm64","riscv64"]'` | `--build-for` (default) |
| Multi-base (no `build-base`; `ubuntu@...` platform names) | `'["ubuntu@22.04:amd64","ubuntu@24.04:amd64"]'` | `--platform` |

The template points at a **staging** secret so that a new SDK does not publish
to production by accident. To go live, run `sdkcraft login --export
credentials.txt` and store the file's content as the repository secret
`SDKCRAFT_STORE_CREDENTIALS_PROD`. Then change the mapping to
`${{ secrets.SDKCRAFT_STORE_CREDENTIALS_PROD }}`. The docs do not say which
channel the reusable workflow releases to; read `canonical/sdkcraft-actions`.

#### forward-port.yml, renovate.yml, renovate-check.yml

```yaml
# forward-port.yml
name: Forward-Port from Main
on:
  push:
    branches: [main]
permissions: {contents: write, issues: write, pull-requests: write}
jobs:
  forward-port:
    uses: canonical/sdkcraft-actions/.github/workflows/forward-port.yml@main
    with:
      long-term-branches: ${{ vars.LONG_TERM_BRANCHES }}
```

```yaml
# renovate.yml
name: Renovate
on:
  schedule:
    - cron: "0 4 * * 1-5"
  workflow_dispatch:
permissions: {contents: write, pull-requests: write, issues: write}
jobs:
  renovate:
    uses: canonical/sdkcraft-actions/.github/workflows/renovate.yml@main
    secrets:
      token: ${{ secrets.GITHUB_TOKEN }}
```

```yaml
# renovate-check.yml
name: Renovate check
on:
  pull_request:
    paths: [renovate.json]
jobs:
  renovate-check:
    uses: canonical/sdkcraft-actions/.github/workflows/renovate-check.yml@main
```

### The description rule

The `description` in `sdkcraft.yaml` must match the README's overview
paragraph so that `sdk info` can reuse it. Write it as a short YAML block
string, with no headings and no bullet lists:

```yaml
description: |
  This SDK provides [toolchain/runtime] for [purpose].
  [Key resources] are persisted on the host to speed up [builds/installs]
  across workshop updates.
```

Approved examples:

```yaml
# go
description: |
  This SDK provides the official Go toolchain for efficient Go
  development. Module downloads are persisted on the host to speed up builds
  across workshop updates, and Go environment settings are preserved between
  workshop updates.
# node
description: |
  This SDK provides a complete Node.js development environment built from
  source, with Corepack enabled for flexible package manager choice. Package
  manager caches are persisted on the host to speed up dependency
  installations across workshop updates.
```

### README template

Rules:

- Title: "[Software Name] SDK for Workshop".
- The overview is 2 or 3 compound sentences: what it is, what it does and who
  it is for. Describe how it changes the environment, without marketing
  language; avoid phrases like "focus on writing and testing code".
- Describe the SDK's behaviour and link upstream for the product itself.
- Do not include "Installed components" or "Platforms, channels, versions"
  sections. Fold the components into the overview; channels belong in
  `sdk info`.
- Say "workshop updates" (not "restarts" or "sessions") when describing what
  mounts survive.
- Mark whether each command runs on the host or in the workshop. Test every
  command before publishing.
- Remove sections that do not apply, replace every `[placeholder]`, and delete
  the guidance comment.

Skeleton:

````markdown
# [Software Name] SDK for Workshop

[Overview: the same text as sdkcraft.yaml `description`.]

---

## Reference workshop

A minimal workshop:

```yaml
## workshop.yaml
name: [workshop-name]
base: ubuntu@[version]
sdks:
  - name: [sdk-name]
    channel: [channel]

actions:
  [action-name]: |
    [command]
```

[One sentence on what this demonstrates.]

---

## Using the SDK

### Prerequisites, project layout

1. [Prerequisite SDKs, e.g. "This relies on the `uv` SDK for venv."]
2. [Expected project layout and preparation commands.]
3. [Side effects during launch and refresh.]

### [Primary workflow task]

Once the workshop is ready:

```bash
[workshop run ...]
```

[Where outputs go and how they persist across workshop updates.]

### [Secondary workflow task]

From within the workshop shell:

```bash
workshop shell
[commands]
```

---

## Plugs (resources this SDK consumes)

### `[plug-name]`

- Interface: `mount`
- Workshop target: `[/path/inside/workshop]`
- Purpose: [What this persists between workshop updates.]

### `gpu`

- Interface: `gpu`
- Purpose: Grants access to [AMD/NVIDIA] GPU hardware on the host.

[Or: "This SDK doesn't define any plugs."]

## Slots (resources this SDK provides)

### `[slot-name]`

- Interface: `mount`
- Workshop source: `[/path/inside/workshop]`
- Purpose: [What resource this exposes to other SDKs]

[Or: "This SDK doesn't define any slots."]

---

## Documentation and guidance

- [[XYZ] official documentation]([upstream-docs-url])

---

## Community and support

- [XYZ] community forum: [link]
- Please review our [Code of Conduct](https://ubuntu.com/community/ethos/code-of-conduct)
  before participating.

---

## Contributions

All contributions, including code, documentation updates, and issue reports,
are welcome!

- See [CONTRIBUTING]([public-github-url]) for guidelines.
- Open issues or pull requests on the [official repository]([repo-url]).

---

## License and copyright

Copyright [START YEAR] [COPYRIGHT HOLDER].

[License name, link, and the claims or notices of every shipped component.]
````

Document tunnels together with the other plugs and slots. If the SDK depends
on resources from another SDK, or exposes resources to others, say so
explicitly in these sections.

## Spread tests for SDKs

SDK tests are <https://github.com/canonical/spread> suites under `tests/`.
The publisher writes and maintains them; SDKcraft only runs the harness. Each
task describes one user workflow, run end to end in a fresh LXD machine that
has Workshop and the packed SDK installed.

```bash
sdkcraft test                    # all tasks
sdkcraft test --list             # show the jobs that would run
sdkcraft test main/              # one suite
sdkcraft test main/launch        # one task (spread expression)
sdkcraft test --platform P       # restrict the platform
```

Compared with running `spread` yourself, `sdkcraft test` also packs the SDK
for every platform that matches the host architecture, copies the packed SDKs
into the test machine with `sdkcraft try`, installs Workshop there, and skips
variants for bases it did not pack.

### Layout

```text
tests/
├── spread.yaml
├── lib/                         # optional shared fixtures (copied by tasks)
└── main/                        # suite "main/"
    ├── launch/                  # starter task from `sdkcraft init`
    │   ├── task.yaml
    │   └── workshop.yaml.in
    └── <other-task>/
        ├── task.yaml
        └── workshop.yaml.in
```

### tests/spread.yaml

This is what `sdkcraft init` generates:

```yaml
project: hello

path: /home/ubuntu/project

backends:
  lxd:
    systems:
      - ubuntu-24.04:
          username: ubuntu
          vm: true               # an LXD VM, so workshops (LXD containers) can run inside

suites:
  main/:
    summary: Test SDK inside workshops with different bases
    environment:
      BASE/jammy: ubuntu@22.04   # one variant per base: <VAR>/<variant-name>: value
      BASE/noble: ubuntu@24.04
```

- `BASE/<codename>` creates one variant of every task in the suite per base.
  Inside a task, `$BASE` holds the value. Declare one variant for each base
  in `sdkcraft.yaml` `platforms`; for 26.04 add
  `BASE/resolute: ubuntu@26.04`.
- The backend system is the test machine. The workshop's base is
  independent of it and is chosen by `$BASE`.

### task.yaml

Template task (`tests/main/launch/task.yaml`):

```yaml
summary: Launch workshop with hello SDK

prepare: |
  envsubst '${BASE}' <workshop.yaml.in >workshop.yaml
  workshop launch

restore: |
  workshop remove || true

execute: |
  # workshop exec -- hello --version

debug: |
  workshop tasks
```

Template definition (`tests/main/launch/workshop.yaml.in`):

```yaml
name: test-hello
base: ${BASE}
sdks:
  - name: try-hello
```

Section semantics:

| Section | Runs | Use for |
|---------|------|---------|
| `summary` | | One line shown in reports |
| `details` | | Optional longer explanation |
| `prepare` | before `execute` | Render `workshop.yaml`, copy fixtures, `workshop launch` |
| `execute` | the test | Commands and assertions; any failing command fails the task |
| `restore` | always, even after a failure | `workshop remove \|\| true` and removal of the files the task created |
| `debug` | only after a failure | Dump `workshop tasks`, `workshop info` and logs |

The task directory is the working directory and also the workshop **project**
directory. `envsubst '${BASE}'` replaces only `${BASE}` (the quoted argument
limits it to that variable), producing `workshop.yaml` for the current
variant. The SDK appears as `try-<name>` because `sdkcraft test` installed it
through the try area.

### Assertions: MATCH and NOMATCH

Spread provides these shell helpers inside tasks. They read standard input
and take an extended regular expression; on failure they print the input:

```bash
workshop info | MATCH '^status: +ready'          # also proves every check-health said okay
workshop exec -- hello --version | MATCH '^hello 1\.2\.'
workshop exec -- sh -c 'hello lint bad.txt' >out.log 2>&1 || true
MATCH 'error: ' <out.log
NOMATCH 'PANIC|Segmentation fault' <out.log
```

Other common patterns:

```bash
# Expect a specific exit status without tripping errexit
rc=0; workshop exec -- hello bad-input || rc=$?; test "$rc" = 2

# Run in the workshop, not on the host; -w sets the working directory
workshop exec -w /tmp/proj -- make

# Inspect structured info (yq is not documented as available; check first)
workshop info | yq '.sdks["hello"].installed'
```

Run builds that write many files in a directory inside the workshop (for
example by copying `/project/x` to `/tmp/x`), not in `/project`, which is the
host's task directory.

### Worked example: persistence across restore and refresh

```yaml
summary: The cache mount survives restore and refresh; the container FS does not

prepare: |
  envsubst '${BASE}' <workshop.yaml.in >workshop.yaml
  workshop launch

restore: |
  workshop remove || true
  rm -f workshop.yaml

execute: |
  workshop exec -- sh -c 'echo keep > ~/.cache/hello/marker'   # mount plug
  workshop exec -- sudo touch /etc/hello-marker                 # container FS

  workshop restore test-hello
  workshop info test-hello | MATCH '^status: +ready'
  workshop exec -- test ! -e /etc/hello-marker
  workshop exec -- cat /home/workshop/.cache/hello/marker | MATCH '^keep$'

  workshop refresh test-hello                                   # no-op if nothing changed
  workshop info test-hello | MATCH '^status: +ready'
  workshop exec -- cat /home/workshop/.cache/hello/marker | MATCH '^keep$'

debug: |
  workshop info test-hello || true
  workshop tasks || true
```

### Good tests

- Give each task one workflow: launch and health, the primary user command,
  persistence, failure modes, interaction with companion SDKs.
- Make `restore` idempotent and always remove the workshop. Ignore errors
  with `|| true`.
- Keep fixtures in `tests/lib/` and copy them into the task directory in
  `prepare`.
- Keep tests offline where possible. Pin what they depend on.
- To exercise `save-state` and `restore-state`, the refresh must have work to
  do. Bump `version` in `sdkcraft.yaml` and run `sdkcraft try` again, or
  change the definition, then check that the `installed:` counter changed.

## Publishing to the SDK Store

The Store-side commands use the live SDK Store at `api.charmhub.io` with an
Ubuntu One account. They have no dry-run mode. Finish building, trying and
testing first.

### Concepts

- **Name**: global. You register it once, with any Ubuntu One account, and
  afterwards only the publisher and collaborators can upload or release under
  it. Names normally cannot be registered again after release. Use the same
  `name` as in `sdkcraft.yaml`.
- **Revision**: an immutable uploaded artifact, one per platform. An
  unreleased revision is invisible to `sdk find`.
- **Channel**: `[<TRACK>/]<RISK>[/<BRANCH>]`, a pointer to a revision per
  platform. Releasing moves the pointer and never rebuilds anything.
  Workshops pick up the new revision at their next `refresh`.
  - Track: defaults to `latest`, which always exists. Other tracks group
    version lines (`1.x`, `1.26`) or variants (`nvidia`). **Do not use a base
    (`24.04`) as a track**; the Store already separates revisions by
    platform.
  - Risk: `stable`, `candidate`, `beta`, `edge`.
  - Branch: optional and short-lived, e.g. `1.2.3/edge/issue-56789`. It
    expires after 30 days without activity.
- In `sdk info`, an arrow (`↑`) in the CHANNELS table means the risk follows
  the one above it.

### Manual flow

```bash
sdkcraft pack                                  # or: sdkcraft clean && sdkcraft pack
sdkcraft login                                 # Ubuntu One email, password, OTP; needs a keyring
sdkcraft whoami
sdkcraft register hello                        # once per SDK, ever
sdkcraft upload hello_amd64_ubuntu@24.04.sdk                     # prints the revision
sdkcraft upload hello_amd64_ubuntu@22.04.sdk --release latest/edge
sdkcraft revisions hello                       # channels and revisions (no base column)
sdk info hello                                 # what users get: version and revision per base
sdkcraft release hello 8 latest/stable         # promote an existing revision
sdkcraft release hello 9 beta,edge             # comma-separated channels
sdkcraft logout
```

- Upload **one artifact per platform**. Each upload creates a revision for
  that platform.
- `--release` takes a comma-separated list of channels.
- `release` is idempotent and prints the channel map.

#### Non-default tracks

```bash
sdkcraft create-track --track 1.26 --track 1.25 go
```

A track can be created only if it matches a Store **guardrail** for the SDK.
Guardrails are not self-service: open an issue at
<https://github.com/canonical/workshop/issues> naming the SDK and the track
pattern (e.g. `1.x`).

### CI flow (template repositories)

With the `canonical/template-sdk` workflows (see
[template-repo](#canonical-sdk-repository-conventions-canonicaltemplate-sdk)):

1. Register the name once by hand: `sdkcraft register <NAME>`.
2. Run `sdkcraft login --export credentials.txt`. This writes the credentials
   to a file with mode 0600 and leaves the local keyring untouched.
3. In GitHub, go to Settings, Secrets and variables, Actions. Add a new
   repository secret `SDKCRAFT_STORE_CREDENTIALS_PROD` with the file's
   content, then delete the file.
4. In `upload.yml`, change
   `SDKCRAFT_STORE_CREDENTIALS: ${{ secrets.SDKCRAFT_STORE_CREDENTIALS_STAGING }}`
   to `..._PROD`.
5. From then on, Renovate opens a PR that bumps `VERSION` on a version
   branch. Merging it triggers `upload.yml`, which builds, uploads and
   releases the revision.

Any non-interactive use reads exported credentials from the environment:

```bash
export SDKCRAFT_STORE_CREDENTIALS=$(cat credentials.txt)
```

### Consuming the result

```yaml
name: dev
base: ubuntu@24.04             # must match one of the SDK's platforms
sdks:
  - name: hello
    channel: latest/stable
```

```bash
sdk find hello                 # Store search (name, title, summary, description, publisher)
sdk info hello [--base ubuntu@24.04] [--arch all]
sdk list                       # SDK volumes on this machine
```
