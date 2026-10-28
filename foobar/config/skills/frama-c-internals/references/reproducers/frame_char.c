/* FRAME / cast-assigns-call SOUNDNESS probe (the wp-cast-frame-defect, reproduced as UNSOUNDNESS).
 *
 *   assert a_is_7 (FALSE post-state)  ->  Typed 1/1 PROVES, +cast 1/1 PROVES, bytes 0/1 rejects
 *   assert a_is_0 (TRUE  post-state)  ->  Typed 0/1, +cast 0/1, bytes 0/1   (shared incompleteness)
 *
 * Typed/+cast prove a==7 AFTER a's byte was zeroed: the `assigns *(char*)p` cast target is dropped
 * from the callee frame (cast errors -> hidden -> effectively `assigns \nothing` -> a unchanged ->
 * false post proves) = a SOUNDNESS hole, not mere incompleteness. bytes is SOUND (rejects a==7) and
 * only incomplete on the true post (safe-side: never claims what it can't justify).
 *
 * Run: frama-c -wp -wp-model bytes -wp-prop a_is_7 -wp-prover alt-ergo,z3 frame_char.c   => 0/1 (sound)
 *      frama-c -wp             -wp-prop a_is_7 -wp-prover alt-ergo,z3 frame_char.c   => 1/1 (UNSOUND)
 */
/*@ requires \valid((char*)p);
    assigns *(char*)p;
    ensures *(char*)p == 0; */
void zero_byte(void *p);

/* little-endian: a=7 is [07 00 00 00]; zero first byte -> [00 00 00 00] = 0.
   TRUE post-state: a==0.   FALSE: a==7. */
int t_true(void){ int a=7; zero_byte(&a); /*@ assert a_is_0: a==0; */ return a; }
int t_false(void){ int a=7; zero_byte(&a); /*@ assert a_is_7: a==7; */ return a; }
