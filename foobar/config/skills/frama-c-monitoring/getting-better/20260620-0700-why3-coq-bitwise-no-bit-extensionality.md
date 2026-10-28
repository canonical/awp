# Why3 Coq bitwise prelude lacks bit-extensionality → value-from-bits facts unprovable

- **Trigger:** wolfSSL `asn.c::GetLength_ex` RTE smoke proof (frama-c-launch, 2026-06-20). The
  ASN.1/DER length decoder's correctness needs two bitwise reconstruction lemmas that are **true and
  entailed** yet discharge by neither SMT nor Coq under the matched `framac-coq8` toolchain.
- **Observed behaviour.** Two helper lemmas stay `Unknown`:
  - `or_low8_sum`: `0 <= x  &&  0 <= b <= 255  ==>  (x << 8) | b == x*256 + b`
  - `mask7f_high`: `0x80 <= b <= 255  ==>  (b & 0x7F) == b - 0x80`
  Both reduce to a **value-from-bits** fact (disjoint bits ⇒ `land == 0`; e.g. `land 128 127 == 0`,
  `land i (lsl i1 8) == 0` for `i < 256`, `lor 128 (land 127 i) == i`). In the Why3 Coq realization
  the prelude's `land`/`lor`/`lsl`/`bit_test` are **abstract `Parameter`s** (confirmed: `Print land`
  is abstract, not `Z.land`), and the axiom set (`land_extraction` / `lor_extraction` /
  `bit_test_extraction` / `lor_addition` / `land_0`) has **no bit-extensionality / value-from-bits
  axiom** — so these are *underivable* in Coq. SMT (Alt-Ergo + Z3, 60 s) also times out, **even on a
  concrete `uint8` operand** (symbolic `land`/`lor` are opaque). So the goals are *simultaneously*
  SMT-incomplete **and** beyond the prelude's Coq realization — the one combination the SMT→Coq
  escalation ladder cannot close.
- **Contrast (what DID close):** `shift8_mul` (`x<<8 == x*256`) and `mask7f_nonneg`
  (`0 <= b&0x7F <= 127`) **proved in Coq, 0 admits** (chains `lsl_1`/`lsl_add` and
  `is_uint8_land`/`is_to_uint8`). The gap is specifically **value-level reconstruction** of an integer
  from its byte/bit pieces, not bit *ranges*.
- **Desired behaviour / fixes (any one):**
  1. a WP low-level **`Bytes`** memory/arith model where `(x<<8)|b` for `b<256` is a definitional
     concatenation (the natural model for byte parsers);
  2. add a **bit-extensionality** (or `land`/`lor` value-reconstruction) axiom to the Why3 Coq driver
     `bv`/`int.Bitwise` realization, so concrete-width facts are derivable;
  3. a Frama-C/WP lemma kit for the recurring "`(hi<<8)|lo` reconstruction" and "`x & 0x7F` low-mask
     value" idioms.
- **`U` clause served.** RTE-robustness of ASN.1/DER and TLS byte parsers — the **top attack surface**
  (EBIOS OS1, G4×V3). These masks recur in *every* length/tag/integer decoder (mbedtls hit the same
  `& 0x7F` class), so the gap caps a whole unit family; closing it would turn several PARTIALs into
  PROVEDs without new spec work.
- **Honesty.** The residual was left genuinely `Unknown` (load-bearing for the 75 C-side goals),
  **not** axiomatized/`Admitted` — Gate B CLEAN, monitor-confirmed. The wolfSSL smoke unit is an honest
  PARTIAL (77/79) because of this tooling gap, not a spec defect or a wolfSSL bug.
