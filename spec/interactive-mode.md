# Interactive completion of missing arguments

**Status: specified, not implemented.** This document adds interactive
argument completion to `auto-wp.py`. It changes only how the language,
harness and project directory are obtained; generation, validation,
credentials and rollback retain the behavior of
[`auto-wp.md`](auto-wp.md) and [`choose-harness.md`](choose-harness.md).

## 1. Command line

```text
./auto-wp.py [--c|--rust] [--harness claude|opencode|copilot|none]
             [--driver rmf|fips] [--level 1|2|3|4] [<directory-name>]
```

When an argument is missing, ask for it interactively. Ask only for missing
arguments, in this fixed order:

1. Language, if neither `--c` nor `--rust` was supplied.
2. Harness, if `--harness` was not supplied.
3. Project directory, if no positional directory was supplied.

Explicit arguments are never replaced or confirmed. A fully specified
invocation runs without questions, including when launched from a terminal.
No new `--interactive` option is required.

The implicit C and Claude defaults are removed for these missing arguments:
there is no preselected menu answer, and pressing Enter does not choose one.
The existing `--driver rmf` default is unchanged. This feature adds no
driver or FIPS-level questions.

## 2. Prompts

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
3. GitHub Copilot (copilot; not implemented yet)
4. None (install a harness manually inside Workshop)
Type 1, 2, 3 or 4:
```

The four answers map to `--harness claude`, `--harness opencode`,
`--harness copilot` and `--harness none`, respectively. `none` is an explicit
choice, not a missing value: it generates the project without installing a
harness and keeps the manual-install instructions.

**Copilot remains gated.** While the implementation gate in
`choose-harness.md` is closed, selecting `3` reports
`--harness copilot is not implemented yet` and exits 2, without asking for
the directory or creating anything. It must not select another harness.
Once Copilot is enabled, remove the unavailable annotation and accept `3`
through the same validation path as the explicit flag.

### 2.3 Directory

```text
Project directory:
```

Read one line as the directory argument. Strip leading and trailing
whitespace; preserve internal spaces. Do not split it into words or require
shell quotes. An empty answer prints `Enter a project directory.` and
repeats this prompt.

Relative paths resolve against the process's original working directory.
`.` and absolute paths are accepted. Input is a literal path: do not run
shell expansion, expand environment variables or `~`, or interpret shell
commands. For example, enter `/home/user/my project`, not a quoted string.

Once supplied, the directory follows the existing target rules: an eligible
existing directory may be populated, but reserved paths are never
overwritten. A filesystem or target-validation failure retains the normal
runtime error and exit 1; it does not restart the questionnaire.

## 3. Input, validation and cancellation

- Write menus, prompts and input-error messages to stderr; leave stdout
  for the existing successful-generation output.
- Strip surrounding whitespace from menu answers. Accept only the listed
  numeric strings. Empty or invalid menu input prints the allowed choices
  and repeats the same question, without losing previous answers.
- Parse and validate explicit arguments before asking anything. Unknown
  flags, conflicting language flags, invalid harness names, excess
  positional arguments, and invalid `--driver`/`--level` combinations
  remain usage errors (exit 2). Explicit `--harness copilot` retains its
  existing gate.
- `--help` prints help and exits 0 without prompting or creating files.
- EOF during a prompt prints `auto-wp: error: input ended before all
  required choices were provided` and exits 1.
- Ctrl-C during a prompt prints `auto-wp: cancelled` and exits 130, without
  a Python traceback.
- Collect and validate all required answers before starting generation.
  Until then, create no project directories, files, git repositories or
  other artifacts. Never request or read a credential.

## 4. Non-interactive use and compatibility

Prompt only when standard input is a terminal (`sys.stdin.isatty()`).
If any required choice is missing and stdin is not a terminal, report all
missing choices in a usage error and exit 2 immediately, without reading
stdin. Do not consume a pipe or silently restore the old defaults.

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
C or Claude selection. Before implementation is considered complete,
update repository automation to supply its intended language and
`--harness` explicitly. `HARNESS` remains a test-driver variable, not an
implicit generator argument; drivers pass `--harness "$HARNESS"` as before.

## 5. Implementation boundaries

Keep the generator standard-library-only. Argument parsing must preserve
the distinction between missing values and explicit choices: use unset
values for language and harness, and an optional positional directory.
Resolve missing values before constructing/executing `Run`; pass the
resolved values through the same validation and generation path used by
explicit arguments.

Implementation will touch `auto-wp.py`, its host tests, dependent container
test invocations, and CLI usage documentation. This specification alone
does not change any of those files or enable Copilot.

## 6. Acceptance criteria

1. With no arguments and terminal input, the three questions appear in
   order. Answers `2`, `4`, and a directory generate a Rust project whose
   manifest records `harness: none` and whose Workshop hook installs no
   harness.
2. Each combination of missing and explicit arguments asks only the
   missing questions, in order. Explicit values are retained.
3. Both language choices and each enabled harness choice generate the
   same configuration as their explicit-command-line equivalents.
4. Invalid and blank menu answers repeat only that menu. Blank directory
   input repeats only the directory prompt. A directory with internal
   spaces is treated as one path.
5. Choosing Copilot while gated exits 2 with the specified message and no
   artifacts. Explicit Copilot selection behaves the same way.
6. With non-terminal stdin, missing arguments fail immediately with exit
   2 and a list of missing choices; fully explicit invocations succeed
   without reading stdin.
7. Help and explicit usage errors never prompt. EOF and Ctrl-C produce
   the specified status and no artifacts or traceback, even after earlier
   questions were answered.
8. Existing target-validation and rollback behavior is preserved.
   Automated generator and container tests use explicit choices rather
   than relying on the old defaults.

Test prompt resolution with controlled input and terminal detection; cover
the actual terminal path with a pseudo-terminal integration test. Do not
launch a model session to test this feature.
