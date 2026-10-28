# Frama-C/WP operational gotchas — the tooling appendix

One place for the hard-won *tooling* lore, kept **separate from per-campaign findings** (which
live in the verdict log / report) and from the *methodology* (stabilizers.md). Report bodies
should follow scope → verdicts → soundness and link here for any "why did WP do that?" — they
should not interleave gotchas with results (review: "pull all tooling lore into one appendix").

This is an index + checklist; the worked detail for the Coq path is in `../../frama-c/references/coq-escalation.md`, and
the two confirmed WP defects are in `getting-better/`.

## Invocation & parsing
- **Includes must be wrapped:** bare `-I` is rejected; pass them inside
  `-cpp-extra-args="-I … -DMBEDTLS_CONFIG_FILE='<…>'"`.
- **Two include sets** (mbedtls): `PARSER` (minimal — leaf ASN.1/X.509) vs `FULL` (adds
  `builtin/src extras platform utilities library` + `-DMBEDTLS_PLATFORM_IS_UNIXLIKE`) for
  anything pulling the cascade via `ssl_misc.h`.
- **Force-includes** for stripped typedef chains (StandardAlgorithms): `-include typedefs.h`
  (+ `Stack.h`); without it WP reports `unexpected token 'value_type'` and **silently drops the
  annotation** — scan for `unbound logic function` / "ignoring" warnings (they read as benign).
- **Submodules first.** A bare clone won't preprocess (`tf_psa_crypto_platform_requirements.h:
  No such file`); `git submodule update --init --recursive` is the binding precondition.

## Scoping & memory model
- **`-wp-fct <fn>` is mandatory** on ssl/net units: Frama-C's *own* `sys/socket.h` has an
  `assigns …(0..)` infinite-range stub that aborts whole-file WP ("Invalid infinite range").
- **`-wp-model +cast`** for `void*`-callback (BIO) code (`void *ctx` cast to a struct) — the
  default Typed model can't reason across the casts ("Cast with incompatible pointer types").
  Caveat: `-wp-model Caveat` may *prove* what `+cast` can't, but can be **vacuous** (confirm with
  a mutation probe before trusting it).
- **`-wp-fct` excludes global lemma goals** — verify a file-level lemma separately with
  `-wp-prop <lemma>`.
- **A large `+cast` function VC blows up from context bloat, not difficulty.** `-wp-model +cast`
  Qed/SMT can stall on a big function (`ssl_parse_record_header`) even when the claim is easy —
  the per-goal context carries the whole function. Fix: **splice the load-bearing arithmetic into
  a tiny standalone harness** (a few lines reproducing just the computation) and prove *that* — a
  fast, decisive answer (record-header overflow: full-fn slow, arithmetic harness 6/6). Distinct
  from the Coq "isolate a named lemma" idiom — here you isolate a *driver*, not a lemma.

## Provers, Coq, replay (see `../../frama-c/references/coq-escalation.md` for the full workflow)
- Prover name for Coq is lowercase `coq` (from `frama-c -wp-detect`); matched toolchain is the
  `framac-coq8` switch (Coq 8.20.1, not Rocq 9.x).
- **SMT cache masks new Coq scripts** → replay with `-wp-cache none`/`replay`, not a plain run.
- **Multi-prover scheduling can mask the Coq verdict** — discharge lemmas with `-wp-prover coq`
  *alone* (or read `-wp-report-json`), not in a combined `alt-ergo,z3,coq` summary.
- `Require` imports go **inside** `Proof.` (WP regenerates the prelude); audit each `.v` with
  `Print Assumptions` — only definitional axioms + proved upstream lemmas, **0 admits**.
- `coqc` passing ≠ `coqtop -batch -l` passing: the latter loads module `Top`, so filename-qualified
  names break; test both.
- **A `Print Assumptions`-clean script still rests on `coqwp`.** `-wp-prover coq` *inlines* WP's
  realization library (`$(frama-c -print-share-path)/wp/coqwp/`), which itself ships ~57 `Admitted`
  **lemmas** — the real TCB of the coq backend. For extreme-rigor campaigns, vendor + harden + CI-gate
  it (the full recipe is in `../../frama-c/references/coqwp-trust-root.md`). Two Coq-8.20 traps when
  you do: **`omega` is gone → `lia`** (coqwp itself won't build on 8.20, so re-prove in a
  self-contained `*_hardened.v`), and **`Require Import Bool` resolves to *Why3's* `bool.Bool`** under
  `-R "$(why3 --print-libdir)/coq" Why3` — force Coq's with `From Coq Require Import Bool`.

## ACSL authoring
- **C `%` is `Z.rem`, not `Z.modulo`** — use the `rem`/`quot` lemma family in Coq.
- **`_Bool` is modelled truth-functionally** — `ensures \result == (e)` pins it only to
  "nonzero iff e"; to compare two bool results add `ensures \result == 0 || \result == 1`.
- **Clause order is fixed:** `requires` must precede `assigns`/`ensures` — WP rejects
  "requires after post-condition" (a fatal annot-error).
- **Loop-invariant validity:** prefer the **range form** `\valid_read(*p+(0..end-*p-1))` over the
  fixed-base `\forall i` for *preservation* (the `\forall` form caused a 30-goal timeout cascade
  in `x509_csr_parse_extensions`).
- **`(buf,end)` pointer comparison needs a same-object anchor.** C pointer comparison/subtraction
  is UB across objects, so WP cannot relate `*p` and `end` until you `requires
  \base_addr(*p)==\base_addr(end)` (and `*p<=end`). For the per-byte read inside the loop, supply a
  **ghost `base` anchor** to instantiate the fixed-base `\valid_read` range, and phrase invariants
  in **linear pointer-difference** form (`0 <= *p-base`, `n <= end-*p`) — several initial timeouts
  were SMT-incomplete-but-entailed and cleared purely by this reformulation. For a sentinel-array
  scan, a pointer-subtraction variant hits WP "Uncomparable locations" — carry a **ghost integer
  index in lockstep** with the cursor (`cur == &arr[i]`) instead (`ciphersuite_from_id`).
- **`-wp-init-const` injects every const-array entry into every goal context.** A `\valid_read`/
  `valid_read_string` over a large const lookup table (the 68 const ciphersuite *name* strings in
  `ciphersuite_from_string`) then goes **SMT-incomplete** — entailed, no counter-model, just too
  much context per goal. It is *not* a spec defect; classify as SMT-incomplete (and consider
  dropping `-wp-init-const` or scoping the goal), do not call it a prover limitation.
- **Static-inline helpers need `assigns \nothing`/`ensures`** or WP re-frames a fresh allocator
  per call, making even `x = end` unprovable (dominant friction on struct-bookkeeping units).
- **`memcpy`/`memmove` over `unsigned char*`** need the exact `\object_pointer((char*)p) &&
  \valid((char*)p+(0..n-1))` form — the `unsigned char* → char*` cast splits the typed chunk.

## Consistency probe for axiomatics (lower-bound integrity)
- A **bare `lemma \false;` is insufficient** to detect an inconsistent axiom set: SMT will not
  instantiate quantified axioms without a trigger, so contradictory `\forall x; g(x)==0` /
  `\forall x; g(x)==1` does **not** prove a bare `\false` (verified). The probe lemma must
  **reference the axiom symbols at a concrete point** — e.g. `lemma p: gcd(a,0)==a+1;` or a
  self-contradiction `f(0,..) != f(0,..)` — so the axioms instantiate. Enforced by
  `framac-consistency-probe.sh`.

## Cross-unit contracts (the leaf-first propagation, WP form)
- A caller binds a callee's contract from the **declaration it sees** (the header), not the
  definition — so cross-unit stub contracts go on the **header prototype** (`asn1.h`,
  `x509_internal.h`, `psa/crypto.h`), and each is verified against its definition (the disjoint
  oracle). **Never** inject a forward-decl into the `.c` to carry a contract — that is a
  faithfulness violation (the reverted `ssl_ticket` move).

## Confirmed WP limitations that cap coverage (filed in getting-better/)
- **Typed-model `\fresh`/allocation unimplemented** — `assigns`/separation goals over freshly
  `calloc`'d linked structures are unprovable by SMT *or* Coq (`\fresh` dropped at translation).
  Caps `x509_get_name` and the structural parsers' alloc footprint. RTE-safety still provable.
- **`+cast` malloc-frame defect** — a call through `assigns *((T*)ptr)` emits a VC with no
  pre/post malloc-map hypothesis → false-as-generated. Caps the `void*`-callback surface
  (`ssl_ticket_parse`, `net_recv`).

## The `obj_size` cast-residual (tried, rejected — do NOT redo in isolation)
`requires end-*p <= SIZE_MAX` closes the `(size_t)(end-*p)` cast-residual on a *self-contained*
function (`get_bitstring_null`), but **cannot be bolted onto a heavily-called leaf**
(`get_tag`/`get_len`) — it becomes a new obligation at every call site that callers without their
own size bound can't discharge (measured regression `x509_get_serial` 57/57 → 57/58). It must be
**propagated through the whole `(buf,end)` family** (chaining from the top-level
`*_parse_der(buf, len:size_t)`), or left as an honest PARTIAL.

## Cross-provider disjoint oracle (operational — extreme-case only)
When decorrelating a soft/over-promise judgment across provider families (Gate C′ completeness
oracle, the stub over-promise judge — see `../templates/squeeze-table.md` and `STUB-AUDIT`), remote
models run via **ollama at `$(cat ~/.local-llm-machine-ip.txt):11434`** (`/api/generate`, `temperature:0`):
- **Reasoning models (`qwen3.5:27b-mlx`, `deepseek-r1:70b`) return EMPTY at small budgets** — they
  burn the budget on hidden thinking. Set `num_predict` ≥ 2000 and read the `thinking` field, or
  they look like a failed call. **Instruct models (`llama4:16x17b`, `gemma4:31b`) are reliable** at
  small budgets and are the workhorses; expect occasional host-contention timeouts (retry).
- A **base** model (`qwen2.5-coder:1.5b-base`) is too weak — it pattern-continues the prompt instead
  of answering. Use 27B+ instruct/reasoning models only.
- Keep the judge **code-blind** (feed the contract + documented surface, never the body/callers) and
  log which families returned cleanly — partial returns are honest, a silent single-family verdict is
  not. This is **extreme-case only**, not a default step (see SKILL.md "When to run this loop").

## `-wp-model Bytes` for cast-pointer arithmetic (void* buf in I/O stubs)
- **Symptom:** goals around `grub_disk_read(disk, sector, offset, size, buf)` where `buf` is typed
  as `void*` and written as `((char*)buf)[0..size-1]` time out or stay Unknown under the default
  `Typed` model. The `assigns_normal_partN` and `call_xxx_requires` goals time out on Alt-Ergo/Z3.
- **Root cause:** the Typed model needs a concrete pointed-to type to reason about pointer ranges;
  a `void*` → `char*` cast creates a type-aliasing gap the model cannot bridge.
- **Fix:** add `-wp-model Bytes` to the frama-c invocation for TUs that have this pattern. Bytes
  model handles byte-level pointer arithmetic directly. Tested: `grub_ext2_blockgroup` went from
  43/45 (Timeout × 2) → **45/45** under Bytes. Record `-wp-model Bytes` in the queue entry for
  all TUs with `void*`-buffer I/O.
- **Arose from:** grub2-2.12 campaign (2026-07-07).

## `grub_add` / `__builtin_add_overflow` aborts whole-file Frama-C parse
- **Symptom:** `[kernel] Frama-C aborted: invalid user input` when parsing `grub-core/font/font.c`
  (and likely other GRUB files). The aborting line uses `grub_add(a, b, &result)` which expands to
  `__builtin_add_overflow(a, b, result)` — a GCC built-in that Frama-C's kernel cannot parse.
- **Workaround:** create an **isolated harness file** containing only the target functions and a
  minimal set of includes (e.g. `grub/font.h`, `grub/types.h`). Do NOT try to pass the full
  `font.c` to Frama-C when `grub_add`-using functions are present. The harness-only approach
  preserves the faithfulness baseline (grub2-2.12/ stays pristine; the harness is new in the
  overlay) and WP proves the target functions cleanly.
- **Scope of the issue:** any GRUB file that includes `<grub/safemath.h>` and uses `grub_add`,
  `grub_mul`, `grub_sub` macros will abort full-file parse. Check with:
  `grep -r 'grub_add\|grub_mul\|grub_sub\|grub_safemath' grub-core/` before scheduling a TU.
- **Arose from:** grub2-2.12 campaign (2026-07-07), RS7 font getter verification.

## Font dimension fields: `grub_font_get_height` overflow — deployment-envelope residual
- **Finding (grub2-2.12):** `font->ascent + font->descent + font->leading` has no runtime bounds
  check. WP discharges the signed-add RTE goal only under `requires -32767 <= field <= 32767`.
  Without this precondition the goal is **not provable** — confirming the production gap. GRUB2
  does not enforce these bounds at font-load time.
- **Classification:** deployment-envelope residual, NOT class-A (tool ceiling). The property is
  provable; the guard is missing in the source. This is a POA&M item (RS7 DoS via crafted PFF2
  font on the EFI system partition).
- **Arose from:** grub2-2.12 campaign (2026-07-07), `grub-core/font/font.c:973`.

## LSM-campaign proof-technique bank (linux-7.1.3, reach for these on Plane-W/H leaves)

Five reusable levers proven repeatedly across the linux-7.1.3 LSM verification campaign (selinux,
commoncap, apparmor, yama, ima, tomoyo, landlock, smack, keys). Each is DISCHARGED (a sound model
choice or a faithful contract), never an assumption. Pick by the symptom.

1. **`-wp-model Typed+cast` — the callback-param / const-pointer cast wall.** When a pristine body
   takes `void *`/`const void *` params it immediately casts to typed pointers (the SELinux
   `index_f[]` `(void*key,void*datum,void*datap)` callbacks; the assoc-array diff comparators), OR
   compares a `const T*` against a non-`const T*` (`cap_capable_helper`'s `const cred_ns` vs
   `ns->parent`), the equality/deref compiles to a `T*→char*` reinterpret that the default Typed
   model cannot bridge — specific `mem_access`/`assigns`/behavior-post goals TIME OUT (not merely
   slow). `Typed+cast` models the cast soundly and closes exactly those. **Show it is needed:** the
   bare-Typed run leaves those named goals unproved (e.g. `role_index` 15/26→26/26,
   `cap_capable_helper` 45/49→49/49, `type_bounds_sanity_check` 28/35→35/35).

2. **`-wp-model Bytes` — multi-member UNION field reads (soundness, not just pass).** Distinct from
   the void*-I/O Bytes entry above. When a body reads two members of the same union (`in6_addr`
   `s6_addr16[]`, `keyring_index_key` `{desc_len,desc}` vs `x`), the default Typed model emits
   **`[wp:union] Accessing union fields with Typed model might be unsound`** and the dependent
   `mem_access` goals time out. Bytes flattens the union to a byte array, making the reads genuinely
   sound and removing the caveat. **This is needed for SOUNDNESS, not to pass** — a Typed run may
   even report all-green *with* the caveat, which is an UNSOUND witness; record Bytes as the sound
   model (`smack_ipv6host_label` / `smk_ipv6_localhost`, `keyring_diff_objects` 61/73-with-caveat →
   73/73-clean).

3. **Pure-WP loop/walk TERMINATION without the SMT inversion wall.** For a `for(;;)`/parent-chain/
   RCU-list/hash-bucket walk, do NOT use an inductive well-founded predicate (Alt-Ergo/Z3 hit an
   inversion wall). Two sound patterns, both FAITHFUL caller obligations — **NOT axioms**:
   - **Well-foundedness PRECONDITION** over an uninterpreted `logic integer depth(node)`: a
     universally-quantified `requires` (any live node above the floor has a live parent of
     strictly-smaller non-negative depth) instantiated at the loop entry, + a "shape" loop invariant
     carrying the first-iteration exit condition across the loop cut, + `loop variant depth(walker)`.
     The real finite tree/list IS well-founded, so the precond is faithful (`cap_capable_helper`
     ns→parent walk; `yama task_is_descendant` process-tree walk — termination there is the
     DoS/soft-lockup security property).
   - **Ghost FUEL** the step-extern strictly decrements: `//@ ghost int g_fuel;` with the step's
     contract `ensures g_fuel == \old(g_fuel)-1; ensures \result != \null ==> g_fuel >= 1;` → outer
     `loop variant g_fuel`. A faithful over-approximation of a finite kernel list (`smack net6addr`
     RCU walk; `device_cgroup match_exception_partial`).

4. **State the EXACT value; do NOT grind the absorption/magnitude restatement (the bitwise walls).**
   Alt-Ergo/Z3 time out on kernel-word bitwise identities: `!(a & ~b) <=> ((a&~b)==0)` and
   `(kernel_cap){a.val & ~b.val}.val == a.val & ~b.val` (the kernel_cap `~`/absorption wall,
   already-filed `wp-bitwise-smt-incompleteness`), `(x | K1 | ite(..,K2,0)) & K3` (Cint
   variable-mask absorption), and `layer << ((w-1)*4) <= 240` / `(x<<4)==x*16` (Cint variable-shift
   magnitude). Two sound work-arounds:
   - **Contract the wall-hitting callee as an EXTERN with the EXACT bit-semantics** (verbatim body
     transcription, e.g. `cap_issubset`: `ensures (\result!=0) <==> ((a.val & ~s.val)==0)`;
     `cap_drop`: `ensures \result.val == (a.val & ~drop.val)`). This is a FAITHFUL (in fact exact)
     over-approximation — a declared TCB leaf, **not a smuggled axiom** (`cap_capset`,
     `nonroot_raised_pE`, `cap_task_fix_setuid`).
   - **Case-split into behaviors whose `ensures` state the EXACT assignment result** (constant
     shifts/masks, Qed-trivial): `ima_cache_flags` non-regression via `flags == \old | K`;
     `get_layer_deny_mask` via `\result ∈ {0, layer, layer<<4}`; the apparmor DFA→perms decoders.
   The exact-value form ENTAILS the magnitude/absorption/`<=240` restatement, so drop the restatement
   as a redundant consequence — no soundness or coverage loss. **The monitor test that this is a real
   wall (not laziness):** a ≤10-line twin of the identity does not prove while the `&`-only variant
   proves instantly.

5. **Faithful callee `\valid`/`\separated`/index REQUIRES envelopes (caller obligations, not
   axioms).** A leaf whose safety depends on a real caller invariant states it as a `requires`, not
   an invented in-body guard: `\valid(arr + (0..nprim-1))` + `\separated(arr, *p)` over the real
   distinct kmalloc'd `nprim`-sized arrays (`role_index`/`cat_index`/`type_index` auth-table
   installers); `requires access_bit < 32` (the sole caller derives it from `for_each_set_bit` over a
   u32); `\valid_read(blob + (0..len-1))` (the untrusted-blob deployment envelope, `next_entry`).
   These are SOUND because they are the genuine caller/deployment invariant (weaker-or-faithful,
   demonstrably satisfiable), and the security property (in-bounds write/read) rests on the local
   GUARD + the array-size `\valid`, with `\separated` supplying only orthogonal frame reasoning.
   Dropping a callee precond is sound **only if** the unit's proved property depends solely on the
   callee's UNCONDITIONAL `ensures` — then narrow the claim honestly (`mls_read_level` dropping
   `next_entry`'s `blob_readable`; `context_read_and_validate` consuming only the unconditional
   identity-bounds `ensures` of `policydb_context_isvalid`).

**Cross-refs:** the `\fresh`-allocation wall (getting-better/`20260619-1600-wp-typed-model-fresh-
allocation-unimplemented.md`) is UNAVOIDABLE for a char-buffer `kmalloc`-then-write leaf — such a
target's `assigns`-frame goals never discharge, so a leaf that allocs+writes a char buffer is
recorded CLASS-A, not witnessed (`str_read`); prefer non-alloc targets. The `!!ptr ^ !!int` frontend
typing bug (bugs-to-report/`frama-c-wp-ptrnull-xor-int-typing`) makes any body with that idiom
un-verifiable (both provers ABORT on an ill-typed Why3 VC) — avoid such targets or file the goal as
status-3. Arose from: linux-7.1.3 LSM /time-loop campaign (2026-07-15…19).

### Addendum — the nonlinear-`mul`-into-shift index-bound wall + "lemma, not scaffold-modification"
- **Wall (linux-7.1.3 `safesetid insert_rule`):** WP+Alt-Ergo/Z3 cannot discharge
  `(u32)(v * const) >> 24 < 256` even as a plain array-index RTE goal at 90s — the nonlinear
  multiply blocks the shift-bound trigger — although the isolated `\forall u32 x; (x>>24) <= 255`
  proves **instantly**. (A hash-table index `hash_32(key,8) = (key*GOLDEN_RATIO_32) >> 24` is the
  canonical shape.)
- **Sound remedy = a LEMMA over the real code, NOT a scaffolding-macro edit.** Add
  `/*@ lemma shift_hi_bounded: \forall u32 x; (x >> (32-b)) <= (1<<b)-1; */` (or an in-body
  `//@ assert`) and keep the header macro **verbatim**. Do NOT "help WP" by appending `& 0xff` to
  the reproduced `hash_32` macro: even when the mask is a provable value-identity, it is a
  **scaffolding modification the faithfulness gate (`strip(//@)==pristine`, body-only) cannot see** —
  the exact silent-header-fabrication risk the onboarding-soundness rule warns about. If a scaffold
  mask is nonetheless used, the MONITOR must independently confirm the value-identity (prove
  `\forall u32 x; (x>>24) <= 255` so the real unmasked index is in range, and reason that masking an
  in-range value is a no-op) and record it explicitly — the mask-redundancy lemma itself will *time
  out* (same bitwise wall), so it cannot be the evidence.
- **Union single-member-at-offset-0 reads → benign `[wp:union]`, discharge under the DUAL model.**
  When a union's members are all the same scalar at offset 0 (`kid_t = union{kuid_t uid; kgid_t
  gid;}`, both `{u32 val}`), Typed still raises `[wp:union] might be unsound` on every access, but
  the read is genuinely single-interpretation. Cross-check under `-wp-model Bytes`: the
  union-dependent goals (index/RTE/fail-closed) prove there (sound), and the few Bytes residues are
  pure pointer-address-equality `ensures` (a Bytes byte-addressing limit) that prove under Typed. A
  DUAL-MODEL witness — every goal discharged under ≥1 sound model — is a legitimate sound record;
  state it, do not report a single "all-green Typed" that carries the caveat.

### Addendum — `-wp-auto="wp:range"` closes a BOUNDED variable shift (a ceiling-raise over the cint variable-shift wall)
- **Wall:** a `1 << x` / `x << k` with a **symbolic** shift amount is the documented cint
  variable-shift ceiling — Alt-Ergo/Z3 cannot bound the uninterpreted `lsl(1,x)` (the
  `bpf_lpm_extract_bit` residue shape). Previously recorded as class-A.
- **Sound remedy when `x` is bounded by a small constant** (e.g. an enum index `x < 8`, from a real
  `requires operation < TOMOYO_MAX_..._OPERATION` envelope): add **`-wp-auto="wp:range"`**. It
  **case-enumerates `x` over its finite range**, each case Qed-evaluated — a **sound proof tactic**
  (assumes/drops NOTHING, **0 axioms**), closing the shift-bound goal cleanly rather than leaving a
  residue. Confirmed on `tomoyo_check_path_number_acl` (`1 << r->param.path_number.operation`,
  `operation < 8`): 27/27 FULL under `-wp-model Typed+cast -wp-auto="wp:range"`.
- **Scope / discriminator (do NOT over-apply):** this works because the shift feeds a **permission
  MASK** (`acl->perm & (1<<op)`), and `x` has a **tight compile-time bound**. It does **NOT** fix the
  cycle-218 STORE-BLOAT wall (a variable shift into a **heap-loaded array index**): there the lemma
  proves in isolation but won't instantiate in-context, and the closer is WP→Coq, not `wp:range`.
  The two are distinct — `wp:range` needs a small *finite range to enumerate*; store-bloat is a
  frame/instantiation problem, not a range problem.
- **Ceiling-raise consequence (toolchain-enrichment retry):** because `wp:range` is a *new sound
  lever*, any prior class-A residue that was a **bounded** variable-shift-into-mask (not a heap-index)
  is now a **retry/overturn candidate** (§1 "retries class-A residues when the toolchain is
  enriched") — re-attempt with a tight `requires` bound + `wp:range` before leaving it class-A.
- **Monitor note:** `wp:range` changes the *proof search*, not the *goal* — it is not a soundness
  lever and needs no non-vacuity carve. Still confirm the bound in the `requires` is a **faithful
  real invariant** (the enum-index range), since that bound is what makes the enumeration finite.

## DEDUP by function name is UNSOUND when keyed on the STATUS column alone (2026-07-20, cycle-262)

The campaign's standing dedup grep

    grep -E "^[^\t]*\bFN\b" verdicts.tsv | grep -cE '\t(WITNESSED|[0-9]+/[0-9]+)\t'

**MISSES rows whose verdict column is not a bare status** — e.g. cycle-218's
`ss/services.c services_compute_xperms_drivers` reads `CLASS-C (91/93 kernel-sem; ...)`,
so the status grep returns **0** and a later cycle nearly re-proved it. A function that was
already WORKED (class-C, class-A, hazard, violation) is still a duplicate for target-selection
purposes even though it is correctly NOT counted as WITNESSED.

**Two different questions, two different greps — do not conflate:**
- *"How many WITNESSED units?"* (the ledger count, Gate R) → status-column grep. Correct as-is;
  a CLASS-C/CLASS-A row must NOT inflate the witnessed count.
- *"Has this function been worked before?"* (target selection / novelty) → the UNION of
  `grep -cE '\bFN\b' verdicts.tsv` (bare name, catches any status) **AND**
  `grep -cE '\bFN\b' linux/linux-acsl/units-faithfulness.tsv` **AND** `ls linux/linux-acsl/units/ | grep FN`.
  Any nonzero ⇒ already worked; inspect the row before investing.

Caught by a verifier sub-agent, confirmed by the monitor (the status grep really does return 0
on that row). The failure mode is silent: it wastes a whole cycle re-proving covered ground.

## A proof standing on an UNPROVED assert is a partial, not a green (2026-07-20, cycle-265)

A "hint" / stepping-stone variant of a unit added asserts `h_slot_valid`, `h_child_inner`,
`h_child_leaf` and appeared to discharge 21/24 goals. The asserts were **themselves unproved**
(Z3-first, `-wp-timeout 300` → 0/3, all Timeout). WP happily used them to discharge downstream
goals, so the apparent green was derived FROM undischarged hypotheses — the same defect as a
smuggled `requires`, just wearing a different hat.

**Rule:** a hint/stepping-stone file counts as a witness ONLY if
1. it is manifest-gated (`strip(//@) == pristine`, whole manifest exit 0), AND
2. **every hint assertion is itself DISCHARGED.**

An `//@ assert` that WP proves from surrounding facts is a legitimate proof step. The identical
assert that WP cannot prove, and that is then assumed downstream, is a smuggled precondition.
Always report which file the counts come from and whether every hint assert discharged.

## `-wp-model +cast` does NOT relate punned union arms — `Bytes` does (same cycle)

Probed decisively on `union sidtab_entry_inner` (`ptr_inner` / `ptr_leaf`):
- On the real unit, `+cast` emits **27 `[wp:union]` warnings across 15 lines, byte-identical to
  Typed** (`diff` → identical). `+cast` governs pointer-*cast* compilation, not union arms.
- 5-line reproducer (`union U { struct A *pa; struct B *pb; }`, `ensures u->pa != \null ==> \result != 0`):
  **Typed 3/4** · **`+cast` 3/4** (goal prefix `typed_cast_` confirms the model *was* applied) ·
  **`Bytes` 4/4, with no union warning at all.**

So a `if (!p->arm_a)` guard licensing a `p->arm_b` deref is **not modelled** under Typed/+cast —
state it as an explicit invariant and say the guard is unverified, or switch to `-wp-model Bytes`.

## Two measurement corrections from the same unit
- The earlier "~5.5 min goal generation" figure did **not** reproduce: 2218s wall for 705 goals,
  with **Qed normalization** (up to 1'39" on a single goal, 686 goals) dominating — not prover time.
- **`-wp-prop=<names>` is the practical handle**: cuts 705 goals → 14 and ~37 min → ~10 min when
  targeting specific open goals.
- **Correction to the earlier background-jobs note:** the *harness* background mechanism DOES
  accumulate (jobs ran 37 min uninterrupted). It is specifically `nohup … &` from a Bash tool call
  that silently restarts.

## WP will not case-split a DISJUNCTIVE equality on a symbolic shift amount (2026-07-20, cycle-266)

**Coordinator-reproduced independently** (own 8-line file, not the verifier's):

```c
/*@ requires s == 0 || s == 9 || s == 18;      // <-- the disjunction
    requires s == 0  ==> x < 512;
    requires s == 9  ==> x < 512*512;
    requires s == 18 ==> x < 512*512*512;
    ensures  (x >> s) < 512; assigns \nothing; */
unsigned f(unsigned x, unsigned s) { return x >> s; }      // 4/5  FAILS
```
Replace the disjunction with a **single** `requires s == 9;` (+ its one bound) → **5/5 PROVES**.

Qed 5ms, no memory model, no context bloat — so this is neither store-bloat nor a timeout.
`-wp-auto=wp:split`, `wp:split,wp:bitshift`, `wp:range` all fail to rescue it.
**Workaround:** restate the bound in shift-free (division) form so a symbolic `>>` never meets a
disjunctive constraint, or hand-write the Coq case analysis.

Corollary measured the same cycle: raising `-wp-timeout` 15 → 240 on the dependent invariants changed
**nothing** (3/6 both ways, Qed 33–50s then timeout). *More CPU is not the lever* — when a goal is
prover-stuck rather than prover-slow, timeout escalation is wasted budget.

## `-wp-model Bytes` is the union lever (confirmed on a real unit, same cycle)
On the real `sidtab_do_lookup` unit, `Bytes` **eliminated all 27 `[wp:union]` warnings** (zero in
output) and closed `wf_here_preserved` (Typed 3/6 → Bytes 4/6). Compare cycle-265: `+cast` left the
27 warnings byte-identical to Typed. So for punned unions: **Typed/+cast cannot relate the arms;
Bytes can.** (Caveat: once explicit hint asserts are present they subsume the advantage — Typed and
Bytes then tie — so Bytes is real but not always load-bearing.)

## Deleting a hint assert is the TEST for whether a green is real
Cycle-266's own retraction, worth copying as a procedure: a 16/17 run looked near-green. Deleting the
single unproved hint (`h_descent_idx`) flipped **four** previously-"proved" goals to timeout — proving
they had been discharged *from* it. **Procedure: for each hint assert, delete it and re-run. Anything
that flips was standing on it.** If the hint itself is unproved, every goal that flips is unproven too.

## `pkill -f <pattern>` can match its own `bash -c` command line and self-kill (2026-07-20)

Cleaning up stray solvers with `pkill -f 'cpp-extra-args=-Iinclude'` killed the shell running it
(exit 144), because the pattern appeared in that shell's own `bash -c` argv. The measurement it was
meant to protect died with it.

**Use `pkill -x <name>`** (exact process name: `pkill -x frama-c`, `pkill -x alt-ergo`, `pkill -x z3`).
A process *name* cannot match the wrapper shell's command line. Reserve `-f` for cases where the name
is genuinely insufficient, and then exclude self explicitly.

Related: CPU contention makes `Timeout` verdicts untrustworthy — a goal can time out spuriously under
load and look like a semantic failure. **Any non-vacuity flip must be confirmed on an uncontended
machine** before it is recorded as a witness; a contended flip is suggestive only.

## Rescuing a MASKED non-vacuity: the TWO-SIDED POSITIVE witness (2026-07-20, cycle-269)

**The problem.** A mutant's stepping-stone `assert` flips, but the *security postconditions* do not —
they are proved from the (assumed) loop invariant, whose preservation goal is discharged from the
now-false assert. That is ordinary WP modularity, but it means the postcondition-level flip is
**MASKED**: the attack proves nothing at the level you actually care about.

**The rescue — prove the fail-open, don't wait for a timeout.** Instead of accepting an
unproved-goal flip as the witness, assert the *fail-open property itself* in the mutant and prove it
POSITIVELY, then prove its converse in the compliant unit:

- mutant:    `//@ assert atk_fail_open: undefined_verdict ==> (rule & ENABLED) != 0;`  → **PROVED**
- compliant: `ensures fail_closed: undefined_verdict ==> (rule & ENABLED) == 0;`        → **PROVED**

Exactly inverted, both directions *positively* discharged. This is a decisive refutation rather than
a timeout artifact, and it is immune to the contention problem (a timeout can be spurious; a positive
proof cannot). **Prefer this whenever the natural attack flip is masked by a stepping stone.**

## A predicate SYMBOL can block unfolding where the inlined fact closes (same cycle)

Two loop-invariant preservation goals would not close when the bit fact was written via a
`predicate P_enabled(...)` — at any probed timeout (20/30/60/150 s, Alt-Ergo and Z3, ±`wp:split`).
Spelling the same fact out **inline** in the assert closed both immediately. The predicate symbol
blocks unfolding under the quantified separation hypotheses.

`-wp-simplify-type` also fixed those two goals **but broke the two loop-variant goals** — a real
trade-off, so inlining was the correct choice. Lesson: when a goal resists, try *inlining the
predicate* before reaching for a global flag that may cost you elsewhere.

## `\fresh` is SILENTLY DROPPED by WP 32.1 — sound, but it buys you nothing (2026-07-20, cycle-270)

**Coordinator-reproduced** with an own minimal probe:

```c
struct S { int x; };
/*@ assigns \nothing; ensures \fresh(\result, sizeof(struct S)); */
extern struct S *alloc(void);
/*@ requires \valid(p); assigns \nothing; ensures \separated(\result, p); */
struct S *f(struct S *p) { return alloc(); }      // 5/6 — \separated does NOT prove
```
WP prints `Allocation, initialization and danglingness not yet implemented` — easy to lose among
normal output — and the `\fresh` clause contributes **nothing**.

**Is it a soundness hole? NO — but know exactly why.** `\fresh` in an *ensures of a stub* is a
hypothesis **given to** the caller. Dropping it leaves the caller with **less** information, so a
proof that still closes, closed **without** it. That is conservative. The genuine hole would be
`\fresh` in a **`requires`** (a caller obligation WP then fails to enforce) — **campaign audit: 0
occurrences in requires position** across all units; every use is prose or ensures-of-stub.

**Practical rule:** never rely on `\fresh` to establish separation for an allocator stub. State the
separation you actually need **explicitly** (`\separated(...)`), or — better — justify it from the
code's **allocation class** (a stack automatic can never alias a slab object; cite the call sites).
The trap is that the spec *looks* like it constrains the model and does not.

## `//@ calls` local-definition wall RECONFIRMED — and it is blocking real targets
Second independent encounter (cycle-268 `landlock_init_layer_masks`, again cycle-270 on the same
function, the entry point of every Landlock fs/net access check). Indirect call sits in
`const access_mask_t handled = get_access_mask(domain, i);` — a local definition with initializer;
Frama-C 32.1: `Statement contract and ACSL pragmas over a local definition are not implemented`.
Faithfulness forbids splitting decl from initializer, so the target is **class-A U-ceiling** until WP
supports it. Note the `num_layers <= LANDLOCK_MAX_NUM_LAYERS` bound is *not* the obstacle — that is
properly enforced in code (`ruleset.c:551-555`) and would have been citable.

## Minor: an apostrophe inside a C comment **within a `//@` ghost declaration** breaks the ACSL lexer
`eof while parsing a char literal` (one instance surfaced an internal-error backtrace). Avoid `'` in
comments inside ghost/annotation blocks.

## *** VACUOUS GREEN: a `logic` fn without `reads` is STATE-INDEPENDENT → WP proves 56/56 of NOTHING ***
### (2026-07-20, cycle-271 — the most dangerous trap found so far; WORSE than the `\fresh` one)

**What happens.** You model mutable abstract state with a label-parameterised logic function:
```c
/*@ logic boolean ebit{L}(struct ebitmap *e, u32 b); */   // NO reads clause
```
Frama-C 32.1 **rejects `reads` on a logic *declaration***, so you drop it. WP then emits only:
```
[wp] Warning: No definition for 'ebit' interpreted as reads nothing
```
and treats `ebit` as **state-INDEPENDENT**. Now `ebitmap_init`'s "no bit set" and `ebitmap_set_bit`'s
"bit set" are contradictory about the *same* term, the success path becomes **unreachable**, and

> **WP reports a fully green 56/56 that proves NOTHING.**

Unlike the `\fresh` trap (which only *loses* information and is therefore sound), this one yields a
**vacuous proof that looks like a complete success**. It is exactly the coherent-and-wrong failure the
loop exists to catch.

**DETECTION — make this routine for ANY unit modelling mutable state with uninterpreted logic:**
1. `//@ assert \false;` at the point after the state-changing call. If it **PROVES**, the context is
   contradictory and every goal downstream is vacuous. (Here it proved: 57/57.)
2. **`-wp-smoke-tests`** on the shipped unit — adds unreachability/inconsistency goals. Coordinator
   independently ran this on the fixed unit: **69/69 (56 real + 13 smoke), no smoke alarm.**

**THE FIX — route mutable abstract state through a GHOST LVALUE, not a logic function:**
```c
//@ ghost unsigned long dst_ver;          // bumped on each mutation
//   dbit(dst_ver, b)  — indexed by the ghost version  → genuinely state-dependent
//   ebit(e, b)        — keep the pure form for IMMUTABLE operands only;
//                       exact for them precisely because `assigns *dst`
```
State the `assigns` so the immutability of the operands is what licenses the pure form.

**Rule of thumb:** a pure uninterpreted `logic` function is safe **only** for values the function
cannot modify. The moment the modelled object is written, you need a ghost lvalue — or you get a
green that means nothing.

## GATE GAP: a unit can pass the FAITHFULNESS gate and still NOT PARSE (2026-07-20, cycle-272)

`units-faithfulness.py` strips `//@` lines and diffs the body against pristine. It **never invokes
Frama-C**. So `OK <fn> (N lines verbatim)` / `FAITHFUL` / exit 0 says *nothing* about whether the file
is even syntactically valid. A cycle shipped a unit that aborted with
`Frama-C aborted: invalid user input` while the faithfulness gate reported OK.

**Two lexical breakages, both in header PROSE (not in the C body, not in annotations):**
1. **`*/` inside a block comment closes it early.** The text `void*/sint8*` (documenting a cast!)
   terminated the `/* ... */`, and the remaining prose was parsed as C → `syntax error`.
2. **An apostrophe** (`Can't`) → `Can't preprocess annotation: unterminated char`.

**MONITOR RULE (added):** the faithfulness gate is necessary, not sufficient. Before recording ANY
count, the monitor must re-run WP **from the committed path** and see the `Proved goals: N/N` line
itself. A count quoted from a report whose file does not parse is unreproducible and must be REJECTED.

**AUTHOR RULE:** grep new units for `*/` inside comments and for `'` before reporting. Prefer
`void* / sint8*` (spaced) or "void-star"; avoid contractions in comments entirely.

## NEGATIVE CONTROL before claiming a `[Failure]` refutation (2026-07-20, cycle-273)

A `[Failure]` verdict is normally far stronger than `[Timeout]` — the prover actively refuted the
goal. But **a prover can emit `[Failure]` from its own weakness under a given memory model.**

Observed: on the mutant, `Bytes` + **z3-only** reported `[Failure]` on both EoP goals — looking like a
decisive refutation. The verifier then ran the **negative control**: z3-only on the **COMPLIANT** unit
at t=120. It reported `[Failure]` on the *same two goals* (31/39). The compliant unit is known good,
so that verdict is z3 weakness under Bytes, not refutation. The claim was correctly downgraded to
`[Timeout]`.

**RULE:** before reporting a `[Failure]` as a refutation, run the identical prover/model configuration
against the **compliant** unit. If the same goals also "fail" there, the verdict is prover weakness —
downgrade the claim, and reach for the **two-sided positive witness** instead (prove the fail-open
property positively in the mutant, prove its converse in the compliant unit; both discharged, mutually
contradictory ⇒ contention- and weakness-immune).

## `Bytes` is not always worse on union-free units
Standing measurement had been: Bytes loses on union-free units (44/48, 28/57, 51/56, 55/56 vs Typed
green). Cycle-273 is the **first counterexample** — a union-free unit where plain Typed is 32/39 and
**both** `Bytes` and `+cast` reach 39/39 (the blocker is a `char td_data[]` flexible-array
reinterpreted as `u32*`). Keep probing plain Typed first, but do not treat "union-free ⇒ Bytes worse"
as a law; it is a tendency.

## Vacuity probe when the body is an UNBRACED `if/else` (2026-07-20, cycle-274)
The mandatory `//@ assert \false;` per-exit-path probe cannot be inserted into an unbraced
`if (c) return a; else return b;` — adding it changes the body and **breaks the faithfulness gate**
(`strip(//@) == pristine`). Equivalent probe that keeps byte-identity: append **path-guarded
postconditions** to the contract instead —
```
ensures VACUITY_PROBE_then: <guard>  ==> \false;
ensures VACUITY_PROBE_else: !<guard> ==> \false;
```
Both must come back **UNPROVED** (each exit path reachable). Remove them and confirm the restored
file diffs identical. Corroborate with `-wp-smoke-tests` as usual.

## `\valid_read` cannot witness an OOB index — and struct padding can make the OOB *legal*
A tempting OOB witness `ensures i > LAST ==> !\valid_read(&arr[i])` is **unprovable in principle**:
`\valid_read` is a *lower* bound on the allocation, so WP can never derive its negation. Worse, it can
be **outright false**: for `aa_state_t start[AA_CLASS_LAST+1]` as the last member of a
`kzalloc(sizeof(struct aa_policydb))` object, gcc_x86_64 **tail padding extends past `start[32]`**, so
`&start[33]` still lies inside the allocated object. Timeouts there are the *correct* verdict — do not
reach for a model lever. Witness the OOB with a **ghost counter / two-sided positive witness** on the
control-flow fact instead of trying to state invalidity.

## Bytes-vs-union: second counterexample, and it is sharper
Cycle-274: union-free unit that *does* contain an incompatible-pointer cast (`unsigned char*` passed
as `const char*`). `+cast` clears **only that one call goal** (20/22) and leaves both class-partition
`ensures` open; **Bytes** is the only model that closes it (22/22, Typed 19/22). So neither
"union-free ⇒ Bytes worse" nor "cast present ⇒ `+cast` is the lever" holds. **Always probe all three.**

## Run the deletion sweep YOURSELF when the verifier does not deliver one (2026-07-20, cycle-275)
The cycle-275 verifier looped on non-verdicts and was stopped before supplying a deletion sweep. The
coordinator ran all 8 hypotheses itself and found **2 of 8 were NOT load-bearing** (`vd_check_in`,
`vd_state_min` — each 84/84 when removed, and 84/84 with both removed together). Recording the unit
as-shipped would have banked a theorem **weaker than what was actually proved**.

`vd_check_in` was inert for an instructive reason: `check[pos]` is only ever **compared** to `state`,
never used as an index, so bounding its *values* buys nothing. `vd_state_min` (`STATE_COUNT >= 2`) was
subsumed by `start_in` (`start < STATE_COUNT`).

**RULE:** a green N/N with un-swept hypotheses is an unfinished measurement, not a result. The sweep is
cheap (one run per hypothesis, scriptable by regex-deleting the single `requires <name>: … ;` clause)
and it is the only thing that distinguishes "these facts were needed" from "these facts were assumed."
Sweep before recording — and when a hypothesis proves unnecessary, DROP it and restate the theorem
stronger.

## Termination inside a macro that is its own loop
`match_char` (apparmor `match.c:436-448`) is a `do { … } while(1)` **macro**, so a `continue` inside it
re-enters the **macro's** loop, not the enclosing `for`. A diff-encoded DFA state therefore walks the
`def[]` chain repeatedly *within a single input character*, and the outer `loop variant len` says
nothing about it. That inner walk needs its **own** variant — here an uninterpreted `dfa_rank(state)`
whose entire content lives in a hypothesis (no axiom asserted). When a loop body expands a macro, check
whether the macro is itself a loop before believing the outer variant covers termination.

## `git add -A` mid-cycle commits the verifier's UNMEASURED work-in-progress (2026-07-20, cycle-276)
The coordinator checkpointed a small verified edit with `git add -A` while a verifier cycle was still
running. That swept the verifier's **in-flight** unit files into the commit — artifacts nobody had
measured. No harm landed this time (the compliant file happened to be byte-identical to its final
version), and the **verifier caught and reported it**, but the commit contained files whose numbers had
never been observed.

**RULE:** while a cycle is in flight, stage **explicitly** — `git add <the specific paths this checkpoint
covers>` — never `-A`/`.`. A commit is a claim that its contents were measured; `-A` silently widens that
claim to whatever else happens to be on disk.

## A `lemma` is a proof obligation; an `axiom` is not — verify, do not assume
A unit reporting "0 axioms" can still carry a `lemma`. In Frama-C a `lemma` **generates a goal**, so if
the run is green the lemma is *discharged* and is a sound helper. An `axiom` generates nothing and is a
smuggled assumption. Do not infer which one you have from the "0 axioms" grep — confirm the lemma is a
real PO: `-wp-prop=<lemma_name>` must report `Proved goals: 1 / 1` (cycle-276 `band_mask24_range`).

## Two-pass deletion sweep — re-sweep the SURVIVORS after pruning
Pass 1 finds inert clauses. Dropping them can make a *previously* load-bearing clause inert (its goal may
now be carried by something else, or gone with a dropped invariant). Cycle-276 dropped 9 clauses in pass 1,
then **re-swept all 16 survivors against the pruned baseline** to confirm each still flips a goal. Without
pass 2 the "load-bearing" labels describe the OLD contract, not the shipped one. Contract went 61 goals →
49: a smaller theorem assuming strictly less.

## `printf` EATS ACSL BACKSLASH ESCAPES when appending ledger rows (2026-07-20, cycle-277 audit)
Appending a `verdicts.tsv` row with `printf '…\t…\n'` makes printf interpret **every** backslash escape
in the *description text*, not just the ones you intended:
- `\null`   → newline + `ull`      → **the row is SPLIT into two lines**
- `\result` → carriage return + `esult` → row split
- `\valid_read` → vertical tab + `alid_read` → character eaten
- `\false`, `\forall`, `\nothing`, `\old` are all similarly exposed (`\f`, `\v`, `\n`, `\b`…)

Measured damage in this campaign's ledger: **53** occurrences of `valid_read` with the backslash eaten,
and **8 orphan row-fragments** (lines 435-443) where a row was split mid-description.

**Counts survived** — the generator keys on the STATUS column, and a split leaves the original row's
`col1`/`col2` intact while the remainder becomes an uncounted junk line (audited: 0 junk fragments
counted, all 293 counted keys well-formed). But **the descriptions are the evidence trail**, so a split
row has a truncated justification — that is auditability damage, not cosmetics.

**RULE:** never put ACSL text through `printf`'s format string. Use either
`printf '%s\n' "$row"` (escapes not interpreted in the *argument*) or a quoted heredoc
(`cat >> file <<'EOF'`). Writing `\\valid_read` also works and is what the later cycles did — which is
why cycles 273-277 rows are clean — but `%s`/heredoc is the robust default because it cannot be
forgotten per-escape.

**Do NOT retro-rewrite a large ledger to fix this mid-campaign**: the counts are provably unaffected,
and rewriting hundreds of committed rows risks worse damage than the truncated prose. Record the
affected region so a later reader knows those descriptions are degraded.

## `-f` SELF-MATCH: it is not a `pkill` bug, it is a `-f` bug (2026-07-20, widened after a recurrence)
Originally banked as "`pkill -f` killed my own shell". It has now recurred in a *different* tool and a
*different* role: a verifier's wait-loop used `pgrep -f 'sweep.py'`, which matched **the waiter's own
command line**, so the waiter saw itself as the job it was waiting for and deadlocked. Cost: wall-clock
on a long sweep, no corrupted measurement.

**The general rule:** `-f` matches the FULL COMMAND LINE of every process, *including the shell that is
running your `pgrep`/`pkill`*. Any wrapper whose argv contains the pattern is a match.
- To wait on / kill a real binary: `pgrep -x <name>` / `pkill -x <name>` — a process *name* cannot match
  the wrapper.
- If you must use `-f`, exclude self: `pgrep -f pat | grep -v "^$$\$"`, or match on a marker file
  (`touch DONE.marker`) instead of on process presence.
- Waiting on a **marker file** is strictly more robust than waiting on process absence, because it also
  distinguishes "finished" from "died".

This has now bitten both the coordinator and a verifier independently — treat `-f` as the hazard, not
the particular command.

## A mutation can leave Plane W fully green while breaking Plane H
Cycle-277's mutant deleted the fail-closed guard: `result_domain` (the Plane-W bound) still proved **1/1**
in the mutant, while the Plane-H property flipped. A bare `-wp-rte` run would have shown **nothing wrong**.
Concrete evidence for why the two planes are tracked separately and why an RTE-only pass is not a
substitute for an authorization postcondition.

## A `\false` probe inserted into a NO-BODY STUB is trivially discharged (2026-07-20, cycle-278)
The vacuity probe was scripted with `sed`, which inserted `//@ ensures \false;` into **both** the unit's
contract and the contract of a **no-body callee stub**. In a stub, `\false` is **assumed**, not proved —
so it trivially discharges the caller and the probe came back **1/1 (proved)**, which looks exactly like
a healthy result. Re-run against the wrapper contract alone: **0/1**, correct.

**RULE:** on any unit carrying contract-only stubs, insert the `\false` probe into the **target
function's contract only**, and confirm the probe count matches the number of exit paths you intended.
A contaminated probe on a stub-bearing unit is indistinguishable from a passing one by its number alone.

## "The attack did not flip" is a RESULT — report it, do not tune until something moves
Cycle-278's wrapper mutated the literal `0` in `aa_dfa_next(dfa, start, 0)` to `1`: **21/21, no flip.**
The correct conclusion is not "pick a better mutation" — it is that **the contract never pinned the
character**, because the callee's proven contract exports no `ensures` about it. The unit proves less
than its name suggests, and that is the finding.

Tuning a mutation until a goal flips converts non-vacuity from evidence into theatre: you end up
demonstrating that *some* mutation is caught, not that the property you claim is the property you
proved. Keep the non-flipping attack in the record alongside any later one that does flip.

## `-wp-prop=<lemma>` can report 0/1 for a lemma that IS proved
`band_mask24_range` discharges **1/1** under the unit's `-wp-auto` tactic set, but a bare
`-wp-prop=band_mask24_range` (tactics omitted) reports **0/1**. A reviewer spot-checking the lemma
without replicating the full option set will wrongly conclude it is unproved — and the natural
"fix" (adding it as an `axiom`) would silently smuggle it into the TCB. **Always re-check a lemma with
the unit's complete option set**, and record that set next to the claim.

## Smoke `dead_code`/`dead_loop` probes catch an over-strong precond that kills a branch (2026-07-20, cycle-279)
`aa_dfa_match_until` has an `if (EC-table) {...} else {...}` split. An unconditional
`requires valid_equiv: \valid(EQUIV_TABLE(dfa)+(0..255))` silently forces `tables[YYTD_ID_EC] != NULL`,
which makes the **else (non-EC) branch dead** — the unit then proves a green N/N that never exercises
half the function. `-wp-smoke-tests` flagged it via its `dead_code`/`dead_loop` checks. Fix: guard the
precond (`tables[YYTD_ID_EC] != NULL ==> \valid(...)`).

Lesson: an over-strong `requires` is a vacuity vector even without a stub — it can prune a real branch.
Smoke tests catch this; the plain `\false`-at-exit probe does NOT (both live exits still look reachable
because the *surviving* branch reaches them). Run smoke on any unit with an input-conditional branch.

## Guard-outside-loop lens (FI-5) — record the NEGATIVE result positively
When a target in a family where a sibling had a find (here match.c after FI-5) comes back clean, state
*why the mechanism is absent*, not just "no finding": (a) is there subtraction in the index arith that
could underflow? (b) is any per-step guard hoisted outside the walk? (c) is the looping macro even used?
Cycle-279: no subtraction, the one hoisted guard is a semantic short-circuit not a bound, and
`match_char` isn't used at all. "Lens applied, mechanism absent because X/Y/Z" is a stronger ledger
statement than silence and stops a later reader re-chasing it.

## FI-audit of a caller-enforced envelope: enumerate ALL call sites, including variable-arg ones (2026-07-20, cycle-280)
`ima_write_template_field_data`'s `string_no_wrap` precond (`datalen < U32_MAX` on the STRING path) is
sound only if enforced by every reachable caller — else it is a smuggled precond masking a `kzalloc(0)` +
`memcpy(…,U32_MAX)` heap overflow. The verifier cited the one literal `DATA_FMT_STRING` call site and
declared it bounded. **That enumeration was incomplete:** one caller passed the format as a *variable*
`fmt`, not a literal, so a grep for `DATA_FMT_STRING` misses it. Resolving `fmt` (only ever the three
DIGEST formats there) closed the hole.

**RULE for any caller-enforced (FI-discipline) bound:** grep every call site, and for each one whose
selector/length is a *variable* rather than a literal, trace the variable to its assignments. A
literal-only grep under-counts the callers and can wave through the exact path that breaks the envelope.

## kzalloc/memcpy assigns-frame timeout — the standard sound carve
Writing into a freshly `kzalloc`'d block, WP's `assigns`-frame partitioning over the symbolic-allocator
region times out (here 2 goals). The campaign-standard sound carve: drop the top-level
`assigns <published fields>` clause — all writes are into fresh allocator memory, so the drop is sound and
every security `ensures` + RTE goal still proves independently. Precedent: `ima_validate_hash_algo`.
Record the carve explicitly; it is a scope narrowing, not a hidden weakening.

## `-variadic-no-translation` is REQUIRED to WP any function that calls sprintf/snprintf (2026-07-20, cycle-281)
Frama-C's default variadic plugin translates a `sprintf("%s:%s:", ...)` call into a synthesized `assigns`
over an *infinite* range, which WP rejects as a **User Error** — the analysis fails to run at all, not
just fails a goal. Pass **`-variadic-no-translation`** so the variadic call is left opaque and governed by
its ACSL stub contract instead. Consequence: the sprintf **result-length bound** (`\result <= N`) becomes
a **disclosed TCB assumption** (a faithful over-approximation of "the format + bounded arg tables produce
≤ N chars"), not something WP derives. Record it as a TCB leaf. This is the standard, sound treatment for
kernel code that formats into a stack buffer.

## Tight-fit stack-buffer bound: verify the SIZE arithmetic AND every caller before calling it an envelope
`ima_eventdigest_init_common` writes `offset+digestsize` into `buffer[201]` where 201 == (max prefix 137)
+ (max digest 64) — a deliberate exact fit. Whether this is a **faithful envelope** or a **stack-overflow
finding** turns entirely on two facts a monitor must re-derive in pristine, because getting either wrong
flips the verdict:
1. the buffer SIZE expression (every macro: `DIGEST_TYPE_NAME_LEN_MAX`, `CRYPTO_MAX_ALG_NAME`,
   `HASH_MAX_DIGESTSIZE`) — transcribe verbatim, do not trust a paraphrase;
2. that the length bound (`digestsize <= 64`) is enforced on **every** caller path — trace each
   `cur_digestsize` to its source. Here all paths source a *registered crypto shash* digest (≤64 by
   `HASH_MAX_DIGESTSIZE` at algo registration) — a genuine cross-subsystem invariant, so envelope not
   finding. **The honest tell it's a "defensive-only" note, not a hard guarantee:** the storage field is a
   `u8` (≤255 by type) with no in-function guard, so the bound is the crypto invariant, not the C type — a
   future non-crypto caller reintroduces the overflow. Record that sharp edge; do not smooth it into
   "proven safe."

## A memory model can silently VACUATE a proof — always smoke + `\false`-probe under the SHIPPED model (2026-07-20, cycle-285)
`ebitmap_read` calls `next_entry()` (a stub) whose `dest_writable` precond is a **char-range validity**
`\valid((char*)buf+(0..n-1))` over TYPED stack buffers (`__le32 buf[3]`, `__le64`). Under **`-wp-model +cast`**
that stub's char-range `assigns` produces an **inconsistent post-frame**, and WP then proves **`\false`** —
the whole contract is vacuous, yet the plain goal count looks healthy. Measured, cache-off:
- `+cast`: direct `ensures \false` **PROVED 1/1**; `-wp-smoke-tests` **6/33** (27 dead_code/dead_loop probes prove).
- `Bytes`: `\false` **UNPROVABLE (0/1 Timeout)**; smoke **33/33**. Bytes is byte-addressable, so it discharges
  the char-range validity soundly. Plain Typed just times out (115/126).

**RULES:**
1. **The shipped model is the one under which smoke passes.** If `-wp-smoke-tests` fails (dead_code/dead_loop
   "Doomed") under a model, that model is **UNSOUND for the unit** — do not ship its count, however green.
2. **Run a direct `ensures \false` probe under the shipped model, cache-off.** It MUST be unprovable. A green
   `NN/NN` proves nothing if `\false` is provable.
3. A unit that only closes under one model must **name that model in the description and pin it** — record the
   status as a bare `NN/NN` (the generator's count regex is anchored `^NN/NN$`; a `124/124 (Bytes)` suffix is
   NOT counted) and put the model note in the prose.
4. **This is NOT the same as a stale-cache masking a goal.** (An earlier same-session hypothesis blamed cache;
   the real cause was model unsoundness. Char-range-assigns-over-typed-buffers ⇒ suspect the model, not the cache.)

## Ledger status column must be a BARE `NN/NN` — annotations go in the description
The report generator counts a WITNESSED unit only when col2 matches `^(WITNESSED|[0-9]+/[0-9]+)$` exactly.
A well-meaning `124/124 (Bytes)` in the status column is silently **not counted** (coverage under-reports).
Put every qualifier — model, caveat, conditionality — in col3; keep col2 a bare count.

## valid_read_string / \valid_read cannot be framed across a write (memset) to a SEPARATED typed object (cycle-286)
`tomoyo_parse_number_union` does `memset(ptr,0,sizeof(*ptr))` then reads `param->data[0]` and calls
`tomoyo_read_token(param)` (requires `valid_read_string(param->data)`). WP cannot carry the string
predicate `valid_read_string(param->data)` — nor even single-byte `\valid_read(param->data)` — across
the memset write to `*ptr`, because it does not assume the two pointer arguments are separated. The
obvious fix is INERT: `\separated(ptr, param->data)` (single-byte), `\separated(ptr, param->data+(0..N))`,
and `\base_addr(ptr)!=\base_addr(param->data)` all leave the count unchanged (69/71). Root: WP's frame
rule for the unbounded `valid_read_string` footprint across a write is not triggered by point/base
separation. Recurring **class-A-candidate** (a valid_read_string-frame ceiling), NOT a missing simple
hypothesis. LOAD-BEARING check: an intermediate `//@ assert valid_read_string(p)` that times out is not
"bookkeeping" — deleting it just relocates the failure onto the downstream RTE read + callee `requires`
that depend on it. TRIAGE RULE: prefer leaves whose security goals do NOT need to thread a string
predicate past a memset/write, until a valid_read_string-across-write frame lemma is banked; such a unit
proves its control-flow-local security ensures but leaves a 2-goal string-frame residual.

## List-walk termination is a CLOSEABLE class-C (ghost-length loop variant), NOT a ceiling (cycle-294)
A `list_for_each_entry_rcu` / linked-list walk whose `terminates` goal times out is NOT a Frama-C ceiling
and NOT an "unfaithful to add a measure" exemption — it is closeable class-C rigor-completion. The proven,
faithful technique (used by witnessed units tomoyo_number_matches_group, apparmor_aa_label_next_confined,
smack_from_secid): declare an uninterpreted `logic integer <len>(T *p) reads \nothing;` measure (no axioms/
statements), have the walk-step stub's ensures STRICTLY DECREASE it and keep it `>= 0`
(`ensures \result==\null || (\valid_read(\result) && len(\result) >= 0); ensures len(\result) < len(p);`),
add `loop invariant p==\null || (\valid_read(p) && len(p) >= 0);` and `loop variant len(p);`. This is a
sound finite-list over-approximation (the "list is finite" fact as a declared stub-TCB), NOT a smuggled
axiom. SOUNDNESS CHECK: the `ensures \false;` probe must stay UNPROVABLE with the measure model in place
(an inconsistent measure would make \false provable). MONITOR RULE: if a verifier returns NN/NN-1 with the
sole residual = list-walk termination and calls it a ceiling, send it back — the precedents prove it closes.

## ACSL after a C label is NOT rejected -- the real constraint is one-//@-line-per-loop-clause (cycle-299 correction)
A prior diagnosis (in the selinux services_compute_xperms rows) claimed "Frama-C 32.1 rejects ANY ACSL
annotation placed directly after a C label (syntax error)". MEASURED FALSE: a `/*@ assert ... */` block and
a single-clause `//@` after a `label:`/fall-through `case` label BOTH parse fine. The REAL syntax constraint
that produces the error is unrelated to labels: **multiple loop clauses must be on ONE `//@` line** --
consecutive separate `//@ loop invariant` / `//@ loop assigns` lines error out; put them on a single
`//@ loop invariant ...; loop assigns ...; loop variant ...;` line (which is also the faithful form, since
units-faithfulness.py strips only `//@` lines). Do not cite an "ACSL-after-label tooling wall" to justify
contracting a callee -- if a callee is contracted rather than proven, cite the REAL reason (e.g. a
memory-model conflict, see next entry).

## Single-model conflict: memset(byte-fill) + word-granular write to the SAME buffer (cycle-299, update_xperms_extended_data)
`update_xperms_extended_data` (selinux services.c:955-972) does `memset(p,0xff,32)` (byte-fill) AND a
`p[i] |= from->p[i]` loop (word-granular OR) to the SAME `u32[8]` buffer. No SINGLE WP memory model
discharges both arms: the memset assigns reconciles with the u32[0..7] frame ONLY under `-wp-model bytes`
(Typed/+cast time out on it), but the exact-OR loop invariant is intractable under Bytes (u32 encode/decode
round-trip over bitwise-OR) while it closes easily under Typed/+cast. Best single-model = Bytes 34/36
(2 OR-arm value goals residual); loop-unroll/-ulevel made it worse. CLASS-A-CANDIDATE (WP memory-model
conflict). The sound response is to CONTRACT this callee (faithful assigns/ensures) at its call sites --
which the witnessed xperms siblings already do. TRIAGE RULE: a byte-fill + word-write to one buffer is a
model-conflict signal; contract-the-callee, don't grind for a single model.

## Faithfulness gate strips ONLY //@ lines -- in-body /*@ */ blocks FAIL it (cycle-304 monitor catch)
The official faithfulness oracle `units-faithfulness.py <manifest.tsv>` (and the onboard-linux.sh strip==pristine
gate) removes a body line ONLY if `line.lstrip().startswith('//@')` -- it does NOT strip `/*@ ... */` block
comments. So ANY in-body ACSL written as a `/*@ loop invariant ...; */` or `/*@ assert ...; */` BLOCK leaves the
stripped body DIVERGING from pristine => the checker reports `FAIL ... body DIVERGES`, even though the code is
"byte-identical after a naive multi-line strip". THREE units (match_mnt_flags, vec_cmp, tomoyo_file_matches_pattern)
were committed FAILING this gate because the monitor verified faithfulness with a hand-rolled perl `/*@..*/`-stripping
diff instead of the official checker. RULES: (1) MONITOR must run the OFFICIAL `units-faithfulness.py <manifest>` for
the faithfulness gate -- never a hand-rolled strip. (2) VERIFIER must write every in-body annotation (loop invariant/
assigns/variant, assert) as a SINGLE `//@` line (all clauses semicolon-separated on that one line -- consecutive
separate //@ loop lines can syntax-error, and multi-line /*@ */ blocks fail the strip gate). The function CONTRACT
before the definition may stay a /*@ */ block (it's outside the per-function body range the checker compares).

## Do NOT ship the false_probe:\false sentinel in the unit (cycle-323)
`ensures false_probe: \false;` is a TEMPORARY model-soundness PROBE: insert it, confirm it is UNPROVABLE
under the SHIPPED model (proving the model is non-vacuous), then REMOVE it before shipping. A verifier
that leaves it in the unit's contract makes the unit permanently N-1/N (the \false goal never proves), so
it is NOT a clean bare NN/NN witness and the coordinator must strip it. The soundness result is the same
either way (unprovable), but the ledger count and the "full closure" claim require the sentinel gone.
Also strip it from the _attack sibling (a clean mutant should flip only the load-bearing goal, not carry a
second unprovable sentinel goal). MONITOR: grep the unit + attack for `false_probe`/`ensures.*\false`
before recording; a shipped sentinel is a cleanup, not a witness at N-1/N.

## axiomatic-block-required-for-reads-clause-uninterpreted-logic (cycle-347)
An uninterpreted ACSL `logic` function that needs a `reads` clause (e.g. `logic boolean
tm_same_ip(struct ipaddr_union *a, struct ipaddr_union *b) reads *a,*b;` to model a
read-only struct-comparing callee's result) MUST be declared inside an `/*@ axiomatic X {
... } */` block — Frama-C 32.1 REJECTS the top-level `/*@ logic boolean f(...) reads ...; */`
form with a User Error. This axiomatic block is AXIOM-FREE and sound as long as it contains
ZERO `axiom`/`lemma` statements (only the uninterpreted `logic` declarations): it asserts
nothing about the functions, so `\result` stays unconstrained over the full domain — exactly
like a top-level uninterpreted logic decl. (Top-level DOES work WITHOUT a reads clause, e.g.
apparmor_vec_cmp's `logic integer pcmp(struct aa_profile*, struct aa_profile*);`.)
Monitor rule: an `axiomatic` block in a "0 axioms" unit is ONLY acceptable if `awk
'/axiomatic/,/}/' unit.c | grep -cE '^\s*(axiom|lemma) '` == 0; document it as axiom-free in
the ledger row. PREFER modeling a callee result with a plain `ensures \result==0||\result==1`
(no logic fn) when the load-bearing property doesn't need the biconditional — avoids the
block entirely.

## ghost-measure-through-stub creates assigns-frame residuals (cycle-365)
Closing a list-walk termination with a `g_rem` ghost measure requires the walk-step
stub (`__ime_next`) to `assigns g_rem` and `ensures 0<=g_rem<\old(g_rem)`. Naively adding
`assigns g_rem \from ...` to the stub AND `loop assigns ..., g_rem` can INTRODUCE new
`assigns_normal/exit_partNN` frame residuals (the g_rem write's `\from` frame times out),
a NET REGRESSION vs the single `terminates` residual. Observed cycle-365
(ima_appraise_signature: closing terminates traded 1 residual for 4 assigns-frame goals,
40/44 vs 36/37). The units that DID close list-walk termination cleanly (evm
evm_protected_xattr_common 59/59, avtab_search_node_next 68/68, safesetid _setid_policy_lookup
48/48) modeled the measure so the g_rem frame discharges — likely g_rem declared+assigned
locally within the loop or the stub `assigns` scoped to avoid the exit-frame goal. RULE:
when adding a ghost measure to close termination, re-run the FULL goal count (not just the
terminates goal) and confirm NO new assigns-frame residuals before claiming FULL closure; if
they appear, it needs a frame-aware measure design (or record the security surface as a
counted carve with the termination as a flagged closeable-class-C residual, per the
match_exception precedent — NOT a class-A ceiling).
