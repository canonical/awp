# Monitor catch: verifier over-claims class-A "NEW Frama-C bug" on a store-bloat RTE

**Cycle-218** (`services_compute_xperms_drivers`, selinux ss). The verifier proposed 2 `rte_index_bound`
goals (`drivers.p[driver>>5]`, `driver` a `u8`) as a **NEW class-A Frama-C hypothesis-threading bug**
(WP not reusing a co-located proved `//@ assert` for the auto-RTE subgoal), with a minimal repro.

**The monitor refutation (decisive, cheap):** a **proving twin** exists. The shift-bound lemma
`\forall x; 0<=x<=255 ==> 0<=(x>>5)<=7` PROVES standalone (Qed valid), and in a **clean minimal frame**
(a direct-`u8` param, no heap load) the identical array-write index bound **discharges** with that lemma
present. Per `no-ceiling.md`, **a proving twin ⇒ CLASS-C, never class-A/status-3.** The real-unit failure
is the same lemma failing to **instantiate** into a store-heavy goal whose index is a heap-load behind 3
pointer derefs inside a loop = **store-bloat** (proves-in-isolation ∧ times-out-in-context ⇒ class-C).

**Levers that do NOT rescue it (so the class-A-vs-C call is unambiguous — all confirm store-bloat, not a wall):**
- minimal-frame helper (index as `requires idx<=7` param): caller obligation still times out;
- antecedent-range assert on the exact heap term (`0 <= driver <= 255`): the assert PROVES but the RTE
  still times out — the `\forall` still won't trigger;
- `-wp-timeout 180 -wp-steps 200000`: `Stepout`, not closed;
- `-wp-model Bytes`: strictly WORSE (more goals time out).
The sanctioned closer for store-bloat is **WP→Coq** (frame/`assumption` tactics beat store-bloat), NOT an
ACSL lever and NOT a fileable frontend defect.

**Why:** the loop's dominant coherent-and-wrong is relabeling unfinished (class-C) work as an exemption
(class-A tool ceiling / status-3 Frama-C bug). A `u8`→`(x>>5)∈[0,7]` bound is elementary; a "NEW Frama-C
bug" on it should trigger immediate skepticism. The **proving-twin probe** (does the same goal discharge
in a clean frame?) is the fast, decisive class-A-vs-C discriminator — cheaper than the full
`no_ceiling_gate.py` bundle and it settles it.

**How to apply:** when a verifier claims class-A/status-3 on an RTE bound over a bitshift/mask of a
range-bounded value, FIRST build the proving twin (same predicate + lemma, minimal frame). If it proves,
the claim is REFUTED → record **CLASS-C** (not witnessed, not class-A), name the store-bloat closer
(WP→Coq), and — per value-order — you may DEFER the Coq close when fresh finding-bearing security leaves
outrank Coq-closing a doubly-witnessed RTE-noise bound (log that judgement). Distinguish the two RTE
sub-kinds: a `1<<31` signed-overflow in a verbatim kernel macro is **kernel-semantics-benign** (discharges
under `-no-warn-signed-overflow`, since the kernel builds `-fno-strict-overflow`), a separate disposition
from the store-bloat index bound. See [[dedup-prose-false-positive]] for the sibling ledger-hygiene catch.
