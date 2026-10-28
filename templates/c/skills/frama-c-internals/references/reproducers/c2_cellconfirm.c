/* Decisive confirmation that WP's Typed model offsets are in CELLS, not bytes.
 *
 *   hook is field-index 1  =>  position_of_field(hook) = 1 CELL  (NOT offsetof = 4 bytes)
 *   &c->hook        shifts +1 cell
 *   (char*)n - K    shifts -K cells  (the byte literal K is consumed as K char-cells)
 *
 * So the round-trip offset = offset(c) + 1 - K.  It collapses to offset(c) IFF K == 1.
 *
 *   K = 4 (the real offsetof(hook), in bytes)  -> Prove: false   (offset off by 3)
 *   K = 1 (matches the 1-cell field shift)      -> proves 4/4     <-- this file
 *
 * Run: frama-c -wp -wp-model +cast -wp-prover alt-ergo,z3 c2_cellconfirm.c   => 4/4
 *      (change the -1 below to -4 to reproduce the Prove:false unit mismatch)
 */
#include <stddef.h>
struct node { int payload; int hook; };
/*@ requires \valid(c); assigns \nothing; */
int peek(struct node *c) {
    int *n = &c->hook;
    struct node *c2 = (struct node *)((char *)n - 1);  /* 1 CELL, matches field-shift +1 */
    /*@ assert rt_cell: c2 == c; */
    return c2->payload;
}
