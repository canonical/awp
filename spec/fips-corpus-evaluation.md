# Evaluation — how well awp digests the FIPS 140-3 corpus

Measured on 2026-11-17 against the corpus of [`fips-corpus-spec.md`](fips-corpus-spec.md)
(53 manifest rows, 51 imported, ISO/IEC 19790 and 24759 not imported) and
the FIPS-Checklist in `../NIST-Specs/FIPS-Checklist` (1372 items). The goal
behind it is a `fips-sl` study of gnutls that a verification campaign can
discharge. Each section gives a difficulty, its measure, what 0.9.0 does
about it, and what stays open.

## Summary

| # | Difficulty | Severity | Handled in 0.9.0 | Still open |
|---|---|---|---|---|
| 1 | Size: ~1.27 M tokens, more than any context | high | read `text/` by section; budgets raised | no retrieval helper; the author must search |
| 2 | ISO/IEC 19790/24759 licensing | **high** | `restricted` rows, opt-in import, citable without text | ~30% of checklist citations unverifiable without them; per-level text unavailable |
| 3 | Extraction fidelity | medium | no `-layout`; tolerant anchor; F-C12 is a WARN | lost headings (e.g. SP 800-108r1 §6.x) need a human |
| 4 | Machine checklist errors | medium | `chk:` is never a source; F-C14 checks ids only | wrong citations inside items |
| 5 | Live lists outside the corpus | medium | documented; `UNSOURCED` + reference | SP 800-140C/D lists, CAVP/ESV certificates |
| 6 | IG and transition churn | medium | sha256 pinning; "corpus change" re-author trigger | no diff tool between editions |
| 7 | Several sources per requirement, with precedence | low | multiple `src:` per `RQ#`, ordered | precedence not checked mechanically |
| 8 | Algorithm-level requirements vs the area/property model | **high** | residual planes `crypto`/`validation` | 42% of checklist items have no property class |
| 9 | Volume | medium | F-C10 budgets 3–40 … 6–70 per area | uncalibrated |
| 10 | Drafts | low | `status` column; F-C13 WARN | — |
| 11 | "Locator exists" ≠ "locator says it" | **high** | F-C12 checks existence only | stays the reviewer's honesty audit |

The framework **can** digest the specs: the citation grammar, the manifest and
the linter scale to 53 documents with no change to the loop's structure
(F1–F5, the code barrier, the human terminus). The hard parts are not
mechanical. They are the ISO licence (2), the fit between algorithm-level
requirements and the eleven-area property model (8), and the semantic check
of citations (11). The linter cannot solve any of the three.

## 1. Size and context

| Document | ~tokens (chars/4) |
|---|---|
| IG | 180 900 |
| SP800-56A | 99 500 |
| SP800-90C | 82 100 |
| SP800-56B | 82 000 |
| SP800-90A | 60 000 |
| CMVP-MM | 59 000 |
| SP800-90B | 50 200 |
| FIPS186-5 | 45 100 |
| **all 51 imported** | **1 272 000** |
| checklist (md view) | ~170 000 |

No agent context holds this; the IG alone is most of a 200k-token window.
The 0.8.0 design ("read the PDF") assumed an 11-page document. 0.9.0 tells
the author to `grep -n` the locator in `specs/text/<DOC>.txt` and read that
section only, and gives a precedence order so it knows where to look first.

**Open.** A small `specs/cite.py DOC LOC` that prints one section would make
lookups reliable and cheap; the agent currently relies on `grep` and a
guessed line range. A per-area reading list (area → ISO clause → IG sections
→ SP 800-140 assertions) would bound the reading for each of AR1–AR11.

## 2. ISO/IEC 19790 and 24759 licensing

Both PDFs are present in `NIST-Specs/`, but:

- ISO/IEC 19790:2012 is licensed to one named individual, for viewing and
  printing one copy, internal use only;
- ISO/IEC 24759:2017 is encrypted with copying disabled, and its notice
  requires prior AENOR authorisation for use on an internal network or a
  corporate platform.

Copying them into every generated project and into a campaign container,
and feeding them to a hosted model, is plausibly outside both licences. So
they are `restricted`, imported only with `--with-restricted`.

**Effect, measured.** Of 3430 source citations in the checklist, 1004 (29%)
point to ISO/IEC 19790 (516) or 24759 (488); of the 3209 citations that name
a corpus document with a locator, 979 (31%) are ISO. Without the text:

- F-C12 cannot check any ISO locator (INFO only);
- the **per-level** requirement text is unavailable. It exists only in
  ISO/IEC 19790 §7 (the level columns). SP 800-140 lists only the assertions
  it modifies; the checklist's 445 `ISO-*` items are paraphrases, and
  paraphrasing a licensed text is itself a derivative-work question, which
  is why the checklist stays local;
- `min-level K` (rule F5) stays the author's reading.

**Open.** A per-organisation decision. With a licence that permits it, run
`import-specs.py --with-restricted` and every ISO citation becomes
checkable; nothing else changes.

## 3. Extraction fidelity

Checklist citations resolved against `specs/text/` (session probe, same
anchor rule as F-C12):

| Outcome | Citations |
|---|---|
| locator found as a heading | 2184 |
| locator found elsewhere in the text | 15 |
| locator not found | 31 |
| document without text (ISO) | 979 |
| document not in the corpus | 128 |
| no locator | 93 |
| **total** | **3430** |

Of the citations that could be checked, 98.6% resolve. The 31 failures mix
real citation errors (§4), probe parsing limits, and **extraction loss**:
`pdftotext` drops some numbered headings entirely (SP 800-108r1 §6.2–§6.4
have no number in the text), and some headings end with a full stop
(`4.3.`). The pre-existing T13 failure was another case: `-layout` wraps a
sentence of Ann. 7 across columns, so the phrase never appeared.

0.9.0 extracts without `-layout`, anchors locators so `4.3.` matches `4.3`
but `7.10` does not match `7.10.2`, and makes F-C12 a WARN, so a lost
heading costs a manual check, not a false failure. T13 now passes.

## 4. The machine-extracted checklist

The checklist is a useful completeness net (1372 atomic items, each with
sources, applicability and a verification hint), but it was produced by a
model and contains errors:

- `FIPS 140-3 §7.10` (FIPS 140-3 has no §7; the clause is ISO/IEC 19790
  §7.10);
- `FIPS 140-3 MM §…`, `FIPS 140-3 Management Manual §7.1.7` (the CMVP-MM,
  not FIPS 140-3);
- `SP 800-140Cr2 §6.1` (does not exist: 140Cr2 has §6.2 only, a pointer to
  the live CMVP list);
- 128 citations name documents not in the corpus (SP 800-57, SP 800-52r2,
  RFC 8446, SP 1800-40B ipd, the CAVP FAQ, the "Use of … with SP800-140Br1"
  documents cited by title).

So `chk:` is a cross-reference and never a `src:`: the author reads the
section the item cites and cites that. F-C14 checks only that the id exists.

## 5. Live lists

SP 800-140C (approved security functions) and SP 800-140D (approved SSP
establishment methods) contain no lists. They point to CMVP web pages that
change independently of any revision. The same holds for CAVP algorithm
certificates and ESV entropy certificates. These are the **actual**
authority for "is this function approved", which is the core of AR1
(`approved-only`) for gnutls.

A requirement resting on them is `src:SP800-140C:6.2` (the pointer) plus
the external reference in prose, and the list itself is the `validation`
residual. Snapshotting the lists into `specs/` would make them citable but
would add a dated, unofficial copy; not done.

## 6. Churn

`NIST-Specs/` holds five IG editions and two Management Manual editions
from about one year. SP 800-131A Rev. 3 and NIST IR 8547 (PQC transition)
are drafts that will change the approved key lengths and algorithm sunset
dates. A citation like `src:IG:C.H` is only meaningful against one edition.

0.9.0 pins one edition per document by sha256; `import-specs.py` refuses a
different edition with the same name; `fips-sl` §4b adds "corpus change" as
a re-author trigger. **Open:** nothing reports which `src:` tokens of an
existing study moved between two IG editions; that check would be a diff of
two `text/IG.txt` section indexes.

## 7. Several sources, with precedence

A real requirement is spread across documents: ISO/IEC 19790 states it, SP
800-140 modifies its assertion, the IG interprets it, an algorithm standard
constrains its parameters (e.g. GCM IV generation: SP 800-38D §8.2 as
restricted by IG C.H). The checklist's preamble gives the precedence used
in `report-format.md`. 0.9.0 allows several `src:` per `RQ#` (F-C4 changed
from "exactly one" to "at least one"), most binding first. The order is not
checked: the linter cannot know whether an IG entry overrides or merely
explains a clause.

## 8. Algorithm-level requirements vs the area model

The checklist by prefix:

| Group | Prefixes | Items | Share |
|---|---|---|---|
| Algorithm | SIG 114, SYM 96, KAS 67, KDF 65, KEM 48, ENT 44, RBG 43, HASH 41, CKG 22, KTS 21, MAC 18 | 579 | 42% |
| ISO assertions | ISO | 445 | 32% |
| Module | MOD 100, ST 69, SSP 52 | 221 | 16% |
| Process | DOC 50, CMVP 41, TRN 36 | 127 | 9% |

`fips-sl`'s model is eleven areas mapped to nine property classes
(`approved-only`, `output-inhibit`, `role-gate`, `integrity-first`,
`zeroize`, `no-plain-ssp-out`, `selftest-order`, `error-state`, `fsm`).
They fit the module and ISO groups well (they are what ISO/IEC 19790 §7
requires of a module). They do not fit the algorithm group: "AES offers
only 128/192/256-bit keys", "the DRBG reseeds before 2^48 requests", "RSA
keys are generated per FIPS 186-5 A.1.3". For gnutls these are exactly the
checks a reviewer will ask about.

Today those land in the `crypto` and `validation` residual planes (CAVP
KATs), which is honest. But some are provable functional properties
(parameter checks, reseed counters, key-length guards, IV uniqueness), and
the property-class vocabulary has no token for them, so a study cannot rank
them as `VO#`s. **Open, and the main design question for the gnutls
campaign:** add a class such as `algo-param` (a parameter or bound from an
algorithm standard, checked per function, WP-provable), or keep algorithm
conformance out of the study and leave it to CAVP.

## 9. Volume

ISO/IEC 24759 has roughly 5–50 assertions per area at level 1 (from the
checklist's ISO items: roles 38, module specification 32, conditional
self-tests 29, physical 16). The 0.8.0 budget of 1–3 requirements per area
would make a corpus-backed study fail Gate A. F-C10 now uses 3–40 at level 1
up to 6–70 at level 4 when the corpus is present. These are placeholders,
as before; the skeleton (8 requirements, one per area) now warns F-C10,
which is expected for a format fixture.

## 10. Drafts

Two manifest rows are drafts (SP 800-131A Rev. 3 ipd and NIST IR 8547), and
27 checklist citations point to the former. They describe where the rules are going, which
matters for a module validated for five years, but are not binding. F-C13
warns when a requirement rests only on drafts.

## 11. Existence is not support

F-C5 and F-C12 prove that a citation names a real document and a real
section. They do not prove the section says what the requirement says; a
fluent author can cite `src:IG:9.7.B` for a zeroisation claim that IG 9.7.B
does not make. This is the skill's dominant coherent-and-wrong, and a
larger corpus makes it **easier** to commit (there are more plausible
sections to cite). It stays with the disjoint reviewer's honesty audit,
which now has the text to check against. A mechanical approximation (term
overlap between the requirement and the cited section) is possible but
would be a weak signal, so it was not added.

## What this means for gnutls

The corpus removes the main blocker of 0.8.0 (everything `UNSOURCED`). A
level 1 study of the gnutls FIPS module can now cite SP 800-140, the IG and
SP 800-131A for most module-level requirements, and the algorithm standards
for its Approved functions. Before running the campaign
(`./auto-wp.py --c --driver fips --level 1 … gnutls-fips`, then
`/time-loop gnutls 96`), decide:

1. whether the ISO licence allows `--with-restricted` (§2);
2. the module boundary: whether nettle, hogweed and GMP are inside it, as
   the vendor's public Security Policy states it (`fips-sl` F1);
3. whether algorithm-parameter properties become `VO#`s (§8).

Even then the deliverable is evidence for a CST laboratory, not a
validation: the CMVP certificate, CAVP/ESV certificates and the operational
environment stay residuals (F5).
