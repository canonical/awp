# fips-sl — specification (draft for review, revision 8)

This document specifies:

- a new skill `templates/common/skills/fips-sl/`, modelled on
  `templates/common/skills/rmf-sl/`, that authors a FIPS 140-3 requirement
  study of a cryptographic module instead of a NIST RMF risk assessment;
- two new `auto-wp.py` options, `--driver` and `--level`, that choose which
  of the two skills drives the verification campaign.

Nothing here is implemented yet. Revision 2 addressed the findings of
`fips-skill-spec-report.md`, and revision 3 those of
`fips-skill-spec-report-2.md`; §10 maps each finding to the section that
handles it. Revision 4 applies the choice of option B for what "instead of"
installs (§6), revision 5 addresses `fips-skill-spec-report-3.md`, and
revision 6 `fips-skill-spec-report-4.md`, revision 7
`fips-skill-spec-report-5.md`, and revision 8 `fips-skill-spec-report-6.md`,
which found it ready to implement. The open points are in §9.

## 1. The source document

The only standard the skill cites is `./NIST.FIPS.140-3.pdf`: FIPS PUB 140-3,
*Security Requirements for Cryptographic Modules*, March 22, 2019 (11 pages,
sha256 `942a4f929dfbd2b4af2e4e03df7f6e6377054346afd9bee346ed0ebac5db384b`).
It replaces the SP 800-30, SP 800-37 and SP 800-53 corpus that `rmf-sl`
cites.

The PDF has two independent numberings: the *Announcement* items 1 to 14
(pages iii–vi) and the body sections 1 to 3 (pages 1–3). This spec writes
them `Ann. n` and `Sec. n`. What the PDF contains, and so what the skill can
cite from it:

| Content | Where |
|---|---|
| Four security levels, named "Level 1, Level 2, Level 3, and Level 4" | Ann. 3, the only place that names them. Sec. 1 gives the count ("four security levels"), and the Abstract says "four increasing, qualitative levels of security" |
| The requirement areas, listed after "These areas include": cryptographic module specification; cryptographic module interfaces; roles, services, and authentication; software/firmware security; operating environment; physical security; non-invasive security; sensitive security parameter management; self-tests; life-cycle assurance; and mitigation of other attacks | Abstract; Ann. 3 |
| The counts: "Four security levels were specified for each of eleven requirement areas" (about FIPS 140-1) | Sec. 1 |
| The level "must be chosen to provide a level of security appropriate for the security requirements of the application and environment", and the requirements of a level are "both the security requirements specific to that level and the security requirements that apply to all modules regardless of the level" | Ann. 7 |
| Conformant modules "shall employ Approved security functions such as cryptographic algorithms, cryptographic key management techniques, and authentication techniques" | Ann. 10 |
| Conformance "is not sufficient to ensure that a particular module is secure". The operator ensures the security is "sufficient and acceptable to the owner of the information that is being protected and that any residual risk is acknowledged and accepted"; "the responsible authority in each agency" ensures the security of the system | Ann. 13 |
| Validation goes through the CMVP and accredited CST laboratories | Ann. 3, 9, 12 |
| The technical requirements are those of ISO/IEC 19790:2012 and the test requirements those of ISO/IEC 24759:2017, modified by SP 800-140 and SP 800-140A to F | Sec. 2, Sec. 3, Table 1 |

**What the PDF does not contain:** the requirements themselves. Apart from
the applicability rule of Ann. 6, the only requirement on a module is
Ann. 10. Which requirement applies in which area at which level is in
ISO/IEC 19790 and the SP 800-140 series, which the PDF names but does not
reproduce. (That the per-level requirements are in ISO/IEC 19790's clause 7
is outside knowledge, not something the PDF says.) This decides much of the
design below. The skill never presents a requirement as coming from the PDF
when it does not (§4.4, rule F3). Whether to add documents to the corpus is
open point 1.

## 2. Command line

```
./auto-wp.py [--c|--rust] [--driver rmf|fips] [--level 1|2|3|4] <directory-name>
```

- `--driver rmf` is the default. The campaign command is `/rmf`, and
  `rmf-sl` drives the campaign.
- `--driver fips` installs `/fips` instead of `/rmf`, so `fips-sl` drives the
  campaign instead of `rmf-sl`. Both skills are installed either way (§6).
  The campaign commands are C-layer files: with `--rust`, neither is
  installed and `commands` stays empty under both drivers (§7.2).
- `--level N` gives the target FIPS 140-3 security level, 1 to 4. It is
  required with `--driver fips` and refused otherwise.

argparse does not care about option order, so `--level 3 --driver fips` is
accepted like `--driver fips --level 3`. argparse checks the `choices`.
`auto-wp.py` then checks the dependency between the two options after
parsing, with `parser.error()`:

| Command line | Result |
|---|---|
| `auto-wp.py foobar` | driver `rmf` |
| `auto-wp.py --driver fips --level 3 foobar` | driver `fips`, level 3 |
| `auto-wp.py --driver fips foobar` | usage error: `--driver fips needs --level 1, 2, 3 or 4` |
| `auto-wp.py --level 3 foobar` | usage error: `--level is only valid with --driver fips` |
| `auto-wp.py --driver fips --level 5 foobar` | usage error (argparse `choices`) |
| `auto-wp.py --driver ebios foobar` | usage error (argparse `choices`); see open point 6 |

Every usage error exits 2 and creates nothing, like the existing ones
(`auto-wp.md` §5, test 4).

**Why `--level` is required and has no default:** Ann. 7 says the level
"must be chosen" for the application and environment. A silent default of 1
would be the generator making that choice for the user.

## 3. What `auto-wp.py` records

`config/auto-wp.json` gains two keys:

```json
"driver": "fips",
"fips_level": 3,
```

With `--driver rmf`, `"driver": "rmf"` is written and `fips_level` is
absent. The manifest is the single place the level is stored. `fips-sl`,
`/fips` and `bin/fips-lint.sh` read it from there (§5 says how the linter is
tested without a project).

The output gains one line after `created config`. The skill count grows by
one, `fips-sl`; the command count stays 3, since each driver installs its
own campaign command only (§6):

```
created foobar/config (language: c)
  driver:   fips (FIPS 140-3 level 3)
  skills:   22
  commands: 3
```

With `--driver rmf` the line is `  driver:   rmf`. The manifest's `commands`
list is `ebios, fips, time-loop` for `fips` and `ebios, rmf, time-loop` for
`rmf` (C; with `--rust` it is empty, and the output says `commands: 0`).

The `tools` step prints one more line for both languages,
`copied  foobar/NIST.FIPS.140-3.pdf`. `install_tools` merges the `tools/`
entries of all layers and prints them in sorted name order
(`auto-wp.py:156`), so the layer order plays no part. With `--c` the line
comes between `copied  foobar/.gitignore` and `copied  foobar/bin`. With
`--rust` it is the only `copied` line.

## 4. The skill `fips-sl`

### 4.1 Files

```
templates/common/skills/fips-sl/
├── SKILL.md                          front matter name: fips-sl
├── fips-sl.sl.json                   the SL definition, same schema as rmf-sl.sl.json
└── references/
    ├── report-format.md              the pinned report format: the linter's contract
    ├── skeleton.md                   the minimal conformant report: the linter's known-good fixture (§5)
    ├── area-properties.md            the eleven areas → verification properties (§4.5)
    └── crosswalk-format.md           a thin pointer to the crosswalk schema,
                                      frama-c-monitoring/templates/crosswalk-template.md,
                                      with the FIPS tag bindings (§7.1), like
                                      rmf-sl/references/crosswalk-format.md
```

`rmf-sl/references/stride-families.md` and `attack-mapping.md` have no
counterpart. The eleven areas take the place of STRIDE and of the 800-53
families (open point 4).

### 4.2 What it keeps from `rmf-sl`

The structure of `rmf-sl/SKILL.md`, section by section, with the same
squeeze-loop discipline:

- **The code barrier.** The study author and the reviewer never read the
  implementation source. They work from the PDF, the module's public
  description (purpose, services, documented interfaces, Security Policy if
  one exists) and the target level. This is what lets the study rank the
  verification work from outside the code. The contaminated-context rule of
  `rmf-sl` §4b applies unchanged: a re-author is delegated to a fresh agent
  that has seen neither the code nor any verification artifact.
- **The actors.** Coordinator, study author, completeness reviewer, optional
  probe, and a human terminus (§4.3). Each has its disjoint `(U, L)` pair,
  as in the `rmf-sl` table §2.
- **The gates.** Gate A (editorial), Gate B (`bin/fips-lint.sh`) and Gate C
  (coverage and realism), as in `rmf-sl` §3. Gate S (the audit of
  capitalized heuristics) is as in `rmf-sl` §4 step 7 and §6.
- **The two artifact kinds.** One report, consolidated and re-authored in
  place, and one numbered feedback packet per verification cycle.
- **The return half.** Verification verdicts come back as typed, code-free
  evidence keyed by requirement, never as code-derived requirements
  (`rmf-sl` §8).

### 4.3 What changes

| | `rmf-sl` | `fips-sl` |
|---|---|---|
| Upper bound `U` | SP 800-30/37/53 doctrine + STRIDE + mission and threat intelligence | `./NIST.FIPS.140-3.pdf` + the module's public description + the target level from the manifest |
| Object of study | a system | a cryptographic module: its boundary, services, roles, SSPs, interfaces and states |
| Engine for finding what to verify | STRIDE | the eleven requirement areas |
| Report sections | R1–R5 | F1–F5 (§4.4) |
| Report file | `PREFIX-rmf-report.md` | `PREFIX-fips-report.md` |
| Gaps file | `PREFIX-rmf-gaps.md` | `PREFIX-fips-gaps.md` |
| Feedback packet | `PREFIX-monitor-feedback-NN.md` (800-37 Monitor step) | `PREFIX-fips-feedback-NN.md` |
| Human terminus | the Authorizing Official grants the ATO | the owner of the protected information, or the agency's responsible authority, acknowledges and accepts the residual risk (Ann. 13). Validation itself is the CST laboratory and the CMVP, outside this loop |
| Dominant coherent-and-wrong | fluent but threat-wrong; adversarial-only | fluent, all eleven areas present, but the requirements are invented while stated as if sourced from the PDF |
| Level | — | one target level, 1–4, read from the manifest |

### 4.4 The report: sections F1–F5

| Section | Title | Content |
|---|---|---|
| **F1** | Module and target level | The module (`MOD#`: its role, never a file name), its boundary, its services (`SV#`), its roles (`RL#`), its SSPs (`SSP#`), its documented interfaces (`IF#`), its states (`ST#`), and the level line of rule F6. |
| **F2** | Requirement areas | One subsection per area, `AR1` to `AR11`, in the PDF's order (the headings are for readers; the linter uses the `AR#` tokens). Each area holds requirement items (`RQ#`) or one `N/A` line (rule F2). |
| **F3** | Failure modes | For each `RQ#`, how the module would fail it (`FM#`): a service run before its self-test passed, an SSP left in memory after use, data output in an error state. |
| **F4** | Verification obligations | Each `FM#` becomes a verification obligation (`VO#`) with a property class from `area-properties.md` and a priority. |
| **F5** | Residuals and sign-off | The residual register: one `RR#` per failure mode or requirement out of reach of the formal tools, with its plane and its non-formal treatment, and the standing residuals of §4.5. Sign-off `PENDING` until the terminus of §4.3 accepts it. |

Rules of the pinned format (`references/report-format.md`), numbered F0 to
F7 so they are not confused with the `rmf-sl` rules. Two `rmf-sl` rules
apply as they are: its rule 0, locality (one artifact per line, with all its
tokens on that line), and its rule 5 (no code artifacts in F1–F4).

0. **Home lines (rule F0).** Each defined tag has a home section:
   `MOD SV RL SSP IF ST` in F1, `RQ` in F2, `FM` in F3, `VO` in F4, `RR` in
   F5. *The `X#` line* is the one line in X's home section whose first tag
   is `X#`. Every such id has exactly one home line. A mention of `X#`
   anywhere else, for example `RQ3` on a `VO#` line, is a reference: rules
   F2–F5 apply to home lines only, so a reference can neither satisfy nor
   break them. This closes the back-reference masking that
   `rmf-sl/references/report-format.md` warns about. `AR1`–`AR11` are
   different: they are a fixed vocabulary, the eleven areas, with no home
   line. Rule F2 and check F-C3 cover them.

1. **Tags (rule F1).** `MOD# SV# RL# SSP# IF# ST# AR# RQ# FM# VO# RR#`. They are
   case-sensitive, have no space before the number, and stay stable across
   iterations. `MOD` and `SSP` are used instead of `MD` and `SP` so that
   `MD5` and `SP800-140C`, which a FIPS report will mention, are not read as
   tags.
2. **Areas (rule F2).** Every `RQ#` line names exactly one `AR#`. An area with no
   requirement has a line in F2 holding its `AR#`, the token `N/A` and a
   non-empty reason: `- AR6 N/A — software-only module, no physical
   enclosure`.
3. **Source on every requirement (rule F3).** Every `RQ#` line carries exactly one
   source token, in ASCII:
   - `src:PDF-ann6`, `src:PDF-ann7`, `src:PDF-ann10` or `src:PDF-ann13`.
     These are the only parts of the PDF with normative or scoping text
     (applicability, level choice, Approved security functions,
     conformance and residual risk). Any other section on an `RQ#` line
     fails the linter;
   - `src:UNSOURCED`: the author's reading of the area at the target level,
     with no text in the corpus behind it.

   `UNSOURCED` is allowed: given §1, it is the honest state of most
   requirements. It is never hidden: every `UNSOURCED` requirement appears in
   the reviewer's critique and in the F5 sign-off. Whether a `src:PDF-…`
   requirement really says what the cited section says is a content check;
   it stays with the reviewer, not the linter.

   Other text may cite the PDF with the full token set (`src:PDF-abs`,
   `src:PDF-ann1` to `src:PDF-ann14`, `src:PDF-sec1`, `src:PDF-sec2`,
   `src:PDF-sec3`, `src:PDF-sec3.1` to `src:PDF-sec3.4`, `src:PDF-tab1`),
   for example an F1 line on the level choice.
4. **Chaining (rule F4).** Every `FM#` line names at least one `RQ#`.
   Every `VO#` line names at least one `FM#`, the `RQ#` of each of them, a
   property class and a priority `P1`–`P3`. Every `RR#` line names a plane
   (§4.5), a treatment, and what it leaves open: at least one `FM#` or
   `RQ#`, or, for a standing residual (§4.5) that no requirement surfaced,
   its area or the token `STANDING` (`physical` → `AR6`, `ENV` → `AR5`,
   `side-channel` → `AR7`; `crypto`, `supply-chain`, `validation` →
   `STANDING`). The token is upper case and matched case-sensitively, so
   prose such as "long-standing" never satisfies it. Because `VO#` and
   `RR#` lines carry their `RQ#`, the coverage check "every `RQ#` is named
   on at least one `VO#` or `RR#` line" stays line-local, like
   `rmf-lint.sh`'s checks. The linter also checks, across home lines, that
   the set of `RQ#` on a `VO#` line equals the union of the `RQ#` named by
   its `FM#` home lines: none missing, none extra. Both are home lines, so
   this is cheap.
5. **Level applicability (rule F5).** An `RQ#` may carry `min-level K`. `K` must not
   exceed the target level, or the item does not belong in the report.
6. **The level line (rule F6).** F1 contains exactly one line matching
   `^level: [1-4]$`: a bare paragraph line, not a list item (`- level: 3`
   does not match). No other line in the report may match it. `min-level K`
   does not match, since it does not start the line. The skeleton (§5) shows
   it.
7. **Scales (rule F7).** The priority is `P1` (high) to `P3` (low). The property class
   is a token from `area-properties.md`. The plane is one of `crypto`,
   `ENV`, `physical`, `side-channel`, `supply-chain`, `logic`, `validation`.

### 4.5 The eleven areas → verification properties

`references/area-properties.md` maps each area to property classes that
`frama-c-monitoring` (WP, macsl) or Creusot can check, and to classes that
stay residual. **This table is the skill's design choice, not text from the
PDF**, and the reference file says so in the same words.

| Area | Property class (token) | What is checked, and how | Residual (plane) |
|---|---|---|---|
| AR1 module specification | `approved-only` | in the approved mode, every service reaches only functions on the module's list of Approved security functions. A **call-graph check** (a Frama-C script over the call graph), not a WP proof | the list itself (`validation`) |
| AR2 interfaces | `output-inhibit` | no data output while the module is in an error or self-test state | — |
| AR3 roles, services, authentication | `role-gate` | each service runs only with an authenticated, authorized role | strength of the authentication mechanism (`crypto`) |
| AR4 software/firmware security | `integrity-first` | the integrity test runs, and passes, before any service | the integrity technique (`crypto`) |
| AR5 operating environment | — | — | `ENV` |
| AR6 physical security | — | — | `physical`. A software-only module marks AR6 `N/A` in F2 and still writes the standing `physical` residual in F5, with "not applicable: no physical enclosure" as its treatment |
| AR7 non-invasive security | — | — | `side-channel`: constant-time tools, not WP |
| AR8 SSP management | `zeroize`, `no-plain-ssp-out` | SSPs are zeroized after use and on every error path; no plaintext SSP leaves through a data output. The `zeroize` proof is on the source: a compiler can remove the clearing as a dead store | removed zeroization (`supply-chain`) |
| AR9 self-tests | `selftest-order`, `error-state` | the pre-operational and conditional self-tests run before first use; a failure enters the error state and stays there | the test vectors (`crypto`) |
| AR10 life-cycle assurance | `fsm` | the transitions the code allows are those of the documented finite state model | configuration management, delivery (`logic`) |
| AR11 mitigation of other attacks | — | — | `side-channel` or `logic`, per item |

**System-level classes.** `output-inhibit`, `role-gate`, `integrity-first`,
`selftest-order`, `error-state` and `fsm` are properties over every path or
over the order of events in the whole module. Per-function `requires` and
`ensures` cannot express them without ghost state. The `rmf-sl` warning
applies to all six: they need macsl or a whole-module invariant, and a ghost
function with a postulated `ensures` does not count as verified.

**Standing residuals.** Every report names these in F5, as in `rmf-sl` rule
6, even if no requirement surfaced them. Each is an `RR#` line with the
plane token, naming what rule F4 asks (an `FM#` or `RQ#` if one exists,
otherwise its area or `STANDING`):

- strength of the cryptographic primitives (`crypto`);
- the AR5, AR6 and AR7 planes (`ENV`, `physical`, `side-channel`);
- compiler correctness, including removed zeroization, and supply chain
  (`supply-chain`);
- the CMVP validation itself (`validation`): a proof is evidence for the
  laboratory, not a validation.

### 4.6 The level

The target level does three things:

1. It is written in F1 (rule F6), and the linter checks it against the
   manifest.
2. It selects which `RQ#` belong in the report (rule F5).
3. It sets the volume budget of Gate A: at level 1 about 1–3 `RQ#` per
   applicable area, rising to 3–6 at level 4. These numbers are
   placeholders (open point 3).

Since the PDF does not say what each level requires, every `min-level`
choice is `UNSOURCED` unless the corpus grows (open point 1). The reviewer
checks them for consistency only: a requirement marked `min-level 3` must
not be weaker than one marked `min-level 2` in the same area.

## 5. The linter `bin/fips-lint.sh`

`bin/fips-lint.sh REPORT.md` is the mechanical lower bound, as
`bin/rmf-lint.sh` is for `rmf-sl`. It is built the same way: a bash wrapper
around an embedded Python 3 script (`"$PY" - "$1" <<'PYLINT'`, with
`PY="${ROCQ_PYTHON_BIN:-python3}"`), using only the standard library. Exit 0
means pass, 1 violations, 2 a usage or format error. The script is
line-oriented, so the `rmf-sl` locality rule (one artifact per line) still holds.

**The target level.** The linter reads `fips_level` from `config/auto-wp.json`
in the current directory, the project root. It exits 2 with a message if the
file is missing, is not valid JSON, or has no `fips_level`. For tests,
`FIPS_LEVEL=N` in the environment overrides the manifest. This is documented
in the script header as a test hook only.

| Check | Rule | Severity |
|---|---|---|
| F-C0 | every `MOD SV RL SSP IF ST RQ FM VO RR` id has exactly one home line (rule F0); one defined twice, or only referenced, fails. `AR#` is not checked here | FAIL |
| F-C1 | sections F1–F5 present, as headings holding `F1` … `F5` | FAIL |
| F-C2 | exactly one line matching `^level: [1-4]$`, inside F1, with the level equal to the manifest's (rule F6) | FAIL |
| F-C3 | each of `AR1`–`AR11` is named on at least one `RQ#` home line or on one `N/A` line with a reason, in F2 (rule F2) | FAIL |
| F-C4 | every `RQ#` home line names exactly one `AR#` and carries exactly one `src:` token | FAIL |
| F-C5 | on `RQ#` home lines that have one (a missing token is F-C4's), the `src:` token is one of `src:PDF-ann6`, `-ann7`, `-ann10`, `-ann13` or `src:UNSOURCED`; every other `src:PDF-…` token anywhere is in the full token set of rule F3 | FAIL |
| F-C6 | chaining (rule F4), on home lines: `FM#` → `RQ#`; `VO#` → `FM#` + `RQ#` + class + priority, its `RQ#` set equal to the union of its `FM#` home lines' `RQ#`; `RR#` → plane + (`FM#`, `RQ#`, `AR#` or `STANDING`); every `RQ#` named on a `VO#` or `RR#` home line | FAIL |
| F-C7 | no `RQ#` home line with `min-level K` greater than the target level (rule F5) | FAIL |
| F-C8 | F5 holds an `RR#` line for each standing plane: `crypto`, `ENV`, `physical`, `side-channel`, `supply-chain`, `validation`. This is a new check: `rmf-lint.sh` does not check the residuals of its rule 6 | FAIL |
| F-C9 | endogeneity: no code artifacts in F1–F4, with the `rmf-lint.sh` C8 regex (`\w+\.(c\|h\|cpp\|cc\|rs)`, `#include`, `#define`, `0x…`, `::`, `->`) | FAIL |
| F-C10 | volume within the Gate-A budget for the level (§4.6) | WARN |
| F-C11 | count of `src:UNSOURCED` items, printed | INFO |

**F-C1 is a precondition.** The other checks presuppose the five
sections. When F-C1 fails, the linter reports F-C1 alone and exits 1
without running the others: a missing F4, for example, would otherwise also
leave every `VO#` without a home line (F-C0) and every `RQ#` uncovered
(F-C6).

**Pilot and canaries.** The known-good fixture is a separate file,
`fips-sl/references/skeleton.md`, so a test can read it without parsing
`report-format.md`, which shows it and links to it. It must pass. Each FAIL
check has one broken copy, made by the test as a string edit of the
skeleton, that must fail with that check's ID and no other. For that, the
skeleton's standing residuals name their area or `STANDING`, never an
`RQ#`, so removing one trips F-C8 alone:

| Broken copy | Check |
|---|---|
| a second `RQ1` home line | F-C0 |
| F4 heading removed | F-C1 |
| `level: 2` while the manifest says 3 | F-C2 |
| AR6 line removed | F-C3 |
| an `RQ#` with no `src:` token | F-C4 |
| an `RQ#` with `src:PDF-ann1` | F-C5 |
| a `VO#` without its `RQ#` | F-C6 |
| `min-level 4` at level 3 | F-C7 |
| the `side-channel` residual removed | F-C8 |
| a file name `parser.c` in F2 | F-C9 |

## 6. What `--driver` installs and changes

**Option B: each driver installs its own campaign command; everything else
is installed for both.** A `fips` project has `/fips` and no `/rmf`; an
`rmf` project has `/rmf` and no `/fips`. `rmf-sl`, `fips-sl`,
`bin/rmf-lint.sh`, `bin/fips-lint.sh` and the PDF are installed whatever the
driver. So the user sees one campaign command, the driver's, and "uses
`fips-sl` instead of `rmf-sl`" means that `fips-sl` drives the campaign:
`rmf-sl` is still present, but nothing in a `fips` project runs it. The
options considered are in open point 8.

**The command filter.** `copy_commands` (`auto-wp.py:134-145`) works per
file. It skips the other driver's command file: `rmf.md` under `--driver
fips`, `fips.md` under `--driver rmf`. The ownership is a constant next to
`LINKS` and `RESERVED`:

```python
DRIVER_COMMANDS = {"rmf": "rmf.md", "fips": "fips.md"}
```

**Why the skills and linters stay for both drivers:**

- About fifteen installed files refer to `rmf-sl` or `bin/rmf-lint.sh`,
  for example: `ebios-sl/references/stride-families.md:70`,
  `report-format.md:137` and `crosswalk-format.md:37` (links to
  `../../rmf-sl/references/attack-mapping.md`);
  `frama-c-launch/SKILL.md:179,535`; `frama-c-monitoring/SKILL.md:864`;
  `frama-c-monitoring/templates/crosswalk-template.md:11`;
  `bin/ledger-ratchet.sh:4`; `time-loop/time-loop.sl.json:96,237,361,380`.
  Removing `rmf-sl` would leave all of them dangling.
- `install_tools` copies each `tools/` entry whole (`copytree` of `bin/`),
  so removing one script from `bin/` would need a new file-level filter.
  `copy_skills` and `install_tools` need no change.

**Mentions of the absent command.** Leaving out `/rmf` or `/fips` breaks no
link, but some installed prose names `/rmf`:

| Where | Change |
|---|---|
| `time-loop/SKILL.md` (16 occurrences, including the "Pairs with" lines 973–974), `commands/time-loop.md` (14), `time-loop.sl.json` (1, in `description`, line 9) | read through the driver table (§7.1) |
| `frama-c-launch/SKILL.md:76-77`, "`--machdep=<name>` via `/rmf`", "When `/rmf` forwards `--machdep=<name>`" | "via `/rmf` or `/fips`", "When `/rmf` or `/fips` forwards" |
| `frama-c-launch/SKILL.md:472`, "forwarded by `/rmf`/`/ebios`" | "forwarded by `/rmf`, `/fips` or `/ebios`" |
| README line 130 | `/{{DRIVER}}` (§7.3) |
| `frama-c-monitoring/references/crosswalk-generation.md:60`, "In the `/rmf` and `/ebios` campaigns" | "In the `/rmf`, `/fips` and `/ebios` campaigns (whichever this project has)" |
| `sl-monitoring-sl/SKILL.md:137,153`, which list `/time-loop`, `/rmf` as examples of use modes | add `/fips`; the list stays a list of examples |
| `rmf-sl/SKILL.md:147`, flags "accepted on the `/rmf` invocation"; `rmf-sl/references/crosswalk-format.md:6`, "The `/rmf` campaign produces a `rmf-crosswalk.md`" | unchanged: `rmf-sl` only runs from `/rmf`, so in a `fips` project the sentence describes a skill that is not driving |

`fips-sl` names `/fips` in the same way, and is inert in an `rmf` project.

What the driver changes:

| | `--driver rmf` | `--driver fips --level N` |
|---|---|---|
| manifest | `"driver": "rmf"` | `"driver": "fips"`, `"fips_level": N` |
| output line | `driver:   rmf` | `driver:   fips (FIPS 140-3 level N)` |
| README (§7.3) | RMF lines | FIPS lines |
| base command of `/time-loop` (§7.1) | `/rmf` | `/fips` |

New and changed files in the templates:

| File | Layer |
|---|---|
| `skills/fips-sl/` (§4.1) | common |
| `tools/NIST.FIPS.140-3.pdf`, copied to the project root as `./NIST.FIPS.140-3.pdf` | common: `templates/common/tools/` is new |
| `commands/fips.md`, installed only with `--driver fips` | c |
| `tools/bin/fips-lint.sh` | c, next to `rmf-lint.sh` |
| `skills/frama-c-launch/templates/fips-crosswalk.md` (the launch-side join, mirroring `rmf-crosswalk.md`; §7.1), `references/fips-feedback.md` | c |
| `skills/frama-c-launch/SKILL.md`: FIPS as a third driver (§7.1), and the `/fips` mentions at lines 76–77 and 472 | c |
| `skills/frama-c-monitoring/SKILL.md`: step 10 (lines 459–466), and one sentence at lines 858–865, "or the FIPS ledger of `crosswalk-template.md` §3 (`# ledger: fips`)" | c |
| `skills/frama-c-monitoring/templates/crosswalk-template.md`: line 10 adds `fips-sl` / `fips-crosswalk.md` to the producers; §3 gains the FIPS ledger form (§7.1) | c |
| `skills/frama-c-launch/frama-c-launch.sl.json`: line 11 (`notes`) adds `*-fips-report.md` | c |
| `skills/rmf-sl/references/crosswalk-format.md`, `skills/ebios-sl/references/crosswalk-format.md`: "the crosswalk is generated" gains "(`bin/crosswalk-gen.sh --kind rmf\|ebios\|fips`)", with the `bin/` prefix that T7 requires | common |
| `skills/frama-c-monitoring/references/crosswalk-generation.md`: lines 11–13 (seating: `PREFIX-fips-report.md`, `fips-ledger.tsv`), 26, 42–46 (the `VO#` header under `fips`), 60 | c |
| `skills/sl-monitoring-sl/SKILL.md`: lines 137 and 153 | common |
| `tools/bin/ledger-ratchet.sh`: the FIPS ledger row form and baseline | c |
| `tools/bin/crosswalk-gen.sh`: `--kind fips` (§7.1) | c |
| `skills/time-loop/SKILL.md`, `time-loop.sl.json`, `commands/time-loop.md`: the driver table | c |
| `README.md`: placeholders | c and rust |

New counts: C 22 skills (12 + 1 common, 9 C), 3 commands (`/ebios`,
`/time-loop` and the driver's), 23 scripts in `bin/`. The C template
directory holds 4 command files. Rust 17 skills by the spec count (13 common, of which the Rust layer
replaces 4 with its own versions, plus 4 Creusot skills), 16 while
`creusot-launch` is pending.

The PDF is vendored, so the project stays stand-alone. It is a US government
work. `test_templates.py` checks its sha256.

## 7. What the other files need

### 7.1 C: `/fips`, `frama-c-launch`, `time-loop`

- **`/fips`** (`templates/c/commands/fips.md`): `/rmf` with the RMF parts
  swapped. Phase 1 runs `fips-sl` code-blind. Phase 2 runs `frama-c-launch`
  then `frama-c-monitoring` on the queue ranked by `PREFIX-fips-report.md`.
  At the end of a cycle with a verdict change, it writes the next
  `PREFIX-fips-feedback-NN.md` per `frama-c-launch/references/fips-feedback.md`.
  This follows the RMF pattern, where the feedback packet is specified in
  `commands/rmf.md` and `rmf-feedback.md`, not in `frama-c-monitoring`.
  The flags are those of `/rmf`, with their aliases: `--fresh`/`--force`,
  `--monitor-only`/`--quick`, `--no-coq`, `--machdep=<name>`, and
  `--linux`/`--full-tu`. The last two are inherited
  as they are: they call `linux/linux-acsl/onboard-linux.sh`, which is not
  in the templates, the same pre-existing gap `/rmf` has. `/fips` is
  installed only with `--driver fips`, so the manifest always has
  `fips_level` when it runs. If the key is missing anyway (a hand-edited
  manifest), `/fips` stops with a message.
- **`frama-c-launch`** gains:
  - `templates/fips-crosswalk.md`, the launch-side join filled by hand at
    onboarding, mirroring `rmf-crosswalk.md`: §1 `MOD#`/`SV#` ↔ translation
    unit; §2 the `VO#` ranking by `P1`–`P3`, with a `VO#` → TU(s) column;
    §3 the verification feedback into F5, which `fips-feedback.md` fills
    (as `rmf-feedback.md:53-54` fills `rmf-crosswalk.md` §3). It holds no
    ledger: the ledger lives in the generated `PREFIX-crosswalk.md` (next
    bullet);
  - `references/fips-feedback.md`, which turns verdicts into evidence keyed
    by `RQ#`. A `PROVED` `VO#` is evidence for its `RQ#`, never a
    validation. A `VIOLATION` re-enters F3 as a failure mode, from its
    finding statement, not from its reproducer.

  Its SKILL.md lists FIPS as a third driver, next to EBIOS and the "NIST RMF
  alternative" (`SKILL.md:177-182` and `:534`).
- **The coverage ledger.** The crosswalk schema has a §3 STRIDE coverage
  ledger, asset × {S,T,R,I,D,E}, which is the surface of
  `frama-c-monitoring`'s Gate C and of `bin/ledger-ratchet.sh`
  (`frama-c-monitoring/templates/crosswalk-template.md:42`,
  `frama-c-monitoring/SKILL.md:464,857-858`). Without STRIDE that ledger
  has no FIPS form, and `ledger-ratchet.sh` would SKIP silently in every
  `fips` project (it SKIPs when no ledger is present). So, under `fips`,
  the §3 ledger of the generated `PREFIX-crosswalk.md` is a FIPS ledger:
  one row per `VO#`, columns `VO#`, `AR#`, property class, and one cell
  with the same lifecycle tokens
  (`UNMODELED | PROVED | TRUSTED-PENDING | TRUSTED | N/A[(RR#)]`). Its
  schema is a FIPS form added to §3 of `crosswalk-template.md`, next to
  §3.3, with the same §3.1 lifecycle and §3.2 ratchet rule. The form pins
  the header row `| VO# | AR# | Class | Coverage |`, and the first cell of
  each row is the bare `VO#`, with no text after it. So the file
  `ledger-ratchet.sh:13` calls the authoritative format contract describes
  both forms. `ledger-ratchet.sh` learns this second row form (a
  `# ledger: fips` marker line in §3 of the crosswalk selects it; the
  generator writes that line, §7.1 "The producer"). The marker
  renders as a Markdown heading, as the existing `# ws1-stage: N` marker
  does (`frama-c-monitoring/SKILL.md:863`); this follows that precedent. Its rule is unchanged: FAIL
  only when a `PROVED` or `TRUSTED` cell falls back to `UNMODELED`, or when
  a row of the baseline is gone.

  **The baseline file.** Today `from_tsv` drops any baseline row with fewer
  than 7 tab-separated fields (`ledger-ratchet.sh:178-181`), so a two-column
  baseline would read back empty and every regression would pass. The FIPS
  baseline is therefore written with `# ledger: fips` as its first line, and
  `from_tsv` parses a file with that first line as `VO#<TAB>cell` rows.

  The marker is matched as the exact line `# ledger: fips`, before the
  generic `#`-comment skip (`ledger-ratchet.sh:177`): the STRIDE baseline's
  first line, `# ledger-baseline.tsv — frozen STRIDE ledger …` (`:167`),
  also starts with `# ledger`.

  **The WS1 stage-1 rule** (`ledger-ratchet.sh:186-207`) fires on any row
  label matching `race|concurren|ws1`. It concerns the STRIDE race family
  and is not applied to the FIPS form, where a row label is a `VO#`.

  **The producer: `crosswalk-gen.sh --kind fips`.** The crosswalk, ledger
  included, is generated, never hand-written: `bin/crosswalk-gen.sh` is the
  only writer of `PREFIX-crosswalk.md`, and `frama-c-monitoring` runs it at
  campaign close (`SKILL.md:459-466`, step 10: "Do NOT hand-write the
  crosswalk"). Today it knows `--kind rmf|ebios` only, and exits 2 when
  neither `PREFIX-rmf-report.md` nor `PREFIX-ebios-report.md` exists
  (`crosswalk-gen.sh:44-52`), so a `fips` campaign close would fail. It
  gains a third kind:
  - `--kind fips`, auto-detected from `PREFIX-fips-report.md` (checked after
    the RMF and EBIOS reports, so existing projects detect as before);
  - §1 rows are the F4 `VO#` home lines (the id, and the text up to the
    first separator as the role), so its unit and coverage columns join on
    `VO#` as they join on `SA#` today (`crosswalk-gen.sh:187-199`). Keying
    §1 on `MOD#`/`SV#` would leave both columns empty, since no `VO#` line
    names an `SV#`. §2 is the F4 `VO#` home lines with the priority
    `P1`–`P3` in place of likelihood and risk, and §5 the F5 `RR#` home
    lines;
  - §3 from `PREFIX-acsl/fips-ledger.tsv` (`VO#<TAB>AR#<TAB>class<TAB>cell`),
    which the code-aware architect fills, as it fills `stride-ledger.tsv`
    today. The generator writes the `# ledger: fips` marker line into §3 of
    `PREFIX-crosswalk.md`, above the table; the TSV itself needs no marker,
    and the generator skips `#` lines in it;
  - the faithfulness check (every `PROVED` cell backed by a
    `Valid`/`PROVED`/`GREEN` verdict, the regex at `crosswalk-gen.sh:126`;
    non-vacuity is the verdict producer's claim, not checked by the
    generator) joined on `VO#`. The overlay's `verdicts.tsv` is read by
    header name, not position (`crosswalk-gen.sh:115-120`; contract at
    `crosswalk-generation.md:44-46`: a header row with at least `SA#`,
    `verdict` and one of `function`/`unit`). Under `fips` the column headed
    `SA#` is headed `VO#`; for kind `fips` the generator reads that header,
    and skips `VO\d+` placeholder units as it skips `SA\d+` ones today
    (`:127`). `frama-c-monitoring` fills the column from the `VO#` → TU(s)
    column of `fips-crosswalk.md` §2. `fips-sl`'s `crosswalk-format.md`
    binds `verdicts.tsv ↔ VO#`, as `rmf-sl`'s and `ebios-sl`'s bind it to
    `RS#` / `SS#` (`crosswalk-format.md:35`).

    The other `verdicts.tsv` layouts are untouched. The overlay scaffold
    line of `onboarding-package.md:46` describes the same
    `PREFIX-acsl/verdicts.tsv`, and its layout stays as it is for RMF and
    EBIOS. These are different files: `framac/.verdicts.tsv` (`bin/framac-gen-verdicts.sh`,
    `framac-queue.sh`, `framac-gen-report.sh`, `framac-soft-residual.sh`),
    and `$ADIR/verdicts.tsv` of `rmf.md:44` / `ebios.md:32`.
- **`frama-c-monitoring`** changes in four places, all for the FIPS kind:
  - step 10 (`SKILL.md:459-466`): under `fips`, the architect fills
    `fips-ledger.tsv` instead of `stride-ledger.tsv`, and
    `bin/crosswalk-gen.sh <prefix>` detects the FIPS kind;
  - `references/crosswalk-generation.md`, the `verdicts.tsv` contract: the
    `VO#` header under `fips` (lines 42–46) and the FIPS seating (lines
    11–13, 26);
  - the `ledger-ratchet.sh` description at `SKILL.md:858-865` gains the FIPS
    ledger;
  - `references/crosswalk-generation.md:60` names `/fips` (§6).

  `fips-lint.sh` has no structural ledger check like `rmf-lint.sh` C9: the
  FIPS ledger is never hand-written, only generated and machine-checked by
  `crosswalk-gen.sh`. `crosswalk-template.md:11` and `SKILL.md:864`, which
  name the RMF and EBIOS linters' C9, stay as they are.

  Its §8e risk-feedback step handles EBIOS only, and RMF has no branch
  there either; that stays as it is.
- **`time-loop`** drives `/rmf` by name throughout its SKILL.md, its
  `time-loop.sl.json` and its command, and it ranks and splits its work by
  the report's scenarios: the monotone-coverage gate, Gate C, the Plane-H
  selector and the Monitor packets are keyed to `RS#` and its risk level
  (`time-loop/SKILL.md:142,154,294,321,537`). Its SKILL.md and its command
  get a driver table that maps the `driver` key of `config/auto-wp.json` to
  all of these:

  | | `rmf` | `fips` |
  |---|---|---|
  | base command | `/rmf` | `/fips` |
  | report | `XXX-analysis-rmf-report.md` | `XXX-analysis-fips-report.md` |
  | gaps | `XXX-analysis-rmf-gaps.md` | `XXX-analysis-fips-gaps.md` |
  | feedback | `XXX-analysis-monitor-feedback-NN.md` | `XXX-analysis-fips-feedback-NN.md` |
  | linter | `bin/rmf-lint.sh` | `bin/fips-lint.sh` |
  | ranked item and scale | `RS#`, risk `High`/`Moderate`/`Low` | `VO#`, priority `P1`/`P2`/`P3` |
  | Plane W (WP) | Tier-1 untrusted-input `RS#` | `VO#` of class `zeroize`, `no-plain-ssp-out` |
  | Plane H (macsl system properties) | Tier-3 authorization/integrity `RS#` | `VO#` of the six system-level classes of §4.5 |
  | outside both planes | — | `approved-only` (call-graph check) |
  | terminus | Authorizing Official | owner of the protected information (Ann. 13) |

  The RMF-specific text stays and is read through the table, so
  `/time-loop grub 72` drives `/fips` in a `fips` project. This includes
  the "Pairs with" line (`time-loop/SKILL.md:973`), which names
  `config/commands/rmf.md`. Without a `driver` key (a project generated
  before this change), `time-loop` assumes `rmf`. The rewrite must keep the
  exact Stop bullet of `commands/time-loop.md` that T6 matches.

  `time-loop.sl.json` cannot hold the table: its `monitors` field is a
  single string (`sl-internal/references/sl-schema-1.0.json:49-52`), today
  `"rmf-sl"`. It stays `"rmf-sl"`, and its `description` gains one sentence:
  under `driver: fips` the base loop is `fips-sl`, per the table in
  SKILL.md.

### 7.2 Rust

The Rust layer has no risk driver wired in today: `creusot-launch` is not
written (`auto-wp.md` §4.3.7, roadmap step 1), and no Rust skill reads an
RMF report. For `--rust`, `--driver` and `--level` are recorded in the
manifest and the README, and `fips-sl` is installed like every common skill.
`creusot-launch` reads the driver from the manifest once it is written. The
area table of §4.5 applies to Creusot unchanged: the property classes belong
to the module, not to the tool. A Rust project has neither `bin/rmf-lint.sh`
nor `bin/fips-lint.sh` (open point 5).

### 7.3 README

`write_readme` replaces `{{DIR}}` and `{{LANGUAGE}}` today. It gains three
placeholders:

- `{{DRIVER}}` → `rmf` or `fips`;
- `{{FEEDBACK}}` → `monitor-feedback` or `fips-feedback`;
- `{{DRIVER_LINE}}` → `Risk study: NIST RMF (rmf-sl).`, or `Requirement
  study: FIPS 140-3, security level N (fips-sl).`

The C README uses them in these places (line numbers as of today):

| Line | Today | With placeholders |
|---|---|---|
| 3–4 (intro) | — | add `{{DRIVER_LINE}}` |
| 96 | `grub-analysis-rmf-report.md` | `grub-analysis-{{DRIVER}}-report.md` |
| 98 | `grub-analysis-monitor-feedback-NN.md` | `grub-analysis-{{FEEDBACK}}-NN.md` |
| 130–131 | `/rmf <dir> <dir>-analysis` — a single campaign (risk study, onboarding, verification) | `/{{DRIVER}} <dir> <dir>-analysis` — a single campaign (study, onboarding, verification) |
| 132–133 | `/ebios <dir>` — … with an EBIOS Risk Manager risk study instead of the RMF one | … with an EBIOS Risk Manager risk study instead of the `{{DRIVER}}` one |
| 163 | `bin/rmf-lint.sh grub-analysis-rmf-report.md` | `bin/{{DRIVER}}-lint.sh grub-analysis-{{DRIVER}}-report.md` |
| 164 | `rmf-lint.sh` and `ebios-lint.sh`, gates of `rmf-sl` and `ebios-sl` | adds `bin/fips-lint.sh` and `fips-sl` |

The Rust README gains only `{{DRIVER_LINE}}`, in its intro.

The quick start stays `/time-loop grub 72` under both drivers: in a `fips`
project, `time-loop` drives `/fips` through the table of §7.1. GRUB as a
whole is not a cryptographic module. Under `--driver fips`, the README adds
one sentence after the command: to study GRUB's cryptographic library as
the module, use `/time-loop grub 72 --dir=grub-core/lib/libgcrypt`. The
path is not verified here, since there is no GRUB clone on the host; the
first level 3 run confirms it. Whether it is the right default target is
open point 2.

## 8. Tests and documents to update

**`tests/test_auto_wp.py`:**

- the usage-error table of §2, in both option orders;
- `--driver fips --level 3`: the manifest keys, the `driver:` line;
  `config/commands/fips.md` present and `rmf.md` absent; otherwise the same
  installed files as the default (`rmf-sl`, `fips-sl`, both linters, the
  PDF);
- the default run: `config/commands/rmf.md` present and `fips.md` absent;
- the default run: `"driver": "rmf"`, no `fips_level`, `driver:   rmf`;
- `test_c_output_exact`: the `driver:` line, the new counts (22, 3) and the
  `copied  foobar/NIST.FIPS.140-3.pdf` line between the `.gitignore` and
  `bin` lines;
- the constants `COMMON_SKILLS` (line 35), which gains `fips-sl`, and
  `C_COMMANDS` (line 44), which is per driver: `ebios, rmf, time-loop` or
  `ebios, fips, time-loop`;
- tests with a hard-coded count: `test_01_c_layout` (line 150, 21 → 22,
  and its `C_SKILLS` and `C_COMMANDS` comparisons), `test_02_rust_layout`
  (lines 168–170, `16 - len(RUST_ABSENT_PENDING)` → 17 − …), `test_02b`
  (line 187, 16 → 17), `test_12_other_cwd` (line 398), `test_18_no_git`
  (line 523) and `test_19_rollback` (line 573), each 21 → 22;
- `test_rust_output_counts`: `lines[1]` (`skills:`) becomes `lines[2]` and
  `lines[2] == "  commands: 0"` (line 626) becomes `lines[3]`; the counts
  become 16 (17 when `creusot-launch` exists) and the PDF line is added;
- `test_rust_output_spec_count_16` becomes `…_17`;
- `test_11_manifest`: the two new keys, and the `commands` list per driver;
- `test_13b`: 23 executables in `bin/`;
- `test_13c`: a Rust project now has `NIST.FIPS.140-3.pdf`, whose
  `copied` line is its only one, and still no `bin/`;
- the README tests (13, 14): the `{{DRIVER}}` lines for both drivers;
- test 19 (rollback) re-run with `--driver fips`.

**`tests/test_templates.py`:**

- the constants `COMMON_SKILLS` (line 17), which gains `fips-sl`, and
  `C_COMMANDS` (line 26), which gains `fips`, since the template holds all
  four command files;
- T3: 13 common skills, 4 C command files in the template
  (`test_T3_c_layer`, line 105, compares with `C_COMMANDS`);
- T5: the C README has exactly
  `{DIR, LANGUAGE, DRIVER, FEEDBACK, DRIVER_LINE}`, the Rust README
  `{DIR, LANGUAGE, DRIVER_LINE}`;
- T6: unchanged, and it must still pass after the `time-loop` rewrite;
- T7: 23 scripts in `templates/c/tools/bin/`;
- T7: every mention of `fips-lint.sh` in the new files is written
  `bin/fips-lint.sh`, as T7 already enforces for the other scripts. T7
  excludes every layer's `tools/` from the scan, not only
  `templates/c/tools` (line 227), so it no longer reads the PDF;
- new T8: `fips-sl/SKILL.md` front matter; the PDF's sha256;
  `sl-internal/scripts/sl_disjointness_check.py fips-sl.sl.json` exits 0.
  The two-file mode is not used with `fips-sl.sl.json`: `time-loop.sl.json`
  keeps `monitors: "rmf-sl"`, and with another base the script only prints
  an INFO (`sl_disjointness_check.py:237-239`), so the check would pass
  without testing anything;
- new T9: `bin/fips-lint.sh` on `references/skeleton.md` passes, and each
  broken copy of §5 fails with its check ID. The test writes a
  `config/auto-wp.json` with `fips_level: 3` in a temporary directory and
  runs the linter there; `FIPS_LEVEL` is tested separately. T9 runs a
  script, so the `test_templates.py` docstring ("They only read
  templates/") changes;
- new T9b: `bin/ledger-ratchet.sh` on a FIPS ledger (§7.1): a first run
  writes the baseline, whose first line is `# ledger: fips`; a second run
  with a `PROVED` cell changed to `UNMODELED` fails, which shows the
  regression is detected after a round trip through the baseline file; a
  `TRUSTED-PENDING` cell only warns; a FIPS ledger whose header row the
  test alters to contain "race" (`ledger-ratchet.sh:114-118`, the other trigger of the WS1
  rule) with a `PROVED` cell passes, since the WS1 rule is not applied to
  the FIPS form; a STRIDE baseline,
  whose first line starts with `# ledger-baseline.tsv`, is still read as
  seven columns;
- new T9c: `bin/crosswalk-gen.sh` on a fixture `PREFIX-fips-report.md`,
  `PREFIX-acsl/fips-ledger.tsv` and a `verdicts.tsv` with a `VO#` header:
  it detects the FIPS kind, writes §1 with one row per `VO#` and its units
  and coverage filled, writes the §3 FIPS ledger, fails when a `PROVED`
  cell has no matching verdict, and `--check` fails on drift. The existing
  RMF and EBIOS kinds still detect as before;
- new T10: the F-C5 section list matches the PDF, from `pdftotext` if it is
  installed; otherwise skipped.

**Level 2:** `tests/c/install-test.sh` runs a second project with
`--driver fips --level 2` and checks C2.1 with the new counts (`skills:   22`;
`commands: 3` is unchanged), plus the
manifest keys.

**Level 3:** a FIPS smoke test needs a module target (open point 2). It is
not specified until the target is chosen.

**`auto-wp.md`:**

| Section | Change |
|---|---|
| §1 | usage line with `--driver` and `--level`; the usage-error rules of §2 |
| §3.2 | the manifest keys; "only `skills/` and `commands/` are copied from a layer" becomes true of `config/` only; tools come from `tools/` on every layer |
| §3.4 | the README placeholders of §7.3 |
| §3.6 | the `driver:` line; the new counts; the PDF `copied` line for both languages, so "with `--rust` there is no `copied` line" is no longer true |
| §4 | the tree shows `common/{skills,commands,tools}` |
| §4.1 | `fips-sl` in the common skills; `common/tools/` |
| §4.2.1 | `fips-lint.sh` in `bin/`; 23 scripts |
| §5 | the tests above |

**`tests.md`:** T3, T5, T7 and the new T8, T9, T9b, T9c and T10 in §3.2
(T6 is unchanged); C2.1 in §5.2
(counts and the second project); R2.1 in §6.2 (counts).

## 9. Open points for review

1. **Corpus.** The PDF names the areas and levels but holds almost none of
   the requirements (§1). As specified, most `RQ#` will be `src:UNSOURCED`,
   which is honest but weak. Two ways to strengthen it:
   - add SP 800-140 and SP 800-140A to F, which are free and public, to the
     corpus. They modify ISO/IEC 19790 rather than replace it, so this helps
     less than it seems;
   - accept a user-supplied ISO/IEC 19790, which is paid and cannot be
     vendored, as an optional file cited as `src:19790-…`.

   You asked for the PDF instead of SP 800-*, so neither is in this draft.
2. **Target.** GRUB as a whole is a system, not a module. §7.3 proposes
   `--dir=grub-core/lib/libgcrypt` as the module boundary; a separate target
   such as a small crypto library is the alternative. Chosen (2026-11-06,
   while implementing this spec): the level 3 FIPS smoke test targets
   [Mbed TLS](https://github.com/Mbed-TLS/mbedtls) at a pinned tag —
   `tests/c/mbed-tls-test.sh` (`MBEDTLS_TAG`/`MBEDTLS_SHA`, default
   `mbedtls-3.6.7`), a real cryptographic library per the fips-sl module
   rule. It prints SKIP until the driver of §6 exists.
3. **Volume per level.** The numbers of §4.6 are placeholders.
4. **STRIDE.** Dropped in favour of the eleven areas. Dropping it also
   drops the STRIDE coverage ledger; §7.1 replaces it with a FIPS ledger per
   `VO#`, which needs a second row form in `ledger-ratchet.sh`. Keeping
   STRIDE as a second coverage check inside AR3 and AR8 would keep the
   existing ledger and ratchet unchanged, at the cost of a longer report and
   two engines to keep consistent.
5. **Linters and corpus in Rust and RMF.** Should `fips-lint.sh`, and
   `rmf-lint.sh` with it, move to `templates/common/tools/bin/` so Rust
   projects get them? Related: `rmf-sl` cites a `nist/` corpus
   (`rmf-sl/SKILL.md:27,36-38`; `rmf-sl.sl.json`, `sources[0].notes`) that
   no template ships. With this change, `fips-sl` would be the only driver
   whose source document is in the project.
6. **More drivers.** `--driver ebios` would follow the same pattern, since
   `ebios-sl` and `/ebios` exist. Not requested; `choices` is `rmf, fips`
   for now.
7. **One level or one per area.** One target level for the whole module is
   the only design the PDF supports. In the real standard, the overall level
   is the minimum over the areas, but the PDF does not say so, and a
   per-area level would need ISO/IEC 19790 (point 1).
8. **What "instead of" installs — decided: option B** (revision 4). The
   options that were considered:

   | | A. both always | B. the other driver's command left out (chosen) | C. the other driver left out entirely |
   |---|---|---|---|
   | `fips` project has | `rmf-sl`, `/rmf`, `rmf-lint.sh` too | `rmf-sl`, `rmf-lint.sh`; no `/rmf` | none of the RMF files |
   | `rmf` project has | `/fips`, which stops without `fips_level` | no `/fips` | none of the FIPS files |
   | code change | none in the copy functions | one filter in `copy_commands` (`auto-wp.py:134-145`), which works per file | a filter in `copy_skills`, `copy_commands` and, per file, in `install_tools` |
   | dangling references | none | none: outside `rmf.md`, `commands/rmf.md` is named only at `time-loop/SKILL.md:973`, covered by the table, and README line 130, which would become `/{{DRIVER}}` | about fifteen files (§6) to reword, plus a test that greps a `fips` project for `rmf-sl` and `rmf-lint` |
   | manifest | `skills` and `commands` identical under both drivers; `driver` is the only difference | `commands` differs | `skills`, `commands` differ |
   | how visible is "instead of" | only in the manifest, the output, the README and what `/time-loop` drives | the user sees one campaign command, the driver's | complete |
   | counts (C) | 22 skills, 4 commands | 22 skills, 3 commands | 21 skills, 3 commands |

   B is specified in §3, §6, §7.3 and §8. A was the simplest but left
   "instead of" visible only in the manifest, the output and the README. C
   matches the words most closely but costs the most. The B column's
   "dangling references: none" holds for links; §6 lists the prose that
   names the absent command and how each mention is handled.

## 10. Review findings and where they are handled

| Finding | Where |
|---|---|
| B1 linter architecture | §5: embedded Python, as `rmf-lint.sh` |
| B2 ambiguous `src:PDF§n` | §1 (`Ann.`/`Sec.`), §4.4 rule F3 (ASCII token set) |
| B3 skip mechanism, README, documents | §6 (command filter only), §7.3 (placeholders, lines), §8 (`auto-wp.md`, `tests.md`) |
| B4 dangling references | §6: both skills and both linters installed; open point 8 |
| S1 terminus | §4.3, §4.4 F5, §7.1 table |
| S2 non-verbatim quotes | §1 (verbatim quotes, Ann. 3 and Sec. 1 for levels and count) |
| S3 "19790 §7" | §1, marked as outside knowledge |
| S4 tag collisions | §4.4 rule F1: `MOD#`, `SSP#` |
| S5 level line | §4.4 rule F6, §5 F-C2 |
| S6 chaining | §4.4 rule F4 (line-local), §5 F-C6 |
| S7 F-C3, F-C8 tokens | §4.4 rules F2 and F7, §5 F-C3 and F-C8 |
| S8 manifest dependency in tests | §5 (exit 2, `FIPS_LEVEL`), §8 T9 |
| S9 affected tests | §8 |
| S10 "exactly as today" | §2, §3 |
| S11 F-C5 existence only | §4.4 rule F3 (four allowed sections), §5 F-C5 |
| S12 system-level classes | §4.5 (six classes; `approved-only` call-graph; `zeroize` compiler note) |
| S13 §8e | §7.1: `/fips` + `fips-feedback.md`, `frama-c-monitoring` unchanged |
| S14 canaries | §5: one broken copy per FAIL check |
| M1 Gate S | §4.2 |
| M2 `/fips` flags | §7.1 |
| M3 option order | §2 |
| M4 `.sl.json` test | §8 T8 |
| M5 quick start under fips | §7.3, open point 2 |
| M6 crosswalk wording | §4.1 |
| M7 open points | §9 points 5 and 7 |

Second review (`fips-skill-spec-report-2.md`):

| Finding | Where |
|---|---|
| B3 (partial) README line 98 | §7.3: `{{FEEDBACK}}`; §8 T5 |
| S2 (partial) Sec. 1 does not name the levels | §1 table, first row |
| S-1 position of the PDF `copied` line | §3 (sorted name order), §8 `test_c_output_exact`, `test_13c` |
| S-2 README line 98 | §7.3 |
| S-3 "the `RQ#` line" undefined | §4.4 rule F0 (home lines), §5 F-C0 and the home-line wording of F-C3 to F-C7 |
| S-4 time-loop table incomplete | §7.1: scale and Plane W/H rows; `SKILL.md:973` |
| S-5 STRIDE ledger | §7.1 (FIPS ledger, `ledger-ratchet.sh` row form), §6 files, §8 T9b, §9 point 4 |
| S-6 open point 8 one-sided | §9 point 8: options A, B, C with both sides |
| M-1 level names | §1 |
| M-2 AR6 vs F-C8 | §4.5 AR6 row |
| M-3 AR8 residual column | §4.5 AR8 row |
| M-4 `monitors` is a string | §7.1 (`time-loop.sl.json`), §8 T8 |
| M-5 fixture | §4.1 `skeleton.md`, §5, §8 T9 and the docstring |
| M-6 flag aliases | §7.1 |
| M-7 level line form | §4.4 rule F6 |
| M-8 libgcrypt path | §7.3 |

Option B (revision 4):

| Change | Where |
|---|---|
| each driver installs only its own campaign command | §2, §3 (counts, manifest), §6 (filter, `DRIVER_COMMANDS`, mentions of the absent command) |
| `/fips` no longer runs in an `rmf` project | §7.1 |
| README `/rmf` bullet becomes `/{{DRIVER}}` | §7.3 |
| tests | §8 |
| decision recorded | §9 point 8 |

Third review (`fips-skill-spec-report-3.md`):

| Finding | Where |
|---|---|
| B-1 F-C0 vs `AR#` | §4.4 rule F0, §5 F-C0 |
| B-2 standing residuals vs chaining | §4.4 rule F4, §4.5 standing residuals, §5 F-C6 and the skeleton note |
| S-1 `frama-c-launch/SKILL.md` mentions of `/rmf` | §6 mentions table and files table |
| S-2 missing files, "otherwise unchanged" | §6 files table, §7.1 `frama-c-monitoring` |
| S-3 stale option-A and §10 wording | §9 point 8 header, §10 B3 and B4 rows |
| S-4 baseline parser, WS1 rule | §7.1 ledger, §8 T9b |
| M-1 mention counts | §6 mentions table |
| M-2 Rust has no campaign command | §2, §3 |
| M-3 F-C5 without a token | §5 F-C5 |
| M-4 two rules named 0 | §4.4: rules F0–F7 |
| M-5 T6 in both lists | §8 `tests.md` |
| M-6 F-C6 consistency | §4.4 rule F4, §5 F-C6 |

Fourth review (`fips-skill-spec-report-4.md`):

| Finding | Where |
|---|---|
| B-1 F-C1 canary trips F-C0 and F-C6 | §5: F-C1 is a precondition |
| B-2 the FIPS ledger has no producer | §7.1: `crosswalk-gen.sh --kind fips`, the `VO#` header of `verdicts.tsv`, `frama-c-monitoring` step 10; §6 files table; §8 T9c |
| S-1 hard-coded counts and test constants | §8 (both test files) |
| M-1 `rmf-sl/references/crosswalk-format.md:6` | §6 mentions table |
| M-2 F4 vs F-C6 directions | §4.4 rule F4, §5 F-C6: set equality |
| M-3 bare word `standing` | §4.4 rule F4: `STANDING` |
| M-4 baseline marker precision | §7.1 the baseline file; §8 T9b |
| M-5 rmf/ebios pair in two more files | §6 files table |
| M-6 T7 reads the PDF | §8 T7 |

Fifth review (`fips-skill-spec-report-5.md`):

| Finding | Where |
|---|---|
| B-1 the ledger has two homes | §7.1: the ledger is §3 of the generated `PREFIX-crosswalk.md`, its schema a FIPS form of `crosswalk-template.md` §3; `fips-crosswalk.md` mirrors `rmf-crosswalk.md` with no ledger; §4.1 `crosswalk-format.md`; §6 files table |
| S-1 `verdicts.tsv` is read by header | §7.1 the producer (`VO#` header, placeholder units, other `verdicts.tsv` files untouched); §6 files table `crosswalk-generation.md` |
| S-2 FIPS §1 keyed on `MOD#`/`SV#` | §7.1: §1 rows are `VO#`; the join is `fips-crosswalk.md` §2; §8 T9c |
| M-1 `# ledger: fips` renders as a heading | §7.1, the `# ws1-stage: N` precedent |
| M-2 no ledger check in `fips-lint.sh` | §7.1, end of the `frama-c-monitoring` bullet |
| M-3 "non-vacuous" | §7.1 the producer |

Sixth review (`fips-skill-spec-report-6.md`, verdict: ready to implement):

| Finding | Where |
|---|---|
| S-1 `crosswalk-gen.sh` without `bin/` | §6 files table |
| M-1 `onboarding-package.md:46` is the same file | §7.1 the producer |
| M-2 `rmf-feedback.md:53-54` | §7.1 `frama-c-launch` |
| M-3 FIPS §3 header not pinned; T9b case vacuous | §7.1 the coverage ledger; §8 T9b |
| M-4 where the marker is emitted | §7.1 the coverage ledger and the producer |
