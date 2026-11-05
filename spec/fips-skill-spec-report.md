# Review of `fips-skill-spec.md`

**Verdict.** The draft is faithful to the request (new `fips-sl` skill modelled on `rmf-sl`, citing only `./NIST.FIPS.140-3.pdf`; `--driver rmf|fips` with `rmf` as default; `--level 1..4`), and its central factual claim is right: the PDF names the four levels and the eleven areas but contains no per-area, per-level requirement text, so most `RQ#` will be `src:UNSOURCED`. The squeeze-loop properties of `rmf-sl` are preserved on paper. It is not implementable as written, for four reasons: the linter is specified against a "grep/awk only" constraint that `rmf-lint.sh` itself does not meet (it is an embedded Python script), the `src:PDF§<n>` token is ambiguous because the PDF has two independent numberings, the driver skip mechanism ignores how `auto-wp.py` copies `tools/` entries whole and how little the README is parametrised, and skipping `rmf-sl` leaves dangling `../rmf-sl/` references in skills that stay installed. Several linter checks are under-defined, two tags collide with crypto vocabulary (`MD#` vs `MD5`), and the human terminus is misattributed relative to PDF §13. The open points are the right ones; open point 1 (corpus) is the real decision.

## Blocking

### B1. The linter architecture claim is false and makes the checks fragile (§5)
- Spec: "It is a bash script with no dependencies beyond coreutils, grep and awk", "as `bin/rmf-lint.sh` is for `rmf-sl`".
- Evidence: `templates/c/tools/bin/rmf-lint.sh:31-36` is a bash wrapper that runs `"$PY" - "$1" <<'PYLINT'` with `PY="${ROCQ_PYTHON_BIN:-python3}"`; the whole linter (lines 37-276) is Python 3 (`re`, section spans, `mentions_any`). `ebios-lint.sh` is built the same way, and 7 other `bin/*.sh` embed python3. The "dependency-free" phrase the spec echoes comes from `rmf-sl/references/report-format.md:16`, which refers to no external *packages*, not to the absence of Python.
- Consequence: F-C2 (read `fips_level` from JSON), F-C3 (slice F2 into AR subsections), F-C6 (transitive RQ←FM←VO reachability) and F-C5 (UTF-8 `§` tokens) are all awkward in grep/awk and trivial in the existing pattern.
- Fix: specify `bin/fips-lint.sh` as a bash wrapper around an embedded python3 script, same usage/exit codes and `ROCQ_PYTHON_BIN` override as `rmf-lint.sh`; drop the grep/awk sentence. Keep Rule 0 (one artifact per line) since the Python linter is still line-oriented.

### B2. `src:PDF§<n>` cannot name a section unambiguously (§4.4 rule 3, §5 F-C5)
- Evidence: the PDF has two numberings. Announcement items 1-14 (pp. iii-vi: "3. Explanation", "7. Applications", "10. Approved Security Functions", "13. Qualifications") and body sections 1-3 (pp. 1-3: "1. INTRODUCTION", "2. DOCUMENT BASIS", "3. APPLICABLE STANDARDS" with 3.1-3.4 and Table 1). `src:PDF§3` therefore means either the paragraph that lists the areas and levels or the one that lists the ISO standards. The spec's own §1 table has to write "Announcement §3" vs "§2, §3, Table 1" to tell them apart; the token grammar cannot.
- Fix: define the grammar as `src:PDF-abs`, `src:PDF-ann<1..14>`, `src:PDF-sec<1|2|3|3.1|3.2|3.3|3.4>`, `src:PDF-tab1` (ASCII only, so no `§` glyph in a grep token), and give F-C5 that fixed list. Also restrict which tokens may source an `RQ#` (see S11).

### B3. The driver ownership/skip mechanism does not match how `auto-wp.py` installs tools and the README (§6, §7.3)
- `bin/rmf-lint.sh` / `bin/fips-lint.sh` are *inside* one `tools/` entry. `install_tools` (`auto-wp.py:147-168`) iterates layer `tools/` entries and copies each whole (`shutil.copytree(..., ignore=shutil.ignore_patterns("*~"))`), printing one `copied foobar/bin` line. Skipping one file inside `bin/` needs a file-level ignore (e.g. extend `ignore_patterns` with the other driver's file names), and the spec's "ownership table" must say it works at three granularities: skill directory (`copy_skills`, `auto-wp.py:119-132`), command file (`copy_commands`, 134-145), and file-inside-a-tools-entry.
- `templates/common/tools/` is new. The code already iterates `tools/` on every layer, but `auto-wp.md` §3.2 ("Only `skills/` and `commands/` are copied from a layer"), §4 (tree shows `common/{skills,commands}/`) and §3.6 ("with `--rust` ... there is no `copied` line") become false; `--rust --driver fips` prints `copied foobar/NIST.FIPS.140-3.pdf`. The spec lists no `auto-wp.md` edits at all.
- README: `write_readme` (`auto-wp.py:182-192`) does two string replacements and `auto-wp.md` §3.4 says "changes nothing else". The spec adds one `{{DRIVER}}` line but also wants "`/fips` in place of `/rmf`" in Other commands. The C template mentions RMF in four more places that would be wrong for a fips project: `templates/c/README.md:96` (`grub-analysis-rmf-report.md`), `:130-133` (`/rmf ...`, "instead of the RMF one"), `:163-164` (`bin/rmf-lint.sh grub-analysis-rmf-report.md`, "machine gates of `rmf-sl`").
- Fix: (1) state the three skip granularities and the `ignore_patterns` mechanism; (2) list the `auto-wp.md` sections to update (§1, §3.2, §3.4, §3.6, §4 tree, §4.1, §4.2.1, §5) and the `tests.md` rows (T5, T7, C2.1); (3) either add placeholders `{{DRIVER_CMD}}` (`rmf`/`fips`), `{{REPORT}}` (`rmf-report`/`fips-report`), `{{LINT}}` (`rmf-lint.sh`/`fips-lint.sh`) and enumerate the five README lines, or keep one `{{DRIVER}}` block and move the four RMF-specific sentences into it.

### B4. Skipping `rmf-sl` and `bin/rmf-lint.sh` leaves dangling references in files that stay installed (§6)
- Evidence, all installed under `--driver fips`:
  - `templates/common/skills/ebios-sl/references/stride-families.md:70`, `report-format.md:137`, `crosswalk-format.md:37` link `../../rmf-sl/references/attack-mapping.md`;
  - `templates/c/skills/frama-c-launch/SKILL.md:179` and `:535` link `../rmf-sl/SKILL.md`;
  - `templates/c/skills/frama-c-monitoring/SKILL.md:864`, `frama-c-monitoring/templates/crosswalk-template.md:11`, `templates/c/tools/bin/ledger-ratchet.sh:4` name `bin/rmf-lint.sh`;
  - `templates/c/skills/time-loop/time-loop.sl.json:96,237,361,380` name `rmf-sl` / `bin/rmf-lint.sh` (§7.1 covers `SKILL.md` and the command but not this file).
- Fix, pick one: (a) install both skills, both commands and both linters always, and let `--driver` select only what `/time-loop`, the README and the manifest `driver` key drive — this reads the user's "uses fips-sl instead of rmf-sl" as "drives with", avoids every dangling link, keeps `attack-mapping.md` reachable from `ebios-sl`, and reduces §6 to the PDF copy; or (b) keep the skip, list the files above for rewrite or conditional wording, and add a template test that greps a `--driver fips` project for `rmf-sl` and `rmf-lint` and expects no hit outside `frama-c-launch/{templates,references}/rmf-*.md`. (a) is simpler and safer.

## Should fix

### S1. Human terminus misattributed (§4.3 table, §4.4 F5)
- Spec: "the module owner accepts the residual risk (PDF §13)".
- PDF Announcement 13: "The operator of a cryptographic module is responsible for ensuring that the security provided by a module is sufficient and acceptable to the owner of the information that is being protected and that any residual risk is acknowledged and accepted. The responsible authority in each agency shall ensure that the security of the system is sufficient and acceptable." The acceptor is the owner of the information / the agency's responsible authority, not the module owner.
- Fix: terminus = "the owner of the protected information (or the agency's responsible authority), PDF Announcement 13"; F5 sign-off `PENDING` until that party signs.

### S2. Quotes attributed to the PDF are not verbatim (§1 table, §4.4 rule 3)
- "uses only Approved security functions" (§10) is in quotation marks; the PDF says "shall employ Approved security functions such as cryptographic algorithms, cryptographic key management techniques, and authentication techniques" (Announcement 10). No "only". The §4.5 `approved-only` class is a defensible reading, but the report-format rule must not present it as PDF text.
- "Level 1, 2, 3, 4 | Abstract; Announcement §3": the Abstract says "four increasing, qualitative levels of security" without naming them; only Announcement 3 ("Level 1, Level 2, Level 3, and Level 4") and body §1 do.
- The word "eleven" occurs once, in body §1, about FIPS 140-1 ("Four security levels were specified for each of eleven requirement areas"); the Abstract and Announcement 3 enumerate eleven areas with "These areas include". Count is right; cite §1 for the number.
- Fix: paraphrase, or quote verbatim; cite Announcement 3 and body §1 for the levels and the count.

### S3. "ISO/IEC 19790 §7" is not in the PDF (§1)
- The PDF never gives a clause number inside 19790. The claim is true of the real standard but unverifiable from the corpus the skill is restricted to. Fix: mark it as external knowledge, or drop "§7".

### S4. Tag collisions with crypto vocabulary (§4.4 rule 1)
- `MD#` matches `MD5`/`MD4`/`MD2`, which a FIPS report will write ("MD5 is not an Approved function"); with `rmf-lint`'s regex style (`\bMD[0-9]+\b`, cf. `rmf-lint.sh:55`) every such mention becomes a phantom module id. `SP#` collides with `SP800-140C`-style spellings of the SP series the PDF itself cites.
- Fix: `MOD#` and `SSP#`.

### S5. `level N` line not pinned (§4.4 F1, §5 F-C2)
- "level" appears in "security level", "min-level 3", "Level 1-4 (PDF)". "Exactly one `level N` line in F1" is not decidable without a grammar, and `min-level K` contains `level K`.
- Fix: one line in F1 matching `^level: [1-4]$` (or a token `LEVEL=3`), F-C2 counts only that pattern.

### S6. Chaining and reachability under-defined (§4.4 rule 2, §5 F-C6)
- `VO#` names `FM#`, `FM#` names `RQ#`, so "every `RQ#` is reached by a `VO#` or `RR#`" is transitive. `rmf-lint.sh` has no transitive check: `mentions_any` (lines 91-96) is line-local. Rule 2 also never says what an `RR#` line names (F4 says an `FM#` becomes an `RR#`; F5 says one `RR#` per requirement).
- Fix: either (Rule 0 style) require every `VO#` and `RR#` line to carry its `FM#` and its `RQ#`, so F-C6 stays line-local, or specify that the linter computes the closure RQ→FM→VO/RR. State that every `RR#` names ≥1 `FM#` or `RQ#`.

### S7. F-C3, F-C8 need tokens (§5)
- F-C3: the spec attributes an `RQ#` to an area both by subsection ("one subsection per area, `AR1` to `AR11`") and by token ("every `RQ#` names its `AR#`"). Pick one for the linter (recommend: the `AR#` token on the RQ line; the heading is for humans) and define the `N/A` form (a line in F2 containing `ARn` and `N/A` followed by non-empty text).
- F-C8 "standing residuals present in F5": define the tokens the linter greps, e.g. plane names `crypto`, `ENV`, `physical`, `side-channel`, `supply-chain` and the word `CMVP`, each on an `RR#` line. Today `rmf-lint` does not check Rule 6 residuals at all (`report-format.md:59` "future"), so this is a new check, not an inherited one.

### S8. The linter's manifest dependency breaks the fixture test (§3, §5, §8)
- `fips-lint.sh` "reads `config/auto-wp.json` from the project root" and "takes no level argument". `test_templates.py` runs on the host, in the repo, where there is no manifest; the "skeleton must pass" pilot cannot run as specified. `rmf-lint.sh` takes only `REPORT.md`.
- Fix: the test creates a temp dir with `config/auto-wp.json` and runs the linter from there; or allow `FIPS_LEVEL=N` as an override for tests only (documented as such). Also say what the linter does when the manifest is absent or has no `fips_level` (exit 2 with a message).

### S9. Tests the change breaks but the spec does not list (§3, §8)
- `tests/test_auto_wp.py:620-626` `test_rust_output_counts` asserts `lines[1]` is the `skills:` line; inserting `driver:` at index 1 breaks it. Spec names only `test_c_output_exact`.
- `tests/test_auto_wp.py:426` `test_13b` asserts 21 `bin/*.sh` in the *project*; this stays 21 for both drivers under the skip design (one linter in, one out), but the spec says "T7 counts 22" without saying the project count stays 21. Under the no-skip design (B4 option a) both become 22.
- `test_T6_time_loop_command` (`tests/test_templates.py:173-190`) matches the exact Stop bullet of `commands/time-loop.md`; the driver-table rewrite of §7.1 must preserve it. Not mentioned.
- `test_11_manifest` needs the new keys; `tests.md` T5/T7/C2.1 rows; `tests/c/install-test.sh` second run.
- Fix: list them.

### S10. "Installs exactly what auto-wp.py installs today" contradicts §3 (§2)
- `--driver rmf` adds `"driver": "rmf"` to the manifest and a `driver:   rmf` output line, so the default run's output and manifest change. Fix: "installs the same files as today; the manifest and the output gain the driver line (§3)".

### S11. F-C5 checks existence only; the dominant coherent-and-wrong is uncaught (§4.3, §5)
- The spec names "requirements invented: stated as if sourced" as the dominant failure, but F-C5 only checks that the cited section exists. `src:PDF-ann1` ("Name of Standard") would pass.
- Fix: whitelist the sections that carry normative or scoping text for `RQ#` lines: Announcement 6 (applicability), 7 (level choice, "specific to that level and ... all modules"), 10 (Approved security functions), 13 (conformance not sufficient, residual risk); anything else on an `RQ#` line FAILs. State explicitly that the content match stays with the reviewer.

### S12. More property classes are system-level than the warning says (§4.5)
- The warning covers `role-gate`, `fsm`, `output-inhibit`. `integrity-first` ("before any service"), `selftest-order` ("before first use") and `error-state` ("stays there") are also whole-module ordering/temporal properties; per-function `requires`/`ensures` cannot express them without ghost state, and the ghost-fiat trap of `rmf-sl` applies.
- `approved-only` is a call-graph property: checkable by a Frama-C script over the callgraph, not a WP proof. `zeroize`: the proof is on source; dead-store elimination by the compiler is a standing residual (plane `supply-chain`), worth one line.
- Fix: extend the warning list; annotate `approved-only` as "call-graph check" and add the compiler note to `zeroize`.

### S13. §8e is EBIOS-only today, and RMF has no branch there either (§7.1)
- `frama-c-monitoring/SKILL.md:803` "8e. EBIOS W5 risk-feedback" only; `rmf` is not mentioned in the skill. The RMF Monitor packet is specified in `templates/c/commands/rmf.md:139-149` and `frama-c-launch/references/rmf-feedback.md`, not in frama-c-monitoring.
- Fix: follow the RMF pattern (command text + `fips-feedback.md`), or add both an RMF and a FIPS branch to §8e; do not add FIPS alone.

### S14. Linter pilot and canary cases should name the F-checks they exercise (§5)
- "drop an area, change the level, put a file name in F2" hits F-C3, F-C2, F-C9. Add a broken copy per FAIL check (F-C1, F-C4, F-C5, F-C6, F-C7, F-C8), as `rmf-sl` §5 asks ("drop a chaining link").

## Minor

### M1. Gate S is not in `rmf-sl` §3 (§4.2)
- `rmf-sl/SKILL.md:113-126` §3 defines Gates A, B, C. Gate S is §4 step 7 and §6. Cite those.

### M2. `/fips` "same arguments and flags as `/rmf`" (§7.1)
- `/rmf`'s `--linux`/`--full-tu` call `linux/linux-acsl/onboard-linux.sh` and `linux-analysis.md` (`commands/rmf.md:32-51`), which are not in the templates. Pre-existing, but do not copy those flags into `/fips` without saying they are inherited as is.

### M3. `--level` ordering (§2)
- The user wrote "a subsequent option". argparse is order-independent, so `--level 3 --driver fips` is accepted. Say so, and that the check "`--level` without `--driver fips`" is done after parsing with `parser.error()` (exit 2, nothing created), since argparse cannot express the dependency.

### M4. `fips-sl.sl.json` test (§8)
- "Valid JSON with the `rmf-sl.sl.json` schema" has no oracle. `templates/common/skills/sl-internal/scripts/sl_disjointness_check.py <loop.sl.json>` exists (exit 0/1/2) and checks referential integrity, authorship and the barrier. Use it, and also run it in two-file mode against `time-loop.sl.json` once that file carries the driver table.

### M5. README quick start under `--driver fips` (§7.3, open point 2)
- The quick start still ends with `/time-loop grub 72`; GRUB is not a cryptographic module (the spec says so in open point 2). Say the quick start is unchanged under fips and why, or point at `--dir=grub-core/lib/libgcrypt` as the module boundary.

### M6. `crosswalk-format.md` wording (§4.1)
- In `rmf-sl`, `references/crosswalk-format.md` is the schema and `frama-c-launch/templates/rmf-crosswalk.md` is the filled template; "the join table consumed by frama-c-launch" blurs the two. Mirror the existing split in words.

### M7. Open points
- Good set; 1, 2 and 5 are the ones that change the design. Open point 5 should also mention that `rmf-sl.sl.json` (`sources[0].notes`) and `rmf-sl/SKILL.md:27,36-38` cite a `nist/` corpus that no template ships, which the spec's PDF vendoring would make the asymmetric exception. Open point 7 could note that, in the real standard, the overall level is the minimum over areas; the PDF does not say it, so the single-level design is the only PDF-sourced one.

## Verified as correct

- PDF: FIPS PUB 140-3, March 22, 2019, 11 pages, sha256 `942a4f92…db384b`. The eleven areas, in the spec's order, are listed in the Abstract and Announcement 3. Announcement 7 says the level "must be chosen to provide a level of security appropriate for the security requirements of the application and environment" and that a level's requirements are "both the security requirements specific to that level and the security requirements that apply to all modules regardless of the level". Announcement 10 requires Approved security functions (a-d, including SP 800-140C/D). Announcement 13 says conformance is not sufficient and residual risk must be acknowledged and accepted. CMVP and CST laboratories: Announcement 3, 9, 12. Body §2-§3 and Table 1: ISO/IEC 19790:2012 and 24759:2017, modified by SP 800-140 and 800-140A-F. The PDF contains no per-area or per-level requirement; the only module-directed "shall" is Announcement 10 (plus the applicability "shall be used" of Announcement 6).
- `auto-wp.py`: argparse with a mutually exclusive `--c`/`--rust` group and one positional (`36-50`); layers `[common, language]` (`60`); `copy_skills` replaces a skill directory whole (`119-132`); `install_tools` copies every layer's `tools/` entries to the project root and keeps existing ones (`147-168`); manifest keys `language`, `auto_wp_version`, `created`, `skills`, `commands` (`105-112`); output lines `created ... / skills / commands` (`113-117`); `LINKS` and `RESERVED` constants (`23-29`); usage errors exit 2 via argparse, run-time errors exit 1 with rollback (`242-256`). The spec's exit-code rules are consistent with these and with `auto-wp.md` §3.6 and §5 test 4.
- `templates/c/tools/bin/`: 21 `*.sh`, including `rmf-lint.sh` and `ebios-lint.sh`; `rmf-lint.sh` exits 0/1/2 and its C8 regex is `\w+\.(c|h|cpp|cc|rs)`, `#include`, `#define`, `0x…`, `::`, `->` over R1-R4 (`168-177`).
- `rmf-sl`: §2 actor table with disjoint `(U, L)` pairs; §4b contaminated-context rule; §5 pilot on a known-good report and a broken copy; §8 return half; `report-format.md` Rules 0, 5 and 6; `references/{stride-families,attack-mapping,crosswalk-format,report-format}.md` exist; `rmf.md` names `PREFIX-rmf-report.md`, `PREFIX-rmf-gaps.md`, `PREFIX-monitor-feedback-NN.md` (`13-14`).
- `frama-c-launch`: `templates/{ebios,rmf}-crosswalk.md` and `references/{ebios,rmf}-feedback.md` exist; `SKILL.md:534` is the "NIST RMF alternative" bullet and `:177-182` the in-line alternative.
- `time-loop`: `SKILL.md` and `commands/time-loop.md` drive `/rmf XXX XXX-analysis` by name and name `XXX-analysis-rmf-report.md`, `-rmf-gaps.md`, `bin/rmf-lint.sh` (`SKILL.md:292`).
- Rust layer: `templates/rust/commands/` empty, no `tools/`, no mention of `rmf`; `creusot-launch` absent and marked pending in both test files; `--rust` installs 16 skills per spec (15 while `creusot-launch` is pending).
- Tests: T5 asserts exactly `{"DIR","LANGUAGE"}` (`test_templates.py:167`); T7 asserts 21 scripts (`:222`); `test_c_output_exact` compares the full stdout (`test_auto_wp.py:602-618`); test 4 checks exit 2 and nothing created; test 19 is the rollback test; `tests.md` C2.1 expects `skills:   21` and `commands: 3`.
- Skill counts: 21 for C (12 common + 9), unchanged by a one-for-one swap; `ebios-sl` and `/ebios` exist and are untouched by the driver.
- Faithfulness to the request: all five asks are covered. Additions beyond the request (vendoring the PDF, `--level` required with `fips` and refused with `rmf`, the `{{DRIVER}}` README line, the `time-loop` driver table) are justified in the text and are the minimum to make the fips project stand-alone and runnable.
