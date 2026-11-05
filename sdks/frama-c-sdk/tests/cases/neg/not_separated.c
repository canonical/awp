/* NEGATIVE: without \separated(p, q), writing *p may change *q.
   Expected: the goal typed_incr_first_ensures_q_unchanged is NOT proved. */
#include <limits.h>
/*@ requires \valid(p) && \valid_read(q);
    requires *p < INT_MAX;
    assigns *p;
    ensures q_unchanged: *q == \old(*q);
*/
void incr_first(int *p, const int *q) { *p = *p + 1; }
