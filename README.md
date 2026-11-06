# auto-wp

`auto-wp.py` creates a project directory pre-loaded with the Claude Code
skills and slash commands for a long-running formal-verification campaign:
C with [Frama-C/WP](https://frama-c.com), or Rust with
[Creusot](https://github.com/creusot-rs/creusot).

```
./auto-wp.py [--c|--rust] <directory-name>
```

The generated directory is stand-alone. It has its own `README.md` with the
quick start: clone the code to analyse next to the configuration, then run
Claude Code in a container (for example `/time-loop grub 72` for a 72-hour
campaign on GRUB). Python 3.10 or later, standard library only.

## Repository layout

| Path | Contents |
|---|---|
| `auto-wp.py` | The generator |
| `templates/` | What it copies: `common/` (all projects), `c/`, `rust/` |
| `sdks/` | [Workshop](https://ubuntu.com/workshop/docs/) SDKs with the toolchains: `frama-c-sdk`, `creusot`, `rocq`, `lean` ([`sdks/README.md`](sdks/README.md)) |
| `tests/` | Program, template, container and SDK tests ([`tests/README.md`](tests/README.md)) |
| `spec/` | The specifications |

## Specifications

- [`spec/auto-wp.md`](spec/auto-wp.md): `auto-wp.py`, the generated project, and its README
- [`spec/tests.md`](spec/tests.md): the test plan
- [`spec/workshop-autowp-c-base-spec.md`](spec/workshop-autowp-c-base-spec.md),
  [`spec/workshop-autowp-rust-base-spec.md`](spec/workshop-autowp-rust-base-spec.md): the Workshop SDKs
- [`spec/gzip-test.md`](spec/gzip-test.md), [`spec/sudo-rs-test.md`](spec/sudo-rs-test.md): the GNU gzip 1.9 (C) and sudo-rs (Rust) campaign tests
- [`spec/fips-skill-spec.md`](spec/fips-skill-spec.md): the `fips-sl` skill (FIPS 140-3), draft
- [`spec/`](spec/): all of them, with review reports

## Tests

```
make test        # program and template tests (seconds)
make help        # every target: container tests, campaigns, SDK builds
```

## Campaign tests in Workshop

Two tests run a real campaign in the [Workshop](https://ubuntu.com/workshop/docs/)
of a freshly generated project, as a user would: GNU gzip 1.9 with Frama-C
([`spec/gzip-test.md`](spec/gzip-test.md) §7), and sudo-rs v0.2.15 with Creusot
([`spec/sudo-rs-test.md`](spec/sudo-rs-test.md)). The toolchains come from the
SDK Store, not from this repository.

### 1. Host set-up, once

LXD 6.8 or later and Workshop (amd64), as in the generated projects' README:

```bash
sudo snap refresh lxd --channel=6/stable   # or: sudo snap install lxd --channel=6/stable
sudo lxd init --auto                       # if LXD was never initialised
sudo snap install --classic workshop
lxc version                                # client and server 6.x
```

Your user must be in the `lxd` group. To see which SDK revisions the Store
serves, per base (`ubuntu@24.04`, `ubuntu@26.04`):

```bash
for i in rocq lean creusot frama-c-sdk; do sdk info $i; done
```

A base missing from a channel makes `workshop launch` fail with
`"<SDK>" SDK: Revision not found`.

### 2. The Claude token, once

The campaigns run Claude Code inside the workshop with a long-lived token of
your Claude subscription, separate from your own login
([`spec/tests.md`](spec/tests.md) §7.1). In your own terminal:

```bash
claude setup-token                         # sign in through the browser; it prints the token
install -d -m 700 ~/.config/auto-wp
install -m 600 /dev/null ~/.config/auto-wp/claude-oauth-token
nano ~/.config/auto-wp/claude-oauth-token  # paste the token on one line
date -u +%F > ~/.config/auto-wp/claude-oauth-token.created
ls -l ~/.config/auto-wp/                   # -rw------- claude-oauth-token
```

The tests only check that the file exists, is not empty and has mode 600 or
400; `AUTOWP_TOKEN_FILE=<path>` points them at another file. The token is
streamed through stdin into a tmpfs file in the workshop, read by the
launcher, then deleted; it never appears on a command line or in LXD's
configuration, and check K2 (G.8, S.6) verifies it was written nowhere.

### 3. Run

```bash
make smoke-c-gzip-ws                       # gzip: 1-hour /time-loop, stopped after 3 h at most
make sudo-rs-rust-ws SUDORS_HOURS=6        # sudo-rs: 6 hours + 30 min for the report
```

or directly, `WORKSHOP=1 tests/c/gzip-test.sh` and
`WORKSHOP=1 SUDORS_HOURS=6 tests/rust/sudo-rs-test.sh`. The `make` targets
keep a log in `tests/out/`. Both can run at the same time (each has its own
workshop); 16 GB of RAM is tight for two, 32 GB is comfortable.

| Variable | Effect |
|---|---|
| `SETUP_ONLY=1` | Stop after the setup checks: no token, no Claude Code, a few minutes. Use it first on a new host. |
| `SUDORS_HOURS=<n>` | sudo-rs budget in hours (default 2) |
| `KEEP=1` | Keep the workshop and the project at the end, to inspect them |
| `WORKSHOP_DIR=<dir>` | Generate the project in `<dir>` instead of a new directory under `~/.awp` |
| `WORKSHOP_BASE=ubuntu@26.04` | Rewrite the definition's `base:` (default as generated, `ubuntu@24.04`) |
| `WORKSHOP_TRY="rocq lean"` | Use `try-<name>` SDKs packed on this host with `sdkcraft try` instead of the Store |
| `IDLE_S=<s>` | Stop early when the transcript has been idle that long (default 1800) |

### 4. What a run does

1. Generates the project on the host with `auto-wp.py --c` or `--rust`, in a
   new private directory `~/.awp/autowp-<project>-ws.XXXXXX/` (W.1). It is on
   disk on purpose: `/tmp` may be a tmpfs, where a reboot would lose the
   campaign's work and the files would take RAM.
2. Adds the apt packages the code needs to
   `.workshop/autowp-packages/hooks/setup-base` (`unzip` for gzip,
   `libpam0g-dev` for sudo-rs), as the generated README tells users to.
3. `workshop launch autowp`: the SDKs are downloaded once per host (about 40
   minutes the first time, 3 minutes after), and the workshop must reach
   `ready` (W.2). W.3 checks the toolchain is the SDK's.
4. Fetches the code to analyse and checks it (G.0: gzip's archive, checksum
   and signature; S.0: sudo-rs at its pinned commit), installs Claude Code,
   moves the token in.
5. Starts Claude Code in `tmux` in the workshop and types the campaign
   request, then waits for it to finish.
6. Runs the checks on the result (G.1–G.11, S.1–S.8; the tables are in the
   two specs), prints `SUMMARY: <passed>, <failed>, <skipped>`, and removes
   the workshop and the project directory unless `KEEP=1`.

### 5. Watch a running campaign

```bash
cd ~/.awp/autowp-gzip-analyze-ws.*/gzip-analyze      # or ...sudo-rs-analyze-ws.*/sudo-rs-analyze
workshop exec autowp -- tmux capture-pane -p -t autowp | tail -40   # the Claude Code screen
workshop shell                                       # then: tmux attach -r -t autowp (read-only)
```

Detach from `tmux` with `Ctrl-b d`; do not type into the session, the test
is driving it. The campaign's files are in the project directory on the
host, which the workshop sees as `/project`.

## Licence

GPL-3.0 ([`LICENSE`](LICENSE)). The SDKs bundle third-party tools under
their own licences; Alt-Ergo, in `frama-c-sdk` and `creusot`, is for
non-commercial use only ([`sdks/README.md`](sdks/README.md)).
