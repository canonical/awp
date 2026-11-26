# auto-wp

`auto-wp.py` creates a project directory pre-loaded with the agent skills and
slash commands for a long-running formal-verification campaign thanks to 
[Squeeze Loops](https://github.com/canonical/squeeze-loop). Supported languages
are C with [Frama-C/WP](https://frama-c.com) + 
[macsl](https://github.com/canonical/macsl), and Rust with
[Creusot](https://github.com/creusot-rs/creusot). The generated project works
with Claude Code, GitHUb Copilot or with OpenCode.

## Example with gzip

Things to install
```bash
# install lxd if not installed
sudo snap install --channel=6/stable lxd
# install workshop if not installed
sudo snap install --classic workshop
```

Clone the awp repo:
```bash
git clone git@github.com:canonical/awp.git
cd awp/
# create a directory named `gzip-1.15-analyze` (or any other name) to analyze a C program
# and install harness opencode (could be also claude|copilot|none)
./auto-wp.py --c --driver rmf --harness opencode gzip-1.15-analyze
cd gzip-1.15-analyze
# now launch  the Workshop:
workshop launch
workshop shell
```
That opens a shell in `/project` in the container pointing to `awp/` on the host. Now in the
Workshop container type:
```bash
# get the source code we want to analyse, gzip in this example
wget https://ftp.gnu.org/gnu/gzip/gzip-1.15.zip
sudo apt install unzip
unzip gzip-1.15.zip
# launch the harness that was installed previously by `auto-wp.py`
opencode --dangerously-skip-permissions   # log in with /connect and choose model
```
Once logged in, to run a loop for 96 hours on the repo `gzip-1.15/` type:
```
/time-loop gzip-1.15 96
```

### Get back to it

1. Detach — F6 (or Ctrl-b d, since the backend is tmux). The campaign keeps
   running. Then `exit` leaves the container.
2. Reconnect — from the host, in the generated directory:

```
workshop shell
```

Unless the project was generated with `--no-byobu`, `workshop shell`
auto-attaches to the persistent byobu session, so the running campaign is
right there again.

## Command line option


```
./auto-wp.py [-h] [--c|--rust] [--driver rmf|fips] [--level 1|2|3|4]
             [--harness claude|opencode|copilot|none]
             [--local-inference|--no-local-inference] [--no-byobu]
             [<directory-name>]
```

Missing choices are asked in order: language, harness, then directory, only
when both stdin and stderr are terminals. There are no language or harness
defaults; Enter does not select an answer. Fully explicit commands never
prompt. Scripts must supply all three choices, for example:

```sh
./auto-wp.py --c --harness claude foobar
```

Run `./auto-wp.py` in a terminal to answer all three questions, or
`./auto-wp.py --rust foobar` to choose just the harness. Directory answers
are literal paths: internal spaces need no quotes, and `~` is not expanded.
EOF exits 1; Ctrl-C exits 130 and rolls back generation.

`claude` selects Claude Code; `opencode` selects OpenCode; `copilot`
selects GitHub Copilot CLI for supervised, manual use; `none` leaves
harness installation to you inside `workshop shell`. Workshop installs the
selected harness without credentials; login happens inside the container.
`--harness copilot` and interactive choice 3 install the standalone CLI
and document in-container login. Automated `HARNESS=copilot` campaigns
remain gated on the runtime spike ([`spec/choose-harness.md`](spec/choose-harness.md)).

### Local inference (OpenCode)

`--harness opencode` can drive a model on your own network instead of a cloud
provider. `--local-inference` writes `~/.config/opencode/opencode.json` in the
container, pointing OpenCode at an OpenAI-compatible server (Ollama, for
example) and starting it on that model; `--no-local-inference` keeps the cloud
provider. With neither flag, OpenCode is the one harness that gets a fourth
question — asked after the harness and before the directory, and only when
both stdin and stderr are terminals:

```text
Use a local inference server for OpenCode?
1. No (connect OpenCode to a cloud provider)
2. Yes (an OpenAI-compatible server on your network, such as Ollama)
Type 1 or 2:
```

Scripts are unaffected: when the question cannot be asked the answer is "no",
which generates exactly what earlier versions did. The options are only
accepted next to `--harness opencode`; anywhere else they are a usage error.

The generated configuration is tuned for a single-slot local runner, where a
long prompt takes far longer than any cloud call. Every value has an
`AUTOWP_INFERENCE_*` override, documented with its default and its reason at
the top of
[`templates/common/harness/opencode-local-inference.sh`](templates/common/harness/opencode-local-inference.sh):

- `headerTimeout` is one hour. No response header is sent until the prompt has
  been processed, so OpenCode's 5-minute default aborts turns the server would
  have finished — it then retries three times and halts the session.
- OpenCode's Ollama discovery is disabled. It takes over any provider named
  `ollama` and replaces its `settings`, which would silently drop those
  timeouts, so `package` and `models` are given explicitly instead.
- Subagents get a second server of their own, on port 11435. A subagent's
  prompt shares almost no prefix with its parent's, so on one server it
  evicts the parent's prompt cache and the next parent turn reprocesses the
  whole context.
- `limit` declares the context window (120000) and output budget (16000) on
  every model entry. Undeclared, OpenCode falls back to its own assumption —
  262144 in 2.3.2 — so `compaction.buffer: "50%"` compacted at about 131k
  tokens, where measured decode is 28.9 tok/s against 45–52 under 60k. The
  declared window must stay at or below the servers' `OLLAMA_CONTEXT_LENGTH`:
  OpenCode sizes prompts against its own figure, never the server's.
- `compaction.keep.tokens` is 15000 rather than 24000, since kept text is
  re-read after every compaction and compactions are now more frequent.
- `tool_output` caps a single tool result at 300 lines / 12 KiB, against a
  default of 2000 / 50 KiB that let one 48.9k-character command output into
  the context.
- `reasoning_effort` is `low` for the `build` agent, set on its request body
  rather than through a model variant: 83.5 % of decode tokens measured as
  invisible reasoning, and a variant changes the model id, which on a
  resolution failure falls back to a cloud model without saying so.

The host address is **not** configured here and not hardcoded anywhere. It is
read from `.local-llm-machine-ip.txt`, one line holding the address, the same
file this project already uses to reach the cross-provider judge
(`skills/sl-auditor/SKILL.md`, `no_ceiling_gate.py`, `skills/time-loop/SKILL.md`).
Put it **in the project directory**, which is mounted into the workshop:

```sh
echo 192.0.2.10 > <project>/.local-llm-machine-ip.txt
```

`auto-wp.py` does that for you when the machine generating the project has its
own `~/.local-llm-machine-ip.txt`, so the usual case needs no manual step.

The container's own `~/.local-llm-machine-ip.txt` is read first and takes
precedence, but it cannot be what a **first** launch uses: there is nowhere to
put it until the launch has created that home. The hook that writes the
configuration therefore lives in `setup-project`, which Workshop runs after
mounting the project and as the workshop user — not in `setup-base`, which
runs before the mount and as root. A snippet there found no address and
skipped silently on every first launch.

The **model** name, unlike the address, is never discovered: it is
`AUTOWP_INFERENCE_MODEL` or the default, so the configuration can name a model
the server does not have. The hook asks the server's `/api/tags` once and
warns if it is missing, listing what is served and the `ollama pull` that
would fix it — advisory only, so the configuration is still written (the model
can be pulled later) and a server that is simply down is reported as
unchecked. `AUTOWP_INFERENCE_CHECK=0` skips the request.

If no location has the file, the hook writes no configuration and prints both
paths it tried, rather than guessing an address — the same rule `sl-auditor`
applies to the judge. Provisioning still succeeds, so you can create the file
and `workshop refresh` to apply it.

Both servers must then be reachable from the container before a campaign
starts. On the LLM host:

```sh
OLLAMA_HOST=0.0.0.0 OLLAMA_KEEP_ALIVE=2h ollama serve
OLLAMA_HOST=0.0.0.0:11435 OLLAMA_KEEP_ALIVE=2h ollama serve
```

Two things about those servers are easy to get wrong and expensive:

- **Give both the same `OLLAMA_CONTEXT_LENGTH`, at or above the declared
  `limit.context`.** OpenCode sizes prompts against that single declared
  window, so a server with a smaller one truncates prompts silently —
  corrupting the reasoning without an error anywhere.
- **Keep the runners loaded between cycles.** A runner that unloads takes its
  prompt cache with it, so the next cycle reprocesses the whole context from
  scratch — minutes of prompt processing per wake at campaign-sized contexts.
  `OLLAMA_KEEP_ALIVE` must comfortably exceed the watchdog's wake interval.

An existing `opencode.json` is never overwritten, so edits survive
`workshop refresh`.

By default the workshop is set up so that `workshop shell` auto-attaches to a
persistent [byobu](https://www.byobu.org/) session (tmux backend, with
tmux-resurrect/continuum so the session survives a container restart): detach
with F6, reconnect with `workshop shell`, and the running campaign is right
there again. Pass `--no-byobu` to skip that configuration; `workshop shell`
then opens a plain shell and you manage `tmux` yourself. `--no-byobu` removes
the `setup-project` hook that configures byobu, so under `--local-inference`
that hook is recreated carrying only the configuration writer.

The generated directory is stand-alone. It has its own `README.md` with the
quick start: clone the code to analyse next to the configuration, then run
your agent harness in a container (for example `/time-loop grub 72` for a
72-hour campaign on GRUB). Python 3.10 or later, standard library only.

It is also a git repository with one commit already in it: `auto-wp.py` runs
`git init -b main` in the project and commits what it generated, so the
campaign's own checkpoints have a baseline to diff against instead of starting
from `No commits yet on main`. `./auto-wp.py foobar` always yields
`foobar/.git`, including inside another repository — the project then is a
nested repository, which keeps the campaign's checkpoints in its own history
and leaves the containing one untouched (git does not recurse into a nested
repository, so it sees one untracked directory). A directory that is *already*
a repository is left exactly as it is, with the generated files unstaged for
its owner to commit. If git has no `user.name` and `user.email` the commit is
skipped with a warning and the tree is left staged.

`--driver fips` also copies the FIPS 140-3 corpus, `specs/`, into the
project. Only its index is in git; import the documents once before
generating ([`specs/README.md`](specs/README.md)):

```sh
specs/import-specs.py --checklist ../NIST-Specs/FIPS-Checklist ../NIST-Specs
./auto-wp.py --c --harness claude --driver fips --level 1 gnutls-fips
```

## Repository layout

| Path | Contents |
|---|---|
| `auto-wp.py` | The generator |
| `templates/` | What it copies: `common/` (all projects), `c/`, `rust/` |
| `specs/` | The FIPS 140-3 corpus for `--driver fips`: `MANIFEST.tsv` and the import script in git, the PDFs and their text local ([`specs/README.md`](specs/README.md)) |
| `sdks/` | [Workshop](https://ubuntu.com/workshop/docs/) SDKs with the toolchains: `frama-c-sdk`, `creusot`, `rocq`, `lean` ([`sdks/README.md`](sdks/README.md)) |
| `tests/` | Program, template, container and SDK tests ([`tests/README.md`](tests/README.md)) |
| `spec/` | The specifications |

## Specifications

- [`spec/auto-wp.md`](spec/auto-wp.md): `auto-wp.py`, the generated project, and its README
- [`spec/interactive-mode.md`](spec/interactive-mode.md): interactive completion and non-terminal usage
- [`spec/choose-harness.md`](spec/choose-harness.md): selecting and switching the agent harness — Claude Code, OpenCode, GitHub Copilot
- [`spec/tests.md`](spec/tests.md): the test plan
- [`spec/workshop-autowp-c-base-spec.md`](spec/workshop-autowp-c-base-spec.md),
  [`spec/workshop-autowp-rust-base-spec.md`](spec/workshop-autowp-rust-base-spec.md): the Workshop SDKs
- [`spec/gzip-test.md`](spec/gzip-test.md), [`spec/sudo-rs-test.md`](spec/sudo-rs-test.md): the GNU gzip 1.9 (C) and sudo-rs (Rust) campaign tests
- [`spec/fips-skill-spec.md`](spec/fips-skill-spec.md): the `fips-sl` skill (FIPS 140-3), draft
- [`spec/fips-corpus-spec.md`](spec/fips-corpus-spec.md): the FIPS 140-3 corpus `specs/` and the `src:<DOC>:<LOC>` citations;
  [`spec/fips-corpus-evaluation.md`](spec/fips-corpus-evaluation.md): how well the framework digests it
- [`spec/`](spec/): all of them, with review reports

## Tests

```
python3 -m pip install -r tests/requirements.txt  # test-only YAML parser
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
make smoke-c-gzip-ws                       # gzip: 96-hour /time-loop, stopped after 98 h at most
make sudo-rs-rust-ws                       # sudo-rs: 96 hours + 30 min for the report
```

or directly, `WORKSHOP=1 tests/c/gzip-test.sh` and
`WORKSHOP=1 tests/rust/sudo-rs-test.sh`. The `make` targets
keep a log in `tests/out/`. Both can run at the same time (each has its own
workshop); 16 GB of RAM is tight for two, 32 GB is comfortable.

| Variable | Effect |
|---|---|
| `SETUP_ONLY=1` | Stop after the setup checks: no token, no Claude Code, a few minutes. Use it first on a new host. |
| `GZIP_HOURS=<n>` | gzip budget in hours (default 96; stopped at n + 2 h) |
| `SUDORS_HOURS=<n>` | sudo-rs budget in hours (default 96; stopped at n + 30 min, or after 30 idle minutes) |
| `KEEP=1` | Keep the workshop and the project at the end, to inspect them |
| `WORKSHOP_DIR=<dir>` | Generate the project in `<dir>` instead of a new directory under `~/.awp` |
| `WORKSHOP_BASE=ubuntu@26.04` | Rewrite the definition's `base:` (default as generated, `ubuntu@24.04`) |
| `WORKSHOP_TRY="rocq lean"` | Use `try-<name>` SDKs packed on this host with `sdkcraft try` instead of the Store |
| `IDLE_S=<s>` | Stop early when the transcript has been idle that long (default 1800) |

### 4. What a run does

1. Generates the project on the host with `auto-wp.py --c --harness "$HARNESS"`
   (or `--rust` instead of `--c`), in a
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
non-commercial use only ([`sdks/README.md`](sdks/README.md)). The documents
of `specs/` are not in git: NIST publications are US Government works;
ISO/IEC 19790 and 24759 are licensed per licensee ([`specs/README.md`](specs/README.md)).
