/* Mechanism (2), isolated. assert rt: c2 == c makes everything else green (4/5):
 * the round-trip identity is the SOLE missing fact. Literal offset (4) rules out
 * offsetof-folding. Typed: rt goal = `a1 = a` with a1 fresh (cast hidden).
 * +cast: rt goal reduces to `Prove: false` (mis-computed offset).
 *   frama-c -wp -wp-prop rt -wp-print c2_literal.c
 *   frama-c -wp -wp-model +cast -wp-prop rt -wp-print c2_literal.c */
#include <stddef.h>
struct node { int payload; int hook; };
/*@ requires \valid(c); assigns \nothing; */
int peek(struct node *c) {
    int *n = &c->hook;
    struct node *c2 = (struct node *)((char *)n - 4);
    /*@ assert rt: c2 == c; */
    return c2->payload;
}
