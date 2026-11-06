# gzip test — a one-hour `/time-loop` run on GNU gzip 1.9 (draft for review)

This document specifies a container test that runs the C campaign on a
second, real code base, GNU gzip 1.9. It is a level 3 test in the sense of
`tests.md` §2: it costs about an hour of the Claude subscription, needs the
Claude token, and is run by hand (`tests/c/gzip-test.sh`; §7 adds a Workshop mode). The
review answers of 2026-10-30 are integrated: the budget stays one hour, gnulib
is in scope, the archive's GPG signature is verified, G.11 has a pass
threshold, and the download falls back to other mirrors.

## 1. What the test does

1. `python3 auto-wp.py gzip-analyze --c`. The flag may come after the
   directory: argparse accepts both orders (checked 2026-10-30, the output is
   `skills:   21`, `commands: 3`).
2. In `gzip-analyze`, download `gzip-1.9.zip` (with mirror fallbacks),
   check its sha256 and its GPG signature, and unzip it, which gives
   `gzip-analyze/gzip-1.9/`.
3. In the container, start Claude Code in the harness and type
   `/time-loop gzip-1.9 1`: the RMF campaign (`rmf-sl` code-blind risk study,
   then `frama-c-launch` and `frama-c-monitoring`) on gzip, with a one-hour
   budget.
4. Wait for the loop to stop, then check the results (§5).

## 2. The source archive

| | |
|---|---|
| URLs, in order | `https://mirror.us-midwest-1.nexcess.net/gnu//gzip/gzip-1.9.zip`, then the fallbacks `https://ftp.gnu.org/gnu/gzip/`, `https://ftpmirror.gnu.org/gzip/`, `https://mirrors.kernel.org/gnu/gzip/`, `https://mirror.csclub.uwaterloo.ca/gnu/gzip/` (same file name) |
| Signature | `gzip-1.9.zip.sig`, from the same mirror as the archive |
| Signer | Jim Meyering, key fingerprint `155D3FC500C834486D1EEA677FD9FCCB000BEEEE` |
| Size | 1 436 834 bytes |
| sha256 | `6dbd6307d88d866bea0d0b39aa14506a6a092eee5bcdc62f0c070ef8ea47e99c` |
| Contents | 484 entries, all under `gzip-1.9/`, including `configure`, `Makefile.in`, `gzip.c`, `README`; 128 `*.c` files, gnulib's `lib/` included |

Size, sha256 and contents were measured on 2026-10-30 by downloading the
file. The same day, all five mirrors served a file with that sha256.

**Mirrors.** The test tries the URLs in order and uses the first that
answers. The pinned sha256 is checked whatever the mirror, so a fallback can
never change the test's input.

**Signature.** The test checks the archive two ways, before the token is
moved in, and exits 2 if either fails:

- the sha256 pin, for reproducibility;
- the GPG signature, for provenance. `gpgv` (in the base image) checks
  `gzip-1.9.zip.sig` against the GNU keyring,
  `https://ftp.gnu.org/gnu/gnu-keyring.gpg`, and the test requires the
  signing key to be the fingerprint above, read from `gpgv --status-fd`'s
  `VALIDSIG` line. Pinning the fingerprint, not the keyring's sha256, keeps
  the check valid when GNU updates the keyring, and means a swapped keyring
  cannot make another key acceptable. Checked on the host on 2026-10-30:
  "Good signature from "Jim Meyering <jim@meyering.net>"", made
  2018-01-07, RSA key `155D3FC5…000BEEEE`.

**Scope.** The whole archive is unzipped and analysed, gnulib's `lib/`
included (most of the 128 `*.c` files): the run uses no `--dir`. The RMF
report's ranking decides what the hour is spent on.

The archive is a release, not a git checkout: it already has `configure`,
so `frama-c-launch` can build it with `./configure && make` (under `bear`
for `compile_commands.json`) without autotools.

## 3. Where it runs

The test reuses the level 3 machinery of `tests/c/smoke-test.sh`
(`tests.md` §5.3), not the README quick start:

- **The container is a copy of `autowp-c-base/ready`** (`tests/c/provision.sh`),
  which has the packages, the opam AppArmor fix and the Frama-C 32.1
  toolchain already built. Without it, `frama-c-launch` would build the
  toolchain itself on the first run, which takes hours, so the one-hour
  budget would end before any verification starts. `bin/launch_lxc.sh`
  is therefore not used here: it creates a container with no toolchain.
- **The project is generated in the container**, not on the host, and not
  mounted: a test run never writes into a host directory (`tests/README.md`,
  "Differences from the README quick start"). `auto-wp.py` and the templates
  are pushed with `autowp_push_project`, as the other tests do.
- **The harness** is `tests/lib/harness.sh`: Claude Code in `tmux`, started
  with `--dangerously-skip-permissions`, with the token moved in by
  `tests/lib/secret.sh` (`tests.md` §7).
- **The checkpoint remote** is a local bare repository `~/remote.git` in the
  container (`tests.md` §3.4).

## 4. Steps of `tests/c/gzip-test.sh`

```
C=autowp-c-gzip-<timestamp>
copy autowp-c-base/ready to $C; wait until ready; egress check
push auto-wp.py and templates/ to ~/auto-wp
in the container, as ubuntu:
    touch ~/.autowp-t0
    cd ~ && python3 auto-wp/auto-wp.py gzip-analyze --c
    cd gzip-analyze
    for m in <mirrors of §2>; do                               # first that answers
        curl -fsSL -o gzip-1.9.zip "$m/gzip-1.9.zip" &&
        curl -fsSL -o gzip-1.9.zip.sig "$m/gzip-1.9.zip.sig" && break
    done
    echo "<sha256>  gzip-1.9.zip" | sha256sum -c --quiet     # else exit 2
    curl -fsSL -o ~/gnu-keyring.gpg https://ftp.gnu.org/gnu/gnu-keyring.gpg
    gpgv --status-fd 1 --keyring ~/gnu-keyring.gpg gzip-1.9.zip.sig gzip-1.9.zip \
        | grep -q '^\[GNUPG:\] VALIDSIG 155D3FC500C834486D1EEA677FD9FCCB000BEEEE '
                                                              # else exit 2
    unzip -q gzip-1.9.zip && rm gzip-1.9.zip gzip-1.9.zip.sig
    bin/fetch-sources.sh
    git add gzip-1.9 && git commit -qm "import gzip-1.9"     # the K1 baseline (§5)
    git rev-parse HEAD > ~/.autowp-gzip-commit
    git init -q --bare ~/remote.git && git remote add origin ~/remote.git
secret_push $C
harness_start $C /home/ubuntu/gzip-analyze '/time-loop gzip-1.9 1'
harness_confirm $C time-loop 300                              # G.1
wait_loop_stopped $C ~/gzip-analyze/gzip-1.9-analysis-acsl/time-loop.state <hard limit>
harness_stop $C
checks G.2 - G.11 (§5)
```

**The import commit.** `gzip-1.9/` is not a git repository, unlike `grub/`,
which is its own clone. The test commits the pristine tree once in
`gzip-analyze`'s own repository before the run. That commit is the baseline
for "source untouched" (G.2), and it keeps the loop's checkpoint commits
small: they then hold only the analysis files and whatever the run changed.
Without it, the first checkpoint would add the whole gzip tree, and nothing
could tell a changed gzip file from an original one.

**Timing.** Budget 1 hour, on purpose: the test checks that the loop starts,
honours its deadline and writes its report on a new code base, and G.11
asks for one proof, not for coverage. The hard limit is 3 hours: the deadline is only
checked between cycles (`time-loop/SKILL.md` §4 step 0), and one cycle on a
first run includes the code-blind risk study and the onboarding, which can
by itself run past the hour. `wait_loop_stopped` returns when the session
has been idle for `IDLE_S` (default 30 minutes) or at the hard limit.

**Make target.** `make smoke-c-gzip`, logging to
`tests/out/c-gzip-<stamp>.log`, next to `smoke-c`. Like the other level 3
targets, it is never run by `make test` or `make test-l2`.

## 5. Checks

Names follow the level 3 checks of `tests.md` §5.3, with the prefix `G.`.
`XXX` is `gzip-1.9`, so the artifact prefix is `gzip-1.9-analysis` and the
report is `gzip-1.9.md`.

| # | Check |
|---|---|
| G.0 | The archive came from one of the mirrors of §2, its sha256 matches, its GPG signature is good and made by the pinned key, and `gzip-1.9/configure` and `gzip-1.9/gzip.c` exist after unzip. Failing here exits 2 before the token is moved in. The mirror used is printed as INFO. |
| G.1 | K4: the `time-loop` command was loaded (`harness_confirm`). |
| G.2 | K1, source untouched: `git diff --quiet <import commit> -- gzip-1.9` succeeds, and `git status --porcelain --untracked-files=no -- gzip-1.9` is empty. Untracked build output inside `gzip-1.9/` (`config.status`, `Makefile`, object files, `compile_commands.json`) is allowed, as for GRUB. |
| G.3 | `gzip-1.9-analysis-rmf-report.md` exists, is not empty, and `bin/rmf-lint.sh` on it exits 0. |
| G.4 | `gzip-1.9-analysis-acsl/time-loop.state` exists, and its deadline is 1 h after its start (± 5 min). |
| G.5 | *Informational.* The number of wakes the state file records. A one-hour budget may hold a single cycle, so fewer than two wakes is reported, not failed (unlike C3.5). |
| G.6 | Every cycle the state file records has a commit in `~/remote.git` (C3.6). |
| G.7 | Stopped on time: the last wake is not later than the deadline plus the longest recorded cycle (C3.7). With a single wake, the check is that no new cycle started after the deadline. |
| G.8 | K2: the token was not written anywhere. |
| G.9 | *Informational.* K3: files changed outside the allowlist, with `~/gzip-analyze` in place of `~/foobar`. |
| G.10 | Report file: `~/gzip-analyze/gzip-1.9.md` exists, is not empty, and is the interim report (the one-hour run pauses at its deadline). No other report file was created in `~/gzip-analyze` or inside `gzip-1.9/`. |
| G.11 | **At least one unit has `PROVED` goals**, read from the overlay's `verdicts.tsv` (a `Valid`/`PROVED`/`GREEN` verdict, as `crosswalk-gen.sh` reads it). The check also prints, as INFO, the number of units onboarded, of goals `PROVED`, and of entries in `gzip-1.9-analysis-found-issues.md`. This makes the test a regression gate for the skills; the risk, accepted, is a failure on an hour lost to rate limits or to a slow onboarding, so a G.11 failure is read with the pane transcript before it is blamed on the skills. |

## 6. Changes to the shared helpers

`tests/lib/harness.sh` hard-codes the GRUB campaign: `campaign_setup_c`
clones GRUB into `~/foobar`, and `campaign_checks_c`, `report_check_c` and
`k3` use `/home/ubuntu/foobar`, `grub`, `grub-analysis-*` and `grub.md`.
The gzip test needs them parameterized:

- `campaign_checks_c` and `report_check_c` take the project directory and
  the source name (`XXX`) as arguments, defaulting to `foobar` and `grub` so
  `smoke-test.sh` and `acceptance.sh` are unchanged;
- `k1` gains a form for a source tracked by the project (`git diff
  <commit> -- <dir>`) next to today's form for a source that is its own
  repository;
- `k3`'s allowlist takes the project directory;
- the setup is a new `campaign_setup_c_gzip` (the steps of §4), not a change
  to `campaign_setup_c`;
- G.5 and G.7 differ from C3.5 and C3.7 (§5), so `campaign_checks_c` takes a
  flag that makes the wake count informational.

## 7. Workshop mode

`WORKSHOP=1 tests/c/gzip-test.sh` runs the same campaign and the same checks
G.0–G.11 in the workshop of a generated project instead of a copy of
`autowp-c-base/ready`: it is the level 3 test of quick start A of
`auto-wp.md` §3.4 and of the SDK support of §4.5 (added 2026-11-05). The
toolchain comes from the `frama-c-sdk` SDK, so `frama-c-launch` should skip
the hours-long build and the hour goes to verification.

### 7.1 What changes

- **The project is generated on the host**, as the README says: `auto-wp.py
  --c <tmp>/gzip-analyze`, then `workshop launch autowp` there. Unlike §3,
  the test writes into a host directory, a new one under `${TMPDIR:-/tmp}`
  (or `WORKSHOP_DIR`), removed at the end unless `KEEP=1`.
- **The guest** is the workshop: the user is `workshop`, the home
  `/home/workshop`, the project `/project`, and every in-guest step goes
  through `workshop exec` (`autowp_use_workshop` in `tests/lib/lxc.sh`).
  The token still goes through stdin into `/run/autowp/token`
  (`workshop exec` passes stdin, checked 2026-11-05), and the `tmux`
  session survives between two `workshop exec` calls (checked the same day).
- **The test edits the generated files** in three ways, each printed as
  INFO: `unzip` is added to `.workshop/autowp-packages/hooks/setup-base`
  (the archive is a zip, and the base image has no `unzip`; the README tells
  users to edit that hook for their code base); `WORKSHOP_BASE` rewrites
  `base:`; `WORKSHOP_TRY="rocq lean"` replaces those Store entries with
  `try-<name>` for SDKs packed with `sdkcraft try` on the host but not
  released yet.
- **Claude Code** is installed in the workshop by step 2 of quick start A
  (`curl -fsSL https://claude.ai/install.sh | bash`).
- **The checkpoint remote** is `~/remote.git` in the workshop's home. K2
  (G.8) also searches `/project`, which is outside the home.

### 7.2 Extra checks

| # | Check |
|---|---|
| W.1 | `auto-wp.py --c` on the host succeeds, and `.workshop/autowp.yaml` names the workshop `autowp` and lists `frama-c-sdk`, `rocq`, `lean` and `project-autowp-packages`, with an executable `setup-base`. |
| W.2 | `workshop launch autowp` succeeds and `workshop info` says `status: ready`, i.e. every SDK's `check-health` passed. The launch time is INFO. |
| W.3 | Before the campaign: `frama-c -version` is 32.1, `frama-c` is `/opt/frama-c-sdk/bin/frama-c`, and `FRAMA_C_SDK_SWITCH`/`FRAMA_C_SDK_SRC` are set. |
| W.4 | After the setup: `bin/fetch-sources.sh` made `framac-src` a link to `/opt/frama-c-sdk/src/frama-c-32.1` (no download), and `bin/framac-onboard.sh` reports the switch present through the SDK. |

`SETUP_ONLY=1` stops after G.0 (and W.1–W.4): no token, no Claude Code
session, a few minutes. It checks the Workshop route without spending the
subscription.

### 7.3 Results

- 2026-11-05, `WORKSHOP=1 WORKSHOP_BASE=ubuntu@26.04 SETUP_ONLY=1`, all
  SDKs from the Store: W.1 passed; W.2 failed with `"rocq" SDK: Revision not
  found - "lean" SDK: Revision not found`. `frama-c-sdk` resolved: its
  `ubuntu@26.04` revision was uploaded that day; `rocq` and `lean` had no
  revision released on `latest/edge` yet.
- 2026-11-05, the same with `WORKSHOP_TRY="rocq lean"`: W.1, W.2 (launch
  in 1899 s, `frama-c-sdk` 32.1 from the Store, `ready`), W.3 and G.0
  passed. W.4 failed because the test called `bin/framac-onboard.sh` without
  its target directory (usage error); `framac-src` was correctly linked to
  `/opt/frama-c-sdk/src/frama-c-32.1`. Fixed in the test (it now passes
  `gzip-1.9 --sample 1`).
- 2026-11-05, rerun after the fix (and with the steps moved to
  `tests/lib/workshop.sh`): 5 passed, 0 failed (W.1, W.2 with the launch in
  186 s now that the SDKs were cached, W.3, G.0, W.4). The campaign itself
  has not run in a workshop yet.
- 2026-11-06, `WORKSHOP=1 WORKSHOP_BASE=ubuntu@26.04 SETUP_ONLY=1`, all
  SDKs from the Store after `rocq` and `lean` were released: W.1 passed, W.2
  failed again with `"rocq" SDK: Revision not found - "lean" SDK: Revision
  not found`. The same day, on `ubuntu@24.04`, `rocq` 9.2.0 and `lean`
  4.35.0 resolved from the Store (`sudo-rs-test.md` §7): their `ubuntu@26.04`
  revisions are not released on `latest/edge`. Until they are, the 26.04 run
  keeps `WORKSHOP_TRY="rocq lean"`.
- 2026-11-06, `WORKSHOP=1 SETUP_ONLY=1` with the definition as generated
  (base `ubuntu@24.04`), all from the Store: W.1 passed, W.2 failed with
  `"frama-c-sdk" SDK: Revision not found`. So a `--c` project launches from
  the Store on neither base yet: 24.04 lacks `frama-c-sdk`, 26.04 lacks
  `rocq` and `lean`.
- 2026-11-06, later: `sdk info` showed all four SDKs with an `ubuntu@24.04`
  and an `ubuntu@26.04` revision on `latest/edge` (the earlier failures were
  the Store catching up after the uploads). `WORKSHOP=1 SETUP_ONLY=1` with
  the definition as generated (`ubuntu@24.04`, every SDK from the Store):
  5 passed, 0 failed (W.1, W.2 with the launch in 2439 s, downloads
  included, W.3, G.0, W.4). Neither `WORKSHOP_BASE` nor `WORKSHOP_TRY` is
  needed any more.

## 8. Documents to update

- `tests.md`: a new §5.5 with §1–§5 of this document in short, and a row in
  the layout of §1 and the table of §2.
- `tests/c/README.md`: a section for `gzip-test.sh`, and a row in its table.
- `Makefile`: the `smoke-c-gzip` target, and `gzip-test.sh` is picked up by
  `check-scripts` through the existing wildcard.
