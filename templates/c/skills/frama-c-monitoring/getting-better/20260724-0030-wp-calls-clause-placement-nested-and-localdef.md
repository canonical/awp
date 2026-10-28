# WP 32.1 `//@ calls` does not ATTACH to an indirect call nested in an expression or in a local-def initializer

- **Trigger (unit/gap):** linux-7.1.3 LSM campaign cycle-443, SELinux `hashtab_search`
  (`security/selinux/ss/hashtab.h:97-118`), the policy-lookup primitive. Its body dispatches
  through two `struct hashtab_key_params` function pointers at positions where a `//@ calls`
  statement annotation cannot bind:
  - **nested in an expression:** `hvalue = key_params.hash(key) & (h->size - 1);` (the call is a
    sub-expression under `& (h->size-1)`, not the whole RHS)
  - **local-def initializer:** `int cmp = key_params.cmp(key, cur->key);` (call is the initializer
    of a local definition)
- **Observed behaviour:** a `//@ calls the_hash;` / `//@ calls the_cmp;` placed on such a statement is
  **silently ignored**. WP warns `no 'calls' specification for statement(s) on line(s): line N` and
  `Missing 'calls' for default behavior`, then conservatively assumes the pointer may call the
  **enclosing** function → havoc/decreases-less recursive-self-call treatment. The entire downstream
  region degenerates (in `hashtab_search`: the load-bearing slot-index bound + the whole chain-walk
  memory-safety — 13 goals, faithful in-place proof stuck at 20/33). The local-definition facet also
  errors outright: `Statement contract and ACSL pragmas over a local definition are not implemented.`
- **Minimal reproducer:**
  ```c
  typedef unsigned int u32;
  /*@ assigns \nothing; */ u32 the_hash(const void *k);
  struct kp { u32 (*hash)(const void *); };
  /*@ requires kp.hash == &the_hash; assigns \nothing; */
  u32 f(const void *key, struct kp kp) {
  	u32 v;
  	//@ calls the_hash;
  	v = kp.hash(key) & 7u;   /* nested -> calls IGNORED, \valid_function degenerates */
  	return v;
  }
  ```
  `frama-c -wp -wp-rte -machdep gcc_x86_64 -wp-prover alt-ergo,z3` → the `no 'calls' specification`
  warning and a Degenerated `\valid_function` RTE goal.
- **Discriminator (this is the PLACEMENT, not `calls` itself, and not `\valid_function`).** `//@ calls`
  DOES attach to a plain whole-RHS assignment statement (`v = kp.hash(key);` then `v = v & 7u;`) — but
  splitting the call out of the expression / local-def **edits the C body**, breaking the
  `strip(//@) == pristine` faithfulness gate, so it is forbidden in an in-place proof. The separate
  `\valid_function`-RTE-unimplemented gap (see `20260625-1100-wp-valid-function-not-implemented.md`)
  is what remains even *after* `calls` attaches; this note is about `calls` failing to attach at all.
- **Desired behaviour:** honor `//@ calls` on any statement that contains exactly one indirect call
  (nested sub-expression or local-def initializer), binding the resolution the same way it does on a
  whole-RHS assignment — OR let a `requires fp == &f` antecedent devirtualize the call without a
  `calls` clause. (Refutation probe: `-wp-dynamic` is OBSOLETE ("@calls annotations are now handled
  directly in the kernel") and does not help; the pointer-pin precond alone does not devirtualize.)
- **Classification / actionable rule.** Genuine `U`-ceiling on the *in-place* faithful proof — a
  frontend/feature placement gap, not prover weakness, not spec smuggling. The property is TRUE and
  machine-provable on a framing-clean twin. **Verifier heuristic: a function that dispatches through a
  function pointer positioned as an expression sub-term or a local-def initializer is status-3-BLOCKED
  for a faithful in-place WP proof — prefer other targets for clean witnesses, and when one must be
  driven, record the block as status-3 (do NOT count it as WITNESSED) rather than editing the body.**
  Companion campaign note: `getting-better/20260723-2330-acsl-calls-nested-in-expression.md`.
