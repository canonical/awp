/* Mechanism (1): pointer-sized store through a non-fitting char* cast.
 * Typed (default): 2/4 (cast errors -> store target hidden -> assigns+valid red).
 * +cast: 4/4 (sound for THIS no-call case; the +cast unsoundness is the frame drop
 *   across an `assigns *(cast)ptr` CALL — reconstruct that to see wp-cast-frame-defect).
 *   frama-c -wp -wp-rte -wp-prover alt-ergo,z3 castmin.c
 *   frama-c -wp -wp-rte -wp-model +cast -wp-prover alt-ergo,z3 castmin.c
 */
#include <stddef.h>
/*@ requires \valid((char*)p + (0 .. n - 1));
    requires n >= sizeof(char*);
    assigns *((char**)p); */
void store_ptr(void *p, size_t n, char *val) { *(char **)p = val; }
