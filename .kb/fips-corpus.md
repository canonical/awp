# Preface

Rules for the FIPS 140-3 corpus `specs/` and the `src:<DOC>:<LOC>`
citations of `fips-sl` (0.9.0). Read with `specs/README.md`,
`spec/fips-corpus-spec.md` and `spec/fips-corpus-evaluation.md`.

IMPORTANT: Read the `.kb/agents.md` file.


# Laws

## §1 - No document in git

Never commit a PDF, `specs/text/` or `specs/checklist/`. Only
`specs/MANIFEST.tsv`, `specs/README.md`, `specs/import-specs.py` and
`specs/.gitignore` are tracked. Check `git status --short specs` before
committing.

## §2 - Restricted documents stay opt-in

ISO/IEC 19790 and 24759 are licensed per licensee. Never import them by
default, copy them into a test fixture or quote them in a committed file.

## §3 - Tests must not depend on local imports

A test that needs the corpus builds a temporary one (the real
`MANIFEST.tsv`, stub text or checklist) or skips when `specs/pdf/` lacks the
file (T13). `make test` must pass on a fresh clone.

## §4 - Extract without -layout

`pdftotext -layout` wraps phrases across columns and broke T13. Use
`pdftotext -enc UTF-8` and normalise whitespace before phrase matching.


# Concepts

## Checklist is not a source

`chk:<ID>` points to the machine-extracted FIPS-Checklist. Several of its
citations are wrong (`FIPS 140-3 §7.10`, `SP 800-140Cr2 §6.1`), so a
requirement cites what the checked section says, never the item.

## New IG edition

Update its `MANIFEST.tsv` row (sha256, pages, source name, title), re-run
`import-specs.py`, and re-check every `src:IG:` of existing studies: F-C12
reports locators that disappeared, not those whose text changed.
