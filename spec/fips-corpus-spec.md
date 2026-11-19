# The FIPS 140-3 corpus — `specs/` (0.9.0)

This document specifies the corpus `fips-sl` cites under `--driver fips`.
It replaces the single vendored `NIST.FIPS.140-3.pdf` of 0.4.0 to 0.8.0
([`fips-skill-spec.md`](fips-skill-spec.md) §1, §4.4 rule F3, open point
9.1). How well the framework digests the corpus, with measurements, is in
[`fips-corpus-evaluation.md`](fips-corpus-evaluation.md).

## 1. Why

FIPS 140-3 is 11 pages. It names the four levels and the eleven areas but
holds none of the per-area, per-level requirements. Those are in ISO/IEC
19790 §7, with their test assertions in ISO/IEC 24759, as modified by
SP 800-140 and 140A–F, interpreted by the Implementation Guidance (IG), and
constrained by SP 800-131A and the algorithm standards. With the PDF alone,
nearly every `RQ#` was `src:UNSOURCED`. A study of a real module (gnutls,
leancrypto) needs the whole chain.

## 2. Layout

```
specs/
├── MANIFEST.tsv     committed: one row per citable document
├── README.md        committed: usage, licences
├── import-specs.py  committed: populate pdf/, text/, checklist/
├── .gitignore       committed: *.pdf, /pdf/, /text/, /checklist/
├── pdf/<ID>.pdf     local
├── text/<ID>.txt    local: pdftotext -enc UTF-8 (no -layout)
└── checklist/       local, optional: data/*.jsonl, one {"id": …} per item
```

**No document is in git.** NIST publications are public, but they total
50 MB and churn (§6), and ISO/IEC 19790/24759 are licensed per licensee.
The manifest pins each edition by sha256, so two checkouts that imported
the same files cite the same text.

### 2.1 `MANIFEST.tsv`

`#` lines are comments; the first other line is the header:

| Column | Values |
|---|---|
| `id` | the `DOC` of `src:DOC:LOC`: `[A-Za-z0-9.-]+`, e.g. `FIPS140-3`, `ISO19790`, `SP800-140C`, `IG` |
| `kind` | `core` (FIPS 140-3, ISO/IEC 19790/24759, SP 800-140 and 140A–F), `guidance` (IG, CMVP-MM, the SP 800-140B "Use of" documents), `transition` (SP 800-131A, its draft successor, NIST IR 8547), `algorithm` |
| `status` | `final` or `draft` (a draft is not binding: F-C13) |
| `license` | `public` or `restricted` |
| `pages` | page count of the pinned edition |
| `sha256` | of the pinned PDF |
| `source_name` | the file name as published |
| `title` | the document title and edition |

There are 53 rows. One edition per document: the IG and the CMVP
Management Manual are pinned to their latest edition, and superseded
editions are not listed. To move to a new edition, change the row in the
same commit as the studies or skill text it affects (`fips-sl` §4b
"Corpus change").

### 2.2 `import-specs.py`

Standard library plus `pdftotext` (poppler-utils).

- `import-specs.py DIR…` scans the directories for PDFs, matches each one
  to a row **by sha256**, copies it to `pdf/<id>.pdf` and extracts
  `text/<id>.txt`. A file whose name matches a row but whose digest does
  not is reported as another edition and skipped.
- `restricted` rows are skipped unless `--with-restricted` is given.
- `--checklist DIR` copies a FIPS-Checklist (its `data/*.jsonl`,
  `build_checklist.py` and `preamble.md`) to `checklist/` and rebuilds its
  generated views there.
- `--status` prints one line per row: present or `MISSING`.

## 3. Installation

`auto-wp.py --driver fips` calls `install_specs` after `install_tools`. It
copies `specs/` to `<project>/specs`, skipping `*~` and `__pycache__`, and
prints `copied  <project>/specs (corpus: N of M documents)`. When N < M it
warns on stderr. A missing `MANIFEST.tsv` is an error: the run exits 1 and
rolls back. An existing `<project>/specs` is `kept`. Under `--driver rmf`
nothing is installed.

The copy is deliberately whole, documents included, so the campaign
container sees the same corpus as the host. This copies the restricted
documents too if they were imported; `specs/README.md` says so.

## 4. Citations

On an `RQ#` home line (`report-format.md` rule F3), one or more tokens, most
binding first:

```
src:<DOC>:<LOC>   DOC in MANIFEST.tsv; LOC as the document numbers it, no §
src:<DOC>         the whole document (rare on an RQ#)
src:PDF-annN      FIPS 140-3 itself, N in 6, 7, 10, 13 (≡ src:FIPS140-3:annN)
src:UNSOURCED     alone on its line
chk:<ID>          a checklist item: a cross-reference, never a source
```

Token grammar: `src:[A-Za-z0-9.-]+(:[A-Za-z0-9._-]*[A-Za-z0-9])?`, so a
trailing full stop ends the token. Examples: `src:ISO19790:7.10.2.1`,
`src:ISO24759:AS10.17`, `src:SP800-140:VE07.26.02`, `src:IG:9.7.B`,
`src:IG:D.O`, `src:SP800-90A:10.1.2`.

## 5. Linter (`bin/fips-lint.sh`)

The corpus is read from `specs/` relative to the working directory, or from
`$FIPS_SPECS`. Without `MANIFEST.tsv` the linter behaves as in 0.8.0: only
`src:PDF-…` and `src:UNSOURCED` are accepted.

| Check | Level | Rule |
|---|---|---|
| F-C4 | FAIL | an `RQ#` has at least one `src:` (was: exactly one) |
| F-C5 | FAIL | every `src:` names a manifest document; FIPS 140-3 on an `RQ#` only Ann. 6/7/10/13; `UNSOURCED` alone; outside `RQ#` lines, `src:PDF-x` must be a section of the PDF |
| F-C10 | WARN | volume per applicable area. With the corpus, `{1: 3–40, 2: 4–50, 3: 5–60, 4: 6–70}` (ISO/IEC 24759 assertion counts per area); without, the 0.8.0 budgets |
| F-C11 | INFO, WARN | the `UNSOURCED` count; WARN above half with the corpus present |
| F-C12 | WARN, INFO | `LOC` occurs in `text/<DOC>.txt` as a whole token, not followed by a word character or `.`+word character (so `4.3.` matches `4.3`, `7.10` does not match `7.10.2`); INFO for documents without text |
| F-C13 | WARN | an `RQ#` whose only sources are `draft` documents |
| F-C14 | FAIL, SKIP | every `chk:<ID>` is in `checklist/data/*.jsonl`; SKIP without a checklist |

F-C12 is a WARN because extraction loses some headings (§6 of the
evaluation). It checks that the locator **exists**, not that it says what
the requirement says; that stays the reviewer's honesty audit.

## 6. Tests

`test_templates.py` T9 checks the manifest pins FIPS 140-3's sha256 and
lists every document the skeleton cites. T10 runs the canaries against a
temporary corpus (the real manifest, a stub checklist) and checks F-C12,
F-C13 and the no-corpus fallback. T13 reads `specs/pdf/FIPS140-3.pdf` and
skips when it is not imported. `test_auto_wp.py` covers `install_specs`
(`test_fips_specs`, `test_fips_specs_missing_manifest`) with a program copy
holding only the manifest, so no test depends on local imports.
