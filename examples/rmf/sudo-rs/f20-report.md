
Title: command path globs: a whole-component `**` matches across `/`
(recursive), unlike ogsudo and sudoers(5) -- grants widen silently

## Summary

In a sudoers command path, sudo-rs matches patterns with the Rust `glob`
crate, in which a whole-component `**` is a RECURSIVE wildcard that
crosses `/`. Original sudo matches command paths with `fnmatch(3)`, where
`**` is just two consecutive `*` and never crosses `/`, and `sudoers(5)`
documents wildcard matching as POSIX glob(3)/fnmatch(3), with wildcards
in the file-name part never matching `/`; `**` is not documented as
special. So any rule containing a whole-component `**` matches strictly
more commands on sudo-rs than the same rule text on ogsudo: a fail-open
authorization widening, accepted silently by `visudo -c`.

Observed: `alice ALL = /opt/tools/**` allows `/opt/tools/sub/deeper/x`,
while the same tree under `alice ALL = /opt/tools/*` denies
`/opt/tools/sub/x`.

## Observed (all lines below are copy-pasted from the runs)

Matrix (dedicated unprivileged user `alice`; every rule carries NOPASSWD
so the glob, not authentication, decides each case; all target binaries
exist and print a marker):

| rule                  | tested command            | sudo-rs 0.2.13 (Ubuntu 26.04) | sudo 1.9.15p5 (24.04) |
|-----------------------|---------------------------|-------------------------------|-----------------------|
| `/opt/tools/*`        | `/opt/tools/x`            | ALLOW                         | ALLOW                 |
| `/opt/tools/*`        | `/opt/tools/sub/x`        | DENY (control)                | DENY                  |
| `/opt/tools/**`       | `/opt/tools/x`            | ALLOW                         | ALLOW                 |
| `/opt/tools/**`       | `/opt/tools/sub/deeper/x` | ALLOW                         | DENY                  |
| `/opt/**/x`           | `/opt/a/b/x`              | ALLOW                         | DENY                  |
| `/opt/**/x`           | `/opt/x`                  | ALLOW                         | DENY                  |
| `/opt/to**ls/x`       | `/opt/tols/x`             | DENY (pattern error)          | ALLOW                 |
| `visudo -c` on the `**` rule | --                 | accepted, no diagnostic       | accepted, no diagnostic |

Versions: sudo-rs 0.2.13-0ubuntu1.2 (the binary shipped with Ubuntu
26.04 LTS), sudo 1.9.15p5 (Ubuntu 24.04), and sudo-rs built from git
main at b0f1a205 (0.2.15) -- all three behave as in the table; the
widening is still present on main. Verified 2026-11-12.

The `**` semantics also show in both directions: on sudo-rs,
`/opt/**/x` matches `/opt/x` (zero directories), and a non-whole-component
`**` (`/opt/to**ls/x`) is a glob pattern error that fails closed with a
diagnostic; on ogsudo `**` is two non-recursive stars, so `/opt/to**ls/x`
matches `/opt/tols/x` and `/opt/**/x` matches neither of the two paths.

## Escalation-shaped demonstration (contingent, but concrete)

Same binary, same directory tree, the rules differ only in `*` vs `**`;
`/opt/tools/sub` and `pwn.sh` are owned by the invoking user:

    escalation demo: rule '/opt/tools/**' -> OBSERVED: pwn.sh ran as uid 0 (root)
    escalation demo: rule '/opt/tools/*'  -> OBSERVED: denied (control holds)

I.e. an admin who writes `**` (expecting, per sudoers(5), a match that
does not descend into subdirectories) grants root execution of anything
the invoking user can place in any subdirectory under the pattern's root.

To be explicit about the bound: this needs an admin-authored `**` rule
and an invoking-user-writable directory under the matched root; there is
no attacker input and no way for an unprivileged user to create the
condition. Without a writable subdirectory the effect is a broadened,
still admin-rooted set of executables.

## Relation to #834

Issue #834 documents glob-crate vs ogsudo fnmatch divergences ([!] vs
[^], leading dot, slash counts, trailing backslash) but does not cover
`**` recursion. It also reasons that these incompatibilities "can't be
misused accidentally"; unlike the listed ones, this case widens GRANTS
whenever an admin writes `**`, so it may be worth adding to that list
(or fixing). No other existing issue mentions `**` recursion (searched
2026-11-12).

## Suggested fix

Any of, in decreasing order of preference:

1. Match ogsudo semantics for command paths: treat `**` as non-recursive
   (two `*`), so wildcards never cross `/`.
2. If recursive semantics are kept, reject a whole-component `**` in a
   command path at parse time with an explicit error (the non-whole-
   component case already fails closed, so the machinery exists).
3. At minimum, warn in `visudo -c` when a command path contains a
   whole-component `**`.

## Reproducer

`vm-test.sh` (run as root in a VM; it builds the /opt tree, writes each
rule to /etc/sudoers.d, runs every case with `sudo -n` as an
unprivileged user and prints the OBSERVED lines quoted above), plus the
three transcripts. Written for multipass:

    multipass launch -n f20 26.04        # or 24.04 for the sudo A/B
    multipass transfer vm-test.sh f20:/tmp/
    multipass exec f20 -- sudo bash /tmp/vm-test.sh

Happy to send a patch implementing 1 or 2 with tests.

Best regards,
Fabrice Derepas, Canonical
