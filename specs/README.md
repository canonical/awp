# specs/ — the FIPS 140-3 corpus

The documents `fips-sl` cites under `--driver fips`
([`spec/fips-corpus-spec.md`](../spec/fips-corpus-spec.md)). Only the
index is committed; the documents themselves are local copies, never in git
(`.gitignore`).

| Path | In git | Contents |
|---|---|---|
| `MANIFEST.tsv` | yes | One row per citable document: `id` (the `DOC` of a `src:DOC:LOC` token), kind, status, licence, pages, sha256, original file name, title |
| `import-specs.py` | yes | Copies matching PDFs in, extracts their text, imports the checklist |
| `pdf/<id>.pdf` | no | The documents, renamed to their id |
| `text/<id>.txt` | no | `pdftotext` output, what agents read and the linter's F-C12 checks locators against |
| `checklist/` | no | A FIPS-Checklist (atomic requirements, each citing its sources), cited as `chk:<ID>` |

## Populate

```bash
specs/import-specs.py --checklist ../NIST-Specs/FIPS-Checklist ../NIST-Specs
specs/import-specs.py --status
```

A PDF is imported only if its sha256 is in `MANIFEST.tsv`: superseded
editions (older IG and Management Manual versions) are ignored, and a file
with a known name but another digest is reported as a different edition.
To move to a new IG, update its `MANIFEST.tsv` row (sha256, pages, source
name, title) in the same commit as the skill or study changes it causes.

`auto-wp.py --driver fips` copies this directory, as it is, to the project's
`specs/` and warns about missing documents.

## Licences

`kind`/`license` in `MANIFEST.tsv`:

- `public`: NIST publications, US Government works.
- `restricted`: ISO/IEC 19790 and ISO/IEC 24759. The copies are licensed
  per licensee and may forbid copying, networked or corporate-platform use
  and machine processing. `import-specs.py` skips them unless you pass
  `--with-restricted`, and then they are copied into every fips project
  you generate, and into its container. Check your licence first. Without
  them, `src:ISO19790:…`/`src:ISO24759:…` citations are still accepted
  but cannot be checked (F-C12 INFO), and the SP 800-140 DTR plus the IG
  are the citable public text for most area requirements.

The checklist is machine-extracted and is not a NIST product. Several of
its citations do not resolve (see
[`spec/fips-corpus-evaluation.md`](../spec/fips-corpus-evaluation.md)).
That is why `chk:` is a cross-reference and never a `src:`.
