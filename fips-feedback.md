# fips-feedback — what the fips driver did not implement (yet)

Status of the implementation of [`spec/fips-skill-spec.md`](spec/fips-skill-spec.md)
(revision 8, "ready to implement") as of 2026-11-06, written where the next
session will look for it. What **is** done: `auto-wp.py` 0.5.0 with
`--driver rmf|fips` and `--level`, the `fips-sl` skill
(`templates/common/skills/fips-sl/`), `/fips`
(`templates/c/commands/fips.md`), `bin/fips-lint.sh`
(`templates/c/tools/bin/`, per the spec's §6 table), the corpus `specs/`
(0.9.0, replacing the vendored `NIST.FIPS.140-3.pdf`;
[`spec/fips-corpus-spec.md`](spec/fips-corpus-spec.md)), the `time-loop` driver
table, `bin/crosswalk-gen.sh --kind fips`, the `bin/ledger-ratchet.sh` FIPS
row form, the launch-side `fips-crosswalk.md` + `fips-feedback.md`, the
monitoring/crosswalk doc updates, the README placeholders, and the tests
(`test_auto_wp.py` driver tests, `test_templates.py` T9–T13, `install-test.sh`
C2.6). This file records the rest.

## Not implemented — the spec's open points, still open

1. **Corpus (spec §9.1) — mostly closed in 0.9.0.** `specs/` indexes 53
   documents (FIPS 140-3, ISO/IEC 19790/24759, SP 800-140 and 140A–F, the
   IG, the CMVP-MM, the SP 800-140B "Use of" guidance, SP 800-131A, the
   algorithm standards), cited `src:<DOC>:<LOC>` and checked by F-C5/F-C12.
   Still open, see [`spec/fips-corpus-evaluation.md`](spec/fips-corpus-evaluation.md):
   ISO/IEC 19790/24759 are licence-restricted and not imported by default, so
   their locators are unchecked; the SP 800-140C/D lists and CAVP/ESV
   certificates are live web data; a locator that exists but does not say
   what the requirement says is still only the reviewer's catch.
2. **Volume per level (spec §9.3).** The Gate-A budgets in `fips-lint.sh`
   F-C10 are placeholders: with the corpus `level 1: 3–40` … `level 4: 6–70`
   requirements per applicable area (ISO/IEC 24759 assertion counts), without
   it `1–3` … `3–6`. Calibrate them after the first real campaign.
3. **More drivers (spec §9.6).** `--driver ebios` is not implemented; the
   `choices` are `rmf|fips`. The pattern (a per-driver command file plus the
   driver tables) would carry it.
4. **Per-area levels (spec §9.7).** One target level for the whole module is
   still the design. ISO/IEC 19790 §7 (now citable, item 1) allows per-area
   levels; implementing them needs a manifest and F-C2/F-C7 change.
5. **Rust-side linting of a fips study (spec §9.5).** `fips-lint.sh` is in the
   C layer, so a Rust project has `bin/rmf-lint.sh` (common since 0.3.0) but
   no `bin/fips-lint.sh`: a `fips-sl` study authored in a Rust project cannot
   be linted until open point 5 is decided. (Note: spec §7.2's sentence "a
   Rust project has neither bin/rmf-lint.sh nor bin/fips-lint.sh" predates the
   0.3.0 move of `rmf-lint.sh` to the common layer and does not hold.)

## Not implemented — integration debts

6. **Rust driver half.** `--driver`/`--level` are recorded in the manifest and
   `fips-sl` is installed under `--rust`, but nothing Rust-side reads them:
   `creusot-launch` is still unwritten (`auto-wp.md` §4.3.7, roadmap step 1),
   and it is the loop that will consume the driver and the `fips-sl` study
   (spec §7.2).
7. **`frama-c-monitoring` §8e stays EBIOS-only** — by design (spec §7.1):
   RMF and FIPS feedback are driven by their campaign commands and
   `references/{rmf,fips}-feedback.md`, not by a monitoring-loop branch. Listed
   so nobody mistakes it for an omission.

## Not yet run — validation debt

8. **Level 2 with the fips driver.** `install-test.sh` C2.6 (the second
   project, `--driver fips --level 2`) is written but has not been executed in
   a container: run `make test-c-l2`.
9. **Level 3 fips campaign.** `tests/c/mbed-tls-test.sh` is written and its
   SKIP guard now passes (the driver exists), but the campaign has never run.
   Its defaults are a full-scale run — FIPS 140-3 **level 4** for **96
   hours**, the cost profile of `acceptance.sh` — and it refuses a credential
   that would expire before the run ends (`secret_check_expiry`;
   `ACCEPT_TOKEN_EXPIRY=1` overrides). For a first cheap smoke pass
   `FIPS_LEVEL=2 MBEDTLS_HOURS=2`. Its workshop mode (`WORKSHOP=1`) is
   untested too.
10. **The GRUB module sentence.** The fips README points at
    `/time-loop grub 72 --dir=grub-core/lib/libgcrypt`; the path is not
    verified (spec §7.3: "the first level 3 run confirms it"), and whether
    GRUB's crypto library is the right default target was open point 2 —
    answered for the smoke test (Mbed TLS), not for the README's example.

## Numbering note (not a gap)

The spec's §8 numbers the new template checks T8, T9, T9b, T9c and T10;
`tests.md` §3.2 already carried a T8 (the workshop layer), so they landed as
**T9–T13** there (T9 the skill + registry + PDF, T10 the linter canaries, T11
the ratchet, T12 the generator, T13 the PDF quotes). Pure renumbering — no
check was omitted or weakened.
