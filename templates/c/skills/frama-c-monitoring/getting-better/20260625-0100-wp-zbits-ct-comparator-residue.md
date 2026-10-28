# WP land/CT-comparator goals need Zbits bit-extensionality wired into generated goals

- **Trigger (unit/gap):** BearSSL-analyze cycle 2, SA8 `pem_from_base64` (case 22 of
  `src/codec/pemdec.c`) — the constant-time base64 char→value primitive (found-issues F2).
- **Observed behaviour:** WP leaves three functional-spec facts Unknown/Timeout even after
  the full probe ladder (Typed RTE-only, `-inline-calls EQ,GT,NOT`, `-wp-model bytes`,
  `-wp-split`, Z3 150s, Alt-Ergo 60s, domain-restricting `requires`):
    1. `land_allones: (a & 0xFFFFFFFF) == a`  (mask against the all-ones word)
    2. `EQ(x,y) == (x==y)`  from the CT idiom `NOT((q|-q)>>31)`, q=x^y
    3. `GT(x,y) == (x>y)`  from the CT idiom `(z^((x^y)&(x^z)))>>31`, z=y-x
  Each survives the refutation probe (quantifies over the full uint32_t domain — no missing
  antecedent: even `a<=100 ==> a&0xFFFFFFFF==a` times out), so it is a genuine prover-side
  residue, not a spec gap.
- **Desired behaviour:** the generated Why3/SMT goals for `land`/`lor`/`lxor`/`lsr` against
  constant masks should carry (or be able to invoke) WP's realized `Zbits` bit-extensionality
  theory, so masking and the `(q|-q)>>31` / `(z^...)>>31` sign-extraction idioms close
  without a hand-authored Coq script. Today the inlined Why3-driver bitvector axioms lack the
  extensionality lemma the SMT solvers need to bit-blast a 32-bit mask cheaply.
- **Minimal example:** `lemma m: \forall integer a; 0 <= a < 0x100000000 ==> (a & 0xFFFFFFFF) == a;`
  under `-wp -wp-prover alt-ergo,z3 -wp-timeout 60` → Timeout. (The CT comparator idioms are
  the same shape over `(q|-q)>>31`.)
- **U clause served:** "specify thoroughly" — the functional base64 map is in-scope soft-side
  completeness; the memory-safety/bounded-output floor is already PROVED (pem_write8 13/13),
  so this only blocks the *functional* tier, not Tier-1. Banked as Coq-attempted residue.
