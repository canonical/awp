# WP Typed/+cast model: allocation & `\fresh` not implemented

**Trigger** — `mbedtls_x509_get_name` (mbedtls 4.1.0, `library/x509.c`), and any unit that builds
a freshly-`mbedtls_calloc`'d linked list. mbedtls run, report §9. Confirmed against `L` (the WP
oracle): the function reaches **95/134**, with the 39 unproved goals all on the allocated chain.

**Observed** — WP's Typed (and `+cast`) memory model prints
`Allocation, initialization and danglingness not yet implemented` and silently **drops** the
`\fresh`/allocation value content of a callee contract. Concretely:
- `mbedtls_calloc`'s `ensures \fresh{Old,Here}(\result, …)` is dropped at *translation time*,
  before any prover backend runs.
- An `allocates \result; ensures \valid((char*)\result+(0..n-1))` contract *does* let WP prove
  `\valid` of the result — so every **RTE / mem-access** goal on `cur->next`, `cur->next_merged`,
  etc. passes (the function is genuinely RTE-robust).
- But **no expressible contract recovers SEPARATION** of the freshly-allocated block from
  pre-existing objects: `\fresh` is dropped, an `allocates`-only result is not separated, and a
  `\forall q; \valid_read{Old}(q) ==> \base_addr(q)!=\base_addr(\result)` postcondition is not
  instantiated for the cells that need it.
- Consequence: the function's own `assigns` / `loop assigns` / chain-separation / `terminates`
  goals over the allocated list (the 39 residuals) are **unprovable — by SMT *or* Coq**, because
  the needed hypothesis never reaches a prover. This is *model-incompleteness*, not
  non-entailment (no counter-model exists — the nodes really are fresh and separated) and not a
  missing invariant.

**Desired** — a WP memory model that implements allocation / `\fresh` semantics (fresh blocks
provably separated from pre-existing objects and from each other), so that `assigns` and
separation footprint goals over dynamically-allocated linked structures are dischargeable; or,
failing that, a documented *sound* idiom to assume fresh-block separation at a call site (so it
need not be smuggled via an `axiom`).

**Minimal example**
```c
struct node { struct node *next; int v; };
/*@ requires \valid(head);
    assigns *head, { n->next | struct node *n ; \valid(n) };  // footprint over a fresh chain
*/
void build(struct node **head, int k) {
  struct node *cur = *head;
  /*@ loop assigns cur, cur->next, *head; */
  while (k-- > 0) {
    cur->next = mbedtls_calloc(1, sizeof *cur->next);  // \fresh dropped -> separation unprovable
    if (!cur->next) return;
    cur = cur->next;
  }
}
```
WP proves `\valid(cur->next)` (so the `cur->next->v = …` access is safe) but cannot prove the
`loop assigns` footprint, because it cannot establish that each new node is separated from the
existing chain.

**Guidance link** — serves the mission `U` "prove RTE-robustness / functional spec of the
untrusted-input X.509 parsers": this gap caps **every allocation-heavy parser** —
`x509_get_name` now, and the structural parsers (`x509_crt_parse_der_core`, CRL/CSR) next, which
build the same kind of `calloc`'d lists. RTE-safety is provable; the spec footprint is not. See
also memory `[[wp-cast-frame-defect]]` for the related `+cast` call-frame variant.
