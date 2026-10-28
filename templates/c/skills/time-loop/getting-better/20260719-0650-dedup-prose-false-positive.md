# Dedup false-positive from function names written verbatim in a row's DESCRIPTION prose

**Observed (cycle-198, 2026-07-19).** The cycle-197 `role_index` verdicts.tsv row ended its
description with a NOTE naming future targets verbatim:
`"analogous un-proven index_f[] leaves class_index/user_index/type_index need ..."`.

The sub-agent novelty check is `grep -icE '\bFN\b' verdicts.tsv` over the WHOLE line (col1 + status
+ description). So `grep -icE '\bclass_index\b'` returned **1** — matching the prose in role_index's
row — even though `class_index` has **0 col1-STATUS rows** (it is genuinely un-proven). Result: three
legitimately-pickable sibling targets were falsely flagged "already proven" and would be skipped.

**Why the Gate-R report was still correct.** `gen-interim-report.py` dedups by `(area, fn)` keyed on
the **STATUS column** (`WITNESSED`/`NN/NN`), never on description prose, so the report's counts were
unaffected. The poison only hit the *verifier sub-agent's* line-wide grep.

**Fix applied.** Reworded the role_index NOTE to not contain sibling function names as verbatim
tokens ("class/user/type/... value-indexed callbacks" instead of "class_index/user_index/type_index").

**Rules going forward:**
1. **A verdicts.tsv row description MUST NOT contain another function's exact name as a bare token**
   when that function is a future/un-proven target — it silently poisons `grep -icE '\bFN\b'` dedup.
   If you must reference siblings, avoid the exact `<name>` token (e.g. write "class/user/type
   index_f callbacks", not "class_index/user_index/type_index").
2. **The authoritative dedup is col1-STATUS, not prose.** To check whether FN is truly proven:
   `grep -E "^[^\t]*\bFN\b" verdicts.tsv | grep -cE '\t(WITNESSED|[0-9]+/[0-9]+)\t'` — count of
   FN appearing in **col1 of a WITNESSED/NN-NN row**, not anywhere on any line. A plain
   `grep -icE '\bFN\b' verdicts.tsv` over-counts by matching description prose.
3. Sub-agent prompts that say "grep -icE '\bFN\b' verdicts.tsv" as the novelty check should add:
   "if the only matches are inside ANOTHER row's description prose (not col1), it is NOT proven —
   verify with the col1-STATUS grep above."

Related: [[20260718-0740-report-ledger-drift-anti-drift-gate]] (Gate-R keys WITNESSED strictly on the
STATUS column, never description prose — same principle, one layer up).
