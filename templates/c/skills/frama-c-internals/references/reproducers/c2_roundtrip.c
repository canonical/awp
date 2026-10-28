/* Mechanism (2): CONTAINER_OF round-trip with \valid(c) in scope.
 * Typed 3/4 and +cast 3/4 — the member access (c2->payload) stays red.
 * Refutes "spec gap": container validity does NOT discharge it. */
#include <stddef.h>
struct node { int payload; int hook; };   /* hook at nonzero byte offset (4) */
/*@ requires \valid(c); assigns \nothing; */
int peek(struct node *c) {
    int *n = &c->hook;
    struct node *c2 = (struct node *)((char *)n - offsetof(struct node, hook));
    return c2->payload;
}
