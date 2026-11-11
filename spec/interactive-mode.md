# Interactive completion of missing arguments

**Status: implemented in 0.8.0.** This document specifies interactive
argument completion to `auto-wp.py`. It changes only how the language,
harness and project directory are obtained; generation, validation,
credentials and rollback retain the behavior of
[`auto-wp.md`](auto-wp.md) and [`choose-harness.md`](choose-harness.md),
except for the sections listed in §7, which the implementing change amends.
The implementation is version **0.8.0** (`VERSION` in `auto-wp.py`, the
manifest's `auto_wp_version`, and the `auto-wp.md` header).

## 1. Command line

```text
./auto-wp.py [-h] [--c|--rust] [--driver rmf|fips] [--level 1|2|3|4]
             [--harness claude|opencode|copilot|none] [<directory-name>]
```

(The option order matches `auto-wp.md` §1.)

When an argument is missing, ask for it interactively. Ask only for missing
arguments, in this fixed order:

1. Language, if neither `--c` nor `--rust` was supplied.
2. Harness, if `--harness` was not supplied.
3. Project directory, if no positional directory was supplied.

Explicit arguments are never replaced or confirmed. A fully specified
invocation runs without questions, including when launched from a terminal.
No new option is added: there is no `--interactive`, `--yes` or
`--no-input` flag. Whether stdin is a terminal (§4) is the only switch.

The implicit C and Claude defaults are removed for these missing arguments:
there is no preselected menu answer, and pressing Enter does not choose one.
The existing default driver, `rmf`, is unchanged. This feature adds no
driver or FIPS-level questions.

`Run.__init__` keeps no harness default: its `harness` parameter becomes
required, so "claude by default" lives nowhere in the program.

## 2. Prompts

All prompt text is written to **stderr** (§3). Each menu ends with a
question line followed by a single space and **no newline**; the answer is
typed on the same line. Write the prompt with `sys.stderr.write` and
`flush()`, then read one raw line from `sys.stdin.buffer` and decode it as
UTF-8 (§3). Do not use
`input(prompt)`, which writes the prompt to stdout.

### 2.1 Language

```text
Choose the language:
1. C (Frama-C/WP)
2. Rust (Creusot)
Type 1 or 2:
```

`1` has exactly the effect of `--c`; `2` has exactly the effect of `--rust`.

### 2.2 Harness

```text
Choose the agent harness:
1. Claude Code (claude)
2. OpenCode (opencode)
3. GitHub Copilot (copilot)
4. None (install a harness manually inside Workshop)
Type 1, 2, 3 or 4:
```

The four answers map to `--harness claude`, `--harness opencode`,
`--harness copilot` and `--harness none`, respectively. `none` is an explicit
choice, not a missing value: it generates the project without installing a
harness and keeps the manual-install instructions.

**Copilot generation is enabled for manual use.** Selecting `3` has the same
effect as `--harness copilot`: continue to the directory question if needed,
install the standalone CLI through the generated Workshop hook, and document
manual login and supervised tasks. Automated `HARNESS=copilot` campaigns
remain gated by `choose-harness.md` §10.6. Generation must not silently
substitute another harness or claim unattended campaign support.

### 2.3 Directory

```text
Project directory:
```

Read one line as the directory argument. Strip leading and trailing
whitespace; preserve internal spaces. Do not split it into words or require
shell quotes. An answer that is empty after stripping prints
`Enter a project directory.` (stderr, own line) and repeats this prompt.
Nothing else is validated here: any other non-empty answer, including `-`,
is a literal path, and the target rules apply afterwards.

Relative paths resolve against the current working directory, as for a
positional argument (`auto-wp.md` §1). `.` and absolute paths are accepted.
Input is a literal path: do not run shell expansion, expand environment
variables or `~`, or interpret shell commands. For example, enter
`/home/user/my project`, not a quoted string.

Once supplied, the directory follows the existing target rules
(`auto-wp.md` §3.1, §3.6); a target failure exits 1 and does not restart
the questionnaire.

## 3. Input, validation and cancellation

- Write menus, prompts and input-error messages to stderr; leave stdout
  for the existing successful-generation output.
- Strip surrounding whitespace from menu answers. Accept only the listed
  numeric strings. An empty or invalid menu answer prints `Type 1 or 2.`
  (or `Type 1, 2, 3 or 4.`) on its own line, then the **whole menu** again,
  without losing previous answers.
- Input that is not valid UTF-8 prints `Input must be valid UTF-8.` on its
  own line, then repeats the menu or directory prompt. Decode each raw line
  with `encoding="utf-8", errors="strict"` and catch `UnicodeDecodeError`
  for that line; never print a traceback or discard subsequent lines.
  Do not decode through a buffered text reader: it may encounter an error
  in a later line while reading the current one.
- Parse and validate explicit arguments before asking anything. Unknown
  flags, conflicting language flags, invalid harness names, excess
  positional arguments, and invalid `--driver`/`--level` combinations
  remain usage errors (exit 2, argparse format: `usage:` block, then
  `auto-wp.py: error: …`). Explicit `--harness copilot` is valid.
- `--help` prints help and exits 0 without prompting or creating files.
  The help strings no longer claim defaults: `--c` and `--harness` say
  "asked interactively when omitted and stdin is a terminal", and the
  positional is shown as optional.
- EOF during a prompt prints, on stderr,
  `auto-wp: error: input ended before all required choices were provided`
  and exits 1.
- Ctrl-C (`KeyboardInterrupt`) **anywhere** — during a prompt or during
  generation — prints `auto-wp: cancelled` on stderr and exits 130,
  without a Python traceback. If generation had started, it is rolled back
  first, using the existing rollback mechanism (`auto-wp.md` §3.6).
  Preserve all files and directories that existed before this invocation.
- Collect and validate all required answers before starting generation.
  Until then, create no project directories, files, git repositories or
  other artifacts. Never request or read a credential.

## 4. Non-interactive use and compatibility

Prompt only when **both** standard input and standard error are terminals
(`sys.stdin.isatty() and sys.stderr.isatty()`): with stderr redirected, the
prompts would be invisible and the program would wait silently.

If any required choice is missing and that condition is false, exit 2
immediately, without consuming stdin, and print on stderr the argparse
`usage:` block followed by one line naming every missing choice in prompt
order, e.g.

```text
auto-wp.py: error: missing --c/--rust, --harness, <directory-name> (not prompting: stdin or stderr is not a terminal)
```

Do not consume a pipe or silently restore the old defaults.

For example:

```sh
# Fully explicit: works unchanged in scripts and terminals.
./auto-wp.py --c --harness claude foobar

# Asks language, then harness, then directory.
./auto-wp.py

# Asks harness only.
./auto-wp.py --rust foobar

# Asks language, then directory; "none" is already resolved.
./auto-wp.py --harness none
```

This intentionally changes invocations that previously relied on implicit
C or Claude selection. Before the implementation is complete, every
non-interactive project-generation invocation in the repository's automation
and documentation must supply its language and `--harness` explicitly
(§7, test T8). Help/version probes, CLI syntax summaries, interactive
examples and deliberate missing-argument tests are exceptions.

The test drivers already pass `--harness "$HARNESS"`, but some generation
calls still omit the language, including the Mbed TLS campaign and C2.6
(the FIPS case in `tests/c/install-test.sh`). Existing host tests also
rely on defaults. Update these as well as the examples in `spec/tests.md`;
commands run through `lxc exec … <<EOF` have non-terminal stdin and would
otherwise exit 2.

## 5. Implementation boundaries

Keep the generator standard-library-only. Argument parsing must preserve
the distinction between missing values and explicit choices: use unset
values for language and harness, and an optional positional directory.
Resolve missing values before constructing/executing `Run`; pass the
resolved values through the same validation and generation path used by
explicit arguments.

The host-test helper `run_auto_wp` (`tests/test_auto_wp.py`) passes
`stdin=subprocess.DEVNULL`, so no host test can block on a prompt when
run from a terminal. Existing generation-test call sites supply explicit
choices; the helper must not inject defaults that would mask the
missing-argument tests. Pseudo-terminal tests use the standard library
(`pty`, `os`, `select`), attach both stdin and stderr to the terminal, and
capture stdout separately. Every subprocess test has a bounded timeout
and cleans up its child and file descriptors. No new test dependency is
added.

Implementation touches `auto-wp.py`, its host tests, the files listed in §7,
and `README.md`. This specification alone does not change any of those
files or enable Copilot.

## 6. Acceptance criteria and tests

1. With no arguments and terminal input, the three questions appear in
   order. Answers `2`, `4`, and a directory generate a Rust project whose
   manifest records `"harness": "none"`, whose stdout shows
   `harness:  none`, and whose Workshop hook installs no harness.
2. All eight combinations of missing and explicit language, harness and
   directory ask only the missing questions, in order. Explicit values are
   retained.
3. Both language choices and each enabled harness choice generate the
   same configuration as their explicit-command-line equivalents.
4. Invalid, blank and non-UTF-8 menu answers repeat only that menu. Blank
   or non-UTF-8 directory input repeats only the directory prompt. A
   directory with internal spaces is treated as one path.
5. Choosing Copilot continues to any remaining question and generates the
   same Copilot configuration as the explicit flag. No artifacts are
   created until the directory has been provided.
6. When stdin or stderr is not a terminal, missing arguments fail
   immediately with exit 2 and the line of §4; fully explicit invocations
   succeed without consuming stdin.
7. Help and explicit usage errors never prompt. EOF during a prompt exits
   1; Ctrl-C during prompting or generation exits 130. Both produce the
   specified message without a traceback. Prompt cancellation creates
   nothing; generation interrupted by Ctrl-C rolls back this invocation's
   changes and preserves pre-existing content.
8. Existing target-validation and rollback behavior is preserved.
   Automated generator and container tests use explicit choices rather
   than relying on the old defaults.

`tests/test_auto_wp.py` gains these tests (no model session is launched):

- **T1** (replaces `test_03_default_is_c`, the `()` and `("--rust",)` cases
  of `test_04b_other_usage_errors`, and `test_default_is_explicit_claude`):
  with `stdin=DEVNULL`, `foo` alone exits 2, stderr names `--c/--rust` and
  `--harness`, and nothing is created; `--rust` alone exits 2 naming
  `--harness` and `<directory-name>`; `--c --harness claude` alone exits 2
  naming `<directory-name>`.
- **T2** (criteria 1–3): on a pty, answers `2\n4\nfoo\n` give a tree
  identical (except `created` and the directory name) to
  `--rust --harness none foo`; likewise both languages with `claude`,
  `opencode` and `copilot`;
  `--rust foo` on a pty asks only the harness question (stderr contains
  `Choose the agent harness` and neither `Choose the language` nor
  `Project directory`); all eight combinations of criterion 2.
- **T3** (criterion 6): a fully explicit invocation with stdin an open pipe
  that is never written exits 0 within the timeout; a missing-argument
  invocation with `input="2\n4\nfoo\n"` exits 2 and creates nothing; a pty
  stdin with stderr redirected to a file also exits 2.
- **T4** (criterion 4): on a pty, `\n`, `3 \n`, `x\n`, `\xff\n`, `1\n` for
  the language give four re-prompts and then proceed; directory `  \n`
  then `my dir\n` gives one `Enter a project directory.` and a project at
  `my dir`. Invalid UTF-8 at the directory prompt repeats that prompt
  without losing a subsequent valid line.
- **T5** (criterion 5): on a pty, `1\n3\n` asks for the directory, with an
  empty working directory until the answer is supplied. Generation then
  succeeds, and the manifest records `"harness": "copilot"`.
- **T6** (criterion 7): on a pty in canonical mode, answer `1\n`, wait for
  the harness prompt, then send the configured VEOF character (normally
  Ctrl-D) on an empty input line. The process exits 1 with the EOF message.
  Keep the master open to collect stderr: closing it tests terminal
  hangup, which may cause SIGHUP or an I/O error rather than EOF.
  Separately, `1\n` followed by `SIGINT` while blocked exits 130 with
  `auto-wp: cancelled` and no `Traceback`. Inject `KeyboardInterrupt`
  deterministically after generation has created an artifact, and verify
  exit 130, rollback and preservation of pre-existing content.
- **T7**: `--help` with `stdin=DEVNULL` exits 0, and its text no longer
  calls `--c` or `claude` the default.
- **T8**: every non-interactive project-generation invocation in
  `tests/**/*.sh` and `spec/tests.md` carries `--c` or `--rust` and
  `--harness`, directly or through explicit forwarding such as
  `ws_generate`. Exclude help probes and the other exceptions in §4;
  comments mentioning the executable alone are not invocations.

## 7. Sections this change amends

The implementing change edits these, in the same commit:

| File | Where | Today | After |
|---|---|---|---|
| `spec/auto-wp.md` | header | "Version described: 0.7.0" | 0.8.0, with a pointer to this spec |
| `spec/auto-wp.md` | §1 usage and table | `<directory-name>` required; `--c` "This is the default"; `--harness` "`claude` (default)" | optional directory; no defaults, asked interactively (this spec) |
| `spec/auto-wp.md` | §1 rules | "Exactly one positional argument is required." | at most one; a missing one is asked for or reported (§4) |
| `spec/auto-wp.md` | §1.1 values table | `claude` marked Default | no default |
| `spec/auto-wp.md` | §1.1.2 | "the default is `claude` and its output equals an explicit `--harness claude`" | replaced by T1 |
| `spec/auto-wp.md` | §3.6 | a missing positional is a usage error, exit 2 | only when not prompting (§4); EOF exit 1, Ctrl-C exit 130 |
| `spec/auto-wp.md` | §5 test 3 | "No language flag behaves like `--c`." | replaced by T1 |
| `spec/choose-harness.md` | §1.5 table, `auto-wp.py --harness` row | `claude` (default) | no default; asked interactively. The `HARNESS=` row (test driver default `claude`) is unchanged |
| `spec/tests.md` | §5.2 and §6.2 commands, C2.5, C2.6, the gzip step | generation examples omit language and/or harness | add the intended language and `--harness claude` (or `"$HARNESS"`) |
| `tests/c/install-test.sh`, `tests/c/mbed-tls-test.sh` | FIPS project generation | language omitted | add `--c`; retain `--harness "$HARNESS"` |
| `tests/test_auto_wp.py` | existing generation calls and version assertions | calls rely on defaults; version is 0.7.0 | supply explicit choices except in deliberate omission tests; expect 0.8.0 |
| `README.md` | usage line and harness paragraph | directory required; default harness is `claude` | the §1 usage line; describe interactive completion instead of a default |
| `auto-wp.py` | module docstring and help strings | "the default", "default: claude" | §3 `--help` wording |
