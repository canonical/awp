# Review of `fips-skill-spec.md`, revision 4

**Verdict.** Not ready as written, for two small reasons; otherwise close. Every finding of report 2 is resolved, and option B is applied consistently in §2, §3, §6, §7.1, §7.3, §8 and the counts; the only option-B leftovers are a stale column label in the open-point-8 table and two stale phrases in §10. Two internal contradictions in the linter rules are blocking because the known-good fixture of §5 cannot pass as specified: F-C0 fails every `AR#` that has requirements (an `AR#` has a home line only when `N/A`, so elsewhere it is "only referenced"), and rule 4 / F-C6 require every `RR#` line to name an `FM#` or `RQ#`, which the standing `physical` residual of a software-only module (the §4.5 AR6 case, and the §7.3 libgcrypt target) cannot do. Both are one-line fixes. The §6 list of installed files that name `/rmf` misses `frama-c-launch/SKILL.md:76-77,472` and miscounts `time-loop.sl.json`. Every PDF claim, every `auto-wp.py`, `time-loop`, `ledger-ratchet.sh`, schema and test citation I re-checked is correct.

## 1. Report 2's findings

| Finding | Status | Reason |
|---|---|---|
| B3 (partial) README line 98 | resolved | §7.3 line 98 → `grub-analysis-{{FEEDBACK}}-NN.md`; §8 T5 set `{DIR, LANGUAGE, DRIVER, FEEDBACK, DRIVER_LINE}`. |
| S2 (partial) Sec. 1 and the level names | resolved | §1 row 1: Ann. 3 "the only place that names them", Sec. 1 for the count, Abstract for "four increasing, qualitative levels". All three verified in the text. |
| S-1 position of the PDF `copied` line | resolved | §3: sorted name order (`auto-wp.py:156`), between `.gitignore` and `bin` for `--c`, only line for `--rust`; §8 `test_c_output_exact`, `test_13c`. |
| S-2 README line 98 | resolved | Same as B3. |
| S-3 "the `RQ#` line" undefined | resolved | §4.4 rule 0 defines the home line; F-C0 requires exactly one per id; F-C3–F-C7 say "home line". It introduces the `AR#` contradiction (new B-1 below). |
| S-4 time-loop table incomplete | resolved | §7.1 table has ranked item + scale, Plane W, Plane H, outside-both-planes rows; `SKILL.md:973` named. |
| S-5 STRIDE ledger | resolved | §7.1 FIPS ledger per `VO#`, `# ledger: fips` marker, `VO#<TAB>cell` baseline, unchanged rule; §6 files; §8 T9b; §9 point 4. |
| S-6 open point 8 one-sided | resolved | §9 point 8 has A, B, C with both sides; decided B. |
| M-1 level names | resolved | §1 row 1. |
| M-2 AR6 vs F-C8 | resolved | §4.5 AR6 row: `N/A` in F2 and still the `physical` residual in F5. |
| M-3 AR8 residual column | resolved | §4.5 AR8 row: `supply-chain`. |
| M-4 `monitors` is a string | resolved | §7.1: stays `"rmf-sl"`, one sentence in `description`; §8 T8 says why two-file mode is not used (`sl_disjointness_check.py:237-239`, verified). |
| M-5 fixture | resolved | §4.1 `references/skeleton.md`; §5 broken copies are string edits by the test; §8 T9 docstring change. |
| M-6 flag aliases | resolved | §7.1 lists `--fresh`/`--force`, `--monitor-only`/`--quick` (matches `rmf.md:18-20`). |
| M-7 level line form | resolved | Rule 6: bare paragraph line, `- level: 3` does not match, skeleton shows it. |
| M-8 libgcrypt path | resolved | §7.3: "not verified here … the first level 3 run confirms it". |

## 2. Option B consistency

Checked against the files; all of the following hold:

- **Counts.** Template: 12 common + 9 C skills today, 21 `bin/*.sh`, 3 C command files, 7 Rust skill dirs of which 4 override common ones (`ls`). Spec: C project 22 skills / 3 commands / 22 scripts, template 4 command files, Rust 16 (17 with `creusot-launch`); all follow. §3 output example (`skills: 22`, `commands: 3`), §6 "New counts", §8 (`test_13b` 22, T3 13 + 4, T7 22, C2.1 `skills: 22` / `commands: 3`) and the §9 B column (22 skills, 3 commands) agree.
- **Manifest.** `copy_commands` returns sorted stems (`auto-wp.py:145`), so `ebios, fips, time-loop` / `ebios, rmf, time-loop` is right. `test_11_manifest` compares the list with the installed directory (`tests/test_auto_wp.py:387-390`), so it needs no option-B special case; the spec's "the `commands` list per driver" is enough.
- **Filter.** `copy_commands` is per file (`auto-wp.py:134-145`); a `DRIVER_COMMANDS` constant next to `LINKS`/`RESERVED` (`:23-29`) is the right place. `copy_skills` and `install_tools` indeed need no change.
- **README.** Quoted "today" text matches `templates/c/README.md` lines 3-4, 96, 98, 130-131, 132-133, 163, 164 exactly. Line 130 → `/{{DRIVER}}` is consistent with B (one campaign command advertised). Line 164 keeps both linters: consistent, since both are installed.
- **`/fips` behaviour.** §7.1 "installed only with `--driver fips`, so the manifest always has `fips_level`" and the hand-edited-manifest stop are consistent with §2/§3/§6.
- **Tests.** Names and current assertions verified: `test_c_output_exact` (`:602-618`, `.gitignore` then `bin`), `test_rust_output_counts` (`:624-626`, `lines[1]` is `skills:`), `test_rust_output_spec_count_16` (`:628-633`), `test_11_manifest`, `test_13b` (`:426`, 21), `test_13c` (`:432-434`, no `bin/`), `test_13`/`test_14` (`NotIn("{{")`), `test_19_rollback`; `test_T3_common_layer`/`test_T3_c_layer` (12, 9, `C_COMMANDS` of 3), `test_T5_readme_placeholders` (`:167`, exactly `{DIR, LANGUAGE}`), `test_T6_*` (Stop bullet and description phrases, `:173-207`), `test_T7_scripts_in_bin` (`:222`, 21; `bin/` prefix rule), docstring "They only read templates/" (`:4`); `tests/c/install-test.sh:35-38` greps `skills:   21` and `commands: 3`. The §8 list covers each.
- **Mentions of the absent command.** The complete set of `/rmf` command mentions under `templates/` outside `rmf-sl/` and `commands/rmf.md` (grep `/rmf(?![-\w])`, which excludes `bin/rmf-lint.sh`) is: `README.md:130`; `commands/time-loop.md` (14 occurrences on 13 lines); `time-loop/SKILL.md` (16 occurrences on 15 lines, `:4,39,46,56,286,419×2,504,523,622,841,885,921,970,974`); `time-loop.sl.json:9` (1); `frama-c-monitoring/references/crosswalk-generation.md:60`; `sl-monitoring-sl/SKILL.md:137,153`; `frama-c-launch/SKILL.md:76,77,472`. Inside `rmf-sl/`, the only one is `SKILL.md:147`, as the spec says. The spec's table misses `frama-c-launch/SKILL.md` and miscounts `time-loop.sl.json` (S-1, M-1 below).
- **Open point 8 table.** The B column is correct in every row. The A column header still reads "(this draft)" (S-3 below).

## 3. New findings

### Blocking

**B-1. F-C0 fails every area that has requirements (§4.4 rule 0, §5 F-C0, F-C3).**
- Rule 0 gives `AR` a home line only as "the `AR` of an `N/A` line"; on an `RQ#` line the first tag is `RQ#`, so `AR1` with three requirements has no home line. F-C0 says "every id has exactly one home line; a tag defined twice, or only referenced, fails". Read literally, the skeleton fails F-C0 for every `AR#` that is not `N/A`, and the canary "AR6 line removed" trips F-C0 as well as F-C3 if `AR6` is mentioned anywhere else (the F5 `physical` residual will mention it).
- Fix: in F-C0 and rule 0, scope the home-line requirement to `MOD SV RL SSP IF ST RQ FM VO RR`; say `AR1`–`AR11` are a fixed vocabulary with no home line, checked by F-C3 only.

**B-2. Standing residuals cannot satisfy rule 4 / F-C6 (§4.4 rule 4, §4.5 "Standing residuals", §5 F-C6, F-C8).**
- Rule 4: "Every `RR#` line names at least one `FM#` or `RQ#`". §4.5: the six standing residuals are `RR#` lines present "even if no requirement surfaced them"; the AR6 row says a software-only module marks AR6 `N/A` (so it has no `RQ#`) and still writes the `physical` residual. That line has nothing to name and fails F-C6 while F-C8 requires it. The §7.3 target (libgcrypt) is software-only, so the first real report hits this. The F-C8 canary ("the `side-channel` residual removed") also risks tripping F-C6's coverage clause if the skeleton's `RR#` line is the only line naming some `RQ#`.
- Fix: let a standing residual name its area instead: F-C6 accepts `FM#`, `RQ#` or `AR#` on an `RR#` line (`physical` → `AR6`, `ENV` → `AR5`, `side-channel` → `AR7`, `crypto`/`supply-chain`/`validation` → a token `standing`). Say the skeleton's standing residuals name no `RQ#` that is not also covered by a `VO#`, so the F-C8 canary trips F-C8 alone.

### Should fix

**S-1. §6 "Mentions of the absent command" misses `frama-c-launch/SKILL.md` (§6 table, §6 "New and changed files", §7.1).**
- `templates/c/skills/frama-c-launch/SKILL.md:76` "(`--machdep=<name>` via `/rmf`)", `:77` "When `/rmf` forwards `--machdep=<name>`", `:472` "forwarded by `/rmf`/`/ebios`, or given directly". In a `fips` project these name a command that does not exist, and `/fips` forwards the same flags (§7.1).
- Fix: add a row: `:76-77` → "via `/rmf` or `/fips`"; `:472` → "`/rmf`, `/fips` or `/ebios`". Add `frama-c-launch/SKILL.md` to the "New and changed files" table (it is already changed by §7.1 for the third-driver text at `:177-182,534`).

**S-2. "New and changed files" and "`frama-c-monitoring` is otherwise unchanged" miss three edits the spec itself asks for (§6 table "New and changed files", §7.1).**
- §6 edits `frama-c-monitoring/references/crosswalk-generation.md:60` and `sl-monitoring-sl/SKILL.md:137,153`, and §7.1 teaches `ledger-ratchet.sh` a second row form, but `frama-c-monitoring/SKILL.md:858-865` documents that script as "parses the six S,T,R,I,D,E columns" and `ledger-ratchet.sh:13` names `crosswalk-template.md §3` as the authoritative format contract. None of the three appear in the file table, and §7.1 says `frama-c-monitoring` is "otherwise unchanged".
- Fix: add `frama-c-monitoring/references/crosswalk-generation.md`, `frama-c-monitoring/SKILL.md` (one sentence at `:858-865`: "or the FIPS ledger of `frama-c-launch/templates/fips-crosswalk.md` §3") and `sl-monitoring-sl/SKILL.md` to the table (layers c, c, common), and reword §7.1 to "unchanged apart from these mentions".

**S-3. Open point 8 still labels A "(this draft)" (§9 point 8).**
- Header row: "A. both always (this draft)". Revision 4 chose B. Also §10 rows "B3 … §6 (no skip)" and "B4 … §6: both drivers installed" describe revision 2/3: B does skip the other driver's command, and both *skills* (not drivers) are installed.
- Fix: "A. both always" / "B. the other driver's command left out (chosen)"; §10: "§6 (command filter only)" and "§6: both skills and both linters installed".

**S-4. `ledger-ratchet.sh`'s baseline parser and WS1 rule are not addressed for the FIPS form (§7.1, §8 T9b).**
- `from_tsv` drops any row with fewer than 7 tab-separated fields (`ledger-ratchet.sh:178-181`), so a `VO#<TAB>cell` baseline reads back empty and the ratchet would PASS on every regression; the baseline file needs its own form (and a marker, since the `# ledger: fips` marker is in the crosswalk, not in the TSV). The WS1 stage-1 rule (`:186-207`) fires on any row label matching `race|concurren|ws1` and would apply to a `VO#` row labelled, say, "VO4 concurrency"; the spec does not say whether it applies to the FIPS form.
- Fix: say the FIPS baseline is written with a `# ledger: fips` first line and parsed as two columns, and that the WS1 stage-1 rule is either not applied to the FIPS form or keyed to the property class. Add to T9b: a regression is detected after a round trip through the baseline file.

### Minor

**M-1. Mention counts (§6 table).** `time-loop.sl.json` has 1 `/rmf` command mention (`:9`), not 3; the `:96,237` hits are `bin/rmf-lint.sh`. `commands/time-loop.md` has 14 occurrences on 13 lines, `time-loop/SKILL.md` 16 on 15 lines; the spec counts the first by lines and the second by occurrences. The "Pairs with" `/rmf` is on `SKILL.md:974` (`:973` names `config/commands/rmf.md`). Write occurrence counts: 16, 14, 1, and "lines 973-974".

**M-2. `--driver fips` on Rust installs no `/fips` (§2, §3).** `templates/rust/commands/` is empty and `commands/fips.md` is a C-layer file, so under `--rust` the manifest's `commands` is `[]` for both drivers and `test_rust_output_counts` keeps `commands: 0`. §2 "installs `/fips` instead of `/rmf`" and §3's `commands` lists are C-only; say so (§7.2 implies it).

**M-3. F-C5 on an `RQ#` line with no `src:` token (§5).** The F-C4 canary ("an `RQ#` with no `src:` token") must trip F-C4 alone; F-C5 "the `src:` token of every `RQ#` home line is one of …" is silent when there is none. Say F-C5 skips lines with no token.

**M-4. Two rules named 0 (§4.4).** The preamble says `rmf-sl`'s rules 0 (locality) and 5 apply "as they are", then the list starts with the FIPS rule 0 (home lines). Number the home-line rule 0a or 8, or fold the locality sentence into it.

**M-5. T6 listed in both "unchanged" and "to update" (§8).** §8 says "T6: unchanged" and then lists T6 among the `tests.md` §3.2 rows to update. Drop T6 from the `tests.md` list, or say the row only gains "and still passes after the driver-table rewrite".

**M-6. F-C6 checks presence, not consistency (§4.4 rule 4).** Rule 4 says a `VO#` line names "the `RQ#` of each" `FM#` it names; F-C6 is line-local and can only check that some `RQ#` is present, not that it is the right one. Say the match between the `VO#` line's `RQ#` and its `FM#` lines' `RQ#` is the reviewer's, or add it to F-C6 as a cross-line check (it is cheap: both are home lines).

## 4. Verified as correct

- **PDF** (`pdftotext -layout`, 427 lines; sha256 `942a4f92…db384b`; 11 pages; March 22, 2019). Announcement 1-14 on pages iii-vi, body 1-3 with 3.1-3.4 and Table 1 on pages 1-3. Verbatim: Ann. 3 "Level 1, Level 2, Level 3, and Level 4" (the only place); Abstract "four increasing, qualitative levels of security"; Sec. 1 "Four security levels were specified for each of eleven requirement areas" (about FIPS 140-1); the eleven areas after "These areas include" in the Abstract and Ann. 3, in the spec's order; Ann. 7 "must be chosen …" and "both the security requirements specific to that level and the security requirements that apply to all modules regardless of the level"; Ann. 10 "shall employ Approved security functions such as cryptographic algorithms, cryptographic key management techniques, and authentication techniques"; Ann. 13 "is not sufficient to ensure that a particular module is secure", "sufficient and acceptable to the owner of the information that is being protected and that any residual risk is acknowledged and accepted", "The responsible authority in each agency"; CMVP/CST in Ann. 3, 9, 12; ISO/IEC 19790:2012, 24759:2017, SP 800-140 and 800-140A-F in Sec. 2, Sec. 3, Table 1. The only module-directed "shall" is Ann. 6 and Ann. 10; no per-area or per-level requirement; no 19790 clause number. Rule 3's full token set names existing parts only.
- **`auto-wp.py`.** `copy_commands` `:134-145` per file, sorted stems; `install_tools` `:147-168`, `sorted(chosen)` at `:156`; `LINKS`/`RESERVED` `:23-29`; `write_readme` `:182-192` replaces `{{DIR}}` and `{{LANGUAGE}}` only; argparse `:36-50`.
- **`time-loop`.** `SKILL.md:142` (WITNESSED-RS# counts), `:154` (Tier-3 RS#), `:294` (Monitor packets keyed to RS#), `:321` (Gate C RS#), `:537` (`monitor-feedback-NN.md` keyed to RS#), `:973` (`config/commands/rmf.md`); Plane W = Tier-1 untrusted-input, Plane H = Tier-3 authorization/integrity (`:72,74`). `time-loop.sl.json:8` `"monitors": "rmf-sl"`; `sl-schema-1.0.json:49-52` types it `string|null`; `sl_disjointness_check.py:237-239` emits INFO when `monitors` does not name the base; single-file mode on `rmf-sl.sl.json` exits 0 (16 checks).
- **Ledger.** `crosswalk-template.md:42` §3 heading, `:47-73` lifecycle and ratchet rule, `:75-79` matrix; `frama-c-monitoring/SKILL.md:464,857-858,864`; `ledger-ratchet.sh:102-106` SKIP, `:161-163` bad-cell FAIL, `:209-217` WARN on `UNMODELED`/`TRUSTED-PENDING`, `:231-248` the two regressions; `rmf-lint.sh` C9 (`:179-252`) is single-file structural only.
- **Dangling-reference list (§6).** All eleven file:line citations hold (`stride-families.md:70`, `report-format.md:137`, `crosswalk-format.md:37`, `frama-c-launch/SKILL.md:179,535`, `frama-c-monitoring/SKILL.md:864`, `crosswalk-template.md:11`, `ledger-ratchet.sh:4`, `time-loop.sl.json:96,237,361,380`). `rmf-sl/SKILL.md:27,36-38` cite `nist/`; no `nist/` under `templates/`.
- **Other citations.** `rmf.md:18-20` flags and aliases; `rmf-lint.sh:30-34` wrapper, `:56-58` `lines_with`, `:170` C8 regex; `rmf-sl/SKILL.md:147` is the only `/rmf` command mention in `rmf-sl/`; `frama-c-launch/SKILL.md:177-182,534-538`; `frama-c-monitoring/SKILL.md:803` §8e is EBIOS-only; `auto-wp.md:10-14` usage, `:99` "Only `skills/` and `commands/`", `:148-149` "two placeholders", `:352` "no `copied` line", `:383` tree, `:916` 21 scripts; `tests.md:113-117` T3/T5/T6/T7, `:251` C2.1, `:356` R2.1.
- **Internal consistency otherwise.** F-C8's six planes equal the standing residuals; rule 7 adds `logic` as a non-standing plane; the nine property classes split 1 (`approved-only`, outside both planes) + 2 (Plane W) + 6 (Plane H) and match the §4.5 table and the §7.1 driver table; ten FAIL checks F-C0–F-C9, ten canaries; `MOD`/`SSP` avoid `MD5`/`SP800`; `^level: [1-4]$` excludes `min-level K` and `- level: 3`; `.gitignore` < `NIST.FIPS.140-3.pdf` < `bin` in byte order; §10 maps every finding of both earlier reports.
