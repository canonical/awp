# WP 32.1 `\valid_function` RTE goal is "not yet implemented" — indirect-call sites un-dischargeable

- **Trigger (unit/gap):** BearSSL-analyze cycle 3, SA1 `cbc_decrypt`
  (`src/ssl/ssl_rec_cbc.c`, the CBC record-decrypt buffer-bounds slice,
  `harness/cbc_decrypt_bounds.c`). The function makes an indirect call through a vtable
  function pointer: `cc->bc.vtable->run(&cc->bc.vtable, cc->iv, data, len)`.
- **Observed behaviour:** with `-wp-rte`, WP emits an RTE obligation
  `rte: function_pointer: \valid_function((cc->bc.vtable)->run)` and then prints
  `\valid_function not yet implemented`; the goal `cbc_decrypt_assert_rte_function_pointer`
  is reported `[Timeout] ... (Degenerated)` under BOTH the Typed and the bytes model. It is
  the only memory-relevant RTE goal that does not close in *either* model. The call's
  *memory frame* is fully handled (resolved via a `//@ calls bc_run;` statement annotation
  whose stub `assigns data[0..len-1]`), so the OOB question around the call is proved — what
  is left un-modelled is solely the *pointer-validity-of-the-callee* predicate.
- **Desired behaviour:** WP should be able to discharge `\valid_function(fp)` when `fp` is a
  field initialized (or `requires`-assumed) to point at a function of the matching type — at
  minimum honor a `requires \valid_function(cc->bc.vtable->run);` antecedent so the call-site
  RTE goal becomes a propagated precondition instead of a degenerate timeout. (Refutation
  probe: adding `requires \valid_function(...)` does NOT flip it — the predicate is "not yet
  implemented" in WP 32.1, so it is a genuine tooling gap, not a missing antecedent.)
- **Minimal example:** any harness with `requires \valid(p); void (*fp)(void); ... fp();`
  under `-wp -wp-rte` emits `\valid_function not yet implemented` on the call.
- **U clause served:** the RS4 memory-safety floor ("no OOB on the decrypt path"). The
  buffer-bounds result is unaffected — every `buf[]`/`tmp1[]`/`tmp2[]` access is proved
  in-bounds via the bytes⟂Typed union; this gap only leaves the callee-pointer-validity RTE
  goal as an honest tooling residual, not a buffer bound. Banked as a WP-32.1 limitation.
